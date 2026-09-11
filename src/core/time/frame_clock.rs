use std::time::{Duration, Instant};

/// Adaptive frame clock for scheduling render frames.
///
/// This clock tracks the monitor's VBlank interval and predicts when the next
/// VBlank will occur. It is used to schedule the start of the render loop
/// just in time to complete compositing before the deadline, minimizing input latency.
#[derive(Debug, Clone)]
pub struct FrameClock {
    /// Timestamp of the last known VBlank
    last_vblank: Instant,

    /// Current estimated refresh interval
    refresh_interval: Duration,

    /// History of refresh intervals for smoothing (moving average)
    interval_history: Vec<Duration>,

    /// Accumulated phase error to correct drift
    phase_error: Duration,
}

impl FrameClock {
    /// Create a new frame clock with a default interval.
    pub fn new(target_interval: Duration) -> Self {
        Self {
            last_vblank: Instant::now(),
            refresh_interval: target_interval,
            interval_history: Vec::with_capacity(10),
            phase_error: Duration::ZERO,
        }
    }

    /// Update the clock with feedback from the presentation extension.
    ///
    /// The `timestamp` is the time the frame was actually presented (VBlank time).
    /// `refresh` is the refresh rate in mHz (milli-Hertz) reported by the output.
    pub fn update_vblank(&mut self, timestamp: Instant, refresh_mhz: u32) {
        // Update refresh interval if provided and non-zero
        if refresh_mhz > 0 {
            let micros = 1_000_000_000 / refresh_mhz as u64;
            let new_interval = Duration::from_micros(micros);

            // Allow some jitter, but update if plausible
            if new_interval.as_millis() >= 4 && new_interval.as_millis() <= 50 {
                self.refresh_interval = new_interval;

                // Keep history (for future smoothing implementation)
                if self.interval_history.len() >= 10 {
                    self.interval_history.remove(0);
                }
                self.interval_history.push(new_interval);
            }
        }

        // Phase correction
        // If we predicted VBlank at T, but it happened at T + delta, we're drifting.
        // We use the reported timestamp as the new anchor.
        if timestamp > self.last_vblank {
            // Calculate phase error for debug/metrics
            let predicted = self.next_vblank();
            if timestamp > predicted {
                self.phase_error = timestamp - predicted;
            } else {
                self.phase_error = predicted - timestamp;
            }

            self.last_vblank = timestamp;
        }
    }

    /// Predict the time of the next VBlank.
    pub fn next_vblank(&self) -> Instant {
        let now = Instant::now();

        if now < self.last_vblank {
            // Clock skew or very recent vblank
            return self.last_vblank + self.refresh_interval;
        }

        // Calculate how many intervals have passed since the last anchor
        let elapsed = now.duration_since(self.last_vblank);
        let intervals = (elapsed.as_nanos() / self.refresh_interval.as_nanos()) as u32;

        // Next vblank is (intervals + 1) * refresh_interval from anchor
        self.last_vblank + self.refresh_interval * (intervals + 1)
    }

    /// Calculate the ideal time to start rendering.
    ///
    /// `estimated_render_time` is how long the compositor expects to take to draw.
    /// Returns the `Instant` when the render loop should wake up.
    pub fn plan_render(&self, estimated_render_time: Duration) -> Instant {
        let target_vblank = self.next_vblank();

        // Safety margin: 2ms to account for scheduling jitter/overhead
        let safety_margin = Duration::from_millis(2);
        let total_margin = estimated_render_time + safety_margin;

        if total_margin >= self.refresh_interval {
            // If render time > refresh interval, we must start immediately (or skip frame)
            return Instant::now();
        }

        target_vblank
            .checked_sub(total_margin)
            .unwrap_or_else(Instant::now)
    }

    /// Get the estimated refresh interval
    pub fn refresh_interval(&self) -> Duration {
        self.refresh_interval
    }

    /// Get the current phase error (drift) from the last update
    pub fn phase_error(&self) -> Duration {
        self.phase_error
    }

    /// Calculate average interval from history
    pub fn average_interval(&self) -> Option<Duration> {
        if self.interval_history.is_empty() {
            None
        } else {
            let sum: Duration = self.interval_history.iter().sum();
            Some(sum / self.interval_history.len() as u32)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_predict_next_vblank() {
        let clock = FrameClock::new(Duration::from_millis(16));
        let start = clock.last_vblank;

        // Next vblank should be start + 16ms
        let next = clock.next_vblank();
        assert!(next > start);
        assert!(next <= start + Duration::from_millis(17));
    }

    #[test]
    fn test_plan_render() {
        let clock = FrameClock::new(Duration::from_millis(16));

        // Planning for 4ms render
        // Should start at next_vblank - 4ms - 2ms (safety) = next_vblank - 6ms
        let plan = clock.plan_render(Duration::from_millis(4));
        let next = clock.next_vblank();

        // plan + 6ms should be roughly next
        let diff = next.duration_since(plan);
        assert!(diff >= Duration::from_millis(6));
        assert!(diff <= Duration::from_millis(7));
    }

    #[test]
    fn test_phase_correction() {
        let mut clock = FrameClock::new(Duration::from_millis(16));
        let original_vblank = clock.last_vblank;

        // Simulate a late VBlank (phase shift)
        let later = original_vblank + Duration::from_millis(5);
        clock.update_vblank(later, 60_000);

        assert_eq!(clock.last_vblank, later);

        // Next prediction should align with new phase
        let next = clock.next_vblank();
        let interval = next.duration_since(later);
        // Interval might be updated slightly by 60Hz refesh rate (16.66ms)
        assert!(interval.as_millis() >= 16);
    }
}

//! Runtime and event loop integration.
//!
//! This module provides the event loop infrastructure for the compositor.
//! It handles:
//! - Wayland event dispatching
//! - Frame timing and vsync coordination
//! - Task scheduling
//! - Platform event loop integration
//!
//! The runtime is designed to integrate with platform event loops:
//! - macOS: CVDisplayLink / NSRunLoop
//! - iOS: CADisplayLink / CFRunLoop
//! - Android: Choreographer / Looper

use std::collections::VecDeque;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use crate::core::compositor::{Compositor, CompositorEvent};
use crate::core::errors::CoreError;
use crate::core::state::CompositorState;

// ============================================================================
// Task System
// ============================================================================

/// A task to be executed by the runtime
pub type Task = Box<dyn FnOnce(&mut CompositorState) + Send>;

/// Task queue for deferred execution
#[derive(Default)]
pub struct TaskQueue {
    tasks: Mutex<VecDeque<Task>>,
}

impl TaskQueue {
    pub fn new() -> Self {
        Self {
            tasks: Mutex::new(VecDeque::new()),
        }
    }

    /// Queue a task for execution
    pub fn push(&self, task: Task) {
        self.tasks.lock().unwrap().push_back(task);
    }

    /// Take all pending tasks
    pub fn take_all(&self) -> Vec<Task> {
        let mut tasks = self.tasks.lock().unwrap();
        tasks.drain(..).collect()
    }

    /// Check if there are pending tasks
    pub fn has_tasks(&self) -> bool {
        !self.tasks.lock().unwrap().is_empty()
    }

    /// Get number of pending tasks
    pub fn len(&self) -> usize {
        self.tasks.lock().unwrap().len()
    }
}

// ============================================================================
// Frame Timing
// ============================================================================

/// Frame timing configuration
#[derive(Debug, Clone)]
pub struct FrameTimingConfig {
    /// Target frame interval (default: 16.67ms for 60Hz)
    pub target_interval: Duration,
    /// Maximum frame time before forcing a frame
    pub max_frame_time: Duration,
    /// Vsync enabled
    pub vsync: bool,
}

impl Default for FrameTimingConfig {
    fn default() -> Self {
        Self {
            target_interval: Duration::from_nanos(16_666_667), // 60Hz
            max_frame_time: Duration::from_millis(100),
            vsync: true,
        }
    }
}

impl FrameTimingConfig {
    /// Create config for a specific refresh rate
    pub fn for_refresh_rate(hz: u32) -> Self {
        Self {
            target_interval: Duration::from_nanos(1_000_000_000 / hz as u64),
            ..Default::default()
        }
    }
}

/// Frame timing state
pub struct FrameTiming {
    #[allow(dead_code)]
    config: FrameTimingConfig,
    clock: crate::core::time::FrameClock,
    frame_count: u64,
    frame_time_sum: Duration,
    fps_update_time: Instant,
    current_fps: f64,
}

impl FrameTiming {
    pub fn new(config: FrameTimingConfig) -> Self {
        let now = Instant::now();
        Self {
            clock: crate::core::time::FrameClock::new(config.target_interval),
            config,
            frame_count: 0,
            frame_time_sum: Duration::ZERO,
            fps_update_time: now,
            current_fps: 0.0,
        }
    }

    /// Check if it's time for a new frame
    pub fn should_render(&self) -> bool {
        // Use a conservative render time estimate (example: 4ms)
        // In the future this could be dynamic based on history
        let render_estimate = Duration::from_millis(4);
        let start_time = self.clock.plan_render(render_estimate);
        Instant::now() >= start_time
    }

    /// Mark frame as started
    pub fn begin_frame(&mut self) -> u64 {
        self.frame_count += 1;
        self.frame_count
    }

    /// Mark frame as complete
    pub fn end_frame(&mut self) {
        let now = Instant::now();

        // We don't have exact VBlank time here, so we effectively just log completion.
        // The FrameClock relies on update_vblank() which should be called with
        // Presentation feedback, but for now we can inform it of completion
        // or rely on explicit feedback calls.
        // For now, let's essentially 'tick' it? No, FrameClock is continuous.

        self.frame_time_sum += Duration::from_micros(16667); // Placeholder

        // Update FPS every second
        let fps_elapsed = now.duration_since(self.fps_update_time);
        if fps_elapsed >= Duration::from_secs(1) {
            self.current_fps = self.frame_count as f64 / fps_elapsed.as_secs_f64();
            self.frame_count = 0;
            self.frame_time_sum = Duration::ZERO;
            self.fps_update_time = now;
        }
    }

    /// Get current FPS
    pub fn fps(&self) -> f64 {
        self.current_fps
    }

    /// Get time until next frame
    pub fn time_until_next_frame(&self) -> Duration {
        let render_estimate = Duration::from_millis(4);
        let start_time = self.clock.plan_render(render_estimate);
        let now = Instant::now();
        if now >= start_time {
            Duration::ZERO
        } else {
            start_time - now
        }
    }

    /// Get frame timestamp for Wayland (milliseconds since epoch)
    pub fn frame_timestamp_ms(&self) -> u32 {
        Compositor::timestamp_ms()
    }
}

impl Default for FrameTiming {
    fn default() -> Self {
        Self::new(FrameTimingConfig::default())
    }
}

// ============================================================================
// Runtime State
// ============================================================================

/// Runtime state flags
#[derive(Debug, Clone, Copy, Default)]
pub struct RuntimeFlags {
    /// Redraw needed
    pub needs_redraw: bool,
    /// Flush needed
    pub needs_flush: bool,
    /// Frame callbacks pending
    pub has_frame_callbacks: bool,
}

// ============================================================================
// Main Runtime
// ============================================================================

/// The compositor runtime.
///
/// This manages the event loop and frame timing for the compositor.
/// Platform adapters should:
/// 1. Call `poll()` or `dispatch()` regularly
/// 2. Call `render()` when the platform is ready to draw
/// 3. Call `frame_complete()` after presenting
pub struct Runtime {
    /// Task queue for deferred execution
    tasks: TaskQueue,

    /// Frame timing
    frame_timing: FrameTiming,

    /// Runtime flags
    flags: RuntimeFlags,

    /// Pending events for platform
    events: Vec<CompositorEvent>,
}

impl Runtime {
    /// Create a new runtime
    pub fn new() -> Self {
        Self {
            tasks: TaskQueue::new(),
            frame_timing: FrameTiming::default(),
            flags: RuntimeFlags::default(),
            events: Vec::new(),
        }
    }

    /// Create runtime with custom frame timing
    pub fn with_frame_timing(config: FrameTimingConfig) -> Self {
        Self {
            tasks: TaskQueue::new(),
            frame_timing: FrameTiming::new(config),
            flags: RuntimeFlags::default(),
            events: Vec::new(),
        }
    }

    // =========================================================================
    // Task Management
    // =========================================================================

    /// Queue a task for execution
    pub fn queue_task<F>(&self, task: F)
    where
        F: FnOnce(&mut CompositorState) + Send + 'static,
    {
        self.tasks.push(Box::new(task));
    }

    /// Execute all pending tasks
    pub fn execute_tasks(&mut self, state: &mut CompositorState) {
        let tasks = self.tasks.take_all();
        for task in tasks {
            task(state);
        }
    }

    // =========================================================================
    // Event Loop Integration
    // =========================================================================

    /// Poll for events (non-blocking)
    ///
    /// This processes Wayland events and returns pending compositor events.
    pub fn poll(
        &mut self,
        compositor: &mut Compositor,
        state: &mut CompositorState,
    ) -> Result<Vec<CompositorEvent>, CoreError> {
        // Execute pending tasks
        self.execute_tasks(state);

        // Dispatch Wayland events
        compositor
            .dispatch(state)
            .map_err(|e| CoreError::wayland_error(e.to_string()))?;

        // Collect events from compositor
        let mut events = compositor.take_events();
        events.append(&mut self.events);

        // Also collect events from state (pushed by protocol handlers)
        events.append(&mut state.pending_compositor_events);

        Ok(events)
    }

    /// Dispatch with timeout
    ///
    /// Blocks until events are available or timeout expires.
    pub fn dispatch(
        &mut self,
        compositor: &mut Compositor,
        state: &mut CompositorState,
        timeout: Duration,
    ) -> Result<Vec<CompositorEvent>, CoreError> {
        // Execute pending tasks
        self.execute_tasks(state);

        // Dispatch Wayland events with timeout
        compositor
            .dispatch_timeout(state, timeout)
            .map_err(|e| CoreError::wayland_error(e.to_string()))?;

        // Collect events
        let mut events = compositor.take_events();
        events.append(&mut self.events);

        // Also collect events from state (pushed by protocol handlers)
        events.append(&mut state.pending_compositor_events);

        Ok(events)
    }

    // =========================================================================
    // Frame Timing
    // =========================================================================

    /// Check if it's time to render a new frame
    pub fn should_render(&self) -> bool {
        self.flags.needs_redraw || self.frame_timing.should_render()
    }

    /// Begin a new frame
    pub fn begin_frame(&mut self) -> u64 {
        self.flags.needs_redraw = false;
        self.frame_timing.begin_frame()
    }

    /// End the current frame
    pub fn end_frame(&mut self) {
        self.frame_timing.end_frame();
    }

    /// Request a redraw
    pub fn request_redraw(&mut self) {
        self.flags.needs_redraw = true;
    }

    /// Get current FPS
    pub fn fps(&self) -> f64 {
        self.frame_timing.fps()
    }

    /// Get time until next frame
    pub fn time_until_next_frame(&self) -> Duration {
        self.frame_timing.time_until_next_frame()
    }

    /// Get frame timestamp for Wayland
    pub fn frame_timestamp_ms(&self) -> u32 {
        self.frame_timing.frame_timestamp_ms()
    }

    // =========================================================================
    // Flags
    // =========================================================================

    /// Get runtime flags
    pub fn flags(&self) -> RuntimeFlags {
        self.flags
    }

    /// Set needs_flush flag
    pub fn set_needs_flush(&mut self, value: bool) {
        self.flags.needs_flush = value;
    }

    /// Set has_frame_callbacks flag
    pub fn set_has_frame_callbacks(&mut self, value: bool) {
        self.flags.has_frame_callbacks = value;
    }

    // =========================================================================
    // Events
    // =========================================================================

    /// Push an event
    pub fn push_event(&mut self, event: CompositorEvent) {
        self.events.push(event);
    }

    /// Check if there are pending events
    pub fn has_events(&self) -> bool {
        !self.events.is_empty()
    }

    // =========================================================================
    // Feedback
    // =========================================================================

    /// Report presentation timing feedback (e.g. from platform VBlank)
    pub fn report_presentation(&mut self, timestamp: Instant, refresh_mhz: u32) {
        self.frame_timing
            .report_presentation(timestamp, refresh_mhz);
    }
}

impl FrameTiming {
    /// Report presentation feedback to the clock
    pub fn report_presentation(&mut self, timestamp: Instant, refresh_mhz: u32) {
        self.clock.update_vblank(timestamp, refresh_mhz);
    }
}

impl Default for Runtime {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_frame_timing_config() {
        let config = FrameTimingConfig::for_refresh_rate(120);
        assert!(config.target_interval < Duration::from_millis(10));
    }

    #[test]
    fn test_task_queue() {
        let queue = TaskQueue::new();
        assert!(!queue.has_tasks());

        queue.push(Box::new(|_state| {}));
        assert!(queue.has_tasks());
        assert_eq!(queue.len(), 1);

        let tasks = queue.take_all();
        assert_eq!(tasks.len(), 1);
        assert!(!queue.has_tasks());
    }
}

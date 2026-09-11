#[derive(Debug, Clone, Default, Copy, PartialEq, Eq)]
pub struct DamageRegion {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

impl DamageRegion {
    pub fn new(x: i32, y: i32, width: i32, height: i32) -> Self {
        Self {
            x,
            y,
            width,
            height,
        }
    }

    /// Check if this region intersects or is adjacent to another
    pub fn intersects(&self, other: &DamageRegion) -> bool {
        self.x < other.x + other.width
            && self.x + self.width > other.x
            && self.y < other.y + other.height
            && self.y + self.height > other.y
    }

    /// Check if this region touches (intersects or shares an edge with) another
    pub fn touches(&self, other: &DamageRegion) -> bool {
        self.x <= other.x + other.width
            && self.x + self.width >= other.x
            && self.y <= other.y + other.height
            && self.y + self.height >= other.y
    }

    /// Compute the bounding box union of two regions
    pub fn union(&self, other: &DamageRegion) -> DamageRegion {
        let x = self.x.min(other.x);
        let y = self.y.min(other.y);
        let right = (self.x + self.width).max(other.x + other.width);
        let bottom = (self.y + self.height).max(other.y + other.height);
        DamageRegion {
            x,
            y,
            width: right - x,
            height: bottom - y,
        }
    }

    /// Check if this region is valid (non-negative dimensions)
    pub fn is_valid(&self) -> bool {
        self.width > 0 && self.height > 0
    }

    /// Check if the given point (in surface-local coordinates) is inside this region
    pub fn contains_point(&self, px: i32, py: i32) -> bool {
        px >= self.x && px < self.x + self.width && py >= self.y && py < self.y + self.height
    }

    /// Clamp this region to the given bounds (0,0,max_w,max_h)
    pub fn clamp(&self, max_width: i32, max_height: i32) -> DamageRegion {
        let x = self.x.max(0);
        let y = self.y.max(0);
        let right = (self.x + self.width).min(max_width);
        let bottom = (self.y + self.height).min(max_height);
        DamageRegion {
            x,
            y,
            width: (right - x).max(0),
            height: (bottom - y).max(0),
        }
    }
}

/// Tracks accumulated damage over multiple commits
#[derive(Debug, Clone, Default)]
pub struct DamageHistory {
    pub regions: Vec<DamageRegion>,
}

impl DamageHistory {
    pub fn add(&mut self, region: DamageRegion) {
        if !region.is_valid() {
            return;
        }

        // Try to merge with an existing touching/overlapping region
        for existing in self.regions.iter_mut() {
            if existing.touches(&region) {
                *existing = existing.union(&region);
                return;
            }
        }
        self.regions.push(region);
        self.merge_pass();
    }

    /// Run a merge pass to collapse any regions that now overlap after additions
    fn merge_pass(&mut self) {
        let mut merged = true;
        while merged {
            merged = false;
            let mut i = 0;
            while i < self.regions.len() {
                let mut j = i + 1;
                while j < self.regions.len() {
                    if self.regions[i].touches(&self.regions[j]) {
                        let combined = self.regions[i].union(&self.regions[j]);
                        self.regions[i] = combined;
                        self.regions.swap_remove(j);
                        merged = true;
                    } else {
                        j += 1;
                    }
                }
                i += 1;
            }
        }
    }

    /// Add multiple regions, merging as we go
    pub fn add_regions(&mut self, regions: &[DamageRegion]) {
        for region in regions {
            if region.is_valid() {
                self.regions.push(*region);
            }
        }
        self.merge_pass();
    }

    pub fn clear(&mut self) {
        self.regions.clear();
    }

    pub fn is_empty(&self) -> bool {
        self.regions.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_merge_overlapping_regions() {
        let mut history = DamageHistory::default();
        history.add(DamageRegion::new(0, 0, 100, 100));
        history.add(DamageRegion::new(50, 50, 100, 100));
        assert_eq!(history.regions.len(), 1);
        assert_eq!(history.regions[0], DamageRegion::new(0, 0, 150, 150));
    }

    #[test]
    fn test_merge_adjacent_regions() {
        let mut history = DamageHistory::default();
        history.add(DamageRegion::new(0, 0, 100, 100));
        history.add(DamageRegion::new(100, 0, 100, 100));
        assert_eq!(history.regions.len(), 1);
        assert_eq!(history.regions[0], DamageRegion::new(0, 0, 200, 100));
    }

    #[test]
    fn test_non_overlapping_regions() {
        let mut history = DamageHistory::default();
        history.add(DamageRegion::new(0, 0, 50, 50));
        history.add(DamageRegion::new(200, 200, 50, 50));
        assert_eq!(history.regions.len(), 2);
    }

    #[test]
    fn test_invalid_region_skipped() {
        let mut history = DamageHistory::default();
        history.add(DamageRegion::new(0, 0, 0, 100));
        history.add(DamageRegion::new(0, 0, -5, 10));
        assert!(history.regions.is_empty());
    }

    #[test]
    fn test_clamp_region() {
        let r = DamageRegion::new(-10, -10, 50, 50);
        let clamped = r.clamp(100, 100);
        assert_eq!(clamped, DamageRegion::new(0, 0, 40, 40));
    }
}

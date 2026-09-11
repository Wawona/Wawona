/// Manages fullscreen state restoration.
#[derive(Debug, Default, Clone)]
pub struct FullscreenState {
    pub previous_width: i32,
    pub previous_height: i32,
    // We might want to track previous position/output too
}

impl FullscreenState {
    pub fn new(width: i32, height: i32) -> Self {
        Self {
            previous_width: width,
            previous_height: height,
        }
    }
}

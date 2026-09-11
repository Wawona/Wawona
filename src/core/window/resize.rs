/// Manages window resizing state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResizeEdge {
    None,
    Top,
    Bottom,
    Left,
    TopLeft,
    BottomLeft,
    Right,
    TopRight,
    BottomRight,
}

#[derive(Debug, Default)]
pub struct ResizeState {
    pub initial_width: i32,
    pub initial_height: i32,
    pub initial_x: i32, // Pointer X at start
    pub initial_y: i32, // Pointer Y at start
    pub edge: ResizeEdge,
}

impl Default for ResizeEdge {
    fn default() -> Self {
        Self::None
    }
}

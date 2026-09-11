use crate::ffi::types::ContentRect;
use crate::util::geometry::Rect;

/// Represents a node in the scene graph.
/// A node can be a surface, a container for other nodes, or a decorator.
#[derive(Debug, Clone)]
pub struct SceneNode {
    pub id: u32,
    pub surface_id: Option<u32>,
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
    pub scale: f32,
    pub opacity: f32,
    pub visible: bool,
    pub children: Vec<u32>,
    /// Normalized content rect within the buffer (0..1 range).
    /// Default is [0, 0, 1, 1] (full buffer).
    /// Non-default when xdg_surface.set_window_geometry crops to a CSD content area.
    pub content_rect: ContentRect,
}

impl SceneNode {
    pub fn new(id: u32) -> Self {
        Self {
            id,
            surface_id: None,
            x: 0,
            y: 0,
            width: 0,
            height: 0,
            scale: 1.0,
            opacity: 1.0,
            visible: true,
            children: Vec::new(),
            content_rect: ContentRect::default(),
        }
    }

    pub fn with_surface(mut self, surface_id: u32) -> Self {
        self.surface_id = Some(surface_id);
        self
    }

    pub fn set_position(&mut self, x: i32, y: i32) {
        self.x = x;
        self.y = y;
    }

    pub fn set_size(&mut self, width: u32, height: u32) {
        self.width = width;
        self.height = height;
    }

    /// Returns the absolute bounding box in scene coordinates
    pub fn bounding_box(&self, parent_x: i32, parent_y: i32) -> Rect {
        Rect {
            x: parent_x + self.x,
            y: parent_y + self.y,
            width: self.width,
            height: self.height,
        }
    }
}

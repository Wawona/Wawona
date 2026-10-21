use crate::core::render::node::SceneNode;
use crate::ffi::types::ContentRect;
use std::collections::HashMap;

/// Represents a flattened surface to be rendered.
#[derive(Debug, Clone)]
pub struct FlattenedSurface {
    pub surface_id: u32,
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
    pub opacity: f32,
    pub scale: f32,
    /// Normalized content rect within the buffer (0..1 range)
    pub content_rect: ContentRect,
}

/// Manages the scene graph.
#[derive(Debug, Default)]
pub struct Scene {
    pub nodes: HashMap<u32, SceneNode>,
    pub root_id: Option<u32>,
}

impl Scene {
    pub fn new() -> Self {
        Self {
            nodes: HashMap::new(),
            root_id: None,
        }
    }

    pub fn set_root(&mut self, node_id: u32) {
        self.root_id = Some(node_id);
    }

    pub fn add_node(&mut self, node: SceneNode) {
        self.nodes.insert(node.id, node);
    }

    pub fn remove_node(&mut self, node_id: u32) {
        // Remove from parent's children first
        for node in self.nodes.values_mut() {
            node.children.retain(|&id| id != node_id);
        }
        self.nodes.remove(&node_id);
    }

    pub fn add_child(&mut self, parent_id: u32, child_id: u32) {
        if let Some(parent) = self.nodes.get_mut(&parent_id) {
            if !parent.children.contains(&child_id) {
                parent.children.push(child_id);
            }
        }
    }

    /// Flattens the scene graph into a z-ordered list of visible surfaces.
    pub fn flatten(&self) -> Vec<FlattenedSurface> {
        let mut result = Vec::new();
        if let Some(root_id) = self.root_id {
            self.flatten_recursive(root_id, 0, 0, 1.0, 1.0, &mut result);
        }
        result
    }

    fn flatten_recursive(
        &self,
        node_id: u32,
        abs_x: i32,
        abs_y: i32,
        abs_scale: f32,
        abs_opacity: f32,
        result: &mut Vec<FlattenedSurface>,
    ) {
        if let Some(node) = self.nodes.get(&node_id) {
            if !node.visible || abs_opacity <= 0.0 {
                return;
            }

            let current_abs_x = abs_x + node.x;
            let current_abs_y = abs_y + node.y;
            let current_abs_scale = abs_scale * node.scale;
            let current_abs_opacity = abs_opacity * node.opacity;

            // Z-order is child index, with this node's own surface inserted
            // after the first `children_below` children.
            let split = node.children_below.min(node.children.len());
            let (below, above) = node.children.split_at(split);
            for &child_id in below {
                self.flatten_recursive(
                    child_id,
                    current_abs_x,
                    current_abs_y,
                    current_abs_scale,
                    current_abs_opacity,
                    result,
                );
            }

            if let Some(surface_id) = node.surface_id {
                result.push(FlattenedSurface {
                    surface_id,
                    x: current_abs_x,
                    y: current_abs_y,
                    width: node.width,
                    height: node.height,
                    opacity: current_abs_opacity,
                    scale: current_abs_scale,
                    content_rect: node.content_rect,
                });
            }

            for &child_id in above {
                self.flatten_recursive(
                    child_id,
                    current_abs_x,
                    current_abs_y,
                    current_abs_scale,
                    current_abs_opacity,
                    result,
                );
            }
        }
    }

    /// Dump the scene graph to a string for debugging.
    pub fn dump(&self) -> String {
        let mut out = String::new();
        if let Some(root_id) = self.root_id {
            self.dump_recursive(root_id, 0, &mut out);
        } else {
            out.push_str("(empty scene)\n");
        }
        out
    }

    fn dump_recursive(&self, node_id: u32, depth: usize, out: &mut String) {
        if let Some(node) = self.nodes.get(&node_id) {
            let indent = "  ".repeat(depth);
            out.push_str(&format!(
                "{}Node {}: pos=({},{}) size={}x{} opacity={:.2} surface={:?}\n",
                indent,
                node.id,
                node.x,
                node.y,
                node.width,
                node.height,
                node.opacity,
                node.surface_id
            ));

            for &child_id in &node.children {
                self.dump_recursive(child_id, depth + 1, out);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn surface_order(scene: &Scene) -> Vec<u32> {
        scene.flatten().iter().map(|s| s.surface_id).collect()
    }

    fn parent_with_two_children(children_below: usize) -> Scene {
        let mut scene = Scene::new();
        scene.add_node(SceneNode::new(1).with_surface(10));
        scene.add_node(SceneNode::new(2).with_surface(20));
        scene.add_node(SceneNode::new(3).with_surface(30));
        scene.set_root(1);
        scene.add_child(1, 2);
        scene.add_child(1, 3);
        if let Some(parent) = scene.nodes.get_mut(&1) {
            parent.children_below = children_below;
        }
        scene
    }

    #[test]
    fn flatten_should_stack_children_above_parent_by_default() {
        assert_eq!(
            surface_order(&parent_with_two_children(0)),
            vec![10, 20, 30]
        );
    }

    #[test]
    fn flatten_should_stack_leading_children_below_parent() {
        assert_eq!(
            surface_order(&parent_with_two_children(1)),
            vec![20, 10, 30]
        );
    }

    #[test]
    fn flatten_should_clamp_children_below_to_child_count() {
        assert_eq!(
            surface_order(&parent_with_two_children(9)),
            vec![20, 30, 10]
        );
    }
}

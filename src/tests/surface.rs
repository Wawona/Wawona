use crate::core::surface::{Surface, buffer::BufferType, damage::DamageRegion};

#[test]
fn test_surface_creation() {
    let surface = Surface::new(1, None, None);
    assert_eq!(surface.id, 1);
    assert!(matches!(surface.current.buffer, BufferType::None));
    assert!(matches!(surface.pending.buffer, BufferType::None));
    assert_eq!(surface.current.scale, 1);
}

#[test]
fn test_surface_damage_accumulation() {
    let mut surface = Surface::new(1, None, None);
    // Assuming damage is tracked in pending state
    surface.pending.damage.push(DamageRegion { x: 0, y: 0, width: 100, height: 100 });
    assert!(!surface.pending.damage.is_empty());
    
    // Commit logic would verify it moves to current, but that might depend on CompositorState
    // So we just test state accumulation here.
}

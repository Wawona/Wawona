use crate::core::surface::damage::DamageRegion;
use crate::core::surface::surface::SurfaceState;

fn map_buffer_point_to_surface(
    x: i32,
    y: i32,
    buffer_width: i32,
    buffer_height: i32,
    transform: wayland_server::protocol::wl_output::Transform,
) -> (i32, i32) {
    match transform {
        wayland_server::protocol::wl_output::Transform::Normal => (x, y),
        wayland_server::protocol::wl_output::Transform::_90 => (buffer_height - y, x),
        wayland_server::protocol::wl_output::Transform::_180 => {
            (buffer_width - x, buffer_height - y)
        }
        wayland_server::protocol::wl_output::Transform::_270 => (y, buffer_width - x),
        wayland_server::protocol::wl_output::Transform::Flipped => (buffer_width - x, y),
        wayland_server::protocol::wl_output::Transform::Flipped90 => {
            (buffer_height - y, buffer_width - x)
        }
        wayland_server::protocol::wl_output::Transform::Flipped180 => (x, buffer_height - y),
        wayland_server::protocol::wl_output::Transform::Flipped270 => (y, x),
        _ => (x, y),
    }
}

fn scale_damage_bounds(min_v: i32, max_v: i32, scale: i32) -> (i32, i32) {
    let scale_f = scale.max(1) as f64;
    let min_scaled = (min_v as f64 / scale_f).floor() as i32;
    let max_scaled = (max_v as f64 / scale_f).ceil() as i32;
    (min_scaled, max_scaled)
}

fn convert_buffer_damage_to_surface(
    region: DamageRegion,
    buffer_width: i32,
    buffer_height: i32,
    scale: i32,
    transform: wayland_server::protocol::wl_output::Transform,
) -> DamageRegion {
    let corners = [
        map_buffer_point_to_surface(region.x, region.y, buffer_width, buffer_height, transform),
        map_buffer_point_to_surface(
            region.x + region.width,
            region.y,
            buffer_width,
            buffer_height,
            transform,
        ),
        map_buffer_point_to_surface(
            region.x,
            region.y + region.height,
            buffer_width,
            buffer_height,
            transform,
        ),
        map_buffer_point_to_surface(
            region.x + region.width,
            region.y + region.height,
            buffer_width,
            buffer_height,
            transform,
        ),
    ];
    let min_x = corners.iter().map(|(x, _)| *x).min().unwrap_or(region.x);
    let max_x = corners
        .iter()
        .map(|(x, _)| *x)
        .max()
        .unwrap_or(region.x + region.width);
    let min_y = corners.iter().map(|(_, y)| *y).min().unwrap_or(region.y);
    let max_y = corners
        .iter()
        .map(|(_, y)| *y)
        .max()
        .unwrap_or(region.y + region.height);

    let (sx, sr) = scale_damage_bounds(min_x, max_x, scale);
    let (sy, sb) = scale_damage_bounds(min_y, max_y, scale);

    DamageRegion::new(sx, sy, (sr - sx).max(0), (sb - sy).max(0))
}

/// Validates and clamps region rectangles to surface bounds.
/// Returns None for regions that pass validation, or clamps out-of-bounds ones.
fn validate_regions(
    regions: &Option<Vec<DamageRegion>>,
    width: i32,
    height: i32,
) -> Option<Vec<DamageRegion>> {
    regions.as_ref().map(|rects| {
        rects
            .iter()
            .filter_map(|r| {
                if r.width <= 0 || r.height <= 0 {
                    tracing::warn!(
                        "Dropping invalid region: {}x{} at ({},{})",
                        r.width,
                        r.height,
                        r.x,
                        r.y
                    );
                    return None;
                }
                if width > 0 && height > 0 {
                    let clamped = r.clamp(width, height);
                    if clamped.width > 0 && clamped.height > 0 {
                        Some(clamped)
                    } else {
                        None
                    }
                } else {
                    Some(*r)
                }
            })
            .collect()
    })
}

/// Performs the atomic update of a surface state.
/// Returns the ID of the buffer that was replaced and should be released, if any.
pub fn apply_commit(pending: &mut SurfaceState, current: &mut SurfaceState) -> Option<u32> {
    // Check if buffer is changing
    let old_buffer = if pending.buffer_id != current.buffer_id {
        current.buffer_id
    } else {
        None
    };

    // 1. Update buffer if pending
    current.buffer = pending.buffer.clone();
    current.buffer_id = pending.buffer_id;

    // 2. Update dimensions based on buffer size, scale and transform
    if let Some((buffer_width, buffer_height)) = current.buffer.dimensions() {
        let scale = pending.scale.max(1);

        // Handle transforms that swap width/height
        let swapped = match pending.transform {
            wayland_server::protocol::wl_output::Transform::_90
            | wayland_server::protocol::wl_output::Transform::_270
            | wayland_server::protocol::wl_output::Transform::Flipped90
            | wayland_server::protocol::wl_output::Transform::Flipped270 => true,
            _ => false,
        };

        if swapped {
            current.width = buffer_height / scale;
            current.height = buffer_width / scale;
        } else {
            current.width = buffer_width / scale;
            current.height = buffer_height / scale;
        }
    } else {
        current.width = 0;
        current.height = 0;
    }

    // 3. Accumulate damage (clamp to surface bounds)
    for region in pending.damage.drain(..) {
        if current.width > 0 && current.height > 0 {
            let clamped = region.clamp(current.width, current.height);
            if clamped.is_valid() {
                current.damage.push(clamped);
            }
        } else {
            if region.is_valid() {
                current.damage.push(region);
            }
        }
    }

    // 3b. Convert buffer-local damage into surface-local coordinates.
    if let Some((buffer_width, buffer_height)) = current.buffer.dimensions() {
        for region in pending.buffer_damage.drain(..) {
            let converted = convert_buffer_damage_to_surface(
                region,
                buffer_width,
                buffer_height,
                pending.scale.max(1),
                pending.transform,
            );
            if current.width > 0 && current.height > 0 {
                let clamped = converted.clamp(current.width, current.height);
                if clamped.is_valid() {
                    current.damage.push(clamped);
                }
            } else if converted.is_valid() {
                current.damage.push(converted);
            }
        }
    } else {
        // No buffer dimensions available yet; preserve damage for later clamp.
        for region in pending.buffer_damage.drain(..) {
            if region.is_valid() {
                current.damage.push(region);
            }
        }
    }

    // 4. Update other attributes
    current.opaque = pending.opaque;
    current.scale = pending.scale;
    current.transform = pending.transform;
    current.offset = pending.offset;

    // 5. Validate and clamp input/opaque regions to surface bounds
    current.input_region = validate_regions(&pending.input_region, current.width, current.height);
    current.opaque_region = validate_regions(&pending.opaque_region, current.width, current.height);

    old_buffer
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::core::surface::buffer::{BufferType, ShmBufferData};

    #[test]
    fn converts_damage_buffer_with_scale() {
        let mut pending = SurfaceState::default();
        let mut current = SurfaceState::default();
        pending.buffer = BufferType::Shm(ShmBufferData {
            width: 200,
            height: 100,
            stride: 800,
            format: 0,
            offset: 0,
            pool_id: 1,
        });
        pending.buffer_id = Some(5);
        pending.scale = 2;
        pending
            .buffer_damage
            .push(DamageRegion::new(20, 10, 40, 20));

        apply_commit(&mut pending, &mut current);

        assert_eq!(current.width, 100);
        assert_eq!(current.height, 50);
        assert_eq!(current.damage, vec![DamageRegion::new(10, 5, 20, 10)]);
    }

    #[test]
    fn converts_damage_buffer_with_transform() {
        let mut pending = SurfaceState::default();
        let mut current = SurfaceState::default();
        pending.buffer = BufferType::Shm(ShmBufferData {
            width: 120,
            height: 60,
            stride: 480,
            format: 0,
            offset: 0,
            pool_id: 2,
        });
        pending.buffer_id = Some(7);
        pending.transform = wayland_server::protocol::wl_output::Transform::_90;
        pending.buffer_damage.push(DamageRegion::new(0, 0, 20, 10));

        apply_commit(&mut pending, &mut current);

        // 90-degree transform swaps dimensions and rotates damage.
        assert_eq!(current.width, 60);
        assert_eq!(current.height, 120);
        assert_eq!(current.damage, vec![DamageRegion::new(50, 0, 10, 20)]);
    }
}

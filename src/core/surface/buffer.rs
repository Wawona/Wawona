use wayland_server::Resource;

#[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
use std::{ffi::c_void, sync::Arc};

#[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
#[derive(Debug)]
pub struct AppleIOSurfaceOwner {
    raw: *mut c_void,
}

#[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
impl AppleIOSurfaceOwner {
    pub(crate) fn raw(&self) -> *mut c_void {
        self.raw
    }
}

#[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
unsafe impl Send for AppleIOSurfaceOwner {}
#[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
unsafe impl Sync for AppleIOSurfaceOwner {}

#[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
impl Drop for AppleIOSurfaceOwner {
    fn drop(&mut self) {
        unsafe { CFRelease(self.raw.cast_const()) }
    }
}

#[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
#[link(name = "IOSurface", kind = "framework")]
extern "C" {
    fn IOSurfaceLookup(csid: u32) -> *mut c_void;
}

#[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFRelease(value: *const c_void);
}

#[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
pub fn retain_iosurface(id: u32) -> Option<Arc<AppleIOSurfaceOwner>> {
    let raw = unsafe { IOSurfaceLookup(id) };
    (!raw.is_null()).then(|| Arc::new(AppleIOSurfaceOwner { raw }))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShmBufferData {
    pub width: i32,
    pub height: i32,
    pub stride: i32,
    pub format: u32,
    pub offset: i32,
    pub pool_id: u32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DmaBufData {
    pub width: u32,
    pub height: u32,
    pub format: u32,
    pub modifier: u64,
    pub fds: Vec<i32>,
    pub offsets: Vec<u32>,
    pub strides: Vec<u32>,
}

/// Represents a GPU-ready or CPU-accessible buffer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BufferType {
    Shm(ShmBufferData),
    DmaBuf(DmaBufData),
    Native(NativeBufferData), // e.g. MacOS IOSurface
    None,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NativeBufferData {
    pub id: u64,
    pub width: i32,
    pub height: i32,
    pub format: u32,
}

#[derive(Debug, Clone)]
pub struct Buffer {
    pub id: u32,
    pub buffer_type: BufferType,
    pub released: bool,
    pub resource: Option<wayland_server::protocol::wl_buffer::WlBuffer>,
    #[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
    pub native_iosurface: Option<Arc<AppleIOSurfaceOwner>>,
}

impl Buffer {
    pub fn new(
        id: u32,
        buffer_type: BufferType,
        resource: Option<wayland_server::protocol::wl_buffer::WlBuffer>,
    ) -> Self {
        Self {
            id,
            buffer_type,
            released: false,
            resource,
            #[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
            native_iosurface: None,
        }
    }

    #[cfg(all(target_vendor = "apple", not(target_os = "watchos")))]
    pub fn with_native_iosurface(mut self, owner: Arc<AppleIOSurfaceOwner>) -> Self {
        self.native_iosurface = Some(owner);
        self
    }

    /// Notify the client that the buffer is no longer being used
    pub fn release(&mut self) {
        if self.released {
            return;
        }

        if let Some(resource) = &self.resource {
            if resource.is_alive() {
                resource.release();
                #[cfg(feature = "verbose-logs")]
                eprintln!("[BUFFER] wl_buffer.release SENT buf={}", self.id);
            } else {
                #[cfg(feature = "verbose-logs")]
                eprintln!("[BUFFER] buf={} resource DEAD, release NOT sent", self.id);
            }
        } else {
            #[cfg(feature = "verbose-logs")]
            eprintln!("[BUFFER] buf={} has NO resource, release NOT sent", self.id);
        }

        self.released = true;
    }
}

/// Maps `wl_shm::Format` to the legacy `u32` tags used by the macOS FFI path (0 = ARGB8888, 1 = XRGB8888).
pub fn wl_shm_format_to_legacy_u32(f: wayland_server::protocol::wl_shm::Format) -> u32 {
    use wayland_server::protocol::wl_shm::Format;
    match f {
        Format::Argb8888 => 0,
        Format::Xrgb8888 => 1,
        _ => f as u32,
    }
}

impl BufferType {
    pub fn dimensions(&self) -> Option<(i32, i32)> {
        match self {
            BufferType::Shm(data) => Some((data.width, data.height)),
            BufferType::DmaBuf(data) => Some((data.width as i32, data.height as i32)),
            BufferType::Native(data) => Some((data.width, data.height)),
            BufferType::None => None,
        }
    }
}

impl Default for BufferType {
    fn default() -> Self {
        Self::None
    }
}

/// Pool offset of the last byte a `wl_shm` buffer covers. `None` when the
/// client-declared layout is empty, negative, or overflows.
pub(crate) fn shm_last_byte(offset: i32, stride: i32, height: i32) -> Option<usize> {
    let offset = usize::try_from(offset).ok()?;
    let stride = usize::try_from(stride).ok()?;
    let height = usize::try_from(height).ok()?;
    stride
        .checked_mul(height)?
        .checked_add(offset)?
        .checked_sub(1)
        .filter(|_| stride > 0 && height > 0)
}

#[cfg(test)]
mod shm_extent_tests {
    use super::shm_last_byte;

    #[test]
    fn last_byte_of_simple_buffer() {
        assert_eq!(shm_last_byte(0, 800, 200), Some(159_999));
    }

    #[test]
    fn last_byte_includes_offset() {
        assert_eq!(shm_last_byte(16, 4, 2), Some(23));
    }

    #[test]
    fn negative_layout_is_rejected() {
        assert_eq!(shm_last_byte(-1, 4, 2), None);
    }

    #[test]
    fn empty_buffer_is_rejected() {
        assert_eq!(shm_last_byte(8, 0, 2), None);
    }

    #[test]
    fn zero_height_is_rejected() {
        assert_eq!(shm_last_byte(0, 4, 0), None);
    }
}

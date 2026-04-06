use std::os::unix::io::AsRawFd;
use wayland_client::{
    protocol::{wl_compositor, wl_keyboard, wl_registry, wl_seat, wl_shm, wl_shm_pool, wl_surface, wl_buffer},
    Connection, Dispatch, QueueHandle, WEnum,
};
use wayland_protocols::xdg::shell::client::{xdg_wm_base, xdg_surface, xdg_toplevel};
use xkbcommon::xkb;
use std::fs::File;
use std::os::unix::prelude::AsFd;

const FONT_WIDTH: i32 = 8;
const FONT_HEIGHT: i32 = 8;

fn get_font_bitmap(c: char) -> [u8; 8] {
    let cp = c as usize;
    if cp < 32 || cp > 126 { return [0; 8]; }
    font8x8::FONT[cp]
}

mod font8x8 {
    include!("../../../../../src/util/font8x8.rs");
}

struct AppData {
    compositor: Option<wl_compositor::WlCompositor>,
    seat: Option<wl_seat::WlSeat>,
    shm: Option<wl_shm::WlShm>,
    wm_base: Option<xdg_wm_base::XdgWmBase>,
    keyboard: Option<wl_keyboard::WlKeyboard>,
    surface: Option<wl_surface::WlSurface>,
    xdg_surface: Option<xdg_surface::XdgSurface>,
    xdg_toplevel: Option<xdg_toplevel::XdgToplevel>,
    
    // XKB state
    xkb_context: Option<xkb::Context>,
    xkb_keymap: Option<xkb::Keymap>,
    xkb_state: Option<xkb::State>,
    
    // Editor state
    text: String,
    cursor_idx: usize,
    
    // Rendering state
    width: i32,
    height: i32,
    configured: bool,
    buffer: Option<wl_buffer::WlBuffer>,
    qh: Option<QueueHandle<AppData>>,
}

impl Dispatch<wl_registry::WlRegistry, ()> for AppData {
    fn event(state: &mut Self, registry: &wl_registry::WlRegistry, event: wl_registry::Event, _: &(), _: &Connection, qh: &QueueHandle<Self>) {
        if let wl_registry::Event::Global { name, interface, version } = event {
            match &interface[..] {
                "wl_compositor" => { state.compositor = Some(registry.bind(name, version, qh, ())); }
                "wl_seat" => { state.seat = Some(registry.bind(name, version, qh, ())); }
                "wl_shm" => { state.shm = Some(registry.bind(name, version, qh, ())); }
                "xdg_wm_base" => { state.wm_base = Some(registry.bind(name, version, qh, ())); }
                _ => {}
            }
        }
    }
}

impl Dispatch<wl_compositor::WlCompositor, ()> for AppData { fn event(_: &mut Self, _: &wl_compositor::WlCompositor, _: wl_compositor::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {} }

impl Dispatch<xdg_wm_base::XdgWmBase, ()> for AppData {
    fn event(_: &mut Self, wm_base: &xdg_wm_base::XdgWmBase, event: xdg_wm_base::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {
        if let xdg_wm_base::Event::Ping { serial } = event { wm_base.pong(serial); }
    }
}

impl Dispatch<xdg_surface::XdgSurface, ()> for AppData {
    fn event(state: &mut Self, xdg_surface: &xdg_surface::XdgSurface, event: xdg_surface::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {
        if let xdg_surface::Event::Configure { serial } = event {
            xdg_surface.ack_configure(serial);
            state.configured = true;
            state.draw();
        }
    }
}

impl Dispatch<xdg_toplevel::XdgToplevel, ()> for AppData {
    fn event(state: &mut Self, _: &xdg_toplevel::XdgToplevel, event: xdg_toplevel::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {
        if let xdg_toplevel::Event::Configure { width, height, .. } = event {
            if width > 0 && height > 0 {
                state.width = width;
                state.height = height;
            }
        }
    }
}

impl Dispatch<wl_seat::WlSeat, ()> for AppData {
    fn event(state: &mut Self, seat: &wl_seat::WlSeat, event: wl_seat::Event, _: &(), _: &Connection, qh: &QueueHandle<Self>) {
        if let wl_seat::Event::Capabilities { capabilities } = event {
            if let WEnum::Value(caps) = capabilities {
                if caps.contains(wl_seat::Capability::Keyboard) {
                    state.keyboard = Some(seat.get_keyboard(qh, ()));
                }
            }
        }
    }
}

impl Dispatch<wl_keyboard::WlKeyboard, ()> for AppData {
    fn event(state: &mut Self, _: &wl_keyboard::WlKeyboard, event: wl_keyboard::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {
        match event {
            wl_keyboard::Event::Keymap { format, fd, size } => {
                if let WEnum::Value(wl_keyboard::KeymapFormat::XkbV1) = format {
                    let keymap_data = unsafe {
                        let ptr = libc::mmap(std::ptr::null_mut(), size as usize, libc::PROT_READ, libc::MAP_PRIVATE, fd.as_raw_fd(), 0);
                        if ptr == libc::MAP_FAILED { return; }
                        std::slice::from_raw_parts(ptr as *const u8, size as usize)
                    };
                    let context = xkb::Context::new(xkb::CONTEXT_NO_FLAGS);
                    let keymap_str = std::str::from_utf8(keymap_data).unwrap_or("").to_string();
                    if let Some(keymap) = xkb::Keymap::new_from_string(&context, keymap_str, xkb::KEYMAP_FORMAT_TEXT_V1, xkb::KEYMAP_COMPILE_NO_FLAGS) {
                        state.xkb_state = Some(xkb::State::new(&keymap));
                        state.xkb_context = Some(context);
                        state.xkb_keymap = Some(keymap);
                    }
                    unsafe { libc::munmap(keymap_data.as_ptr() as *mut _, size as usize); }
                }
            }
            wl_keyboard::Event::Key { key, state: key_state, .. } => {
                let keycode = key + 8; // XKB Offset
                let pressed = key_state == WEnum::Value(wl_keyboard::KeyState::Pressed);
                
                if pressed {
                    if let Some(xkb_state) = &mut state.xkb_state {
                        let keysym = xkb_state.key_get_one_sym(keycode.into());
                        
                        match u32::from(keysym) {
                            xkb::keysyms::KEY_BackSpace => {
                                if state.cursor_idx > 0 && !state.text.is_empty() {
                                    // Remove char before cursor
                                    if let Some((idx, _)) = state.text.char_indices().nth(state.cursor_idx - 1) {
                                        state.text.remove(idx);
                                        state.cursor_idx -= 1;
                                    }
                                }
                            }
                            xkb::keysyms::KEY_Delete => {
                                if state.cursor_idx < state.text.chars().count() {
                                    if let Some((idx, _)) = state.text.char_indices().nth(state.cursor_idx) {
                                        state.text.remove(idx);
                                    }
                                }
                            }
                            xkb::keysyms::KEY_Left => {
                                if state.cursor_idx > 0 { state.cursor_idx -= 1; }
                            }
                            xkb::keysyms::KEY_Right => {
                                if state.cursor_idx < state.text.chars().count() { state.cursor_idx += 1; }
                            }
                            xkb::keysyms::KEY_Return | xkb::keysyms::KEY_KP_Enter => {
                                if let Some((idx, _)) = state.text.char_indices().nth(state.cursor_idx) {
                                    state.text.insert(idx, '\n');
                                } else {
                                    state.text.push('\n');
                                }
                                state.cursor_idx += 1;
                            }
                            _ => {
                                let utf8 = xkb_state.key_get_utf8(keycode.into());
                                if !utf8.is_empty() {
                                    // Insert at cursor
                                    if state.text.is_empty() || state.cursor_idx >= state.text.chars().count() {
                                        state.text.push_str(&utf8);
                                    } else {
                                        if let Some((idx, _)) = state.text.char_indices().nth(state.cursor_idx) {
                                            state.text.insert_str(idx, &utf8);
                                        }
                                    }
                                    state.cursor_idx += utf8.chars().count();
                                }
                            }
                        }
                        state.draw();
                    }
                }
            }
            wl_keyboard::Event::Modifiers { mods_depressed, mods_latched, mods_locked, group, .. } => {
                if let Some(xkb_state) = &mut state.xkb_state {
                    xkb_state.update_mask(mods_depressed, mods_latched, mods_locked, 0, 0, group);
                }
            }
            _ => {}
        }
    }
}

impl Dispatch<wl_surface::WlSurface, ()> for AppData { fn event(_: &mut Self, _: &wl_surface::WlSurface, _: wl_surface::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {} }
impl Dispatch<wl_shm::WlShm, ()> for AppData { fn event(_: &mut Self, _: &wl_shm::WlShm, _: wl_shm::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {} }
impl Dispatch<wl_shm_pool::WlShmPool, ()> for AppData { fn event(_: &mut Self, _: &wl_shm_pool::WlShmPool, _: wl_shm_pool::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {} }
impl Dispatch<wl_buffer::WlBuffer, ()> for AppData { fn event(_: &mut Self, _: &wl_buffer::WlBuffer, _: wl_buffer::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {} }

impl AppData {
    fn draw(&mut self) {
        if !self.configured { return; }
        
        // --- Setup Buffer ---
        let (surface, shm, qh) = match (self.surface.as_ref(), self.shm.as_ref(), self.qh.as_ref()) {
            (Some(s), Some(shm), Some(qh)) => (s, shm, qh),
            _ => return,
        };

        let width = self.width;
        let height = self.height;
        let stride = width * 4;
        let size = stride * height;

        let tmp_path = format!("/tmp/wawona-client-shm.{}", std::process::id());
        let file = File::options().read(true).write(true).create(true).truncate(true).open(&tmp_path).expect("Failed to create SHM");
        std::fs::remove_file(&tmp_path).ok();
        file.set_len(size as u64).expect("Failed size");

        let pool = shm.create_pool(file.as_fd(), size, qh, ());
        let buffer = pool.create_buffer(0, width, height, stride, wl_shm::Format::Argb8888, qh, ());

        unsafe {
            let ptr = libc::mmap(std::ptr::null_mut(), size as usize, libc::PROT_WRITE, libc::MAP_SHARED, file.as_raw_fd(), 0) as *mut u32;
            if ptr != libc::MAP_FAILED as *mut u32 {
                let slice = std::slice::from_raw_parts_mut(ptr, (width * height) as usize);
                
                // --- Background ---
                slice.fill(0xFF1E1E1E); // VS Code Dark Theme background
                
                // --- Status Bar Background ---
                let bar_height = 30;
                let bar_start = height - bar_height;
                for i in (bar_start * width)..(height * width) {
                    if i >= 0 && (i as usize) < slice.len() {
                        slice[i as usize] = 0xFF007ACC; // Blue status bar
                    }
                }

                // --- Text Rendering ---
                let mut x = 10;
                let mut y = 10;
                let scale = 2; // 16x16 chars
                let char_w = FONT_WIDTH * scale;
                let char_h = FONT_HEIGHT * scale;
                
                // Track cursor pixel position
                let mut cursor_pos = (x, y);
                let chars_count = self.text.chars().count();
                
                // Sanity check cursor
                if self.cursor_idx > chars_count { self.cursor_idx = chars_count; }

                for (i, c) in self.text.chars().enumerate() {
                    // Capture cursor position if this is the cursor index
                    if i == self.cursor_idx {
                        cursor_pos = (x, y);
                    }

                    if c == '\n' {
                        x = 10;
                        y += char_h + 4;
                        continue;
                    }
                    
                    // Word wrap
                    if x + char_w > width {
                         x = 10;
                         y += char_h + 4;
                    }

                    // Stop rendering if invalid
                    if y + char_h > bar_start {
                        break;
                    }

                    let bitmap = get_font_bitmap(c);
                    for row in 0..8 {
                        let bits = bitmap[row];
                        for col in 0..8 {
                           if (bits >> (7 - col)) & 1 == 1 {
                               for sy in 0..scale {
                                   for sx in 0..scale {
                                       let px = x + (col as i32 * scale) + sx;
                                       let py = y + (row as i32 * scale) + sy;
                                       if px < width && py < bar_start {
                                           slice[(py * width + px) as usize] = 0xFFCCCCCC; // Light text
                                       }
                                   }
                               }
                           }
                        }
                    }
                    x += char_w + 2;
                }
                
                // Catch cursor if at end of string
                if self.cursor_idx == chars_count {
                    cursor_pos = (x, y);
                }

                // --- Draw Cursor ---
                let (cx, cy) = cursor_pos;
                // Only draw if visible
                if cy + char_h <= bar_start {
                    for sy in 0..char_h {
                        for sx in 0..2 { // 2px width
                             let px = cx + sx;
                             let py = cy + sy;
                             if px < width && py < bar_start {
                                 slice[(py * width + px) as usize] = 0xFFFFFFFF; // White cursor
                             }
                        }
                    }
                }
                
                // --- Status Text ---
                // "Ln ?, Col ? | Chars: ?"
                // Since we don't have a full string renderer for status yet, let's just draw some blocks or simple stats
                // Or implementing a simple string printer helper would be good.
                // For now, let's just skip complex status text to keep it simple, or re-use the loop.
                
                // Helper to draw string at x,y
                // ... (omitted for brevity in this step, but could be added easily)

                libc::munmap(ptr as *mut _, size as usize);
            }
        }

        surface.attach(Some(&buffer), 0, 0);
        surface.damage(0, 0, width, height);
        surface.commit();
        self.buffer = Some(buffer);
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let conn = Connection::connect_to_env()?;
    let display = conn.display();
    let mut event_queue = conn.new_event_queue();
    let qh = event_queue.handle();
    
    let mut app_data = AppData {
        compositor: None, seat: None, shm: None, wm_base: None,
        keyboard: None, surface: None, xdg_surface: None, xdg_toplevel: None,
        xkb_context: None, xkb_keymap: None, xkb_state: None,
        text: String::from("Type here..."), cursor_idx: 12,
        width: 800, height: 600, configured: false,
        buffer: None, qh: Some(qh.clone()),
    };
    
    let _registry = display.get_registry(&qh, ());
    event_queue.roundtrip(&mut app_data)?;
    
    if let (Some(compositor), Some(wm_base)) = (&app_data.compositor, &app_data.wm_base) {
        let surface = compositor.create_surface(&qh, ());
        let xdg_surface = wm_base.get_xdg_surface(&surface, &qh, ());
        let xdg_toplevel = xdg_surface.get_toplevel(&qh, ());
        xdg_toplevel.set_title("Wawona Edit".to_string());
        surface.commit();
        app_data.surface = Some(surface);
        app_data.xdg_surface = Some(xdg_surface);
        app_data.xdg_toplevel = Some(xdg_toplevel);
    }
    
    loop { event_queue.blocking_dispatch(&mut app_data)?; }
}

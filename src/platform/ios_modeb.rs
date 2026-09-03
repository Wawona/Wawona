//! Rust-owned iOS Mode B own-display desktop broker and Machines greeter.
//!
//! UIKit supplies lifecycle, profile JSON, and input events. This module owns
//! IOMFB lifecycle, recovery state, greeter selection, and pixels.

use serde::Deserialize;
use std::ffi::{c_char, c_void, CStr, CString};
use std::ptr;
use std::sync::{Mutex, OnceLock};

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct IomfbDamage {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct IomfbSurface {
    iosurface: *mut c_void,
    id: u32,
    width: u32,
    height: u32,
    bytes_per_row: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct IgettyCallbacks {
    context: *mut c_void,
    present_session: Option<extern "C" fn(*mut c_void, u32, u8, *const c_char) -> i32>,
}

impl Default for IomfbSurface {
    fn default() -> Self {
        Self {
            iosurface: ptr::null_mut(),
            id: 0,
            width: 0,
            height: 0,
            bytes_per_row: 0,
        }
    }
}

extern "C" {
    fn wwn_iomfb_open(out_session: *mut *mut c_void) -> i32;
    fn wwn_iomfb_acquire(session: *mut c_void, out_surface: *mut IomfbSurface) -> i32;
    fn wwn_iomfb_present_iosurface(
        session: *mut c_void,
        iosurface: *mut c_void,
        damage: IomfbDamage,
    ) -> i32;
    fn wwn_iomfb_last_error(session: *mut c_void) -> *const c_char;
    fn wwn_iomfb_restore(session: *mut c_void) -> i32;
    fn wwn_iomfb_destroy(session: *mut c_void);

    fn IOSurfaceLock(surface: *mut c_void, options: u32, seed: *mut u32) -> i32;
    fn IOSurfaceUnlock(surface: *mut c_void, options: u32, seed: *mut u32) -> i32;
    fn IOSurfaceGetBaseAddress(surface: *mut c_void) -> *mut c_void;

    fn wwn_igetty_ios_initialize(callbacks: IgettyCallbacks) -> i32;
    fn wwn_igetty_ios_register_session(kind: u8, label: *const c_char) -> u32;
    fn wwn_igetty_ios_adopt_live_text_sessions() -> u32;
    fn wwn_igetty_ios_switch_to(session_id: u32) -> i32;
    fn wwn_igetty_ios_unregister_session(session_id: u32);
    fn wwn_igetty_ios_active_session() -> u32;
    fn wwn_igetty_ios_session_count() -> usize;
    fn wwn_igetty_ios_session_at(
        index: usize,
        out_id: *mut u32,
        out_kind: *mut u8,
        label: *mut c_char,
        label_capacity: usize,
    ) -> i32;
    fn wwn_igetty_ios_shutdown();
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
enum DesktopPhase {
    Inactive = 0,
    Greeter = 1,
    Session = 2,
    Recovering = 3,
}

#[derive(Debug, Clone, Deserialize)]
struct Machine {
    #[serde(alias = "machineId")]
    id: String,
    name: String,
    #[serde(rename = "type", default)]
    kind: String,
}

#[derive(Debug, Clone)]
struct LogicalSession {
    id: u32,
    kind: u8,
    label: String,
}

struct Desktop {
    sink: usize,
    width: u32,
    height: u32,
    phase: DesktopPhase,
    machines: Vec<Machine>,
    machine_sessions: Vec<u32>,
    sessions: Vec<LogicalSession>,
    show_session_chooser: bool,
    active_machine: Option<String>,
    failed_presents: u32,
}

impl Default for Desktop {
    fn default() -> Self {
        Self {
            sink: 0,
            width: 0,
            height: 0,
            phase: DesktopPhase::Inactive,
            machines: Vec::new(),
            machine_sessions: Vec::new(),
            sessions: Vec::new(),
            show_session_chooser: false,
            active_machine: None,
            failed_presents: 0,
        }
    }
}

impl Desktop {
    fn sink_ptr(&self) -> *mut c_void {
        self.sink as *mut c_void
    }

    fn render_greeter(&mut self) -> i32 {
        if self.sink == 0 {
            return -1;
        }
        let mut surface = IomfbSurface::default();
        let acquire = unsafe { wwn_iomfb_acquire(self.sink_ptr(), &mut surface) };
        if acquire != 0 || surface.iosurface.is_null() {
            return acquire;
        }
        self.width = surface.width;
        self.height = surface.height;
        let lock = unsafe { IOSurfaceLock(surface.iosurface, 0, ptr::null_mut()) };
        if lock != 0 {
            return lock;
        }
        let base = unsafe { IOSurfaceGetBaseAddress(surface.iosurface) }.cast::<u8>();
        if base.is_null() {
            unsafe { IOSurfaceUnlock(surface.iosurface, 0, ptr::null_mut()) };
            return -1;
        }
        let mut canvas = Canvas {
            base,
            width: surface.width,
            height: surface.height,
            stride: surface.bytes_per_row,
        };
        canvas.clear(0xff10_1724);
        canvas.rect(0, 0, surface.width, 18, 0xff4d_c3ff);
        let title = if self.show_session_chooser {
            "WAWONA SESSIONS"
        } else {
            "WAWONA MACHINES"
        };
        canvas.text(36, 48, 5, title, 0xfff4_f8ff);
        canvas.text(38, 100, 2, "MODE B OWN DISPLAY", 0xff8f_a7c4);

        let card_width = surface.width.saturating_sub(64);
        if self.show_session_chooser {
            let active_session = unsafe { wwn_igetty_ios_active_session() };
            for (index, session) in self.sessions.iter().take(6).enumerate() {
                let y = 150 + index as u32 * 94;
                let color = if active_session == session.id {
                    0xff21_5b83
                } else {
                    0xff1d_2b3d
                };
                canvas.rect(32, y, card_width, 76, color);
                canvas.text(52, y + 15, 3, &session.label, 0xffff_ffff);
                canvas.text(52, y + 49, 1, session_kind_label(session.kind), 0xffa9_bbd0);
            }
            if self.sessions.is_empty() {
                canvas.text(40, 170, 3, "NO SESSIONS", 0xffff_a65c);
            }
        } else {
            for (index, machine) in self.machines.iter().take(6).enumerate() {
                let y = 150 + index as u32 * 94;
                let color = if index == 0 { 0xff21_5b83 } else { 0xff1d_2b3d };
                canvas.rect(32, y, card_width, 76, color);
                canvas.text(52, y + 15, 3, &machine.name, 0xffff_ffff);
                canvas.text(52, y + 49, 1, &machine.kind, 0xffa9_bbd0);
            }
            if self.machines.is_empty() {
                canvas.text(40, 170, 3, "NO MACHINES", 0xffff_a65c);
            }
        }
        let footer_y = surface.height.saturating_sub(76);
        canvas.rect(32, footer_y, card_width, 48, 0xff21_5b83);
        canvas.text(
            52,
            footer_y + 14,
            2,
            if self.show_session_chooser {
                "MACHINES"
            } else {
                "SESSIONS"
            },
            0xffff_ffff,
        );
        unsafe { IOSurfaceUnlock(surface.iosurface, 0, ptr::null_mut()) };
        let present = unsafe {
            wwn_iomfb_present_iosurface(self.sink_ptr(), surface.iosurface, IomfbDamage::default())
        };
        if present == 0 {
            self.failed_presents = 0;
            tracing::info!(
                target: "wwn.modeb.desktop",
                op = "greeter-present",
                backing_id = surface.id,
                width = surface.width,
                height = surface.height,
                copy = "zero",
                "Rust Machines greeter presented"
            );
        } else {
            self.failed_presents = self.failed_presents.saturating_add(1);
        }
        present
    }

    fn refresh_sessions(&mut self) {
        self.sessions.clear();
        let count = unsafe { wwn_igetty_ios_session_count() };
        for index in 0..count {
            let mut id = 0;
            let mut kind = 0;
            let mut label = [0i8; 128];
            let rc = unsafe {
                wwn_igetty_ios_session_at(
                    index,
                    &mut id,
                    &mut kind,
                    label.as_mut_ptr(),
                    label.len(),
                )
            };
            if rc != 0 {
                continue;
            }
            let label = unsafe { CStr::from_ptr(label.as_ptr()) }
                .to_string_lossy()
                .into_owned();
            self.sessions.push(LogicalSession { id, kind, label });
        }
    }
}

static DESKTOP: OnceLock<Mutex<Desktop>> = OnceLock::new();

extern "C" fn present_logical_session(
    _context: *mut c_void,
    session_id: u32,
    kind: u8,
    label: *const c_char,
) -> i32 {
    let label = if label.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(label) }
            .to_string_lossy()
            .into_owned()
    };
    tracing::info!(
        target: "wwn.modeb.session",
        op = "switch",
        session_id,
        kind,
        label,
        "logical session selected"
    );
    0
}

fn session_kind_for_machine(machine: &Machine) -> u8 {
    let kind = machine.kind.to_ascii_lowercase();
    if kind.contains("virtual") || kind == "vm" {
        3
    } else if kind.contains("container") {
        4
    } else if machine.name.to_ascii_lowercase().contains("weston")
        || machine.name.to_ascii_lowercase().contains("niri")
    {
        5
    } else {
        2
    }
}

fn session_kind_label(kind: u8) -> &'static str {
    match kind {
        0 => "MACHINES GREETER",
        1 => "WAWONA ZSH PTY",
        2 => "NATIVE",
        3 => "JIT VIRTUAL MACHINE",
        4 => "JIT CONTAINER IN VM",
        5 => "COMPOSITOR",
        _ => "SESSION",
    }
}

fn desktop() -> &'static Mutex<Desktop> {
    DESKTOP.get_or_init(|| Mutex::new(Desktop::default()))
}

#[no_mangle]
pub unsafe extern "C" fn wwn_modeb_desktop_start(out_width: *mut u32, out_height: *mut u32) -> i32 {
    let mut state = desktop()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if state.sink != 0 {
        if !out_width.is_null() {
            *out_width = state.width;
        }
        if !out_height.is_null() {
            *out_height = state.height;
        }
        return 0;
    }
    let mut sink = ptr::null_mut();
    let result = wwn_iomfb_open(&mut sink);
    if result != 0 || sink.is_null() {
        tracing::error!(target: "wwn.modeb.desktop", op = "start", result, "IOMFB ownership failed");
        return if result == 0 { -1 } else { result };
    }
    state.sink = sink as usize;
    let igetty = wwn_igetty_ios_initialize(IgettyCallbacks {
        context: ptr::null_mut(),
        present_session: Some(present_logical_session),
    });
    if igetty != 0 {
        wwn_iomfb_restore(sink);
        wwn_iomfb_destroy(sink);
        *state = Desktop::default();
        return igetty;
    }
    state.refresh_sessions();
    state.phase = DesktopPhase::Greeter;
    let render = state.render_greeter();
    if !out_width.is_null() {
        *out_width = state.width;
    }
    if !out_height.is_null() {
        *out_height = state.height;
    }
    render
}

#[no_mangle]
pub unsafe extern "C" fn wwn_modeb_desktop_set_profiles_json(json: *const c_char) -> i32 {
    if json.is_null() {
        return -1;
    }
    let bytes = CStr::from_ptr(json).to_bytes();
    let Ok(machines) = serde_json::from_slice::<Vec<Machine>>(bytes) else {
        return -1;
    };
    let mut state = desktop()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    for session_id in std::mem::take(&mut state.machine_sessions) {
        wwn_igetty_ios_unregister_session(session_id);
    }
    state.machines = machines;
    let registrations = state
        .machines
        .iter()
        .map(|machine| {
            CString::new(machine.name.as_str()).map_or(0, |label| {
                wwn_igetty_ios_register_session(session_kind_for_machine(machine), label.as_ptr())
            })
        })
        .collect();
    state.machine_sessions = registrations;
    state.refresh_sessions();
    state.phase = DesktopPhase::Greeter;
    state.show_session_chooser = false;
    state.active_machine = None;
    state.render_greeter()
}

#[no_mangle]
pub unsafe extern "C" fn wwn_modeb_desktop_present_iosurface(
    iosurface: *mut c_void,
    width: u32,
    height: u32,
) -> i32 {
    let mut state = desktop()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if state.sink == 0 || iosurface.is_null() {
        return -1;
    }
    let result = wwn_iomfb_present_iosurface(
        state.sink_ptr(),
        iosurface,
        IomfbDamage {
            x: 0,
            y: 0,
            width,
            height,
        },
    );
    if result == 0 {
        state.failed_presents = 0;
    } else {
        state.failed_presents = state.failed_presents.saturating_add(1);
        if state.failed_presents >= 3 {
            state.phase = DesktopPhase::Recovering;
        }
    }
    result
}

#[no_mangle]
pub extern "C" fn wwn_modeb_desktop_handle_touch(x: f32, y: f32, ended: u8) -> i32 {
    if ended == 0 {
        return 0;
    }
    let mut state = desktop()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if state.phase != DesktopPhase::Greeter || x < 32.0 || x >= state.width as f32 - 32.0 {
        return 0;
    }
    if y >= state.height.saturating_sub(92) as f32 {
        unsafe { wwn_igetty_ios_adopt_live_text_sessions() };
        state.refresh_sessions();
        state.show_session_chooser = !state.show_session_chooser;
        return state.render_greeter();
    }
    if y < 150.0 {
        return 0;
    }
    let index = ((y - 150.0) / 94.0) as usize;
    if y > (150 + index as u32 * 94 + 76) as f32 {
        return 0;
    }
    if state.show_session_chooser {
        let Some(session) = state.sessions.get(index).filter(|_| index < 6) else {
            return 0;
        };
        let session_id = session.id;
        if unsafe { wwn_igetty_ios_switch_to(session_id) } != 0 {
            return 0;
        }
        if session.kind == 0 {
            state.show_session_chooser = false;
            return state.render_greeter();
        }
        state.phase = DesktopPhase::Session;
        state.active_machine = None;
        return 0;
    }
    if index >= state.machines.len().min(6) {
        return 0;
    }
    let Some(session_id) = state.machine_sessions.get(index).copied() else {
        return 0;
    };
    if unsafe { wwn_igetty_ios_switch_to(session_id) } != 0 {
        return 0;
    }
    state.phase = DesktopPhase::Session;
    state.active_machine = Some(state.machines[index].id.clone());
    (index + 1) as i32
}

#[no_mangle]
pub extern "C" fn wwn_modeb_desktop_recover_to_greeter() -> i32 {
    let mut state = desktop()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    state.phase = DesktopPhase::Recovering;
    state.active_machine = None;
    state.show_session_chooser = false;
    unsafe {
        wwn_igetty_ios_switch_to(0);
        wwn_igetty_ios_adopt_live_text_sessions();
    }
    state.refresh_sessions();
    state.phase = DesktopPhase::Greeter;
    state.render_greeter()
}

#[no_mangle]
pub extern "C" fn wwn_modeb_desktop_adopt_text_sessions() -> i32 {
    let mut state = desktop()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let count = unsafe { wwn_igetty_ios_adopt_live_text_sessions() };
    state.refresh_sessions();
    if state.phase == DesktopPhase::Greeter {
        let render = state.render_greeter();
        if render != 0 {
            return render;
        }
    }
    count as i32
}

#[no_mangle]
pub extern "C" fn wwn_modeb_desktop_phase() -> u32 {
    desktop()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .phase as u32
}

#[no_mangle]
pub extern "C" fn wwn_modeb_desktop_last_error() -> *const c_char {
    let state = desktop()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    unsafe { wwn_iomfb_last_error(state.sink_ptr()) }
}

#[no_mangle]
pub unsafe extern "C" fn wwn_modeb_desktop_restore() -> i32 {
    let mut state = desktop()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if state.sink == 0 {
        state.phase = DesktopPhase::Inactive;
        return 0;
    }
    let sink = state.sink_ptr();
    wwn_igetty_ios_shutdown();
    let result = wwn_iomfb_restore(sink);
    wwn_iomfb_destroy(sink);
    *state = Desktop::default();
    result
}

struct Canvas {
    base: *mut u8,
    width: u32,
    height: u32,
    stride: u32,
}

impl Canvas {
    fn clear(&mut self, color: u32) {
        self.rect(0, 0, self.width, self.height, color);
    }

    fn rect(&mut self, x: u32, y: u32, width: u32, height: u32, color: u32) {
        let max_x = x.saturating_add(width).min(self.width);
        let max_y = y.saturating_add(height).min(self.height);
        for py in y.min(self.height)..max_y {
            let row = unsafe { self.base.add((py * self.stride) as usize).cast::<u32>() };
            for px in x.min(self.width)..max_x {
                unsafe { row.add(px as usize).write(color) };
            }
        }
    }

    fn text(&mut self, x: u32, y: u32, scale: u32, text: &str, color: u32) {
        let mut cursor = x;
        for ch in text.to_ascii_uppercase().chars() {
            let glyph = glyph(ch);
            for (row, bits) in glyph.iter().enumerate() {
                for col in 0..5 {
                    if bits & (1 << (4 - col)) != 0 {
                        self.rect(
                            cursor + col * scale,
                            y + row as u32 * scale,
                            scale,
                            scale,
                            color,
                        );
                    }
                }
            }
            cursor = cursor.saturating_add(6 * scale);
            if cursor >= self.width.saturating_sub(5 * scale) {
                break;
            }
        }
    }
}

fn glyph(ch: char) -> [u8; 7] {
    match ch {
        'A' => [14, 17, 17, 31, 17, 17, 17],
        'B' => [30, 17, 17, 30, 17, 17, 30],
        'C' => [14, 17, 16, 16, 16, 17, 14],
        'D' => [30, 17, 17, 17, 17, 17, 30],
        'E' => [31, 16, 16, 30, 16, 16, 31],
        'F' => [31, 16, 16, 30, 16, 16, 16],
        'G' => [14, 17, 16, 23, 17, 17, 15],
        'H' => [17, 17, 17, 31, 17, 17, 17],
        'I' => [31, 4, 4, 4, 4, 4, 31],
        'J' => [7, 2, 2, 2, 18, 18, 12],
        'K' => [17, 18, 20, 24, 20, 18, 17],
        'L' => [16, 16, 16, 16, 16, 16, 31],
        'M' => [17, 27, 21, 21, 17, 17, 17],
        'N' => [17, 25, 21, 19, 17, 17, 17],
        'O' => [14, 17, 17, 17, 17, 17, 14],
        'P' => [30, 17, 17, 30, 16, 16, 16],
        'Q' => [14, 17, 17, 17, 21, 18, 13],
        'R' => [30, 17, 17, 30, 20, 18, 17],
        'S' => [15, 16, 16, 14, 1, 1, 30],
        'T' => [31, 4, 4, 4, 4, 4, 4],
        'U' => [17, 17, 17, 17, 17, 17, 14],
        'V' => [17, 17, 17, 17, 17, 10, 4],
        'W' => [17, 17, 17, 21, 21, 21, 10],
        'X' => [17, 17, 10, 4, 10, 17, 17],
        'Y' => [17, 17, 10, 4, 4, 4, 4],
        'Z' => [31, 1, 2, 4, 8, 16, 31],
        '0' => [14, 17, 19, 21, 25, 17, 14],
        '1' => [4, 12, 4, 4, 4, 4, 14],
        '2' => [14, 17, 1, 2, 4, 8, 31],
        '3' => [30, 1, 1, 14, 1, 1, 30],
        '4' => [2, 6, 10, 18, 31, 2, 2],
        '5' => [31, 16, 16, 30, 1, 1, 30],
        '6' => [14, 16, 16, 30, 17, 17, 14],
        '7' => [31, 1, 2, 4, 8, 8, 8],
        '8' => [14, 17, 17, 14, 17, 17, 14],
        '9' => [14, 17, 17, 15, 1, 1, 14],
        '-' => [0, 0, 0, 31, 0, 0, 0],
        '.' => [0, 0, 0, 0, 0, 12, 12],
        '/' => [1, 2, 2, 4, 8, 8, 16],
        _ => [0; 7],
    }
}

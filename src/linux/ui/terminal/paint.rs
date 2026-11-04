//! VT text buffer refresh and sixel/image blits.

use std::cell::{Cell, RefCell};
use std::fs::File;
use std::io::{ErrorKind, Write};
use std::rc::Rc;
use std::sync::Arc;

use gtk::prelude::*;
use gtk4 as gtk;

use crate::term::{TerminalImage, TerminalSession, TerminalSpan};

pub(super) fn write_pty(file: &mut File, bytes: &[u8]) {
    let mut sent = 0;
    let mut spins = 0;
    while sent < bytes.len() && spins < 32 {
        match file.write(&bytes[sent..]) {
            Ok(0) => spins += 1,
            Ok(n) => {
                sent += n;
                spins = 0;
            }
            Err(err)
                if err.kind() == ErrorKind::Interrupted || err.kind() == ErrorKind::WouldBlock =>
            {
                spins += 1;
            }
            Err(_) => return,
        }
    }
}



pub(super) struct PictureLayer {
    pub(super) images: Vec<TerminalImage>,
    pub(super) scrollback: i32,
}

pub(super) fn refresh(
    session: &TerminalSession,
    buffer: &gtk::TextBuffer,
    pictures: &RefCell<PictureLayer>,
    grid: &Cell<(u32, u32)>,
    back: &gtk::DrawingArea,
    front: &gtk::DrawingArea,
) {
    let lines = session.lines();
    let screen = grid.get().1 as i32;
    {
        let mut layer = pictures.borrow_mut();
        layer.scrollback = (lines.len() as i32 - screen).max(0);
        layer.images = session.images();
    }
    buffer.set_text("");
    let table = buffer.tag_table();
    for line in &lines {
        for span in &line.spans {
            insert_span(buffer, &table, span);
        }
        let mut iter = buffer.end_iter();
        buffer.insert(&mut iter, "\n");
    }
    back.queue_draw();
    front.queue_draw();
}

fn insert_span(buffer: &gtk::TextBuffer, table: &gtk::TextTagTable, span: &TerminalSpan) {
    if span.text.is_empty() {
        return;
    }
    let name = format!(
        "wtn-{:06x}-{:06x}-{}{}{}{}{}{}",
        span.fg & 0xFFFFFF,
        span.bg & 0xFFFFFF,
        u8::from(span.bold),
        u8::from(span.italic),
        u8::from(span.underline),
        u8::from(span.blink),
        u8::from(span.strike),
        if span.blink { "-blink" } else { "" }
    );
    let tag = if let Some(tag) = table.lookup(&name) {
        tag
    } else if let Some(tag) = buffer.create_tag(Some(&name), &[]) {
        tag.set_foreground(Some(&css(span.fg)));
        if span.bg != 0 {
            tag.set_background(Some(&css(span.bg)));
        }
        if span.bold {
            tag.set_weight(700);
        }
        if span.italic {
            tag.set_style(gtk::pango::Style::Italic);
        }
        if span.underline {
            tag.set_underline(gtk::pango::Underline::Single);
        }
        if span.strike {
            tag.set_strikethrough(true);
        }
        tag
    } else {
        let mut end = buffer.end_iter();
        buffer.insert(&mut end, &span.text);
        return;
    };
    let mut end = buffer.end_iter();
    buffer.insert_with_tags(&mut end, &span.text, &[&tag]);
}

pub(super) fn emit_pointer(
    session: &Arc<TerminalSession>,
    master: &Rc<RefCell<File>>,
    glyph: &Cell<(i32, i32)>,
    x: f64,
    y: f64,
    button: u32,
    pressed: bool,
    motion: bool,
) {
    let (cell_w, cell_h) = glyph.get();
    if cell_w < 1 || cell_h < 1 {
        return;
    }
    let col = (x as i32 / cell_w).clamp(0, 511) as u32 + 1;
    let row = (y as i32 / cell_h).clamp(0, 255) as u32 + 1;
    let vt_button = match button {
        2 => 1,
        3 => 2,
        _ => 0,
    };
    session.pointer(vt_button, col, row, pressed, motion);
    let reply = session.take_reply();
    if reply.is_empty() {
        return;
    }
    let mut file = master.borrow_mut();
    write_pty(&mut file, &reply);
}

pub(super) fn paste_from_clipboard(session: &Arc<TerminalSession>, master: &Rc<RefCell<Option<File>>>) {
    let Some(display) = gtk::gdk::Display::default() else {
        return;
    };
    let session = session.clone();
    let master = master.clone();
    display
        .clipboard()
        .read_text_async(None::<&gtk::gio::Cancellable>, move |result| {
            let Ok(Some(text)) = result else {
                return;
            };
            let bytes = session.encode_paste(text.to_string());
            if let Some(file) = master.borrow_mut().as_mut() {
                write_pty(file, &bytes);
            }
        });
}

fn css(rgb: u32) -> String {
    format!(
        "#{:02x}{:02x}{:02x}",
        (rgb >> 16) & 0xFF,
        (rgb >> 8) & 0xFF,
        rgb & 0xFF
    )
}

pub(super) fn wire_picture_canvas(
    canvas: &gtk::DrawingArea,
    pictures: &Rc<RefCell<PictureLayer>>,
    glyph: &Rc<Cell<(i32, i32)>>,
    scroll: &gtk::ScrolledWindow,
    behind: bool,
) {
    let pictures = pictures.clone();
    let glyph = glyph.clone();
    let scroll = scroll.clone();
    canvas.set_draw_func(move |_area, cr, _width, _height| {
        if behind {
            let _ = cr.set_source_rgb(0.0, 0.0, 0.0);
            let _ = cr.paint();
        }
        let (cell_w, cell_h) = glyph.get();
        if cell_w < 1 || cell_h < 1 {
            return;
        }
        let layer = pictures.borrow();
        let scroll_y = scroll.vadjustment().value();
        for image in &layer.images {
            let front = image.z >= 0;
            if behind == front {
                continue;
            }
            blit_picture(cr, image, cell_w, cell_h, layer.scrollback, scroll_y);
        }
    });
}

fn blit_picture(
    cr: &gtk::cairo::Context,
    image: &TerminalImage,
    cell_w: i32,
    cell_h: i32,
    scrollback: i32,
    scroll_y: f64,
) {
    let width = image.pixel_width as i32;
    let height = image.pixel_height as i32;
    if width < 1 || height < 1 {
        return;
    }
    let need = (width as usize)
        .saturating_mul(height as usize)
        .saturating_mul(4);
    if image.rgba.len() < need {
        return;
    }
    let Ok(stride) = gtk::cairo::Format::ARgb32.stride_for_width(image.pixel_width) else {
        return;
    };
    let data = rgba_to_cairo(
        &image.rgba,
        width as usize,
        height as usize,
        stride as usize,
    );
    let Ok(surface) = gtk::cairo::ImageSurface::create_for_data(
        data,
        gtk::cairo::Format::ARgb32,
        width,
        height,
        stride,
    ) else {
        return;
    };
    let x = image.column as f64 * cell_w as f64 + image.x_px as f64;
    let y = (scrollback + image.row) as f64 * cell_h as f64 + image.y_px as f64 - scroll_y;
    let dest_w = image.columns.max(1) as f64 * cell_w as f64;
    let dest_h = image.rows.max(1) as f64 * cell_h as f64;
    let _ = cr.save();
    let _ = cr.translate(x, y);
    let _ = cr.scale(dest_w / width as f64, dest_h / height as f64);
    let _ = cr.set_source_surface(&surface, 0.0, 0.0);
    let _ = cr.paint();
    let _ = cr.restore();
}

fn rgba_to_cairo(rgba: &[u8], width: usize, height: usize, stride: usize) -> Vec<u8> {
    let mut data = vec![0u8; stride.saturating_mul(height)];
    for y in 0..height {
        let src = y * width * 4;
        let dst = y * stride;
        for x in 0..width {
            let i = src + x * 4;
            let a = rgba[i + 3] as u32;
            let r = rgba[i] as u32 * a / 255;
            let g = rgba[i + 1] as u32 * a / 255;
            let b = rgba[i + 2] as u32 * a / 255;
            let pixel = (a << 24) | (r << 16) | (g << 8) | b;
            let o = dst + x * 4;
            data[o..o + 4].copy_from_slice(&pixel.to_ne_bytes());
        }
    }
    data
}

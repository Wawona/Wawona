#!/usr/bin/env bun
/**
 * Wawona macOS editable v4 — measured against refs/macOS.png
 *
 * Fixes from v3 critique:
 * - layers: wallpaper → light veil → glass chrome (not opaque slabs)
 * - title: traffic + mark + title/subtitle | segmented pill nav | search + gear
 * - sidebar: Library / Favorites / Tags / Platform Targets + Transfers card
 * - rows: landscape thumbs, status pills, play/more — not radar badges
 * - inspector: hero, Open/Pause/Stop, 4 tabs, specs, storage, tags, pinned, Relay
 */
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const refs = join(root, "refs");
const assets = join(root, "assets");
const thumbs = join(assets, "thumbs");

const cmd = (command, params = {}) => ({ command, params });
const steps = [];

/**
 * FigCraft: missing/invalid fill → opaque WHITE.
 * 8-digit #RRGGBBAA is unreliable; #00000000 often reads as white on canvas.
 * Use fill:"none" for empty, or fills:[{type:"solid",color,opacity}] for glass.
 */
function parseHex(hex) {
  if (typeof hex !== "string" || !hex.startsWith("#")) return null;
  if (hex.length === 7) return { color: hex.toUpperCase(), opacity: 1 };
  if (hex.length === 9) {
    return {
      color: hex.slice(0, 7).toUpperCase(),
      opacity: Math.round((parseInt(hex.slice(7, 9), 16) / 255) * 1000) / 1000,
    };
  }
  return null;
}

function normalizeProps(props = {}) {
  const out = { ...props };
  for (const key of ["fill", "stroke"]) {
    const v = out[key];
    if (v == null || v === "transparent" || v === "#00000000") {
      out[key] = "none";
      continue;
    }
    const parsed = parseHex(v);
    if (!parsed) continue;
    if (key === "fill") {
      if (parsed.opacity >= 0.999) {
        out.fill = parsed.color;
      } else if (parsed.opacity <= 0.02) {
        out.fill = "none";
      } else {
        delete out.fill;
        out.fills = [{ type: "solid", color: parsed.color, opacity: parsed.opacity }];
      }
    } else {
      // strokes: no reliable alpha — use solid rim at readable weight
      out.stroke = parsed.opacity < 0.2 ? "#6E6890" : parsed.color;
    }
  }
  return out;
}

const add = (...xs) => {
  for (const s of xs) {
    if (
      s?.command === "node.create" ||
      s?.command === "frame.create"
    ) {
      if (s.params?.props) s.params.props = normalizeProps(s.params.props);
    }
    steps.push(s);
  }
};

// Tokens sampled from refs/macOS.png (valley-glass)
// Keep 8-digit forms; normalizeProps expands them to solid+opacity paints.
const T = {
  glass: "#1A2038A8",
  glassSide: "#1C2440B8",
  glassInsp: "#1A223CD0",
  glassHi: "#2A3458C8",
  glassRow: "#A8B4FF18",
  glassRowSel: "#0078F840",
  glassPill: "#C8B0E030",
  glassPillOn: "#E8D0F060",
  fg: "#F5F7FF",
  muted: "#A8B0C8",
  border: "#6E6890", // solid rim light (8-digit alpha strokes are unreliable)
  primary: "#0078F8",
  onPrimary: "#FFFFFF",
  running: "#38E078",
  stopped: "#8E96A8",
  ready: "#48C8F8",
  trafficR: "#FF5F57",
  trafficY: "#FEBC2E",
  trafficG: "#28C840",
  veil: "#1A104830",
  mark: "#0078F8",
  selectStroke: "#3A90DF",
};

// Shape language measured vs refs/macOS.png (1512×982 align)
// concept: window ~22, machine cards ~14, thumbs ~10–12, search/status stadium,
// CTA ~14–stadium, side selection ~10, inspector hero squircle ~12
const R = {
  window: 22,
  panel: 0, // flush panels; window clips top corners
  card: 14,
  row: 14,
  thumb: 10,
  hero: 12,
  control: 10,
  side: 10,
  search: 999, // stadium
  pill: 999,
  cta: 14,
  chip: 8,
  track: 999,
  traffic: 12,
  smooth: 0.6, // continuous corner where supported
};

function text(parent, characters, props, name) {
  return cmd("node.create", {
    type: "text",
    parent: { $step: parent },
    text: characters,
    name: name || String(characters).slice(0, 28),
    props,
  });
}

function frame(parent, name, props = {}) {
  return cmd("node.create", {
    type: "frame",
    parent: typeof parent === "number" ? { $step: parent } : parent,
    name,
    // Default: no fill (NOT #00000000 — that becomes white in FigCraft)
    props: { fill: "none", ...props },
  });
}

const platforms = [
  { id: "macos", label: "macOS", ref: "macOS.png", w: 1512, h: 1008 },
  { id: "ios", label: "iOS", ref: "iOS.png", w: 1600, h: 900 },
  { id: "ipados", label: "iPadOS", ref: "iPadOS.png", w: 1400, h: 1050 },
  { id: "android", label: "Android", ref: "Android_Tablet.png", w: 1400, h: 900 },
  { id: "linux", label: "Linux", ref: "Linux.png", w: 1400, h: 900 },
  { id: "web", label: "Web", ref: "Web_DOM.png", w: 1400, h: 900 },
  { id: "windows", label: "Windows", ref: "Windows.png", w: 1400, h: 900 },
  { id: "visionos", label: "visionOS", ref: "visionOS.png", w: 1400, h: 900 },
  { id: "tvos", label: "tvOS", ref: "tvOS_Apple_TV.png", w: 1400, h: 900 },
  { id: "watchos", label: "watchOS", ref: "Apple_Watch.png", w: 1400, h: 900 },
  { id: "wearos", label: "Wear OS", ref: "Wear_OS.png", w: 1400, h: 900 },
  { id: "asteroidos", label: "AsteroidOS", ref: "AsteroidOS_Oppo_Watch.png", w: 1400, h: 900 },
  { id: "android-xr", label: "Android XR (extra)", ref: "Android_XR.png", w: 1400, h: 900 },
];

// ========== file ==========
add(cmd("file.rename", { name: "Wawona ALL_TARGETS UI v4" }));
add(cmd("page.rename", { name: "00 Concept plates" }));
add(cmd("page.setBackground", { color: "#0A0812" }));
add(
  cmd("node.create", {
    type: "text",
    x: 0,
    y: -36,
    text: "Approved comps = pixel truth. Editable macOS on page 02 (v4 layers).",
    name: "plates intro",
    props: { fontSize: 14, fill: "#9AA0B8" },
  }),
);

let x = 0;
let y = 0;
let col = 0;
const gap = 80;
for (const p of platforms) {
  add(
    cmd("node.create", {
      type: "frame",
      x,
      y,
      width: p.w,
      height: p.h + 36,
      name: `${p.label} · concept`,
      props: {
        fill: "#12101C",
        layout: "vertical",
        gap: 8,
        padding: [8, 8, 8, 8],
        cornerRadius: 16,
        stroke: "#FFFFFF22",
        strokeWeight: 1,
      },
    }),
  );
  const board = steps.length - 1;
  add(
    text(board, `${p.id}  ·  ${p.label}  ·  concept plate`, {
      fontSize: 12,
      fill: "#9AA0B8",
    }),
  );
  add(
    cmd("file.placeImage", {
      path: join(refs, p.ref),
      parent: { $step: board },
      width: p.w - 16,
      name: `plate/${p.id}`,
      mode: "fit",
    }),
  );
  col += 1;
  if (col >= 2) {
    col = 0;
    x = 0;
    y += p.h + 36 + gap;
  } else {
    x += p.w + gap;
  }
}

// ========== Foundations ==========
add(cmd("page.add", { name: "01 Foundations" }));
add(cmd("page.select", { index: 1 }));
add(cmd("page.setBackground", { color: "#0A0812" }));
add(
  cmd("variable.createCollection", {
    name: "Wawona colours",
    modes: ["Dark", "Light"],
  }),
);
const coll = steps.length - 1;
for (const [name, dark, light] of [
  ["color/bg", "#182030", "#F4F6FB"],
  ["color/glass", "#1C2440", "#FFFFFFE6"],
  ["color/fg", T.fg, "#1A1A2E"],
  ["color/muted", T.muted, "#5B6168"],
  ["color/primary", T.primary, "#007AFF"],
  ["color/running", T.running, T.running],
  ["color/border", T.border, "#D0D5E0"],
]) {
  add(
    cmd("variable.create", {
      collection: { $step: coll },
      name,
      type: "color",
      values: { Dark: dark, Light: light },
    }),
  );
}
add(
  cmd("node.create", {
    type: "frame",
    x: 0,
    y: 0,
    width: 720,
    height: 360,
    name: "Token board",
    props: {
      fill: "#12101C",
      layout: "vertical",
      gap: 14,
      padding: 24,
      cornerRadius: 16,
    },
  }),
);
const board = steps.length - 1;
add(text(board, "Valley-glass tokens (v4)", { fontSize: 22, fontStyle: "Bold", fill: T.fg }));
add(
  text(board, "Match macOS.png: translucent charcoal-violet over landscape. Neon status.", {
    fontSize: 12,
    fill: T.muted,
    sizingH: "fill",
  }),
);
add(frame(board, "Swatches", { layout: "horizontal", gap: 12, sizingH: "fill" }));
const sw = steps.length - 1;
for (const [label, hex] of [
  ["glass", "#1C2440"],
  ["primary", T.primary],
  ["running", T.running],
  ["fg", T.fg],
  ["muted", T.muted],
]) {
  add(
    frame(sw, label, {
      layout: "vertical",
      gap: 8,
      padding: 8,
      fill: T.glassHi,
      cornerRadius: 12,
    }),
  );
  const cell = steps.length - 1;
  add(
    cmd("node.create", {
      type: "rectangle",
      parent: { $step: cell },
      width: 72,
      height: 48,
      props: { fill: hex, cornerRadius: 8 },
    }),
  );
  add(text(cell, label, { fontSize: 11, fill: T.muted }));
}

// ========== macOS editable ==========
add(cmd("page.add", { name: "02 macOS editable" }));
add(cmd("page.select", { index: 2 }));
add(cmd("page.setBackground", { color: "#05040A" }));
add(
  cmd("node.create", {
    type: "text",
    x: 0,
    y: -32,
    text: "v4 · layers fixed · measured against macOS.png (wallpaper → veil → glass → chrome)",
    name: "edit intro",
    props: { fontSize: 13, fill: "#9AA0B8" },
  }),
);

// Trace plate (concept underlay for eyeballing)
add(
  cmd("node.create", {
    type: "frame",
    x: 1600,
    y: 0,
    width: 1512,
    height: 982,
    name: "macOS · concept underlay",
    props: { fill: "#000000", clip: true, cornerRadius: R.window },
  }),
);
const under = steps.length - 1;
add(
  cmd("file.placeImage", {
    path: join(refs, "macOS.png"),
    parent: { $step: under },
    x: 0,
    y: 0,
    width: 1512,
    height: 982,
    name: "concept",
    mode: "fill",
  }),
);

// Editable window
add(
  cmd("frame.create", {
    preset: 'MacBook Pro 14"',
    x: 0,
    y: 0,
    name: "macOS · Machines",
    props: {
      fill: "#121828",
      layout: null,
      clip: true,
      cornerRadius: R.window,
      cornerSmoothing: R.smooth,
    },
  }),
);
const win = steps.length - 1;

// L0 wallpaper
add(
  cmd("file.placeImage", {
    path: join(assets, "wawona-valley-wallpaper.png"),
    parent: { $step: win },
    x: 0,
    y: 0,
    width: 1512,
    height: 982,
    name: "L0 wallpaper",
    mode: "fill",
  }),
);
// L1 light veil — keep landscape readable through glass
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: win },
    name: "L1 veil",
    x: 0,
    y: 0,
    width: 1512,
    height: 982,
    props: { fill: T.veil, absolute: true },
  }),
);

// Column splits measured from concept seams (wider side + inspector than v3)
const TITLE_H = 58;
const SIDE_W = 268;
const INSP_W = 372;
const CAT_X = SIDE_W;
const CAT_W = 1512 - SIDE_W - INSP_W;
const ROW_THUMB = 40; // concept thumbs ~40; was 52 → 100px default row trap

// —— Title bar (absolute children) ——
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: win },
    name: "L2 Title bar",
    x: 0,
    y: 0,
    width: 1512,
    height: TITLE_H,
    props: {
      absolute: true,
      fill: T.glassSide,
      stroke: T.border,
      strokeWeight: 1,
      layout: null,
      clip: true,
    },
  }),
);
const titleBar = steps.length - 1;

// Brand cluster left
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: titleBar },
    name: "Brand",
    x: 14,
    y: 12,
    width: 340,
    height: 34,
    props: {
      absolute: true,
      layout: "horizontal",
      gap: 10,
      crossAlign: "center",
      fill: "#00000000",
    },
  }),
);
const brand = steps.length - 1;
add(frame(brand, "Traffic", { layout: "horizontal", gap: 7, crossAlign: "center" }));
const traffic = steps.length - 1;
for (const c of [T.trafficR, T.trafficY, T.trafficG]) {
  add(
    cmd("node.create", {
      type: "ellipse",
      parent: { $step: traffic },
      width: R.traffic,
      height: R.traffic,
      props: { fill: c },
    }),
  );
}
add(
  cmd("node.create", {
    type: "ellipse",
    parent: { $step: brand },
    width: 22,
    height: 22,
    name: "mark",
    props: { fill: T.mark },
  }),
);
add(
  frame(brand, "Titles", {
    layout: "vertical",
    gap: 0,
  }),
);
const titlesBrand = steps.length - 1;
add(text(titlesBrand, "Wawona Compositor", { fontSize: 13, fontStyle: "SemiBold", fill: T.fg }));
add(text(titlesBrand, "Universal Wayland Compositor", { fontSize: 10, fill: T.muted }));

// Centered segmented pill (Machines / Sessions / Images / Runtimes)
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: titleBar },
    name: "Segmented nav",
    x: 500,
    y: 11,
    width: 492,
    height: 36,
    props: {
      absolute: true,
      layout: "horizontal",
      gap: 2,
      padding: [3, 4, 3, 4],
      cornerRadius: R.pill,
      fill: T.glassPill,
      stroke: T.border,
      strokeWeight: 1,
      crossAlign: "center",
      mainAlign: "center",
    },
  }),
);
const pill = steps.length - 1;
for (const [label, on] of [
  ["Machines", true],
  ["Sessions", false],
  ["Images", false],
  ["Runtimes", false],
]) {
  add(
    frame(pill, label, {
      layout: "horizontal",
      padding: [0, 16, 0, 16],
      height: 28,
      cornerRadius: R.pill,
      fill: on ? T.glassPillOn : "#00000000",
      crossAlign: "center",
      mainAlign: "center",
    }),
  );
  const t = steps.length - 1;
  add(
    text(t, label, {
      fontSize: 12,
      fontStyle: on ? "SemiBold" : "Regular",
      fill: on ? T.fg : T.muted,
    }),
  );
}

// Search right
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: titleBar },
    name: "Search",
    x: 1208,
    y: 13,
    width: 220,
    height: 32,
    props: {
      absolute: true,
      layout: "horizontal",
      padding: [0, 14, 0, 14],
      cornerRadius: R.search,
      fill: T.glassRow,
      stroke: T.border,
      strokeWeight: 1,
      crossAlign: "center",
      gap: 8,
    },
  }),
);
const search = steps.length - 1;
add(text(search, "⌕", { fontSize: 12, fill: T.muted }));
add(text(search, "Search", { fontSize: 12, fill: T.muted }));
add(frame(search, "grow", { sizingH: "fill", height: 1, fill: "#00000000" }));
add(text(search, "⌘F", { fontSize: 11, fill: T.muted }));

// Gear — rounded square matching search height
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: titleBar },
    name: "Settings gear",
    x: 1440,
    y: 13,
    width: 32,
    height: 32,
    props: {
      absolute: true,
      layout: "horizontal",
      mainAlign: "center",
      crossAlign: "center",
      cornerRadius: R.control,
      fill: T.glassRow,
      stroke: T.border,
      strokeWeight: 1,
    },
  }),
);
const gear = steps.length - 1;
add(text(gear, "⚙︎", { fontSize: 14, fill: T.fg }));

// —— Sidebar ——
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: win },
    name: "L2 Sidebar",
    x: 0,
    y: TITLE_H,
    width: SIDE_W,
    height: 982 - TITLE_H,
    props: {
      absolute: true,
      fill: T.glassSide,
      stroke: T.border,
      strokeWeight: 1,
      layout: null,
      clip: true,
    },
  }),
);
const side = steps.length - 1;
// Scroll body (library…) absolute; Transfers pinned to bottom
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: side },
    name: "Sidebar body",
    x: 10,
    y: 10,
    width: SIDE_W - 20,
    height: 982 - TITLE_H - 108,
    props: {
      absolute: true,
      fill: "#00000000",
      layout: "vertical",
      gap: 3,
      padding: 0,
    },
  }),
);
const sideBody = steps.length - 1;

function sideLabel(parent, s) {
  add(text(parent, s, { fontSize: 10, fill: T.muted }));
}
function sideRow(parent, label, badge, on, dot) {
  add(
    frame(parent, label, {
      layout: "horizontal",
      gap: 8,
      crossAlign: "center",
      padding: [0, 10, 0, 10],
      height: 28,
      cornerRadius: R.side,
      fill: on ? T.glassRowSel : T.glassRow,
      stroke: on ? T.selectStroke : "#00000000",
      strokeWeight: on ? 1.5 : 0,
      sizingH: "fill",
      sizingV: "fixed",
    }),
  );
  const item = steps.length - 1;
  if (dot) {
    add(
      cmd("node.create", {
        type: "ellipse",
        parent: { $step: item },
        width: 7,
        height: 7,
        props: { fill: typeof dot === "string" ? dot : T.muted },
      }),
    );
  }
  add(
    text(item, label, {
      fontSize: 12,
      fontStyle: on ? "SemiBold" : "Regular",
      fill: T.fg,
    }),
  );
  add(frame(item, "grow", { sizingH: "fill", height: 1, fill: "#00000000" }));
  if (badge !== "" && badge != null) {
    add(text(item, String(badge), { fontSize: 11, fill: T.muted }));
  }
}

sideLabel(sideBody, "Library");
sideRow(sideBody, "Machines", "5", true, T.primary);
sideRow(sideBody, "Sessions", "1", false, T.muted);
sideRow(sideBody, "Images", "", false, T.muted);
sideRow(sideBody, "Runtimes", "", false, T.muted);
sideLabel(sideBody, "Favorites");
sideRow(sideBody, "Pinned", "2", false, null);
sideRow(sideBody, "Recent", "", false, null);
sideLabel(sideBody, "Tags");
sideRow(sideBody, "Work", "2", false, "#5AC8FA");
sideRow(sideBody, "Dev", "3", false, "#BF5AF2");
sideRow(sideBody, "Test", "1", false, "#34C759");
sideLabel(sideBody, "Platform Targets");
sideRow(sideBody, "macOS", "", true, T.primary);
sideRow(sideBody, "iOS / iPadOS", "", false, T.muted);
sideRow(sideBody, "Android", "", false, T.muted);
sideRow(sideBody, "WASM / Web", "", false, T.muted);

add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: side },
    name: "Transfers",
    x: 10,
    y: 982 - TITLE_H - 100,
    width: SIDE_W - 20,
    height: 88,
    props: {
      absolute: true,
      layout: "vertical",
      gap: 4,
      padding: 9,
      cornerRadius: R.card,
      fill: T.glassHi,
      stroke: T.border,
      strokeWeight: 1,
    },
  }),
);
const xfer = steps.length - 1;
add(
  frame(xfer, "xfer head", {
    layout: "horizontal",
    mainAlign: "spaceBetween",
    sizingH: "fill",
  }),
);
const xh = steps.length - 1;
add(text(xh, "Transfers", { fontSize: 10, fill: T.muted }));
add(text(xh, "✕", { fontSize: 10, fill: T.muted }));
add(text(xfer, "NixOS vm.qcow2", { fontSize: 12, fontStyle: "SemiBold", fill: T.fg }));
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: xfer },
    name: "track",
    width: SIDE_W - 20 - 18,
    height: 5,
    props: { fill: "#FFFFFF22", cornerRadius: R.track, sizingH: "fill" },
  }),
);
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: xfer },
    name: "fill",
    width: Math.round((SIDE_W - 38) * 0.57),
    height: 5,
    props: { fill: T.primary, cornerRadius: R.track },
  }),
);
add(text(xfer, "3.2 / 5.6 GB · 12.4 MB/s", { fontSize: 10, fill: T.muted }));

// —— Catalog (more transparent so wallpaper reads) ——
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: win },
    name: "L2 Catalog",
    x: CAT_X,
    y: TITLE_H,
    width: CAT_W,
    height: 982 - TITLE_H,
    props: {
      absolute: true,
      fill: "#15203866",
      layout: "vertical",
      gap: 6,
      padding: [14, 14, 14, 14],
    },
  }),
);
const catalog = steps.length - 1;

add(
  frame(catalog, "Catalog header", {
    layout: "horizontal",
    mainAlign: "spaceBetween",
    crossAlign: "center",
    sizingH: "fill",
    sizingV: "hug",
    padding: [0, 0, 6, 0],
  }),
);
const chead = steps.length - 1;
add(
  frame(chead, "Titles", {
    layout: "vertical",
    gap: 3,
    sizingH: "fill",
    sizingV: "hug",
  }),
);
const titles = steps.length - 1;
add(text(titles, "Machines", { fontSize: 24, fontStyle: "Bold", fill: T.fg }));
add(text(titles, "5 machines · 2 pinned · 1 running", { fontSize: 12, fill: T.muted }));
add(
  frame(chead, "Header actions", {
    layout: "horizontal",
    gap: 8,
    crossAlign: "center",
    sizingH: "hug",
    sizingV: "hug",
  }),
);
const had = steps.length - 1;
add(
  frame(had, "View toggle", {
    layout: "horizontal",
    gap: 2,
    padding: [3, 3, 3, 3],
    cornerRadius: R.pill,
    fill: T.glassRow,
    stroke: T.border,
    strokeWeight: 1,
    sizingH: "hug",
    sizingV: "hug",
  }),
);
const vt = steps.length - 1;
for (const [label, on] of [
  ["≡", true],
  ["▦", false],
]) {
  add(
    frame(vt, label, {
      layout: "horizontal",
      mainAlign: "center",
      crossAlign: "center",
      width: 28,
      height: 26,
      cornerRadius: R.pill,
      fill: on ? T.glassPillOn : "#00000000",
    }),
  );
  const b = steps.length - 1;
  add(text(b, label, { fontSize: 12, fill: on ? T.fg : T.muted }));
}
// Split + New control (plus | chevron) like concept
add(
  frame(had, "New split", {
    layout: "horizontal",
    gap: 0,
    height: 32,
    cornerRadius: R.control,
    fill: T.primary,
    clip: true,
    crossAlign: "center",
    sizingH: "hug",
    sizingV: "fixed",
  }),
);
const neuWrap = steps.length - 1;
add(
  frame(neuWrap, "New", {
    layout: "horizontal",
    mainAlign: "center",
    crossAlign: "center",
    padding: [0, 12, 0, 12],
    height: 32,
    fill: "#00000000",
  }),
);
const neu = steps.length - 1;
add(text(neu, "+", { fontSize: 16, fontStyle: "SemiBold", fill: T.onPrimary }));
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: neuWrap },
    name: "split",
    width: 1,
    height: 18,
    props: { fill: "#FFFFFF44" },
  }),
);
add(
  frame(neuWrap, "chevron", {
    layout: "horizontal",
    mainAlign: "center",
    crossAlign: "center",
    width: 28,
    height: 32,
    fill: "#00000000",
  }),
);
const ch = steps.length - 1;
add(text(ch, "▾", { fontSize: 11, fill: T.onPrimary }));

const machines = [
  {
    name: "Sample Linux VM",
    kind: "Virtual Machine · NixOS",
    status: "Running",
    time: "12m",
    color: T.running,
    thumb: "vm.png",
    selected: true,
    action: "⏹",
  },
  {
    name: "Dev Container",
    kind: "Container · OCI",
    status: "Stopped",
    time: "",
    color: T.stopped,
    thumb: "container.png",
    selected: false,
    action: "▶",
  },
  {
    name: "Native Shell",
    kind: "Native Shell · Local",
    status: "Running",
    time: "3m",
    color: T.running,
    thumb: "shell.png",
    selected: false,
    action: "⏹",
  },
  {
    name: "Relay Wasm",
    kind: "Native Shell · WASI",
    status: "Ready",
    time: "",
    color: T.ready,
    thumb: "wasm.png",
    selected: false,
    action: "▶",
  },
  {
    name: "Term",
    kind: "Native Shell · Local",
    status: "Stopped",
    time: "",
    color: T.stopped,
    thumb: "term.png",
    selected: false,
    action: "▶",
  },
];

for (const m of machines) {
  // Concept cards ~56–64px; hug height (FigCraft defaults missing height → fixed 100)
  add(
    frame(catalog, m.name, {
      layout: "horizontal",
      gap: 10,
      padding: [8, 12, 8, 12],
      crossAlign: "center",
      sizingH: "fill",
      sizingV: "hug",
      fill: m.selected ? T.glassRowSel : T.glassRow,
      stroke: m.selected ? T.selectStroke : T.border,
      strokeWeight: m.selected ? 2 : 1,
      cornerRadius: R.row,
      cornerSmoothing: R.smooth,
    }),
  );
  const row = steps.length - 1;
  // Rounded clipped thumb (concept: ~40 soft squircle)
  add(
    frame(row, `${m.name} thumb wrap`, {
      width: ROW_THUMB,
      height: ROW_THUMB,
      cornerRadius: R.thumb,
      cornerSmoothing: R.smooth,
      clip: true,
      fill: "#00000044",
      sizingV: "fixed",
      sizingH: "fixed",
    }),
  );
  const thumbWrap = steps.length - 1;
  add(
    cmd("file.placeImage", {
      path: join(thumbs, m.thumb),
      parent: { $step: thumbWrap },
      width: ROW_THUMB,
      height: ROW_THUMB,
      name: `${m.name} thumb`,
      mode: "fill",
    }),
  );
  add(
    frame(row, "meta", {
      layout: "vertical",
      gap: 2,
      sizingH: "fill",
      sizingV: "hug",
    }),
  );
  const meta = steps.length - 1;
  add(text(meta, m.name, { fontSize: 13, fontStyle: "SemiBold", fill: T.fg }));
  add(text(meta, m.kind, { fontSize: 11, fill: T.muted }));

  // Status capsule + separate time (concept splits Running pill from 12m)
  add(
    frame(row, "status cluster", {
      layout: "horizontal",
      gap: 8,
      crossAlign: "center",
      sizingV: "hug",
    }),
  );
  const sc = steps.length - 1;
  add(
    frame(sc, "status", {
      layout: "horizontal",
      gap: 6,
      padding: [0, 10, 0, 10],
      height: 22,
      crossAlign: "center",
      cornerRadius: R.pill,
      fill: m.color + "28",
      stroke: m.color + "55",
      strokeWeight: 1,
      sizingV: "fixed",
    }),
  );
  const st = steps.length - 1;
  add(
    cmd("node.create", {
      type: "ellipse",
      parent: { $step: st },
      width: 7,
      height: 7,
      props: { fill: m.color },
    }),
  );
  add(text(st, m.status, { fontSize: 11, fill: T.fg }));
  if (m.time) {
    add(text(sc, m.time, { fontSize: 11, fill: T.muted }));
  }

  add(
    frame(row, "row actions", {
      layout: "horizontal",
      gap: 6,
      crossAlign: "center",
      sizingV: "hug",
    }),
  );
  const ra = steps.length - 1;
  for (const [lab, glyph] of [
    ["play", m.action],
    ["more", "···"],
  ]) {
    add(
      frame(ra, lab, {
        layout: "horizontal",
        mainAlign: "center",
        crossAlign: "center",
        width: 26,
        height: 26,
        cornerRadius: R.pill, // circular controls
        fill: T.glassHi,
        stroke: T.border,
        strokeWeight: 1,
        sizingV: "fixed",
        sizingH: "fixed",
      }),
    );
    const b = steps.length - 1;
    add(text(b, glyph, { fontSize: 11, fill: T.fg }));
  }
}

// —— Inspector (concept: square hero + title, one CTA row, grouped specs) ——
const INSP_PAD = 12;
const INSP_INNER = INSP_W - INSP_PAD * 2;
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: win },
    name: "L2 Inspector",
    x: 1512 - INSP_W,
    y: TITLE_H,
    width: INSP_W,
    height: 982 - TITLE_H,
    props: {
      absolute: true,
      fill: T.glassInsp,
      stroke: T.border,
      strokeWeight: 1,
      layout: "vertical",
      gap: 10,
      padding: [INSP_PAD, INSP_PAD, INSP_PAD, INSP_PAD],
    },
  }),
);
const insp = steps.length - 1;

// Head: square hero | titles + running
const HERO = 88;
add(
  frame(insp, "insp head", {
    layout: "horizontal",
    gap: 12,
    crossAlign: "center",
    sizingH: "fill",
    sizingV: "hug",
  }),
);
const ih = steps.length - 1;
add(
  frame(ih, "hero wrap", {
    width: HERO,
    height: HERO,
    cornerRadius: R.hero,
    cornerSmoothing: R.smooth,
    clip: true,
    fill: "#00000044",
    sizingH: "fixed",
    sizingV: "fixed",
  }),
);
const heroWrap = steps.length - 1;
add(
  cmd("file.placeImage", {
    path: join(thumbs, "inspector-hero.png"),
    parent: { $step: heroWrap },
    width: HERO,
    height: HERO,
    name: "hero",
    mode: "fill",
  }),
);
add(
  frame(ih, "insp titles", {
    layout: "vertical",
    gap: 6,
    sizingH: "fill",
    sizingV: "hug",
  }),
);
const it = steps.length - 1;
add(text(it, "Sample Linux VM", { fontSize: 15, fontStyle: "Bold", fill: T.fg }));
add(text(it, "Virtual Machine · NixOS", { fontSize: 11, fill: T.muted }));
add(
  frame(it, "Running pill", {
    layout: "horizontal",
    gap: 5,
    padding: [0, 9, 0, 9],
    height: 22,
    cornerRadius: R.pill,
    fill: "#38E07833",
    crossAlign: "center",
    sizingV: "fixed",
  }),
);
const rp = steps.length - 1;
add(
  cmd("node.create", {
    type: "ellipse",
    parent: { $step: rp },
    width: 7,
    height: 7,
    props: { fill: T.running },
  }),
);
add(text(rp, "Running", { fontSize: 11, fill: T.running }));
add(text(it, "Since 11:42 AM (12m)", { fontSize: 10, fill: T.muted }));

// Concept: one horizontal action strip
add(
  frame(insp, "Primary actions", {
    layout: "horizontal",
    gap: 6,
    sizingH: "fill",
    sizingV: "hug",
    crossAlign: "center",
  }),
);
const pact = steps.length - 1;
add(
  frame(pact, "Open Session", {
    layout: "horizontal",
    mainAlign: "center",
    crossAlign: "center",
    gap: 6,
    padding: [0, 12, 0, 12],
    height: 32,
    cornerRadius: R.cta,
    fill: T.primary,
    sizingH: "fill",
    sizingV: "fixed",
  }),
);
const open = steps.length - 1;
add(text(open, "▣", { fontSize: 12, fill: T.onPrimary }));
add(text(open, "Open Session", { fontSize: 12, fontStyle: "SemiBold", fill: T.onPrimary }));
for (const label of ["Pause", "Stop"]) {
  add(
    frame(pact, label, {
      layout: "horizontal",
      mainAlign: "center",
      crossAlign: "center",
      padding: [0, 8, 0, 8],
      height: 32,
      cornerRadius: R.control,
      fill: T.glassHi,
      stroke: T.border,
      strokeWeight: 1,
      sizingH: "hug",
      sizingV: "fixed",
    }),
  );
  const b = steps.length - 1;
  add(text(b, label, { fontSize: 12, fill: T.fg }));
}
add(
  frame(pact, "···", {
    layout: "horizontal",
    mainAlign: "center",
    crossAlign: "center",
    width: 32,
    height: 32,
    cornerRadius: R.control,
    fill: T.glassHi,
    stroke: T.border,
    strokeWeight: 1,
    sizingH: "fixed",
    sizingV: "fixed",
  }),
);
const moreInsp = steps.length - 1;
add(text(moreInsp, "···", { fontSize: 12, fill: T.fg }));

// Tabs as stadium track (concept segmented)
add(
  frame(insp, "Tabs", {
    layout: "horizontal",
    gap: 2,
    padding: [3, 3, 3, 3],
    sizingH: "fill",
    sizingV: "hug",
    cornerRadius: R.pill,
    fill: T.glassRow,
    stroke: T.border,
    strokeWeight: 1,
    crossAlign: "center",
  }),
);
const tabs = steps.length - 1;
for (const [label, on] of [
  ["Overview", true],
  ["Config", false],
  ["Resources", false],
  ["Logs", false],
]) {
  add(
    frame(tabs, label, {
      layout: "horizontal",
      mainAlign: "center",
      crossAlign: "center",
      padding: [0, 8, 0, 8],
      height: 24,
      cornerRadius: R.pill,
      fill: on ? T.glassPillOn : "none",
      sizingH: "fill",
      sizingV: "fixed",
    }),
  );
  const t = steps.length - 1;
  add(
    text(t, label, {
      fontSize: 10,
      fontStyle: on ? "SemiBold" : "Regular",
      fill: on ? T.fg : T.muted,
    }),
  );
}

// Specs: one grouped surface with inset dividers (not separate cards)
add(
  frame(insp, "Specs group", {
    layout: "vertical",
    gap: 0,
    sizingH: "fill",
    sizingV: "hug",
    cornerRadius: R.card,
    fill: T.glassHi,
    stroke: T.border,
    strokeWeight: 1,
    clip: true,
  }),
);
const specs = steps.length - 1;
const specRows = [
  ["Runtime", "NixOS (planned)", true],
  ["Connection", "Local", true],
  ["Display", "Wayland (Wawona) ✓", true],
  ["Graphics", "Metal (MoltenVK) ✓", false],
];
specRows.forEach(([k, v, div], i) => {
  add(
    frame(specs, k, {
      layout: "horizontal",
      mainAlign: "spaceBetween",
      crossAlign: "center",
      padding: [0, 12, 0, 12],
      height: 34,
      sizingH: "fill",
      sizingV: "fixed",
      fill: "none",
    }),
  );
  const row = steps.length - 1;
  add(text(row, k, { fontSize: 11, fill: T.muted }));
  add(text(row, v, { fontSize: 11, fill: T.fg }));
  if (div) {
    add(
      frame(specs, `spec-div-${i}`, {
        layout: "horizontal",
        mainAlign: "center",
        height: 1,
        sizingH: "fill",
        sizingV: "fixed",
        padding: [0, 12, 0, 12],
        fill: "none",
      }),
    );
    const dw = steps.length - 1;
    add(
      cmd("node.create", {
        type: "rectangle",
        parent: { $step: dw },
        name: `spec-line-${i}`,
        height: 1,
        props: { fill: "#FFFFFF14", sizingH: "fill" },
      }),
    );
  }
});

add(
  frame(insp, "Storage", {
    layout: "vertical",
    gap: 5,
    padding: [10, 12, 10, 12],
    cornerRadius: R.card,
    fill: T.glassHi,
    stroke: T.border,
    strokeWeight: 1,
    sizingH: "fill",
    sizingV: "hug",
  }),
);
const stor = steps.length - 1;
add(
  frame(stor, "stor head", {
    layout: "horizontal",
    mainAlign: "spaceBetween",
    sizingH: "fill",
    sizingV: "hug",
  }),
);
const sh = steps.length - 1;
add(text(sh, "Storage", { fontSize: 11, fill: T.muted }));
add(text(sh, "6.4 / 20 GB", { fontSize: 11, fill: T.fg }));
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: stor },
    name: "stor track",
    width: INSP_INNER - 24,
    height: 5,
    props: { fill: "#FFFFFF22", cornerRadius: R.track, sizingH: "fill" },
  }),
);
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: stor },
    name: "stor fill",
    width: Math.round((INSP_INNER - 24) * 0.32),
    height: 5,
    props: { fill: T.primary, cornerRadius: R.track },
  }),
);

add(
  frame(insp, "Tags", {
    layout: "horizontal",
    gap: 6,
    crossAlign: "center",
    sizingH: "fill",
    sizingV: "hug",
  }),
);
const tags = steps.length - 1;
for (const [label, fill] of [
  ["Work", "#5AC8FA55"],
  ["Dev", "#BF5AF255"],
]) {
  add(
    frame(tags, label, {
      layout: "horizontal",
      padding: [0, 10, 0, 10],
      height: 22,
      cornerRadius: R.pill,
      fill,
      stroke: T.border,
      strokeWeight: 1,
      crossAlign: "center",
      sizingV: "fixed",
    }),
  );
  const chip = steps.length - 1;
  add(text(chip, label, { fontSize: 11, fill: T.fg }));
}
add(
  frame(tags, "+", {
    layout: "horizontal",
    mainAlign: "center",
    crossAlign: "center",
    width: 22,
    height: 22,
    cornerRadius: R.pill,
    fill: T.glassRow,
    stroke: T.border,
    strokeWeight: 1,
    sizingH: "fixed",
    sizingV: "fixed",
  }),
);
const plus = steps.length - 1;
add(text(plus, "+", { fontSize: 12, fill: T.muted }));

add(
  frame(insp, "Pinned", {
    layout: "horizontal",
    mainAlign: "spaceBetween",
    crossAlign: "center",
    padding: [8, 12, 8, 12],
    cornerRadius: R.card,
    fill: T.glassHi,
    stroke: T.border,
    strokeWeight: 1,
    sizingH: "fill",
    sizingV: "hug",
  }),
);
const pin = steps.length - 1;
add(text(pin, "Pinned", { fontSize: 12, fill: T.muted }));
add(
  frame(pin, "toggle", {
    layout: "horizontal",
    mainAlign: "max",
    crossAlign: "center",
    width: 42,
    height: 22,
    cornerRadius: R.pill,
    fill: T.primary,
    padding: [2, 2, 2, 2],
    sizingH: "fixed",
    sizingV: "fixed",
  }),
);
const tog = steps.length - 1;
add(
  cmd("node.create", {
    type: "ellipse",
    parent: { $step: tog },
    width: 18,
    height: 18,
    props: { fill: "#FFFFFF" },
  }),
);

add(
  frame(insp, "Relay info", {
    layout: "vertical",
    gap: 4,
    padding: 10,
    cornerRadius: R.card,
    fill: T.glassHi,
    stroke: T.border,
    strokeWeight: 1,
    sizingH: "fill",
    sizingV: "hug",
  }),
);
const relay = steps.length - 1;
add(text(relay, "Relay", { fontSize: 12, fontStyle: "SemiBold", fill: T.fg }));
add(
  text(relay, "NixOS prebuilt runtime for this Virtual Machine.", {
    fontSize: 11,
    fill: T.muted,
    sizingH: "fill",
  }),
);
add(text(relay, "Learn more →", { fontSize: 11, fill: T.primary }));

// Settings cover — System Settings idiom: fixed nav, grouped lists, hairline chrome
add(
  cmd("frame.create", {
    preset: 'MacBook Pro 14"',
    x: 3200,
    y: 0,
    name: "macOS · Settings cover",
    props: { fill: "#121828", layout: null, clip: true, cornerRadius: R.window },
  }),
);
const setWin = steps.length - 1;
add(
  cmd("file.placeImage", {
    path: join(assets, "wawona-valley-wallpaper.png"),
    parent: { $step: setWin },
    x: 0,
    y: 0,
    width: 1512,
    height: 982,
    name: "wallpaper",
    mode: "fill",
  }),
);
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: setWin },
    name: "dim",
    x: 0,
    y: 0,
    width: 1512,
    height: 982,
    props: { fill: "#0A1020B8", absolute: true },
  }),
);

// Sheet metrics — absolute chrome/nav/detail so sizes stay locked
const SHEET_W = 920;
const SHEET_H = 680;
const SHEET_X = Math.round((1512 - SHEET_W) / 2);
const SHEET_Y = Math.round((982 - SHEET_H) / 2);
const NAV_W = 220;
const CHROME_H = 52;
const DETAIL_PAD_X = 28;
const ROW_PAD_X = 18;
const GROUP_R = 12;
const DIV_INSET = ROW_PAD_X;
const DETAIL_INNER_W = SHEET_W - NAV_W - DETAIL_PAD_X * 2;
const DIV_W = DETAIL_INNER_W - DIV_INSET * 2;

add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: setWin },
    name: "Settings sheet",
    x: SHEET_X,
    y: SHEET_Y,
    width: SHEET_W,
    height: SHEET_H,
    props: {
      absolute: true,
      fill: T.glassSide,
      stroke: T.border,
      strokeWeight: 1,
      cornerRadius: 20,
      layout: null,
      clip: true,
    },
  }),
);
const sheet = steps.length - 1;

// Chrome — no full stroke (avoids double rim); hairline under
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: sheet },
    name: "Settings chrome",
    x: 0,
    y: 0,
    width: SHEET_W,
    height: CHROME_H,
    props: {
      absolute: true,
      fill: T.glassHi,
      layout: "horizontal",
      mainAlign: "spaceBetween",
      crossAlign: "center",
      padding: [0, 22, 0, 22],
    },
  }),
);
const sch = steps.length - 1;
add(text(sch, "Settings", { fontSize: 16, fontStyle: "SemiBold", fill: T.fg }));
add(
  frame(sch, "Done", {
    layout: "horizontal",
    mainAlign: "center",
    crossAlign: "center",
    padding: [0, 16, 0, 16],
    height: 28,
    cornerRadius: R.pill,
    fill: T.primary,
  }),
);
const done = steps.length - 1;
add(text(done, "Done", { fontSize: 13, fontStyle: "SemiBold", fill: T.onPrimary }));
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: sheet },
    name: "chrome hairline",
    x: 0,
    y: CHROME_H - 1,
    width: SHEET_W,
    height: 1,
    props: { fill: "#FFFFFF18", absolute: true },
  }),
);

// Nav column — inset selection, no outer stroke (split via hairline)
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: sheet },
    name: "Settings nav",
    x: 0,
    y: CHROME_H,
    width: NAV_W,
    height: SHEET_H - CHROME_H,
    props: {
      absolute: true,
      fill: T.glass,
      layout: "vertical",
      gap: 2,
      padding: [16, 14, 16, 14],
    },
  }),
);
const snav = steps.length - 1;
add(
  frame(snav, "nav label wrap", {
    layout: "horizontal",
    padding: [0, 10, 8, 10],
    sizingH: "fill",
    fill: "none",
  }),
);
const snavLab = steps.length - 1;
add(text(snavLab, "Wawona", { fontSize: 11, fontStyle: "SemiBold", fill: T.muted }));
for (const [label, on] of [
  ["General", true],
  ["Display", false],
  ["Input", false],
  ["Graphics", false],
  ["Network", false],
  ["Permissions", false],
]) {
  add(
    frame(snav, label, {
      layout: "horizontal",
      crossAlign: "center",
      mainAlign: "min",
      padding: [0, 12, 0, 12],
      height: 32,
      cornerRadius: 8,
      fill: on ? T.glassRowSel : "none",
      stroke: on ? T.selectStroke : "none",
      strokeWeight: on ? 1 : 0,
      sizingH: "fill",
    }),
  );
  const r = steps.length - 1;
  add(
    text(r, label, {
      fontSize: 13,
      fontStyle: on ? "SemiBold" : "Regular",
      fill: on ? T.fg : T.muted,
    }),
  );
}
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: sheet },
    name: "nav hairline",
    x: NAV_W - 1,
    y: CHROME_H,
    width: 1,
    height: SHEET_H - CHROME_H,
    props: { fill: "#FFFFFF18", absolute: true },
  }),
);

// Detail pane
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: sheet },
    name: "Settings detail",
    x: NAV_W,
    y: CHROME_H,
    width: SHEET_W - NAV_W,
    height: SHEET_H - CHROME_H,
    props: {
      absolute: true,
      fill: "#15203866",
      layout: "vertical",
      gap: 12,
      padding: [24, DETAIL_PAD_X, 24, DETAIL_PAD_X],
    },
  }),
);
const sdet = steps.length - 1;

// Title block — hug height (FigCraft defaults missing height to fixed 100)
add(
  frame(sdet, "title block", {
    layout: "vertical",
    gap: 6,
    sizingH: "fill",
    sizingV: "hug",
    fill: "none",
  }),
);
const stitle = steps.length - 1;
add(text(stitle, "General", { fontSize: 22, fontStyle: "Bold", fill: T.fg }));
add(
  text(stitle, "Appearance, startup, and default machine behaviour.", {
    fontSize: 13,
    fill: T.muted,
    sizingH: "fill",
  }),
);

function prefRow(parent, label, value, withDivider, key) {
  add(
    frame(parent, label, {
      layout: "horizontal",
      mainAlign: "spaceBetween",
      crossAlign: "center",
      padding: [0, ROW_PAD_X, 0, ROW_PAD_X],
      height: 44,
      sizingH: "fill",
      sizingV: "fixed",
      fill: "none",
    }),
  );
  const row = steps.length - 1;
  add(text(row, label, { fontSize: 13, fill: T.fg }));
  add(
    frame(row, `${label} value`, {
      layout: "horizontal",
      gap: 4,
      crossAlign: "center",
      sizingV: "hug",
      fill: "none",
    }),
  );
  const val = steps.length - 1;
  add(text(val, value, { fontSize: 13, fill: T.muted }));
  add(text(val, "›", { fontSize: 15, fill: "#8E96B0" }));
  if (withDivider) {
    // Inset hairline as a hug-height strip (avoid absolute x in auto-layout)
    add(
      frame(parent, `div-${key}`, {
        layout: "horizontal",
        mainAlign: "center",
        height: 1,
        sizingH: "fill",
        sizingV: "fixed",
        padding: [0, DIV_INSET, 0, DIV_INSET],
        fill: "none",
      }),
    );
    const divWrap = steps.length - 1;
    add(
      cmd("node.create", {
        type: "rectangle",
        parent: { $step: divWrap },
        name: `div-line-${key}`,
        height: 1,
        props: { fill: "#FFFFFF14", sizingH: "fill" },
      }),
    );
  }
}

function prefGroup(parent, name, rows) {
  add(
    frame(parent, name, {
      layout: "vertical",
      gap: 0,
      sizingH: "fill",
      sizingV: "hug",
      cornerRadius: GROUP_R,
      fill: T.glassHi,
      stroke: T.border,
      strokeWeight: 1,
      clip: true,
    }),
  );
  const g = steps.length - 1;
  rows.forEach(([k, v, div], i) => prefRow(g, k, v, div, `${name}-${i}`));
  return g;
}

prefGroup(sdet, "Prefs group", [
  ["Appearance", "Match System", true],
  ["Launch at login", "Off", true],
  ["Default machine kind", "Native Shell", true],
  ["Confirm before Stop", "On", false],
]);

// Section label sits above its group (gap ≥ 2× row rhythm)
add(
  frame(sdet, "Sessions label wrap", {
    layout: "horizontal",
    padding: [10, 4, 0, 4],
    sizingH: "fill",
    sizingV: "hug",
    fill: "none",
  }),
);
const slab = steps.length - 1;
add(text(slab, "Sessions", { fontSize: 12, fontStyle: "SemiBold", fill: T.muted }));
prefGroup(sdet, "Sessions group", [
  ["Restore last session", "On", true],
  ["Clipboard share", "Ask", true],
  ["Idle timeout", "30 min", false],
]);

add(
  text(sdet, "Changes apply to new sessions. Running machines keep their current settings.", {
    fontSize: 11,
    fill: T.muted,
    sizingH: "fill",
    sizingV: "hug",
  }),
);

const out = join(__dirname, "build-macos-v4.json");
writeFileSync(out, JSON.stringify(steps, null, 2));
console.log(`Wrote ${steps.length} commands → ${out}`);

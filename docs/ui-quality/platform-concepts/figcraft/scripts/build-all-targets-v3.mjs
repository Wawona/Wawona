#!/usr/bin/env bun
/**
 * Wawona ALL_TARGETS FigCraft v3
 * Skills: wawona-ui-skills, frontend-design, impeccable (comp-led),
 * figcraft-design, better-ui / better-colors.
 *
 * Page 00: Concept plates = approved comps (pixel truth)
 * Page 01: Foundations
 * Page 02: macOS editable reconstruction over valley wallpaper + glass
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
const add = (...xs) => steps.push(...xs);

const T = {
  glass: "#1A1628B8",
  glassSolid: "#1A1628D0",
  glassHi: "#2A2440CC",
  glassRow: "#FFFFFF14",
  glassRowSel: "#3D9CFF38",
  glassPill: "#FFFFFF22",
  glassPillOn: "#FFFFFF44",
  fg: "#F2F4FF",
  muted: "#B4B9D0",
  border: "#FFFFFF28",
  primary: "#3D9CFF",
  onPrimary: "#FFFFFF",
  running: "#34C759",
  stopped: "#8E8E93",
  ready: "#5AC8FA",
  trafficR: "#FF5F57",
  trafficY: "#FEBC2E",
  trafficG: "#28C840",
  veil: "#0A061866",
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

function frame(parent, name, props) {
  // FigCraft missing fill → opaque white. Always set.
  return cmd("node.create", {
    type: "frame",
    parent: typeof parent === "number" ? { $step: parent } : parent,
    name,
    props: { fill: "#00000000", ...props },
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
add(cmd("file.rename", { name: "Wawona ALL_TARGETS UI v3" }));
add(cmd("page.rename", { name: "00 Concept plates" }));
add(cmd("page.setBackground", { color: "#0A0812" }));

add(
  cmd("node.create", {
    type: "text",
    x: 0,
    y: -36,
    text: "Approved comps (pixel truth). Product filter: Settings = gear cover. Editable macOS on page 02.",
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
  ["color/bg", "#12101C", "#F4F6FB"],
  ["color/glass", T.glassSolid, "#FFFFFFE6"],
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
    height: 400,
    name: "Token board",
    props: {
      fill: "#12101C",
      layout: "vertical",
      gap: 16,
      padding: 28,
      cornerRadius: 16,
    },
  }),
);
const board = steps.length - 1;
add(
  text(board, "Valley-glass Operate tokens", {
    fontSize: 24,
    fontStyle: "Bold",
    fill: T.fg,
  }),
);
add(
  text(
    board,
    "From concept comps. Glass over landscape. Neon status. Settings = gear.",
    { fontSize: 13, fill: T.muted, sizingH: "fill" },
  ),
);
add(
  frame(board, "Swatches", {
    layout: "horizontal",
    gap: 12,
    sizingH: "fill",
  }),
);
const sw = steps.length - 1;
for (const [label, hex] of [
  ["glass", T.glassSolid],
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
  add(text(cell, `${label}\n${hex}`, { fontSize: 11, fill: T.muted }));
}

// ========== macOS editable (comp-led: match macOS.png IA) ==========
add(cmd("page.add", { name: "02 macOS editable" }));
add(cmd("page.select", { index: 2 }));
add(cmd("page.setBackground", { color: "#05040A" }));

add(
  cmd("node.create", {
    type: "text",
    x: 0,
    y: -32,
    text: "Editable · valley-glass · match macOS.png (pill nav, targets, row actions, gear cover)",
    name: "edit intro",
    props: { fontSize: 13, fill: "#9AA0B8" },
  }),
);

add(
  cmd("frame.create", {
    preset: 'MacBook Pro 14"',
    x: 0,
    y: 0,
    name: "macOS · Machines",
    props: {
      fill: "#0D0A14",
      layout: null,
      clip: true,
      cornerRadius: 18,
    },
  }),
);
const win = steps.length - 1;

add(
  cmd("file.placeImage", {
    path: join(assets, "wawona-valley-wallpaper.png"),
    parent: { $step: win },
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
    parent: { $step: win },
    name: "veil",
    x: 0,
    y: 0,
    width: 1512,
    height: 982,
    props: { fill: T.veil, absolute: true },
  }),
);

// Title bar (absolute children so pill stays centered like the comp)
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: win },
    name: "Title bar",
    x: 0,
    y: 0,
    width: 1512,
    height: 52,
    props: {
      absolute: true,
      fill: T.glassSolid,
      stroke: T.border,
      strokeWeight: 1,
      layout: null,
      clip: true,
    },
  }),
);
const titleBar = steps.length - 1;
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: titleBar },
    name: "Brand",
    x: 16,
    y: 10,
    width: 280,
    height: 32,
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
add(
  frame(brand, "Traffic", {
    layout: "horizontal",
    gap: 7,
    crossAlign: "center",
  }),
);
const traffic = steps.length - 1;
for (const c of [T.trafficR, T.trafficY, T.trafficG]) {
  add(
    cmd("node.create", {
      type: "ellipse",
      parent: { $step: traffic },
      width: 12,
      height: 12,
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
    props: { fill: T.primary },
  }),
);
add(
  text(brand, "Wawona Compositor", {
    fontSize: 13,
    fontStyle: "SemiBold",
    fill: T.fg,
  }),
);
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: titleBar },
    name: "Pill nav",
    x: 556,
    y: 8,
    width: 400,
    height: 36,
    props: {
      absolute: true,
      layout: "horizontal",
      gap: 4,
      padding: [4, 4, 4, 4],
      cornerRadius: 999,
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
      padding: [7, 14, 7, 14],
      cornerRadius: 999,
      fill: on ? T.glassPillOn : "#00000000",
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
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: titleBar },
    name: "Search",
    x: 1220,
    y: 10,
    width: 200,
    height: 32,
    props: {
      absolute: true,
      layout: "horizontal",
      padding: [8, 14, 8, 14],
      cornerRadius: 10,
      fill: T.glassRow,
      stroke: T.border,
      strokeWeight: 1,
      crossAlign: "center",
    },
  }),
);
const search = steps.length - 1;
add(text(search, "Search  ⌘F", { fontSize: 12, fill: T.muted }));
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: titleBar },
    name: "Settings gear",
    x: 1434,
    y: 9,
    width: 34,
    height: 34,
    props: {
      absolute: true,
      layout: "horizontal",
      mainAlign: "center",
      crossAlign: "center",
      cornerRadius: 10,
      fill: T.glassRow,
      stroke: T.border,
      strokeWeight: 1,
    },
  }),
);
const gear = steps.length - 1;
add(text(gear, "⚙︎", { fontSize: 14, fill: T.fg }));

// Sidebar
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: win },
    name: "Sidebar",
    x: 0,
    y: 52,
    width: 248,
    height: 930,
    props: {
      absolute: true,
      fill: T.glass,
      stroke: T.border,
      strokeWeight: 1,
      layout: "vertical",
      gap: 6,
      padding: [12, 10, 12, 10],
    },
  }),
);
const side = steps.length - 1;

function sideSection(parent, label) {
  add(text(parent, label, { fontSize: 10, fill: T.muted }));
}

function sideRow(parent, label, badge, on, icon) {
  add(
    frame(parent, label, {
      layout: "horizontal",
      gap: 8,
      crossAlign: "center",
      padding: [6, 8, 6, 8],
      cornerRadius: 10,
      fill: on ? T.glassRowSel : T.glassRow,
      stroke: on ? T.primary : "#00000000",
      strokeWeight: on ? 1.5 : 0,
      sizingH: "fill",
    }),
  );
  const item = steps.length - 1;
  if (icon) {
    add(
      cmd("node.create", {
        type: "ellipse",
        parent: { $step: item },
        width: 7,
        height: 7,
        props: { fill: typeof icon === "string" ? icon : T.muted },
      }),
    );
  }
  add(text(item, label, { fontSize: 12, fontStyle: on ? "SemiBold" : "Regular", fill: T.fg }));
  add(frame(item, "grow", { sizingH: "fill", height: 1, fill: "#00000000" }));
  if (badge !== undefined && badge !== "") {
    add(text(item, String(badge), { fontSize: 11, fill: T.muted }));
  }
}

sideSection(side, "Library");
sideRow(side, "Machines", "5", true, T.primary);
sideRow(side, "Sessions", "1", false, T.muted);
sideRow(side, "Images", "", false, T.muted);
sideRow(side, "Runtimes", "", false, T.muted);
sideSection(side, "Favorites");
sideRow(side, "Pinned", "2", false, null);
sideRow(side, "Recent", "", false, null);
sideSection(side, "Tags");
for (const [label, color, n] of [
  ["Work", "#5AC8FA", "2"],
  ["Dev", "#BF5AF2", "3"],
  ["Test", "#34C759", "1"],
]) {
  sideRow(side, label, n, false, color);
}
sideSection(side, "Platform Targets");
for (const [label, on] of [
  ["macOS", true],
  ["iOS / iPadOS", false],
  ["Android", false],
  ["WASM / Web", false],
]) {
  sideRow(side, label, "", on, on ? T.primary : T.muted);
}
add(
  frame(side, "Transfers", {
    layout: "vertical",
    gap: 6,
    padding: 10,
    cornerRadius: 12,
    fill: T.glassHi,
    stroke: T.border,
    strokeWeight: 1,
    sizingH: "fill",
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
add(text(xh, "Transfers", { fontSize: 11, fill: T.muted }));
add(text(xh, "✕", { fontSize: 11, fill: T.muted }));
add(
  text(xfer, "NixOS vm.qcow2", {
    fontSize: 12,
    fontStyle: "SemiBold",
    fill: T.fg,
  }),
);
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: xfer },
    name: "progress track",
    width: 210,
    height: 6,
    props: { fill: "#FFFFFF22", cornerRadius: 3 },
  }),
);
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: xfer },
    name: "progress",
    width: 120,
    height: 6,
    props: { fill: T.primary, cornerRadius: 3 },
  }),
);
add(text(xfer, "3.2 / 5.6 GB · 12.4 MB/s", { fontSize: 10, fill: T.muted }));

// Catalog
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: win },
    name: "Catalog",
    x: 248,
    y: 52,
    width: 940,
    height: 930,
    props: {
      absolute: true,
      fill: "#100C1A88",
      layout: "vertical",
      gap: 8,
      padding: [14, 16, 14, 16],
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
  }),
);
const chead = steps.length - 1;
add(
  frame(chead, "Titles", {
    layout: "vertical",
    gap: 4,
    sizingH: "fill",
  }),
);
const titles = steps.length - 1;
add(text(titles, "Machines", { fontSize: 28, fontStyle: "Bold", fill: T.fg }));
add(
  text(titles, "5 machines · 2 pinned · 1 running", {
    fontSize: 12,
    fill: T.muted,
  }),
);
add(
  frame(chead, "Header actions", {
    layout: "horizontal",
    gap: 8,
    crossAlign: "center",
  }),
);
const had = steps.length - 1;
add(
  frame(had, "View toggle", {
    layout: "horizontal",
    gap: 2,
    padding: [3, 3, 3, 3],
    cornerRadius: 10,
    fill: T.glassRow,
    stroke: T.border,
    strokeWeight: 1,
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
      width: 30,
      height: 28,
      cornerRadius: 8,
      fill: on ? T.glassPillOn : "#00000000",
    }),
  );
  const b = steps.length - 1;
  add(text(b, label, { fontSize: 13, fill: on ? T.fg : T.muted }));
}
add(
  frame(had, "New", {
    layout: "horizontal",
    mainAlign: "center",
    crossAlign: "center",
    padding: [10, 14, 10, 14],
    cornerRadius: 10,
    fill: T.primary,
  }),
);
const neu = steps.length - 1;
add(text(neu, "+ New", { fontSize: 13, fontStyle: "SemiBold", fill: T.onPrimary }));

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
    thumb: "shell.png",
    selected: false,
    action: "▶",
  },
];

for (const m of machines) {
  add(
    frame(catalog, m.name, {
      layout: "horizontal",
      gap: 12,
      padding: [10, 12, 10, 12],
      crossAlign: "center",
      sizingH: "fill",
      fill: m.selected ? T.glassRowSel : T.glassRow,
      stroke: m.selected ? T.primary : T.border,
      strokeWeight: m.selected ? 2 : 1,
      cornerRadius: 14,
    }),
  );
  const row = steps.length - 1;
  add(
    cmd("file.placeImage", {
      path: join(thumbs, m.thumb),
      parent: { $step: row },
      width: 52,
      height: 52,
      name: `${m.name} thumb`,
      mode: "fill",
    }),
  );
  add(
    frame(row, "meta", {
      layout: "vertical",
      gap: 4,
      sizingH: "fill",
    }),
  );
  const meta = steps.length - 1;
  add(text(meta, m.name, { fontSize: 15, fontStyle: "SemiBold", fill: T.fg }));
  add(text(meta, m.kind, { fontSize: 12, fill: T.muted }));
  add(
    frame(row, "status", {
      layout: "horizontal",
      gap: 6,
      padding: [6, 12, 6, 12],
      crossAlign: "center",
      cornerRadius: 999,
      fill: "#00000066",
      stroke: m.color + "66",
      strokeWeight: 1,
    }),
  );
  const st = steps.length - 1;
  add(
    cmd("node.create", {
      type: "ellipse",
      parent: { $step: st },
      width: 8,
      height: 8,
      props: { fill: m.color },
    }),
  );
  add(
    text(st, m.time ? `${m.status} · ${m.time}` : m.status, {
      fontSize: 11,
      fill: T.fg,
    }),
  );
  add(
    frame(row, "row actions", {
      layout: "horizontal",
      gap: 6,
      crossAlign: "center",
    }),
  );
  const ra = steps.length - 1;
  add(
    frame(ra, "play", {
      layout: "horizontal",
      mainAlign: "center",
      crossAlign: "center",
      width: 32,
      height: 32,
      cornerRadius: 10,
      fill: T.glassHi,
      stroke: T.border,
      strokeWeight: 1,
    }),
  );
  const play = steps.length - 1;
  add(text(play, m.action, { fontSize: 12, fill: T.fg }));
  add(
    frame(ra, "more", {
      layout: "horizontal",
      mainAlign: "center",
      crossAlign: "center",
      width: 32,
      height: 32,
      cornerRadius: 10,
      fill: T.glassHi,
      stroke: T.border,
      strokeWeight: 1,
    }),
  );
  const more = steps.length - 1;
  add(text(more, "···", { fontSize: 12, fill: T.muted }));
}

// Inspector
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: win },
    name: "Inspector",
    x: 1188,
    y: 52,
    width: 324,
    height: 930,
    props: {
      absolute: true,
      fill: T.glass,
      stroke: T.border,
      strokeWeight: 1,
      layout: "vertical",
      gap: 8,
      padding: 12,
    },
  }),
);
const insp = steps.length - 1;
add(
  cmd("file.placeImage", {
    path: join(thumbs, "inspector-hero.png"),
    parent: { $step: insp },
    width: 300,
    height: 120,
    name: "hero",
    mode: "fill",
  }),
);
add(
  frame(insp, "insp head", {
    layout: "horizontal",
    mainAlign: "spaceBetween",
    crossAlign: "center",
    sizingH: "fill",
  }),
);
const ih = steps.length - 1;
add(
  frame(ih, "insp titles", {
    layout: "vertical",
    gap: 3,
    sizingH: "fill",
  }),
);
const it = steps.length - 1;
add(text(it, "Sample Linux VM", { fontSize: 17, fontStyle: "Bold", fill: T.fg }));
add(text(it, "Virtual Machine · NixOS", { fontSize: 11, fill: T.muted }));
add(
  frame(ih, "Running pill", {
    layout: "horizontal",
    gap: 6,
    padding: [5, 10, 5, 10],
    cornerRadius: 999,
    fill: "#34C75933",
    crossAlign: "center",
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

add(
  frame(insp, "Primary actions", {
    layout: "vertical",
    gap: 8,
    sizingH: "fill",
  }),
);
const pact = steps.length - 1;
add(
  frame(pact, "Open Session", {
    layout: "horizontal",
    mainAlign: "center",
    crossAlign: "center",
    padding: [12, 16, 12, 16],
    cornerRadius: 11,
    fill: T.primary,
    sizingH: "fill",
  }),
);
const open = steps.length - 1;
add(
  text(open, "Open Session", {
    fontSize: 13,
    fontStyle: "SemiBold",
    fill: T.onPrimary,
  }),
);
add(
  frame(pact, "Secondary", {
    layout: "horizontal",
    gap: 8,
    sizingH: "fill",
  }),
);
const sec = steps.length - 1;
for (const label of ["Pause", "Stop"]) {
  add(
    frame(sec, label, {
      layout: "horizontal",
      mainAlign: "center",
      crossAlign: "center",
      padding: [10, 12, 10, 12],
      cornerRadius: 10,
      fill: T.glassHi,
      stroke: T.border,
      strokeWeight: 1,
      sizingH: "fill",
    }),
  );
  const b = steps.length - 1;
  add(text(b, label, { fontSize: 12, fill: T.fg }));
}
add(
  frame(insp, "Tabs", {
    layout: "horizontal",
    gap: 4,
    sizingH: "fill",
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
      padding: [7, 10, 7, 10],
      cornerRadius: 8,
      fill: on ? T.glassRowSel : T.glassRow,
    }),
  );
  const t = steps.length - 1;
  add(
    text(t, label, {
      fontSize: 11,
      fontStyle: on ? "SemiBold" : "Regular",
      fill: on ? T.fg : T.muted,
    }),
  );
}
for (const [k, v] of [
  ["Runtime", "NixOS (planned)"],
  ["Connection", "Local"],
  ["Display", "Wayland (Wawona) ✓"],
  ["Graphics", "Metal (MoltenVK) ✓"],
]) {
  add(
    frame(insp, k, {
      layout: "horizontal",
      mainAlign: "spaceBetween",
      crossAlign: "center",
      padding: [9, 10, 9, 10],
      cornerRadius: 10,
      fill: T.glassHi,
      sizingH: "fill",
    }),
  );
  const row = steps.length - 1;
  add(text(row, k, { fontSize: 12, fill: T.muted }));
  add(text(row, v, { fontSize: 12, fill: T.fg }));
}
add(
  frame(insp, "Storage", {
    layout: "vertical",
    gap: 6,
    padding: [9, 10, 9, 10],
    cornerRadius: 10,
    fill: T.glassHi,
    sizingH: "fill",
  }),
);
const stor = steps.length - 1;
add(
  frame(stor, "stor head", {
    layout: "horizontal",
    mainAlign: "spaceBetween",
    sizingH: "fill",
  }),
);
const sh = steps.length - 1;
add(text(sh, "Storage", { fontSize: 12, fill: T.muted }));
add(text(sh, "6.4 / 20 GB", { fontSize: 12, fill: T.fg }));
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: stor },
    name: "stor track",
    width: 268,
    height: 6,
    props: { fill: "#FFFFFF22", cornerRadius: 3 },
  }),
);
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: stor },
    name: "stor fill",
    width: 86,
    height: 6,
    props: { fill: T.primary, cornerRadius: 3 },
  }),
);
add(
  frame(insp, "Tags", {
    layout: "horizontal",
    gap: 6,
    crossAlign: "center",
    sizingH: "fill",
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
      padding: [5, 12, 5, 12],
      cornerRadius: 999,
      fill,
      stroke: T.border,
      strokeWeight: 1,
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
    width: 28,
    height: 24,
    cornerRadius: 999,
    fill: T.glassRow,
    stroke: T.border,
    strokeWeight: 1,
  }),
);
const plus = steps.length - 1;
add(text(plus, "+", { fontSize: 12, fill: T.muted }));
add(
  frame(insp, "Pinned", {
    layout: "horizontal",
    mainAlign: "spaceBetween",
    crossAlign: "center",
    padding: [9, 10, 9, 10],
    cornerRadius: 10,
    fill: T.glassHi,
    sizingH: "fill",
  }),
);
const pin = steps.length - 1;
add(text(pin, "Pinned", { fontSize: 12, fill: T.muted }));
add(
  frame(pin, "toggle", {
    layout: "horizontal",
    mainAlign: "max",
    crossAlign: "center",
    width: 44,
    height: 24,
    cornerRadius: 999,
    fill: T.primary,
    padding: [2, 2, 2, 2],
  }),
);
const tog = steps.length - 1;
add(
  cmd("node.create", {
    type: "ellipse",
    parent: { $step: tog },
    width: 20,
    height: 20,
    props: { fill: "#FFFFFF" },
  }),
);
add(
  frame(insp, "Relay info", {
    layout: "vertical",
    gap: 6,
    padding: 12,
    cornerRadius: 12,
    fill: T.glassHi,
    stroke: T.border,
    strokeWeight: 1,
    sizingH: "fill",
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

// Settings cover (gear) — second top-level frame
add(
  cmd("frame.create", {
    preset: 'MacBook Pro 14"',
    x: 1600,
    y: 0,
    name: "macOS · Settings cover",
    props: {
      fill: "#0D0A14",
      layout: null,
      clip: true,
      cornerRadius: 18,
    },
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
    props: { fill: "#05040ACC", absolute: true },
  }),
);
add(
  cmd("node.create", {
    type: "frame",
    parent: { $step: setWin },
    name: "Settings sheet",
    x: 256,
    y: 80,
    width: 1000,
    height: 820,
    props: {
      absolute: true,
      fill: T.glassSolid,
      stroke: T.border,
      strokeWeight: 1,
      cornerRadius: 20,
      layout: "vertical",
      gap: 0,
      clip: true,
    },
  }),
);
const sheet = steps.length - 1;
add(
  frame(sheet, "Settings chrome", {
    layout: "horizontal",
    mainAlign: "spaceBetween",
    crossAlign: "center",
    padding: [16, 20, 16, 20],
    sizingH: "fill",
    fill: T.glassHi,
  }),
);
const sch = steps.length - 1;
add(text(sch, "Settings", { fontSize: 20, fontStyle: "Bold", fill: T.fg }));
add(
  frame(sch, "Done", {
    layout: "horizontal",
    padding: [8, 16, 8, 16],
    cornerRadius: 10,
    fill: T.primary,
  }),
);
const done = steps.length - 1;
add(text(done, "Done", { fontSize: 13, fontStyle: "SemiBold", fill: T.onPrimary }));
add(
  frame(sheet, "Settings body", {
    layout: "horizontal",
    gap: 0,
    sizingH: "fill",
    sizingV: "fill",
  }),
);
const sbody = steps.length - 1;
add(
  frame(sbody, "Settings nav", {
    layout: "vertical",
    gap: 6,
    padding: 14,
    width: 220,
    fill: T.glass,
    sizingV: "fill",
  }),
);
const snav = steps.length - 1;
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
      padding: [10, 12, 10, 12],
      cornerRadius: 10,
      fill: on ? T.glassRowSel : T.glassRow,
      stroke: on ? T.primary : "#00000000",
      strokeWeight: on ? 1.5 : 0,
      sizingH: "fill",
    }),
  );
  const r = steps.length - 1;
  add(
    text(r, label, {
      fontSize: 13,
      fontStyle: on ? "SemiBold" : "Regular",
      fill: T.fg,
    }),
  );
}
add(
  frame(sbody, "Settings detail", {
    layout: "vertical",
    gap: 12,
    padding: 24,
    sizingH: "fill",
    sizingV: "fill",
    fill: "#100C1A66",
  }),
);
const sdet = steps.length - 1;
add(text(sdet, "General", { fontSize: 22, fontStyle: "Bold", fill: T.fg }));
add(
  text(sdet, "Appearance, startup, and default machine behaviour.", {
    fontSize: 13,
    fill: T.muted,
    sizingH: "fill",
  }),
);
for (const [k, v] of [
  ["Appearance", "Match System"],
  ["Launch at login", "Off"],
  ["Default machine kind", "Native Shell"],
  ["Confirm before Stop", "On"],
]) {
  add(
    frame(sdet, k, {
      layout: "horizontal",
      mainAlign: "spaceBetween",
      crossAlign: "center",
      padding: [14, 16, 14, 16],
      cornerRadius: 12,
      fill: T.glassHi,
      stroke: T.border,
      strokeWeight: 1,
      sizingH: "fill",
    }),
  );
  const r = steps.length - 1;
  add(text(r, k, { fontSize: 14, fill: T.fg }));
  add(text(r, v, { fontSize: 13, fill: T.muted }));
}

const out = join(__dirname, "build-all-targets-v3.json");
writeFileSync(out, JSON.stringify(steps, null, 2));
console.log(`Wrote ${steps.length} commands → ${out}`);
console.log(`Plates: ${platforms.length}`);

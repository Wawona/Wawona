#!/usr/bin/env bun
/**
 * Build Wawona ALL_TARGETS Machines UI into a FigCraft command script.
 * Drive with: figcraft-cli run scripts/build-all-targets.json --out …
 * Regenerates JSON then expects the caller to run figcraft-cli.
 */
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const refs = join(root, "refs");

const cmd = (command, params = {}) => ({ command, params });

const platforms = [
  {
    id: "macos",
    label: "macOS",
    ref: "macOS.png",
    preset: "MacBook Pro 14\"",
    paradigm: "desktop-split",
  },
  {
    id: "ios",
    label: "iOS",
    ref: "iOS.png",
    preset: "iPhone 16 Pro",
    paradigm: "phone-stack",
  },
  {
    id: "ipados",
    label: "iPadOS",
    ref: "iPadOS.png",
    preset: "iPad Pro 11\"",
    paradigm: "tablet-split",
  },
  {
    id: "android",
    label: "Android",
    ref: "Android_Tablet.png",
    preset: "Android Expanded",
    paradigm: "tablet-split",
  },
  {
    id: "linux",
    label: "Linux",
    ref: "Linux.png",
    preset: "Desktop",
    paradigm: "desktop-split",
  },
  {
    id: "web",
    label: "Web",
    ref: "Web_DOM.png",
    preset: "Desktop",
    paradigm: "desktop-split",
  },
  {
    id: "windows",
    label: "Windows",
    ref: "Windows.png",
    preset: "Desktop",
    paradigm: "desktop-split",
  },
  {
    id: "visionos",
    label: "visionOS",
    ref: "visionOS.png",
    width: 1280,
    height: 720,
    paradigm: "spatial",
  },
  {
    id: "tvos",
    label: "tvOS",
    ref: "tvOS_Apple_TV.png",
    preset: "TV",
    paradigm: "tv-focus",
  },
  {
    id: "watchos",
    label: "watchOS",
    ref: "Apple_Watch.png",
    preset: "Apple Watch 45mm",
    paradigm: "watch",
  },
  {
    id: "wearos",
    label: "Wear OS",
    ref: "Wear_OS.png",
    width: 198,
    height: 242,
    paradigm: "watch",
  },
  {
    id: "asteroidos",
    label: "AsteroidOS",
    ref: "AsteroidOS_Oppo_Watch.png",
    width: 198,
    height: 242,
    paradigm: "watch",
  },
];

const extra = [
  {
    id: "android-xr",
    label: "Android XR (extra)",
    ref: "Android_XR.png",
    width: 1280,
    height: 720,
    paradigm: "spatial",
  },
];

const machines = [
  {
    name: "Sample Linux VM",
    kind: "Virtual Machine · NixOS",
    status: "Running",
    statusColor: "#34C759",
    selected: true,
  },
  {
    name: "Dev Container",
    kind: "Container · OCI",
    status: "Stopped",
    statusColor: "#8E8E93",
    selected: false,
  },
  {
    name: "Native Shell",
    kind: "Native Shell · Local",
    status: "Running",
    statusColor: "#34C759",
    selected: false,
  },
  {
    name: "Relay Wasm",
    kind: "Native Shell · WASI",
    status: "Ready",
    statusColor: "#3D9CFF",
    selected: false,
  },
];

const C = {
  bg: "#12101C",
  surface: "#1A1628",
  surfaceHi: "#241E38",
  fg: "#F2F4FF",
  muted: "#A8AEC4",
  border: "#FFFFFF22",
  primary: "#3D9CFF",
  onPrimary: "#FFFFFF",
  glass: "#FFFFFF14",
};

const steps = [];

function add(...items) {
  steps.push(...items);
}

function text(parentStep, characters, props, name) {
  return cmd("node.create", {
    type: "text",
    parent: { $step: parentStep },
    text: characters,
    name: name || characters.slice(0, 24),
    props,
  });
}

function frame(parentStep, name, props, extra = {}) {
  return cmd("node.create", {
    type: "frame",
    parent: { $step: parentStep },
    name,
    props,
    ...extra,
  });
}

// --- Foundations ---
add(cmd("file.rename", { name: "Wawona ALL_TARGETS UI" }));
add(cmd("page.rename", { name: "00 References" }));
add(
  cmd("variable.createCollection", {
    name: "Wawona colours",
    modes: ["Dark", "Light"],
  }),
);
const colorCollectionStep = steps.length - 1;

const colorVars = [
  ["color/bg", { Dark: C.bg, Light: "#F4F6FB" }],
  ["color/surface", { Dark: C.surface, Light: "#FFFFFF" }],
  ["color/fg", { Dark: C.fg, Light: "#1A1A2E" }],
  ["color/muted", { Dark: C.muted, Light: "#5B6168" }],
  ["color/border", { Dark: C.border, Light: "#D0D5E0" }],
  ["color/primary", { Dark: C.primary, Light: "#007AFF" }],
  ["color/on-primary", { Dark: C.onPrimary, Light: "#FFFFFF" }],
  ["color/running", { Dark: "#34C759", Light: "#34C759" }],
];

for (const [name, values] of colorVars) {
  add(
    cmd("variable.create", {
      collection: { $step: colorCollectionStep },
      name,
      type: "color",
      values,
    }),
  );
}

add(cmd("page.add", { name: "01 Foundations" }));
const foundationsPage = steps.length - 1;
add(cmd("page.select", { index: 1 }));

add(
  cmd("node.create", {
    type: "frame",
    name: "Token board",
    x: 0,
    y: 0,
    width: 960,
    height: 520,
    props: {
      fill: C.bg,
      layout: "vertical",
      gap: 16,
      padding: 32,
    },
  }),
);
const tokenBoard = steps.length - 1;

add(
  text(tokenBoard, "Wawona design tokens", {
    fontSize: 28,
    fontStyle: "Bold",
    fill: C.fg,
  }),
);
add(
  text(
    tokenBoard,
    "Dark deck from concept pack. Settings = gear cover. Machines kinds = Native Shell / VM / Container.",
    { fontSize: 14, fill: C.muted, sizingH: "fill" },
  ),
);

add(
  frame(tokenBoard, "Swatches", {
    layout: "horizontal",
    gap: 12,
    sizingH: "fill",
    sizingV: "hug",
  }),
);
const swatches = steps.length - 1;
for (const [label, hex] of [
  ["bg", C.bg],
  ["surface", C.surface],
  ["primary", C.primary],
  ["running", "#34C759"],
  ["fg", C.fg],
]) {
  add(
    frame(swatches, label, {
      layout: "vertical",
      gap: 8,
      padding: 8,
      fill: C.surfaceHi,
      cornerRadius: 12,
      sizingH: "hug",
    }),
  );
  const cell = steps.length - 1;
  add(
    cmd("node.create", {
      type: "rectangle",
      parent: { $step: cell },
      name: `${label}-chip`,
      width: 72,
      height: 48,
      props: { fill: hex, cornerRadius: 8 },
    }),
  );
  add(text(cell, `${label}\n${hex}`, { fontSize: 11, fill: C.muted }));
}

// --- References page ---
add(cmd("page.select", { index: 0 }));
add(
  text(
    undefined,
    // page-level text without parent: create at page
    "Concept PNG references (not editable chrome)",
    { fontSize: 20, fontStyle: "Bold", fill: C.fg },
  ),
);
// Fix: node.create needs parent or lands on page — omit parent for page
steps[steps.length - 1] = cmd("node.create", {
  type: "text",
  x: 0,
  y: -48,
  text: "Concept PNG references (authority for feel; editable screens on 02)",
  name: "Refs title",
  props: { fontSize: 20, fontStyle: "Bold", fill: "#1A1A2E" },
});

let refX = 0;
let refY = 0;
const refCols = 3;
let col = 0;
for (const p of [...platforms, ...extra]) {
  add(
    cmd("file.placeImage", {
      path: join(refs, p.ref),
      x: refX,
      y: refY,
      width: 640,
      name: `ref/${p.id}`,
    }),
  );
  col += 1;
  if (col >= refCols) {
    col = 0;
    refX = 0;
    refY += 420;
  } else {
    refX += 680;
  }
}

// --- Screens page ---
add(cmd("page.add", { name: "02 Screens" }));
add(cmd("page.select", { index: 2 }));
add(cmd("page.setBackground", { color: "#0B0A12" }));

function machineRow(parentStep, m) {
  add(
    frame(parentStep, m.name, {
      layout: "horizontal",
      gap: 12,
      padding: [12, 14, 12, 14],
      crossAlign: "center",
      sizingH: "fill",
      sizingV: "hug",
      fill: m.selected ? "#3D9CFF22" : C.glass,
      stroke: m.selected ? C.primary : C.border,
      strokeWeight: m.selected ? 1.5 : 1,
      cornerRadius: 14,
    }),
  );
  const row = steps.length - 1;
  add(
    cmd("node.create", {
      type: "rectangle",
      parent: { $step: row },
      name: "thumb",
      width: 44,
      height: 44,
      props: { fill: C.surfaceHi, cornerRadius: 10 },
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
  add(
    text(meta, m.name, {
      fontSize: 14,
      fontStyle: "SemiBold",
      fill: C.fg,
    }),
  );
  add(text(meta, m.kind, { fontSize: 11, fill: C.muted }));
  add(
    frame(row, "status", {
      layout: "horizontal",
      gap: 6,
      padding: [4, 10, 4, 10],
      crossAlign: "center",
      cornerRadius: 999,
      fill: "#00000055",
      sizingH: "hug",
    }),
  );
  const status = steps.length - 1;
  add(
    cmd("node.create", {
      type: "ellipse",
      parent: { $step: status },
      width: 8,
      height: 8,
      props: { fill: m.statusColor },
    }),
  );
  add(text(status, m.status, { fontSize: 11, fill: C.fg }));
}

function primaryButton(parentStep, label) {
  add(
    frame(parentStep, label, {
      layout: "horizontal",
      mainAlign: "center",
      crossAlign: "center",
      padding: [12, 18, 12, 18],
      gap: 8,
      cornerRadius: 12,
      fill: C.primary,
      sizingH: "hug",
      sizingV: "hug",
    }),
  );
  const b = steps.length - 1;
  add(
    text(b, label, {
      fontSize: 13,
      fontStyle: "SemiBold",
      fill: C.onPrimary,
    }),
  );
  return b;
}

function gearButton(parentStep) {
  add(
    frame(parentStep, "Settings gear", {
      layout: "horizontal",
      mainAlign: "center",
      crossAlign: "center",
      width: 36,
      height: 36,
      cornerRadius: 10,
      fill: C.glass,
      stroke: C.border,
      strokeWeight: 1,
    }),
  );
  const g = steps.length - 1;
  add(text(g, "Set", { fontSize: 11, fontStyle: "SemiBold", fill: C.fg }));
  return g;
}

function buildDesktop(p, originX, originY) {
  const frameParams = p.preset
    ? { preset: p.preset, x: originX, y: originY, name: `${p.label} · Machines` }
    : {
        x: originX,
        y: originY,
        width: p.width,
        height: p.height,
        name: `${p.label} · Machines`,
      };
  add(
    cmd("frame.create", {
      ...frameParams,
      props: {
        fill: C.bg,
        layout: "horizontal",
        clip: true,
        cornerRadius: p.paradigm === "spatial" ? 28 : 12,
      },
    }),
  );
  const root = steps.length - 1;

  // Sidebar
  add(
    frame(root, "Sidebar", {
      layout: "vertical",
      gap: 16,
      padding: 16,
      width: 220,
      sizingV: "fill",
      fill: C.surface,
      stroke: C.border,
      strokeWeight: 1,
    }),
  );
  const side = steps.length - 1;
  add(
    text(side, "Wawona", {
      fontSize: 18,
      fontStyle: "Bold",
      fill: C.fg,
    }),
  );
  add(text(side, "Library", { fontSize: 11, fill: C.muted }));
  for (const [label, badge] of [
    ["Machines", "5"],
    ["Sessions", "1"],
  ]) {
    add(
      frame(side, label, {
        layout: "horizontal",
        mainAlign: "spaceBetween",
        crossAlign: "center",
        padding: [8, 10, 8, 10],
        cornerRadius: 10,
        fill: label === "Machines" ? "#3D9CFF33" : "none",
        sizingH: "fill",
      }),
    );
    const item = steps.length - 1;
    add(text(item, label, { fontSize: 13, fill: C.fg }));
    add(text(item, badge, { fontSize: 12, fill: C.muted }));
  }
  add(
    text(side, "Images / Runtimes = concept only", {
      fontSize: 10,
      fill: C.muted,
      sizingH: "fill",
    }),
  );

  // Center list
  add(
    frame(root, "Catalog", {
      layout: "vertical",
      gap: 12,
      padding: 20,
      sizingH: "fill",
      sizingV: "fill",
      fill: C.bg,
    }),
  );
  const catalog = steps.length - 1;
  add(
    frame(catalog, "Header", {
      layout: "horizontal",
      mainAlign: "spaceBetween",
      crossAlign: "center",
      sizingH: "fill",
    }),
  );
  const header = steps.length - 1;
  add(
    frame(header, "Titles", {
      layout: "vertical",
      gap: 4,
      sizingH: "fill",
    }),
  );
  const titles = steps.length - 1;
  add(
    text(titles, "Machines", {
      fontSize: 28,
      fontStyle: "Bold",
      fill: C.fg,
    }),
  );
  add(
    text(titles, "5 machines · 2 pinned · 1 running", {
      fontSize: 12,
      fill: C.muted,
    }),
  );
  add(
    frame(header, "Actions", {
      layout: "horizontal",
      gap: 8,
      crossAlign: "center",
    }),
  );
  const actions = steps.length - 1;
  gearButton(actions);
  primaryButton(actions, "New");

  for (const m of machines) machineRow(catalog, m);

  // Inspector
  add(
    frame(root, "Inspector", {
      layout: "vertical",
      gap: 12,
      padding: 16,
      width: 280,
      sizingV: "fill",
      fill: C.surface,
      stroke: C.border,
      strokeWeight: 1,
    }),
  );
  const insp = steps.length - 1;
  add(
    text(insp, "Sample Linux VM", {
      fontSize: 18,
      fontStyle: "Bold",
      fill: C.fg,
    }),
  );
  primaryButton(insp, "Open Session");
  for (const [k, v] of [
    ["Runtime", "NixOS (planned)"],
    ["Connection", "Local"],
    ["Display", "Wayland (Wawona)"],
    ["Graphics", "Metal / ANGLE"],
  ]) {
    add(
      frame(insp, k, {
        layout: "horizontal",
        mainAlign: "spaceBetween",
        crossAlign: "center",
        padding: [8, 10, 8, 10],
        cornerRadius: 10,
        fill: C.surfaceHi,
        sizingH: "fill",
      }),
    );
    const row = steps.length - 1;
    add(text(row, k, { fontSize: 12, fill: C.muted }));
    add(text(row, v, { fontSize: 12, fill: C.fg }));
  }
  add(
    text(insp, "Settings opens as cover (gear), not a root tab.", {
      fontSize: 11,
      fill: C.muted,
      sizingH: "fill",
    }),
  );
}

function buildPhone(p, originX, originY) {
  add(
    cmd("frame.create", {
      preset: p.preset,
      x: originX,
      y: originY,
      name: `${p.label} · Machines`,
      props: {
        fill: C.bg,
        layout: "vertical",
        padding: [54, 16, 24, 16],
        gap: 12,
        clip: true,
      },
    }),
  );
  const root = steps.length - 1;
  add(
    frame(root, "Top", {
      layout: "horizontal",
      mainAlign: "spaceBetween",
      crossAlign: "center",
      sizingH: "fill",
    }),
  );
  const top = steps.length - 1;
  add(text(top, "Machines", { fontSize: 28, fontStyle: "Bold", fill: C.fg }));
  gearButton(top);
  add(
    frame(root, "Search", {
      layout: "horizontal",
      padding: [10, 12, 10, 12],
      cornerRadius: 12,
      fill: C.glass,
      stroke: C.border,
      strokeWeight: 1,
      sizingH: "fill",
    }),
  );
  const search = steps.length - 1;
  add(text(search, "Search machines…", { fontSize: 13, fill: C.muted }));
  for (const m of machines) machineRow(root, m);
  add(
    text(root, "No Machines|Settings tab bar. Gear = Settings cover.", {
      fontSize: 10,
      fill: C.muted,
      sizingH: "fill",
    }),
  );
}

function buildWatch(p, originX, originY) {
  const params = p.preset
    ? { preset: p.preset, x: originX, y: originY }
    : { x: originX, y: originY, width: p.width, height: p.height };
  add(
    cmd("frame.create", {
      ...params,
      name: `${p.label} · Machines`,
      props: {
        fill: C.bg,
        layout: "vertical",
        padding: 8,
        gap: 6,
        clip: true,
        cornerRadius: 40,
      },
    }),
  );
  const root = steps.length - 1;
  add(
    frame(root, "Head", {
      layout: "horizontal",
      mainAlign: "spaceBetween",
      sizingH: "fill",
    }),
  );
  const head = steps.length - 1;
  add(text(head, "Machines", { fontSize: 13, fontStyle: "Bold", fill: C.fg }));
  add(text(head, "Set", { fontSize: 10, fill: C.muted }));
  for (const m of machines.slice(0, 3)) {
    add(
      frame(root, m.name, {
        layout: "vertical",
        gap: 2,
        padding: 6,
        cornerRadius: 10,
        fill: m.selected ? "#3D9CFF33" : C.glass,
        sizingH: "fill",
      }),
    );
    const row = steps.length - 1;
    add(text(row, m.name, { fontSize: 10, fontStyle: "SemiBold", fill: C.fg }));
    add(text(row, m.status, { fontSize: 9, fill: m.statusColor }));
  }
}

function buildTv(p, originX, originY) {
  add(
    cmd("frame.create", {
      preset: p.preset || "TV",
      x: originX,
      y: originY,
      name: `${p.label} · Machines`,
      props: {
        fill: C.bg,
        layout: "vertical",
        padding: 40,
        gap: 24,
        clip: true,
      },
    }),
  );
  const root = steps.length - 1;
  add(
    frame(root, "Header", {
      layout: "horizontal",
      mainAlign: "spaceBetween",
      crossAlign: "center",
      sizingH: "fill",
      fill: C.bg,
    }),
  );
  const header = steps.length - 1;
  add(text(header, "Machines", { fontSize: 42, fontStyle: "Bold", fill: C.fg }));
  gearButton(header);
  add(
    frame(root, "Focus row", {
      layout: "horizontal",
      gap: 20,
      sizingH: "fill",
      fill: C.bg,
    }),
  );
  const row = steps.length - 1;
  for (const m of machines) {
    add(
      frame(row, m.name, {
        layout: "vertical",
        gap: 10,
        padding: 20,
        width: 260,
        height: 320,
        cornerRadius: 20,
        fill: m.selected ? "#3D9CFF44" : C.surface,
        stroke: m.selected ? C.primary : C.border,
        strokeWeight: m.selected ? 3 : 1,
      }),
    );
    const card = steps.length - 1;
    add(
      cmd("node.create", {
        type: "rectangle",
        parent: { $step: card },
        width: 220,
        height: 140,
        props: { fill: C.surfaceHi, cornerRadius: 12 },
      }),
    );
    add(text(card, m.name, { fontSize: 20, fontStyle: "Bold", fill: C.fg }));
    add(text(card, m.status, { fontSize: 16, fill: m.statusColor }));
  }
}

let x = 0;
let y = 0;
let maxRowH = 0;
const gap = 120;

for (const p of [...platforms, ...extra]) {
  const before = steps.length;
  if (p.paradigm === "phone-stack") buildPhone(p, x, y);
  else if (p.paradigm === "watch") buildWatch(p, x, y);
  else if (p.paradigm === "tv-focus") buildTv(p, x, y);
  else buildDesktop(p, x, y);

  // Place reference under / beside: small caption
  add(
    cmd("node.create", {
      type: "text",
      x,
      y: y - 28,
      text: `${p.id}  ·  ${p.paradigm}  ·  ref ${p.ref}`,
      name: `label/${p.id}`,
      props: { fontSize: 12, fill: "#8E8E93" },
    }),
  );

  // Advance grid
  const w = p.width || (p.paradigm === "watch" ? 220 : p.paradigm === "phone-stack" ? 420 : 1600);
  const h = p.height || (p.paradigm === "watch" ? 280 : p.paradigm === "phone-stack" ? 900 : 1100);
  maxRowH = Math.max(maxRowH, h);
  x += w + gap;
  if (x > 5200) {
    x = 0;
    y += maxRowH + gap + 40;
    maxRowH = 0;
  }
  void before;
}

const outJson = join(__dirname, "build-all-targets.json");
writeFileSync(outJson, JSON.stringify(steps, null, 2));
console.log(`Wrote ${steps.length} commands → ${outJson}`);
console.log(`Platforms: ${platforms.length} ALL_TARGETS + ${extra.length} extra`);

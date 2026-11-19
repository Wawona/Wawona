#!/usr/bin/env bun
/**
 * macOS flagship Machines UI — match macOS.png comp (Operate + glass valley).
 * Skills: frontend-design, impeccable, better-ui, figcraft-design.
 */
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const ref = join(root, "refs", "macOS.png");

const cmd = (command, params = {}) => ({ command, params });
const steps = [];
const add = (...xs) => steps.push(...xs);

const T = {
  glass: "#1A1628D9",
  glassHi: "#2A2440E6",
  glassRow: "#FFFFFF14",
  glassRowSel: "#3D9CFF33",
  fg: "#F5F7FF",
  muted: "#B4B9D0",
  border: "#FFFFFF2E",
  primary: "#3D9CFF",
  onPrimary: "#FFFFFF",
  running: "#34C759",
  stopped: "#8E8E93",
  ready: "#5AC8FA",
  trafficR: "#FF5F57",
  trafficY: "#FEBC2E",
  trafficG: "#28C840",
};

function text(parent, characters, props, name) {
  return cmd("node.create", {
    type: "text",
    parent: { $step: parent },
    text: characters,
    name: name || characters.slice(0, 28),
    props,
  });
}

function frame(parent, name, props) {
  // FigCraft defaults missing fill to opaque white (breaks dark UI text).
  const next = { fill: "#00000000", ...props };
  return cmd("node.create", {
    type: "frame",
    parent: typeof parent === "number" ? { $step: parent } : parent,
    name,
    props: next,
  });
}

add(cmd("file.rename", { name: "Wawona macOS Machines v2" }));
add(cmd("page.rename", { name: "Comp + Editable" }));
add(cmd("page.setBackground", { color: "#0A0814" }));

// --- Comp reference (authority) ---
add(
  cmd("file.placeImage", {
    path: ref,
    x: 0,
    y: 40,
    width: 1512,
    name: "COMP macOS.png (authority)",
  }),
);
add(
  cmd("node.create", {
    type: "text",
    x: 0,
    y: 8,
    text: "COMP (do not edit) · editable reconstruction →",
    name: "comp label",
    props: { fontSize: 13, fill: "#8E8E93" },
  }),
);

// --- Editable MacBook frame ---
const originX = 1600;
const originY = 40;
add(
  cmd("frame.create", {
    preset: 'MacBook Pro 14"',
    x: originX,
    y: originY,
    name: "macOS · Machines (editable)",
    props: {
      fill: "#1B1430",
      layout: "vertical",
      clip: true,
      cornerRadius: 12,
    },
  }),
);
const win = steps.length - 1;
// Landscape wash behind chrome (absolute)
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: win },
    name: "landscape wash",
    x: 0,
    y: 0,
    width: 1512,
    height: 982,
    props: {
      absolute: true,
      fill: "#3A2850",
    },
  }),
);

// Title bar
add(
  frame(win, "Title bar", {
    layout: "horizontal",
    crossAlign: "center",
    gap: 12,
    padding: [10, 14, 10, 14],
    sizingH: "fill",
    fill: "#0E0C18CC",
    stroke: T.border,
    strokeWeight: 1,
  }),
);
const titleBar = steps.length - 1;
add(
  frame(titleBar, "Traffic", {
    layout: "horizontal",
    gap: 8,
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
  text(titleBar, "Wawona Compositor", {
    fontSize: 13,
    fontStyle: "SemiBold",
    fill: T.fg,
  }),
);
add(
  text(titleBar, "Universal Wayland Compositor", {
    fontSize: 11,
    fill: T.muted,
  }),
);
add(
  frame(titleBar, "Spacer", {
    sizingH: "fill",
    sizingV: "fixed",
    height: 1,
    fill: "#00000000",
  }),
);
add(
  frame(titleBar, "Search", {
    layout: "horizontal",
    padding: [6, 12, 6, 12],
    cornerRadius: 8,
    fill: T.glassRow,
    stroke: T.border,
    strokeWeight: 1,
    width: 200,
  }),
);
const search = steps.length - 1;
add(text(search, "Search  ⌘F", { fontSize: 11, fill: T.muted }));
add(
  frame(titleBar, "Settings", {
    layout: "horizontal",
    mainAlign: "center",
    crossAlign: "center",
    width: 32,
    height: 28,
    cornerRadius: 8,
    fill: T.glassRow,
    stroke: T.border,
    strokeWeight: 1,
  }),
);
const gear = steps.length - 1;
add(text(gear, "⚙︎", { fontSize: 14, fill: T.fg }));

// Body: 3 columns
add(
  frame(win, "Body", {
    layout: "horizontal",
    gap: 0,
    sizingH: "fill",
    sizingV: "fill",
    fill: "#00000000",
  }),
);
const body = steps.length - 1;

// Sidebar
add(
  frame(body, "Sidebar", {
    layout: "vertical",
    gap: 14,
    padding: 14,
    width: 228,
    sizingV: "fill",
    fill: T.glass,
    stroke: T.border,
    strokeWeight: 1,
  }),
);
const side = steps.length - 1;
add(text(side, "Library", { fontSize: 11, fill: T.muted }));
for (const [label, badge, on] of [
  ["Machines", "5", true],
  ["Sessions", "1", false],
]) {
  add(
    frame(side, label, {
      layout: "horizontal",
      mainAlign: "spaceBetween",
      crossAlign: "center",
      padding: [8, 10, 8, 10],
      cornerRadius: 10,
      fill: on ? T.glassRowSel : "none",
      stroke: on ? T.primary : "none",
      strokeWeight: on ? 1 : 0,
      sizingH: "fill",
    }),
  );
  const item = steps.length - 1;
  add(text(item, label, { fontSize: 13, fontStyle: "SemiBold", fill: T.fg }));
  add(text(item, badge, { fontSize: 12, fill: T.muted }));
}
add(text(side, "Favorites", { fontSize: 11, fill: T.muted }));
for (const [label, badge] of [
  ["Pinned", "2"],
  ["Recent", ""],
]) {
  add(
    frame(side, label, {
      layout: "horizontal",
      mainAlign: "spaceBetween",
      padding: [6, 10, 6, 10],
      sizingH: "fill",
    }),
  );
  const item = steps.length - 1;
  add(text(item, label, { fontSize: 12, fill: T.fg }));
  if (badge) add(text(item, badge, { fontSize: 11, fill: T.muted }));
}
add(text(side, "Tags", { fontSize: 11, fill: T.muted }));
for (const [label, color, n] of [
  ["Work", "#5AC8FA", "2"],
  ["Dev", "#BF5AF2", "3"],
  ["Test", "#34C759", "1"],
]) {
  add(
    frame(side, `tag-${label}`, {
      layout: "horizontal",
      gap: 8,
      crossAlign: "center",
      padding: [4, 8, 4, 8],
      sizingH: "fill",
    }),
  );
  const row = steps.length - 1;
  add(
    cmd("node.create", {
      type: "ellipse",
      parent: { $step: row },
      width: 8,
      height: 8,
      props: { fill: color },
    }),
  );
  add(text(row, label, { fontSize: 12, fill: T.fg }));
  add(text(row, n, { fontSize: 11, fill: T.muted }));
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
add(text(xfer, "Transfers", { fontSize: 11, fill: T.muted }));
add(text(xfer, "NixOS vm.qcow2", { fontSize: 12, fontStyle: "SemiBold", fill: T.fg }));
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: xfer },
    name: "progress track",
    width: 180,
    height: 6,
    props: { fill: "#FFFFFF22", cornerRadius: 3 },
  }),
);
add(text(xfer, "3.2 / 5.6 GB · 12.4 MB/s", { fontSize: 10, fill: T.muted }));

// Catalog
add(
  frame(body, "Catalog", {
    layout: "vertical",
    gap: 12,
    padding: 18,
    sizingH: "fill",
    sizingV: "fill",
    fill: "#120F1CCC",
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
const hact = steps.length - 1;
add(
  frame(hact, "New", {
    layout: "horizontal",
    mainAlign: "center",
    crossAlign: "center",
    padding: [8, 14, 8, 14],
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
    color: T.running,
    selected: true,
    time: "12m",
  },
  {
    name: "Dev Container",
    kind: "Container · OCI",
    status: "Stopped",
    color: T.stopped,
    selected: false,
  },
  {
    name: "Native Shell",
    kind: "Native Shell · Local",
    status: "Running",
    color: T.running,
    selected: false,
    time: "3m",
  },
  {
    name: "Relay Wasm",
    kind: "Native Shell · WASI",
    status: "Ready",
    color: T.ready,
    selected: false,
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
      width: 48,
      height: 48,
      props: {
        fill: "#4A3860",
        cornerRadius: 10,
        stroke: T.border,
        strokeWeight: 1,
      },
    }),
  );
  add(
    frame(row, "meta", {
      layout: "vertical",
      gap: 3,
      sizingH: "fill",
    }),
  );
  const meta = steps.length - 1;
  add(text(meta, m.name, { fontSize: 14, fontStyle: "SemiBold", fill: T.fg }));
  add(text(meta, m.kind, { fontSize: 11, fill: T.muted }));
  add(
    frame(row, "status", {
      layout: "horizontal",
      gap: 6,
      padding: [5, 10, 5, 10],
      crossAlign: "center",
      cornerRadius: 999,
      fill: "#00000066",
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
}

// Inspector
add(
  frame(body, "Inspector", {
    layout: "vertical",
    gap: 12,
    padding: 16,
    width: 300,
    sizingV: "fill",
    fill: T.glass,
    stroke: T.border,
    strokeWeight: 1,
  }),
);
const insp = steps.length - 1;
add(
  cmd("node.create", {
    type: "rectangle",
    parent: { $step: insp },
    name: "hero thumb",
    width: 268,
    height: 140,
    props: {
      fill: "#5A3A58",
      cornerRadius: 12,
      stroke: T.border,
      strokeWeight: 1,
    },
  }),
);
add(text(insp, "Sample Linux VM", { fontSize: 18, fontStyle: "Bold", fill: T.fg }));
add(text(insp, "Virtual Machine · NixOS · Running 12m", { fontSize: 11, fill: T.muted }));
add(
  frame(insp, "Primary actions", {
    layout: "horizontal",
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
    padding: [10, 14, 10, 14],
    cornerRadius: 10,
    fill: T.primary,
    sizingH: "fill",
  }),
);
const open = steps.length - 1;
add(text(open, "Open Session", { fontSize: 13, fontStyle: "SemiBold", fill: T.onPrimary }));
for (const label of ["Pause", "Stop"]) {
  add(
    frame(pact, label, {
      layout: "horizontal",
      mainAlign: "center",
      crossAlign: "center",
      padding: [10, 12, 10, 12],
      cornerRadius: 10,
      fill: T.glassHi,
      stroke: T.border,
      strokeWeight: 1,
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
      padding: [6, 10, 6, 10],
      cornerRadius: 8,
      fill: on ? T.glassRowSel : "none",
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
  ["Storage", "6.4 / 20 GB"],
]) {
  add(
    frame(insp, k, {
      layout: "horizontal",
      mainAlign: "spaceBetween",
      crossAlign: "center",
      padding: [8, 10, 8, 10],
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
  frame(insp, "Tags", {
    layout: "horizontal",
    gap: 6,
    sizingH: "fill",
  }),
);
const tags = steps.length - 1;
for (const [label, fill] of [
  ["Work", "#5AC8FA44"],
  ["Dev", "#BF5AF244"],
]) {
  add(
    frame(tags, label, {
      layout: "horizontal",
      padding: [4, 10, 4, 10],
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
  cmd("node.create", {
    type: "text",
    x: originX,
    y: 8,
    text: "EDITABLE · glass Operate deck · Settings = title-bar control",
    name: "edit label",
    props: { fontSize: 13, fill: "#8E8E93" },
  }),
);

const out = join(__dirname, "build-macos-v2.json");
writeFileSync(out, JSON.stringify(steps, null, 2));
console.log(`Wrote ${steps.length} commands → ${out}`);

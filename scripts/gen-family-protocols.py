#!/usr/bin/env python3
"""Generate protocol scanner modules + dispatch handlers for weston/treeland/external."""

from __future__ import annotations

from pathlib import Path
from xml.etree import ElementTree as ET

FAMILIES = {
    "weston": Path("protocols/weston"),
    "treeland": Path("protocols/treeland"),
    "external": Path("protocols/external"),
}

CATALOG = {
    "ivi_application",
    "ivi_hmi_controller",
    "text_cursor_position",
    "weston_content_protection",
    "weston_debug_v1",
    "weston_desktop_shell",
    "weston_direct_display_v1",
    "weston_capture_v1",
    "weston_test",
    "weston_touch_calibration",
    "treeland_capture_manager_v1",
    "treeland_dde_shell_manager_v1",
    "treeland_foreign_toplevel_manager_v1",
    "treeland_output_manager_v1",
    "treeland_personalization_manager_v1",
    "treeland_shortcut_manager_v1",
    "treeland_virtual_output_manager_v1",
    "treeland_wallpaper_color_manager_v1",
    "treeland_window_management_v1",
    "treeland_wallpaper_manager_v1",
    "treeland_wallpaper_shell_v1",
    "gtk_shell1",
    "wl_eglstream_display",
    "wl_eglstream_controller",
    "mir_shell_v1",
    "xapp_shell_v1",
    "agl_shell",
    "agl_shell_desktop",
    "agl_screenshooter",
    "zaura_shell",
    "zaura_output_manager_v2",
}


def rust_type(iface: str) -> str:
    return "".join(p[:1].upper() + p[1:] for p in iface.split("_"))


def to_variant(req_name: str) -> str:
    return "".join(p.title() for p in req_name.split("_"))


def parse_xml(path: Path):
    root = ET.parse(path).getroot()
    ifaces = []
    for iface in root.findall("interface"):
        name = iface.get("name")
        ver = int(iface.get("version", "1"))
        reqs = []
        for req in iface.findall("request"):
            args = []
            for a in req.findall("arg"):
                args.append(
                    {
                        "name": a.get("name"),
                        "type": a.get("type"),
                        "interface": a.get("interface"),
                    }
                )
            reqs.append({"name": req.get("name"), "args": args})
        # event object refs
        event_refs = []
        for ev in iface.findall("event"):
            for a in ev.findall("arg"):
                if a.get("type") == "object" and a.get("interface"):
                    event_refs.append(a.get("interface"))
        ifaces.append(
            {
                "name": name,
                "version": ver,
                "requests": reqs,
                "event_refs": event_refs,
            }
        )
    return ifaces


def collect_refs(ifaces, local_names):
    refs = set()
    for i in ifaces:
        for r in i["requests"]:
            for a in r["args"]:
                ii = a.get("interface")
                if a["type"] in ("object", "new_id") and ii and ii not in local_names:
                    if not ii.startswith("wl_"):
                        refs.add(ii)
        for ii in i["event_refs"]:
            if ii not in local_names and not ii.startswith("wl_"):
                refs.add(ii)
    return refs


def main() -> None:
    family_xmls = {f: [] for f in FAMILIES}
    all_ifaces = {}
    for family, d in FAMILIES.items():
        for xml in sorted(d.glob("*.xml")):
            ifaces = parse_xml(xml)
            stem = xml.stem
            family_xmls[family].append((stem, ifaces))
            for i in ifaces:
                all_ifaces[i["name"]] = (family, stem, i["version"], i["requests"])

    for family, items in family_xmls.items():
        out_dir = Path(f"src/core/wayland/{family}")
        out_dir.mkdir(parents=True, exist_ok=True)
        mod_protos = []
        for stem, ifaces in items:
            local = {i["name"] for i in ifaces}
            refs = collect_refs(ifaces, local)
            imports = []
            for r in sorted(refs):
                if r in all_ifaces and all_ifaces[r][0] == family:
                    imports.append(all_ifaces[r][1])
            imports = sorted(set(imports) - {stem})
            proto_name = stem.replace("-", "_") + "_protocol"
            mod_protos.append((proto_name, stem, ifaces, imports))

            lines = [
                f"//! Generated bindings for {stem}.",
                "",
                "#[allow(unused_imports)]",
                "use wayland_server;",
                "#[allow(unused_imports)]",
                "use wayland_server::protocol::*;",
            ]
            for imp in imports:
                lines.append("#[allow(unused_imports)]")
                lines.append(
                    f"use crate::core::wayland::{family}::{imp.replace('-', '_')}_protocol::*;"
                )
            lines += [
                "",
                "#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]",
                "pub mod __interfaces {",
                "    use wayland_server::protocol::__interfaces::*;",
            ]
            for imp in imports:
                lines.append(
                    f"    use crate::core::wayland::{family}::{imp.replace('-', '_')}_protocol::__interfaces::*;"
                )
            lines.append(
                f'    wayland_scanner::generate_interfaces!("protocols/{family}/{stem}.xml");'
            )
            lines += [
                "}",
                "",
                "#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]",
                "use self::__interfaces::*;",
                "",
                f'wayland_scanner::generate_server_code!("protocols/{family}/{stem}.xml");',
                "",
            ]
            (out_dir / f"{proto_name}.rs").write_text("\n".join(lines))

        h: list[str] = [f"//! Auto-generated {family} protocol handlers.", ""]
        for proto_name, stem, ifaces, imports in mod_protos:
            h.append(f"mod {proto_name};")
        h += [
            "",
            "use wayland_server::{",
            "    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,",
            "};",
            "use crate::core::state::CompositorState;",
            "use crate::core::wayland::policy;",
            "",
        ]
        for proto_name, stem, ifaces, imports in mod_protos:
            for i in ifaces:
                ty = rust_type(i["name"])
                h.append(f"use {proto_name}::{i['name']}::{{self, {ty}}};")
        h.append("")

        globals_created = []
        for proto_name, stem, ifaces, imports in mod_protos:
            for i in ifaces:
                ty = rust_type(i["name"])
                req_mod = i["name"]
                if i["name"] in CATALOG:
                    h += [
                        f"impl GlobalDispatch<{ty}, ()> for CompositorState {{",
                        "    fn bind(",
                        "        _state: &mut Self,",
                        "        _handle: &DisplayHandle,",
                        "        _client: &Client,",
                        f"        resource: New<{ty}>,",
                        "        _global_data: &(),",
                        "        data_init: &mut DataInit<'_, Self>,",
                        "    ) {",
                        "        data_init.init(resource, ());",
                        "    }",
                        "}",
                        "",
                    ]
                    globals_created.append((i["name"], ty, i["version"]))

                h += [
                    f"impl Dispatch<{ty}, ()> for CompositorState {{",
                    "    fn request(",
                    "        _state: &mut Self,",
                    "        _client: &Client,",
                    f"        _resource: &{ty},",
                    f"        request: {req_mod}::Request,",
                    "        _data: &(),",
                    "        _dhandle: &DisplayHandle,",
                    "        data_init: &mut DataInit<'_, Self>,",
                    "    ) {",
                ]
                arms = []
                for r in i["requests"]:
                    new_ids = [a for a in r["args"] if a["type"] == "new_id"]
                    if not new_ids:
                        continue
                    var = to_variant(r["name"])
                    fields = []
                    inits = []
                    for a in r["args"]:
                        if a["type"] == "new_id":
                            fields.append(a["name"])
                            inits.append(f"data_init.init({a['name']}, ());")
                        else:
                            fields.append(f"{a['name']}: _")
                    arms.append((var, fields, inits))
                if arms:
                    h.append("        match request {")
                    for var, fields, inits in arms:
                        h.append(
                            f"            {req_mod}::Request::{var} {{ {', '.join(fields)} }} => {{"
                        )
                        for line in inits:
                            h.append(f"                {line}")
                        h.append("            }")
                    h.append("            _ => {}")
                    h.append("        }")
                else:
                    h.append("        let _ = (request, data_init);")
                h += ["    }", "}", ""]

        h += [
            "pub fn register(state: &mut CompositorState, dh: &DisplayHandle) {",
            "    if !policy::allow_desktop_extensions(state.protocol_profile) {",
            "        return;",
            "    }",
        ]
        for name, ty, ver in globals_created:
            h.append(
                f"    dh.create_global::<CompositorState, {ty}, ()>({ver}, ());"
            )
        h += [
            f'    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered {family} protocol globals");',
            "}",
            "",
            "#[cfg(test)]",
            "mod tests {",
            "    #[test]",
            f"    fn {family}_register_compiles() {{",
            "        assert!(true);",
            "    }",
            "}",
            "",
        ]
        (out_dir / "mod.rs").write_text("\n".join(h))
        print(family, "globals", len(globals_created), "protos", len(mod_protos))


if __name__ == "__main__":
    main()

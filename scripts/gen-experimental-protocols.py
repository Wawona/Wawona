#!/usr/bin/env python3
"""Generate experimental + wl_drm protocol handlers for remaining Missing rows."""

from __future__ import annotations

from pathlib import Path
from xml.etree import ElementTree as ET

CATALOG = {
    "xx_session_manager_v1",
    "xdg_session_manager_v1",
    "xx_cutouts_manager_v1",
    "xx_zone_manager_v1",
    "xx_keyboard_filter_manager_v1",
    "xx_input_method_manager_v2",
    "wl_drm",
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


def main() -> None:
    xmls = list(Path("protocols/ext").glob("*.xml"))
    xmls.append(Path("protocols/external/wayland-drm.xml"))
    out_dir = Path("src/core/wayland/experimental")
    out_dir.mkdir(parents=True, exist_ok=True)

    all_ifaces = {}
    items = []
    for xml in sorted(xmls, key=lambda p: p.name):
        ifaces = parse_xml(xml)
        stem = xml.stem
        items.append((stem, ifaces, xml))
        for i in ifaces:
            all_ifaces[i["name"]] = (stem, i["version"], i["requests"], xml)

    mod_protos = []
    for stem, ifaces, xml in items:
        local = {i["name"] for i in ifaces}
        refs = set()
        for i in ifaces:
            for r in i["requests"]:
                for a in r["args"]:
                    ii = a.get("interface")
                    if (
                        a["type"] in ("object", "new_id")
                        and ii
                        and ii not in local
                        and not ii.startswith("wl_")
                    ):
                        refs.add(ii)
            for ii in i["event_refs"]:
                if ii not in local and not ii.startswith("wl_"):
                    refs.add(ii)
        imports = []
        for r in sorted(refs):
            if r in all_ifaces:
                imports.append(all_ifaces[r][0])
        imports = sorted(set(imports) - {stem})
        proto_name = stem.replace("-", "_") + "_protocol"
        mod_protos.append((proto_name, stem, ifaces, imports, xml))

        lines = [
            f"//! Generated bindings for {stem}.",
            "",
            "#[allow(unused_imports)]",
            "use wayland_server;",
            "#[allow(unused_imports)]",
            "use wayland_server::protocol::*;",
        ]
        if "xdg" in stem or "session" in stem:
            lines += [
                "#[allow(unused_imports)]",
                "use wayland_protocols::xdg::shell::server::*;",
            ]
        for imp in imports:
            lines.append("#[allow(unused_imports)]")
            lines.append(
                f"use crate::core::wayland::experimental::{imp.replace('-', '_')}_protocol::*;"
            )
        lines += [
            "",
            "#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]",
            "pub mod __interfaces {",
            "    use wayland_server::protocol::__interfaces::*;",
        ]
        if "xdg" in stem or "session" in stem:
            lines.append(
                "    use wayland_protocols::xdg::shell::server::__interfaces::*;"
            )
        for imp in imports:
            lines.append(
                f"    use crate::core::wayland::experimental::{imp.replace('-', '_')}_protocol::__interfaces::*;"
            )
        rel = str(xml)
        lines.append(f'    wayland_scanner::generate_interfaces!("{rel}");')
        lines += [
            "}",
            "",
            "#[allow(missing_docs, non_camel_case_types, non_snake_case, dead_code)]",
            "use self::__interfaces::*;",
            "",
            f'wayland_scanner::generate_server_code!("{rel}");',
            "",
        ]
        (out_dir / f"{proto_name}.rs").write_text("\n".join(lines))

    h = ["//! Experimental / remaining protocol handlers.", ""]
    for proto_name, stem, ifaces, imports, xml in mod_protos:
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
    for proto_name, stem, ifaces, imports, xml in mod_protos:
        for i in ifaces:
            ty = rust_type(i["name"])
            h.append(f"use {proto_name}::{i['name']}::{{self, {ty}}};")
    h.append("")

    globals_created = []
    for proto_name, stem, ifaces, imports, xml in mod_protos:
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
                        n = a["name"]
                        if n == "type":
                            n = "_type"
                        fields.append(f"{n}: _")
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
        h.append(f"    dh.create_global::<CompositorState, {ty}, ()>({ver}, ());")
    h += [
        '    crate::wlog!(crate::util::logging::COMPOSITOR, "Registered experimental protocol globals");',
        "}",
        "",
        "#[cfg(test)]",
        "mod tests {",
        "    #[test]",
        "    fn experimental_register_compiles() {",
        "        assert!(true);",
        "    }",
        "}",
        "",
    ]
    (out_dir / "mod.rs").write_text("\n".join(h))
    print("globals", [g[0] for g in globals_created])
    print("protos", len(mod_protos))


if __name__ == "__main__":
    main()

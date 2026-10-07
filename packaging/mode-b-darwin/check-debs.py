#!/usr/bin/env python3
"""Sanitize, syntax-check, and checksum Mode B Darwin CLI debs and apt index."""

from __future__ import annotations

import gzip
import hashlib
import io
import re
import tarfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"
REPO = ROOT / "repo"
fails: list[str] = []
warns: list[str] = []
oks: list[str] = []


def fail(msg: str) -> None:
    fails.append(msg)
    print("FAIL", msg)


def warn(msg: str) -> None:
    warns.append(msg)
    print("WARN", msg)


def ok(msg: str) -> None:
    oks.append(msg)
    print("OK  ", msg)


SECRETISH = re.compile(
    rb"(-----BEGIN|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-"
    rb"|discord\.com/api/webhooks)"
)
PKG_NAME = re.compile(r"^[a-z0-9][a-z0-9+\-\.]+$")
VER = re.compile(r"^[0-9][0-9A-Za-z\.\+\-~]*$")


def parse_ar(data: bytes) -> list[dict]:
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("missing !<arch> magic")
    off = 8
    members = []
    while off < len(data):
        if off + 60 > len(data):
            raise ValueError(f"truncated ar header at {off}")
        hdr = data[off : off + 60]
        if hdr[58:60] != b"`\n":
            raise ValueError(f"bad ar end at {off}")
        name = hdr[0:16].decode("ascii").rstrip()
        mode = hdr[40:48].decode("ascii").strip()
        size = int(hdr[48:58].decode("ascii").strip())
        off += 60
        body = data[off : off + size]
        if len(body) != size:
            raise ValueError(f"{name}: declared {size} got {len(body)}")
        off += size
        if size % 2 == 1:
            if off >= len(data) or data[off : off + 1] not in (b"\n", b"\0"):
                raise ValueError(f"{name}: missing odd-size pad")
            off += 1
        members.append({"name": name, "mode": mode, "size": size, "body": body})
    if off != len(data):
        raise ValueError(f"ar consumed {off} of {len(data)}")
    return members


def gzip_math(blob: bytes, label: str) -> bytes:
    d = gzip.decompress(blob)
    crc = zlib.crc32(d) & 0xFFFFFFFF
    isize = len(d) & 0xFFFFFFFF
    stored_crc = int.from_bytes(blob[-8:-4], "little")
    stored_isize = int.from_bytes(blob[-4:], "little")
    if stored_crc != crc:
        fail(f"{label}: gzip CRC32 stored={stored_crc:08x} computed={crc:08x}")
    else:
        ok(f"{label}: gzip CRC32 {crc:08x}")
    if stored_isize != isize:
        fail(f"{label}: gzip ISIZE stored={stored_isize} computed={isize}")
    else:
        ok(f"{label}: gzip ISIZE {isize}")
    return d


def tar_files(blob: bytes, label: str) -> dict[str, bytes]:
    tf = tarfile.open(fileobj=io.BytesIO(blob), mode="r:")
    files = {}
    for ti in tf.getmembers():
        if not ti.isfile():
            continue
        payload = tf.extractfile(ti).read()
        if len(payload) != ti.size:
            fail(f"{label}:{ti.name}: tar size {ti.size} payload {len(payload)}")
        files[ti.name.lstrip("./")] = payload
    return files


def parse_control(text: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    last = None
    for i, line in enumerate(text.splitlines(), 1):
        if line.startswith(" ") or line.startswith("\t"):
            if last is None:
                fail(f"control continuation with no field at line {i}")
            else:
                fields[last] += "\n" + line
            continue
        if ": " not in line and not line.endswith(":"):
            fail(f"control line {i} not Field: value: {line!r}")
            continue
        k, _, v = line.partition(":")
        k, v = k.strip(), v.strip()
        if k in fields:
            fail(f"duplicate control field {k}")
        fields[k] = v
        last = k
    return fields


def main() -> int:
    debs = sorted(OUT.glob("*.deb"))
    if len(debs) != 4:
        fail(f"expected 4 debs, found {len(debs)}")
    control_by_pkg: dict[str, dict[str, str]] = {}
    size_by_pkg: dict[str, int] = {}
    hashes: dict[str, dict[str, str]] = {}

    for deb in debs:
        raw = deb.read_bytes()
        size_by_pkg[deb.name] = len(raw)
        hashes[deb.name] = {
            "md5": hashlib.md5(raw).hexdigest(),
            "sha1": hashlib.sha1(raw).hexdigest(),
            "sha256": hashlib.sha256(raw).hexdigest(),
        }
        print(f"\n=== {deb.name} size={len(raw)} ===")
        m = re.match(
            r"^([a-z0-9][a-z0-9+\-\.]*)_([^_]+)_([a-z0-9-]+)\.deb$", deb.name
        )
        if not m:
            fail(f"{deb.name}: filename not name_version_arch.deb")
            continue
        fn_pkg, fn_ver, fn_arch = m.group(1), m.group(2), m.group(3)
        try:
            members = parse_ar(raw)
            ok(f"{deb.name}: ar parse; bytes consumed == file size {len(raw)}")
        except Exception as e:
            fail(f"{deb.name}: ar parse: {e}")
            continue
        names = [x["name"] for x in members]
        if names != ["debian-binary", "control.tar.gz", "data.tar.gz"]:
            fail(f"{deb.name}: member order {names}")
        else:
            ok(f"{deb.name}: member order")
        for mem in members:
            if mem["mode"] not in ("100644", "0100644"):
                fail(f"{deb.name}:{mem['name']}: ar mode {mem['mode']!r} not octal 100644")
            else:
                ok(f"{deb.name}:{mem['name']}: ar mode {mem['mode']}")
        if members[0]["body"] not in (b"2.0\n", b"2.0"):
            fail(f"{deb.name}: debian-binary {members[0]['body']!r}")
        else:
            ok(f"{deb.name}: debian-binary 2.0")
        ctrl_raw = gzip_math(members[1]["body"], f"{deb.name} control.tar.gz")
        data_raw = gzip_math(members[2]["body"], f"{deb.name} data.tar.gz")
        ctrl_files = tar_files(ctrl_raw, f"{deb.name} control")
        data_files = tar_files(data_raw, f"{deb.name} data")
        if "control" not in ctrl_files:
            fail(f"{deb.name}: no control")
            continue
        control = ctrl_files["control"].decode("utf-8")
        if not control.endswith("\n"):
            fail(f"{deb.name}: control missing trailing newline")
        fields = parse_control(control)
        for req in ("Package", "Version", "Architecture", "Maintainer", "Description"):
            if req not in fields:
                fail(f"{deb.name}: missing {req}")
        if fields.get("Package") != fn_pkg:
            fail(f"{deb.name}: Package != filename")
        else:
            ok(f"{deb.name}: Package matches filename")
        if fields.get("Version") != fn_ver:
            fail(f"{deb.name}: Version != filename")
        else:
            ok(f"{deb.name}: Version matches filename")
        if fields.get("Architecture") != fn_arch:
            fail(f"{deb.name}: Architecture != filename")
        else:
            ok(f"{deb.name}: Architecture matches filename")
        if fields.get("Package") and not PKG_NAME.match(fields["Package"]):
            fail(f"{deb.name}: illegal Package name")
        if fields.get("Version") and not VER.match(fields["Version"]):
            fail(f"{deb.name}: illegal Version")
        if fields.get("Version") == "26.10.6":
            if 26 * 10000 + 10 * 100 + 6 != 261006:
                fail("CalVer arithmetic")
            else:
                ok(f"{deb.name}: CalVer 26.10.6 (26*10000+10*100+6=261006)")
        if fields.get("Architecture") not in (
            "iphoneos-arm64",
            "iphoneos-arm",
            "iphoneos-arm64e",
        ):
            fail(f"{deb.name}: unexpected arch")
        data_bytes = sum(len(v) for v in data_files.values())
        expected_inst = (data_bytes + 1023) // 1024
        if "Installed-Size" in fields:
            got = int(fields["Installed-Size"])
            if got != expected_inst:
                fail(
                    f"{deb.name}: Installed-Size {got} != ceil({data_bytes}/1024)={expected_inst}"
                )
            else:
                ok(f"{deb.name}: Installed-Size {got} = ceil({data_bytes}/1024)")
        else:
            warn(f"{deb.name}: no Installed-Size; payload {data_bytes} => {expected_inst} KiB")
        control_by_pkg[fields.get("Package", "")] = fields
        if SECRETISH.search(raw):
            fail(f"{deb.name}: secret-like pattern")
        else:
            ok(f"{deb.name}: no PEM/token/webhook blobs")
        if not any(n.startswith("usr/bin/") for n in data_files):
            warn(f"{deb.name}: no usr/bin payload (docs-only stub)")
        if fields.get("Package") == "wawona-security-tools":
            joined = b" ".join(data_files.values()) + ctrl_files["control"]
            if b"AGPL" not in joined:
                fail(f"{deb.name}: AGPL text missing")
            else:
                ok(f"{deb.name}: AGPL mention")
            if not any(n.endswith("/copyright") for n in data_files):
                fail(f"{deb.name}: missing copyright file")
            else:
                ok(f"{deb.name}: copyright file")

    pkg_text = (REPO / "Packages").read_bytes()
    gz = (REPO / "Packages.gz").read_bytes()
    if gzip.decompress(gz) != pkg_text:
        fail("Packages.gz != Packages")
    else:
        ok(f"Packages.gz == Packages ({len(pkg_text)} bytes)")
    gzip_math(gz, "Packages.gz")

    stanzas: list[dict[str, str]] = []
    cur: dict[str, str] = {}
    last = None
    for line in pkg_text.decode().splitlines():
        if line == "":
            if cur:
                stanzas.append(cur)
                cur = {}
                last = None
            continue
        if line.startswith(" "):
            cur[last] += "\n" + line
            continue
        k, _, v = line.partition(":")
        k, v = k.strip(), v.strip()
        cur[k] = v
        last = k
    if cur:
        stanzas.append(cur)
    if {s.get("Package") for s in stanzas} != set(control_by_pkg):
        fail("Packages set != deb Package set")
    else:
        ok(f"Packages stanzas {len(stanzas)} match debs")

    for s in stanzas:
        name = s.get("Package")
        fn = s.get("Filename")
        if not fn:
            fail(f"Packages {name}: missing Filename")
            continue
        on_disk = (REPO / fn) if not Path(fn).is_absolute() else Path(fn)
        if not on_disk.is_file():
            fail(f"Packages {name}: Filename {fn} does not exist")
        else:
            ok(f"Packages {name}: Filename exists ({on_disk.stat().st_size} bytes)")
        base = Path(fn).name
        actual = size_by_pkg.get(base)
        if "Size" not in s:
            fail(f"Packages {name}: missing Size")
        elif actual is not None and int(s["Size"]) != actual:
            fail(f"Packages {name}: Size {s['Size']} != {actual}")
        elif actual is not None:
            ok(f"Packages {name}: Size {actual}")
        for algo, key in (("md5", "MD5sum"), ("sha1", "SHA1"), ("sha256", "SHA256")):
            if key not in s:
                fail(f"Packages {name}: missing {key}")
            elif hashes.get(base, {}).get(algo) != s[key].lower():
                fail(f"Packages {name}: {key} mismatch")
            else:
                ok(f"Packages {name}: {key} matches file")

    rel = (REPO / "Release").read_text(encoding="utf-8")
    if "SHA256:" not in rel or "MD5Sum:" not in rel:
        fail("Release missing checksum stanzas")
    else:
        for label, hexfn in (
            ("MD5Sum", lambda p: hashlib.md5(p.read_bytes()).hexdigest()),
            ("SHA1", lambda p: hashlib.sha1(p.read_bytes()).hexdigest()),
            ("SHA256", lambda p: hashlib.sha256(p.read_bytes()).hexdigest()),
        ):
            if f"{label}:" not in rel:
                fail(f"Release missing {label}")
                continue
            section = rel.split(f"{label}:", 1)[1]
            next_hdr = re.search(r"\n[A-Z][A-Za-z0-9-]*:", section)
            block = section if not next_hdr else section[: next_hdr.start()]
            for line in block.splitlines():
                line = line.strip()
                if not line:
                    continue
                digest, size_s, name = line.split()
                p = REPO / name
                if not p.is_file():
                    fail(f"Release {label} {name} missing")
                    continue
                if hexfn(p) != digest:
                    fail(f"Release {label} {name} digest mismatch")
                elif p.stat().st_size != int(size_s):
                    fail(f"Release {label} {name} size {size_s} != {p.stat().st_size}")
                else:
                    ok(f"Release {label} {name} digest and size")

    print("\n--- summary ---")
    print(f"OK {len(oks)}  WARN {len(warns)}  FAIL {len(fails)}")
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())

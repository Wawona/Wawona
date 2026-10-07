#!/usr/bin/env python3
"""Write Debian packages and apt index. macOS `ar` is Mach-O; do not use it."""

from __future__ import annotations

import gzip
import hashlib
import io
import tarfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "out"
REPO = ROOT / "repo"
VERSION = "26.10.6"
PKGS = (
    "wawona-uikit-tools",
    "wawona-launch-tools",
    "wawona-defaults",
    "wawona-security-tools",
)


def tar_gz(files: dict[str, bytes]) -> bytes:
    tar_buf = io.BytesIO()
    with tarfile.open(fileobj=tar_buf, mode="w", format=tarfile.GNU_FORMAT) as tar:
        for name, data in sorted(files.items()):
            info = tarfile.TarInfo(name=name)
            info.size = len(data)
            info.mode = 0o644
            info.uid = 0
            info.gid = 0
            info.mtime = 0
            tar.addfile(info, io.BytesIO(data))
    raw = tar_buf.getvalue()
    gz = io.BytesIO()
    with gzip.GzipFile(fileobj=gz, mode="wb", mtime=0) as gzf:
        gzf.write(raw)
    return gz.getvalue()


def ar_member(name: str, data: bytes) -> bytes:
    # Debian ar: mode is octal ASCII 100644, not decimal 33188.
    header = (
        f"{name:<16}{0:12d}{0:6d}{0:6d}{'100644':<8}{len(data):10d}`\n"
    ).encode("ascii")
    if len(header) != 60:
        raise RuntimeError(f"ar header length {len(header)}")
    body = data + (b"\n" if len(data) % 2 == 1 else b"")
    return header + body


def parse_control(text: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    last = None
    for line in text.splitlines():
        if line.startswith(" "):
            fields[last] += "\n" + line
            continue
        k, _, v = line.partition(":")
        last = k.strip()
        fields[last] = v.strip()
    return fields


def write_deb(pkg: str) -> Path:
    control = (ROOT / "debian" / pkg / "control").read_text(encoding="utf-8")
    if not control.endswith("\n"):
        control += "\n"
    upstreams = (ROOT / "UPSTREAMS.txt").read_bytes()
    data_files: dict[str, bytes] = {
        f"usr/share/doc/{pkg}/UPSTREAMS.txt": upstreams,
    }
    if pkg == "wawona-security-tools":
        data_files[f"usr/share/doc/{pkg}/copyright"] = (
            b"ldid is AGPL-3.0. Source: https://github.com/ProcursusTeam/ldid\n"
        )
    installed = (sum(len(v) for v in data_files.values()) + 1023) // 1024
    if "Installed-Size:" not in control:
        lines = control.splitlines(keepends=True)
        out_lines = []
        inserted = False
        for line in lines:
            out_lines.append(line)
            if line.startswith("Architecture:") and not inserted:
                out_lines.append(f"Installed-Size: {installed}\n")
                inserted = True
        control = "".join(out_lines)
    data = tar_gz(data_files)
    control_tar = tar_gz({"control": control.encode("utf-8")})
    binary = b"2.0\n"
    blob = (
        b"!<arch>\n"
        + ar_member("debian-binary", binary)
        + ar_member("control.tar.gz", control_tar)
        + ar_member("data.tar.gz", data)
    )
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{pkg}_{VERSION}_iphoneos-arm64.deb"
    path.write_bytes(blob)
    return path


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def md5(p: Path) -> str:
    return hashlib.md5(p.read_bytes()).hexdigest()


def sha1(p: Path) -> str:
    return hashlib.sha1(p.read_bytes()).hexdigest()


def write_index(debs: list[Path]) -> None:
    REPO.mkdir(parents=True, exist_ok=True)
    pool = REPO / "pool" / "main"
    stanzas = []
    for deb in debs:
        raw = deb.read_bytes()
        fields = parse_control((ROOT / "debian" / deb.name.split("_")[0] / "control").read_text())
        pkg = fields["Package"]
        dest_dir = pool / pkg[0] / pkg
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest = dest_dir / deb.name
        dest.write_bytes(raw)
        rel = dest.relative_to(REPO).as_posix()
        desc = fields["Description"].split("\n", 1)[0]
        extra = fields["Description"][len(desc) :].lstrip("\n")
        stanza = (
            f"Package: {pkg}\n"
            f"Version: {fields['Version']}\n"
            f"Architecture: {fields['Architecture']}\n"
            f"Maintainer: {fields['Maintainer']}\n"
            f"Filename: {rel}\n"
            f"Size: {len(raw)}\n"
            f"MD5sum: {md5(deb)}\n"
            f"SHA1: {sha1(deb)}\n"
            f"SHA256: {sha256(deb)}\n"
            f"Description: {desc}\n"
        )
        if extra:
            stanza += extra + ("\n" if not extra.endswith("\n") else "")
        stanzas.append(stanza.rstrip() + "\n")
    packages = "\n".join(stanzas) + "\n"
    pkg_path = REPO / "Packages"
    pkg_path.write_text(packages, encoding="utf-8")
    gz_path = REPO / "Packages.gz"
    with gz_path.open("wb") as fh:
        with gzip.GzipFile(fileobj=fh, mode="wb", mtime=0) as gzf:
            gzf.write(packages.encode("utf-8"))

    def sums(algo_name: str, hexfn) -> str:
        lines = []
        for name in ("Packages", "Packages.gz"):
            p = REPO / name
            digest = hexfn(p)
            lines.append(f" {digest} {p.stat().st_size:>8d} {name}")
        return f"{algo_name}:\n" + "\n".join(lines) + "\n"

    date = time.strftime("%a, %d %b %Y %H:%M:%S UTC", time.gmtime(0))
    release = (
        "Origin: Wawona\n"
        "Label: Wawona Mode B Darwin CLI\n"
        "Suite: stable\n"
        "Codename: wawona\n"
        "Architectures: iphoneos-arm64 iphoneos-arm\n"
        "Components: main\n"
        f"Date: {date}\n"
        "Description: Mode B Darwin CLI packages. Not for the App Store app.\n"
        + sums("MD5Sum", md5)
        + sums("SHA1", sha1)
        + sums("SHA256", sha256)
    )
    (REPO / "Release").write_text(release, encoding="utf-8")


def main() -> None:
    debs = [write_deb(pkg) for pkg in PKGS]
    write_index(debs)
    for p in debs:
        print(p, p.stat().st_size, sha256(p))


if __name__ == "__main__":
    main()

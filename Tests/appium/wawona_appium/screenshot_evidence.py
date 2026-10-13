"""Catalog pass means a real machine screenshot of the client, not a log line."""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

# Tiny / blank captures are not proof. Require a non-trivial PNG.
MIN_PNG_BYTES = 12_000
MIN_WIDTH = 200
MIN_HEIGHT = 200


def gallery_root(artifacts: Path) -> Path:
    root = artifacts / "catalog-gallery"
    root.mkdir(parents=True, exist_ok=True)
    return root


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise AssertionError(f"{path} is not a PNG")
    # IHDR: width/height big-endian after length+type
    width, height = struct.unpack(">II", data[16:24])
    return int(width), int(height)


def _inflate_idat(path: Path) -> bytes:
    data = path.read_bytes()
    pos = 8
    idats: list[bytes] = []
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        ctype = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if ctype == b"IEND":
            break
        if ctype == b"IDAT":
            idats.append(chunk)
    if not idats:
        return b""
    return zlib.decompress(b"".join(idats))


def _png_is_near_solid(path: Path, *, sample_stride: int = 64) -> bool:
    """Reject all-black / all-white frames (common empty Metal/Xvfb captures)."""
    try:
        raw = _inflate_idat(path)
    except zlib.error:
        return False
    if not raw:
        return True
    samples = raw[::sample_stride]
    if not samples:
        return True
    lo = min(samples)
    hi = max(samples)
    return (hi - lo) < 8


def _center_region_is_blank(
    path: Path,
    *,
    max_mean_black: float = 18.0,
    min_mean_white: float = 235.0,
    max_stddev: float = 12.0,
) -> bool:
    """Reject shots where the Wawona content area is empty (black or white).

    Mac2 often captures the whole display (dock + IDE chrome give variance)
    while the Machines/compositor pane is empty. Sample the center 50% box.
    """
    try:
        from PIL import Image  # type: ignore
        import statistics
    except ImportError:
        width, height = png_size(path)
        try:
            raw = _inflate_idat(path)
        except zlib.error:
            return False
        if not raw or width < 8 or height < 8:
            return True
        for bpp in (4, 3, 2, 1):
            row = 1 + width * bpp
            if len(raw) >= row * height:
                break
        else:
            return False
        y0, y1 = height // 4, (3 * height) // 4
        x0, x1 = width // 4, (3 * width) // 4
        samples: list[int] = []
        for y in range(y0, y1, 4):
            base = y * row + 1
            for x in range(x0, x1, 4):
                samples.append(raw[base + x * bpp])
        if not samples:
            return True
        mean = sum(samples) / len(samples)
        var = sum((s - mean) ** 2 for s in samples) / len(samples)
        stddev = var**0.5
        return mean < max_mean_black or mean > min_mean_white or stddev < max_stddev

    with Image.open(path) as im:
        im = im.convert("L")
        w, h = im.size
        box = (w // 4, h // 4, (3 * w) // 4, (3 * h) // 4)
        crop = im.crop(box)
        pixels = list(crop.getdata())
        if not pixels:
            return True
        mean = sum(pixels) / len(pixels)
        stddev = statistics.pstdev(pixels)
        return mean < max_mean_black or mean > min_mean_white or stddev < max_stddev


def require_client_screenshot(path: Path, client_id: str) -> Path:
    if not path.is_file():
        raise AssertionError(
            f"Missing screenshot for {client_id}: {path}. "
            "Catalog OK requires a machine PNG of the running Wayland client."
        )
    size = path.stat().st_size
    if size < MIN_PNG_BYTES:
        raise AssertionError(
            f"Screenshot for {client_id} too small ({size} bytes < {MIN_PNG_BYTES}). "
            "Likely empty capture, not a real desktop/client frame."
        )
    width, height = png_size(path)
    if width < MIN_WIDTH or height < MIN_HEIGHT:
        raise AssertionError(
            f"Screenshot for {client_id} too small: {width}x{height} "
            f"(need ≥{MIN_WIDTH}x{MIN_HEIGHT})"
        )
    if _png_is_near_solid(path):
        raise AssertionError(
            f"Screenshot for {client_id} looks blank/solid ({width}x{height}). "
            "Client must be visibly drawn on the host surface."
        )
    if _center_region_is_blank(path):
        raise AssertionError(
            f"Screenshot for {client_id} has a blank content area "
            f"({width}x{height} black/white/flat). Start/Focus so the "
            "Wayland client paints inside Wawona before capturing."
        )
    return path


def publish_gallery(src: Path, artifacts: Path, client_id: str) -> Path:
    dest = gallery_root(artifacts) / f"{client_id}.png"
    dest.write_bytes(src.read_bytes())
    # Sidecar for humans / CI index
    (gallery_root(artifacts) / f"{client_id}.ok").write_text(
        f"client={client_id}\nbytes={src.stat().st_size}\n",
        encoding="utf-8",
    )
    return dest


def write_gallery_index(artifacts: Path, clients: list[str]) -> Path:
    root = gallery_root(artifacts)
    lines = [
        "<!DOCTYPE html><meta charset=utf-8>",
        "<title>Wawona Appium catalog gallery</title>",
        "<style>body{font:14px system-ui;margin:24px}img{max-width:100%;border:1px solid #444}",
        "figure{margin:0 0 32px}figcaption{font-weight:600;margin:8px 0}</style>",
        "<h1>Catalog Wayland clients (machine screenshots)</h1>",
        "<p>Each tile must show the named client running in Wawona. "
        "A green pytest without a PNG here is a bug.</p>",
    ]
    for client in clients:
        png = root / f"{client}.png"
        if png.is_file():
            lines.append(
                f"<figure><figcaption>{client}</figcaption>"
                f"<img src='{client}.png' alt='{client}'></figure>"
            )
        else:
            lines.append(f"<figure><figcaption>{client}: MISSING</figcaption></figure>")
    index = root / "index.html"
    index.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return index

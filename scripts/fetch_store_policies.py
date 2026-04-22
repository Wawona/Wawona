#!/usr/bin/env python3
"""
Offline mirror of official Apple App Store and Google Play policy / legal pages.
Uses stdlib only. From repo root:

  nix shell nixpkgs#python3 --command python3 scripts/fetch_store_policies.py

Writes into inspirational_projects/ (see inspirational_projects/POLICY_MIRRORS.txt).
"""
from __future__ import annotations

import json
import re
import time
import urllib.error
import urllib.request
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlparse, urlunparse

_REPO_ROOT = Path(__file__).resolve().parent.parent
ROOT = _REPO_ROOT / "inspirational_projects"
OUT_APPLE = ROOT / "apple-app-store"
OUT_PLAY = ROOT / "google-play-store"
MANIFEST = ROOT / "FETCH_MANIFEST.json"

UA = (
    "Mozilla/5.0 (compatible; WawonaPolicyMirror/1.0; local offline reference)"
)


class LinkExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag != "a":
            return
        href = dict(attrs).get("href")
        if not href:
            return
        h = href.strip()
        if h.startswith("#") or h.lower().startswith("javascript:"):
            return
        self.links.append(h)


def fetch_url(url: str) -> tuple[bytes, str | None]:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as resp:
        body = resp.read()
        ct = resp.headers.get("Content-Type")
    return body, ct


def _is_pdf_url(url: str) -> bool:
    p = urlparse(url)
    path = (p.path or "").lower()
    return path.endswith(".pdf") or ".pdf" in path


def extract_links(html: bytes, base_url: str) -> list[str]:
    p = LinkExtractor()
    try:
        p.feed(html.decode("utf-8", errors="replace"))
    except Exception:
        pass
    out: list[str] = []
    for href in p.links:
        absu = _norm_url(urljoin(base_url, href))
        if _is_pdf_url(absu):
            continue
        out.append(absu)
    return out


# --- Apple ---
APPLE_PREFIXES_DEV = (
    "/app-store/",
    "/distribute/",
    "/support/terms",
    "/support/downloads/terms",
    "/support/app-store-connect",
    "/programs/",
    "/in-app-purchase/",
    "/contact/app-store",
)
APPLE_PREFIXES_WWW = ("/legal/internet-services/itunes/", "/legal/internet-services/", "/legal/privacy/")

APPLE_SEEDS = [
    "https://developer.apple.com/support/terms/",
    "https://developer.apple.com/app-store/review/guidelines/",
    "https://developer.apple.com/app-store/",
    "https://developer.apple.com/distribute/",
    "https://developer.apple.com/programs/",
    "https://developer.apple.com/in-app-purchase/",
    "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/",
]

APPLE_PDF_EXTRA = [
    "https://developer.apple.com/support/downloads/terms/apple-developer-program/Apple-Developer-Program-License-Agreement-English.pdf",
    "https://developer.apple.com/support/downloads/terms/schedules/Schedule-2-and-3-English.pdf",
    "https://developer.apple.com/support/downloads/terms/exhibits/Exhibits-to-Schedule-2-and-3-English.pdf",
    "https://developer.apple.com/support/downloads/terms/apple-developer-enterprise-program/Apple-Developer-Enterprise-Program-License-Agreement-English.pdf",
    "https://developer.apple.com/support/downloads/terms/apple-developer-agreement/Apple-Developer-Agreement-20250318-English.pdf",
]

PLAY_HOSTS = {"play.google.com", "developer.android.com"}

# Policy center + Play Console “about” hub (bounded crawl; no support.google.com — unbounded cross-links).
PLAY_SEEDS = [
    "https://play.google.com/about/developer-content-policy/",
    "https://developer.android.com/distribute/play-policies",
    "https://play.google.com/console/about/",
]


def _norm_url(url: str) -> str:
    p = urlparse(url)
    return urlunparse((p.scheme, p.netloc.lower(), p.path or "/", "", "", ""))


def apple_allowed(url: str) -> bool:
    p = urlparse(url)
    if p.scheme not in ("http", "https") or not p.netloc:
        return False
    host = p.netloc.lower()
    path = p.path or "/"
    if host == "developer.apple.com":
        return any(path.startswith(pref) for pref in APPLE_PREFIXES_DEV)
    if host == "www.apple.com":
        return any(path.startswith(pref) for pref in APPLE_PREFIXES_WWW)
    return False


def play_allowed(url: str) -> bool:
    p = urlparse(url)
    if p.scheme not in ("http", "https"):
        return False
    host = p.netloc.lower()
    if host not in PLAY_HOSTS:
        return False
    path = p.path or "/"
    if host == "play.google.com":
        return (
            path.startswith("/about/")
            or path.startswith("/console/")
            or "developer-content-policy" in path
            or "policy" in path.lower()
        )
    if host == "developer.android.com":
        return "/distribute/" in path or "play-policies" in path or "/google-play/" in path
    return False


def url_to_relpath(base_out: Path, url: str, ext: str) -> Path:
    p = urlparse(url)
    parts = [x for x in p.path.split("/") if x]
    if not parts:
        parts = ["index"]
    if parts[-1].lower().endswith(".html"):
        parts[-1] = parts[-1][:-5]
    safe = "_".join(re.sub(r"[^a-zA-Z0-9._-]+", "-", seg) for seg in parts)[:180]
    if p.query:
        safe += "_" + re.sub(r"[^a-zA-Z0-9]+", "-", p.query)[:60]
    return base_out / f"{safe}{ext}"


def crawl(
    seeds: list[str],
    allowed,
    out_dir: Path,
    max_pages: int,
    subdir_html: str,
    delay_sec: float,
) -> tuple[list[dict], int]:
    out_html = out_dir / subdir_html
    out_html.mkdir(parents=True, exist_ok=True)
    visited: set[str] = set()
    queue: list[str] = list(seeds)
    manifest_pages: list[dict] = []

    while queue and len(visited) < max_pages:
        url = queue.pop(0)
        if url in visited:
            continue
        if not allowed(url):
            continue
        visited.add(url)
        if _is_pdf_url(url):
            continue
        try:
            body, ct = fetch_url(url)
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, OSError) as e:
            manifest_pages.append({"url": url, "error": str(e)})
            time.sleep(delay_sec)
            continue
        ct_l = (ct or "").lower()
        if "application/pdf" in ct_l or body[:4] == b"%PDF":
            out_pdf = out_dir / "pdf"
            out_pdf.mkdir(parents=True, exist_ok=True)
            rel = url_to_relpath(out_pdf, url, ".pdf")
            rel.parent.mkdir(parents=True, exist_ok=True)
            rel.write_bytes(body)
            manifest_pages.append(
                {
                    "url": url,
                    "saved": str(rel.relative_to(out_dir)),
                    "content_type": ct,
                    "bytes": len(body),
                    "note": "fetched_as_pdf_from_html_queue",
                }
            )
            time.sleep(delay_sec)
            continue
        rel = url_to_relpath(out_html, url, ".html")
        rel.parent.mkdir(parents=True, exist_ok=True)
        rel.write_bytes(body)
        manifest_pages.append(
            {
                "url": url,
                "saved": str(rel.relative_to(out_dir)),
                "content_type": ct,
                "bytes": len(body),
            }
        )
        for link in extract_links(body, url):
            if link not in visited and allowed(link):
                queue.append(link)
        time.sleep(delay_sec)

    return manifest_pages, len(visited)


def collect_apple_pdf_links() -> list[str]:
    """English PDFs linked from the agreements index (avoids dozens of locale PDFs)."""
    url = "https://developer.apple.com/support/terms/"
    try:
        body, _ = fetch_url(url)
    except Exception:
        return []
    text = body.decode("utf-8", errors="replace")
    found: set[str] = set()
    for m in re.finditer(r'href=["\']([^"\']+\.pdf[^"\']*)["\']', text, re.I):
        href = m.group(1).strip()
        absu = urljoin(url, href)
        if "developer.apple.com" not in absu or "/support/downloads/terms/" not in absu:
            continue
        low = absu.lower()
        if "english" not in low and not low.endswith("english.pdf"):
            continue
        found.add(_norm_url(absu))
    return sorted(found)


def fetch_one_off_html(urls: list[str], out_dir: Path, subdir: str, delay_sec: float) -> list[dict]:
    """Single-page fetches (no link following) for hubs that would crawl unbounded."""
    out_html = out_dir / subdir
    out_html.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []
    for url in urls:
        try:
            body, ct = fetch_url(url)
            rel = url_to_relpath(out_html, url, ".html")
            rel.parent.mkdir(parents=True, exist_ok=True)
            rel.write_bytes(body)
            rows.append(
                {
                    "url": url,
                    "saved": str(rel.relative_to(out_dir)),
                    "content_type": ct,
                    "bytes": len(body),
                }
            )
        except Exception as e:
            rows.append({"url": url, "error": str(e)})
        time.sleep(delay_sec)
    return rows


def download_pdfs(urls: list[str], out_dir: Path, delay_sec: float) -> list[dict]:
    out_pdf = out_dir / "pdf"
    out_pdf.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []
    for url in urls:
        try:
            body, ct = fetch_url(url)
            rel = url_to_relpath(out_pdf, url, ".pdf")
            rel.parent.mkdir(parents=True, exist_ok=True)
            rel.write_bytes(body)
            rows.append(
                {
                    "url": url,
                    "saved": str(rel.relative_to(out_dir)),
                    "bytes": len(body),
                    "content_type": ct,
                }
            )
        except Exception as e:
            rows.append({"url": url, "error": str(e)})
        time.sleep(delay_sec)
    return rows


def main() -> None:
    OUT_APPLE.mkdir(parents=True, exist_ok=True)
    OUT_PLAY.mkdir(parents=True, exist_ok=True)
    delay = 0.35

    apple_pdf_urls = sorted(set(APPLE_PDF_EXTRA + collect_apple_pdf_links()))

    m_apple_pages, apple_n = crawl(
        APPLE_SEEDS,
        apple_allowed,
        OUT_APPLE,
        max_pages=55,
        subdir_html="html",
        delay_sec=delay,
    )
    m_apple_pdf = download_pdfs(apple_pdf_urls, OUT_APPLE, delay_sec=delay)

    m_play_pages, play_n = crawl(
        PLAY_SEEDS,
        play_allowed,
        OUT_PLAY,
        max_pages=45,
        subdir_html="html",
        delay_sec=delay,
    )
    play_support = fetch_one_off_html(
        [
            "https://support.google.com/googleplay/android-developer/topic/9858052",
            "https://support.google.com/googleplay/android-developer/answer/16810878",
        ],
        OUT_PLAY,
        subdir="html/support_one_off",
        delay_sec=delay,
    )

    summary = {
        "note": "Unofficial offline copy for reference. Always use Apple and Google official sites for compliance.",
        "fetched_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "apple": {
            "html_pages": m_apple_pages,
            "visited_count": apple_n,
            "pdfs": m_apple_pdf,
        },
        "google_play": {
            "html_pages": m_play_pages,
            "visited_count": play_n,
            "support_one_off": play_support,
        },
    }
    MANIFEST.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print("Done. apple html:", apple_n, "pdfs:", len(m_apple_pdf), "google html:", play_n)
    print("Manifest:", MANIFEST)


if __name__ == "__main__":
    main()

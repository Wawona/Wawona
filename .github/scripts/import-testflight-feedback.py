#!/usr/bin/env python3
"""Import TestFlight App Store Connect feedback into GitHub issues.

Uses ASC API 4.0 beta feedback resources (screenshot + crash). Strips tester
identity and other PII. Re-encodes screenshots (no EXIF/GPS). Dedupes via an
HTML comment in the issue body.

Auth: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID,
APP_STORE_CONNECT_API_KEY (base64 .p8, same as Ship: beta).
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

ASC_BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_PREFIX = "com.aspauldingcode.Wawona"
MARKER = "testflight-id"
EMAIL_RE = re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.I)
IPV4_RE = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
IPV6_RE = re.compile(r"\b(?:[0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}\b", re.I)
USERS_PATH_RE = re.compile(r"/Users/[^/\s]+")
HOME_PATH_RE = re.compile(r"(?:/home/|C:\\Users\\)[^\s\\/]+", re.I)
UDID_RE = re.compile(r"\b[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\b", re.I)
SECRET_LINE_RE = re.compile(
    r"(?i)(password|passwd|secret|token|authorization|api[_-]?key)\s*[:=]\s*\S+"
)
SKIP_ATTRS = frozenset(
    {
        "email",
        "firstName",
        "lastName",
        "fullName",
        "udid",
        "serialNumber",
        "deviceName",
        "carrier",
        "timeZone",
        "location",
        "advertisingIdentifier",
        "vendorIdentifier",
        "ipAddress",
        "phoneNumber",
        "appleId",
        "accountName",
    }
)


def redact_text(text: str) -> str:
    if not text:
        return ""
    out = EMAIL_RE.sub("[redacted-email]", text)
    out = SECRET_LINE_RE.sub(r"\1=[redacted]", out)
    out = USERS_PATH_RE.sub("/Users/[redacted]", out)
    out = HOME_PATH_RE.sub("[redacted-home]", out)
    out = UDID_RE.sub("[redacted-udid]", out)
    out = IPV4_RE.sub("[redacted-ip]", out)
    out = IPV6_RE.sub("[redacted-ip]", out)
    return out.strip()


def keep_attr(key: str, value: Any) -> bool:
    if key in SKIP_ATTRS:
        return False
    if value is None or value == "":
        return False
    lowered = key.lower()
    if any(part in lowered for part in ("email", "name", "udid", "serial", "token")):
        if lowered in {"deviceModel", "osVersion", "appPlatform"}:
            return True
        if "model" in lowered or "version" in lowered or "platform" in lowered:
            return True
        if "email" in lowered or "udid" in lowered or "serial" in lowered:
            return False
        if lowered.endswith("name") or lowered.endswith("Name"):
            return False
    return True


def sanitize_attrs(attrs: dict[str, Any] | None) -> dict[str, str]:
    out: dict[str, str] = {}
    if not attrs:
        return out
    for key, value in attrs.items():
        if not keep_attr(key, value):
            continue
        if isinstance(value, (dict, list)):
            continue
        text = redact_text(str(value))
        if text:
            out[key] = text
    return out


def load_p8() -> str:
    raw = os.environ.get("APP_STORE_CONNECT_API_KEY") or os.environ.get("ASC_P8") or ""
    raw = raw.strip()
    if not raw:
        raise SystemExit("missing APP_STORE_CONNECT_API_KEY / ASC_P8")
    if "BEGIN PRIVATE KEY" in raw:
        return raw
    padded = raw + "=" * (-len(raw) % 4)
    decoded = base64.b64decode(padded).decode("utf-8")
    if "BEGIN PRIVATE KEY" not in decoded:
        raise SystemExit("APP_STORE_CONNECT_API_KEY is not a base64 .p8")
    return decoded


def make_token() -> str:
    import jwt  # PyJWT

    key_id = os.environ.get("APP_STORE_CONNECT_KEY_ID") or os.environ.get("ASC_KEY_ID")
    issuer = os.environ.get("APP_STORE_CONNECT_ISSUER_ID") or os.environ.get("ASC_ISSUER_ID")
    if not key_id or not issuer:
        raise SystemExit("missing APP_STORE_CONNECT_KEY_ID / ISSUER_ID")
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 19 * 60, "aud": "appstoreconnect-v1"},
        load_p8(),
        algorithm="ES256",
        headers={"alg": "ES256", "kid": key_id, "typ": "JWT"},
    )


def http_json(url: str, token: str, method: str = "GET") -> dict[str, Any]:
    req = urllib.request.Request(
        url,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as err:
        detail = err.read().decode("utf-8", errors="replace")
        raise SystemExit(f"ASC {err.code} {url}: {detail[:800]}") from err
    return json.loads(body) if body else {}


def http_bytes(url: str, token: str | None = None) -> bytes:
    headers = {"User-Agent": "Wawona-testflight-import"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def paginate(token: str, path: str, params: dict[str, str]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    items: list[dict[str, Any]] = []
    included: list[dict[str, Any]] = []
    url = f"{ASC_BASE}{path}?{urllib.parse.urlencode(params)}"
    while url:
        payload = http_json(url, token)
        items.extend(payload.get("data") or [])
        included.extend(payload.get("included") or [])
        url = (payload.get("links") or {}).get("next") or ""
    return items, included


def index_included(included: list[dict[str, Any]]) -> dict[tuple[str, str], dict[str, Any]]:
    out: dict[tuple[str, str], dict[str, Any]] = {}
    for row in included:
        out[(row.get("type") or "", row.get("id") or "")] = row
    return out


def rel_id(resource: dict[str, Any], name: str) -> str | None:
    rel = ((resource.get("relationships") or {}).get(name) or {}).get("data")
    if isinstance(rel, dict):
        return rel.get("id")
    if isinstance(rel, list) and rel:
        return rel[0].get("id")
    return None


def rel_ids(resource: dict[str, Any], name: str) -> list[str]:
    rel = ((resource.get("relationships") or {}).get(name) or {}).get("data")
    if isinstance(rel, dict) and rel.get("id"):
        return [rel["id"]]
    if isinstance(rel, list):
        return [row["id"] for row in rel if row.get("id")]
    return []


def related_url(resource: dict[str, Any], name: str) -> str | None:
    return (
        ((resource.get("relationships") or {}).get(name) or {}).get("links") or {}
    ).get("related")


def list_app_ids(token: str) -> list[str]:
    apps, _ = paginate(token, "/v1/apps", {"limit": "200"})
    ids = []
    for app in apps:
        bid = (app.get("attributes") or {}).get("bundleId") or ""
        if bid == BUNDLE_PREFIX or bid.startswith(BUNDLE_PREFIX + "."):
            ids.append(app["id"])
    return ids


def screenshot_urls(shot: dict[str, Any], included: dict[tuple[str, str], dict[str, Any]]) -> list[str]:
    urls: list[str] = []
    for sid in rel_ids(shot, "screenshots") + rel_ids(shot, "screenshot"):
        row = included.get(("betaFeedbackScreenshot", sid)) or included.get(
            ("screenshot", sid)
        )
        attrs = (row or {}).get("attributes") or {}
        for key in ("url", "imageUrl", "fileUrl"):
            if attrs.get(key):
                urls.append(str(attrs[key]))
        assets = attrs.get("imageAssets") or attrs.get("asset") or []
        if isinstance(assets, dict):
            assets = [assets]
        for asset in assets:
            if isinstance(asset, dict) and asset.get("url"):
                urls.append(str(asset["url"]))
        templates = attrs.get("templateUrl") or attrs.get("urlTemplate")
        if isinstance(templates, str) and "{w}" in templates:
            urls.append(templates.replace("{w}", "1280").replace("{h}", "1280").replace("{f}", "jpg"))
    return list(dict.fromkeys(urls))


def strip_image(data: bytes) -> bytes | None:
    try:
        from PIL import Image
    except ImportError:
        return data
    try:
        img = Image.open(io.BytesIO(data))
        img = img.convert("RGB")
        img.thumbnail((1280, 1280))
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=82, optimize=True, exif=b"")
        return buf.getvalue()
    except Exception:
        return None


def gh(*args: str, input_text: str | None = None) -> str:
    env = os.environ.copy()
    proc = subprocess.run(
        ["gh", *args],
        input=input_text,
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "gh failed")
    return proc.stdout.strip()


def existing_markers(repo: str) -> set[str]:
    found: set[str] = set()
    try:
        raw = gh(
            "issue",
            "list",
            "--repo",
            repo,
            "--label",
            "testflight",
            "--state",
            "all",
            "--limit",
            "200",
            "--json",
            "body",
        )
        for issue in json.loads(raw or "[]"):
            body = issue.get("body") or ""
            for match in re.finditer(rf"<!-- {MARKER}: ([A-Za-z0-9:_-]+) -->", body):
                found.add(match.group(1))
    except RuntimeError as err:
        print(f"warn: could not list issues: {err}", file=sys.stderr)
    return found


def ensure_labels(repo: str) -> None:
    for name, color, desc in (
        ("testflight", "0E8A16", "Imported from App Store Connect TestFlight feedback"),
        ("bug", "D73A4A", "Something did nothing, crashed, or looked wrong"),
    ):
        subprocess.run(
            [
                "gh",
                "label",
                "create",
                name,
                "--repo",
                repo,
                "--color",
                color,
                "--description",
                desc,
                "--force",
            ],
            check=False,
            capture_output=True,
        )


def upload_issue_image(repo: str, issue: str, jpeg: bytes, filename: str) -> str | None:
    owner, name = repo.split("/", 1)
    url = f"https://uploads.github.com/repos/{owner}/{name}/issues/{issue}/images?name={urllib.parse.quote(filename)}"
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""
    req = urllib.request.Request(
        url,
        data=jpeg,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "image/jpeg",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError:
        return None
    return payload.get("url") or payload.get("browser_url")


def write_artifact(kind_id: str, jpeg: bytes, crash_text: str | None) -> None:
    root = Path(os.environ.get("GITHUB_WORKSPACE") or ".") / "testflight-inbox"
    dest = root / kind_id.replace(":", "_")
    dest.mkdir(parents=True, exist_ok=True)
    if jpeg:
        (dest / "screenshot.jpg").write_bytes(jpeg)
    if crash_text:
        (dest / "crash.txt").write_text(crash_text, encoding="utf-8")


def issue_title(kind: str, attrs: dict[str, str], comment: str) -> str:
    platform = attrs.get("osVersion") or attrs.get("deviceOsVersion") or ""
    model = attrs.get("deviceModel") or attrs.get("device") or ""
    snippet = comment.splitlines()[0][:48] if comment else kind
    parts = ["[testflight]", kind]
    if model:
        parts.append(model)
    if platform:
        parts.append(platform)
    title = " ".join(parts)
    if snippet and snippet != kind:
        title = f"{title}: {snippet}"
    return title[:90]


def build_body(
    marker: str,
    kind: str,
    attrs: dict[str, str],
    comment: str,
    crash: str | None,
    image_md: str,
    run_url: str,
) -> str:
    lines = [
        f"<!-- {MARKER}: {marker} -->",
        "Imported from App Store Connect TestFlight feedback.",
        "Tester identity, emails, IPs, UDIDs, and screenshot EXIF were stripped.",
        "",
        f"**Kind:** {kind}",
        "",
        "| Field | Value |",
        "|-------|-------|",
    ]
    preferred = (
        "deviceModel",
        "osVersion",
        "appPlatform",
        "architecture",
        "connectionType",
        "screenWidth",
        "screenHeight",
    )
    seen = set()
    for key in preferred:
        if key in attrs:
            lines.append(f"| `{key}` | {attrs[key]} |")
            seen.add(key)
    for key, value in sorted(attrs.items()):
        if key in seen or key in {"comment", "email"}:
            continue
        lines.append(f"| `{key}` | {value} |")
    lines += ["", "## Tester comment", ""]
    lines.append(comment or "_No comment._")
    if image_md:
        lines += ["", "## Screenshot", "", image_md]
    if crash:
        lines += ["", "## Crash log (redacted)", "", "```text", crash[:24000], "```"]
    lines += [
        "",
        "## Notes",
        "",
        "This is not a substitute for **Settings → About → Copy Recent Logs**.",
        "If you have a workflow artifact from this import, it is on the Actions run.",
    ]
    if run_url:
        lines.append(f"Run: {run_url}")
    return "\n".join(lines) + "\n"


def create_issue(repo: str, title: str, body: str) -> str:
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, suffix=".md") as tmp:
        tmp.write(body)
        path = tmp.name
    try:
        url = gh(
            "issue",
            "create",
            "--repo",
            repo,
            "--title",
            title,
            "--label",
            "bug",
            "--label",
            "testflight",
            "--body-file",
            path,
        )
    finally:
        os.unlink(path)
    return url


def fetch_crash_log(token: str, resource: dict[str, Any]) -> str:
    url = related_url(resource, "crashLog") or related_url(resource, "crashLogs")
    if not url:
        return ""
    try:
        payload = http_json(url, token)
    except SystemExit:
        return ""
    data = payload.get("data")
    if isinstance(data, dict):
        attrs = data.get("attributes") or {}
        for key in ("log", "crashLog", "text", "file"):
            if attrs.get(key):
                return redact_text(str(attrs[key]))
        dl = attrs.get("url")
        if dl:
            try:
                return redact_text(http_bytes(str(dl), token).decode("utf-8", errors="replace"))
            except Exception:
                return ""
    return redact_text(json.dumps(payload)[:4000])


def process(
    token: str,
    repo: str,
    dry_run: bool,
    seen: set[str],
) -> int:
    created = 0
    run_url = os.environ.get("GITHUB_RUN_URL") or ""
    if not run_url and os.environ.get("GITHUB_SERVER_URL") and os.environ.get("GITHUB_REPOSITORY"):
        run_url = (
            f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}"
            f"/actions/runs/{os.environ.get('GITHUB_RUN_ID', '')}"
        )
    app_ids = list_app_ids(token)
    if not app_ids:
        print("no App Store Connect apps matching com.aspauldingcode.Wawona")
        return 0
    kinds = (
        ("SCREENSHOT", "/v1/betaFeedbackScreenshotSubmissions", "screenshot"),
        ("CRASH", "/v1/betaFeedbackCrashSubmissions", "crash"),
    )
    for kind, path, label in kinds:
        for app_id in app_ids:
            params = {
                "filter[app]": app_id,
                "limit": "50",
            }
            if kind == "SCREENSHOT":
                params["include"] = "build,screenshots"
            else:
                params["include"] = "build"
            try:
                rows, included_rows = paginate(token, path, params)
            except SystemExit as err:
                print(f"warn: {kind} list with include failed, retrying bare: {err}")
                rows, included_rows = paginate(
                    token,
                    path,
                    {"filter[app]": app_id, "limit": "50"},
                )
            included = index_included(included_rows)
            for row in rows:
                rid = row.get("id") or ""
                marker = f"{kind}:{rid}"
                if not rid or marker in seen:
                    continue
                attrs_raw = row.get("attributes") or {}
                comment = redact_text(str(attrs_raw.get("comment") or ""))
                attrs = sanitize_attrs(attrs_raw)
                build_id = rel_id(row, "build")
                if build_id:
                    build = included.get(("builds", build_id)) or included.get(("build", build_id))
                    battrs = sanitize_attrs((build or {}).get("attributes"))
                    for key in ("version", "uploadedDate", "processingState"):
                        if key in battrs:
                            attrs[f"build_{key}"] = battrs[key]
                crash = fetch_crash_log(token, row) if kind == "CRASH" else ""
                jpegs: list[bytes] = []
                for shot_url in screenshot_urls(row, included)[:3]:
                    try:
                        blob = http_bytes(shot_url, token)
                    except Exception:
                        try:
                            blob = http_bytes(shot_url)
                        except Exception:
                            continue
                    cleaned = strip_image(blob)
                    if cleaned:
                        jpegs.append(cleaned)
                if dry_run:
                    print(f"dry-run {marker} comment={comment[:80]!r} shots={len(jpegs)}")
                    seen.add(marker)
                    continue
                write_artifact(marker, jpegs[0] if jpegs else b"", crash or None)
                image_md = ""
                title = issue_title(label, attrs, comment)
                body = build_body(marker, label, attrs, comment, crash or None, image_md, run_url)
                url = create_issue(repo, title, body)
                issue_no = url.rstrip("/").split("/")[-1]
                md_parts = []
                for i, jpeg in enumerate(jpegs):
                    hosted = upload_issue_image(repo, issue_no, jpeg, f"tf-{rid}-{i}.jpg")
                    if hosted:
                        md_parts.append(f"![TestFlight screenshot]({hosted})")
                if md_parts:
                    gh(
                        "issue",
                        "comment",
                        issue_no,
                        "--repo",
                        repo,
                        "--body",
                        "## Screenshot\n\n" + "\n\n".join(md_parts),
                    )
                print(f"opened {url} for {marker}")
                seen.add(marker)
                created += 1
    return created


class RedactTests(unittest.TestCase):
    def test_email_and_path(self) -> None:
        raw = "hi alex@wawona.io from /Users/alex/code password=hunter2 1.2.3.4"
        out = redact_text(raw)
        self.assertNotIn("alex@wawona.io", out)
        self.assertNotIn("/Users/alex", out)
        self.assertNotIn("hunter2", out)
        self.assertNotIn("1.2.3.4", out)

    def test_skip_tester_fields(self) -> None:
        cleaned = sanitize_attrs(
            {
                "email": "a@b.c",
                "deviceModel": "iPhone17,1",
                "osVersion": "26.5",
                "udid": "ABCDEF",
            }
        )
        self.assertEqual(cleaned.get("deviceModel"), "iPhone17,1")
        self.assertNotIn("email", cleaned)
        self.assertNotIn("udid", cleaned)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return 0 if unittest.main(module=__name__, argv=[sys.argv[0], "-q"], exit=False).result.wasSuccessful() else 1
    repo = os.environ.get("GITHUB_REPOSITORY") or "Wawona/Wawona"
    token = make_token()
    if not args.dry_run:
        ensure_labels(repo)
    seen = existing_markers(repo)
    created = process(token, repo, args.dry_run, seen)
    print(f"imported {created} new TestFlight submissions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

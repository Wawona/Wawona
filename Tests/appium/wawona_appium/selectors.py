"""Load canonical selectors.json."""

from __future__ import annotations

import json
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[1]
_SELECTORS_PATH = _ROOT / "selectors.json"


def load_selector_ids(path: Path | None = None) -> list[str]:
    p = path or _SELECTORS_PATH
    data = json.loads(p.read_text(encoding="utf-8"))
    ids = list(data.get("ids", []))
    ids.extend(data.get("apple_only", []))
    return ids


def required_cross_platform_ids(path: Path | None = None) -> list[str]:
    p = path or _SELECTORS_PATH
    data = json.loads(p.read_text(encoding="utf-8"))
    return list(data.get("ids", []))

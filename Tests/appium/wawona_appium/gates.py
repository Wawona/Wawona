"""Load matrix.toml and decide skip / assert-absent for each platform cell."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11
    import tomli as tomllib  # type: ignore

_ROOT = Path(__file__).resolve().parents[1]
_MATRIX_PATH = _ROOT / "matrix.toml"


def load_matrix(path: Path | None = None) -> dict[str, Any]:
    p = path or _MATRIX_PATH
    with p.open("rb") as f:
        return tomllib.load(f)


def platform_name() -> str:
    return os.environ.get("WAWONA_APPIUM_PLATFORM", "ios").strip().lower()


def platform_row(matrix: dict[str, Any] | None = None) -> dict[str, Any]:
    m = matrix or load_matrix()
    name = platform_name()
    platforms = m.get("platforms", {})
    if name not in platforms:
        raise KeyError(f"Unknown platform {name!r} in matrix.toml")
    return platforms[name]


def feature_state(feature: str, matrix: dict[str, Any] | None = None) -> str:
    row = platform_row(matrix)
    if feature not in row:
        raise KeyError(f"Feature {feature!r} missing for {platform_name()}")
    return str(row[feature])


def skip_if_not_available(feature: str, *, allow: set[str] | None = None) -> str | None:
    """Return a pytest skip reason, or None when the test should run.

    Planned/blocked cells skip. Forbidden cells should use assert_absent instead
    when the UI control must be proven missing.
    """
    state = feature_state(feature)
    ok = allow or {"available"}
    if state in ok:
        return None
    if state == "forbidden":
        return f"{feature} forbidden on {platform_name()}"
    if state == "planned":
        return f"{feature} planned on {platform_name()} (not a green Start yet)"
    if state == "blocked":
        return f"{feature} blocked on {platform_name()}"
    if state == "resize_window":
        # Treated as available for resize-style tests.
        return None if "resize_window" in ok or "available" in ok else f"{feature}={state}"
    if state in {"fill_primary", "multi_scene", "native_appkit", "stub"}:
        return None if state in ok or "available" in ok else None
    return f"{feature}={state} on {platform_name()}"


def allows_new_window() -> bool:
    policy = feature_state("multi_window")
    return policy in {"multi_scene", "native_appkit"}


def vm_kind_policy() -> str:
    return feature_state("vm")


def container_kind_policy() -> str:
    return feature_state("container")


def catalog_entry(kind: str, name: str, matrix: dict[str, Any] | None = None) -> dict[str, Any]:
    m = matrix or load_matrix()
    catalog = m.get("catalog", {})
    group = catalog.get(kind, {})
    if name not in group:
        raise KeyError(f"catalog.{kind}.{name} missing")
    return group[name]

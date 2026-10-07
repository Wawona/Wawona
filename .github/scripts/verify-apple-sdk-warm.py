#!/usr/bin/env python3
"""Guard Apple SDK warm + Xcode pin wiring (apple-sdks.nix is not the cache).

Host Xcode platform SDKs are warmed by warm-ios-simulator-sdk.sh so impure
xcodebuild / build-app.nix can skip -downloadPlatform. This check fails if:

  1. The warm or select-xcode scripts fail `bash -n`,
  2. product-build apple-family / ios-sim, device-e2e, or Gate: packages
     frontend-syntax-check drop the warm step,
  3. select-xcode.sh loses the fail-closed pin, or a workflow reintroduces
     "newest Xcode" selection (`sort -V | tail -1`).
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / ".github" / "scripts"
WORKFLOWS = ROOT / ".github" / "workflows"

WARM = SCRIPTS / "warm-ios-simulator-sdk.sh"
SELECT = SCRIPTS / "select-xcode.sh"

WARM_REF = ".github/scripts/warm-ios-simulator-sdk.sh"
SELECT_REF = ".github/scripts/select-xcode.sh"
NEWEST_XCODE = re.compile(r"sort\s+-V\s*\|\s*tail\s+-1")


def bash_n(path: Path) -> str | None:
    r = subprocess.run(
        ["bash", "-n", str(path)],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        err = (r.stderr or r.stdout or "").strip() or f"exit {r.returncode}"
        return f"{path.relative_to(ROOT).as_posix()}: bash -n failed: {err}"
    return None


def job_block(text: str, job: str) -> str:
    """Return the YAML body of `jobs.<job>` until the next top-level job."""
    m = re.search(rf"(?m)^  {re.escape(job)}:\s*\n", text)
    if not m:
        return ""
    start = m.end()
    nxt = re.search(r"(?m)^  [A-Za-z0-9_-]+:\s*\n", text[start:])
    return text[start : start + nxt.start()] if nxt else text[start:]


def main() -> int:
    errors: list[str] = []

    for script in (WARM, SELECT):
        if not script.is_file():
            errors.append(f"missing {script.relative_to(ROOT).as_posix()}")
        else:
            err = bash_n(script)
            if err:
                errors.append(err)

    select_text = SELECT.read_text(encoding="utf-8") if SELECT.is_file() else ""
    if "DEFAULT_XCODE_APP=" not in select_text:
        errors.append("select-xcode.sh: missing DEFAULT_XCODE_APP pin")
    if "Pinned Xcode not found" not in select_text:
        errors.append("select-xcode.sh: missing fail-closed missing-pin error")
    if NEWEST_XCODE.search(select_text):
        errors.append("select-xcode.sh: reintroduced newest-Xcode selection")

    ios_sim_wf = (WORKFLOWS / "product-ios-sim.yml").read_text(encoding="utf-8")
    apple_family_wf = (WORKFLOWS / "product-apple-family.yml").read_text(encoding="utf-8")
    if WARM_REF not in ios_sim_wf:
        errors.append("product-ios-sim.yml: missing warm-ios-simulator-sdk.sh")
    if WARM_REF not in apple_family_wf:
        errors.append(
            "product-apple-family.yml: missing warm-ios-simulator-sdk.sh "
            "(watch/tv/vision sim builds still hit -downloadPlatform iOS without the skip flag)"
        )
    for plat in ("ipados", "tvos", "watchos", "visionos"):
        if f"warm-ios-simulator-sdk.sh {plat}" not in apple_family_wf:
            errors.append(
                f"product-apple-family.yml: warm script must be passed {plat} "
                "(ios|ipados|tvos|watchos|visionos)"
            )

    e2e_ios = (WORKFLOWS / "device-e2e-ios.yml").read_text(encoding="utf-8")
    if WARM_REF not in e2e_ios:
        errors.append("device-e2e-ios.yml: missing warm-ios-simulator-sdk.sh")

    nix = (WORKFLOWS / "nix.yml").read_text(encoding="utf-8")
    frontend = job_block(nix, "frontend-syntax-check")
    if WARM_REF not in frontend:
        errors.append(
            "nix.yml job frontend-syntax-check: missing warm-ios-simulator-sdk.sh all "
            "(iOS/tvOS/watchOS/visionOS simulator destinations)"
        )
    if "warm-ios-simulator-sdk.sh all" not in frontend and WARM_REF in frontend:
        errors.append(
            "nix.yml job frontend-syntax-check: warm script should be invoked with `all`"
        )

    for wf_name in (
        "product-ios-sim.yml",
        "product-apple-family.yml",
        "product-macos-app.yml",
        "product-ios-modeb.yml",
        "device-e2e-ios.yml",
        "device-e2e-macos.yml",
        "device-gate.yml",
        "nix.yml",
        "release.yml",
        "release-beta.yml",
        "bundled-clients-matrix.yml",
        "leak-idle-gate.yml",
    ):
        path = WORKFLOWS / wf_name
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        if NEWEST_XCODE.search(text):
            errors.append(f"{wf_name}: reintroduced newest-Xcode selection (sort -V | tail -1)")
        # Apple product / syntax lanes that select Xcode should keep using the pin script.
        if wf_name in (
            "product-ios-sim.yml",
            "product-apple-family.yml",
            "product-macos-app.yml",
            "product-ios-modeb.yml",
            "device-e2e-ios.yml",
            "nix.yml",
            "release-beta.yml",
        ):
            if SELECT_REF not in text:
                errors.append(f"{wf_name}: missing select-xcode.sh")

    if errors:
        print("Apple SDK warm / Xcode pin check FAILED:")
        for err in errors:
            print(f"- {err}")
        return 1

    print("Apple SDK warm / Xcode pin check OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

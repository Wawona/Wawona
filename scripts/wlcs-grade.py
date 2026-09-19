#!/usr/bin/env python3
"""Turn WLCS' GoogleTest XML into stable CI JSON and Markdown reports."""

from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def grade_for(rate: float) -> str:
    for minimum, grade in ((99, "A"), (95, "B"), (90, "C"), (80, "D")):
        if rate >= minimum:
            return grade
    return "F"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--xml", required=True, type=Path)
    parser.add_argument("--json", required=True, type=Path)
    parser.add_argument("--markdown", required=True, type=Path)
    parser.add_argument("--wlcs-exit-code", type=int, required=True)
    parser.add_argument("--minimum-pass-rate", type=float, default=100.0)
    parser.add_argument("--maximum-failures", type=int, default=0)
    args = parser.parse_args()

    infrastructure_error = None
    cases: list[dict[str, object]] = []
    if not args.xml.is_file():
        infrastructure_error = "WLCS did not produce GoogleTest XML"
    else:
        try:
            root = ET.parse(args.xml).getroot()
            for case in root.iter("testcase"):
                failure = case.find("failure")
                error = case.find("error")
                skipped = case.find("skipped")
                status = (
                    "failed"
                    if failure is not None or error is not None
                    else "skipped"
                    if skipped is not None or case.get("status") == "notrun"
                    else "passed"
                )
                detail_node = failure if failure is not None else error
                cases.append(
                    {
                        "suite": case.get("classname", ""),
                        "name": case.get("name", ""),
                        "status": status,
                        "duration_seconds": float(case.get("time", "0") or 0),
                        "detail": (detail_node.text or "").strip()
                        if detail_node is not None
                        else "",
                    }
                )
        except (ET.ParseError, ValueError) as exc:
            infrastructure_error = f"invalid WLCS XML: {exc}"

    passed = sum(case["status"] == "passed" for case in cases)
    failed = sum(case["status"] == "failed" for case in cases)
    skipped = sum(case["status"] == "skipped" for case in cases)
    scored = passed + failed
    pass_rate = (100.0 * passed / scored) if scored else 0.0
    conforms = (
        infrastructure_error is None
        and scored > 0
        and pass_rate >= args.minimum_pass_rate
        and failed <= args.maximum_failures
        and args.wlcs_exit_code == 0
    )
    report = {
        "schema_version": 1,
        "suite": "WLCS",
        "conforms": conforms,
        "grade": grade_for(pass_rate),
        "pass_rate": round(pass_rate, 3),
        "counts": {
            "total": len(cases),
            "scored": scored,
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
        },
        "policy": {
            "minimum_pass_rate": args.minimum_pass_rate,
            "maximum_failures": args.maximum_failures,
        },
        "wlcs_exit_code": args.wlcs_exit_code,
        "infrastructure_error": infrastructure_error,
        "tests": cases,
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

    lines = [
        "# Wawona Wayland conformance",
        "",
        f"**Verdict:** {'CONFORMANT' if conforms else 'NOT CONFORMANT'}  ",
        f"**Grade:** {report['grade']} ({pass_rate:.2f}%)",
        "",
        "| Passed | Failed | Skipped | Scored |",
        "|---:|---:|---:|---:|",
        f"| {passed} | {failed} | {skipped} | {scored} |",
    ]
    if infrastructure_error:
        lines.extend(["", f"**Infrastructure error:** {infrastructure_error}"])
    failures = [case for case in cases if case["status"] == "failed"]
    if failures:
        lines.extend(["", "## Failures"])
        lines.extend(
            f"- `{case['suite']}.{case['name']}`" for case in failures
        )
    args.markdown.write_text("\n".join(lines) + "\n")
    print(json.dumps({key: report[key] for key in ("conforms", "grade", "pass_rate", "counts")}))
    return 0 if conforms else 1


if __name__ == "__main__":
    sys.exit(main())

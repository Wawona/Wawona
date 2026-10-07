#!/usr/bin/env python3
"""One aggregator for verification findings.

Each tool wrapper appends NDJSON. This script writes the GitHub summary
and exits 1 when any finding has severity error.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


FIELDS = ("tool", "file", "line", "rule", "failure", "fix", "severity")


def load_rows(paths: list[Path]) -> list[dict]:
    rows = []
    for path in paths:
        if not path.exists():
            continue
        if path.is_dir():
            files = sorted(path.rglob("*.ndjson"))
        else:
            files = [path]
        for item in files:
            for line in item.read_text(errors="replace").splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    row = {
                        "tool": "verification-report",
                        "file": str(item),
                        "line": 1,
                        "rule": "ndjson",
                        "failure": "row was not JSON",
                        "fix": "emit one JSON object per line",
                        "severity": "error",
                    }
                row.setdefault("severity", "error")
                row.setdefault("line", 1)
                rows.append(row)
    return rows


def markdown(rows: list[dict]) -> str:
    if not rows:
        return "# Verification report\n\nNo findings.\n"
    lines = ["# Verification report", ""]
    by_file: dict[str, list[dict]] = {}
    for row in rows:
        by_file.setdefault(str(row.get("file", "?")), []).append(row)
    for name in sorted(by_file):
        lines.append(f"## `{name}`")
        lines.append("")
        for row in by_file[name]:
            lines.append(
                f"- **{row.get('tool')}** {name}:{row.get('line')} "
                f"`{row.get('rule')}` {row.get('failure')}"
            )
            lines.append(f"  - fix: {row.get('fix')}")
        lines.append("")
    return "\n".join(lines) + "\n"


def annotations(rows: list[dict]) -> None:
    for row in rows:
        if row.get("severity", "error") != "error":
            continue
        failure = str(row.get("failure", "")).replace("\n", " ")
        fix = str(row.get("fix", "")).replace("\n", " ")
        print(
            f"::error file={row.get('file')},line={row.get('line')}::"
            f"{row.get('tool')} {row.get('rule')}: {failure} fix: {fix}"
        )


def cmd_emit(args: argparse.Namespace) -> int:
    row = {
        "tool": args.tool,
        "file": args.file,
        "line": args.line,
        "rule": args.rule,
        "failure": args.failure,
        "fix": args.fix,
        "severity": args.severity,
    }
    path = Path(args.out)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as handle:
        handle.write(json.dumps(row) + "\n")
    return 0


def cmd_summarize(args: argparse.Namespace) -> int:
    rows = load_rows([Path(p) for p in args.inputs])
    text = markdown(rows)
    out = Path(args.markdown)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as handle:
            handle.write(text)
    annotations(rows)
    errors = [row for row in rows if row.get("severity", "error") == "error"]
    print(f"verification findings: {len(rows)} errors: {len(errors)}")
    return 1 if errors else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    emit = sub.add_parser("emit")
    emit.add_argument("--out", required=True)
    emit.add_argument("--tool", required=True)
    emit.add_argument("--file", required=True)
    emit.add_argument("--line", type=int, default=1)
    emit.add_argument("--rule", required=True)
    emit.add_argument("--failure", required=True)
    emit.add_argument("--fix", required=True)
    emit.add_argument("--severity", default="error")
    emit.set_defaults(func=cmd_emit)
    summary = sub.add_parser("summarize")
    summary.add_argument("inputs", nargs="+")
    summary.add_argument("--markdown", required=True)
    summary.set_defaults(func=cmd_summarize)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

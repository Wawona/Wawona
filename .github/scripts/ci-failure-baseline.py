#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
from collections import Counter
from pathlib import Path


SIGNATURES = [
    ("neon_builtin_mismatch", r"incompatible constant for this __builtin_neon function"),
    ("toolchain_path_missing", r"is not a full path to an existing compiler tool"),
    ("libffi_print_multi_os", r"unsupported option '-print-multi-os-directory'"),
    ("cmake_notfound", r"The following variables are used in this project, but they are set to NOTFOUND"),
    ("cmake_asm_not_set", r"CMAKE_ASM_COMPILER not set"),
    ("cts_unknown_gl_target", r"ninja: error: unknown target 'glcts'"),
    ("cts_unknown_vk_target", r"ninja: error: unknown target 'deqp-vk'"),
    ("gradle_daemon", r"Could not connect to the Gradle daemon"),
    ("ios_errno_missing", r"fatal error: 'errno\.h' file not found"),
    ("network_dns", r"Could not resolve host"),
    ("gradle_oom", r"OutOfMemoryError: Java heap space"),
]


def gh_json(args):
    return json.loads(subprocess.check_output(["gh", *args], text=True))


def classify(log: str) -> str:
    for key, pattern in SIGNATURES:
        if re.search(pattern, log):
            return key
    return "unknown"


def first_error(log: str) -> str:
    m = re.search(r"(error: Cannot build .*|CMake Error:.*|ninja: error:.*|fatal error:.*|clang: error:.*)", log)
    return (m.group(1) if m else "").strip()


def collect_failed_jobs(repo: str, run_id: str):
    view = gh_json(["run", "view", run_id, "--repo", repo, "--json", "status,conclusion,jobs"])
    failed = [j for j in view.get("jobs", []) if j.get("conclusion") == "failure"]
    sigs = []
    for j in failed:
        jid = str(j["databaseId"])
        try:
            log = subprocess.check_output(
                ["gh", "api", f"repos/{repo}/actions/jobs/{jid}/logs"],
                text=True,
                stderr=subprocess.STDOUT,
                timeout=30,
            )
        except Exception as ex:
            log = f"log-fetch-failed: {ex}"
        sigs.append((j["name"], classify(log), first_error(log)))
    return sigs


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate GH Actions failure baseline table")
    ap.add_argument("--repo", default="Wawona/Wawona")
    ap.add_argument("--workflow", default="Nix CI")
    ap.add_argument("--limit", type=int, default=11, help="Number of runs to inspect")
    ap.add_argument("--out", default="ci-failure-baseline.md")
    ap.add_argument("--out-json", default="ci-failure-baseline.json")
    ap.add_argument("--enforce-run-id", help="Run ID to enforce blocker signature thresholds against")
    ap.add_argument(
        "--blocker-signatures",
        nargs="*",
        default=["toolchain_path_missing", "neon_builtin_mismatch", "gradle_daemon"],
        help="Signature keys that should not exceed the threshold in --enforce-run-id",
    )
    ap.add_argument("--max-blocker-count", type=int, default=0)
    args = ap.parse_args()

    runs = gh_json(
        [
            "run",
            "list",
            "--repo",
            args.repo,
            "--workflow",
            args.workflow,
            "--limit",
            str(args.limit),
            "--json",
            "databaseId,status,conclusion,displayTitle,createdAt,url",
        ]
    )

    rows = []
    for run in runs:
        rid = str(run["databaseId"])
        sigs = collect_failed_jobs(args.repo, rid)
        failed = sigs

        counts = Counter(sig for _, sig, _ in sigs)
        top = ", ".join([f"{k}:{v}" for k, v in counts.most_common(4)]) if counts else "none"
        rows.append(
            {
                "run_id": run["databaseId"],
                "createdAt": run["createdAt"],
                "title": run["displayTitle"],
                "failed_count": len(sigs),
                "top_signatures": top,
                "failed_jobs": sigs,
            }
        )

    lines = []
    lines.append("# Nix CI Failure Baseline")
    lines.append("")
    lines.append("| Run ID | Created | Failed Jobs | Top Signatures |")
    lines.append("|---|---|---:|---|")
    for r in rows:
        lines.append(f"| {r['run_id']} | {r['createdAt']} | {r['failed_count']} | {r['top_signatures']} |")
    lines.append("")
    lines.append("## Failed Job Details")
    lines.append("")
    for r in rows:
        lines.append(f"### {r['run_id']} — {r['title']}")
        if not r["failed_jobs"]:
            lines.append("- No failed jobs.")
            lines.append("")
            continue
        for job_name, sig, err in r["failed_jobs"]:
            if err:
                lines.append(f"- `{job_name}`: `{sig}` — `{err}`")
            else:
                lines.append(f"- `{job_name}`: `{sig}`")
        lines.append("")

    Path(args.out).write_text("\n".join(lines), encoding="utf-8")
    Path(args.out_json).write_text(json.dumps(rows, indent=2), encoding="utf-8")
    print(f"Wrote {args.out}")
    print(f"Wrote {args.out_json}")

    if args.enforce_run_id:
        enforce_sigs = set(args.blocker_signatures)
        enforce_jobs = collect_failed_jobs(args.repo, str(args.enforce_run_id))
        enforce_counts = Counter(sig for _, sig, _ in enforce_jobs)
        breaches = []
        for sig in sorted(enforce_sigs):
            count = enforce_counts.get(sig, 0)
            if count > args.max_blocker_count:
                breaches.append((sig, count))

        if breaches:
            print("Blocker threshold exceeded:")
            for sig, count in breaches:
                print(f"  - {sig}: {count} (max allowed: {args.max_blocker_count})")
            return 2
        print("Blocker thresholds satisfied.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Guard flake.lock against nixpkgs lineage drift (issue #47).

Wawona builds every patched dependency (`wwn-*`) and the cross-compile toolchain
against a single nixpkgs so source hashes resolve consistently. This check fails
if:

  1. Any build-critical input (wwn-*, wwn-toolchain, rust-overlay, microvm,
     crate2nix) resolves to a nixpkgs node other than the root nixpkgs, or
  2. A nixpkgs node distinct from the root is consumed by anything other than an
     allowlisted build-tool input.

Only pure build tooling (e.g. cachix, pulled transitively by crate2nix) may
diverge, because it does not enter the cross-compiled artifact closure.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / "flake.lock"

# Nodes permitted to reference a non-root nixpkgs (pure build tooling that does
# not affect the cross-compiled artifact closure).
ALLOWED_NON_ROOT_CONSUMERS = {"cachix"}

# Root inputs whose nixpkgs MUST equal the root nixpkgs node.
BUILD_CRITICAL_PREFIXES = ("wwn-",)
BUILD_CRITICAL_EXACT = {"rust-overlay", "microvm", "crate2nix"}


def main() -> int:
    if not LOCK.is_file():
        print(f"FAIL missing {LOCK}", file=sys.stderr)
        return 1
    data = json.loads(LOCK.read_text(encoding="utf-8"))
    nodes = data["nodes"]
    root = data["root"]
    root_inputs = nodes[root]["inputs"]

    def resolve(edge):
        """Resolve a lock edge (node name or follows-path list) to a node name.

        String edges reference a node directly; list edges are follows-paths
        traversed from the root node, per the flake.lock format.
        """
        if isinstance(edge, str):
            return edge
        node = root
        for seg in edge:
            node = resolve(nodes[node]["inputs"][seg])
        return node

    root_nixpkgs = resolve(root_inputs.get("nixpkgs"))
    if not root_nixpkgs:
        print("FAIL: root has no nixpkgs input node")
        return 1

    errors: list[str] = []

    # 1. Every build-critical root input must resolve nixpkgs to the root node.
    for name, dst in root_inputs.items():
        critical = name.startswith(BUILD_CRITICAL_PREFIXES) or name in BUILD_CRITICAL_EXACT
        if not critical:
            continue
        edge = nodes.get(resolve(dst), {}).get("inputs", {}).get("nixpkgs")
        # A missing nixpkgs edge means the input doesn't take nixpkgs (fine).
        if edge is None:
            continue
        resolved = resolve(edge)
        if resolved != root_nixpkgs:
            errors.append(
                f"input '{name}' resolves nixpkgs to '{resolved}', not the root "
                f"'{root_nixpkgs}'. Add `{name}.inputs.nixpkgs.follows = \"nixpkgs\"`"
            )

    # 2. No unexpected consumer of a non-root nixpkgs node.
    nixpkgs_nodes = {k for k in nodes if k == "nixpkgs" or k.startswith("nixpkgs_")}
    for npkgs in sorted(nixpkgs_nodes - {root_nixpkgs}):
        consumers = [
            parent
            for parent, node in nodes.items()
            for edge, dst in node.get("inputs", {}).items()
            if dst == npkgs
        ]
        stray = [c for c in consumers if c not in ALLOWED_NON_ROOT_CONSUMERS]
        if stray:
            rev = nodes[npkgs].get("locked", {}).get("rev", "")[:12]
            errors.append(
                f"non-root nixpkgs '{npkgs}' (@{rev}) consumed by {sorted(stray)}; "
                "make them follow the root nixpkgs or add to the tooling allowlist"
            )

    if errors:
        print("nixpkgs lineage check FAILED (issue #47):")
        for err in errors:
            print(f"- {err}")
        return 1

    root_rev = nodes[root_nixpkgs].get("locked", {}).get("rev", "")[:12]
    print(f"nixpkgs lineage check OK. Single build lineage @{root_rev} "
          f"(tooling exceptions: {sorted(ALLOWED_NON_ROOT_CONSUMERS)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

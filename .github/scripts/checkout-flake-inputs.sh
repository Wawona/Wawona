#!/usr/bin/env bash
# Shallow-clone flake inputs needed for cross-repo verify scripts when the
# workspace checkout is Wawona-only (no sibling wwn-toolchain / wwn-weston).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

clone_at_lock() {
  local input="$1"
  local dest="$2"
  if [[ -d "$dest/.git" ]]; then
    echo "Using existing $dest"
    return 0
  fi
  local rev
  rev="$(jq -r --arg n "$input" '.nodes[$n].locked.rev // empty' flake.lock)"
  if [[ -z "$rev" ]]; then
    echo "::error::flake.lock has no locked rev for $input" >&2
    exit 1
  fi
  local owner repo
  owner="$(jq -r --arg n "$input" '.nodes[$n].locked.owner // empty' flake.lock)"
  repo="$(jq -r --arg n "$input" '.nodes[$n].locked.repo // empty' flake.lock)"
  # FlakeHub tarball locks omit owner/repo; Wawona DAG nodes are Wawona/<input>.
  if [[ -z "$owner" || -z "$repo" ]]; then
    owner=Wawona
    repo="$input"
  fi
  echo "Cloning $owner/$repo @ $rev -> $dest"
  git clone --filter=blob:none "https://github.com/${owner}/${repo}.git" "$dest"
  git -C "$dest" checkout "$rev"
}

clone_at_lock wwn-toolchain "$ROOT/wwn-toolchain"
clone_at_lock wwn-weston "$ROOT/wwn-weston"

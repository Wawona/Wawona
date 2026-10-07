#!/usr/bin/env bash
# Obsolete. Use build-modeb-demo-tipa.sh (Swift + C Mode B tipa).
set -euo pipefail
echo "build-modeb-fb-jit-tipa.sh is obsolete; running build-modeb-demo-tipa.sh" >&2
exec "$(cd "$(dirname "$0")" && pwd)/build-modeb-demo-tipa.sh" "$@"

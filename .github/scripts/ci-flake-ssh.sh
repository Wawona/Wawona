#!/usr/bin/env bash
# Load WAWONA_FLAKE_SSH_KEY so Nix can fetch private git+ssh flake inputs
# (today: wwn-iomfb-rs). Public inputs should use github: and need no key.
set -euo pipefail

if [[ -z "${WAWONA_FLAKE_SSH_KEY:-}" ]]; then
  echo "ci-flake-ssh: no WAWONA_FLAKE_SSH_KEY (private SSH flake inputs will fail)"
  exit 0
fi

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
umask 077
printf '%s\n' "$WAWONA_FLAKE_SSH_KEY" >"$HOME/.ssh/wawona_flake"
chmod 600 "$HOME/.ssh/wawona_flake"

cat >>"$HOME/.ssh/config" <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/wawona_flake
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
chmod 600 "$HOME/.ssh/config"

ssh -T git@github.com 2>&1 | head -5 || true
echo "ci-flake-ssh: SSH identity ready for private flake inputs"

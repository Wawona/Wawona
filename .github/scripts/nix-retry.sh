#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: nix-retry.sh <command...>" >&2
  exit 2
fi

attempt=1
max_attempts=3

while [ "$attempt" -le "$max_attempts" ]; do
  log_file="$(mktemp)"
  echo "==> Attempt ${attempt}/${max_attempts}: $*"

  if "$@" 2>&1 | tee "$log_file"; then
    rm -f "$log_file"
    exit 0
  fi

  if grep -Eq "Could not resolve host|HTTP error 418|timed out|Connection reset by peer|502 Bad Gateway|503 Service Unavailable|504 Gateway Timeout" "$log_file"; then
    rm -f "$log_file"
    if [ "$attempt" -lt "$max_attempts" ]; then
      sleep_seconds=$((attempt * 20))
      echo "Transient network failure detected, retrying in ${sleep_seconds}s..."
      sleep "$sleep_seconds"
      attempt=$((attempt + 1))
      continue
    fi
  fi

  echo "Command failed with non-retryable error (or retries exhausted)." >&2
  cat "$log_file" >&2
  rm -f "$log_file"
  exit 1
done

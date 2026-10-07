#!/usr/bin/env bash
# Install pinned Kani from the official Linux release tarball (GHA / CI).
# Mirrors `cargo kani setup --use-local-bundle` without compiling kani-verifier.
set -euo pipefail

VER="${1:-0.68.0}"
ARCH="${2:-x86_64-unknown-linux-gnu}"
KANI_ROOT="${HOME}/.kani"
KANI_HOME="${KANI_ROOT}/kani-${VER}"

curl --fail --location --output /tmp/kani.tgz \
  "https://github.com/model-checking/kani/releases/download/kani-${VER}/kani-${VER}-${ARCH}.tar.gz"
mkdir -p "${KANI_ROOT}"
rm -rf "${KANI_HOME}"
tar -xzf /tmp/kani.tgz -C "${KANI_ROOT}"

TOOLCHAIN="$(tr -d '[:space:]' < "${KANI_HOME}/rust-toolchain-version")"
rustup toolchain install "${TOOLCHAIN}" --profile minimal \
  --component llvm-tools --component rustc-dev \
  --component rust-src --component rustfmt
ln -sfn "${HOME}/.rustup/toolchains/${TOOLCHAIN}" "${KANI_HOME}/toolchain"

mkdir -p "${HOME}/.cargo/bin"
for name in kani cargo-kani; do
  cat > "${HOME}/.cargo/bin/${name}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
KANI_HOME=${KANI_HOME}
export PATH="\${KANI_HOME}/bin:\${PATH:-}"
export RUSTUP_TOOLCHAIN="\$(tr -d '[:space:]' < "\${KANI_HOME}/rust-toolchain-version")"
if [[ -n "\${LD_LIBRARY_PATH:-}" ]]; then
  _filtered=""
  IFS=':' read -r -a _parts <<< "\${LD_LIBRARY_PATH}"
  for _p in "\${_parts[@]}"; do
    case "\${_p}" in
      */toolchains/*/lib|*/toolchains/*/lib/) ;;
      *)
        if [[ -n "\${_filtered}" ]]; then
          _filtered="\${_filtered}:\${_p}"
        else
          _filtered="\${_p}"
        fi
        ;;
    esac
  done
  export LD_LIBRARY_PATH="\${_filtered}"
fi
exec -a ${name} "\${KANI_HOME}/bin/kani-driver" "\$@"
EOF
  chmod +x "${HOME}/.cargo/bin/${name}"
done

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${HOME}/.cargo/bin" >> "${GITHUB_PATH}"
  echo "${KANI_HOME}/bin" >> "${GITHUB_PATH}"
fi

export PATH="${HOME}/.cargo/bin:${KANI_HOME}/bin:${PATH}"
cargo kani --version

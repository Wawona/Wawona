#!/usr/bin/env bash
# Hide stub ghostty_surface_* / wwn_term_* in libwawona.a and inject the
# real Terminal crate (libghostty-vt) objects.
#
# Fallback only. Prefer macOS/Linux `nix-ghostty-vt` in rust-backend-c2n so
# engine.rs lands in libwawona.a. Forced via WAWONA_TERMINAL_OVERLAY=1 or when
# the backend still ships engine_stub.
set -euo pipefail
LIB_A="${1:?libwawona.a}"
TERM_A="${2:?libwawona_terminal.a}"

OBJCOPY="${LLVM_OBJCOPY:-}"
LLVM_AR="${LLVM_AR:-}"
LLVM_NM="${LLVM_NM:-}"

if [[ -z "$OBJCOPY" ]]; then
  shopt -s nullglob
  for cand in /nix/store/*-llvm-21*/bin/llvm-objcopy; do
    if [[ -x "$cand" ]]; then
      OBJCOPY="$cand"
      LLVM_AR="$(dirname "$cand")/llvm-ar"
      LLVM_NM="$(dirname "$cand")/llvm-nm"
      break
    fi
  done
  shopt -u nullglob
fi
if [[ -z "$OBJCOPY" || ! -x "$OBJCOPY" ]]; then
  echo "error: llvm-objcopy (LLVM 21+) required to overlay libghostty term" >&2
  exit 1
fi
LLVM_AR="${LLVM_AR:-$(dirname "$OBJCOPY")/llvm-ar}"
LLVM_NM="${LLVM_NM:-$(dirname "$OBJCOPY")/llvm-nm}"

if [[ ! -f "$LIB_A" || ! -f "$TERM_A" ]]; then
  echo "error: missing archive(s): $LIB_A / $TERM_A" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
WORK="$TMP/work"
mkdir -p "$WORK"
cd "$WORK"

"$LLVM_AR" x "$LIB_A"

# libwawona.a already links the pinned wawona-terminal crate. Drop those objects
# before merging the overlay archive or rustc std/uniffi duplicate at link time.
_stale=0
shopt -s nullglob
for o in *.o; do
  case "$o" in
    wawona_terminal.*) ;;
    *) continue ;;
  esac
  rm -f "$o"
  _stale=$((_stale + 1))
done
shopt -u nullglob
if [[ "$_stale" -gt 0 ]]; then
  echo "Removed $_stale pinned wawona-terminal object(s) from libwawona.a"
fi

map="$TMP/redef.map"
: >"$map"
syms=(
  ghostty_init ghostty_shutdown ghostty_string_free
  ghostty_surface_new ghostty_surface_free ghostty_surface_resize
  ghostty_surface_write ghostty_surface_key ghostty_surface_take_reply
  ghostty_surface_viewport ghostty_surface_origin ghostty_surface_title
  ghostty_surface_set_cell_px ghostty_surface_pointer ghostty_surface_encode_paste
  wwn_term_new wwn_term_free wwn_term_resize wwn_term_feed wwn_term_take_reply
  wwn_term_cols wwn_term_line_count wwn_term_viewport wwn_term_origin
  wwn_term_title wwn_term_set_cell_px wwn_term_pointer wwn_term_encode_paste
  wwn_term_string_free wwn_term_image_count wwn_term_image_meta wwn_term_image_rgba
  wwn_term_refresh_scrollback_cap wwn_term_cursor wwn_term_lines_json
  wwn_term_images_json wwn_term_bytes_lines_json wwn_term_bytes_images_json
  wwn_term_line_cells
)
for s in "${syms[@]}"; do
  printf '_%s _stale_%s\n' "$s" "$s" >>"$map"
done

hid=0
for o in *.o; do
  # Homemade ghostty_* / wwn_term_* live in wawona (screen shim + uniffi_api).
  if "$LLVM_NM" --defined-only "$o" 2>/dev/null | grep -Eq ' T _(ghostty_|wwn_term_)'; then
    "$OBJCOPY" --redefine-syms="$map" "$o" "$o.re"
    mv "$o.re" "$o"
    echo "Hid homemade term ABI in $o"
    hid=1
  fi
done
if [[ "$hid" -eq 0 ]]; then
  echo "warning: no homemade ghostty/term ABI exports in $LIB_A (already overlaid?)" >&2
fi

# Merge Terminal/libghostty objects into libwawona.a. Skip a second Rust std
# (use libwawona's). Keep Terminal's uniffi_core: crate hashes differ from the
# domain uniffi already in libwawona, and wawona_terminal UniFFI needs them.
# Zig VT objects stay.
skip_rust_rt() {
  case "$1" in
    std-*|core-*|alloc-*|compiler_builtins-*|panic_abort-*|panic_unwind-*) return 0 ;;
    rustc_std_workspace_*|rustc_demangle-*|std_detect-*|unwind-*) return 0 ;;
    hashbrown-*|gimli-*|memchr-*|miniz_oxide-*) return 0 ;;
    adler2-*|object-*|cfg_if-*|libc-*) return 0 ;;
    *) return 1 ;;
  esac
}

TERM_DIR="$TMP/term"
mkdir -p "$TERM_DIR"
(
  cd "$TERM_DIR"
  "$LLVM_AR" x "$TERM_A"
  for o in *.o; do
    [[ -f "$o" ]] || continue
    if skip_rust_rt "$o"; then
      rm -f "$o"
      continue
    fi
    cp -f "$o" "$WORK/"
  done
)

rm -f "$LIB_A"
"$LLVM_AR" crs "$LIB_A" ./*.o
echo "Overlayed libghostty Terminal into $LIB_A"

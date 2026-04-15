{ pkgs, stdenv, lib, wawonaAndroidProject ? null, wawonaSrc ? null, wawonaVersion ? "v1.0", iconAssets ? "AUTO" }:

let
  # Resolve icon assets:
  # 1. If explicitly null, use null (breaks recursion)
  # 2. If explicitly provided (not "AUTO"), use that derivation
  # 3. If "AUTO", try to resolve locally from wawonaSrc
  androidIconAssets =
    if iconAssets == null then null
    else if iconAssets != "AUTO" then iconAssets
    else if wawonaSrc != null && builtins.pathExists ./android-icon-assets.nix then
      import ./android-icon-assets.nix { inherit pkgs lib wawonaSrc; }
    else
      null;

  # Canonical Android Studio project is ./android.
  # gradlegen now updates that location by default to avoid duplicate Gradle roots.
  # Optional isolated output is still available via --out <dir>.
  projectPath = if wawonaAndroidProject != null then toString wawonaAndroidProject else "";
  outDir = "android";
  generateScript = pkgs.writeShellScriptBin "gradlegen" ''
    set -euo pipefail
    OUT="${outDir}"
    RUN_SKIP_EXPORT=0
    CLEAN_SKIP=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --run-skip-export) RUN_SKIP_EXPORT=1; shift ;;
        --clean-skip) CLEAN_SKIP=1; shift ;;
        --out)
          if [ "$#" -lt 2 ]; then
            echo "ERROR: --out requires a directory argument." >&2
            exit 1
          fi
          OUT="$2"
          shift 2
          ;;
        *)
          echo "ERROR: Unknown argument: $1" >&2
          echo "Usage: gradlegen [--run-skip-export] [--clean-skip] [--out <dir>]" >&2
          exit 1
          ;;
      esac
    done

    if [ ! -f "./Package.swift" ]; then
      echo "ERROR: Run gradlegen from repo root (Package.swift missing)." >&2
      exit 1
    fi

    # Default mode: maintain a single canonical Android project at ./android.
    if [ "$OUT" = "android" ]; then
      if [ ! -d "./android/app" ]; then
        echo "ERROR: ./android project is missing (expected ./android/app)." >&2
        exit 1
      fi

      if [ "$CLEAN_SKIP" -eq 1 ]; then
        rm -rf "./android/Skip"
      fi
      mkdir -p "./android/Skip"

      # If a prebuilt Nix project is available, hydrate Skip artifacts from it.
      if [ "$RUN_SKIP_EXPORT" -eq 0 ] && [ -n "${projectPath}" ] && [ -d "${projectPath}/Skip" ]; then
        rm -rf "./android/Skip"
        mkdir -p "./android/Skip"
        cp -R ${projectPath}/Skip/. "./android/Skip/" 2>/dev/null || true
      fi

      if [ "$RUN_SKIP_EXPORT" -eq 1 ]; then
        if ! command -v skip >/dev/null 2>&1; then
          echo "ERROR: skip CLI not found; install Skip or run without --run-skip-export." >&2
          exit 1
        fi
        echo "Running skip export into ./android/Skip ..."
        rm -rf "./android/Skip"
        mkdir -p "./android/Skip"
        skip export --project . -d "./android/Skip" --verbose
      fi

      echo ""
      echo "Canonical Android Studio project is ./android/"
      if [ "$RUN_SKIP_EXPORT" -eq 0 ]; then
        echo "Tip: run 'nix run .#gradlegen -- --run-skip-export' to refresh ./android/Skip."
      fi
      exit 0
    fi

    # Optional isolated copy mode for experimentation.
    if [ -d "$OUT" ]; then
      chmod -R u+w "$OUT" 2>/dev/null || true
      rm -rf "$OUT"
    fi
    mkdir -p "$OUT"

    if [ -n "${projectPath}" ] && [ -d "${projectPath}" ]; then
      echo "Copying full Android project (backend + native libs) to $OUT/..."
      cp -r ${projectPath}/* "$OUT/"
      chmod -R u+w "$OUT" 2>/dev/null || true
    else
      if [ -n "${toString wawonaSrc}" ] && [ -d "${toString wawonaSrc}/android" ]; then
        echo "Copying repository Android project to $OUT/..."
        cp -r ${toString wawonaSrc}/android/* "$OUT/"
        chmod -R u+w "$OUT" 2>/dev/null || true
        ${if androidIconAssets != null then ''
          if [ -d "${androidIconAssets}/res" ]; then
            mkdir -p "$OUT/app/src/main/res"
            cp -r ${androidIconAssets}/res/* "$OUT/app/src/main/res/"
            chmod -R u+w "$OUT/app/src/main/res" 2>/dev/null || true
            echo "Merged Wawona launcher icon assets"
          fi
        '' else ""}
      else
        echo "ERROR: Could not locate android project sources under wawonaSrc."
        exit 1
      fi
    fi

    # Trim generated project bloat for Android Studio import.
    find "$OUT" -type d \( \
      -name ".gradle" -o -name ".kotlin" -o -name ".idea" -o -name ".cxx" -o -name "build" \
    \) -prune -exec rm -rf {} + 2>/dev/null || true
    rm -f "$OUT/local.properties" 2>/dev/null || true

    if [ -d "./android/Skip" ]; then
      mkdir -p "$OUT/Skip"
      cp -R ./android/Skip/. "$OUT/Skip/" 2>/dev/null || true
    fi

    if [ "$RUN_SKIP_EXPORT" -eq 1 ]; then
      if ! command -v skip >/dev/null 2>&1; then
        echo "ERROR: skip CLI not found; install Skip or run without --run-skip-export." >&2
        exit 1
      fi
      echo "Running skip export into $OUT/Skip ..."
      mkdir -p "$OUT/Skip"
      skip export --project . -d "$OUT/Skip" --verbose
    fi

    if [ ! -d "$OUT/Skip" ]; then
      echo "NOTE: Skip artifacts were not found in generated project."
      echo "      Run: nix run .#gradlegen -- --run-skip-export"
    fi

    echo ""
    echo "Project ready at $OUT/"
    echo "Open $OUT/ in Android Studio and select device/emulator."
  '';

in {
  inherit generateScript;
}

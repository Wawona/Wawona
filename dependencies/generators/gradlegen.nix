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

  # Script to generate Android Studio project in Wawona-gradle-project/ (gitignored).
  # When wawonaAndroidProject is available (pre-built Android project with jniLibs),
  # copies the full project. Otherwise falls back to gradle files + sources only.
  projectPath = if wawonaAndroidProject != null then toString wawonaAndroidProject else "";
  outDir = "Wawona-gradle-project";
  generateScript = pkgs.writeShellScriptBin "gradlegen" ''
    set -e
    OUT="${outDir}"

    # Clean previous run (handles read-only Nix store copies)
    if [ -d "$OUT" ]; then
      chmod -R u+w "$OUT" 2>/dev/null || true
      rm -rf "$OUT"
    fi
    mkdir -p "$OUT"

    if [ -n "${projectPath}" ] && [ -d "${projectPath}" ]; then
      echo "Copying full Android project (backend + native libs) to $OUT/..."
      cp -r ${projectPath}/* "$OUT/"
      chmod -R u+w "$OUT" 2>/dev/null || true
      echo ""
      echo "Project ready at $OUT/"
      echo "Open $OUT/ in Android Studio and select device/emulator."
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
        echo "Generated Android Studio project in $OUT/ from repository sources."
      else
        echo "ERROR: Could not locate android project sources under wawonaSrc."
        exit 1
      fi
    fi
  '';

in {
  inherit generateScript;
}

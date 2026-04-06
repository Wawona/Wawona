{
  lib,
  stdenv,
  writeShellScript,
}:
{
  versions ? [ ],
  xcodeBaseDir ? null,
}:

assert stdenv.hostPlatform.isDarwin;
stdenv.mkDerivation {
  name = "xcode-wrapper-impure";
  __noChroot = true;
  buildCommand = ''
    set -euo pipefail

    resolve_xcode_base_dir() {
      local selected=""

      if [ -n "${if xcodeBaseDir == null then "" else xcodeBaseDir}" ]; then
        selected="${if xcodeBaseDir == null then "" else xcodeBaseDir}"
      fi

      if [ -z "$selected" ] && [ -x /usr/bin/xcode-select ]; then
        local dev_dir
        dev_dir=$(/usr/bin/xcode-select -p 2>/dev/null || true)
        case "$dev_dir" in
          *.app/Contents/Developer)
            selected="''${dev_dir%/Contents/Developer}"
            ;;
        esac
      fi

      if [ -z "$selected" ]; then
        for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app /Applications/Xcode_*.app /Applications/Xcode*.app; do
          if [ -d "$candidate" ]; then
            selected="$candidate"
            break
          fi
        done
      fi

      if [ -z "$selected" ] || [ ! -d "$selected/Contents/Developer" ]; then
        echo "Could not locate a usable Xcode installation." >&2
        echo "Select one with xcode-select or pass xcodeBaseDir explicitly." >&2
        exit 1
      fi

      printf '%s\n' "$selected"
    }

    resolvedXcodeBaseDir="$(resolve_xcode_base_dir)"
    xcodebuildPath="$resolvedXcodeBaseDir/Contents/Developer/usr/bin/xcodebuild"
    simulatorPath="$resolvedXcodeBaseDir/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator"
    sdkDir="$resolvedXcodeBaseDir/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs"

    mkdir -p $out/bin
    cd $out/bin
    ${
      if versions == [ ] then
        ''
          ln -s "$xcodebuildPath" xcodebuild
        ''
      else
        ''
          cat > xcodebuild <<EOF
          #!${stdenv.shell}
          set -euo pipefail
          xcodebuildPath="$resolvedXcodeBaseDir/Contents/Developer/usr/bin/xcodebuild"
          currentVer="\$("\$xcodebuildPath" -version | awk 'NR==1{print \$2}')"
          wrapperVers=(${lib.concatStringsSep " " versions})

          for ver in "''${wrapperVers[@]}"; do
            if [[ "\$currentVer" == "\$ver" ]]; then
              exec "\$xcodebuildPath" "\$@"
            fi
          done

          echo "The installed Xcode version (\$currentVer) does not match any of the allowed versions: ${lib.concatStringsSep ", " versions}" >&2
          echo "Please update your local Xcode installation to match one of the allowed versions." >&2
          exit 1
          EOF
          chmod +x xcodebuild
        ''
    }
    ln -s /usr/bin/xcode-select
    ln -s /usr/bin/security
    ln -s /usr/bin/codesign
    ln -s /usr/bin/xcrun
    ln -s /usr/bin/plutil
    ln -s /usr/bin/clang
    ln -s /usr/bin/lipo
    ln -s /usr/bin/file
    ln -s /usr/bin/rev
    if [ -x "$simulatorPath" ]; then
      ln -s "$simulatorPath" Simulator
    fi
    if [ -x "$resolvedXcodeBaseDir/Contents/Developer/usr/bin/simctl" ]; then
      ln -s "$resolvedXcodeBaseDir/Contents/Developer/usr/bin/simctl" simctl
    fi
    if [ -x "$resolvedXcodeBaseDir/Contents/Developer/usr/bin/actool" ]; then
      ln -s "$resolvedXcodeBaseDir/Contents/Developer/usr/bin/actool" actool
    fi

    cd ..
    if [ -d "$sdkDir" ]; then
      ln -s "$sdkDir" SDKs
    fi
  '';
}

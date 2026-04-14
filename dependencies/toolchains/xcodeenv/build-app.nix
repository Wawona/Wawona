{
  stdenv,
  lib,
  composeXcodeWrapper,
}:
{
  name,
  src,
  sdkVersion ? "13.1",
  target ? null,
  configuration ? null,
  scheme ? null,
  sdk ? null,
  xcodeFlags ? "",
  release ? false,
  certificateFile ? null,
  certificatePassword ? null,
  provisioningProfile ? null,
  codeSignIdentity ? null,
  signMethod ? null,
  automaticProvisioning ? false,
  developmentTeam ? null,
  generateIPA ? false,
  generateXCArchive ? false,
  enableWirelessDistribution ? false,
  installURL ? null,
  bundleId ? null,
  appVersion ? null,
  ...
}@args:

assert
  release
  ->
    (
      automaticProvisioning
      || (
        certificateFile != null
        && certificatePassword != null
        && provisioningProfile != null
        && signMethod != null
        && codeSignIdentity != null
      )
    );
assert enableWirelessDistribution -> installURL != null && bundleId != null && appVersion != null;
assert automaticProvisioning -> developmentTeam != null;

let
  _target = if target == null then name else target;
  targetFlag = lib.optionalString (scheme == null) "-target ${_target}";

  _configuration =
    if configuration == null then if release then "Release" else "Debug" else configuration;

  _sdk =
    if sdk == null then
      if release then "iphoneos" + sdkVersion else "iphonesimulator" + sdkVersion
    else
      sdk;

  deleteKeychain = ''
    security default-keychain -s login.keychain
    security delete-keychain $keychainName
  '';

  xcodewrapperFormalArgs = composeXcodeWrapper.__functionArgs or (builtins.functionArgs composeXcodeWrapper);
  xcodewrapperArgs = builtins.intersectAttrs xcodewrapperFormalArgs args;
  xcodewrapper = composeXcodeWrapper xcodewrapperArgs;

  extraArgs = removeAttrs args (
    [
      "name"
      "scheme"
      "xcodeFlags"
      "release"
      "certificateFile"
      "certificatePassword"
      "provisioningProfile"
      "codeSignIdentity"
      "signMethod"
      "automaticProvisioning"
      "developmentTeam"
      "generateIPA"
      "generateXCArchive"
      "enableWirelessDistribution"
      "installURL"
      "bundleId"
      "version"
    ]
    ++ builtins.attrNames xcodewrapperFormalArgs
  );
in
stdenv.mkDerivation (
  {
    name = lib.replaceStrings [ " " ] [ "" ] name;
    buildPhase = ''
      export PATH=${xcodewrapper}/bin:$PATH
      export DEVELOPER_DIR="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
      if [ -z "$DEVELOPER_DIR" ] || [ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]; then
        if [ -n "''${XCODE_APP:-}" ] && [ -x "$XCODE_APP/Contents/Developer/usr/bin/xcodebuild" ]; then
          export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
        else
          XCODE_APP_CANDIDATE="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1 || true)"
          if [ -n "$XCODE_APP_CANDIDATE" ] && [ -x "$XCODE_APP_CANDIDATE/Contents/Developer/usr/bin/xcodebuild" ]; then
            export DEVELOPER_DIR="$XCODE_APP_CANDIDATE/Contents/Developer"
          else
            echo "ERROR: Could not resolve DEVELOPER_DIR. Set XCODE_APP or run xcode-select -s <Xcode.app>." >&2
            exit 1
          fi
        fi
      fi
      export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$DEVELOPER_DIR/usr/bin:$PATH"
      export HOME="$TMPDIR/home"
      export CFFIXED_USER_HOME="$HOME"
      mkdir -p "$HOME/Library/Developer/Xcode/DerivedData"
      mkdir -p "$HOME/Library/Developer/Xcode/Archives"
      mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"

      ${lib.optionalString release ''
        ${lib.optionalString (!automaticProvisioning) ''
          keychainName="$(basename $out)"
          security create-keychain -p "" $keychainName
          security default-keychain -s $keychainName
          security unlock-keychain -p "" $keychainName
          security import ${certificateFile} -k $keychainName -P "${certificatePassword}" -A
          security set-key-partition-list -S apple-tool:,apple: -s -k "" $keychainName
          PROVISIONING_PROFILE=$(grep UUID -A1 -a ${provisioningProfile} | grep -o "[-A-Za-z0-9]\{36\}")
          if [ ! -f "$HOME/Library/MobileDevice/Provisioning Profiles/$PROVISIONING_PROFILE.mobileprovision" ]
          then
              mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
              cp ${provisioningProfile} "$HOME/Library/MobileDevice/Provisioning Profiles/$PROVISIONING_PROFILE.mobileprovision"
          fi
          security find-identity -p codesigning $keychainName
        ''}
      ''}

      export CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
      export CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      export LD="$CC"

      ${lib.optionalString (lib.hasInfix "simulator" _sdk) ''
        if [ "''${WAWONA_SKIP_IOS_SIMULATOR_PLATFORM_DOWNLOAD:-}" = "1" ]; then
          echo "Skipping xcodebuild -downloadPlatform iOS (WAWONA_SKIP_IOS_SIMULATOR_PLATFORM_DOWNLOAD=1)"
        else
          # actool CompileAssetCatalogVariant thinned needs a Simulator *runtime* whose build
          # matches the iphonesimulator SDK. Partial Xcode installs often error with:
          # "No simulator runtime version from [...] available to use with iphonesimulator SDK version ..."
          echo "Ensuring iOS Simulator platform is installed for SDK ${_sdk}..."
          xcodebuild -downloadPlatform iOS || {
            echo "ERROR: xcodebuild -downloadPlatform iOS failed (network or Xcode issue)." >&2
            echo "Fix: Xcode → Settings → Components → install iOS Simulator for this Xcode, then retry." >&2
            echo "Or export WAWONA_SKIP_IOS_SIMULATOR_PLATFORM_DOWNLOAD=1 if runtimes already match." >&2
            exit 1
          }
        fi
      ''}

      xcodebuild ${targetFlag} -configuration ${_configuration} ${
        lib.optionalString (scheme != null) "-scheme ${scheme}"
      } -sdk ${_sdk} TARGETED_DEVICE_FAMILY="1, 2" ONLY_ACTIVE_ARCH=NO CONFIGURATION_TEMP_DIR=$TMPDIR CONFIGURATION_BUILD_DIR=$out ${
        lib.optionalString (generateIPA || generateXCArchive) "-archivePath \"${name}.xcarchive\" archive"
      } ${lib.optionalString (release && !automaticProvisioning) ''PROVISIONING_PROFILE=$PROVISIONING_PROFILE OTHER_CODE_SIGN_FLAGS="--keychain $HOME/Library/Keychains/$keychainName-db"''} ${lib.optionalString (release && automaticProvisioning) ''-allowProvisioningUpdates DEVELOPMENT_TEAM=${developmentTeam} CODE_SIGN_STYLE=Automatic''} ${xcodeFlags}

      ${lib.optionalString release ''
        ${lib.optionalString generateIPA ''
          cat > "${name}.plist" <<EOF
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
              ${lib.optionalString (!automaticProvisioning) ''
              <key>signingCertificate</key>
              <string>${codeSignIdentity}</string>
              <key>provisioningProfiles</key>
              <dict>
                  <key>${bundleId}</key>
                  <string>$PROVISIONING_PROFILE</string>
              </dict>
              <key>signingStyle</key>
              <string>manual</string>
              ''}
              ${lib.optionalString automaticProvisioning ''
              <key>signingStyle</key>
              <string>automatic</string>
              <key>teamID</key>
              <string>${developmentTeam}</string>
              ''}
              <key>method</key>
              <string>${if automaticProvisioning then "development" else signMethod}</string>
              ${lib.optionalString (signMethod == "enterprise" || signMethod == "ad-hoc") ''
                <key>compileBitcode</key>
                <false/>
              ''}
          </dict>
          </plist>
          EOF

          xcodebuild -exportArchive -archivePath "${name}.xcarchive" -exportOptionsPlist "${name}.plist" -exportPath $out ${lib.optionalString automaticProvisioning "-allowProvisioningUpdates"}

          mkdir -p $out/nix-support
          echo "file binary-dist \"$(echo $out/*.ipa)\"" > $out/nix-support/hydra-build-products

          ${lib.optionalString enableWirelessDistribution ''
            appname="$(basename "$(echo $out/*.ipa)" .ipa)"
            sed -e "s|@INSTALL_URL@|${installURL}?bundleId=${bundleId}\&amp;version=${appVersion}\&amp;title=$appname|" ${./install.html.template} > $out/''${appname}.html
            echo "doc install \"$out/''${appname}.html\"" >> $out/nix-support/hydra-build-products
          ''}
        ''}
        ${lib.optionalString generateXCArchive ''
          mkdir -p $out
          mv "${name}.xcarchive" $out
        ''}

        ${lib.optionalString (!automaticProvisioning) ''
          ${deleteKeychain}
        ''}
      ''}
    '';

    failureHook = lib.optionalString (release && !automaticProvisioning) deleteKeychain;

    installPhase = "true";
  }
  // extraArgs
)

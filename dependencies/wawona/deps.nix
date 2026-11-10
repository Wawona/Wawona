# Per-SDK inputs of the committed Wawona.xcodeproj. `nix run .#deps -- <sdk>`
# links .deps/<sdk> to one of these slices, named by Xcode's PLATFORM_NAME
# (plus iphoneos-modeb for Wawona-iOS-ModeB):
#   Wawona.xcconfig          WWN_HEADERS_<target> and WWN_LDFLAGS_<target>,
#                            included by src/resources/xcode/wwn-version.xcconfig
#   backend, zsh, fastfetch  archives scripts/xcode-prebuild.sh stages
#   bundle/                  what scripts/xcode-embed.sh copies into the app
#   uniffi                   generated Swift for WawonaModel
{
  lib,
  pkgs,
  wawonaVersion,
  wawonaSrc,
  ilandGlLdflagsNix,
  # { <sdk> = { deps, backend }; } for every Apple-mobile SDK, plus macosx.
  slices,
  macosExtras, # { fastfetch, zsh, igetty, moltenvk }
  modeB, # { iomfb, igetty, backend }, linked only by Wawona-iOS-ModeB
}: let
  p = toString;
  isSim = sdk: lib.hasSuffix "simulator" sdk;
  isWatch = lib.hasPrefix "watch";
  family = sdk:
    if lib.hasPrefix "iphone" sdk then "ios"
    else if lib.hasPrefix "appletv" sdk then "tvos"
    else if lib.hasPrefix "xr" sdk then "visionos"
    else if isWatch sdk then "watchos"
    else "macos";
  targets = {
    # Wawona-iOS-ModeB device flags come only from the iphoneos-modeb slice.
    iphoneos = [ "Wawona_iOS" "Wawona_iPadOS" ];
    iphonesimulator = [ "Wawona_iOS" "Wawona_iPadOS" "Wawona_iOS_ModeB" ];
    tvos = [ "Wawona_tvOS" ];
    visionos = [ "Wawona_visionOS" ];
    watchos = [ "Wawona_watchOS" ];
    macos = [ "Wawona_macOS" ];
  };
  undef = map (s: "-Wl,-u,_${s}");
  quoted = n: v: "WAWONA_${n}_VERSION=\\\"${v}\\\"";
  versionDefs = [ "WAWONA_VERSION=\\\"${wawonaVersion}\\\"" ] ++ lib.mapAttrsToList quoted {
    WAYLAND = "1.23.0"; XKBCOMMON = "1.7.0"; LZ4 = "1.10.0"; ZSTD = "1.5.7";
    LIBFFI = "3.5.2"; SSHPASS = "1.10"; WAYPIPE = "0.11.0";
  };
  cxx = [ "-lc++" "-lc++abi" "-ldl" ];
  wasm = d: [ "-L${p d.wawona-wasm}/lib" ]
    ++ undef [ "wawona_wasm_run" "wawona_wasm_can_run" "wawona_wasm_request_interrupt" "wawona_wasm_is_running" "wpm_main" ]
    ++ [ "-lwawona_wasm" ];
  relay = d: undef [ "relay_resolve_backend" "relay_start" "relay_start_shm_importer" "relay_start_host_waypipe" ]
    ++ [ "${p d.wawona-relay}/lib/libwawona_relay.a" "-L${p (d.zstd or pkgs.zstd.out)}/lib" "-lzstd" ];
  pixmanHeaders = d: [ "${p d.pixman}/include" "${p d.pixman}/include/pixman-1" ];

  # Apple ld64 resolves archives in any order, so one list serves every mobile SDK.
  mobileLdflags = sdk: d: let watch = isWatch sdk; in
    lib.optionals (!isSim sdk && !watch) [ "-force_load" "$(DERIVED_FILE_DIR)/libwawona-getprogname.a" ]
    ++ map (n: "-L${p d.${n}}/lib") [ "libwayland" "xkbcommon" "libffi" "pixman" "zstd" "lz4" "libssh2" "mbedtls" "openssl" "epoll-shim" ]
    ++ [ "-lxkbcommon" "-lwayland-client" ] ++ lib.optional watch "-lwayland-server"
    ++ [ "-lffi" "-lpixman-1" "-lzstd" "-llz4" "-lz" "-lssh2" "-lmbedcrypto" "-lmbedx509" "-lmbedtls" "-lssl" "-lcrypto" "-lepoll-shim" ]
    ++ lib.optionals (d ? iland) ([ "-L${p d.iland}/lib" ]
      ++ undef [ "iland_drm_set_present_callback" "iland_drm_set_preferred_mode" "iland_drm_complete_page_flip" "iland_drm_prepare_virtual_fd" ]
      ++ [ "-liland_userland" ])
    ++ [ "-force_load" "$(DERIVED_FILE_DIR)/libfastfetch.a" "@FASTFETCH_FRAMEWORKS@" ]
    ++ wasm d ++ lib.optionals (!watch) (relay d)
    ++ [ "-L${p d.waypipe}/lib" "-lwaypipe" "-force_load" "${p d.ssh-cli}/lib/libwwn-ssh-cli.a" ]
    ++ undef [ "ssh_main" "ssh_keygen_main" "scp_main" ]
    ++ [ "-force_load" "${p d.wawona-pty}/lib/libwwn-pty.a" "-lresolv" "-force_load" "$(DERIVED_FILE_DIR)/libwawona-zsh.a" ]
    ++ undef [ "wawona_coreutils_main" "fastfetch_main" "waypipe_main" "wawona_dispatch_can_handle" "wawona_dispatch_inprocess" "wawona_dispatch_spawn_async" ]
    ++ [ "-liconv" "-L$(DERIVED_FILE_DIR)" "-lwawona" ] ++ cxx
    ++ lib.optionals (family sdk == "ios" || family sdk == "visionos") [ "-framework" "IOKit" ];
  mobileHeaders = sdk: d:
    lib.optional (isWatch sdk) "${p d.libffi}/include"
    ++ [ "${p d.libwayland}/include" "${p d.libwayland}/include/wayland" ]
    ++ lib.optional (!isWatch sdk) "${p d.xkbcommon}/include"
    ++ [ "${p d.libssh2}/include" ]
    ++ lib.optionals (isWatch sdk) [ "$(SRCROOT)/src/platform/watchos" "$(SRCROOT)/src/util" ]
    ++ pixmanHeaders d;

  macosLdflags = d: [
    "-L${p d.libwayland}/lib" "-L${p d.xkbcommon}/lib" "-L${p d.pixman}/lib" "-L${p d.epoll-shim}/lib" "-L${pkgs.openssl.out}/lib"
    "-lxkbcommon" "-lwayland-client" "-lpixman-1" "-lepoll-shim" "-lssl" "-lcrypto" "-lz" "-L$(DERIVED_FILE_DIR)" "-lwawona"
  ] ++ import ilandGlLdflagsNix { inherit lib; deps = d; forceLoad = true; }
    ++ wasm d ++ relay d ++ cxx ++ [ "-framework" "IOKit" ];
  macosHeaders = d: [
    "${p d.libwayland}/include" "${p d.libwayland}/include/wayland" "${p d.xkbcommon}/include"
    "$(SRCROOT)/src" "$(SRCROOT)/src/platform/macos/ui" "$(SRCROOT)/src/platform/macos/ui/Machines"
    "$(SRCROOT)/src/platform/macos/ui/Settings" "$(SRCROOT)/src/platform/macos"
  ] ++ pixmanHeaders d ++ [ "${p d.iland}/include" "${p d.iland}/include/EGL" "${p d.iland}/include/GLES2" ]
    ++ map (n: "${p d.${n}}/include") [ "angle" "kmscube" "vkcube" "opengl-cube" ];

  line = k: v: "${k} = $(inherited) ${lib.concatStringsSep " " v}\n";
  xcconfig = sdk: d: let
    cond = if sdk == "macosx" then "" else "[sdk=${sdk}*]";
    ld = if sdk == "macosx" then macosLdflags d else mobileLdflags sdk d;
    hdr = if sdk == "macosx" then macosHeaders d else mobileHeaders sdk d;
    ldCond = if isWatch sdk && !isSim sdk then "${cond}[arch=arm64]" else cond;
  in lib.concatMapStrings (t:
    line "WWN_HEADERS_${t}${cond}" hdr + line "WWN_LDFLAGS_${t}${ldCond}" ld
    + lib.optionalString (isWatch sdk && !isSim sdk) (line "WWN_LDFLAGS_${t}${cond}[arch=arm64_32]" [ "-liconv" ])
  ) (targets.${sdk} or targets.${family sdk})
  + "WWN_VERSION_DEFS = ${lib.concatStringsSep " " versionDefs}\nMARKETING_VERSION = ${wawonaVersion}\n";

  modeBXcconfig = let d = slices.iphoneos.deps; t = "Wawona_iOS_ModeB"; c = "[sdk=iphoneos*]"; in
    line "WWN_HEADERS_${t}${c}" (mobileHeaders "iphoneos" d ++ [ "${p modeB.iomfb}/include" "${p modeB.igetty}/include" ])
    + line "WWN_LDFLAGS_${t}${c}" (mobileLdflags "iphoneos" d
      ++ undef [ "wwn_modeb_desktop_start" "wwn_iomfb_open" ] ++ [ "-L${p modeB.iomfb}/lib" "-lwwn_iomfb" ]
      ++ undef [ "wwn_igetty_ios_initialize" ] ++ [ "-L${p modeB.igetty}/lib" "-lwwn_igetty_ios" ]);

  fonts = pkgs.callPackage ../libs/fonts { };
  xkb = pkgs.callPackage ../libs/xkb-trimmed.nix { };
  cursors = pkgs.callPackage ./adwaita-cursors.nix { };
  catalog = pkgs.callPackage ../generators/applications-catalog.nix { inherit pkgs lib wawonaSrc; };

  # Mobile bundle root: share/ beside the executable. Watch ships a font and
  # rootfs subset (ASC ITMS-90389: 75 MB thinned cap; scripts under the watch
  # rootfs are flagged as unsigned code).
  mobileBundle = sdk: d: ''
    mkdir -p bundle/share/X11 bundle/share/fonts
    ln -s ${xkb}/share/X11/xkb bundle/share/X11/xkb
  '' + (if isWatch sdk then ''
    mkdir bundle/share/fonts/truetype bundle/share/icons
    for f in Regular Bold; do
      ln -s ${fonts}/share/fonts/truetype/DejaVuSansMNerdFontMono-$f.ttf bundle/share/fonts/truetype/
    done
    ln -s ${catalog}/share/applications bundle/share/applications
    ln -s ${catalog}/share/icons/hicolor bundle/share/icons/hicolor
    cp -R ${d.wawona-rootfs}/rootfs bundle/wawona-rootfs
    chmod -R u+w bundle/wawona-rootfs
    rm -rf bundle/wawona-rootfs/usr/share/zsh
    find bundle/wawona-rootfs -type f \( -name '*.pl' -o -name '*.py' -o -name '*.rb' \
      -o -name '*.sh' -o -name '*.bash' -o -name '*.zsh' \) -delete
  '' else ''
    rmdir bundle/share/fonts
    ln -s ${fonts}/share/fonts bundle/share/fonts
    ln -s ${d.wawona-rootfs}/rootfs bundle/wawona-rootfs
  '');

  # macOS bundle root: Contents/. xcode-embed.sh signs and relocates what lands here.
  macosBundle = d: let x = macosExtras; r = "bundle/Resources"; in ''
    mkdir -p ${r}/bin ${r}/share/icons/Adwaita ${r}/vulkan/icd.d bundle/MacOS bundle/Frameworks
    for b in ${d.waypipe}/bin/waypipe ${d.sshpass}/bin/sshpass ${x.fastfetch}/bin/fastfetch ${x.zsh}/bin/zsh \
      ${lib.concatMapStringsSep " " (t: "${d.openssh}/bin/${t}") [ "ssh" "ssh-keygen" "scp" "sftp" "ssh-agent" "ssh-add" ]}; do
      ln -s $b ${r}/bin/
    done
    ln -s ${x.igetty}/bin/igettyd ${x.igetty}/bin/igetty bundle/MacOS/
    for l in modeb-ttyd:igettyd modeb-tty:igettyd modeb-getty:igetty; do
      ln -s ''${l#*:} bundle/MacOS/''${l%%:*}
      ln -s ../../MacOS/''${l#*:} ${r}/bin/''${l%%:*}
    done
    ln -s ../../MacOS/igetty ${r}/bin/igetty
    mkdir -p ${r}/libexec && ln -s ${x.igetty}/libexec/wwn-modeb-session ${r}/libexec/
    ln -s ${fonts}/share/fonts ${r}/share/fonts
    ln -s ${cursors}/share/icons/Adwaita/cursors ${cursors}/share/icons/Adwaita/index.theme ${r}/share/icons/Adwaita/
    ln -s ${cursors}/share/icons/default ${r}/share/icons/default
    ln -s ${catalog}/share/applications ${r}/share/applications
    ln -s ${catalog}/share/icons/hicolor ${r}/share/icons/hicolor
    for j in ${x.moltenvk}/share/vulkan/icd.d/*.json; do
      sed 's|"library_path":.*|"library_path": "../../../Frameworks/libMoltenVK.dylib",|' $j > ${r}/vulkan/icd.d/$(basename $j)
    done
    cp ${x.moltenvk}/lib/libMoltenVK.dylib bundle/Frameworks/
    cp ${d.iland}/lib/libEGL.dylib bundle/Frameworks/libEGL.dylib
    cp ${d.angle}/lib/libEGL.dylib bundle/Frameworks/libEGL_angle.dylib
  '';

  mkSlice = sdk: { deps, backend }: let
    macos = sdk == "macosx";
    ff = if macos then null else deps.fastfetch;
  in pkgs.runCommand "wawona-deps-${sdk}" { } (''
    mkdir -p $out && cd $out
    ln -s ${backend} backend
    if [ -d ${backend}/uniffi/swift ]; then ln -s ${backend}/uniffi/swift uniffi; fi
    cat > Wawona.xcconfig <<'EOF'
    ${xcconfig sdk deps}
    EOF
  '' + lib.optionalString (!macos) ''
    ln -s ${deps.zsh} zsh
    ln -s ${ff} fastfetch
    fw=$(sed '/^$/d; s/^/-framework /' ${ff}/nix-support/fastfetch-frameworks | tr '\n' ' ')
    substituteInPlace Wawona.xcconfig --replace-fail @FASTFETCH_FRAMEWORKS@ "$fw"
  '' + (if macos then macosBundle deps else mobileBundle sdk deps));
  # The Sileo (iOS 13) and TrollStore (iOS 14) products differ only in backend.
  modeBSlice = backend: (mkSlice "iphoneos" (slices.iphoneos // { inherit backend; })).overrideAttrs (old: {
      name = "wawona-deps-iphoneos-modeb";
      buildCommand = old.buildCommand + ''
        cat > Wawona.xcconfig <<'EOF'
        ${modeBXcconfig}
        EOF
        fw=$(sed '/^$/d; s/^/-framework /' ${slices.iphoneos.deps.fastfetch}/nix-support/fastfetch-frameworks | tr '\n' ' ')
        substituteInPlace Wawona.xcconfig --replace-fail @FASTFETCH_FRAMEWORKS@ "$fw"
      '';
    });
in
  lib.mapAttrs mkSlice slices // { iphoneos-modeb = modeBSlice modeB.backend; inherit modeBSlice; }

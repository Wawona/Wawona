# Bundled userland prefix for iOS/iPadOS local shell (App Store–compliant).
{
  lib,
  pkgs,
  buildModule,
  iosToolchain,
  simulator ? false,
}:

let
  zsh = buildModule.buildForIOS "zsh" { inherit simulator; };
  zshrcTemplate = pkgs.writeText "zshrc.template" ''
    export HISTFILE="$HOME/.zsh_history"
    export HISTSIZE=5000
    autoload -Uz add-zsh-hook

    wwn-report-cwd() {
      print -Pn "\e]7;file://''${PWD}\a"
    }
    add-zsh-hook chpwd wwn-report-cwd
    wwn-report-cwd

    PS1='%F{green}%n@%m%f:%F{blue}%~%f$ '
  '';
in
pkgs.runCommand "wawona-rootfs-ios${if simulator then "-sim" else ""}"
  {
    inherit zsh;
  }
  ''
    set -euo pipefail
    mkdir -p $out/rootfs/usr/bin $out/rootfs/usr/share/zsh $out/rootfs/etc/zsh $out/rootfs/home
    cp "$zsh/bin/zsh" $out/rootfs/usr/bin/zsh
    chmod 755 $out/rootfs/usr/bin/zsh
    if [ -d "$zsh/share/zsh" ]; then
      cp -R "$zsh/share/zsh/." $out/rootfs/usr/share/zsh/
    fi
    cp ${zshrcTemplate} $out/rootfs/etc/zsh/zshrc.template
    cat > $out/rootfs/README.txt <<'EOF'
Bundled Wawona userland — do not modify files inside the app bundle.
Writable HOME and history live under Application Support after first launch.
EOF
  ''

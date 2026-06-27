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

  # Sourced by every zsh (before .zshrc). The build-time fpath/module_path
  # prefix is a read-only Nix store path that does not exist on the device,
  # so re-point fpath at the bundled function tree. Modules are statically
  # linked (configure --disable-dynamic), so module_path is unused.
  zshenvTemplate = pkgs.writeText "zshenv.template" ''
    # Wawona iOS .zshenv — sourced for every shell. Safe to edit.
    : ''${WAWONA_BUNDLE_ROOTFS:=''${WAWONA_ROOTFS:-''${HOME:h}}}
    typeset -gU fpath
    # Default fpath: ZLE/prompt helpers only. The Completion/ tree (compinit,
    # _* completers) is large and its autoload path currently faults on iOS;
    # add it only when WAWONA_ENABLE_COMPINIT=1.
    fpath=(
      $WAWONA_BUNDLE_ROOTFS/usr/share/zsh/Functions
      $WAWONA_BUNDLE_ROOTFS/usr/share/zsh/Functions/**(/N)
    )
    if [[ -n "''${WAWONA_ENABLE_COMPINIT:-}" ]]; then
      fpath=(
        $WAWONA_BUNDLE_ROOTFS/usr/share/zsh/Completion
        $WAWONA_BUNDLE_ROOTFS/usr/share/zsh/Completion/**(/N)
        $fpath
      )
    fi
  '';

  # Interactive configuration. Real zsh + ZLE drive the line editor; this no
  # longer contains a read/eval loop. Fully user-editable in writable HOME.
  zshrcTemplate = pkgs.writeText "zshrc.template" ''
    # Wawona iOS .zshrc — interactive shell configuration. Safe to edit.

    export HISTFILE="$HOME/.zsh_history"
    export HISTSIZE=2000
    export SAVEHIST=2000
    setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE
    setopt INTERACTIVE_COMMENTS NO_BEEP NO_NOMATCH

    # No real child processes exist in the sandbox; keep job-control quiet.
    unsetopt MONITOR 2>/dev/null

    # Completion disabled by default on iOS (see .zshenv fpath). Set
    # WAWONA_ENABLE_COMPINIT=1 before launch to opt in once the autoload path
    # is stable on device.
    # A command whose output lacks a trailing newline must not leave a stray
    # inverse '%' mark bleeding into the next prompt over the fake PTY.
    PROMPT_EOL_MARK=""

    PROMPT='%F{cyan}%~%f %# '

    # Long OSC 7 cwd URIs overflow weston-terminal's escape buffer and the path
    # leaks onto the screen as plain text. Keep the prompt; drop cwd OSC hooks.
    chpwd_functions=()
    precmd_functions=( ''${precmd_functions:#__vte*} ''${precmd_functions:#_vte*} )
    for __wwn_vte_fn in __vte_osc7 _vte_precmd __vte_precmd; do
      (( ''${+functions[__$wwn_vte_fn]} )) && unfunction __wwn_vte_fn 2>/dev/null
    done
    unset __wwn_vte_fn
    precmd() {
      print -Pn "\e]0;%~\a"
    }

    # No fork/exec for terminal control sequences.
    clear() {
      print -rn -- $'\033[2J\033[H'
    }

    # Bundled in-process utilities (uutils coreutils) that the zsh exec hook
    # dispatches WITHOUT fork/exec on the iOS sandbox. Keep in sync with the
    # `coreutils` feature subset in Cargo.toml and wwn_safe_subset in
    # wawona-dispatch.c. These names normally never reach the handler below
    # (the exec hook runs them in-process); the list only lets us print an
    # accurate message if a build ships without the coreutils feature linked.
    typeset -gaU WAWONA_INPROC_TOOLS
    WAWONA_INPROC_TOOLS=(
      ls cat cp mv rm mkdir rmdir ln touch echo pwd head tail wc sort cut tr
      seq basename dirname stat du df date env printenv uname whoami yes tee
      nl tac fold expand unexpand truncate
    )

    # iOS sandbox: there is no fork/exec. zsh builtins and the bundled
    # in-process tools above run directly; everything else cannot launch.
    # This handler is the clean fallback for commands the in-process dispatcher
    # did not handle.
    command_not_found_handler() {
      local cmd="$1"
      if (( ''${WAWONA_INPROC_TOOLS[(Ie)$cmd]} )); then
        # A bundled tool that the dispatcher could not run (e.g. a build
        # without the coreutils feature linked, such as watchOS).
        print -- "wawona: '$cmd' is bundled but unavailable in this build."
      else
        print -- "wawona: command not found: $cmd (no builtin or bundled in-process tool; external binaries can't run in the iOS sandbox)."
      fi
      return 127
    }
  '';

  # Login shells source this last. Keep it short and user-editable.
  zloginTemplate = pkgs.writeText "zlogin.template" ''
    # Wawona iOS .zlogin — runs once for login shells. Safe to edit.
    print -P "%F{green}Wawona%f zsh ''${ZSH_VERSION} — in-process, App Store compliant."
    # zsh runs interactively ("-zsh -i"); its main loop draws PROMPT before each
    # ZLE read, so do not emit a prompt here (it would double the first prompt).
  '';
in
pkgs.runCommand "wawona-rootfs-ios${if simulator then "-sim" else ""}"
  {
    inherit zsh;
  }
  ''
    set -euo pipefail
    mkdir -p $out/rootfs/etc/zsh $out/rootfs/home $out/rootfs/usr/bin $out/rootfs/usr/share
    cp ${zshenvTemplate} $out/rootfs/etc/zsh/zshenv.template
    cp ${zshrcTemplate} $out/rootfs/etc/zsh/zshrc.template
    cp ${zloginTemplate} $out/rootfs/etc/zsh/zlogin.template
    cat > $out/rootfs/usr/bin/zsh <<'EOF'
# Wawona iOS: zsh is linked into the app binary (libwawona-zsh.a).
# This path exists only for shell conventions; exec is in-process via wawona-pty.
EOF
    if [ -d "$zsh/share/zsh" ]; then
      cp -R "$zsh/share/zsh" $out/rootfs/usr/share/
    fi
    cat > $out/rootfs/README.txt <<'EOF'
Bundled Wawona userland templates — do not modify files inside the app bundle.
zsh is linked into the app binary; this tree holds templates, share files, and
writable HOME data under Application Support after first launch.
EOF
    echo "16" > $out/rootfs/etc/zsh/.template-version
  ''

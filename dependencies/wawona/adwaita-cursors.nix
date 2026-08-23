# Weston cursor assets without nixpkgs adwaita-icon-theme.
#
# pkgs.adwaita-icon-theme rebuilds the full GTK icon set (meson, gtk, librsvg,
# gdk-pixbuf, libtiff -doc). libtiff docs pull Sphinx → requests →
# charset-normalizer (mypyc) → mypy pytest. A cold Darwin laptop then spends
# ~45 minutes compiling Python that Wawona never ships.
#
# GNOME's source tarball already contains the Xcursor files. This derivation
# unpacks those plus the X11 aliases meson would have installed. Dependencies
# are the tarball FOD and stdenvNoCC. Not gtk, not librsvg, not mypy.
{
  lib,
  stdenvNoCC,
  adwaita-icon-theme,
}:
stdenvNoCC.mkDerivation {
  pname = "adwaita-cursors";
  inherit (adwaita-icon-theme) version src;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/icons/Adwaita/cursors
    cp -a Adwaita/cursors/. $out/share/icons/Adwaita/cursors/
    rm -f $out/share/icons/Adwaita/cursors/*.cur
    cd $out/share/icons/Adwaita/cursors

    # Adwaita 50 meson.build cursor_symlinks (X11 names → CSS names).
    link_aliases() {
      src="$1"
      shift
      for dest in "$@"; do
        ln -sfn "$src" "$dest"
      done
    }
    link_aliases all-resize fleur
    link_aliases crosshair cross cross_reverse diamond_cross tcross
    link_aliases context-menu dnd-ask
    link_aliases default arrow dnd-move left_ptr top_left_arrow move
    link_aliases e-resize right_side
    link_aliases ew-resize sb_h_double_arrow
    link_aliases grab hand1
    link_aliases help question_arrow
    link_aliases n-resize top_side
    link_aliases ne-resize top_right_corner
    link_aliases nesw-resize fd_double_arrow
    link_aliases ns-resize sb_v_double_arrow
    link_aliases nw-resize top_left_corner
    link_aliases nwse-resize bd_double_arrow
    link_aliases pointer hand2
    link_aliases s-resize bottom_side
    link_aliases se-resize bottom_right_corner
    link_aliases sw-resize bottom_left_corner
    link_aliases text xterm
    link_aliases w-resize left_side
    link_aliases wait watch
    # Weston looks for these; Adwaita 50 does not ship them.
    ln -sfn copy dnd-copy
    ln -sfn default dnd-none

    runHook postInstall
  '';

  meta = {
    description = "Adwaita Xcursor files for Weston, without gtk or librsvg";
    homepage = adwaita-icon-theme.meta.homepage or "https://gitlab.gnome.org/GNOME/adwaita-icon-theme";
    license = adwaita-icon-theme.meta.license or lib.licenses.cc-by-sa-30;
  };
}

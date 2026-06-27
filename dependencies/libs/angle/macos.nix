# ANGLE for macOS — Conformant OpenGL ES (GLES2/3) over Metal.
#
# Provided by nixpkgs (cached binary, BSD-3). This is the GLES/EGL implementation
# that the iland `egl` shim and the GL Weston test clients (weston-simple-egl,
# kmscube, es2gears) link/dlopen against.
#
# Outputs: $out/lib/{libEGL.dylib,libGLESv2.dylib,...} and $out/include/{EGL,GLES2,GLES3,KHR}.
{
  lib,
  pkgs,
  common ? null,
  buildModule ? null,
  ...
}:

pkgs.angle

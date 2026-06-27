<div align="center">
  <img src=".resources/iland_mascot.png" alt="iland mascot" width="210">

  # iland

  **_Wayland compositor support library for macOS_**
</div>

# What is this?

iland is a library that implements the platform functionality required by Wayland compositors on macOS.

It is not an application, desktop environment, compositor, or display server. Instead, iland provides the low-level services that Wayland compositors expect from the operating system, allowing them to run natively on macOS.

No AppKit, Cocoa, Aqua, or WindowServer integration is required.

# Bullshit!

I'm not kidding! Look for yourself! (Booting directly to Weston)

<img src=".resources/booting-to-weston.gif" alt="Booting to Weston on macOS" width="600">

# Build!!

To build, you need these:
```
sudo port install angle                  # OpenGL ES implementaition
sudo port install wayland                # XQuartz fork — builds on darwin
sudo port install wayland-protocols
sudo port install libpixman cairo pango
sudo port install libxkbcommon
sudo port install pkgconfig meson ninja
```

`sh compile.sh`
Produces `libwayland-mac.dylib`. 

# Weston?
Clean: `sudo pkill -9 inputd framebufferd weston caffeinate; sudo rm -rf /private/tmp/libwayland-support; rm -rf build build-weston;`

Build: `sh compile.sh; sh build-weston.sh`

All: `sudo pkill -9 inputd framebufferd weston caffeinate; sudo rm -rf /private/tmp/libwayland-support; rm -rf build build-weston; sh compile.sh; sh build-weston.sh`

**System Integrity Protection (SIP) must be disabled** for `DYLD_INSERT_LIBRARIES` and runtime code patching (used by Dobby) to function. Without disabling SIP, the shim will not work.

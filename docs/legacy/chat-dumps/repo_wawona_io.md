> **Superseded.** Jailbreak/Procursus chat dump. Not product documentation. Do not copy to wawona.io. Never mix with `wwn-apt`.

I can run x11, fluxbox wm, pasteboard, launchd, neovim, and other packages on my iPhone using Dopamine2 roothide jailbreak.
There is a repo from roothide which supports many procurses-roothide packages, many include super bizzare packages patched to run on iOS. Where are they? Where is fluxbox for iOS? where is x11 for iOS? Where is pasteboard for iOS? Where is launchd for iOS? 
What you're seeing is one of the more interesting parts of the modern iOS jailbreak ecosystem.
The short answer is: they are mostly standard Unix/Linux packages that have been cross-compiled for Darwin/iOS by the Procursus project, with a relatively small number of iOS-specific patches. They aren't rewritten from scratch for iOS.

Here's where everything comes from.

Procursus
Almost all of the packages you're describing originate from the Procursus build system.
Procursus is effectively an entire cross-compiling distribution that builds thousands of packages for Apple platforms (iOS, iPadOS, tvOS, macOS, etc.). It produces Debian packages (.deb) that Dopamine, palera1n, and other Procursus-based jailbreaks install.

The build recipes live in Procursus' repositories, where each package has:

build scripts
Darwin patches
compiler flags
dependency information
packaging metadata
For many packages there are zero or only a few lines of iOS-specific code.
Fluxbox
Fluxbox is literally the normal X11 Fluxbox source code.
Procursus simply builds it against Darwin versions of:

libX11
libXext
libXrender
libXrandr
libXft
freetype
fontconfig
etc.
The Procursus package lists it as an iOS package depending on the X11 libraries above.
So there is no special "iOS Fluxbox."

It's basically:

Fluxbox source
        ↓
Darwin patches
        ↓
cross compile
        ↓
.deb
X11
Likewise, the X11 libraries are largely the same X.Org codebase.
Procursus has packages for things like:

libX11
libxcb
xtrans
xorgproto
libXrender
libXext
xbitmaps
many others
These are the same libraries Linux distributions package, rebuilt for Darwin/iOS.
The actual X server is a different story—historically, running a full X server on iOS has required additional work because iOS doesn't expose a traditional framebuffer or desktop environment. Many setups instead display X applications through VNC or remote displays rather than directly on SpringBoard.

launchd
This one's different.
launchd is Apple's own init system.

It is already part of iOS.

There isn't a Procursus implementation replacing it.

Jailbreaks simply expose it.

When you use:

launchctl
you're talking to the same launchd that boots every iPhone.
Jailbreaks mainly:

remove restrictions
allow additional LaunchDaemons
expose more filesystem locations
patch sandboxing
They do not replace launchd itself.
pasteboard
Similarly, "pasteboard" isn't a Procursus invention.
On iOS the system pasteboard is Apple's:

UIPasteboard
or at a lower level:
pasteboardd
There are also command-line utilities that communicate with the system pasteboard daemon.
Again, Procursus generally packages userland tools rather than replacing the underlying Apple service.

Neovim
Neovim is almost entirely unchanged.
The only differences are:

compiled for arm64e Darwin
linked against Procursus libraries
packaged into a .deb
Same source code.
Why do these packages run?
Because Darwin is still Unix.
Underneath UIKit and SpringBoard you still have:

POSIX
libc
Mach kernel
BSD sockets
pthreads
mmap
fork substitutes
pipes
signals
kqueue
Most Unix software doesn't care whether it's running on:
macOS
iOS
tvOS
as long as those interfaces exist.
Where are the patches?
Usually in Procursus itself.
For example a package directory typically contains something like

build.sh
patches/
control
The patches/ directory is where Darwin-specific fixes live.
Many packages have:

patches/
    0001-darwin.patch
Others have no patches whatsoever because they already build cleanly.
Why are there so many "weird" packages?
Procursus has spent years porting the BSD/Linux userspace to iOS.
That includes:

gcc
clang
llvm
git
tmux
zsh
fish
neovim
python
ruby
node
rust
Go
Java
X11
Fluxbox
OpenSSH
rsync
ffmpeg
ImageMagick
Thousands of packages are available because once the foundational libraries (libc, libiconv, ncurses, OpenSSL, zlib, etc.) were ported, many higher-level Unix programs could be rebuilt with relatively little effort.
How does Dopamine rootHide fit into this?
Dopamine rootHide doesn't provide these packages itself. Instead, it provides a jailbreak environment that allows Procursus packages to run in a rootless-compatible way while coexisting with iOS's sealed system volume and modern security model. The package manager then installs Procursus-built .deb packages into the jailbreak's writable prefix.
Since you're interested in Wawona Compositor and bringing more desktop-like software to iOS, you're looking at the same ecosystem that has already demonstrated it's possible to port large parts of a Unix desktop stack. Understanding how Procursus adapts packages—and where it has to patch around Darwin-specific behavior—is a good foundation for porting additional software such as Wayland compositors or graphics libraries.
Nice! but where the hell are these packages and their patches and sources? I want them
Yep. The nice thing about Procursus is that almost everything is open source. You can study exactly how they got packages like Fluxbox, X11, Python, GCC, etc. running on iOS.
1. The Procursus build system (this is the gold mine)
This is the repository you want:
Procursus GitHub repository

It contains things like:

makefiles/
    fluxbox.mk
    xorg-libX11.mk
    xorg-libXext.mk
    neovim.mk
    python3.mk
    clang.mk
    ...
and
build_info/
which contains the Debian control files.
2. The patches
These are usually here:
build_patch/
or for older packages:
build_info/<package>/
For example, Fluxbox has:
build_info/
    fluxbox/
        bsd.diff
That bsd.diff is the patch Procursus applies before compiling.
3. The build recipe
Every package has a .mk file.
For Fluxbox you'll find something like

makefiles/fluxbox.mk
which tells Procursus
download source
apply patches
configure
cross compile
package into .deb
These files are incredibly useful because they show exactly which compiler flags and SDKs were required.
4. Where does Fluxbox itself come from?
Not Procursus.
It downloads the official source from the Fluxbox project.

Official source:

Fluxbox source code

or release tarballs:

Fluxbox downloads

Procursus doesn't fork it unless necessary.

X11
The X11 libraries are also upstream.
Examples include

xorg-libX11.mk

xorg-libxcb.mk

xorg-libXext.mk

xorg-libXrender.mk

xorg-libXrandr.mk

xorgproto.mk
Most of these simply download from X.Org.
Where are the actual .deb packages?
If you're jailbroken they're already installed.
For example

/var/jb/Library/dpkg/info/
contains
fluxbox.list

fluxbox.md5sums

fluxbox.postinst

fluxbox.prerm
while the binaries live under
/var/jb/usr/bin

/var/jb/usr/lib

/var/jb/usr/share
because Dopamine rootHide uses /var/jb as the jailbreak prefix.
Want to see the source package?
You can even ask apt.
apt source fluxbox
or
apt-cache showsrc fluxbox
if the repository provides source packages.
The build system is fascinating
Here's the part that made me smile when I first dug into it.
Procursus has an entire Apple cross compiler toolchain.

Inside you'll find scripts like

build_tools/

compile_iphoneos.sh

compile_macos.sh

prosdk.sh

cross-pkg-config

aarch64-apple-ios-pkg-config
Those are literally the scripts that turn ordinary Unix software into iOS packages.
If you're interested in Wawona Compositor...
This is exactly where I'd start.
I'd spend a weekend reading:

makefiles/
starting with
xorg-libX11.mk
libxcb.mk
mesa.mk
libdrm.mk
pixman.mk
cairo.mk
pango.mk
gtk3.mk
fluxbox.mk
and then compare them against their Linux counterparts.
You'll quickly discover that 95% of the work isn't in the application itself—it's in the build system. Procursus has already solved a huge amount of the Darwin-specific cross-compilation, SDK, codesigning, packaging, and patch management. Reusing those techniques could save you a tremendous amount of effort when bringing additional desktop software to iOS.




Sorry. fastfetch isn't there, only neofetch was. ignore it. 

Let's dig into neovim instead. 
12 files
 (105 ms)
12 files
in
ProcursusTeam/Procursus (press backspace or delete to remove)


makefiles/neovim.mk
Makefile
·
52
 (52)
SUBPROJECTS    += neovim
NEOVIM_VERSION := 0.9.0
DEB_NEOVIM_V   ?= $(NEOVIM_VERSION)
neovim-setup: setup
	$(call GITHUB_ARCHIVE,neovim,neovim,v$(NEOVIM_VERSION),v$(NEOVIM_VERSION))
	$(call EXTRACT_TAR,neovim-v$(NEOVIM_VERSION).tar.gz,neovim-$(NEOVIM_VERSION),neovim)
	$(call DO_PATCH,neovim,neovim,-p1)
	$(call DO_PATCH,neovim-ios,neovim,-p1)
Show 34 more matches


build_info/neovim.prerm
Shell
·
5
 (5)
case "$1" in
  remove|deconfigure)
    update-alternatives --remove editor @MEMO_PREFIX@@MEMO_SUB_PREFIX@/bin/nvim
    update-alternatives --remove ex @MEMO_PREFIX@@MEMO_SUB_PREFIX@/libexec/neovim/ex
    update-alternatives --remove rvim @MEMO_PREFIX@@MEMO_SUB_PREFIX@/libexec/neovim/rvim
    update-alternatives --remove rview @MEMO_PREFIX@@MEMO_SUB_PREFIX@/libexec/neovim/rview
    update-alternatives --remove vi @MEMO_PREFIX@@MEMO_SUB_PREFIX@/bin/nvim
Show 2 more matches


build_info/neovim.control
6
 (6)
Package: neovim
Version: @DEB_NEOVIM_V@
Architecture: @DEB_ARCH@
Maintainer: @DEB_MAINTAINER@
Priority: optional
Homepage: https://neovim.io/
Section: Text_Editors
Show 3 more matches


build_info/neovim.postinst
Shell
·
5
 (5)
…ate-alternatives --install @MEMO_PREFIX@@MEMO_SUB_PREFIX@/bin/ex ex @MEMO_PREFIX@@MEMO_SUB_PREFIX@/libexec/neovim/ex 30
…ternatives --install @MEMO_PREFIX@@MEMO_SUB_PREFIX@/bin/rvim rvim @MEMO_PREFIX@@MEMO_SUB_PREFIX@/libexec/neovim/rvim 30
…natives --install @MEMO_PREFIX@@MEMO_SUB_PREFIX@/bin/rview rview @MEMO_PREFIX@@MEMO_SUB_PREFIX@/libexec/neovim/rview 30
…ternatives --install @MEMO_PREFIX@@MEMO_SUB_PREFIX@/bin/view view @MEMO_PREFIX@@MEMO_SUB_PREFIX@/libexec/neovim/view 30
…s --install @MEMO_PREFIX@@MEMO_SUB_PREFIX@/bin/vimdiff vimdiff @MEMO_PREFIX@@MEMO_SUB_PREFIX@/libexec/neovim/vimdiff 30


build_patch/neovim-ios/neovim-no-coreservices.diff
Diff
·
2
 (2)
--- neovim/src/nvim/os/lang.c.orig	2023-04-20 04:04:04.055687796 +0000
+++ neovim/src/nvim/os/lang.c	2023-04-20 04:08:13.254952890 +0000
@@ -26,10 +26,7 @@
 
     // $LANG is not set, either because it was unset or Nvim was started
     // from the Dock. Query the system locale.
-    if (LocaleRefGetPartString(NULL,


build_misc/neovim/ex
Shell
·
0
 (0)
#!/bin/sh
exec /usr/bin/nvim -e "$@"


build_patch/neovim/cross.patch
Diff
·
4
 (4)
--- neovim/src/nvim/po/CMakeLists.txt.orig	2023-04-20 04:17:33.297033954 +0000
+++ neovim/src/nvim/po/CMakeLists.txt	2023-04-20 04:17:39.923092526 +0000
@@ -53,7 +53,7 @@
   list(SORT NVIM_RELATIVE_SOURCES)
   add_custom_command(
     OUTPUT ${NVIM_POT}
-    COMMAND $<TARGET_FILE:nvim> -u NONE -i NONE -n --headless --cmd "set cpo+=+"
Show 2 more matches


build_misc/neovim/rvim
Shell
·
0
 (0)
#!/bin/sh
exec /usr/bin/nvim -Z "$@"


build_misc/neovim/view
Shell
·
0
 (0)
#!/bin/sh
exec /usr/bin/nvim -R "$@"


build_misc/neovim/rview
Shell
·
0
 (0)
#!/bin/sh
exec /usr/bin/nvim -RZ "$@"


build_misc/neovim/vimdiff
Shell
·
0
 (0)
#!/bin/sh
exec /usr/bin/nvim -d "$@"


makefiles/unibilium.mk
Makefile
·
1
 (1)
DEB_UNIBILIUM_V   ?= $(UNIBILIUM_VERSION)
unibilium-setup: setup
	$(call GITHUB_ARCHIVE,neovim,unibilium,$(UNIBILIUM_VERSION),v$(UNIBILIUM_VERSION))
	$(call EXTRACT_TAR,unibilium-$(UNIBILIUM_VERSION).tar.gz,unibilium-$(UNIBILIUM_VERSION),unibilium)
	$(call DO_PATCH,unibilium,unibilium)
	mkdir -p $(BUILD_WORK)/unibilium/libtool



What if I want to bundle for Apple AppStore compliance? What patches need to be made here? 


This is exactly the kind of question where it's useful to distinguish between **"runs on a jailbroken iPhone"** and **"passes App Store Review."** They are very different targets.

The good news is that **Neovim is actually a surprisingly realistic candidate for App Store distribution.** There are already App Store apps that embed terminal editors or terminal emulators. The challenge isn't Neovim itself—it's how you integrate it.

## What the Procursus patches are doing

The two patches you found are mostly about making Neovim compile on Darwin/iOS.

### 1. `neovim-no-coreservices.diff`

This patch removes the use of Apple's CoreServices locale APIs.

It changes code like:

```c
LocaleRefGetPartString(...)
```

to use a more portable implementation.

This isn't an App Store issue—it's a build compatibility issue. CoreServices locale APIs aren't always available or desirable on iOS.

---

### 2. `cross.patch`

This fixes cross-compilation.

During a normal Neovim build, CMake runs the freshly-built `nvim` executable to generate translation files.

That doesn't work when you're cross-compiling on macOS for iOS because the iOS binary can't execute on the build machine.

Again, this has nothing to do with App Store compliance.

---

## What would actually need to change for the App Store?

Much less than people often think.

### 1. Remove assumptions about `/usr`

Procursus installs to:

```
/usr/bin
/usr/share
/usr/lib
```

or, under rootless jailbreaks:

```
/var/jb/usr/...
```

On the App Store, your app only has access to its sandbox.

You'd instead install Neovim under something like:

```
MyApp.app/
    Frameworks/
    Resources/
        runtime/
        syntax/
        lua/
```

or copy the runtime into:

```
Documents/.config
```

Then tell Neovim where it lives:

```c
setenv("VIMRUNTIME", "...", 1);
```

or via startup arguments.

---

### 2. Replace absolute paths

Procursus wrapper:

```sh
exec /usr/bin/nvim
```

becomes something like:

```objc
NSBundle.mainBundle
```

finding

```
Resources/bin/nvim
```

---

### 3. Runtime files

Neovim expects

```
share/nvim/runtime
```

Instead:

```
App Bundle
    Resources/runtime
```

No source changes required.

---

### 4. Dynamic libraries

Procursus links against

```
libuv
libluv
msgpack
tree-sitter
libtermkey
unibilium
libvterm
```

For the App Store you'd probably:

* statically link many of these
* or embed them in

```
Frameworks/
```

This is a packaging decision, not a Neovim source change.

---

### 5. Terminal backend

This is the biggest architectural change.

Neovim expects a terminal.

On iOS you need one.

Projects typically embed a terminal widget like:

* `VT100`-style emulation
* `libvterm`
* a custom terminal view

The App Store has many apps with embedded terminal emulators, so this is feasible.

---

### 6. Fork/PTY support

Neovim uses PTYs for `:terminal`.

iOS supports PTYs, but they're more constrained than on desktop Unix. Depending on your app's design, you might:

* disable `:terminal`,
* adapt it,
* or provide an internal shell process.

This is an engineering decision more than an App Store rule.

---

### 7. Shell configuration

Instead of assuming:

```
/bin/sh
```

or

```
/usr/bin/zsh
```

you'd point Neovim at the shell bundled with your app (or disable shell escapes if your app doesn't include one).

---

## What *doesn't* need changing?

Probably 95–99% of Neovim.

That's one reason Neovim is such a good embedded component.

---

## If I were building Wawona

Given what you've shared about Wawona, I'd avoid trying to mimic a jailbreak filesystem layout inside the app.

Instead I'd structure it roughly like:

```
Wawona.app
│
├── Frameworks
│     libuv
│     libtree-sitter
│     ...
│
├── Resources
│     nvim/
│         runtime/
│         syntax/
│         parser/
│
├── bin
│     nvim
│     zsh
│
└── Documents
      home/
          .config/
          projects/
```

Your launcher would:

1. set `HOME` to the app's Documents directory,
2. set `VIMRUNTIME` to the bundled runtime,
3. set `PATH` to the app's bundled `bin`,
4. `exec()` Neovim as a child process connected to a PTY.

Neovim itself would remain almost entirely unchanged.

---

## The broader insight

After reading through Procursus for a while, you'll notice a pattern: **the patches are usually about portability and cross-compilation, not about iOS UI or App Store policies.** The real work of making a Unix program "feel native" on iOS happens *outside* the program—in the launcher, filesystem layout, environment variables, process management, terminal emulator, and graphics integration.

For Wawona, this is encouraging because it means you can often keep upstream software very close to its original source, making updates and long-term maintenance much easier.

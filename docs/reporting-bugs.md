# How to report a Wawona bug

Use this when Wawona does nothing, a machine will not start, or a session looks
wrong. GitHub issues need a copied diagnostics block. Chat on Discord is optional.

Public page: [wawona.io/docs/reporting-bugs/](https://wawona.io/docs/reporting-bugs/).

## What to send

A useful report has all of these:

1. What you tapped (Start, Focus, a machine name such as Weston).
2. What you expected, and what you saw (including "nothing happened").
3. **Copied diagnostics** from the app when you can. That block includes:
   - Wawona version and build
   - Host OS, version, and device identifier
   - Install channel (TestFlight, Sideload, App Store, Simulator, macOS)
   - Active machine (id, name, type, client). No SSH passwords.
   - Recent in-app log lines

Sideloaded iOS IPAs do not go through TestFlight crash mail. Copied logs are how
we see those builds.

## TestFlight (Apple beta)

If **Install** in Settings → About says TestFlight, you have two channels. Use
both when you can.

### TestFlight feedback (App Store Connect)

Crashes on a TestFlight build are sent to App Store Connect on their own. For
anything that is not a crash (Start does nothing, a blank compositor, a wrong
window):

1. Reproduce the problem.
2. Take a screenshot in Wawona, or open the **TestFlight** app, select Wawona,
   and send **Beta Feedback**.
3. Write what you tapped and what you saw. Attach the screenshot if TestFlight
   offers it.

That feedback is the beta-tester path Apple provides. It does not include
Wawona's in-app log ring.

### GitHub with copied logs (still do this)

TestFlight mail does not replace copied diagnostics. After you send TestFlight
feedback (or instead, if you prefer GitHub):

1. **Settings → About → Copy Recent Logs** (or **Copy Active Machine Logs**).
2. Open [the bug form](https://github.com/Wawona/Wawona/issues/new?template=bug.yml).
3. Set install channel to **TestFlight**. Paste the clipboard into **Copied
   diagnostics**.

If you already sent TestFlight feedback, say so in the GitHub issue (date and
a short quote is enough). We cannot see TestFlight comments from GitHub, and
we cannot see GitHub from App Store Connect unless you link them.

TestFlight invites are posted on the [Wawona Discord](https://discord.gg/wHVSV52uw5).

Do not paste SSH passwords, key passphrases, or other secrets. The in-app copy
already omits those fields.

## Apple (iOS, iPadOS, macOS, visionOS)

1. Reproduce the problem once (Start the machine, wait a few seconds).
2. Open **Settings → About**.
3. Confirm **Version**, **Platform**, and **Install**.
4. Tap **Copy Recent Logs**. For a Weston or Niri session that failed, prefer
   **Copy Active Machine Logs** if that machine is still the active one.
5. Tap **Report a Bug on GitHub**, or open
   [the bug form](https://github.com/Wawona/Wawona/issues/new?template=bug.yml).
6. Paste the clipboard into **Copied diagnostics**. Fill platform, install
   channel, version, and host OS from the same block.

tvOS and watchOS have no pasteboard. **Copy Recent Logs** shows the text in an
alert. Photograph it or type the Version / Platform / Install lines into the
form, and describe what you tapped.

## Android and Linux

There is no Copy Logs button on those UIs yet. Open the same
[bug form](https://github.com/Wawona/Wawona/issues/new?template=bug.yml) and fill:

- Platform
- Install channel (Play, sideload APK, AppImage, nix, other)
- Wawona version (About in the app, or the CalVer in the filename)
- Host OS and version

Then describe Start / Focus and what you saw. Attach `adb logcat` (Android) or
a terminal capture (Linux) if you have one.

## After you file

The issue lands on [github.com/Wawona/Wawona](https://github.com/Wawona/Wawona/issues).
You can also ask on the [Wawona Discord](https://discord.gg/wHVSV52uw5). Put the
GitHub issue link in Discord if you already filed.

Settings keys for the copy buttons: see [settings.md](./settings.md) (About).

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
2. Open [the bug form](https://github.com/Wawona/Wawona/issues/new?template=bug.yml)
   or tap **Report a Bug on GitHub** (that step also copies logs and fills
   platform / version / host OS).
3. Confirm install channel is **TestFlight (Beta)**. Paste the clipboard into
   **Copied diagnostics** if that field is empty.

If you already sent TestFlight feedback, say so in the GitHub issue (date and
a short quote is enough). A scheduled importer (`Watch: TestFlight feedback`)
opens a GitHub issue when App Store Connect receives screenshot or crash
feedback. Tester email, UDID, IPs, and screenshot EXIF are stripped; sanitized
screenshots are attached when GitHub accepts the upload. Copied in-app logs are
still not in that payload. Paste them on the imported issue if you have them.

TestFlight invites are posted on the [Wawona Discord](https://discord.gg/wHVSV52uw5).

Do not paste SSH passwords, key passphrases, or other secrets. The in-app copy
already omits those fields.

## Apple (iOS, iPadOS, macOS, visionOS)

1. Reproduce the problem once (Start the machine, wait a few seconds).
2. Open **Settings → About**.
3. Confirm **Version**, **Platform**, and **Install**.
4. Tap **Report a Bug on GitHub**. Wawona copies recent logs (active-machine
   lines when a machine is selected) and opens the
   [bug form](https://github.com/Wawona/Wawona/issues/new?template=bug.yml)
   with platform, install channel, version, host OS, and logs filled.
5. Write **What happened**. Submit.

**Copy Recent Logs** / **Copy Active Machine Logs** remain if you only need
the clipboard.

tvOS has no pasteboard. Report a Bug still opens the form with this platform
filled. watchOS Report a Bug opens the form on the paired iPhone.

## Android and Linux

**Settings → About → Report a Bug on GitHub** copies the in-app log ring and
opens the same form with platform Android or Linux filled. Attach `adb logcat`
or a terminal capture if the ring is empty.

## After you file

The issue lands on [github.com/Wawona/Wawona](https://github.com/Wawona/Wawona/issues).
You can also ask on the [Wawona Discord](https://discord.gg/wHVSV52uw5). Put the
GitHub issue link in Discord if you already filed.

Settings keys for the copy buttons: see [settings.md](./settings.md) (About).

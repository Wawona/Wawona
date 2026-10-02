# Apply Relay guest Multi-User fix on the Mac tree

This cloud agent cannot write `github.com/Wawona/Relay` (403) and cannot see
`/Users/8amps/Wawona/Relay`. Apply these files on the Mac Relay checkout:

```bash
cd /Users/8amps/Wawona/Relay
git apply /Users/8amps/Wawona/Wawona/docs/relay-build/0001-fix-guest-settle-Multi-User-via-linger-and-stable-in.patch
# or copy:
# cp docs/relay-build/guest-src/guest.nix import/vms/dependencies/vms/mobile/
# cp docs/relay-build/guest-src/guest-artifacts.nix import/vms/dependencies/vms/mobile/
cp docs/relay-build/static-cpu-completion-plan.md docs/
cp docs/relay-build/vsock-checkpoint.md docs/
```

Then rebuild guest artifacts and re-run the 1200s udev service traces.
Do not reset legacy disks. Preserve QA profile storage.

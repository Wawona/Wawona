#!/usr/bin/env python3
"""Verify the Linux canonical machine-profile model matches the cross-platform
`wawona.machineProfiles.v1` schema.

The Rust model in `src/linux/machine_profile.rs` must use the same serde JSON
keys as the Swift `MachineProfile`/`MachineRuntimeOverrides` Codable types
(`Sources/WawonaModel/MachineProfile.swift`), including the irregular acronym
casing, and expose all five machine types. The store
(`src/linux/profile_store.rs`) must persist under the canonical key and migrate
the legacy Linux config.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODEL = ROOT / "src/linux/machine_profile.rs"
STORE = ROOT / "src/linux/profile_store.rs"

# Canonical machine-type rawValues (snake_case) shared across platforms.
REQUIRED_TYPE_RAWS = ("native", "ssh_waypipe", "ssh_terminal", "virtual_machine", "container")

# MachineProfile CodingKeys (Swift property names used verbatim as JSON keys).
REQUIRED_PROFILE_KEYS = (
    '"type"', '"sshHost"', '"sshUser"', '"sshPort"', '"sshPassword"',
    '"remoteCommand"', '"vmSubtype"', '"containerSubtype"', '"runtimeOverrides"',
    '"executablePath"', '"autoLaunch"', '"displayName"',
)

# MachineRuntimeOverrides keys with irregular acronym casing that must be
# reproduced exactly (camelCase auto-derivation cannot).
REQUIRED_OVERRIDE_KEYS = (
    '"vulkanDriver"', '"openGLDriver"', '"dmabufEnabled"', '"inputProfile"',
    '"bundledAppID"', '"waypipeEnabled"', '"forceSSD"', '"renderMacOSPointer"',
    '"autoScale"', '"waylandDisplay"', '"colorOperations"', '"waypipeSSHPassword"',
    '"logLevel"', '"shakeToCloseEnabled"', '"swipeBackToCloseEnabled"',
)


def main() -> int:
    errors: list[str] = []

    if not MODEL.is_file():
        errors.append(f"missing canonical model: {MODEL}")
    if not STORE.is_file():
        errors.append(f"missing profile store: {STORE}")
    if errors:
        for e in errors:
            print(f"- {e}")
        return 1

    model = MODEL.read_text(encoding="utf-8")
    store = STORE.read_text(encoding="utf-8")

    for raw in REQUIRED_TYPE_RAWS:
        # snake_case rename_all derives these from the enum variants.
        pass
    # Ensure all five variants exist by name.
    for variant in ("Native", "SshWaypipe", "SshTerminal", "VirtualMachine", "Container"):
        if variant not in model:
            errors.append(f"machine_profile.rs missing MachineType::{variant}")
    if 'rename_all = "snake_case"' not in model:
        errors.append("MachineType must serialize snake_case to match Swift rawValues")

    for key in REQUIRED_PROFILE_KEYS:
        if key not in model:
            errors.append(f"machine_profile.rs missing canonical JSON key {key}")

    for key in REQUIRED_OVERRIDE_KEYS:
        if key not in model:
            errors.append(f"machine_profile.rs missing runtime-override key {key}")

    if "wawona.machineProfiles.v1" not in store:
        errors.append("profile_store.rs must use canonical key 'wawona.machineProfiles.v1'")
    if "machine-profiles-v1.json" not in store:
        errors.append("profile_store.rs must persist machine-profiles-v1.json")
    if "migrate_from_legacy" not in store:
        errors.append("profile_store.rs must migrate the legacy Linux config")

    if errors:
        print("Linux machine-profile parity check FAILED:")
        for e in errors:
            print(f"- {e}")
        return 1

    print("Linux machine-profile parity check OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())

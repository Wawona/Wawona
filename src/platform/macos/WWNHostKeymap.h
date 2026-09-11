// Thin macOS trampoline: TIS + UCKeyTranslate -> HostKeymapBridge.
// iOS family has no public TIS dump. Stubs no-op.

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// Walk the current layout source and push UTF-32 levels into Rust.
/// When `core` is non-NULL, also reload the Smithay seat keymap.
void WWNHostKeymapDumpAndApply(void *core);

/// Observe `kTISNotifySelectedKeyboardInputSourceChanged` (macOS only).
void WWNHostKeymapStartObserving(void *core);

#ifdef __cplusplus
}
#endif

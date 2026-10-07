//! wl_seat is owned by Smithay (`delegate_seat!` in `core/wayland/mod.rs`).
//!
//! Do not add custom `GlobalDispatch` / `Dispatch` for wl_seat, wl_pointer,
//! wl_keyboard, or wl_touch here. That dual-registers against Smithay and
//! fails `verify-wayland-runtime-ownership.py --strict`.

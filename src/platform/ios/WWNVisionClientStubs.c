/*
 * Intentionally empty.
 *
 * visionOS has macOS product parity and links the real fastfetch, fuzzel,
 * niri, neovim, and waypipe archives through visionosDeps/visionosSimDeps.
 * Do not reintroduce success-shaped link stubs here: they hide missing package
 * mappings and make Machines report that a bundled client started when it
 * immediately returned from a fake entry point.
 */

# Retired. Product Android no longer ships weston-simple-shm / foot / wawona_wl
# multicall into jniLibs. Optional Wayland clients install via Termux apt / wpm.
# Kept as an empty fragment so older call sites that still import this path
# get a no-op instead of a missing file.
{
  androidCC ? null,
  libwaylandAndroid ? null,
  westonAndroid ? null,
  footAndroid ? null,
}:
{
  preBuildFragment = ''
    echo "android-bundled-clients: skipped (optional-software unbundled)"
  '';
  verifyApkFragment = ''
    true
  '';
}

# Resolve JetBrains Runtime for Wawona Android Gradle.
# Source: `source scripts/lib/android-jbr.sh`
# Canonical: docs/agent-rules/wawona-android-jbr.md
#
# Prefer Android Studio embedded JBR 21. Never export Nix OpenJDK as the
# Studio / local Gradle JVM (Invalid Gradle JDK configuration).

wawona_android_jbr_home() {
  local c
  for c in \
    "${ANDROID_STUDIO_JBR:-}" \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
    "${HOME}/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
    "/opt/android-studio/jbr"
  do
    if [ -n "$c" ] && [ -x "$c/bin/java" ]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

wawona_android_export_jbr() {
  local home
  home="$(wawona_android_jbr_home)" || return 1
  export JAVA_HOME="$home"
  export PATH="$JAVA_HOME/bin:$PATH"
}

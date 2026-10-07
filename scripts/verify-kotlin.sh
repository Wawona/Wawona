#!/usr/bin/env bash
# Android host checks. JBMC or Java PathFinder must run. Lincheck is absent on purpose.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/android"
OUT="${1:-$ROOT/verification-out/kotlin.ndjson}"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"
REPORT="$ROOT/scripts/verification-report.py"
fail=0

emit() {
  python3 "$REPORT" emit --out "$OUT" --tool "$1" --file "$2" --line 1 \
    --rule "$3" --failure "$4" --fix "$5"
  fail=1
}

# Module path is :Wawona (settings.gradle maps it to app/).
GRADLE_TASKS=(:Wawona:testDebugUnitTest :Wawona:detekt :Wawona:lintDebug)
if ! ./gradlew "${GRADLE_TASKS[@]}" --offline; then
  if ! ./gradlew "${GRADLE_TASKS[@]}"; then
    emit gradle "android/app/src/test/java/com/aspauldingcode/wawona/MachineInputSanitizerTest.kt" \
      "kotest-detekt-lint" \
      "unit test, detekt, or lint failed" \
      "./gradlew ${GRADLE_TASKS[*]}"
  fi
fi

emit spotbugs "android/app/build.gradle.kts" "missing-tool" \
  "SpotBugs is not wired on AGP 9 (BaseExtension removed). Blocker until a SpotBugs Android path exists." \
  "restore SpotBugs when AGP-compatible plugin supports ApplicationExtension"

HARNESS="$ROOT/verification/kotlin/SanitizeHarness.java"
mkdir -p "$ROOT/verification-out/kotlin"
if ! javac -d "$ROOT/verification-out/kotlin" "$HARNESS"; then
  emit jbmc "verification/kotlin/SanitizeHarness.java" "javac" \
    "failed to compile JVM sanitizer harness" "javac verification/kotlin/SanitizeHarness.java"
else
  if command -v jbmc >/dev/null 2>&1; then
    if ! jbmc --classpath "$ROOT/verification-out/kotlin" SanitizeHarness \
        --unwind 8 --max-nondet-string-length 8; then
      emit jbmc "verification/kotlin/SanitizeHarness.java" "jbmc" \
        "JBMC failed the bounded sanitizer harness" \
        "jbmc --classpath verification-out/kotlin SanitizeHarness --unwind 8"
    fi
  else
    emit jbmc "verification/kotlin/SanitizeHarness.java" "missing-tool" \
      "JBMC is not installed. ESBMC Java is the listed fallback and was not selected." \
      "install CBMC's jbmc and run it on SanitizeHarness"
  fi

  if command -v jpf >/dev/null 2>&1 || [[ -n "${JPF_HOME:-}" ]]; then
    JPF_BIN="${JPF_HOME:+$JPF_HOME/bin/jpf}"
    JPF_BIN="${JPF_BIN:-jpf}"
    if ! "$JPF_BIN" +cg.max_depth=20 "$ROOT/verification-out/kotlin/SanitizeHarness.class" 2>/tmp/jpf.err; then
      emit jpf "verification/kotlin/SanitizeHarness.java" "jpf" \
        "$(tr '\n' ' ' </tmp/jpf.err | head -c 200)" \
        "jpf +cg.max_depth=20 SanitizeHarness"
    fi
  else
    emit jpf "verification/kotlin/SanitizeHarness.java" "missing-tool" \
      "Java PathFinder is not installed" \
      "install JPF and depth-cap SanitizeHarness"
  fi
fi

python3 "$REPORT" summarize "$OUT" --markdown "$(dirname "$OUT")/kotlin.md" || fail=1
exit "$fail"

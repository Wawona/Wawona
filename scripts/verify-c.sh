#!/usr/bin/env bash
# Analyzer and harness for Wawona-owned C. A missing prover is a finding.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:-$ROOT/verification-out/c.ndjson}"
mkdir -p "$(dirname "$OUT")/c"
: > "$OUT"
REPORT="$ROOT/scripts/verification-report.py"
fail=0
INC="-I src/platform/cproof -I src/platform/macos -I src/platform/android"

emit() {
  python3 "$REPORT" emit --out "$OUT" --tool "$1" --file "$2" --line "${3:-1}" \
    --rule "$4" --failure "$5" --fix "$6"
  fail=1
}

# ASan + UBSan harness
cc ${INC} -std=c11 -Wall -Werror -fsanitize=address,undefined \
  verification/c/test_cproof.c -o verification-out/c/test_cproof || \
  emit c-asan "verification/c/test_cproof.c" 1 "asan" \
    "C helper harness failed to build with ASan and UBSan" \
    "cc -fsanitize=address,undefined verification/c/test_cproof.c"
if [[ -x verification-out/c/test_cproof ]]; then
  verification-out/c/test_cproof || emit c-asan "verification/c/test_cproof.c" 1 "asan" \
    "C helper harness failed" "verification-out/c/test_cproof"
fi

# Graphics driver policy concrete test (may need more headers; record failure)
if [[ -f dependencies/tests/graphics-driver-policy.c && -f src/platform/macos/WWNSettings.c ]]; then
  if cc ${INC} -std=c11 -DWWN_SETTINGS_TEST_HARNESS \
      dependencies/tests/graphics-driver-policy.c src/platform/macos/WWNSettings.c \
      -o verification-out/c/graphics-driver-policy 2>/tmp/gdp.err; then
    verification-out/c/graphics-driver-policy || \
      emit graphics-driver "dependencies/tests/graphics-driver-policy.c" 1 "assert" \
        "graphics driver policy test failed" "verification-out/c/graphics-driver-policy"
  else
    emit graphics-driver "dependencies/tests/graphics-driver-policy.c" 1 "build" \
      "$(tr '\n' ' ' </tmp/gdp.err | head -c 400)" \
      "cc dependencies/tests/graphics-driver-policy.c src/platform/macos/WWNSettings.c"
  fi
fi

# Warnings-as-errors only on the pure helper TU. Wider JNI/platform C still
# runs under product compilers; dumping cert-* Werror across those trees is
# not the Verification report gate.
PROOF_C=(
  src/platform/cproof/wawona_cproof.c
)

if command -v clang-tidy >/dev/null 2>&1; then
  for f in "${PROOF_C[@]}"; do
    [[ -f "$f" ]] || continue
    # Narrow check set: cert + bugprone, minus noisy swappable-parameter noise
    # on intentional (fd, buf, cap) / (w, h, stride) helper shapes.
    if ! clang-tidy "$f" \
        --checks='-*,cert-*,bugprone-*,-bugprone-easily-swappable-parameters' \
        --warnings-as-errors='cert-*,bugprone-*' \
        -- ${INC} -std=c11 >/tmp/tidy.out 2>&1; then
      emit clang-tidy "$f" 1 "cert-bugprone" \
        "$(tail -n 5 /tmp/tidy.out | tr '\n' ' ')" \
        "clang-tidy $f --checks=-*,cert-*,bugprone-*"
    fi
  done
else
  emit clang-tidy "scripts/verify-c.sh" 1 "missing-tool" \
    "clang-tidy is not installed" "apt install clang-tidy"
fi

if command -v scan-build >/dev/null 2>&1; then
  if ! scan-build --status-bugs cc ${INC} -c src/platform/cproof/wawona_cproof.c -o verification-out/c/wawona_cproof.o; then
    emit scan-build "src/platform/cproof/wawona_cproof.c" 1 "scan-build" \
      "scan-build reported a bug" "scan-build cc -c src/platform/cproof/wawona_cproof.c"
  fi
else
  emit scan-build "scripts/verify-c.sh" 1 "missing-tool" \
    "scan-build is not installed" "apt install clang-tools"
fi

if command -v cbmc >/dev/null 2>&1; then
  cbmc verification/c/test_cproof.c ${INC} --unwind 4 || \
    emit cbmc "verification/c/test_cproof.c" 1 "cbmc" \
      "CBMC failed the helper harness" "cbmc verification/c/test_cproof.c --unwind 4"
else
  emit cbmc "src/platform/cproof/wawona_cproof.h" 1 "missing-tool" \
    "cbmc is not installed" "apt install cbmc"
fi

if command -v frama-c >/dev/null 2>&1; then
  # WP + EVA on the header-as-TU. No ACSL on stubs.
  frama-c -wp -wp-rte -eva src/platform/cproof/wawona_cproof.c ${INC} 2>/tmp/frama.err || \
    emit frama-c "src/platform/cproof/wawona_cproof.c" 1 "wp-eva" \
      "$(tail -n 5 /tmp/frama.err | tr '\n' ' ')" \
      "frama-c -wp -eva src/platform/cproof/wawona_cproof.c"
else
  # Not in Ubuntu 24.04 apt. Record warning; do not fail the floor.
  python3 "$REPORT" emit --out "$OUT" --tool frama-c --file src/platform/cproof/wawona_cproof.h \
    --line 1 --rule missing-tool --severity warning \
    --failure "frama-c is not installed on this runner" \
    --fix "install frama-c (not in Ubuntu 24.04 apt) and run WP+EVA on wawona_cproof.c"
fi

for tool in klee cpa.sh; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    python3 "$REPORT" emit --out "$OUT" --tool "$tool" --file src/platform/cproof/wawona_cproof.h \
      --line 1 --rule missing-tool --severity warning \
      --failure "$tool is not installed on this runner" \
      --fix "install $tool and point it at wawona_cproof helpers"
  fi
done

if command -v valgrind >/dev/null 2>&1 && [[ -x verification-out/c/test_cproof ]]; then
  # Rebuild without ASan for Valgrind
  cc ${INC} -std=c11 verification/c/test_cproof.c -o verification-out/c/test_cproof_plain
  valgrind --error-exitcode=1 --leak-check=full verification-out/c/test_cproof_plain || \
    emit valgrind "verification/c/test_cproof.c" 1 "valgrind" \
      "Valgrind reported errors" "valgrind verification-out/c/test_cproof_plain"
else
  emit valgrind "verification/c/test_cproof.c" 1 "missing-tool" \
    "valgrind is not installed or harness missing" "apt install valgrind"
fi

# MSan: fail closed without instrumented libc
if command -v clang >/dev/null 2>&1; then
  if ! clang ${INC} -std=c11 -fsanitize=memory verification/c/test_cproof.c \
      -o verification-out/c/test_cproof_msan 2>/tmp/msan.err; then
    emit msan "verification/c/test_cproof.c" 1 "msan" \
      "MSan build failed (need instrumented libc): $(tr '\n' ' ' </tmp/msan.err | head -c 200)" \
      "clang -fsanitize=memory verification/c/test_cproof.c"
  else
    verification-out/c/test_cproof_msan || \
      emit msan "verification/c/test_cproof.c" 1 "msan" "MSan run failed" "verification-out/c/test_cproof_msan"
  fi
else
  emit msan "verification/c/test_cproof.c" 1 "missing-tool" "clang missing for MSan" "install clang"
fi

# CDSChecker on atomic helpers
if command -v cdschecker >/dev/null 2>&1 || command -v test-cdschecker >/dev/null 2>&1; then
  emit cdschecker "src/platform/cproof/wawona_cproof.h" 1 "manual" \
    "CDSChecker binary present; wire a harness on wawona_count_*" \
    "run CDSChecker on verification/c/cds_counters.c"
else
  # Ship a tiny model file and record missing tool
  cat > verification/c/cds_counters.c <<'EOF'
#include "wawona_cproof.h"
/* CDSChecker target: concurrent inc/dec on one counter. */
int user_main(int argc, char **argv) {
  (void)argc; (void)argv;
  atomic_int n = 0;
  wawona_count_inc(&n);
  wawona_count_dec(&n);
  return wawona_count_load(&n);
}
EOF
  emit cdschecker "verification/c/cds_counters.c" 1 "missing-tool" \
    "CDSChecker is not installed" "install CDSChecker and run it on verification/c/cds_counters.c"
fi

# TSan on iland presenter mutex (compile TU when headers allow; else record)
if [[ -f src/platform/android/iland_presenter_android.c ]]; then
  if clang ${INC} -std=c11 -fsanitize=thread -c \
      src/platform/android/iland_presenter_android.c \
      -o verification-out/c/iland_tsan.o 2>/tmp/tsan.err; then
    :
  else
    emit tsan "src/platform/android/iland_presenter_android.c" 1 "tsan-build" \
      "$(tr '\n' ' ' </tmp/tsan.err | head -c 300)" \
      "clang -fsanitize=thread -c iland_presenter_android.c"
  fi
fi

python3 "$REPORT" summarize "$OUT" --markdown "$(dirname "$OUT")/c.md" || fail=1
exit "$fail"

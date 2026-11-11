//! The lanes for Wawona's C helpers, the Swift contracts and the Android host.

use super::{ok, tail_on_failure, Lane};
use crate::util::*;
use anyhow::Result;

const INC: [&str; 6] = ["-I", "src/platform/cproof", "-I", "src/platform/macos", "-I", "src/platform/android"];
const HARNESS: &str = "verification/c/test_cproof.c";
const CPROOF: &str = "src/platform/cproof/wawona_cproof.c";

pub fn c(lane: Lane) -> Result<()> {
    let out = lane.dir().join("c");
    std::fs::create_dir_all(&out)?;
    let bin = |n: &str| out.join(n).display().to_string();
    let cc = |compiler: &str, flags: &[&str], srcs: &[&str], o: &str| {
        let mut c = cmd(compiler);
        c.args(INC).arg("-std=c11").args(flags).args(srcs).args(["-o", o]);
        c
    };

    let asan = bin("test_cproof");
    if let Some(t) =
        tail_on_failure(&mut cc("cc", &["-Wall", "-Werror", "-fsanitize=address,undefined"], &[HARNESS], &asan), 5)
    {
        lane.error(
            "c-asan",
            HARNESS,
            "asan",
            &format!("harness failed to build with ASan and UBSan: {t}"),
            "cc -fsanitize=address,undefined verification/c/test_cproof.c",
        );
    } else if !ok(&mut cmd(&asan)) {
        lane.error("c-asan", HARNESS, "asan", "C helper harness failed under ASan and UBSan", &asan);
    }

    let policy = "dependencies/tests/graphics-driver-policy.c";
    let settings = "src/platform/macos/WWNSettings.c";
    if root().join(policy).is_file() && root().join(settings).is_file() {
        let o = bin("graphics-driver-policy");
        if let Some(t) = tail_on_failure(&mut cc("cc", &["-DWWN_SETTINGS_TEST_HARNESS"], &[policy, settings], &o), 5) {
            lane.error("graphics-driver", policy, "build", &t, &format!("cc {policy} {settings}"));
        } else if !ok(&mut cmd(&o)) {
            lane.error("graphics-driver", policy, "assert", "graphics driver policy test failed", &o);
        }
    }

    // Warnings as errors on the pure helper translation unit only; the JNI and
    // platform C build under the product compilers.
    if have("clang-tidy") {
        let checks = "-*,cert-*,bugprone-*,-bugprone-easily-swappable-parameters";
        let mut t = cmd("clang-tidy");
        t.args([CPROOF, &format!("--checks={checks}"), "--warnings-as-errors=cert-*,bugprone-*", "--"])
            .args(INC)
            .arg("-std=c11");
        if let Some(tail) = tail_on_failure(&mut t, 5) {
            lane.error("clang-tidy", CPROOF, "cert-bugprone", &tail, &format!("clang-tidy {CPROOF} --checks={checks}"));
        }
    } else {
        lane.error(
            "clang-tidy",
            "xtask/src/prove/native.rs",
            "missing-tool",
            "clang-tidy is not installed",
            "apt install clang-tidy",
        );
    }

    if have("scan-build") {
        let mut s = cmd("scan-build");
        s.args(["--status-bugs", "cc"]).args(INC).args(["-c", CPROOF, "-o"]).arg(out.join("wawona_cproof.o"));
        if !ok(&mut s) {
            lane.error(
                "scan-build",
                CPROOF,
                "scan-build",
                "scan-build reported a bug",
                &format!("scan-build cc -c {CPROOF}"),
            );
        }
    } else {
        lane.error(
            "scan-build",
            "xtask/src/prove/native.rs",
            "missing-tool",
            "scan-build is not installed",
            "apt install clang-tools",
        );
    }

    if have("cbmc") {
        if !ok(cmd("cbmc").arg(HARNESS).args(INC).args(["--unwind", "4"])) {
            lane.error(
                "cbmc",
                HARNESS,
                "cbmc",
                "CBMC failed the helper harness",
                "cbmc verification/c/test_cproof.c --unwind 4",
            );
        }
    } else {
        lane.error(
            "cbmc",
            "src/platform/cproof/wawona_cproof.h",
            "missing-tool",
            "cbmc is not installed",
            "apt install cbmc",
        );
    }

    if have("frama-c") {
        if let Some(t) = tail_on_failure(cmd("frama-c").args(["-wp", "-wp-rte", "-eva", CPROOF]).args(INC), 5) {
            lane.error("frama-c", CPROOF, "wp-eva", &t, &format!("frama-c -wp -eva {CPROOF}"));
        }
    } else {
        // Not in Ubuntu 24.04 apt.
        lane.warn(
            "frama-c",
            "src/platform/cproof/wawona_cproof.h",
            "missing-tool",
            "frama-c is not installed on this runner",
            "install frama-c and run WP+EVA on wawona_cproof.c",
        );
    }
    for tool in ["klee", "cpa.sh"] {
        if !have(tool) {
            lane.warn(
                tool,
                "src/platform/cproof/wawona_cproof.h",
                "missing-tool",
                &format!("{tool} is not installed on this runner"),
                &format!("install {tool} and point it at wawona_cproof helpers"),
            );
        }
    }

    // Valgrind needs a build without ASan.
    let plain = bin("test_cproof_plain");
    if have("valgrind") && ok(&mut cc("cc", &[], &[HARNESS], &plain)) {
        if !ok(cmd("valgrind").args(["--error-exitcode=1", "--leak-check=full", &plain])) {
            lane.error("valgrind", HARNESS, "valgrind", "Valgrind reported errors", &format!("valgrind {plain}"));
        }
    } else {
        lane.error(
            "valgrind",
            HARNESS,
            "missing-tool",
            "valgrind is not installed or the harness did not build",
            "apt install valgrind",
        );
    }

    // MSan fails closed without an instrumented libc.
    if have("clang") {
        let msan = bin("test_cproof_msan");
        if let Some(t) = tail_on_failure(&mut cc("clang", &["-fsanitize=memory"], &[HARNESS], &msan), 3) {
            lane.error(
                "msan",
                HARNESS,
                "msan",
                &format!("MSan build failed (needs an instrumented libc): {t}"),
                "clang -fsanitize=memory verification/c/test_cproof.c",
            );
        } else if !ok(&mut cmd(&msan)) {
            lane.error("msan", HARNESS, "msan", "MSan run failed", &msan);
        }
    } else {
        lane.error("msan", HARNESS, "missing-tool", "clang missing for MSan", "install clang");
    }

    let counters = "verification/c/cds_counters.c";
    match ["cdschecker", "test-cdschecker"].into_iter().find(|t| have(t)) {
        Some(cds) => {
            if !ok(cmd(cds).args(INC).arg(counters)) {
                lane.error(
                    "cdschecker",
                    counters,
                    "cdschecker",
                    "CDSChecker rejected the wawona_count_* harness",
                    &format!("{cds} {counters}"),
                );
            }
        }
        None => lane.warn(
            "cdschecker",
            counters,
            "missing-tool",
            "CDSChecker is not installed",
            "install CDSChecker and run it on verification/c/cds_counters.c",
        ),
    }

    let presenter = "src/platform/android/iland_presenter_android.c";
    if root().join(presenter).is_file() {
        let mut t = cmd("clang");
        t.args(INC).args(["-std=c11", "-fsanitize=thread", "-c", presenter, "-o"]).arg(out.join("iland_tsan.o"));
        if let Some(tail) = tail_on_failure(&mut t, 5) {
            lane.error("tsan", presenter, "tsan-build", &tail, &format!("clang -fsanitize=thread -c {presenter}"));
        }
    }
    lane.finish()
}

pub fn swift(lane: Lane) -> Result<()> {
    // The vector package keeps WawonaUI (which needs WawonaApple) out of the link.
    let pkg = root().join("verification/swift-ssh-vector");
    let test = "Tests/WawonaUIContractsTests/SSHHostVectorTests.swift";
    if !ok(cmd("swift").args(["test", "--filter", "SSHHostVectorTests"]).current_dir(&pkg)) {
        lane.error(
            "swift-test",
            test,
            "swift-testing",
            "Swift SSH host differential failed",
            "cd verification/swift-ssh-vector && swift test --filter SSHHostVectorTests",
        );
    }
    let strict = ["build", "--target", "WawonaUIContracts", "-Xswiftc", "-strict-concurrency=complete"];
    if !ok(cmd("swift").args(strict).current_dir(&pkg)) {
        lane.error("swift-concurrency", "Sources/WawonaUIContracts", "strict-concurrency", "WawonaUIContracts failed strict concurrency", "cd verification/swift-ssh-vector && swift build --target WawonaUIContracts -Xswiftc -strict-concurrency=complete");
    }
    for san in ["address", "undefined", "thread"] {
        if !ok(cmd("swift")
            .args(["test", &format!("--sanitize={san}"), "--filter", "SSHHostVectorTests"])
            .current_dir(&pkg))
        {
            lane.error(
                &format!("swift-{san}"),
                test,
                "sanitize",
                &format!("swift test --sanitize={san} failed"),
                &format!("cd verification/swift-ssh-vector && swift test --sanitize={san} --filter SSHHostVectorTests"),
            );
        }
    }
    lane.finish()
}

pub fn kotlin(lane: Lane) -> Result<()> {
    // The floor is JVM, detekt and lint; WAWONA_VERIFICATION_KOTLIN skips the NDK build.
    let tasks = [
        ":Wawona:testDebugUnitTest",
        ":Wawona:detekt",
        ":Wawona:lintDebug",
        "--init-script",
        "android/detekt.init.gradle",
    ];
    let gradle = || {
        let mut c = cmd(root().join("gradlew"));
        c.args(tasks).env("WAWONA_VERIFICATION_KOTLIN", env_or("WAWONA_VERIFICATION_KOTLIN", "1"));
        c
    };
    if !ok(gradle().arg("--offline")) && !ok(&mut gradle()) {
        lane.error(
            "gradle",
            "android/app/src/test/java/com/aspauldingcode/wawona/MachineInputSanitizerTest.kt",
            "kotest-detekt-lint",
            "unit test, detekt, or lint failed",
            &format!("./gradlew {}", tasks.join(" ")),
        );
    }
    lane.warn(
        "spotbugs",
        "android/app/build.gradle.kts",
        "missing-tool",
        "SpotBugs is not wired on AGP 9 (BaseExtension removed).",
        "restore SpotBugs when an AGP-compatible plugin supports ApplicationExtension",
    );

    let harness = "verification/kotlin/SanitizeHarness.java";
    let classes = lane.dir().join("kotlin");
    std::fs::create_dir_all(&classes)?;
    if !ok(cmd("javac").arg("-d").arg(&classes).arg(harness)) {
        lane.error(
            "jbmc",
            harness,
            "javac",
            "failed to compile the JVM sanitizer harness",
            &format!("javac {harness}"),
        );
        return lane.finish();
    }
    if have("jbmc") {
        let mut j = cmd("jbmc");
        j.arg("--classpath").arg(&classes).args([
            "SanitizeHarness",
            "--unwind",
            "8",
            "--max-nondet-string-length",
            "8",
        ]);
        if !ok(&mut j) {
            lane.error(
                "jbmc",
                harness,
                "jbmc",
                "JBMC failed the bounded sanitizer harness",
                "jbmc --classpath verification-out/kotlin SanitizeHarness --unwind 8",
            );
        }
    } else {
        lane.warn(
            "jbmc",
            harness,
            "missing-tool",
            "JBMC is not installed on this runner.",
            "install CBMC's jbmc and run it on SanitizeHarness",
        );
    }
    let jpf =
        std::env::var("JPF_HOME").map(|h| format!("{h}/bin/jpf")).ok().or_else(|| have("jpf").then(|| "jpf".into()));
    match jpf {
        Some(jpf) => {
            if let Some(t) =
                tail_on_failure(cmd(&jpf).arg("+cg.max_depth=20").arg(classes.join("SanitizeHarness.class")), 3)
            {
                lane.error("jpf", harness, "jpf", &t, "jpf +cg.max_depth=20 SanitizeHarness");
            }
        }
        None => lane.warn(
            "jpf",
            harness,
            "missing-tool",
            "Java PathFinder is not installed on this runner.",
            "install JPF and depth-cap SanitizeHarness",
        ),
    }
    lane.finish()
}

//! Grades a WLCS run: GoogleTest XML into CI JSON and Markdown reports.

use std::path::{Path, PathBuf};

use anyhow::Result;
use serde_json::json;

#[derive(clap::Args)]
pub struct Args {
    #[arg(long)]
    xml: PathBuf,
    #[arg(long)]
    json: PathBuf,
    #[arg(long)]
    markdown: PathBuf,
    #[arg(long)]
    log: Option<PathBuf>,
    #[arg(long)]
    wlcs_exit_code: i32,
    #[arg(long, default_value_t = 100.0)]
    minimum_pass_rate: f64,
    #[arg(long, default_value_t = 0)]
    maximum_failures: usize,
}

/// `timeout` exits 124, or 137 after `--kill-after`.
const TIMEOUT_EXIT_CODES: [i32; 2] = [124, 137];

struct Case {
    suite: String,
    name: String,
    status: &'static str,
    duration: f64,
    detail: String,
}

/// The last test GoogleTest started and never reported: the one that hung.
fn unfinished_test(log: Option<&Path>) -> Option<String> {
    let text = std::fs::read(log?).ok()?;
    let mut running = None;
    for line in String::from_utf8_lossy(&text).lines() {
        if let Some(name) = line.strip_prefix("[ RUN      ] ") {
            running = Some(name.trim().to_string());
        } else if ["[       OK ] ", "[  FAILED  ] ", "[  SKIPPED ] "].iter().any(|p| line.starts_with(p)) {
            running = None;
        }
    }
    running
}

fn grade_for(rate: f64) -> &'static str {
    [(99.0, "A"), (95.0, "B"), (90.0, "C"), (80.0, "D")]
        .into_iter()
        .find(|(min, _)| rate >= *min)
        .map_or("F", |(_, g)| g)
}

fn parse(xml: &Path) -> std::result::Result<Vec<Case>, String> {
    let text = std::fs::read_to_string(xml).map_err(|_| "WLCS did not produce GoogleTest XML".to_string())?;
    let doc = roxmltree::Document::parse(&text).map_err(|e| format!("invalid WLCS XML: {e}"))?;
    let mut cases = Vec::new();
    for case in doc.descendants().filter(|n| n.has_tag_name("testcase")) {
        let child = |tag| case.children().find(|n| n.has_tag_name(tag));
        let failure = child("failure").or_else(|| child("error"));
        let status = if failure.is_some() {
            "failed"
        } else if child("skipped").is_some() || case.attribute("status") == Some("notrun") {
            "skipped"
        } else {
            "passed"
        };
        let time = case.attribute("time").filter(|t| !t.is_empty()).unwrap_or("0");
        cases.push(Case {
            suite: case.attribute("classname").unwrap_or_default().to_string(),
            name: case.attribute("name").unwrap_or_default().to_string(),
            status,
            duration: time.parse().map_err(|e| format!("invalid WLCS XML: {e}"))?,
            detail: failure.and_then(|n| n.text()).unwrap_or_default().trim().to_string(),
        });
    }
    Ok(cases)
}

pub fn grade(a: Args) -> Result<()> {
    let (cases, mut infrastructure_error) = match parse(&a.xml) {
        Ok(c) => (c, None),
        Err(e) => (Vec::new(), Some(e)),
    };
    let unfinished = unfinished_test(a.log.as_deref());
    if TIMEOUT_EXIT_CODES.contains(&a.wlcs_exit_code) {
        let hung = unfinished.as_ref().map(|t| format!(" (hung in `{t}`)")).unwrap_or_default();
        infrastructure_error = Some(format!("WLCS exceeded the run timeout{hung}"));
    }
    let count = |s| cases.iter().filter(|c| c.status == s).count();
    let (passed, failed, skipped) = (count("passed"), count("failed"), count("skipped"));
    let scored = passed + failed;
    let pass_rate = if scored > 0 { 100.0 * passed as f64 / scored as f64 } else { 0.0 };
    // GoogleTest exits 1 on ordinary test failures, which the thresholds
    // judge; any other non-zero status is an infrastructure failure.
    let conforms = infrastructure_error.is_none()
        && scored > 0
        && pass_rate >= a.minimum_pass_rate
        && failed <= a.maximum_failures
        && matches!(a.wlcs_exit_code, 0 | 1);
    let grade = grade_for(pass_rate);
    let counts =
        json!({ "total": cases.len(), "scored": scored, "passed": passed, "failed": failed, "skipped": skipped });
    let tests: Vec<_> = cases
        .iter()
        .map(|c| {
            json!({ "suite": c.suite, "name": c.name, "status": c.status,
                    "duration_seconds": c.duration, "detail": c.detail })
        })
        .collect();
    let rounded = (pass_rate * 1000.0).round() / 1000.0;
    let report = json!({
        "schema_version": 1,
        "suite": "WLCS",
        "conforms": conforms,
        "grade": grade,
        "pass_rate": rounded,
        "counts": counts,
        "policy": { "minimum_pass_rate": a.minimum_pass_rate, "maximum_failures": a.maximum_failures },
        "wlcs_exit_code": a.wlcs_exit_code,
        "infrastructure_error": infrastructure_error,
        "unfinished_test": unfinished,
        "tests": tests,
    });
    if let Some(dir) = a.json.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(&a.json, serde_json::to_string_pretty(&report)? + "\n")?;

    let mut md = vec![
        "# Wawona Wayland conformance".to_string(),
        String::new(),
        format!("**Verdict:** {}  ", if conforms { "CONFORMANT" } else { "NOT CONFORMANT" }),
        format!("**Grade:** {grade} ({pass_rate:.2}%)"),
        String::new(),
        "| Passed | Failed | Skipped | Scored |".into(),
        "|---:|---:|---:|---:|".into(),
        format!("| {passed} | {failed} | {skipped} | {scored} |"),
    ];
    if let Some(e) = &infrastructure_error {
        md.extend([String::new(), format!("**Infrastructure error:** {e}")]);
    }
    if failed > 0 {
        md.extend([String::new(), "## Failures".into()]);
        md.extend(cases.iter().filter(|c| c.status == "failed").map(|c| format!("- `{}.{}`", c.suite, c.name)));
    }
    std::fs::write(&a.markdown, md.join("\n") + "\n")?;
    println!("{}", json!({ "conforms": conforms, "grade": grade, "pass_rate": rounded, "counts": counts }));
    if !conforms {
        std::process::exit(1);
    }
    Ok(())
}

//! `cargo xtask report`: one record per verification finding (tool, file,
//! line, rule, failure, fix, severity), appended as NDJSON by each tool
//! wrapper, then summarized into Markdown and GitHub annotations.

use crate::util::*;
use anyhow::{bail, Result};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::io::Write;
use std::path::PathBuf;

#[derive(clap::Subcommand)]
pub enum Cmd {
    /// Append one finding.
    Emit {
        #[arg(long)]
        out: PathBuf,
        #[arg(long)]
        tool: String,
        #[arg(long)]
        file: String,
        #[arg(long, default_value_t = 1)]
        line: u64,
        #[arg(long)]
        rule: String,
        #[arg(long)]
        failure: String,
        #[arg(long)]
        fix: String,
        #[arg(long, default_value = "error")]
        severity: String,
    },
    /// Summarize NDJSON files (or directories of them); fails on any error finding.
    Summarize {
        inputs: Vec<PathBuf>,
        #[arg(long)]
        markdown: PathBuf,
    },
}

pub fn main(c: Cmd) -> Result<()> {
    match c {
        Cmd::Emit { out, tool, file, line, rule, failure, fix, severity } => append(
            &out,
            &json!({"tool": tool, "file": file, "line": line, "rule": rule, "failure": failure, "fix": fix, "severity": severity}),
        ),
        Cmd::Summarize { inputs, markdown } => summarize(&inputs, &markdown),
    }
}

/// Appends one finding row to `out`.
pub fn append(out: &std::path::Path, row: &Value) -> Result<()> {
    if let Some(d) = out.parent() {
        std::fs::create_dir_all(d)?;
    }
    writeln!(std::fs::OpenOptions::new().create(true).append(true).open(out)?, "{row}")?;
    Ok(())
}

fn rows(inputs: &[PathBuf]) -> Result<Vec<Value>> {
    let mut files = Vec::new();
    for p in inputs {
        if p.is_dir() {
            files.extend(super::files_under(p, "", ".ndjson"));
        } else if p.exists() {
            files.push(p.clone());
        }
    }
    let mut rows = Vec::new();
    for f in files {
        for l in read(&f)?.lines().map(str::trim).filter(|l| !l.is_empty()) {
            let mut row: Value = serde_json::from_str(l).unwrap_or_else(|_| {
                json!({"tool": "verification-report", "file": f.display().to_string(), "line": 1, "rule": "ndjson",
                       "failure": "row was not JSON", "fix": "emit one JSON object per line", "severity": "error"})
            });
            let o = row.as_object_mut().unwrap();
            o.entry("severity").or_insert("error".into());
            o.entry("line").or_insert(1.into());
            rows.push(row);
        }
    }
    Ok(rows)
}

fn field(r: &Value, k: &str) -> String {
    match &r[k] {
        Value::String(s) => s.clone(),
        Value::Null => String::new(),
        v => v.to_string(),
    }
}

pub fn summarize(inputs: &[PathBuf], md: &std::path::Path) -> Result<()> {
    let rows = rows(inputs)?;
    let mut text = String::from("# Verification report\n\n");
    if rows.is_empty() {
        text.push_str("No findings.\n");
    } else {
        let mut by_file: BTreeMap<String, Vec<&Value>> = BTreeMap::new();
        for r in &rows {
            by_file.entry(field(r, "file")).or_default().push(r);
        }
        for (name, rs) in by_file {
            text.push_str(&format!("## `{name}`\n\n"));
            for r in rs {
                text.push_str(&format!(
                    "- **{}** {name}:{} `{}` {}\n  - fix: {}\n",
                    field(r, "tool"),
                    field(r, "line"),
                    field(r, "rule"),
                    field(r, "failure"),
                    field(r, "fix")
                ));
            }
            text.push('\n');
        }
    }
    write(md, &text)?;
    if let Ok(s) = std::env::var("GITHUB_STEP_SUMMARY") {
        std::fs::OpenOptions::new().create(true).append(true).open(s)?.write_all(text.as_bytes())?;
    }
    let errors: Vec<&Value> = rows.iter().filter(|r| field(r, "severity") == "error").collect();
    for r in &errors {
        println!(
            "::error file={},line={}::{} {}: {} fix: {}",
            field(r, "file"),
            field(r, "line"),
            field(r, "tool"),
            field(r, "rule"),
            field(r, "failure").replace('\n', " "),
            field(r, "fix").replace('\n', " ")
        );
    }
    println!("verification findings: {} errors: {}", rows.len(), errors.len());
    if !errors.is_empty() {
        bail!("{} error findings", errors.len());
    }
    Ok(())
}

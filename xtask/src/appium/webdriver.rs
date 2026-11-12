//! A blocking W3C WebDriver client with the Appium extensions the suite uses.
//! https://www.w3.org/TR/webdriver2/ and
//! https://appium.io/docs/en/latest/reference/api/

use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use base64::Engine;
use serde_json::{json, Value};

/// The W3C web element reference key.
const ELEMENT: &str = "element-6066-11e4-a52e-4f735466cecf";

pub struct Driver {
    base: String,
    pub timeout: Duration,
}

#[derive(Clone)]
pub struct Element(String);

/// A WebDriver error response, by its `error` code.
#[derive(Debug)]
pub struct WdError {
    pub code: String,
    pub message: String,
}

impl std::fmt::Display for WdError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.code, self.message.chars().take(400).collect::<String>())
    }
}

impl std::error::Error for WdError {}

fn call(method: &str, url: &str, body: Option<&Value>) -> Result<Value> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .http_status_as_error(false)
        .timeout_global(Some(Duration::from_secs(600)))
        .build()
        .into();
    let mut res = match (method, body) {
        ("GET", _) => agent.get(url).call(),
        ("DELETE", _) => agent.delete(url).call(),
        (_, b) => agent
            .post(url)
            .header("Content-Type", "application/json")
            .send(serde_json::to_vec(&b.cloned().unwrap_or(json!({})))?),
    }
    .with_context(|| format!("{method} {url}"))?;
    let status = res.status();
    let text = res.body_mut().with_config().limit(256 << 20).read_to_string()?;
    let v: Value = if text.is_empty() { json!({}) } else { serde_json::from_str(&text).context("WebDriver JSON")? };
    if !status.is_success() {
        let e = &v["value"];
        return Err(WdError {
            code: e["error"].as_str().unwrap_or("unknown error").into(),
            message: e["message"].as_str().unwrap_or(&text).into(),
        }
        .into());
    }
    Ok(v["value"].clone())
}

/// True when `e` is a WebDriver error with one of `codes`.
pub fn is(e: &anyhow::Error, codes: &[&str]) -> bool {
    e.downcast_ref::<WdError>().is_some_and(|w| codes.contains(&w.code.as_str()))
}

impl Driver {
    pub fn new(server: &str, capabilities: Value) -> Result<Self> {
        let server = server.trim_end_matches('/');
        let v = call(
            "POST",
            &format!("{server}/session"),
            Some(&json!({ "capabilities": { "alwaysMatch": capabilities } })),
        )?;
        let id = v["sessionId"].as_str().context("new session: no sessionId")?;
        Ok(Self { base: format!("{server}/session/{id}"), timeout: Duration::from_secs(20) })
    }

    fn get(&self, path: &str) -> Result<Value> {
        call("GET", &format!("{}{path}", self.base), None)
    }

    fn post(&self, path: &str, body: Value) -> Result<Value> {
        call("POST", &format!("{}{path}", self.base), Some(&body))
    }

    pub fn quit(&self) {
        let _ = call("DELETE", &self.base, None);
    }

    fn element(v: &Value) -> Result<Element> {
        Ok(Element(v[ELEMENT].as_str().context("element reference")?.into()))
    }

    /// Strategies: `accessibility id`, `name`, `xpath`.
    pub fn find(&self, using: &str, value: &str) -> Result<Element> {
        Self::element(&self.post("/element", json!({ "using": using, "value": value }))?)
    }

    pub fn find_all(&self, using: &str, value: &str) -> Result<Vec<Element>> {
        let v = self.post("/elements", json!({ "using": using, "value": value }))?;
        v.as_array().into_iter().flatten().map(Self::element).collect()
    }

    pub fn active(&self) -> Result<Element> {
        Self::element(&self.get("/element/active")?)
    }

    pub fn click(&self, e: &Element) -> Result<()> {
        self.post(&format!("/element/{}/click", e.0), json!({})).map(drop)
    }

    pub fn send_keys(&self, e: &Element, text: &str) -> Result<()> {
        self.post(&format!("/element/{}/value", e.0), json!({ "text": text })).map(drop)
    }

    pub fn clear(&self, e: &Element) -> Result<()> {
        self.post(&format!("/element/{}/clear", e.0), json!({})).map(drop)
    }

    pub fn displayed(&self, e: &Element) -> Result<bool> {
        Ok(self.get(&format!("/element/{}/displayed", e.0))?.as_bool().unwrap_or(false))
    }

    /// The element's rectangle: x, y, width, height.
    pub fn rect(&self, e: &Element) -> Result<[i64; 4]> {
        let r = self.get(&format!("/element/{}/rect", e.0))?;
        let n = |k: &str| r[k].as_f64().unwrap_or(0.0) as i64;
        Ok([n("x"), n("y"), n("width"), n("height")])
    }

    fn png(v: Value) -> Result<Vec<u8>> {
        let b64 = v.as_str().context("screenshot")?;
        Ok(base64::engine::general_purpose::STANDARD.decode(b64.replace(['\n', '\r'], ""))?)
    }

    pub fn screenshot(&self) -> Result<Vec<u8>> {
        Self::png(self.get("/screenshot")?)
    }

    pub fn element_screenshot(&self, e: &Element) -> Result<Vec<u8>> {
        Self::png(self.get(&format!("/element/{}/screenshot", e.0))?)
    }

    /// An Appium `mobile:` / `macos:` extension command.
    pub fn execute(&self, script: &str, args: Value) -> Result<Value> {
        self.post("/execute/sync", json!({ "script": script, "args": [args] }))
    }

    pub fn set_orientation(&self, o: &str) -> Result<()> {
        self.post("/orientation", json!({ "orientation": o })).map(drop)
    }

    pub fn hide_keyboard(&self) -> Result<()> {
        self.post("/appium/device/hide_keyboard", json!({})).map(drop)
    }

    /// The first element matching `id` that is displayed, within the timeout.
    pub fn wait_visible(&self, id: &str, timeout: Option<Duration>) -> Result<Element> {
        let end = Instant::now() + timeout.unwrap_or(self.timeout);
        loop {
            match self.find("accessibility id", id) {
                Ok(e) if self.displayed(&e).unwrap_or(false) => return Ok(e),
                Err(e) if is(&e, &["invalid session id"]) => return Err(e),
                _ => {}
            }
            if Instant::now() >= end {
                bail!("{id} not visible within {:?}", timeout.unwrap_or(self.timeout));
            }
            std::thread::sleep(Duration::from_millis(500));
        }
    }

    /// Whether `id` resolves. A lost session is an error; Mac2 reports a
    /// missing accessibility node as an assorted proxy error, which is absence.
    pub fn exists(&self, id: &str) -> Result<bool> {
        match self.find("accessibility id", id) {
            Ok(_) => Ok(true),
            Err(e) if is(&e, &["invalid session id"]) => Err(e),
            Err(_) => Ok(false),
        }
    }
}

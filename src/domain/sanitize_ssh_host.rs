//! SSH host sanitize. One implementation for product code, helpers-check, and Kani.

/// Drop accidental scheme, path, query, and `host:port` so host and port stay split.
pub fn sanitize_ssh_host(raw: &str) -> String {
    let mut value = raw.trim().to_string();
    if value.is_empty() {
        return String::new();
    }

    if let Some(idx) = value.find("://") {
        value = value[idx + 3..].to_string();
    }
    if let Some(idx) = value.find('/') {
        value.truncate(idx);
    }
    if let Some(idx) = value.find('?') {
        value.truncate(idx);
    }
    if let Some(idx) = value.find('#') {
        value.truncate(idx);
    }

    value = value
        .chars()
        .filter(|c| !c.is_whitespace() && !"\"'`$;&|<>\\".contains(*c))
        .collect();

    if value.starts_with('[') {
        if let Some(closing) = value.find(']') {
            let after = closing + 1;
            if after < value.len() && value.as_bytes()[after] == b':' {
                let suffix = &value[after + 1..];
                if !suffix.is_empty() && suffix.chars().all(|c| c.is_ascii_digit()) {
                    value.truncate(closing + 1);
                }
            }
        }
    } else if let Some(colon) = value.rfind(':') {
        let host_part = &value[..colon];
        let port_part = &value[colon + 1..];
        if !host_part.contains(':')
            && !port_part.is_empty()
            && port_part.chars().all(|c| c.is_ascii_digit())
        {
            value.truncate(colon);
        }
    }

    value
}

pub fn normalize_ssh_port(raw: &str, fallback: i32) -> i32 {
    let trimmed = raw.trim();
    match trimmed.parse::<i32>() {
        Ok(parsed) if (1..=65535).contains(&parsed) => parsed,
        _ => fallback,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_vector_matches_file() {
        let raw = include_str!("../../verification/ssh_host_vector.tsv");
        for line in raw.lines() {
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let (input, expected) = line.split_once('\t').unwrap();
            assert_eq!(sanitize_ssh_host(input), expected, "input {input}");
        }
    }

    #[test]
    fn sanitize_strips_scheme_and_port() {
        assert_eq!(
            sanitize_ssh_host(" ssh://host.example:2222/path "),
            "host.example"
        );
        assert_eq!(sanitize_ssh_host("[::1]:22"), "[::1]");
        assert_eq!(sanitize_ssh_host("10.0.0.1"), "10.0.0.1");
    }

    #[test]
    fn normalize_port_bounds() {
        assert_eq!(normalize_ssh_port("22", 1), 22);
        assert_eq!(normalize_ssh_port("0", 22), 22);
        assert_eq!(normalize_ssh_port("65536", 22), 22);
        assert_eq!(normalize_ssh_port("abc", 22), 22);
    }
}

#[cfg(all(test, not(loom)))]
mod sanitize_proptest {
    use super::sanitize_ssh_host;
    use proptest::prelude::*;

    proptest! {
        #[test]
        fn sanitize_drops_shell_metacharacters(raw in "[ -~]{0,24}") {
            let out = sanitize_ssh_host(&raw);
            for ch in out.chars() {
                prop_assert!(!ch.is_whitespace());
                prop_assert!(!"\"'`$;&|<>\\".contains(ch));
            }
        }
    }
}

#[cfg(kani)]
#[kani::proof]
fn sanitize_ascii_has_no_shell_metacharacters() {
    let mut bytes = [0u8; 6];
    for slot in &mut bytes {
        let b: u8 = kani::any();
        kani::assume((32..127).contains(&b));
        *slot = b;
    }
    let raw = std::str::from_utf8(&bytes).unwrap();
    let out = sanitize_ssh_host(raw);
    for ch in out.chars() {
        assert!(!ch.is_whitespace());
        assert!(!"\"'`$;&|<>\\".contains(ch));
    }
}

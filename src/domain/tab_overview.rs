//! Tab Overview search / filter policy shared by Apple, Android, and Linux hosts.
//!
//! Hosts own preview cards and Focus. This module only decides which titles
//! match a query (Safari-style tab search).

/// Case-insensitive substring match. Empty / whitespace query matches all.
pub fn title_matches(query: &str, title: &str) -> bool {
    let q = query.trim();
    if q.is_empty() {
        return true;
    }
    title
        .to_lowercase()
        .contains(&q.to_lowercase())
}

/// Indices into `titles` that match `query`, in original order.
pub fn filter_indices(query: &str, titles: &[impl AsRef<str>]) -> Vec<usize> {
    titles
        .iter()
        .enumerate()
        .filter(|(_, t)| title_matches(query, t.as_ref()))
        .map(|(i, _)| i)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_query_keeps_all() {
        let titles = ["Weston", "Niri", "Foot"];
        assert_eq!(filter_indices("", &titles), vec![0, 1, 2]);
        assert_eq!(filter_indices("   ", &titles), vec![0, 1, 2]);
    }

    #[test]
    fn substring_is_case_insensitive() {
        let titles = ["Weston Terminal", "niri", "Foot"];
        assert_eq!(filter_indices("WEST", &titles), vec![0]);
        assert_eq!(filter_indices("ni", &titles), vec![1]);
    }
}

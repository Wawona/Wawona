import Foundation
import WawonaModel

public enum MachineFuzzySearch {
  public static func fzfScore(pattern: String, candidate: String) -> Int? {
    if pattern.isEmpty { return 0 }
    let p = Array(pattern.lowercased())
    let c = Array(candidate.lowercased())
    if p.count > c.count { return nil }

    let boundaryChars = CharacterSet(charactersIn: " _-/.:")
    var score = 0
    var pi = 0
    var ci = 0
    var lastMatch = -1

    while pi < p.count, ci < c.count {
      if p[pi] == c[ci] {
        score += 8
        if lastMatch >= 0 {
          let gap = ci - lastMatch - 1
          if gap == 0 {
            score += 14
          } else {
            score -= min(gap, 10)
          }
        }
        if ci == 0 {
          score += 10
        } else {
          let prev = String(c[ci - 1]).unicodeScalars
          if let scalar = prev.first, boundaryChars.contains(scalar) {
            score += 9
          }
        }
        lastMatch = ci
        pi += 1
      }
      ci += 1
    }
    return pi == p.count ? score : nil
  }

  public static func filter(
    profiles: [MachineProfile],
    query: String,
    searchableText: (MachineProfile) -> String
  ) -> [MachineProfile] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return profiles }

    let terms = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    let scored: [(MachineProfile, Int)] = profiles.compactMap { profile in
      let haystack = searchableText(profile)
      var total = 0
      for term in terms {
        guard let termScore = fzfScore(pattern: term, candidate: haystack) else {
          return nil
        }
        total += termScore
      }
      return (profile, total)
    }

    return scored
      .sorted {
        if $0.1 == $1.1 {
          return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
        }
        return $0.1 > $1.1
      }
      .map(\.0)
  }
}

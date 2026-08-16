# No em dashes (org-wide)

**Hard forbid** Unicode em dash `—` (U+2014), `&mdash;`, `&#8212;`, and en dash
`–` (U+2013) used between words. Applies to public docs, product UI strings,
comments, and agent rules.

## Use instead

Period, comma, colon, or parentheses. Numeric ranges use a hyphen: `5-15 GB`.

```text
Bad:  Native on macOS — no VM.
Good: Native on macOS. No VM.

Bad:  Fastlane — lanes in fastlane/
Good: Fastlane: lanes in fastlane/
```

The Bad lines above are the only place the glyph may appear in rules: so agents
can match it. Never put it in shippable copy.

Site voice: `wawona.io` `.cursor/rules/wawona-io-voice.mdc`. Cursor rule:
`wawona-no-em-dash.mdc` (alwaysApply).

---
name: wawona-write
description: Loop for writing Wawona software on prior knowledge. Use when editing code, Nix, UI, packaging, or ports in Wawona or wwn-* repos. Requires wwn-mcp RAG, matching skills/rules, and a capture step if something new was learned.
---

# Write software (improve on prior)

Every Wawona change must make the documented knowledge **more true**, not
re-open a closed incident or invert a gate.

## Loop

1. **RAG.** Skill `wawona-rag`. `where_to_edit` + `get_capability` before edits.
2. **Skill/rule.** Read `wawona-priors` row for the topic. Open that rule/skill.
3. **Improve.** Cite what this change supersedes (issue, incident, rule clause).
   If the prior already forbids it, stop.
4. **Prove.** Link/eval/package failures: local `nix build` of the failing cell
   (`wawona-local-before-ci`). UI: agent-device (`wawona-test-control`).
5. **Capture.** If you learned a durable fact, skill `wawona-learn` + reindex RAG.

## Improve means

- Fix a hole the prior documented
- Narrow a `planned` gate toward `available` without lying
- Delete a rejected path (stubs, wrong winsys, Mode B in store)
- Record a new hard reject so the next agent does not repeat it

## Not improve

- Re-host a Wayland client onto KMS because Wayland-EGL is unfinished
- Ship Mode B/JIT/IOMFB in store IPA
- Invert the repo DAG
- "Solve" a red target by dropping Weston/Niri
- Take Over / LLDB `watchdogd` without Path B ACK
- Leave the new fact in chat only

Voice: `wawona-caveman`. Product map: `wawona-product-map`.

# Mission-critical assurance

Canonical policy: `Wawona/docs/mission-critical-assurance.md`.

AI-authored changes have the same review, proof, test, security, and provenance
requirements as human changes. Model confidence is not evidence.

Use risk tiers. VM memory, MMU, CPU, virtio, privilege, watchdog, and display
ownership changes are Tier 3. They require named obligations tied to production
Rust, bounded proof, an unbounded model when tractable, negative tests, and an
explicit statement of what remains unproved.

Do not introduce Bend-2-generated C product logic. It violates Rust-first and
creates a second semantics that Kani, Verus, and Miri do not jointly cover.

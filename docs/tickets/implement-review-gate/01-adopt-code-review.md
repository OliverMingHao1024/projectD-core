# Adopt cross-agent code-review

## What to deliver

A projectD-maintained `code-review` CanonicalSkill that reviews either an
uncommitted working tree or a fixed-point diff along separate Standards and Spec
axes. It must remain usable when no issue tracker, specification, or sub-agent
runtime is available.

## Acceptance criteria

- [ ] The Skill is read-only and never modifies reviewed source.
- [ ] Working-tree and fixed-point comparison modes are supported.
- [ ] Repository standards override general review heuristics.
- [ ] Standards and Spec findings are reported separately with evidence.
- [ ] A missing specification skips only the Spec axis and is reported clearly.
- [ ] Sub-agents are optional rather than required.
- [ ] The upstream setup Skill and Claude-specific assumptions are removed.
- [ ] Source license, pinned commit, digest, registry lifecycle, UI metadata, and
      GovernanceWiring are complete.
- [ ] Official Skill and projectD checks pass.

## Blocked by

- None — ready now.

## References

- [Implementation Review Gate specification](../../specs/implement-review-gate.md)
- [Upstream code-review Skill](https://github.com/mattpocock/skills/tree/ed37663cc5fbef691ddfecd080dff42f7e7e350d/skills/engineering/code-review)

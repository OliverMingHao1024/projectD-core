# Adopt implement with a mandatory review gate

## What to deliver

A projectD-maintained `implement` CanonicalSkill that executes one approved
specification or ticket with the relevant stack guidance, testing strategy, and
mandatory `code-review` completion gate for behavioral changes.

## Acceptance criteria

- [ ] The Skill refuses to invent unresolved product decisions and implements
      only settled scope.
- [ ] It selects relevant PG and stack guidance without duplicating coding
      standards.
- [ ] TDD is conditional, while relevant tests and acceptance-criteria
      verification remain mandatory.
- [ ] Code and behavior-affecting configuration changes invoke `code-review`.
- [ ] Documentation-only work can report `code-review: not applicable`.
- [ ] Material review findings are fixed or explicitly reported; material fixes
      receive one focused re-review.
- [ ] The workflow cannot enter an unbounded review loop.
- [ ] Commit and push remain separately authorized actions.
- [ ] Source license, pinned commit, digest, registry lifecycle, UI metadata, and
      GovernanceWiring are complete.
- [ ] Official Skill, projectD, and end-to-end workflow checks pass.

## Blocked by

- [Adopt cross-agent code-review](01-adopt-code-review.md)

## References

- [Implementation Review Gate specification](../../specs/implement-review-gate.md)
- [Upstream implement Skill](https://github.com/mattpocock/skills/tree/ed37663cc5fbef691ddfecd080dff42f7e7e350d/skills/engineering/implement)

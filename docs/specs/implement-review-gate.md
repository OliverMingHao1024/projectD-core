# Implementation Review Gate

## Problem

The upstream `implement` workflow mandates TDD, review, and commit regardless of
context. Removing review entirely, however, would make implementation quality
vary across AI Agents.

## Outcome

Provide a cross-agent delivery flow:

`to-spec → to-tickets → implement → code-review`

The flow keeps TDD conditional while making review a completion gate for code
and behavior-affecting configuration changes.

## User stories

1. As a project maintainer, I want every behavioral implementation reviewed, so
   that standards violations and specification drift are caught consistently.
2. As an implementing Agent, I want to select the testing approach from project
   evidence, so that work is not blocked by an unsuitable TDD mandate.
3. As a project maintainer, I want upstream Skill updates detected without
   overwriting local adaptations, so that projectD governance remains stable.

## Acceptance criteria

- [x] `implement` operates only from an approved specification, ticket, or
      equivalently settled scope.
- [x] TDD is optional; validation and relevant tests remain mandatory.
- [x] Source-code and behavior-affecting configuration changes must pass
      `code-review`.
- [x] Documentation-only work may report `code-review: not applicable`.
- [x] `code-review` supports an uncommitted working tree and fixed-point branch,
      tag, or commit comparisons.
- [x] Standards and specification findings remain separate.
- [x] Review does not require sub-agents; the current Agent can run both axes.
- [x] Material fixes receive one focused re-review without creating an
      unbounded review loop.
- [x] Neither Skill commits or pushes without explicit user authorization.
- [x] Upstream changes produce a drift report and never overwrite a
      CanonicalSkill automatically.

## Implementation decisions

- Adopt the adapted `code-review` CanonicalSkill before the `implement`
  CanonicalSkill that depends on it.
- Place both cross-stack Skills under `core/skills/` and expose them through
  projectD GovernanceWiring.
- Remove the upstream setup Skill dependency, Claude-specific metadata,
  mandatory sub-agent dispatch, mandatory TDD, and automatic commit behavior.
- Reuse project glossary, ADRs, repository standards, PG guidance, and
  stack-specific packs instead of duplicating coding rules.
- Track each upstream path by pinned commit and digest in the SkillRegistry.

## Testing decisions

- Validate both folders with the official Skill validator.
- Run projectD catalog, registry, contract, and GovernanceWiring checks.
- Exercise working-tree review, fixed-point review, and review without a
  specification.
- Verify that non-TDD implementation still runs relevant tests and reaches the
  mandatory review gate.
- Verify that material review fixes trigger at most one focused re-review.

## Out of scope

- Adopting the upstream `tdd` Skill.
- Automatically fixing every review finding.
- Automatically committing, pushing, or opening a pull request.
- Automatically merging future upstream changes.

## Assumptions and open questions

- No open question currently blocks implementation.

## References

- [Targeted Skill intake ADR](../adr/0001-targeted-skill-intake.md)
- [Upstream implement Skill](https://github.com/mattpocock/skills/tree/ed37663cc5fbef691ddfecd080dff42f7e7e350d/skills/engineering/implement)
- [Upstream code-review Skill](https://github.com/mattpocock/skills/tree/ed37663cc5fbef691ddfecd080dff42f7e7e350d/skills/engineering/code-review)

---
name: implement
description: Implement one approved specification, ticket, or equivalently settled scope with repository-appropriate guidance, tests, and a mandatory code-review gate for behavioral changes. Use when the user asks to implement approved work rather than explore, clarify, prototype, or merely plan it.
---

# Implement

Deliver one settled unit of work. Do not invent unresolved product decisions or
silently expand scope.

## Establish the contract

1. Read the approved spec, ticket, acceptance criteria, and referenced decisions.
   If a material requirement is unresolved, stop and ask rather than guessing.
2. Read applicable repository instructions, current code, tests, and relevant
   language or stack Skills. Reuse their rules instead of copying them here.
3. Inspect repository status before editing. Preserve unrelated and pre-existing
   user changes, and record the files or hunks in the implementation scope.
4. Select the smallest vertical slice that satisfies the approved outcome.

## Implement and verify

Choose the testing strategy from project evidence:

- Prefer TDD when a stable behavioral seam exists and a failing test will reduce
  uncertainty, especially for regressions and complex logic.
- Do not require TDD when the seam is absent, the change is mechanical, or the
  repository uses another established verification workflow.
- In every case, add or update appropriate tests when behavior changes and
  verify the acceptance criteria.

Implement incrementally. Run focused tests and static checks during the work,
then run the broadest relevant suite justified by the change before declaring it
complete. Report checks that could not run and why.

## Complete the review gate

Classify the result:

- **Code or behavior-affecting configuration:** Invoke the `code-review` Skill
  against the working-tree scope and approved spec. Material findings block
  completion.
- **Documentation-only:** Report `code-review: not applicable` and perform a
  focused diff and link check instead.

Resolve material findings that are inside the approved scope. After material
review fixes, invoke one focused re-review of the corrected hunks. Do not create
an unbounded review loop: if a material finding remains after that re-review,
report the work as blocked and ask for direction.

Minor findings may be fixed when clearly in scope or reported for follow-up.
Never claim the review gate passed when material findings remain.

## Finish

Summarize delivered behavior, tests and checks, review-gate status, unresolved
risks, and changed files. Do not commit, push, open a pull request, or mutate an
issue tracker unless the user separately authorizes that action.

## Source

Adapted for cross-agent use from
<https://github.com/mattpocock/skills/tree/ed37663cc5fbef691ddfecd080dff42f7e7e350d/skills/engineering/implement>.
Licensed under MIT; see [LICENSE](LICENSE). The adaptation makes TDD conditional,
loads project-specific guidance instead of prescribing coding rules, requires a
bounded `code-review` gate for behavioral changes, and removes automatic commit.

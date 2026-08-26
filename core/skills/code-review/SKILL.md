---
name: code-review
description: Read-only review of a working tree, branch, commit, tag, or PR along separate Standards and Spec axes.
---

# Code Review

Review only. Do not edit source, resolve findings, stage changes, or alter tracker
state while this Skill is active.

## Establish the review scope

Choose one mode and state it in the report:

- **Working tree:** Use when uncommitted changes exist and no fixed point was
  supplied. Inspect `git diff HEAD`, repository status, and relevant untracked
  files. Distinguish pre-existing user changes from the requested work.
- **Fixed point:** Resolve the user-supplied commit, branch, tag, or merge-base,
  then inspect the three-dot diff to `HEAD` and the intervening commit list.
  State whether uncommitted changes are excluded.
- **Discovered base:** When the working tree is clean, use an unambiguous PR base
  or tracked upstream merge-base. Ask only when no single base can be established
  safely.

Fail early when the reference is invalid or the resulting scope is empty.

## Gather evidence

Find the specification in this order:

1. a path, issue, PR, or ticket supplied by the user or invoking workflow;
2. references in the reviewed commits or branch metadata;
3. a matching approved spec or ticket in the repository.

If no specification exists, skip the Spec axis and state `No spec available`.
Do not invent requirements.

Load repository standards that govern the changed files: applicable `AGENTS.md`
files, constitution or governance rules, contribution guides, language and stack
Skills, ADRs, and documented conventions. Repository-specific rules override
general heuristics.

## Review independently

Run both axes without allowing one result to mask the other:

### Standards

Check the diff against documented rules. Use general design smells only as
judgement prompts, never as hard violations: unclear names, duplicated logic,
scattered changes, inappropriate coupling, speculative generality, and behavior
tested through unstable implementation details. Skip issues already enforced by
the completed toolchain unless its output shows a failure.

### Spec

Compare the diff with the approved outcome and acceptance criteria. Find missing
or partial requirements, unrequested scope, behavior that contradicts the spec,
and tests that fail to demonstrate the promised outcome.

Use sub-agents only when current instructions and user authorization permit it.
Otherwise review both axes directly in the current Agent. Independence of the
axes is required; parallel execution is not.

## Report

Lead with findings, ordered by severity within each axis. For every finding:

- label it `Material` or `Minor`;
- cite the changed file and line or hunk;
- cite the governing rule or specification requirement;
- explain the observable risk;
- suggest the smallest corrective direction without implementing it.

A finding is material when it can affect correctness, security, data integrity,
public behavior, acceptance criteria, or a mandatory documented rule. If no
finding exists, say so explicitly under that axis.

End with:

- finding totals for Standards and Spec;
- any skipped axis and reason;
- `Review gate: passed` only when no material finding remains;
- `Review gate: blocked` when material findings remain.

Do not merge the two axes into one score or claim full specification compliance
when the Spec axis was unavailable.

## Source

Adapted for cross-agent use from
<https://github.com/mattpocock/skills/tree/ed37663cc5fbef691ddfecd080dff42f7e7e350d/skills/engineering/code-review>.
Licensed under MIT; see [LICENSE](LICENSE). The adaptation adds working-tree
review, removes the tracker setup dependency and mandatory parallel sub-agents,
keeps both axes usable in one Agent, and makes review a read-only evidence gate.

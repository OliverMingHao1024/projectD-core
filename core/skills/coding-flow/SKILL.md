---
name: coding-flow
description: Plan and build a new feature or behavior change with DDD, BDD, and TDD; use before writing code.
---

# Coding Flow

DDD decides the model and its boundaries. BDD defines behavior and acceptance.
TDD owns unit-level implementation quality. Each layer answers a different
question; do not let one stand in for another.

| Layer | Question | Output |
| --- | --- | --- |
| DDD | What are the things, words, and boundaries? | Glossary, bounded context, model decisions |
| BDD | Is the behavior right? | Given/When/Then scenarios the user can accept |
| TDD | Is the code well built? | Red → green → refactor unit tests |

## Scale the flow to the risk

Do not run every stage by default.

- **Small, mechanical, or single-rule change:** after stage 0, skip DDD and BDD;
  use `implement` directly.
- **Behavior change inside a known model:** after stage 0, skip DDD; start at BDD.
- **New feature, new term, or new boundary:** run every stage.

State which stages you are skipping and why before starting.

## 0. Confirm the requirement

Do this before touching any file, at every risk level. If the user points to a
requirement document or spec, read it first and do not ask what it already answers.

Ask until each item is clear:

- **What:** the user-visible behavior, not the implementation.
- **Where:** which sub-projects are involved (front end, back end, SQL).
- **Entry point:** what triggers it (button, route, API call, scheduled job).
- **Data flow:** where data comes from, how it changes, and where it goes.
- **Success:** how we know it works.
- **Edge cases:** empty input, unauthorized user, network or data failure.

Gate: no open item. Do not assume an answer; ask.

## 1. DDD: settle the model

Use the `domain-modeling` Skill.

1. List the domain terms the work touches. Reuse existing terms; add one only
   when no existing term fits.
2. Name the boundary: which context owns the rule, and which contexts only call it.
3. Record decisions that are hard to reverse or surprising without context.

Gate: every term used later has one meaning, and one context owns each rule.
If a term is still ambiguous, stop and ask.

## 2. BDD: define behavior

Write scenarios in the domain's own words from stage 1.

```
Scenario: <business outcome>
  Given <state in domain terms>
  When  <one action>
  Then  <observable result>
```

1. One scenario per business outcome. Include the normal path, the failure path,
   and the edge cases that matter.
2. Scenarios describe behavior a user can see, not classes or methods.
3. Show the scenarios to the user. Treat them as the acceptance criteria.

Gate: the user accepts the scenarios, and each scenario uses only stage-1 terms.
Use `to-spec` or `to-tickets` when the work is large enough to need them.

## 3. TDD: build one scenario at a time

Use the `implement` Skill for the contract, scope, and review gate.

Before the first scenario, map the impact:

- List every file each layer must change, using the applicable stack pack for
  that layer's conventions (for example `csharp`, and its ESOAF reference for
  ESOAF back ends).
- For full-stack work, settle the API contract (request and response shape)
  before coding either side.
- Show the impact map to the user and confirm before writing code.

Then, for each scenario:

1. Take one scenario. Pick the smallest vertical slice that satisfies it.
2. Write a failing unit test first. Confirm it fails for the expected reason.
3. Write the least code that passes. Then refactor with the tests green.
4. Run the scenario itself to confirm the behavior, not only the unit tests.
5. Repeat for the next scenario.

Follow `implement`: TDD is conditional. Where no stable seam exists, use the
repository's established verification and say so.

## 4. Verify: try to break it

Tests going green is not the end.

1. Re-read the final diff against the scenarios and the stage-1 boundary.
2. Look for a counterexample: an input, a state, or a caller that makes a
   scenario fail. Try at least one for each scenario.
3. If one succeeds, go back to the stage that owns the mistake (term → 1,
   behavior → 2, code → 3), fix it, and verify again.
4. Run `code-review` through the `implement` review gate for behavioral changes.

Gate: every scenario passes, no counterexample is left open, and the review gate
has no material findings. Report anything that could not be run.

## Boundaries

- Do not invent product decisions. Ask when a term or scenario is unresolved.
- Build only the stated requirement. Do not refactor unrelated code as part of
  the feature; propose it as a separate change.
- Do not commit, push, or open a pull request unless the user separately asks.
- Reuse the Skills named above instead of copying their rules here.

## Source

Original to projectD. Stage 0, the impact map, and the scope rules absorb the
earlier shared `new-feature` Skill, which this replaces. The "try to break it"
stage is inspired by the Critical Relay idea in
<https://github.com/pop15106/pixiu-core> of challenging a result before handing
it off, reduced to a single manual check without its evidence ledger or scripts.

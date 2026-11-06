---
name: refactor
description: Restructure existing code without changing behavior, behind a test safety net.
---

# Refactor

Refactoring changes structure, not behavior. If behavior changes, it is not a
refactor. Every refactor must be verifiable.

For module seams and deeper architecture changes, use `codebase-design` or
`improve-codebase-architecture` instead.

## 1. Set up a safety net first

- Find the tests that cover the code. Run them now and note the pass count.
- If there are none, **stop and ask** whether to add tests first or proceed at the
  user's risk. Do not skip this silently.

## 2. Diagnose

Read the code, then check which applies:

- A function too long to follow → extract sub-functions.
- A file mixing unrelated jobs → split it.
- The same logic in three or more places → extract one shared function.
- A name that does not say what it is → rename.
- A magic number or string → name it as a constant.
- Conditionals nested three or more levels → use guard clauses or early returns.

## 3. Map the blast radius

- Which files change, and which callers a rename or signature change affects.
- Where an extracted shared function lives, and who owns it.

Show the plan to the user when it spans more than two files.

## 4. Change one kind of thing at a time

In this order, keeping tests green after each step:

1. Rename.
2. Extract constants.
3. Extract functions.
4. Reorganize files.

## 5. Verify

Run the same tests as step 1. Everything that passed must still pass. If a test
breaks, the refactor changed behavior: revert that step and investigate.

## Hard rules

- Do not fix bugs or add features inside a refactor; propose them separately.
- Do not change a public API signature without the user's approval.
- Say so explicitly when the code has no test coverage.

## Source

Moved from the retired `oai-core/shared-skills` into projectD.

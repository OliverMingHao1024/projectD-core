---
name: minimal-implementation-ladder
description: Decide how much to build before writing code, adding files, dependencies, or abstractions; use when scoping a change, fix, or refactor.
---

# Minimal Implementation Ladder

Before writing new code, adding a file, adding a dependency, or widening scope, walk
this ladder from the top and stop at the first rung that holds.

## Before you climb

Read the task and the code it touches first. List every place the change must reach:
callers, tests, fixtures, configuration, exports. Check what it could break for users,
such as data it would destroy or expose, or callers that stop working. That is scope;
extra features are not. Being lazy applies to the solution, never to finishing every
part the task needs.

1. **Nothing to build.** Can configuration, an existing command, an existing screen,
   or an explanation meet the need? If so, say so and stop.
2. **Already in this repository.** Is there a helper, component, mapper, script, or
   pattern of the same shape? Reuse it with the smallest adjustment.
3. **Standard library.** Does the language's standard library already cover it?
4. **Native platform.** Does the browser, OS, or framework already provide it? Prefer
   it over a hand-written generic component, unless the project already has its own
   component for the job; then use that one (rung 2).
5. **Dependency already in use.** Is a dependency the project already installs and
   uses able to do it safely? Do not add a new one.
6. **A smaller shared point.** Can one fix at the real shared function, mapper, or
   schema boundary replace a patch in every caller?
7. **Smallest correct new code.** Only now add new code, scoped to what acceptance
   needs: no extra files, abstractions, or settings. New non-trivial logic (a branch,
   a loop, a parser, money, or security) still leaves one small test or self-check;
   do not add tests beyond that. When two options are equally small, take the one that
   is correct on edge cases.

## Never simplified away

Shortening a diff is a side effect, not the goal. Keep:

- Output, format, or behavior the user explicitly asked for.
- Security, authorization, input validation, parameterized queries, data-loss
  protection, and rollback.
- Error handling for external systems, transaction boundaries, idempotency, audit
  logging, and masking of sensitive data.
- Compatibility with legacy systems and known manual procedures.
- Verification proportionate to risk.

## Rules of use

- If the smallest option conflicts with safety, maintainability, or the user's need,
  present two or three options with trade-offs and wait for the user to choose.
- Do not apply the ladder to unrelated pre-existing changes; stay within the task's
  agreed paths.
- A small task does not justify delegating to extra agents.
- Report briefly, and only when the choice affects scope, dependencies, or safety:
  what was reused, what was deliberately not added, what was kept.

This is a subordinate, composable aid. The project constitution, nearer repository
rules, and the user's current explicit instructions always take precedence.

## Source

Idea inspired by `vault/governance/minimal-implementation-ladder.md` in
<https://github.com/pop15106/pixiu-core> (reviewed at
`f4d9aec06ef742723fc00f39639d42eb1a726cb6`). That repository has no LICENSE file, so
no text is copied: this Skill is an independent rewrite of the idea.

The "Before you climb" step, the edge-case tie-break, the small-test rule, and the
"project's own component first" note are independent rewrites of ideas in
`skills/ponytail/SKILL.md` of <https://github.com/DietrichGebert/ponytail> (MIT),
(reviewed at `09c434ab73ca43761c5d8b0c5d341926c2fba710`). No text is copied; its levels, `shortcut:` comments, hooks, and always-on
reply footer were deliberately not adopted.

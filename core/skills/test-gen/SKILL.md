---
name: test-gen
description: Add unit tests to existing code using the repository's test framework and conventions.
---

# Test Generation

For new behavior, write tests first through `coding-flow`. Use this Skill to cover
code that already exists.

## 1. Find the framework

Read the project files and the applicable stack pack. Common signals:

- `package.json` with `jasmine`/`karma` → Jasmine + Karma.
- `package.json` with `jest`/`vitest` → Jest or Vitest.
- `*.csproj` → the test project's framework (xUnit, NUnit, or MSTest).
- `pom.xml` or `build.gradle` → JUnit 5.

If it is still unclear, ask before writing.

## 2. Read the target

Understand inputs, outputs, side effects, and edge cases before writing anything.

## 3. List the cases

For each public function or component:

- Normal input and expected output.
- Boundaries: empty, null, zero, maximum.
- Error and exception paths.
- Async or side-effect paths, when present.

## 4. Write the tests

- Follow the repository's existing naming. If there is none, use
  `should_<expectedBehavior>_when_<condition>`.
- One behavior per test; several assertions about that behavior are fine.
- No logic in tests: no `if`, no loops.
- Mock only external dependencies (HTTP, database, file system), never the unit
  under test.
- Tests must be independent: no shared mutable state.

## 5. Place and run them

Put the file where the project already keeps tests (for example `foo.spec.ts` next
to `foo.ts`, or a `test/` folder). Run them and report the result, including any
test that could not run and why.

## Source

Moved from the retired `oai-core/shared-skills` into projectD.

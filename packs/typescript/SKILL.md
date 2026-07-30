---
name: typescript
description: TypeScript and JavaScript language, compiler, module-system, and build-tool conventions. Use when changing .ts, .tsx, or JavaScript source, tsconfig, package scripts, generated-output boundaries, type checking, or build configuration.
---

# TypeScript Pack

Use for TypeScript or JavaScript language and build-tool work. Combine with `frontend-core`
for browser UI, `node-runtime` for Node.js, and the applicable framework pack.

## Establish the Baseline

- Read the TypeScript version, module system, package manager, compiler options, build
  tool, runtime targets, lint setup, test setup, and generated-output policy.
- Inspect JavaScript interoperability and project-reference or workspace boundaries.
- Preserve repository-level strictness and version constraints.

## Rules

- Preserve the established module system, package manager, and build pipeline.
- Keep TypeScript strictness and compiler options aligned with the existing project.
- Make public type, runtime-validation, and generated-output boundaries explicit.
- Follow existing import, path alias, declaration, and source-map conventions.
- Avoid unsafe assertions that hide unvalidated external data.
- Do not introduce or replace a frontend framework incidentally.

## Verification

- Run the repository's focused tests, lint, type check, and production build.
- Verify emitted output and runtime behavior when compiler or module settings change.
- Check affected package boundaries when using workspaces or project references.

---
name: typescript
description: TypeScript language, compiler, and JavaScript/TypeScript build-tool conventions.
---

# TypeScript Pack

Use for TypeScript or JavaScript language and build-tool work. Combine with
`frontend-core` for browser UI or `node-runtime` for Node.js services.

## Rules

- Preserve the repository's module system, package manager, and compiler/build tool versions.
- Keep TypeScript strictness and compiler options aligned with the existing project.
- Keep JavaScript interop and generated output boundaries explicit.
- Avoid adding a frontend framework when the project is framework-neutral.

## Verification

- Run the repository's existing compiler and build checks for changed packages.

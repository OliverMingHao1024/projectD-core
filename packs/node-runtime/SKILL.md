---
name: node-runtime
description: Node.js runtime, Express services, middleware, and process lifecycle conventions.
---

# Node Runtime Pack

Use for Node.js services, Express tools, CLI programs, and runtime code. Combine
with `typescript` when the implementation is TypeScript or with `frontend-core`
when the service also owns a browser UI.

## Rules

- Preserve the repository's Node version, module system, package manager, and startup contract.
- Validate external input at trust boundaries and propagate asynchronous errors explicitly.
- Keep Express middleware ordering, response contracts, and shutdown behavior testable.
- Use named constants, parameterized queries, and explicit cleanup for filesystem or process resources.
- Avoid adding a frontend framework to a server or utility application without a demonstrated need.

## Verification

- Run the repository's existing lint, type-check, build, and focused tests.
- Exercise one success path and one validation/error path for changed Express or CLI behavior.

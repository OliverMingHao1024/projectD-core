---
name: node-runtime
description: Node.js runtime conventions for services, Express applications, CLI tools, middleware, asynchronous work, and process lifecycle. Use when changing Node entry points, server behavior, filesystem or process resources, shutdown handling, tests, or runtime configuration.
---

# Node Runtime Pack

Use for Node.js services, Express tools, CLI programs, and runtime code. Combine with
`typescript` for TypeScript or `frontend-core` when the application owns a browser UI.

## Establish the Baseline

- Read the Node version, module system, package manager, startup contract, runtime
  configuration, framework, test setup, and deployment or process model.
- Inspect middleware ordering, error propagation, logging, and shutdown behavior.
- Preserve repository-level architecture and version constraints.

## Rules

- Validate external input at trust boundaries and propagate asynchronous failures.
- Preserve Express middleware ordering and response contracts.
- Clean up filesystem, network, timer, and child-process resources explicitly.
- Keep graceful shutdown and signal handling correct for long-running processes.
- Use parameterized queries and keep secrets outside source code.
- Do not add a frontend framework or replace runtime tooling without demonstrated need.

## Verification

- Run the repository's focused tests, lint, type check, and production build.
- Exercise one success path and one validation or failure path for changed boundaries.
- Verify startup, shutdown, and resource cleanup when lifecycle code changes.

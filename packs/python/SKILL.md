---
name: python
description: Python conventions for scripts and automation, FastAPI, Flask or Django backends, and data or analysis workflows. Use when changing Python modules, dependency management, typing, data processing, web boundaries, tests, linting, or runtime commands.
---

# Python Pack

Use for Python application and automation work. Combine with another applicable pack when
Python owns a browser UI, external service, or technology-specific boundary.

## Establish the Baseline

- Read the supported Python version, package manager, environment setup, application
  framework, project layout, quality-tool configuration, and test runner.
- Identify whether the work is a script, web backend, data pipeline, notebook, library,
  or long-running process.
- Preserve the repository's module boundaries, dependency workflow, typing policy, and
  formatting conventions.

## Rules

- Keep business logic out of transport, CLI, notebook, and framework entry points.
- Add type annotations at meaningful public boundaries and follow existing strictness.
- Validate external input and preserve useful exception context.
- Bound memory use, retries, loops, and concurrency according to measured workload needs.
- Keep secrets and machine-specific paths outside source code.
- Do not replace package managers, frameworks, or quality tools incidentally.

## Verification

- Run the repository's focused tests, lint, type checks, and relevant execution path.
- Exercise one valid input and one invalid or failure input for changed boundaries.
- Verify deterministic output and resource cleanup for scripts or data workflows.

## References

- Read [project-conventions.md](references/project-conventions.md) for structure, typing,
  review checks, tests, and command guidance.

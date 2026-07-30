---
name: csharp
description: C# conventions for ASP.NET Core APIs, backend services, console and background tools, and existing .NET Framework applications. Use when changing C# source, project or solution files, dependency injection, data access, asynchronous behavior, builds, or tests.
---

# C# Pack

Use for C# application work. Combine with another applicable pack when a C# service also
owns a browser UI or another technology-specific boundary.

## Establish the Baseline

- Read the target framework, SDK and project style, solution structure, package versions,
  nullable policy, build commands, and test setup before changing code.
- Distinguish SDK-style .NET applications from existing .NET Framework applications.
- Preserve the repository's architecture, dependency injection, data access, logging,
  and configuration conventions.

## Rules

- Use the configured dependency injection container; do not construct managed services
  manually at call sites.
- Keep asynchronous APIs task-based, propagate cancellation, and avoid `async void`
  except for event handlers.
- Validate external input and handle exceptions at meaningful system boundaries.
- Preserve transaction, query, and resource lifetimes; check data access changes for
  N+1 behavior and unintended materialization.
- Follow existing naming, file layout, and test conventions.
- Do not upgrade target frameworks, packages, or architecture as part of an unrelated change.

## Verification

- Run the repository's focused tests and appropriate `dotnet` or MSBuild build.
- Exercise one success path and one validation or failure path for changed boundaries.
- Verify dependency-injection lifetimes and cancellation for affected long-running work.

## References

- Read [project-conventions.md](references/project-conventions.md) for structure, naming,
  review checks, tests, and build-command guidance.

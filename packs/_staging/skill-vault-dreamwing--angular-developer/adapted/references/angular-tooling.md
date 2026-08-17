# Angular Tooling and Configuration

Angular CLI commands can modify source, configuration, dependencies, and deployment
settings. Inspect the workspace and command scope before execution.

## CLI selection

- In an existing workspace, prefer repository scripts and the workspace-local Angular CLI.
- In a genuinely greenfield project, use the user-specified Angular version. If none is
  specified, select the current stable compatible toolchain and report the resolved version.
- Use generators when they match the repository convention; manual edits remain valid when
  generators would create unrelated files or dependencies.

## Mutation boundaries

- Treat `ng add` and package-manager install commands as dependency changes.
- Treat `ng update` and migration schematics as codebase-wide transformations that require
  explicit migration scope, a clean recovery path, and staged verification.
- Treat `ng deploy` and deployment builders as deployment changes requiring separate
  authorization.
- Do not accept an interactive install prompt implicitly.

## Migration workflow

1. Confirm the installed Angular and TypeScript versions and supported migration path.
2. Record the exact project or path scope and inspect pending worktree changes.
3. Run one migration stage at a time.
4. Review the diff and run focused checks after each stage.
5. Stop when a stage creates unrelated changes or the recovery boundary is unclear.

Do not run standalone, control-flow, signal, or inject migrations merely because the
current Angular version offers them.

## Environment configuration

- Never place secrets in Angular environment files or other client bundles.
- Use build-time replacement when each environment can have a distinct artifact.
- Use runtime configuration only when one artifact must serve multiple environments and
  the startup dependency is acceptable.
- Validate runtime configuration as untrusted input and define startup failure behavior.

## MCP

Angular CLI MCP can read workspace configuration, search documentation, and, when enabled,
run builds, tests, dev servers, or migrations. Do not add MCP host configuration or run
`npx ... mcp` during ordinary Angular work. Apply the projectD-core MCP security boundary,
least privilege, read-only/local-only options where available, and explicit user approval.

# External Runtime State

- Status: approved design; migration implementation pending
- Scope: Git-ignored runtime, private state, indexes, models, virtual
  environments, and regenerable caches currently stored under `.local/`

## Problem

The repository checkout currently carries device-specific runtime data under
`.local/`. A 2026-08-30 evidence snapshot measured approximately 549 MiB:

| Current subtree | Approximate size | Classification |
|---|---:|---|
| `.local/project-history` | 505 MiB | mixed state, index, model cache, virtualenv |
| `.local/test-venv` | 36 MiB | regenerable cache |
| `.local/governance` | 5 MiB | private durable state |
| Codex app-server schemas | 2.8 MiB | regenerable cache |
| `.local/usage` | 859 KiB | private durable ledger/report state |

Git ignores these files, but their location still couples repository lifecycle,
backup, cleanup, and multi-device behavior to one checkout.

## Desired boundary

Use two explicit roots:

- `PROJECTD_STATE_HOME`: durable device-local state such as registries,
  allowlists, ledgers, reports, wiring state, project-history configuration,
  and indexes.
- `PROJECTD_CACHE_HOME`: regenerable virtual environments, model downloads,
  downloaded schemas, and test caches.

No secret, private ledger, model cache, virtual environment, or generated index
is committed to Git or copied to `projectD-knowledge`.

Suggested platform defaults after migration:

- Windows state: `%LOCALAPPDATA%\projectD\state`
- Windows cache: `%LOCALAPPDATA%\projectD\cache`
- Linux state: `$XDG_STATE_HOME/projectD` when defined
- Linux cache: `$XDG_CACHE_HOME/projectD` when defined

Explicit environment variables override defaults. Scripts must not silently
scan for older state outside the known legacy path.

## Migration design

1. Add one shared path resolver used by every PowerShell/Python entry point.
2. Add `Plan`, `Apply`, `Check`, and `Rollback` modes to a bounded
   migration command.
3. `Plan` reports exact source, destination, sizes, conflicts, and required
   free space without writing.
4. `Apply` copies to a temporary destination, verifies file counts and
   digests, then atomically activates the new roots.
5. Existing state remains untouched until activation and verification succeed.
6. Cache data may be rebuilt instead of copied; durable state may not.
7. Cross-device or network destinations require separate explicit
   authorization.
8. Rollback restores the previous resolver configuration without deleting the
   verified destination.
9. Legacy `.local/` cleanup is a later explicit action after both old and new
   paths have been verified.

## Compatibility

During one migration release, reads may fall back to the known repository
`.local/` path only when the resolved external path does not exist. Writes
must target one root only. Every command reports which root is active; silent
fallback is forbidden.

## Acceptance criteria

- All path construction is centralized and covered by contract tests.
- Project-history, usage monitoring, governance wiring, knowledge registry,
  captures, and test tooling use the resolver.
- Migration fails closed on conflicts, partial copies, digest mismatches,
  insufficient space, or unsafe destinations.
- No raw prompt, response, tool arguments/output, credentials, or real account
  email enters exported diagnostics.
- Existing repository checks pass with both legacy and external-root fixtures.
- A verified rollback test restores the legacy configuration without data loss.

# ADR 0019 — Run the Claude post-tool evidence hook in the background

- Status: accepted
- Date: 2026-11-16
- Supersedes: the "every Claude hook event is synchronous" rule in
  `../specs/governance-evals-v2-phase-3.md` (Host hook 邊界) for `PostToolUse` and
  `PostToolUseFailure` only

## Context

Every Claude tool call outside `Read|Glob|Grep` starts three `pwsh` processes: two
parallel `PreToolUse` hooks and one `PostToolUse` (or `PostToolUseFailure`) hook. The
dominant cost is `pwsh` startup (measured 2026-11-11: about 1.8 s empty start, about
2.3 s per hook; see `vault/memory/memory-summary.md`). The IT policy blocks the usual
fixes (antivirus exclusions), and tuning the script itself gains little.

All three events were synchronous, so Claude waited for the post hook before it
continued. That post hook does one thing: it appends the `effect-result` record
(`record-3`) to the per-call operation log and moves the runner state from
`requires-reconciliation` to `open` (or keeps it for a failure). It cannot block or
change the tool result, because the tool has already run.

Claude Code's `asyncRewake` command-hook option runs a hook in the background with the
same stdin payload, still enforces its `timeout`, and wakes Claude immediately when the
hook exits with code 2, showing its stderr. The shared handler already exits 2 with a
stderr message on any rejection.

## Decision

Register the Claude `PostToolUse` and `PostToolUseFailure` evidence hooks with
`"asyncRewake": true`. Keep `PreToolUse` synchronous: the intent record must still be
durable before the effect, and policy denial must still happen before the effect.

Codex hooks are unchanged.

## Why this is safe enough

- Each tool call has its own log and lock; `PreToolUse` reads only its own call's log,
  so a later call never depends on an earlier call's result record.
- A result that never lands (session exits while the hook runs, or the hook is killed)
  leaves that log at `requires-reconciliation` with `pending_effect_id` set. That is
  the state the ledger already defines for "intent without result", so the evidence
  stays truthful instead of silently claiming success.
- A handler rejection still reaches Claude through the exit-2 rewake, so failures are
  not hidden.

## Consequences

- Claude no longer waits for one `pwsh` start per tool call. The expected saving is
  roughly one hook (about 2.3 s) per call; this figure is an estimate until measured
  on the host.
- More operation logs may remain at `requires-reconciliation` after abrupt exits.
  Evidence readers must keep treating that state as unverified, never as success.
- A rejection is reported after Claude has already continued, not before. Post-tool
  rejections could not undo the effect before either.
- The host contract test asserts `PreToolUse` synchronous and the two Claude post
  events `asyncRewake`.

## Not chosen

- `if` filters on the hook: would drop coverage for tools the ledger must record.
- Narrowing the command-policy hook matcher: it also blocks Edit/Write to the
  classification registry, and it already runs in parallel with the evidence hook, so
  the wall-time gain is small.
- A long-running `http` hook server: removes `pwsh` startup entirely but adds a local
  listener and a fail-closed availability problem. Revisit only with measured need.

## Verification boundary

Contract tests prove the configuration shape only. Whether the hook actually runs in
the background, and how much time it saves, must be confirmed on the live host.

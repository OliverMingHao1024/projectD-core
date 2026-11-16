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
  roughly one hook (about 2.3 s) per call. Measured on the host: about 2.0 s per call
  (see "Host measurement" below).
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

## Host measurement (2026-11-16)

Read-only measurement on the live host after PR #130. No code or settings changed.
Result: the post hook now runs in the background, and Claude no longer waits for it.
The saving is about 2.0 s per hooked tool call.

### Main evidence: when the result reaches Claude

Method: compare when the tool result reached Claude (session transcript `.jsonl`,
`tool_result` timestamp) with when the post hook finished (operation log `record-3`
`occurred_at`).

| | Before (synchronous, 05:51 UTC) | After (`asyncRewake`, 08:51 UTC) |
|---|---|---|
| Sample | 4 calls (Write, Edit, update_plan, Bash) | 10 sequential `git status --short` |
| Result reached Claude vs. `record-3` | 0.08–0.24 s **after** | 1.89–2.48 s **before** (median 2.03 s) |

- Before: Claude received the result only after the post hook finished.
- After: Claude received it about 2 s earlier, while the post hook was still running.
- Remaining cost: from tool call to result is still about 4.0 s (median of 9;
  `git status` itself is fast). That time is now almost all the synchronous
  `PreToolUse` hooks, mostly `pwsh` startup (about 2.5 s from the tool call to the
  hook's first record).

### Ledger-only metrics (cannot show the saving)

A second run of 10 `git status --short` calls (09:00–09:01 UTC), measured from the
operation logs only (all times converted to UTC first):

| Metric | After (10 calls) |
|---|---|
| Gap between call starts, mean / median | 7.91 s / 7.90 s |
| `record-3` − `record-2`, mean / median | 3.72 s / 3.73 s |
| `runner_state.status` not `open` | 0 / 10 |

- `record-3` − `record-2` is not expected to shrink: the post hook still runs to the
  end; only Claude stops waiting for it.
- The gap between call starts includes model think time, which varies by more than
  2 s from call to call. It is a rough metric only.
- No valid "before" baseline was found for these metrics: no older session had 5 or
  more back-to-back Bash calls before 2026-11-16T08:49:42Z. The closest run (4 Bash
  calls on 2026-11-13) ran different, slower commands, so it was not compared.

### Limits

- Small sample. Only 4 clean pairs before the change; calls sent in parallel in one
  message were left out because they could not be matched reliably.
- Transcript timestamps mark when a message was written, not exact execution time
  (about ±0.1 s).
- The first call after the change took 16.4 s from tool call to result. Cause unknown
  (possibly a cold start); it is not counted above.
- No abrupt session exit was tested, so the `requires-reconciliation` path for a
  result that never lands is still unverified on the host.

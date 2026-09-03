# Codex hook intermittent failure — diagnostic handoff

Not a formal spec. This is an operations diagnostic record preserving the investigation,
root causes, mitigations and verified resolution of the Runtime Governance v2 Codex live-pilot blockers.
It is retained because the Windows hook transport findings and current-policy revalidation are useful
operational evidence; normative runtime behavior remains defined by the Runtime Governance v2 spec and runbook.

## Resolution (2026-09-02)

The remaining blocker was root-caused and fixed locally. It was not a race in
the projectD hook and did not require a change to the runtime policy logic.

Codex CLI `0.145.0` on Windows builds command hooks as `cmd.exe /C` plus an
extra pair of outer quotes around the entire `commandWindows` string. The
release source does this in
[`command_runner.rs`](https://github.com/openai/codex/blob/rust-v0.145.0/codex-rs/hooks/src/engine/command_runner.rs),
where `build_command` passes `raw_arg(format!(r#""{}""#, handler.command))`.
When `commandWindows` itself contains a quoted executable path and a quoted
PowerShell `-Command` payload, `cmd.exe` misparses the nested quotes before
PowerShell reaches the script. OpenAI issue
[#38168](https://github.com/openai/codex/issues/38168) documents the same
failure, including the misleading case where Codex reports `Completed` even
though the command body never ran.

The project-side workaround is deliberately quote-free at the Codex boundary:

- `.codex/hooks.json` now uses a quote-free `-EncodedCommand` bootstrap that
  resolves `git rev-parse --show-toplevel`, then invokes
  `scripts\codex-governance-hook.cmd` with either `host` or `policy`.
  No `commandWindows` value contains an embedded double quote. The bootstrap
  must end with `exit $LASTEXITCODE`; otherwise a rejecting inner hook can
  create correct deny evidence while the outer Windows PowerShell process
  reports success to Codex and fails open.
- `scripts/codex-governance-hook.cmd` owns the quoted PowerShell 7 path and
  script arguments after Codex/`cmd.exe` has successfully entered the batch
  file.
- Keep the outer bootstrap executable as `powershell.exe`. Replacing it with
  `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe` passed a manual
  reproduction of Codex's `cmd.exe /C` shape but failed in a real Codex run
  (`6` Pre/Post failures, zero decisions). The full PowerShell 7 path remains
  inside the batch launcher, where quoting is safe.
- The focused contracts reject a future `commandWindows` value containing
  embedded quotes and verify that both Windows hook modes use the launcher.

Verification on Codex CLI `0.145.0`:

- Before the workaround, the reproduction produced only `Failed` hook lines,
  zero runtime decisions, and zero operation evidence.
- After the workaround, the same reproduction plus three consecutive repeats
  produced zero Pre/Post hook failures. Every tool call produced both runtime
  decisions and paired operation evidence (the three repeat runs produced
  `3/6`, `3/6`, and `7/14` decision/evidence counts respectively).
- A separate live run started from the repository's `docs/` subdirectory also
  produced zero hook failures, three decisions, and six operation-evidence
  files. The encoded bootstrap therefore preserves git-root resolution instead
  of depending on the session cwd.
- `governance-host-operation-hook.contract.ps1` and
  `governance-command-policy-hook.contract.ps1` both pass.

This resolves hook process entry/loading for the current Windows pilot. It does
not make a non-zero hook exit a reliable deny signal in Codex CLI `0.145.0` on
Windows. A second live test found that an inner `exit 2`, even when correctly
propagated through both launcher layers, was displayed as a general hook
failure and the requested tool still executed. Durable deny evidence existed,
but the host failed open.

The Codex-specific deny path now follows the host's documented structured
`PreToolUse` response instead: it writes
`hookSpecificOutput.permissionDecision = "deny"` and a metadata-only reason to
stdout, then exits 0. Both `governance-host-operation-hook.ps1` and
`governance-command-policy-hook.ps1` use this path when `HostName=codex`;
Claude retains stderr plus exit 2. The encoded Windows bootstrap still
propagates `$LASTEXITCODE` so launcher or script failures are not hidden, but
Codex policy denial itself no longer depends on a non-zero process result.

The same-session authorization flow was then completed on Codex CLI `0.145.0`:

- a bootstrap read created runtime-policy evidence for the live session;
- a user-authorized `workspace-write/workspace-file` envelope produced an
  `enforced allow`, wrote the local marker, and recorded
  `operation-started -> effect-intended -> effect-result(succeeded)`;
- a subsequent `command-execute/command-environment` request, outside that
  envelope, produced `enforced deny / capability-not-granted`;
- Codex displayed `PreToolUse hook (blocked)`, no command output appeared, and
  no operation JSON was created for the denied call;
- all captured runtime decisions and authorization envelopes passed their JSON
  schemas, the allow operation log passed its evaluator, and the unified
  Governance Evals finished `32 passed, 0 failed`.

This verified the then-current bounded Codex authorization flow and remains
decisive evidence for the Windows hook transport and structured-deny behavior.
A subsequent security review changed the policy digest and found that an agent
could invoke the issuance switch itself, that a workspace grant could target
runtime authorization/control files, and that a Codex PreToolUse internal error
still fell back to the unreliable non-zero exit path. The hardened build now
requires interactive typed confirmation, binds envelopes to the current policy,
fails closed without an envelope for effectful/unclassified calls, protects
runtime state/control targets, and returns structured deny for Codex PreToolUse
errors. Therefore the old allow/deny evidence is historical, not verification of
the hardened policy digest; the current-policy repeat is recorded below. Claude,
hosted/specialized tool paths, crash/reopen recovery, and cross-host
compatibility also remain unverified.

## Interactive revalidation follow-up (2026-09-03)

A trusted interactive Codex CLI `0.152.1` session exercised the hardened policy
digest. The repository hooks loaded and produced 25 runtime decisions under one
stable task/run identity: 22 `network-read / observe-only / advisory` decisions
and three `unclassified-effect / deny / enforced` decisions. This is current
evidence that the interactive hook transport and structured deny path execute;
it is not a completed authorization pilot.

Timestamp correlation against a redacted transcript showed that the three deny
decisions matched one `mcp__codegraph__codegraph_explore` call and two
open-ended `web__run` calls. The DevSpace open/read and GitHub read paths were
classified as `network-read`, so the trace does not support changing the
normalizer to make those unknown calls silently grantable.

The pilot instead exposed a runbook defect. Its generic request to read a local
file did not pin one host tool on CLI `0.152.1`: Codex first attempted DevSpace,
whose initial `open_workspace` call returned MCP error `-32603`, then attempted
CodeGraph, GitHub and web fallbacks. Some network reads succeeded and the model
returned the expected heading, but no completed local-file read established
that result. Multiple decisions and orphaned operation intents therefore made
the bootstrap unsuitable as the source for an authorization envelope. The
session was stopped before issuance, allow or deny cases.

`runtime-governance-v2-codex-live-pilot.md` now pins the bootstrap to exactly
one successful `codex.list_mcp_resources({})` metadata read, records the
observer start time, requires exactly one decision and one completed operation
JSON, and stops on any Apps/connector fallback. This keeps the bootstrap
bounded and attributable while still satisfying the spec's benign observed
source-operation gate.

The next allow attempt exposed a separate deterministic adapter defect. Codex
requested two direct edits, and both were denied as `unclassified-effect`
before any file changed. The session transcript showed the editor's internal
custom call as `exec`, while the
[official Codex hook contract](https://learn.chatgpt.com/zh-Hant/docs/hooks#pretooluse)
states that the hook receives the canonical `tool_name: "apply_patch"` with the
patch text in `tool_input.command`. The projectD normalizer and synthetic
fixtures had incorrectly used only `tool_input.patch`, so the real payload had
no parseable write target and correctly fell back to deny. A red contract using
the canonical payload reproduced the exact `unclassified-effect`; the
normalizer now reads `command` first and retains `patch` only as a compatibility
fallback. Host-hook integration fixtures now use the canonical field. Because
the normalizer is part of the policy digest, authorization issued before this
fix was stale, so the live pilot bootstrapped and issued a fresh envelope before
retrying the allow case.

### Current-policy pilot completed

The fresh trusted interactive Codex CLI `0.152.1` flow using
`gpt-5.6-luna / medium` then completed under one stable task/run identity and
policy digest:

- the pinned `codex.list_mcp_resources({})` bootstrap produced one
  `network-read / observe-only / advisory` decision and one succeeded operation
  with no pending effect;
- a user typed the exact confirmation in an independent interactive terminal,
  producing a 15-minute `workspace-write / workspace-file` envelope with no
  external or destructive grant;
- an explicit built-in `apply_patch` request produced
  `verified / explicit-current-task / exact / enforced allow`, wrote the exact
  local marker and recorded a succeeded operation;
- an out-of-scope `git status --short` shell request produced
  `command-execute / enforced deny / capability-not-granted` before effect, with
  no command output and no corresponding operation JSON;
- the three key decisions, authorization envelope and two succeeded operation logs
  passed their schemas; all durable privacy flags remained false; unified
  Governance Evals passed `32/32`.

This verifies the current-policy bounded Codex single-host authorization path
for the exercised model/effort. It does not extend coverage to other Codex
models, Claude, hosted/specialized tools, recovery, observers or a cross-host
matrix.

## What's fixed and merged (PR #74, master)

`.codex/hooks.json`'s `commandWindows` had two confirmed, reproducible bugs:

1. Missing `-NonInteractive` — a missing/null parameter binding inside
   `governance-host-operation-hook.ps1` made `pwsh` try to prompt
   interactively (`Supply values for the following parameters:
   ChildPath[0]:`), which hangs forever under `codex exec` (no TTY to
   answer). Fixed.
2. Bare `pwsh` instead of the full path. Codex's own internal `exec` calls
   (visible in its own transcript) always use
   `"C:\Program Files\PowerShell\7\pwsh.exe"`, never bare `pwsh` — bare
   `pwsh` was not reliably resolving in whatever environment Codex spawns
   hook subprocesses in on this machine. Fixed by matching Codex's own
   working pattern.

Both are verified fixed: `scripts/tests/governance-host-operation-hook.contract.ps1`
passes (4/4), and manually invoking the exact `commandWindows` string
(outside Codex) reliably produces a `.local/governance/runtime-policy/codex/
decision-*.json` file with exit code 0.

## Original remaining blocker (historical evidence)

Live-testing `codex exec --dangerously-bypass-hook-trust -s workspace-write`
against the current (fixed) `.codex/hooks.json`, across ~6 separate runs on
this machine:

- Some runs: the large majority of `hook: PreToolUse`/`PostToolUse`
  invocations report `Completed`.
- Other runs, with the *identical* `.codex/hooks.json` content, no config
  change in between: **100% of invocations report `Failed`.**
- In every single case (both "mostly Completed" and "100% Failed" runs),
  `.local/governance/runtime-policy/codex/` and
  `.local/governance/operation-hooks/codex/` end up **completely empty** —
  even the runs that reported `Completed` never actually produced a
  decision file.

The decisive diagnostic: `commandWindows` was temporarily rewritten to
redirect all output unconditionally to a log file regardless of success or
failure (`*>> '...codex-hook-raw.log'`, plus an unconditional
`'EXIT='+$LASTEXITCODE... | Add-Content` after it) so *something* would be
written no matter what happened inside the PowerShell script. Manually
running that exact string worked and wrote the log. Under a live
`codex exec` run with the same hooks.json, **the log file was never
created at all** — not empty, not partially written, simply never touched.

This rules out:
- Anything wrong inside `governance-host-operation-hook.ps1`'s own logic
  (bugs there would still hit the redirect and get logged).
- A wrong working directory / git worktree resolving to some other repo
  root (confirmed via the session's own `rollout-*.jsonl` transcript:
  `cwd` is correctly `D:\workspaces\projectD-core` for the whole session).
- Windows UAC file virtualization silently redirecting writes to
  `%LOCALAPPDATA%\VirtualStore\...` (checked; empty/not present).

It points at something failing **before** the PowerShell process ever
executes any of the `-Command` string's content — i.e. in however Codex
itself constructs/spawns the `commandWindows` process on Windows. The later
source-level investigation identified that exact boundary as the deterministic
outer-quote bug documented in the resolution above. The alternating
`Completed`/`Failed` display was not evidence of alternating process execution:
neither display was trustworthy without the durable decision file.

## Investigation checklist and outcome (better positioned than a human/Claude
observer, since it can introspect its own hook-invocation code)

1. How does Codex actually spawn a `commandWindows` string on Windows —
   does it tokenize by whitespace, hand the whole string to `CreateProcess`
   as a single command line, or wrap it via `cmd.exe /c`? This determines
   whether embedded spaces (e.g. in `"C:\Program Files\PowerShell\7\
   pwsh.exe"`, or in the `-Command "..."` argument itself) are preserved
   correctly.
2. Is there a concurrency limit or resource contention when multiple
   `PreToolUse` hooks fire for parallel tool calls (observed: up to 6
   `hook: PreToolUse` lines appearing before any `Completed`/`Failed`
   resolves)? Does hook subprocess spawning have a race or a shared handle
   that fails under concurrent load?
3. Does Codex log the hook subprocess's actual exit code, stderr, or
   spawn error anywhere more detailed than the terse `hook: X Failed` line
   printed to the transcript (e.g. in `~/.codex/log/`, a debug trace level,
   or via `RUST_LOG`)? None was found in `~/.codex/log/` during this
   investigation (only an empty `codex-login.log`).
4. Whether `--dangerously-bypass-hook-trust` itself changes the
   invocation path in a way that differs from the trusted/interactive path
   (this pilot could only be tested non-interactively, so the trusted path
   was never exercised).

## How to reproduce

```powershell
cd D:\workspaces\projectD-core
codex exec --dangerously-bypass-hook-trust -s workspace-write "Read the file README.md and reply with exactly one sentence summarizing what this repository is."
```

Watch for `hook: PreToolUse Failed` / `hook: PostToolUse Failed` in the
transcript, and check whether
`.local/governance/runtime-policy/codex/decision-*.json` files actually
appear afterward (they should, once per tool call, if the hook genuinely
ran end to end).

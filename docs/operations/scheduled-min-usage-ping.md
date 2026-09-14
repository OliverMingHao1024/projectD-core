# Scheduled minimal-usage ping (Codex + Claude Code)

- Status: active, 2026-09-15
- Purpose: keep a minimal, fixed daily usage window for both CLIs without touching project content or doing real work.

## Schedule

Windows Task Scheduler, weekdays only, 09:30 local time (machine timezone is `Taipei Standard Time`):

- `ProjectD-Codex-MinUsage-Weekday0930`
- `ProjectD-Claude-MinUsage-Weekday0930`

Both trigger at the same time; no forced stagger. `MultipleInstances=IgnoreNew`, `ExecutionTimeLimit=5min`, `RestartCount=0` (no scheduler-level retry).

## What each run does

Each task runs a wrapper script under `.local/ops/scheduled-min-usage/` (gitignored, not in this repo's history):

- `run-codex-min-usage.ps1` → `codex exec --skip-git-repo-check -s read-only --color never -C <neutral dir> "只回覆 OK，不要讀取或修改任何檔案。"`
- `run-claude-min-usage.ps1` → `claude -p --no-session-persistence --output-format text --tools "" --strict-mcp-config "只回覆 OK，不要讀取或修改任何檔案。"`

Both run with their working directory set to `%LOCALAPPDATA%\projectD-core-scheduled-ping\<codex|claude>` — a neutral folder outside this repo — so neither CLI reads, analyzes, or modifies project content. Codex additionally runs in `read-only` sandbox; Claude runs with all tools disabled (`--tools ""`) and no MCP servers loaded.

Each wrapper: checks the CLI exists before running, applies a 120s hard timeout (kills the process tree on timeout, never leaves a background process), never retries, and always exits with the underlying CLI's exit code (or `1` on missing CLI / timeout / launch failure). Failures in one CLI never block or affect the other's task.

## Logs and data handling

- `.local/ops/scheduled-min-usage/logs/codex.log` and `logs/claude.log` — one file per CLI, appended per run.
- Log content is limited to: timestamps, the exact command line, the CLI's stdout/stderr, and the exit code. No API keys, tokens, passwords, or project source content are ever written — the prompt itself is a fixed literal string, and the sandboxed/tool-disabled runs never touch real files.
- The entire `.local/` directory is excluded via `.gitignore`, so none of this reaches source control or any remote.

## Management

| Action | Command |
|---|---|
| Next run time | `Get-ScheduledTask -TaskName 'ProjectD-*-MinUsage-Weekday0930' \| Get-ScheduledTaskInfo \| Select TaskName,NextRunTime` |
| Last result | `Get-ScheduledTask -TaskName 'ProjectD-*-MinUsage-Weekday0930' \| Get-ScheduledTaskInfo \| Select TaskName,LastRunTime,LastTaskResult` |
| Manual test | `& .local\ops\scheduled-min-usage\run-codex-min-usage.ps1` / `run-claude-min-usage.ps1` |
| Disable | `Disable-ScheduledTask -TaskName 'ProjectD-Codex-MinUsage-Weekday0930'` (and Claude's) |
| Enable | `Enable-ScheduledTask -TaskName 'ProjectD-Codex-MinUsage-Weekday0930'` (and Claude's) |
| Re-create / change time | edit `-At` in `setup-scheduled-tasks.ps1`, re-run it |
| Full removal | `& .local\ops\scheduled-min-usage\uninstall-scheduled-tasks.ps1`, then optionally delete the `.local\ops\scheduled-min-usage\` folder |

## Governance note

Creating these tasks and writing these scripts required an explicit `command-execute` + `workspace-write` task authorization, issued by the user in a real interactive terminal via `scripts/governance-task-authorization.ps1` (see [agent-runtime-governance.md](../specs/agent-runtime-governance.md)) — this agent cannot self-authorize such effects.

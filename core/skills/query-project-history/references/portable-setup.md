# Portable local setup

Use the project-history capability as an optional local component. Run the normal
`scripts/setup.ps1` first, then:

```powershell
.\scripts\setup-project-history.ps1
```

The installer creates only ignored local state under:

```text
.local/project-history/
├── .venv/
├── candidates/
├── dispositions/
├── models/
├── index.db
├── logs/
├── projects.json
└── runtime.json
```

It asks before downloading Python, FastEmbed, or the embedding model. In
non-interactive environments, downloads require `-AllowDownload`; otherwise setup
fails closed. For restricted company environments:

- Use `-Wheelhouse <path>` for approved offline Python wheels.
- Use `-PackageIndexUrl <internal-url>` for an approved internal PyPI mirror.
- Use `-ModelSource <path>` for an approved FastEmbed cache.
- Use `-PythonPath <path>` for an IT-managed or portable Python 3.11+ runtime.
- Use `-Mode lexical` when no embedding model is approved. This path does not
  install FastEmbed or download a model.

Do not copy `index.db`, `projects.json`, model caches, logs, or personal project
history between personal and company devices. Clone only projectD-core, set up the
local runtime on the target device, then explicitly add approved repositories to the
target device's allowlist.

Manage the allowlist through the Runtime interface:

```powershell
.\scripts\project-history.ps1 project list
.\scripts\project-history.ps1 project add D:\workspaces\approved-project
.\scripts\project-history.ps1 project remove approved-project
```

The add/remove commands show the planned change and require confirmation.
`projects.json` remains human-readable, but the Runtime owns its validation and
atomic updates.

`include_auxiliary: false` indexes confirmed `docs/history/*.md` only. Set it to
`true` only when Git commits and selected project documents are approved as
experimental evidence by passing `-IncludeAuxiliary` to `project add`.

Daily commands:

```powershell
.\scripts\project-history.ps1 status
.\scripts\project-history.ps1 rebuild
.\scripts\project-history.ps1 update
.\scripts\project-history.ps1 query
.\scripts\project-history.ps1 mode lexical
.\scripts\project-history.ps1 mode hybrid
.\scripts\project-history.ps1 candidate list
```

Both `update` and `rebuild` create and validate a temporary index before atomically
replacing the current index. A failed project leaves the old index intact. Query
output always shows the active `lexical` or `hybrid` mode; mode changes never silently
downgrade and require a rebuild before querying.

Operations logs retain command type, time, duration, success, and error type for up
to seven days and 10 MB. They never store query text, retrieved content, or project
data. The interactive query prompt also keeps the query out of the PowerShell command
history. Automation may pass query text as the second argument only when its own
process-history policy is acceptable.

PowerShell Bootstrap owns Python, venv, packages, models, and download consent.
The Python `LocalHistoryRuntime` owns allowlist, mode, index, query, and operation
state. The direct Python CLI is an internal interface; normal use goes through
`project-history.ps1`.

Candidate review commands are also local-first:

```powershell
.\scripts\project-history.ps1 candidate scan approved-project
.\scripts\project-history.ps1 candidate defer <id>
.\scripts\project-history.ps1 candidate exclude <id>
.\scripts\project-history.ps1 candidate retain <id> -RecordPath <confirmed-record.md>
```

Candidate files and dispositions stay under `.local`. Retain writes a confirmed
Record only after validating it through the active index mode, then removes the local
Candidate. It does not commit or push Git.

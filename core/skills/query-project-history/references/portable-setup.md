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
├── models/
├── index.db
├── logs/
└── projects.json
```

It asks before downloading Python, FastEmbed, or the embedding model. In
non-interactive environments, downloads require `-AllowDownload`; otherwise setup
fails closed. For restricted company environments:

- Use `-Wheelhouse <path>` for approved offline Python wheels.
- Use `-PackageIndexUrl <internal-url>` for an approved internal PyPI mirror.
- Use `-ModelSource <path>` for an approved FastEmbed cache.
- Use `-PythonPath <path>` for an IT-managed or portable Python 3.11+ runtime.

Do not copy `index.db`, `projects.json`, model caches, logs, or personal project
history between personal and company devices. Clone only projectD-core, set up the
local runtime on the target device, then explicitly add approved repositories to the
target device's `projects.json`.

Example allowlist entry:

```json
{
  "schema_version": 1,
  "projects": [
    {
      "name": "approved-project",
      "path": "D:\\workspaces\\approved-project",
      "include_auxiliary": false
    }
  ]
}
```

`include_auxiliary: false` indexes confirmed `docs/history/*.md` only. Set it to
`true` only when Git commits and selected project documents are approved as
experimental evidence.

Daily commands:

```powershell
.\scripts\project-history.ps1 status
.\scripts\project-history.ps1 rebuild
.\scripts\project-history.ps1 update
.\scripts\project-history.ps1 query
```

`update` refreshes every currently allowlisted project. Use `rebuild` after removing
or renaming an allowlist entry so stale records are pruned.

Operations logs retain command type, time, duration, success, and error type for up
to seven days and 10 MB. They never store query text, retrieved content, or project
data. The interactive query prompt also keeps the query out of the PowerShell command
history. Automation may pass query text as the second argument only when its own
process-history policy is acceptable.

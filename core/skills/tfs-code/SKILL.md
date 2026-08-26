---
name: tfs-code
description: Search, read, inspect, or clone F25B TFS code; not for builds, pipelines, or work items.
---

# F25B TFS source access

Use this Skill only for finding, reading, and cloning source code from the internal
Azure DevOps Server 2022 environment.

## Endpoints

- TFS: `http://f25b-tfs.f25b.com:8080/tfs/DefaultCollection`
- Hound: `https://hound-tfs-hound.apps.okd.f25b.com`
- SSH: `ssh://f25b-tfs.f25b.com`

These endpoints require the F25B network or VPN.

## Safety boundaries

1. Prefer read-only operations. Do not create, update, or delete TFS state with this
   Skill.
2. Route build, release, pipeline, and work-item tasks to the separate `tfs` Skill.
   If it is unavailable, tell the user instead of improvising write-capable API calls.
3. Never print, log, commit, or place a PAT in a URL or process argument.
4. Use the legacy token file `%USERPROFILE%\.tfs-claude-pat` only for compatibility.
   It must contain a code-scoped PAT. Check its existence without reading it aloud.
5. Prefer the organization-trusted CA for Hound. If certificate trust is unavailable,
   allow TLS verification bypass only for the exact Hound hostname above and disclose
   that limitation in the result.
6. Before cloning, confirm the destination and avoid overwriting an existing path.

## Choose the access path

| Need | Access path |
|---|---|
| Find a symbol across repositories | Hound; no PAT required |
| Read a known file, tree, ref, commit, or PR | TFS REST; code-scoped PAT required |
| Work with a repository locally | `git clone` over SSH or HTTP |

### Cross-repository search

Use `GET /api/v1/search` on Hound. URL-encode regex and filename filters.

- `q`: RE2 regex
- `i`: `fosho` for case-insensitive search
- `files`: filename regex, such as `\.cs$`
- `repos`: comma-separated Hound repository keys, or `*`
- `rng`: range such as `:20` or `20:40`
- `stats`: `true` to include timing and hit counts

Hound repository keys use `<Project>_<Repo>_<branch>`. Resolve the authoritative
TFS URL from `GET /api/v1/repos` before using REST or clone.

Example for the exact internal Hound host:

```powershell
$tfsHound = 'https://hound-tfs-hound.apps.okd.f25b.com'
curl.exe -s "$tfsHound/api/v1/search?q=GetCustomerBalance&i=fosho&files=%5C.cs%24&repos=*&rng=:20&stats=true"
```

If the corporate CA is unavailable and the request fails only because of the known
self-signed certificate, retry this exact host with `curl.exe -sk` and report that
certificate verification was bypassed.

### Read through TFS REST

Before REST access, test for the token file:

```powershell
$tfsPatPath = Join-Path $env:USERPROFILE '.tfs-claude-pat'
Test-Path -LiteralPath $tfsPatPath -PathType Leaf
```

If it is absent, stop and ask the user to create a Code (read) PAT from TFS:
Profile → Security → Personal Access Tokens → New Token. On PowerShell, save it
without a trailing newline using `Set-Content -NoNewline`. Never ask the user to
paste the token into chat.

Build the Basic authorization header in memory so the PAT is not placed in a command
argument:

```powershell
$tfsPatPath = Join-Path $env:USERPROFILE '.tfs-claude-pat'
$tfsCodePat = [IO.File]::ReadAllText($tfsPatPath).TrimEnd("`r", "`n")
$tfsBasic = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(":" + $tfsCodePat)
)
$tfsHeaders = @{ Authorization = "Basic $tfsBasic" }
```

Do not preflight the PAT. Make the requested read operation and treat only HTTP
401/403 as expired or insufficient authorization. Ask the user to replace the file
when that occurs. Use API version `7.0`; some resources reject `7.1`.

Read [references/tfs-rest.md](references/tfs-rest.md) when constructing REST URLs or
interpreting Hound responses.

### Clone

Prefer SSH when the user's public key is already registered in TFS:

```powershell
git clone ssh://f25b-tfs.f25b.com:22/tfs/DefaultCollection/BOT/_git/BOT_MI
```

Otherwise use the repository's HTTP `remoteUrl` and Git Credential Manager or an
interactive credential prompt:

```powershell
git clone http://f25b-tfs.f25b.com:8080/tfs/DefaultCollection/BOT/_git/BOT_MI
```

Never embed the PAT in the clone URL because it persists in shell history and
`.git/config`.

## Source

Adapted for projectD from F25B Skill Vault `ali/tfs-code`, version 2, published by
楊俊翰 on 2026-07-13. The archive SHA-256 is
`4a304fbb6af8d00e4598ed33ac0cab97e303e7db3819c49f770b953ef2b31e57`.
The source declares no SPDX license; treat it as F25B-internal content and do not
redistribute it externally.

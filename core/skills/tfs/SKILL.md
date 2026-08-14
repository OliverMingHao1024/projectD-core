---
name: tfs
description: Query and manage build, release, deployment, pipeline, work item, repository or pull-request metadata, and service endpoints on the F25B internal TFS / Azure DevOps Server. Use when the user asks about build or deployment status, release history, pipeline definitions or triggers, work items, service endpoints, or explicitly requests a state-changing TFS action. Require fresh confirmation before every queue, release, deploy, work-item mutation, pipeline change, or service-endpoint change. Use tfs-code instead for finding, reading, or cloning source code.
---

# F25B TFS operations

Operate against the internal Azure DevOps Server 2022 instance:

`http://f25b-tfs.f25b.com:8080/tfs/DefaultCollection`

Require the F25B network or VPN. Use the REST API rather than assuming the cloud
`dev.azure.com` endpoints or `az pipelines` behavior.

## Scope

Use this Skill for:

- build definitions, runs, logs, and queueing;
- release definitions, releases, environments, and deployments;
- pipeline configuration and triggers;
- work-item queries and mutations;
- repository or pull-request metadata, but not source contents;
- service endpoints.

Use `tfs-code` for cross-repository search, source-file reading, and clone. If that
Skill is unavailable, tell the user instead of inventing a source-access workflow.

## Safety boundaries

1. Treat the TFS instance as shared infrastructure. Read-only GET requests and WIQL
   queries may proceed when they are clearly within the user's requested scope.
2. Before every state-changing request, show the exact project, resource, action,
   important payload fields, and expected effect. Obtain fresh user confirmation.
3. Never carry approval from one mutation to another. Queueing a build does not
   authorize a release or deployment.
4. For a deployment, identify the target environment and whether it is production.
   Do not infer an environment, branch, build, release, or definition ID.
5. Do not create, update, or delete service endpoints unless the user explicitly
   names the endpoint and approves the exact change. Never expose endpoint secrets.
6. Never print, log, commit, or place a PAT in a URL or process argument.
7. Prefer a dedicated PAT with the minimum scopes supported by the requested APIs.
   The legacy compatibility file `%USERPROFILE%\.tfs-pat-all` contains an all-scopes
   PAT and must be treated as a high-privilege secret.
8. Name F25B Git development branches
   `dev/{developer}/{feature-code}/{change-summary}`. Use the established developer
   identifier, preserve the project's feature-code casing, and write the summary in
   lowercase kebab-case; for example,
   `dev/oliver/TA23001/asian-asset-financing`. Inspect existing remote branches before
   creating one, and do not fall back to a generic `feature/` prefix.

## API versions

- Use `api-version=7.0` by default. Some resources reject `7.1`.
- Use `api-version=4.1-preview.3` for release APIs on this server.
- Retry unexpectedly missing fields with the versions above before concluding that
  data is absent. Older versions can silently omit fields such as build triggers.

## Authentication

Check for the token without displaying it:

```powershell
$tfsPatPath = Join-Path $env:USERPROFILE '.tfs-pat-all'
Test-Path -LiteralPath $tfsPatPath -PathType Leaf
```

If absent, stop and ask the user to create a dedicated TFS PAT. Use only the scopes
needed for the intended task when the server supports them. If the installed server
requires the legacy all-scopes token, have the user save it to `.tfs-pat-all` without
a trailing newline. Never ask the user to paste a token into chat.

Build the Basic authorization header in memory:

```powershell
$tfsPatPath = Join-Path $env:USERPROFILE '.tfs-pat-all'
$tfsPat = [IO.File]::ReadAllText($tfsPatPath).TrimEnd("`r", "`n")
$tfsBasic = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(":" + $tfsPat)
)
$tfsHeaders = @{ Authorization = "Basic $tfsBasic" }
$tfsBase = 'http://f25b-tfs.f25b.com:8080/tfs/DefaultCollection'
```

Do not preflight the PAT. Make the requested operation and treat HTTP 401/403 as an
expired token, an insufficient scope, or the wrong token. Ask the user to replace or
correct it without exposing the value.

## Workflow

1. Resolve project, definition, release, environment, work-item, or endpoint IDs
   through read-only calls. Do not guess identifiers.
2. For status questions, gather only the data needed and report timestamps, result,
   reason, source build, environment status, and task issues when relevant.
3. For a requested mutation, prepare the exact endpoint and payload without sending
   it, then request confirmation using the safety boundaries above.
4. After confirmation, send one mutation and read back its resulting state. Report
   the returned ID, status, and any server error without retrying a mutation blindly.

Read [references/read-operations.md](references/read-operations.md) for query endpoints
and release-status traversal. Read
[references/write-operations.md](references/write-operations.md) only after the user
requests a mutation; it contains payload templates, not standing authorization.

## Source

Adapted for projectD from F25B Skill Vault `ch-chang/tfs`, version 2, published by
張智翔 on 2026-07-15 and forked from `ali/tfs`. The archive SHA-256 is
`e71a7cff7bd9942a8039950ae0d7a19d2140795957c2a9dfa4a6ca39aef50711`.
The source declares no SPDX license; treat it as F25B-internal content and do not
redistribute it externally.

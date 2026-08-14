# Read-only TFS operations

Build `$tfsHeaders` and `$tfsBase` as described in `SKILL.md`. Use only the project
and identifiers supported by the user's request or resolved through prior reads.

## Builds

```powershell
Invoke-RestMethod -Headers $tfsHeaders -Uri "$tfsBase/{project}/_apis/build/builds?definitions={defId}&`$top=5&api-version=7.0"
Invoke-RestMethod -Headers $tfsHeaders -Uri "$tfsBase/{project}/_apis/build/definitions?api-version=7.0"
```

For builds, report `id`, `buildNumber`, `status`, `result`, `reason`, `sourceBranch`,
`queueTime`, `startTime`, and `finishTime` when present.

## Releases and deployments

```powershell
Invoke-RestMethod -Headers $tfsHeaders -Uri "$tfsBase/{project}/_apis/release/releases?definitionId={defId}&`$top=5&api-version=4.1-preview.3"
Invoke-RestMethod -Headers $tfsHeaders -Uri "$tfsBase/{project}/_apis/release/releases/{releaseId}?api-version=4.1-preview.3"
Invoke-RestMethod -Headers $tfsHeaders -Uri "$tfsBase/{project}/_apis/release/definitions?api-version=4.1-preview.3"
```

To answer whether a deployment ran or succeeded:

1. List recent releases for the definition.
2. Select the relevant release using time and `reason`; do not assume the newest is
   the user's intended run when multiple candidates exist.
3. Fetch that release by ID because list responses can omit environments.
4. Traverse `environments[].deploySteps[].releaseDeployPhases[].deploymentJobs[].tasks[]`.
5. Report each relevant task's `status` and `issues`.
6. Resolve the deployed build from `artifacts[].definitionReference.version`, where
   `id` is the build ID and `name` is the build number.

## Work items

Read work items by ID:

```powershell
Invoke-RestMethod -Headers $tfsHeaders -Uri "$tfsBase/_apis/wit/workitems?ids=123,124&api-version=7.0"
```

WIQL uses POST but is read-only in effect:

```powershell
$tfsWiql = @{
    query = "SELECT [System.Id] FROM WorkItems WHERE [System.State] = 'Active'"
} | ConvertTo-Json
Invoke-RestMethod `
    -Headers $tfsHeaders `
    -Uri "$tfsBase/{project}/_apis/wit/wiql?api-version=7.0" `
    -Method Post `
    -ContentType 'application/json' `
    -Body $tfsWiql
```

Do not generalize WIQL's read-only POST exception to other POST endpoints.

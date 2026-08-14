# State-changing TFS operations

These templates do not authorize execution. Before every request, follow the
confirmation gate in `SKILL.md`, including exact project, target, payload, and effect.

## Queue a build

```powershell
$tfsBuildBody = @{
    definition = @{ id = {defId} }
    sourceBranch = 'refs/heads/main'
} | ConvertTo-Json -Depth 4
Invoke-RestMethod `
    -Headers $tfsHeaders `
    -Uri "$tfsBase/{project}/_apis/build/builds?api-version=7.0" `
    -Method Post `
    -ContentType 'application/json' `
    -Body $tfsBuildBody
```

Confirm the definition ID, source branch, parameters, and expected downstream
triggers. After queueing, read back the returned build ID and status.

## Create a release

```powershell
$tfsReleaseBody = @{
    definitionId = {defId}
    description = '...'
} | ConvertTo-Json
Invoke-RestMethod `
    -Headers $tfsHeaders `
    -Uri "$tfsBase/{project}/_apis/release/releases?api-version=4.1-preview.3" `
    -Method Post `
    -ContentType 'application/json' `
    -Body $tfsReleaseBody
```

Creating a release does not authorize deploying it. Obtain separate confirmation
for each target environment.

## Update a work item

```powershell
$tfsPatch = @(
    @{ op = 'add'; path = '/fields/System.State'; value = 'Resolved' }
) | ConvertTo-Json
Invoke-RestMethod `
    -Headers $tfsHeaders `
    -Uri "$tfsBase/_apis/wit/workitems/{id}?api-version=7.0" `
    -Method Patch `
    -ContentType 'application/json-patch+json' `
    -Body $tfsPatch
```

Show the user the work-item ID and every patch operation before confirmation. Never
delete a work item or service endpoint unless the user explicitly requests that exact
destructive action and confirms its impact.

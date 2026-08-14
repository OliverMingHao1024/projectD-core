# TFS and Hound reference

## Hound

List indexed repositories:

```powershell
$tfsHound = 'https://hound-tfs-hound.apps.okd.f25b.com'
curl.exe -s "$tfsHound/api/v1/repos"
```

Search results are grouped by repository under `Results`. Each hit includes
`Filename`, `Matches[].Line`, `LineNumber`, `Before`, and `After`.

## TFS REST

Set the base URL after building `$tfsHeaders` as described in `SKILL.md`:

```powershell
$tfsBase = 'http://f25b-tfs.f25b.com:8080/tfs/DefaultCollection'
```

Use only read operations:

```powershell
Invoke-RestMethod -Headers $tfsHeaders -Uri "$tfsBase/_apis/projects?api-version=7.0"
Invoke-RestMethod -Headers $tfsHeaders -Uri "$tfsBase/_apis/git/repositories?api-version=7.0"
Invoke-RestMethod -Headers $tfsHeaders -Uri "$tfsBase/{project}/_apis/git/repositories/{repo}/refs?api-version=7.0"
Invoke-RestMethod -Headers $tfsHeaders -Uri "$tfsBase/{project}/_apis/git/repositories/{repo}/items?path=/&recursionLevel=Full&api-version=7.0"
Invoke-RestMethod -Headers $tfsHeaders -Uri "$tfsBase/{project}/_apis/git/repositories/{repo}/items?path=/src/Foo.cs&api-version=7.0&`$format=text"
Invoke-RestMethod -Headers $tfsHeaders -Uri "$tfsBase/{project}/_apis/git/repositories/{repo}/commits?api-version=7.0"
Invoke-RestMethod -Headers $tfsHeaders -Uri "$tfsBase/{project}/_apis/git/repositories/{repo}/pullrequests?api-version=7.0"
```

TFS code search is a read-like POST endpoint and is an acceptable fallback when
Hound cannot serve the request:

```powershell
$tfsSearchBody = @{
    searchText = 'GetCustomerBalance'
    '$top' = 20
} | ConvertTo-Json
Invoke-RestMethod `
    -Headers $tfsHeaders `
    -Uri "$tfsBase/_apis/search/codesearchresults?api-version=4.1-preview.1" `
    -Method Post `
    -ContentType 'application/json' `
    -Body $tfsSearchBody
```

Do not reuse this exception for any state-changing POST endpoint.

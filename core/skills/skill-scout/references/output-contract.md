# Output Contract

The script writes one JSON object to stdout:

```json
{
  "schema_version": 1,
  "mode": "source",
  "request": "https://github.com/owner/repo/tree/main/skills/example",
  "queries": [],
  "expanded_scope": false,
  "staged": false,
  "candidates": [],
  "rejections": []
}
```

## Invariants

- `mode` is `source` or `capability`.
- `queries` contains at most three entries.
- `candidates` contains at most `MaxCandidates`, which is constrained to 1–3.
- `expanded_scope` and `staged` are always `false`; this script is read-only.
- Every candidate includes repository, source path, pinned commit, SPDX license,
  Skill name and description, content digest, dependency hints, executable-file
  indicators, relevance, and cross-agent risks.
- A rejection includes the source identity and one or more hard-gate reasons.

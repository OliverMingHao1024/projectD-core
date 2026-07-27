---
description: 定向尋找或審查 GitHub Skill；不廣掃、不自動 staging 或收錄。
argument-hint: "<功能需求> | --source <GitHub Skill URL> [--max-candidates 1..3]"
allowed-tools: ["Bash", "Read", "Grep", "Glob"]
---

# /skill-scout

Use the canonical `skill-scout` Skill. Pass `$ARGUMENTS` as either:

- a capability requirement; or
- `--source <GitHub Skill URL or owner/repo/path>`.

If arguments are empty or ambiguous, ask one narrowing question. Reject legacy
`--stars` and `--updated-within` flags with the current usage; do not silently run
the retired broad scan.

Keep this command read-only. Never stage, execute candidate code, adopt a Skill, or
search for alternatives to an ineligible exact source without separate user
confirmation.

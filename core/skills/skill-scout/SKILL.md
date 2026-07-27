---
name: skill-scout
description: Find or inspect a specific GitHub-hosted Agent Skill through a bounded, evidence-based, read-only workflow. Use when the user asks to locate a Skill for a named capability, supplies a GitHub Skill URL or repository path for review, or wants up to three verified candidates without broad ecosystem scanning.
---

# Skill Scout

Keep discovery targeted. Accept exactly one of:

- a capability requirement;
- an exact GitHub Skill URL or `owner/repo/path`.

If neither is supplied, ask what the user wants. Do not run a default scan.

## Exact source

Run:

```powershell
pwsh -File scripts/skill-scout.ps1 -Source "<GitHub URL or owner/repo/path>"
```

Inspect only the requested Skill and required dependency paths. If it is ineligible,
report why and ask before searching for alternatives.

## Capability search

Clarify an ambiguous capability before searching. Formulate at most three precise
GitHub code-search queries, then run:

```powershell
pwsh -File scripts/skill-scout.ps1 `
  -Capability "<requirement>" `
  -Query "<query 1>","<query 2>" `
  -MaxCandidates 3
```

Stop after three eligible candidates. Do not broaden keywords or use Web sources
unless GitHub yields no eligible result and the user approves expanding the search.
Articles and awesome-lists are leads, never candidates.

## Hard gates

Require:

- an accessible `SKILL.md` with portable `name` and `description`;
- a clear SPDX license;
- a pinned commit and source path;
- all required dependencies present or included for separate review.

Never execute candidate scripts, hooks, installers, or downloaded code. Treat
stars as supporting evidence, not the primary rank.

## Output and staging

The script emits normalized JSON and never writes staging. Explain at most three
candidates using direct-fit evidence, source/path/commit, license, dependencies,
projectD overlap or conflict, and cross-agent adaptation cost.

Only after the user selects a candidate, propose staging it as:

```text
packs/_staging/<owner>-<repo>--<source-path>/
├─ upstream/   # immutable pinned snapshot
├─ adapted/    # projectD candidate
└─ SOURCE.md
```

Obtain explicit confirmation before creating staging content. Never adopt or update
a CanonicalSkill in this workflow without a separate confirmation.

Use `skill-update-check` for upstream updates; do not scan adopted Skills here.

Read [output-contract.md](references/output-contract.md) when implementing or
validating integrations with the script.

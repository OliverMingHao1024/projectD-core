---
name: skill-update-check
description: Compare pinned digests to find upstream changes in adopted GitHub Skills and identify those needing re-review.
---

# Skill Update Check

Run the bundled script:

```powershell
pwsh -File scripts/skill-update-check.ps1
```

Optionally limit the check:

```powershell
pwsh -File scripts/skill-update-check.ps1 -CandidateId "<registry id>"
```

Read `vault/governance/skill-registry.json`, inspect only candidates with
`lifecycle_status: adopted`, and compare the current upstream path digest with the
stored digest.

Report `unchanged`, `update-available`, `skipped`, or `error`. A provider without
an update adapter, such as the internal Skill Vault, is `skipped` rather than sent
through the GitHub inspector. Do not modify the registry,
CanonicalSkills, staging, decision records, or upstream content. Never execute
candidate scripts.

When updates exist, show the old and new commit/digest and propose a separate
static review. Adoption remains a user-confirmed workflow.

# Contributing

This is a personally maintained, private repository (see `LICENSE`). It is not
open to external contributions, but this document records the actual
development workflow for future-me and any explicitly invited collaborator.

## Setup

```powershell
git clone https://github.com/OliverMingHao1024/projectD-core.git
cd projectD-core
pwsh -File scripts/setup.ps1 -Mode Check   # read-only wiring check
pwsh -File scripts/setup.ps1               # wire into Claude Code / Codex
```

See `README.md` for what setup does and how to uninstall/relocate.

## Running checks locally

```powershell
# Portable repository consistency gate (skill catalog, frontmatter, wiring)
pwsh -File scripts/projectd-check.ps1

# Same, with the governance eval layers included
pwsh -File scripts/projectd-check.ps1 -GovernanceEvals

# Individual contract tests
pwsh -File scripts/tests/<name>.contract.ps1

# Python-side contract wrappers
python -m pytest tests/
```

Optional pre-push hook (local-only, no network, no file mutation):

```powershell
pwsh -File scripts/governance-hooks.ps1 -Mode Install
```

## Style

- PowerShell scripts: prefer explicit, read-only checks by default; anything
  that mutates state must be opt-in via an explicit flag (see existing
  `scripts/*.ps1` for the pattern).
- Markdown: canonical Skill content lives only under `core/skills/` and
  `packs/*`; do not fork copies elsewhere.
- Governance rule changes: route through `vault/governance/` per
  `vault/governance/INDEX.md`, not by editing `core/constitution/rules.md`
  casually — that file is the L0 constitution.

## Before opening a PR

1. Run `pwsh -File scripts/projectd-check.ps1 -GovernanceEvals` locally.
2. Make sure `.github/workflows/governance-check.yml`'s jobs (`secret-scan`,
   `repository-governance`) would pass — CI runs both on every PR.
3. Keep commits scoped; this repo uses PR merges into `master` (see
   `git log --merges` for the existing pattern), not direct pushes to
   `master`.

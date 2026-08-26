# Changelog

All notable changes to this repository are recorded here going forward.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).
This repo has no external consumers, so semantic versioning is used as an
internal baseline marker, not a compatibility promise.

## [Unreleased]

## [0.1.0] - 2026-08-26

Initial tagged baseline. Prior history (2026-07-24 onward, ~90 commits / 31
merged PRs) established the current architecture — L0 constitution, vault
governance, `core/skills` + `packs/*`, the governance eval/CI contract suite,
and the ADRs under `docs/adr/`. See `git log` and `docs/adr/` for the detailed
record; this entry marks the first point release rather than re-deriving a
per-commit history.

Added at this tag:
- `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`, `CODEOWNERS`
- CI: secret scanning (TruffleHog), pinned `actions/checkout`/`actions/setup-python`
  SHAs, Python lint (ruff) and coverage reporting for `tests/`
- ADR numbering fix: `0001-targeted-skill-intake.md` renumbered to `0016`
  (collided with the earlier `0001-separate-project-history-lifecycle.md`)

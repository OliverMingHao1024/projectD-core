# Changelog

All notable changes to this repository are recorded here going forward.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).
This repo has no external consumers, so semantic versioning is used as an
internal baseline marker, not a compatibility promise.

## [Unreleased]

### Added
- `core/mods/statusbar`: Claude Code mod drawing a status bar above the prompt (model, folder and
  git branch, context %, 5h / 7d plan usage, tokens, session cost), Apple-style capsules on desktop.
- `core/mods/open-todos`: Claude Code mod with a side pane of open todos and active sessions across
  every local session, grouped by project (`/todos`).
- `statusbar`: dark capsule style, shortcut buttons (`/compact`, `/grilling`) on row two, and per-repo
  branch capsules on their own row when the folder is a workspace root (e.g. a TFS root) rather than a repo.
- `open-todos`: project colour spine, status palette, per-todo `Chat` button, and
  `~/.claude/open-todos-ignore.txt` to hide projects.
- Global wiring links each `core/mods/<name>` into `~/.claude/mods/<name>` (junction).
- `implement`: strict verification evidence rules (#108).
- Governance: skill catalog coverage check and stale vault-doc memory removed (#110); subagents,
  tool search, host UI and `git -C` reads allowed, plus local evidence pruning (#111);
  Claude hooks skipped for pure Read/Glob/Grep (#112); hook path speedup, prune schedule,
  init trim and timeout fix (#113).
- `open-todos`: reads desktop step lists and adds done buttons (#114).

> Entries after 0.1.0 are abridged from PR titles; `git log` is authoritative.

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

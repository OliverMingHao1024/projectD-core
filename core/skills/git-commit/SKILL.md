---
name: git-commit
description: Write a Conventional Commits message from intended staged changes; use when asked to commit.
---

# Git Commit

Commit only what the user intends, with a message that explains why.

## 1. Inspect what is staged

Run `git diff --staged`. If nothing is staged, ask which files to stage. Never use
`git add -A` or `git add .` in a dirty worktree unless the user explicitly approves
every included change; stage named paths instead.

## 2. Read the diff

- Find the primary intent: feature, fix, refactor, test, docs, or chore.
- Find the affected scope: module, component, Skill, or package name.
- Note any breaking change.

## 3. Write the message

```
<type>(<scope>): <short description>

<body: what changed and why, wrapped at 72 characters>

<footer: BREAKING CHANGE: <description>, or Closes #<issue>>
```

- `type`: `feat`, `fix`, `refactor`, `test`, `docs`, or `chore`.
- Title line at most 72 characters, in imperative mood ("add", not "added").
- The body explains the problem and the reason, not a file list.
- Follow the repository's recent commit style when it differs from this.

## 4. Confirm, then commit

Show the proposed message. Run `git commit` only after the user approves it or has
already asked for the commit in this request. Do not push unless separately asked.

## Source

Moved from the retired `oai-core/shared-skills` into projectD.

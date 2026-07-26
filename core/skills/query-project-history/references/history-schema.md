# Project history schema

Store confirmed records at `<project>/docs/history/YYYY-MM-DD-slug.md`.

```markdown
---
project: intentype
date: 2026-07-27
type: bug
status: accepted
technologies: [Python, Windows]
commits: [c5aece8]
supersedes: []
verified_by: [pytest tests/test_application.py]
---

# Return to the control panel from settings

## Context
Why the work happened.

## Symptom or goal
What was observed or intended.

## Attempts
Each attempted route and its outcome. Mark failed routes explicitly.

## Root cause
The verified cause, or `unknown`.

## Resolution
The adopted result, if any.

## Verification
Commands, tests, or observations that support the result.

## Applicability
Where this lesson applies and where it does not.
```

Allowed statuses are `accepted`, `rejected`, `failed`, `superseded`, and
`experimental`. A retrospective candidate remains `experimental` until a human
confirms both the content and final status.

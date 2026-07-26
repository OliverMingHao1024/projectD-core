# Project history schema

Store confirmed records at `<project>/docs/history/YYYY-MM-DD-slug.md`.
Store unconfirmed `HistoryCandidate` files only under the ignored local runtime
directory. Never commit them or include them in the formal index. A retained
Candidate becomes a `HistoryRecord`; a deferred Candidate remains local; an excluded
Candidate is deleted and leaves only a content-free local `CandidateDisposition`.

```markdown
---
project: intentype
date: 2026-07-27
type: bug
status: accepted
evidence_level: verified
technologies: [Python, Windows]
commits: [c5aece8]
supersedes: []
verified_by: [pytest tests/test_application.py]
---

# Return to the control panel from settings

## Context
Why the work happened. Use `unknown` when the reason cannot be established.

## Symptom or goal
What was observed or intended.

## Attempts
Each attempted route and its outcome. Mark failed routes explicitly.
Do not invent attempts that are absent from evidence.

## Root cause
The verified cause, or `unknown`.

## Resolution
The adopted result, if any.

## Verification
Commands, tests, or observations that support the result.

## Applicability
Where this lesson applies and where it does not.
```

Formal Record statuses are `accepted`, `rejected`, `failed`, and `superseded`.
A retrospective Candidate is always `experimental` until a human confirms both the
content and final Record status.

Evidence levels:

- `verified`: directly supported by source, diff, tests, documents, or tool output.
- `user-confirmed`: explicitly confirmed by the user without durable project evidence.
- `inferred`: reasoned from available clues; candidate-only, never a formal fact.
- `unknown`: insufficient evidence.

Apply the level to each material claim when levels differ within one record. Never
upgrade `inferred` or `unknown` merely because the candidate was retained.
The frontmatter value summarizes the central rationale. When individual claims differ,
prefix them inline, for example `[verified]`, `[user-confirmed]`, `[inferred]`, or
`[unknown]`.

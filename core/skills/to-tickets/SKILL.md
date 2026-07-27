---
name: to-tickets
description: Break an approved plan, specification, issue, or settled conversation into dependency-aware tracer-bullet tickets. Use when the user wants executable vertical slices, acceptance criteria, blocking edges, or a reviewed ticket breakdown before publishing work to a local or external tracker.
---

# To Tickets

Turn approved scope into tickets that fresh agents can complete independently.
Do not use tickets to reopen product discovery.

## Process

1. Read the supplied plan, spec, issue, conversation, glossary, ADRs, and relevant
   repository context. Fetch referenced issue bodies and comments when access is
   available.
2. Draft narrow vertical slices. Each ticket must:
   - deliver a complete, demoable or independently verifiable behavior;
   - fit one fresh agent context;
   - cross the necessary layers instead of isolating one technical layer;
   - state observable acceptance criteria;
   - name only genuine blockers.
3. Put enabling prefactors first only when they make later slices independently
   viable. For a mechanical change with a wide blast radius, use expand–migrate–
   contract tickets instead of forcing an artificial vertical slice.
4. Present the numbered breakdown with title, blocked-by edges, delivered
   behavior, and acceptance criteria. Ask whether its granularity and dependency
   graph are correct; revise until approved.
5. Ask where to publish. Do not create files, issues, labels, links, or tracker
   relationships before explicit confirmation of the batch and destination.
6. Publish blockers before dependents. Use native blocking relationships when
   the configured tracker supports them; otherwise record `Blocked by` in each
   ticket. Never close or modify a parent issue unless separately requested.

## Ticket template

```markdown
# <Ticket title>

## What to deliver
<The end-to-end behavior this ticket makes work.>

## Acceptance criteria
- [ ] <Externally verifiable result>

## Blocked by
- <Ticket title/link, or "None — ready now">

## References
- <Parent spec, ADR, issue, or prototype>
```

Avoid implementation checklists, stale file paths, and code snippets. A ticket
describes a verifiable outcome; the implementing agent determines the internal
steps from current repository evidence.

## Source

Adapted for cross-agent use from
<https://github.com/mattpocock/skills/tree/ed37663cc5fbef691ddfecd080dff42f7e7e350d/skills/engineering/to-tickets>.
Licensed under MIT; see [LICENSE](LICENSE). The adaptation removes
`setup-matt-pocock-skills` and Claude-specific metadata, uses project-defined
tracker conventions, and requires approval before local or external writes.

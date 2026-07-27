---
name: to-spec
description: Synthesize an already-discussed feature, plan, or decision into a reviewable product and engineering specification without restarting discovery. Use when the user asks to turn settled conversation context into a spec or PRD, optionally for later publication to the project's issue tracker.
---

# To Spec

Synthesize what is already known. Do not restart an interview or invent missing
decisions. Mark material gaps as assumptions or open questions.

## Process

1. Read the relevant conversation, repository state, domain glossary, ADRs, and
   referenced artifacts. Prefer project terminology.
2. Identify the highest stable seam at which the behavior can be verified.
   Prefer existing seams. Ask only when an unresolved seam would materially
   change scope or acceptance criteria.
3. Draft the specification in the conversation using the template below.
   Reference existing artifacts instead of duplicating them.
4. Ask the user to approve the draft and choose its destination. Do not create a
   file, issue, label, or other shared-state artifact before that confirmation.
5. When publication is approved, follow the repository's documented tracker or
   specification convention. If none exists, propose a local Markdown path.

## Specification template

```markdown
# <Feature or change>

## Problem
<The problem from the user's perspective.>

## Outcome
<The observable result and who benefits.>

## User stories
1. As a <role>, I want <capability>, so that <benefit>.

## Acceptance criteria
- [ ] <Externally observable behavior>

## Implementation decisions
- <Confirmed modules, interfaces, contracts, schema, or interactions>

## Testing decisions
- <Verification seam, important scenarios, and relevant prior art>

## Out of scope
- <Explicit boundary>

## Assumptions and open questions
- <Anything not yet confirmed>

## References
- <Existing ADR, issue, plan, prototype, or source>
```

Keep the specification durable: describe behavior and decisions, not transient
file paths or full implementation snippets. Include a small decision-rich
snippet only when prose would be less precise, and identify its source.

## Source

Adapted for cross-agent use from
<https://github.com/mattpocock/skills/tree/ed37663cc5fbef691ddfecd080dff42f7e7e350d/skills/engineering/to-spec>.
Licensed under MIT; see [LICENSE](LICENSE). The adaptation removes
`setup-matt-pocock-skills` and Claude-specific metadata, makes tracker support
project-defined, preserves settled gaps as explicit assumptions, and requires
approval before any file or tracker write.

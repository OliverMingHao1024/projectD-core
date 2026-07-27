---
name: grill-with-docs
description: Stress-test a plan or design through a relentless one-question-at-a-time interview while proposing confirmed domain glossary and architectural-decision updates. Use when the user wants to grill an idea and preserve the resulting terminology or decisions as project documentation.
---

# Grill with Docs

Run the `grilling` Skill workflow and apply the `domain-modeling` Skill throughout
the interview.

Ask one question at a time. Challenge ambiguous terminology, test decisions with
concrete scenarios, and distinguish domain language from implementation detail.

When a domain term becomes clear, propose the exact `CONTEXT.md` change inline.
When a decision meets the `domain-modeling` ADR threshold, propose the exact ADR
content. Never create or edit either document until the user confirms that specific
write. Continue the interview after each accepted or rejected proposal.

Do not implement the plan or design being discussed unless the user separately
authorizes implementation after shared understanding is reached.

If either dependency Skill is unavailable, state which workflow is missing and
perform the same behavior directly rather than silently dropping the interview or
documentation discipline.

## Source

Adapted for cross-agent discovery from
<https://github.com/mattpocock/skills/tree/ed37663cc5fbef691ddfecd080dff42f7e7e350d/skills/engineering/grill-with-docs>.
Licensed under MIT; see [LICENSE](LICENSE). The adapted version replaces
tool-specific slash-command syntax and model-invocation metadata, and preserves
projectD-core's confirm-before-write rule for glossary and ADR updates.

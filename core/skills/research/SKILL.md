---
name: research
description: Investigate a question against high-trust primary sources and capture the findings as a Markdown file in the repo. Use when the user wants a topic researched, docs or API facts gathered, or reading legwork delegated to a background agent.
---

If the current agent supports spinning up a background/sub-agent, delegate the research to one so you keep working while it reads; otherwise perform the research directly yourself and say so rather than claiming it ran in the background.

The job:

1. Investigate the question against **primary sources** — official docs, source code, specs, first-party APIs — not a secondary write-up of them. Follow every claim back to the source that owns it.
2. Draft the findings as a single Markdown file, citing each claim's source.
3. Propose where to save it — matching the repo's existing convention for such notes if one exists, otherwise a sensible location you name — and confirm before writing.

## Source

Adapted for cross-agent discovery from
<https://github.com/mattpocock/skills/tree/ed37663cc5fbef691ddfecd080dff42f7e7e350d/skills/engineering/research>.
Licensed under MIT; see [LICENSE](LICENSE). The adapted version makes the background-agent
delegation conditional on the current agent supporting it, and gates the findings file
write behind explicit confirmation of its location.

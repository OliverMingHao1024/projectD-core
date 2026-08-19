---
name: research
description: Investigate a question against high-trust primary sources and capture the findings as a Markdown file in the repo, or compare several candidates against objective criteria. Use when the user wants a topic researched, docs or API facts gathered, several options compared before picking one, or reading legwork delegated to a background agent.
---

If the current agent supports spinning up a background/sub-agent, delegate the research to one so you keep working while it reads; otherwise perform the research directly yourself and say so rather than claiming it ran in the background.

The job:

1. Investigate the question against **primary sources** — official docs, source code, specs, first-party APIs — not a secondary write-up of them. Follow every claim back to the source that owns it.
2. Draft the findings as a single Markdown file, citing each claim's source.
3. Propose where to save it — matching the repo's existing convention for such notes if one exists, otherwise a sensible location you name — and confirm before writing.

## Comparing candidates

When the question is "which of these options is worth using" rather than "what are the facts about X":

1. Define the objective comparison fields before reading any candidate in depth — e.g. for software: stars, forks, last commit date, license, open-issue activity; for other domains, whatever fields actually distinguish "worth it" from "not." Decide this once, up front, so every candidate is judged the same way.
2. Verify each candidate against those fields individually — a search result's title or description is a lead, not a fact. Query the authoritative source directly (e.g. `gh api repos/<org>/<repo>` for GitHub projects) before recommending or ruling out anything.
3. Keep verified facts and impressions from search snippets separate, the same way as any other judgment call: say plainly which is which.
4. Rank or group by the verified fields, not by how prominently a candidate appeared in search results — a well-marketed but stale candidate ranks below a less visible but active one.
5. When a candidate that looked promising from its description doesn't hold up once verified, say so plainly and drop it, rather than keeping it on the list out of inertia.

## Source

Adapted for cross-agent discovery from
<https://github.com/mattpocock/skills/tree/ed37663cc5fbef691ddfecd080dff42f7e7e350d/skills/engineering/research>.
Licensed under MIT; see [LICENSE](LICENSE). The adapted version makes the background-agent
delegation conditional on the current agent supporting it, gates the findings file write
behind explicit confirmation of its location, and adds the "Comparing candidates" flow
above, which is not part of the upstream skill.

---
name: handoff
description: Write a handoff document for another agent, only when asked.
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work.

Propose the filename `handoff-<slug>.md` (slug from the topic) and where to write it, and confirm before writing. Default to `.local/handoff/` when the repository ignores `.local/`; otherwise default to the temporary directory of the user's OS (`$TMPDIR`, else `/tmp`; `%TEMP%` on Windows). Never write the document into tracked source paths. Report the path once written.

Include a "suggested skills" section in the document, naming which skills the next agent should call the Skill tool for.

Do not duplicate content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.

## Source

Adapted for cross-agent discovery from
<https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/productivity/handoff>.
Licensed under MIT; see [LICENSE](LICENSE). The adaptation drops the non-portable
`disable-model-invocation` and `argument-hint` frontmatter keys (the invocation
restriction moves into the description and `agents/openai.yaml`) and gates the file
write behind explicit user confirmation of filename and location instead of writing
to the OS temporary directory unprompted.

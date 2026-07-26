# Local project-history retrieval PoC

## Goal

Let a person ask natural-language questions across `intentype` and `photoFilter` and
retrieve verified solutions, failed routes, and decisions with traceable evidence.

## Boundaries

- Keep source records in each repository; keep only a rebuildable index in core.
- Use confirmed `docs/history/*.md` as primary evidence.
- Optionally index Git commits and selected specs, dev logs, architecture, and
  verification documents as auxiliary evidence.
- Exclude `tickets_hunter`, conversations, secrets, dependencies, build outputs, and
  raw logs.
- Run SQLite, FTS5, embedding, and vector scoring locally.

## Acceptance

Use 20 reviewed questions. For each question, an expected record must appear in the
top five. Results must preserve evidence status and source identity. Hybrid search
must improve meaning-based paraphrases over the lexical baseline before adoption.

---
name: query-project-history
description: Search verified project decisions, debugging history, failed attempts, and superseded solutions across local repositories. Use when the user asks whether a similar problem happened before, why a technical choice was made, what approaches failed, how a prior issue was fixed, or wants evidence-backed cross-project history retrieval.
---

# Query Project History

Use the bundled CLI to retrieve local project history. Treat source Markdown and Git
objects as evidence; treat the SQLite index as disposable derived data.

## Query

1. Locate the index path from the repository configuration or ask for it.
2. Run:

```powershell
python scripts/history_search.py query --db <index.db> --query "<question>"
```

3. Read the returned source files or commits before drawing a conclusion.
4. Label every approach by its recorded status. Never present `failed`, `rejected`,
   `superseded`, or `experimental` evidence as the current recommendation.
5. Cite the project, source path or commit, and status in the answer. State when no
   verified record answers the question.

## Index

Index confirmed history as primary evidence:

```powershell
python scripts/history_search.py index --db <index.db> --project <repo>
```

Add Git and selected project documents only when the user wants auxiliary evidence:

```powershell
python scripts/history_search.py index --db <index.db> --project <repo> --include-auxiliary
```

Use `--mode lexical` for a dependency-free baseline. Hybrid indexing requires the
local-only FastEmbed dependency from `scripts/requirements.txt` and a locally
cached/downloaded model. Add `--mode hybrid` to both `index` and `query`. Use
`--project <name>` when the question targets one repository. Do not claim hybrid
retrieval succeeded when the embedding backend is unavailable.

## Capture a history candidate

After a meaningful debugging or design session, draft a candidate using
[history-schema.md](references/history-schema.md). Show it to the user and write it
to `<project>/docs/history/YYYY-MM-DD-slug.md` only after explicit confirmation.
Do not save full conversations, secrets, raw runtime logs, dependencies, or build
artifacts.

Use `candidates` only to propose retrospective records. Git evidence cannot prove
uncommitted failed attempts:

```powershell
python scripts/history_search.py candidates --project <repo> --limit 10
```

## Evaluate

Compare lexical and hybrid retrieval against the same reviewed question set. Require
at least one expected source in the top five, evidence links for conclusions, and no
status confusion. Do not promote the PoC to shared infrastructure if it does not
materially improve semantic paraphrase queries.

```powershell
python scripts/history_search.py evaluate --db <index.db> `
  --benchmark <benchmark.json> --mode hybrid --output <results.json>
```

---
name: improve-codebase-architecture
description: Scan for deepening opportunities, present a visual report, and grill the selected architecture change.
---

# Improve Codebase Architecture

Surface architectural friction and propose **deepening opportunities** — refactors that turn shallow modules into deep ones. The aim is testability and AI-navigability.

This command is _informed_ by the project's domain model and built on a shared design vocabulary:

- Run the `codebase-design` Skill for the architecture vocabulary (**module**, **interface**, **depth**, **seam**, **adapter**, **leverage**, **locality**) and its principles (the deletion test, "the interface is the test surface", "one adapter = hypothetical seam, two = real"). Use these terms exactly in every suggestion — don't drift into "component," "service," "API," or "boundary." If `codebase-design` is not available in the current agent, explain that dependency instead of silently dropping the vocabulary.
- If the project has a domain glossary, the domain language in `CONTEXT.md` gives names to good seams; ADRs in `docs/adr/` record decisions this command should not re-litigate. Neither file is assumed to exist — treat their absence as normal, not a gap to fill unprompted.

## Process

### 1. Explore

**Scope before you scan — YAGNI.** Deepening a module pays off by making future changes to it easier, so put extra weight on the parts of the codebase that have recently changed. Decide *where* to look before you look:

- If the user named a direction — a module, a subsystem, a pain point — take it, and skip the inference below.
- Otherwise, walk back a good stretch of the commit history (`git log --oneline`) to find the codebase's hot spots — the files and areas that keep coming up — and let those paths pull your attention first. If the changes are scattered with no clear hot spot, widen the net.

Read the project's domain glossary (`CONTEXT.md`), if one exists, and any ADRs in the area you're touching first.

Then walk the codebase — using a read-only exploration sub-agent if the current agent supports one, otherwise reading the area directly yourself. Don't follow rigid heuristics — explore organically and note where you experience friction:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow** — interface nearly as complex as the implementation?
- Where have pure functions been extracted just for testability, but the real bugs hide in how they're called (no **locality**)?
- Where do tightly-coupled modules leak across their seams?
- Which parts of the codebase are untested, or hard to test through their current interface?

Apply the **deletion test** to anything you suspect is shallow: would deleting it concentrate complexity, or just move it? A "yes, concentrates" is the signal you want.

### 2. Present candidates as an HTML report

Write a self-contained HTML file to the OS temp directory so nothing lands in the repo. Resolve the temp dir from `$TMPDIR`/`$TMP`, falling back to `/tmp` on Linux/macOS or a Windows temp path on Windows, and write to `<tmpdir>/architecture-review-<timestamp>.html` so each run gets a fresh file. Open it for the user — `xdg-open <path>` on Linux, `open <path>` on macOS, `cmd //c start "" <path>` from Git Bash or `Start-Process <path>` from PowerShell on Windows — and tell them the absolute path regardless of whether the open command succeeds.

The report uses **Tailwind via CDN** for layout and styling, and **Mermaid via CDN** for diagrams where a graph/flow/sequence reliably communicates the structure — both are a default choice, not a mandate; fall back to plain CSS/inline SVG if the environment has no network access when the report is opened. Mix Mermaid with hand-crafted CSS/SVG visuals — use Mermaid when relationships are graph-shaped (call graphs, dependencies, sequences), and hand-built divs/SVG when you want something more editorial (mass diagrams, cross-sections, collapse animations). Each candidate gets a **before/after visualisation**. Be visual. Report copy is written in the user's language; keep the architecture vocabulary terms themselves (module, seam, adapter, etc.) untranslated so they stay recognisable.

For each candidate, render a card with:

- **Files** — which files/modules are involved
- **Problem** — why the current architecture is causing friction
- **Solution** — plain English description of what would change
- **Benefits** — explained in terms of locality and leverage, and how tests would improve
- **Before / After diagram** — side-by-side, custom-drawn, illustrating the shallowness and the deepening
- **Recommendation strength** — one of `Strong`, `Worth exploring`, `Speculative`, rendered as a badge

End the report with a **Top recommendation** section: which candidate you'd tackle first and why.

**Use CONTEXT.md vocabulary for the domain (when it exists), and the `codebase-design` vocabulary for the architecture.** If `CONTEXT.md` defines "Order," talk about "the Order intake module" — not "the FooBarHandler," and not "the Order service."

**ADR conflicts**: if a candidate contradicts an existing ADR, only surface it when the friction is real enough to warrant revisiting the ADR. Mark it clearly in the card (e.g. a warning callout: _"contradicts ADR-0007 — but worth reopening because…"_). Don't list every theoretical refactor an ADR forbids.

See [HTML-REPORT.md](HTML-REPORT.md) for the full HTML scaffold, diagram patterns, and styling guidance.

Do NOT propose interfaces yet. After the file is written, ask the user: "Which of these would you like to explore?"

### 3. Grilling loop

Once the user picks a candidate, run the `grilling` Skill to walk the decision tree with them — constraints, dependencies, the shape of the deepened module, what sits behind the seam, what tests survive. If `grilling` is not available in the current agent, explain that dependency and walk the same decision tree yourself, one question at a time.

As decisions crystallize, use the `domain-modeling` Skill to keep the domain model current — every `CONTEXT.md`/ADR write below goes through that skill's confirm-then-write discipline, never inline:

- **Naming a deepened module after a concept not in `CONTEXT.md`?** Propose adding the term to `CONTEXT.md` (create the file, with confirmation, if it doesn't exist).
- **Sharpening a fuzzy term during the conversation?** Propose the `CONTEXT.md` update right there.
- **User rejects the candidate with a load-bearing reason?** Offer an ADR, framed as: _"Want me to record this as an ADR so future architecture reviews don't re-suggest it?"_ Only offer when the reason would actually be needed by a future explorer to avoid re-suggesting the same thing — skip ephemeral reasons ("not worth it right now") and self-evident ones.
- **Want to explore alternative interfaces for the deepened module?** Run the `codebase-design` Skill and use its design-it-twice pattern.

## Source

Adapted for cross-agent discovery from
<https://github.com/mattpocock/skills/tree/ed37663cc5fbef691ddfecd080dff42f7e7e350d/skills/engineering/improve-codebase-architecture>.
Licensed under MIT; see [LICENSE](LICENSE). The adapted version de-Claude-ifies the
exploration sub-agent step, fixes the Windows `start`/`%TEMP%` commands for Git
Bash/PowerShell, makes `CONTEXT.md`/ADR/`docs/adr/` optional rather than assumed, routes
every domain-model write through `domain-modeling`'s confirm-then-write discipline, adds
a no-network fallback for the Tailwind/Mermaid CDNs, and states the report's output
language separately from its architecture-vocabulary terms.

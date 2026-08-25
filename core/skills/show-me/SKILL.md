---
name: show-me
description: Explain a concept, code path, state change, comparison, or system relationship visually when the user asks to see it or when a compact visual would materially improve understanding. Do not use for ordinary answers already clear in brief prose.
---

# Show Me

Make the current topic easier to understand with the smallest useful visual. Lead with
the visual or its conclusion, keep adjacent prose brief, and follow higher-priority user,
project, accessibility, and output rules.

## Decide Whether to Visualize

Visualize when the user explicitly asks to see, map, diagram, or visually compare
something, or when prose obscures an important relationship, sequence, hierarchy, or
state change.

Skip the visual when one fact, one step, a short list, or a compact paragraph is already
clear. Choose one primary visual. Combine formats only when each answers a distinct part
of the question.

## Choose the Smallest Shape

| Need | Preferred shape |
|---|---|
| Logic or an algorithm | Pseudocode |
| Runtime order and ownership | Call tree |
| Actual UI composition and state | Component tree |
| File responsibility or refactor layout | Shallow file tree |
| Exact mappings or repeated comparisons | Table |
| Events or state changing over time | Timeline or sequence diagram |
| A known shape changing | Diff |
| Three or more connected relationships | Mermaid graph or sequence |
| Dense layout, responsive UI, or a comparison that text cannot carry | Focused HTML artifact |

Use `component` only for real UI framework components. Otherwise preserve the project's
established architectural vocabulary for modules, interfaces, seams, adapters, states,
and ownership.

## Keep the Visual Faithful

- Use verified labels, paths, calls, props, states, and data from the conversation or
  inspected source. Mark assumptions and omit invented detail.
- Keep trees shallow and diagrams focused on the relationship needed for the answer.
- Label an illustrative change `Proposed — not applied`. Do not present a conceptual
  diff, path, or state as an actual repository modification.
- Show a complete block when most of it is new, omitted context would hide ownership or
  order, or the user needs a copyable target shape.
- Put each visual beside the short explanation it supports.
- If Mermaid or rich rendering is unavailable, preserve the meaning with a fenced text
  tree, table, or pseudocode instead of dropping the visual.

## Create HTML Only When It Earns Its Cost

Use one self-contained HTML file only when a text diagram, table, or Mermaid view would
be materially harder to understand.

1. Use real product labels and, when available, the product's own color, type, spacing,
   and component tokens. Support desktop, mobile, keyboard use, zoom, and reduced motion.
2. Keep the artifact useful without network access. Inline essential CSS and SVG; if an
   optional external asset fails, retain a clear HTML/CSS fallback.
3. Write temporary output to an environment-approved temporary or visualization
   directory with a unique `show-me-<description>-<id>.html` name. Do not write it into
   the repository unless the user requests a repository artifact or the task already
   defines one there.
4. Open it through the host environment's preview capability. If a shell opener is
   necessary, use `Start-Process` on Windows, `open` on macOS, or `xdg-open` on Linux;
   never assume Bash or macOS.
5. Return the absolute artifact path and state whether the preview opened. Do not publish
   or send the artifact externally without separate authorization.

## Source

Adapted from HumanLayer `show-me` version 1.0.1 at commit
`6ab9013a10c28f5046f7f999549cd5328a0b30d7` under the MIT License. The adaptation
narrows activation, makes artifact handling cross-platform and repository-safe, adds
offline and accessibility fallbacks, and distinguishes proposed visuals from applied
changes.

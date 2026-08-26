---
name: codegraph
description: Explore symbols, callers, dependencies, and paths through an existing CodeGraph; never install it implicitly.
---

# CodeGraph

Use CodeGraph as an external, local code-knowledge-graph tool. Keep its
installation and version guidance in the upstream project:
<https://github.com/colbymchenry/codegraph>.

## Check availability

1. Confirm the repository root contains `.codegraph/`.
2. Confirm a CodeGraph MCP tool or CLI is available.
3. If either check fails, skip CodeGraph and use normal repository search.
4. Never install, initialize, or rebuild an index unless the user explicitly
   requests it.

## Explore

- Prefer the exposed CodeGraph MCP exploration tool when available.
- Otherwise use `codegraph explore "<symbol or question>"`.
- Use CodeGraph for symbol locations, callers, dependencies, and code paths.
- Verify important conclusions against source files before reporting them.

## Safety

- Treat index output as derived evidence that may be stale.
- Do not expose indexed secrets or unrelated source content.
- Follow the repository's existing approval and tool-use rules.

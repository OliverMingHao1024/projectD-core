# Architecture Decision Records

This directory preserves why projectD-core adopted its current governance
boundaries. ADRs are historical decisions; active specifications describe the
current executable contract.

## Current decisions

| ADR | Domain | Status | Current authority |
|---|---|---|---|
| [0001](0001-separate-project-history-lifecycle.md) — Separate project-history lifecycle | Project history | accepted | ADR |
| [0002](0002-split-history-bootstrap-and-runtime.md) — Split bootstrap and runtime | Project history | accepted | ADR |
| [0003](0003-manage-governance-wiring-as-desired-state.md) — Desired-state governance wiring | Governance wiring | accepted | ADR |
| [0005](0005-separate-knowledge-workspace.md) — Separate KnowledgeWorkspace | Knowledge workspace | accepted | [KnowledgeWorkspace core boundary](../specs/knowledge-workspace-boundary.md) |
| [0010](0010-bound-local-security-scans-and-verify-downloads.md) — Bound scans and verify downloads | Supply-chain security | accepted | ADR |
| [0015](0015-isolate-ai-agent-mcp-server-execution.md) — Isolate privileged MCP execution | DevSpace security | amended by 0017 | [DevSpace security boundary](../specs/devspace-security-boundary.md) |
| [0016](0016-targeted-skill-intake.md) — Govern external Skill intake | Skill governance | accepted | ADR |
| [0017](0017-allow-anonymous-devtunnel-for-isolated-devspace-on-personal-registrations.md) — Narrow tunnel exception | DevSpace security | accepted; amends 0015 | [DevSpace security boundary](../specs/devspace-security-boundary.md) |

KnowledgeWorkspace-owned ADRs are maintained in
[projectD-knowledge](https://github.com/OliverMingHao1024/projectD-knowledge/tree/main/adr).
Their former core copies remain available through Git history and the knowledge
repository; they are not current projectD-core decisions.

## Reading rules

1. Read the current specification first when an ADR names
   `current_authority`.
2. Read an amended ADR together with every ADR listed in `amended_by`.
3. ADRs explain decisions and trade-offs; they do not prove that the current
   machine or deployment satisfies the decision.
4. Runtime readiness requires current checks and evidence, not merely an
   accepted ADR.
5. New decisions receive a new number. Do not rewrite historical rationale to
   make a later exception appear to have always existed.

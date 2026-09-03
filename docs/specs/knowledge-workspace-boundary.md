# KnowledgeWorkspace Core Boundary

- Status: active
- Workspace owner: `projectD-knowledge`
- Core owner: `projectD-core`

## Purpose

Keep `projectD-core` limited to provider-neutral AI governance and adapters while
the separate KnowledgeWorkspace owns concrete knowledge schemas, validators,
fixtures, indexes, FeaturePages, research, and workspace-specific ADRs.

## Ownership

| `projectD-core` owns | `projectD-knowledge` owns |
|---|---|
| workspace registry and allowlist rules | manifest and FeaturePage schemas |
| supported schema-version policy | schema validators and fixtures |
| lifecycle and security minimums | generated and verified indexes |
| fail-closed query/lint adapter | candidate and verified FeaturePages |
| adapter contracts and tests | workspace specification and ADRs |
| repository/source authority boundary | research and historical archives |

## Core invariants

1. Source repositories remain the authority for code, tests, product decisions,
   and observable behavior.
2. Knowledge content is a wayfinder, not implementation authority.
3. Core must not duplicate workspace schemas, validators, fixtures, indexes, or
   FeaturePages.
4. Query adapters validate the supported schema version and fail closed on
   unknown versions, stale source evidence, unknown repositories, or unsafe paths.
5. Workspace registration is explicit; adapters never scan sibling repositories
   or filesystem roots to discover sources.
6. Candidate generation never promotes content. Promotion requires deterministic
   validation, owner review, and a pull request in `projectD-knowledge`.
7. Session startup does not preload the KnowledgeWorkspace.

## Core implementation map

- Local registry: `.local/knowledge-workspaces.json` (Git-ignored)
- Query adapter: `scripts/knowledge-query.ps1`
- Requirement adapter: `scripts/knowledge-requirement.ps1`
- Separation decision: `docs/adr/0005-separate-knowledge-workspace.md`

## Workspace authority

- [Active specification](https://github.com/OliverMingHao1024/projectD-knowledge/blob/main/specs/external-knowledge-wiki.md)
- [Requirement source and evolution](https://github.com/OliverMingHao1024/projectD-knowledge/blob/main/specs/spec-source-and-evolution.md)
- [KnowledgeWorkspace ADRs](https://github.com/OliverMingHao1024/projectD-knowledge/tree/main/adr)
- [Research and archive](https://github.com/OliverMingHao1024/projectD-knowledge/tree/main/research)

Changes to the cross-repository ownership boundary update this contract and ADR
0005. Changes to concrete workspace behavior belong only in
`projectD-knowledge`.

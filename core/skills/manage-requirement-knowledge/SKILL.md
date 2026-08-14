---
name: manage-requirement-knowledge
description: Capture and evolve governed ProjectD requirement knowledge. Use when a user attaches a DOC or DOCX requirement, asks to formalize or adjust a requirement, or confirms that debugging changed a specification and the result should enter ProjectD-knowledge.
---

# Manage Requirement Knowledge

Orchestrate requirement intake without duplicating KnowledgeWorkspace contracts.
The repository owns schemas, templates, validators, and indexes; this Skill owns
the cross-project workflow.

## Resolve the workspace

1. Resolve projectD-core from `PROJECTD_CORE` or the current Fleet wiring.
2. Read `<core>/.local/knowledge-workspaces.json` and resolve
   `workspaces.projectd-knowledge`.
3. Read the KnowledgeWorkspace `README.md` and
   `docs/specs/spec-source-and-evolution.md` completely.
4. Fail closed when the registry or approved specification is unavailable. Never
   substitute an absolute path in committed content.

## Select one mode

- `new`: A new requirement has a DOC or DOCX source.
- `amend`: The owner wants to change an existing ConfirmedSpec.
- `debug`: A confirmed debugging result should become a DebugRecord and may
  justify a SpecAmendment.

Ask for the mode only when intent is ambiguous. Resolve the current repository
to a logical system through the registry; present the inferred system and Feature
to the owner before writing when the match is not already explicit.

## New requirement

1. Require the source document, system, Feature ID, and Requirement ID. Search
   verified FeaturePages and aliases before proposing a provisional Feature ID.
2. Run `<core>/scripts/knowledge-requirement.ps1 -Mode new ...`. Treat duplicate
   digest, unsupported DOC conversion, review markup, or missing source as a
   blocking result, not a warning to bypass.
3. Run `grill-me` one question at a time. Do not implement the business change.
4. Run `to-spec` after shared understanding. Create candidate `confirmed.md` and
   `delta.md` from the KnowledgeWorkspace templates; preserve the OriginalSpec.
5. Keep OriginalSpec, ConfirmedSpec, SpecDelta, any provisional FeaturePage, and
   the generated index in one promotion pull request.

## Requirement amendment

1. Resolve the latest verified ConfirmedSpec and Amendment chain.
2. Record only an owner-confirmed requirement change, ambiguity resolution, or
   implementation constraint. A code defect that violates the existing spec is
   not an Amendment.
3. Create the next immutable amendment revision from the workspace template,
   declare `supersedes`, and regenerate `current.md`.

## Debug record

1. Use the diagnosis evidence; do not save full chats or runtime logs.
2. Create a DebugRecord with the problem, root cause, impact, fix, verification,
   and commit or pull-request references.
3. Create a linked SpecAmendment only when the owner confirms that expected
   behavior changed.

## Validate and promote

Run the workspace validator with index generation, regenerate navigation and any
affected current view, then run the requirement contract tests. Candidate content
stays on a requirement branch; `main` contains only verified content.

Show the owner the source digest, extracted review flags, delta, validation result,
and pull-request scope. Never mark content verified, commit, push, open or merge a
promotion pull request without the corresponding explicit approval. AI output,
validator success, or review completion is not promotion authority.

## Safety invariants

- Keep original documents and conversion caches under Git-ignored `.local/`.
- Do not commit secrets, personal data, absolute local paths, or full conversations.
- Preserve immutable original revisions and fail on duplicate digest.
- Separate expected behavior from current implementation and surface stale or
  unknown evidence.
- Use repository scripts as the deterministic interface so Claude Code and Codex
  produce the same structure even when prose differs.

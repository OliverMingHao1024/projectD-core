---
name: select-frontend-capability
description: Select or review a frontend capability without locking every project to one framework, library, vendor, or author's preferences. Use when choosing or replacing UI primitives, notifications, forms, client or server state, motion, charts, virtualization, styling, accessibility infrastructure, or similar frontend dependencies in React, Angular, mixed monorepos, or other web projects.
---

# Select Frontend Capability

Choose from project evidence, not a global favorite list. Separate the stable capability requirement from the replaceable implementation.

## Priority

Apply decisions in this order:

1. User's current explicit instruction.
2. Project-local decision record.
3. Existing maintainable project dependency and convention.
4. Matching technology adapter.
5. This shared selection process.
6. External recommendations.

Do not replace a working existing solution merely to standardize projects.

## Workflow

### 1. Locate the decision scope

Identify the current workspace, app, package, and files. In a mixed monorepo, route by the affected subproject rather than the repository root.

Inspect relevant evidence such as:

- `package.json` and lockfile
- framework configuration
- existing imports and shared components
- design system and accessibility conventions
- supported browsers, SSR/runtime, bundle and licensing constraints

### 2. Define the capability

Describe the user-visible need without naming a package. Separate required behavior from optional polish.

Examples:

- "Accessible transient notifications with queued dismissal"
- "Cached server state with invalidation and request deduplication"
- "Virtualized rendering for 50,000 table rows"

### 3. Reuse before selecting

Prefer, in order:

1. No new dependency.
2. Existing project abstraction.
3. Platform or framework-native capability.
4. Existing maintainable dependency.
5. A new dependency with evidence.

### 4. Load the matching adapter

For the projectD frontend pack:

- React: read `packs/frontend-react/references/react-capabilities.md`.
- Angular: read `packs/frontend-angular/references/angular-capabilities.md`.
- Mixed repository: load only the adapter for the affected app; load both only for an actual cross-framework contract.
- Unsupported stack: apply this workflow from repository evidence and explicitly note the missing adapter.

Adapter entries are candidates with conditions, not mandatory defaults.

### 5. Decide at proportional depth

- **Small and reversible**: state the selected existing option and one-sentence reason.
- **New dependency**: compare the strongest candidate with the no-new-dependency path; cover maintenance, license, accessibility, runtime compatibility, bundle and exit cost.
- **Replacement or platform decision**: include migration scope, coexistence, rollback, ecosystem lock-in and explicit user approval before mutation.

Do not install, replace, or migrate a dependency when the request is only to analyze or recommend.

### 6. Persist stable decisions

When the choice should govern future work, propose or update a project-local decision using
`references/frontend-capability-decision.md`. Do not create decision-document bureaucracy for a
one-off, low-impact choice.

Reopen a recorded decision only when:

- requirements materially change;
- maintenance stops or security/licensing risk appears;
- the implementation becomes incompatible with the target runtime/framework;
- measured cost becomes materially disproportionate; or
- the user requests reconsideration.

## Output

Keep routine answers short. For consequential selection, report:

```text
Scope:
Capability:
Current solution:
Decision:
Evidence:
Trade-offs and exit cost:
Reconsider when:
```

Distinguish verified facts from assumptions. Verify time-sensitive package status against primary sources before recommending adoption.

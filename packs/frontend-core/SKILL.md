---
name: frontend-core
description: Framework-neutral browser UI conventions for HTML, CSS, accessibility, responsive behavior, interaction, and perceived performance. Use for any browser-facing interface work regardless of frontend framework.
---

# Frontend Core Pack

Use for browser-facing work regardless of framework. Combine with the applicable framework
and language packs when the project uses them.

## Establish the Baseline

- Inspect the design system, semantic HTML, CSS architecture, responsive behavior,
  accessibility requirements, browser support, and performance constraints.
- Identify established component boundaries, design tokens, motion conventions, and
  loading, empty, error, and offline states.
- Inspect shared browser utilities such as Lodash, including their version, loading or
  import form, type declarations, and bundler behavior.

## Rules

- Prefer semantic HTML and native browser capabilities before adding dependencies.
- Preserve existing design tokens, layout conventions, and component boundaries.
- Keep keyboard navigation, focus visibility, reduced motion, contrast, and screen-reader
  behavior explicit.
- Treat loading, empty, error, and offline states as part of the UI contract.
- Add motion only when it clarifies state or interaction and follow existing motion tokens.
- Preserve the application's existing Lodash distribution and import convention; apply
  its operations with explicit mutation, missing-value, lifecycle, and bundle semantics.
- Measure expensive rendering or asset work before optimizing.

## Verification

- Run the repository's focused UI tests, lint, type check, and production build.
- Manually verify keyboard, responsive, reduced-motion, and failure-state behavior.
- Check the affected surface in the project's supported browsers or rendering modes.

## References

- Read [lodash.md](references/lodash.md) when using Lodash for collection, object, path,
  equality, cloning, timing, or aggregation operations.
- Read [web-interface-review.md](references/web-interface-review.md) for an explicit UI audit or
  when a change materially affects forms, navigation, focus, content resilience, localization,
  hydration, media, or interactive state. Do not load the full checklist for every small UI edit.

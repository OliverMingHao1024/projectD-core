---
name: frontend-core
description: Framework-neutral HTML, CSS, browser, accessibility, and UI foundations.
---

# Frontend Core Pack

Use this pack for browser-facing work regardless of framework. Inspect the existing
design system, semantic HTML, CSS architecture, responsive behavior, accessibility
requirements, and performance constraints before selecting libraries.

## Rules

- Prefer semantic HTML and native browser capabilities before adding dependencies.
- Preserve the repository's existing design tokens, layout conventions, and component boundaries.
- Keep keyboard navigation, focus visibility, reduced motion, contrast, and screen-reader behavior explicit.
- Treat loading, empty, error, and offline states as part of the UI contract.
- Use CSS transitions and existing motion tokens first; add animation only when it clarifies state or interaction.
- Measure expensive rendering or asset work before optimizing.

## Verification

- Run the project's existing lint, type-check, and focused UI tests when available.
- Manually verify keyboard, responsive, reduced-motion, and failure states for changed surfaces.

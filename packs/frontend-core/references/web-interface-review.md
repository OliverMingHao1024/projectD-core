# Web Interface Review

Use this reference for a focused interface audit. Apply only checks relevant to the changed
surface, its supported environments, and its actual interaction model.

## Establish Review Evidence

- Inspect the product brief, design system, supported browsers, rendering model, localization
  requirements, and changed files before reporting findings.
- Distinguish a confirmed defect from a missing verification or test. Do not present preference
  as a defect.
- Cite the smallest useful file and line location. Explain user impact and a proportionate remedy.
- Review representative loading, empty, error, success, disabled, long-content, and narrow-screen
  states when the surface can reach them.

## Accessibility and Semantics

- Prefer native elements and landmarks that match the behavior. Verify accessible names for
  icon-only and custom controls.
- Verify logical keyboard order, visible focus, focus that is not obscured by sticky content, and
  appropriate focus movement for dialogs, menus, and route changes.
- Associate labels, instructions, and errors with form controls. Announce asynchronous status or
  validation changes only when users need the update.
- Check heading structure, page language, meaningful alternative text, decorative-image handling,
  text scaling, contrast, and a non-drag alternative when those concerns apply.

## Interaction and Forms

- Use links for navigation and buttons for actions. Preserve standard browser behaviors such as
  open-in-new-tab, back navigation, and form submission when practical.
- Choose `type`, `name`, `autocomplete`, input mode, and validation from the field's meaning and
  the desired password-manager behavior. Do not disable paste.
- Make labels and intended hit targets operable. Do not add pointer cursors or enlarged targets
  indiscriminately when the platform convention or nearby layout would make them misleading.
- Prevent accidental duplicate submissions for asynchronous or consequential actions, and show
  progress without erasing the user's input.
- Place validation feedback where it can be discovered. Move focus or provide an error summary
  when the form and error pattern require it.
- Warn about unsaved changes only when navigation would lose meaningful user work. Choose confirm,
  undo, or immediate action according to reversibility and consequence.

## Navigation and State

- Make state shareable in the URL when users need to bookmark, reload, compare, or send it. Keep
  ephemeral interaction state local when URL synchronization adds no user value.
- Verify deep links, back/forward behavior, scroll restoration, and focus restoration for the
  routes and overlays the surface actually uses.
- Ensure dialogs and popovers have clear dismissal, focus containment where appropriate, and a
  usable result when JavaScript or network work is delayed.

## Content and Responsive Layout

- Test realistic empty, long, localized, user-generated, and error content. Ensure flexible
  children can shrink, text can wrap, and truncation does not hide required information without
  another way to access it.
- Verify that fixed and sticky regions do not cover content, validation messages, anchors, or
  focused controls. Account for safe areas where the target devices require it.
- Check layout at content-driven breakpoints and with browser zoom or increased text size; do not
  treat one set of device widths as proof of responsiveness.
- Preserve content hierarchy and task order across viewport changes rather than only rearranging
  boxes until they fit.

## Motion and Feedback

- Require a purpose for motion: continuity, spatial explanation, feedback, progress, or attention
  prioritization. Remove decorative motion that competes with frequent tasks.
- Respect reduced-motion preferences with an intentional alternative. Ensure frequent or direct
  interactions remain interruptible and do not queue stale animation.
- Gate hover-only behavior to devices that support hover, and provide keyboard or touch access to
  the same information.
- Animate properties deliberately and measure suspected jank. Do not prescribe universal easing
  curves or fixed durations without project or interaction evidence.

## Media and Perceived Performance

- Reserve image and media space to avoid layout shifts. Provide meaningful alternatives,
  captions, controls, pause behavior, and loading strategy according to the content.
- Prioritize only genuinely critical above-the-fold assets; defer work that is not needed for the
  first useful state.
- Investigate layout thrashing, long tasks, excessive rendering, and large collections with
  measurements. Choose virtualization, memoization, or preloading from evidence rather than a
  fixed item-count rule.
- Verify font loading and fallbacks preserve legibility and layout. Preload selectively.

## Localization and Rendering Integrity

- Use locale-aware formatting for user-facing dates, times, numbers, and currencies. Keep machine
  formats for data exchange and identifiers.
- Test text expansion, bidirectional layout when supported, and strings assembled from translated
  fragments. Do not infer language solely from location.
- For server-rendered interfaces, inspect time, randomness, browser-only APIs, persisted state,
  and locale differences for hydration mismatches. Suppress a mismatch only after its cause is
  understood and intentionally accepted.

## Report Findings

Use one row per actionable finding:

| Severity | Location | Evidence | User impact | Recommendation |
| --- | --- | --- | --- | --- |

Prioritize functional access, data loss, misleading behavior, and severe performance problems
over visual polish. Report style-only issues only when they violate the brief, design system, or a
confirmed project convention.

Do not impose title casing, component libraries, pointer behavior, URL state, animation timing,
virtualization thresholds, or copy punctuation as universal rules.

## Attribution

This checklist was independently rewritten for projectD after reviewing
[`vercel-labs/web-interface-guidelines`](https://github.com/vercel-labs/web-interface-guidelines)
at commit `e3d624ba66d021785b00b200ed506f47af9a46ae` (MIT License, Copyright Vercel Labs).
The upstream checklist is a research source; project requirements and observed evidence remain
authoritative.

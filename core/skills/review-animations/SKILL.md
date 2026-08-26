---
name: review-animations
description: Review motion purpose, continuity, interruptibility, accessibility, fit, and measured performance.
---

# Review Animations

Review only the requested motion scope. Do not implement fixes or expand into unrelated feature review unless asked.

## Establish Context

Before judging:

- identify the affected app and technology stack;
- inspect existing motion tokens, libraries and component conventions;
- determine interaction purpose and frequency;
- check accessibility and browser/device requirements;
- respect documented project decisions.

## Review Areas

### Purpose and restraint

- Require a user-facing reason for motion.
- Judge intensity from frequency, product character and input method.
- Recommend deletion or simplification when motion adds delay or distraction.

### Continuity and interaction

- Check coherent entry and exit paths.
- Check origin relative to triggers for anchored surfaces.
- For rapid or gesture-controlled states, verify smooth interruption from the current presented value.
- Check pointer cancellation, cleanup, keyboard activation and non-gesture alternatives.

### Timing and implementation

- Compare timing and easing to existing project tokens and the component's distance and purpose.
- Do not enforce a universal duration ceiling; flag outliers with evidence.
- For velocity handoff, verify the installed library's physical-spring or inertia API.
- Treat CSS, WAAPI and motion libraries as choices with trade-offs, not automatic performance guarantees.

### Performance

- Prefer compositor-friendly properties as an initial strategy.
- Require measurement for layout animation, filters, blur, shadows and large translucent layers.
- Cite observed jank, profiler evidence or a clear rendering risk; distinguish fact from hypothesis.

### Accessibility

- Preserve semantic state without relying on motion.
- Honor reduced-motion behavior and retain necessary feedback.
- Gate hover-only motion by input capability.
- Verify focus, contrast and meaningful keyboard behavior.

## Output

List actionable findings first:

| Severity | Location | Current behavior | Recommended change | Evidence |
| --- | --- | --- | --- | --- |

Then give one verdict:

- **Block**: a confirmed usability, accessibility, safety, continuity or material performance regression.
- **Approve with notes**: no blocker, but measurable or contextual follow-up remains.
- **Approve**: motion fits the project and relevant fallbacks are covered.

When feel cannot be determined from code, require slow-motion playback, frame-by-frame inspection or representative-device testing.

## Attribution

Partially adapted from `emilkowalski/skills`, `review-animations`, commit
`e695d13cb298db0f46d5ef05be2ad13fa12908a6`, MIT License.

---
name: design-engineering
description: Design or review polished web interfaces using evidence-based interaction, motion, component, typography, accessibility, and perceived-performance principles. Use when improving UI craft, interaction feedback, component behavior, motion cohesion, or the small implementation details that affect how an interface feels.
---

# Design Engineering

Improve interface quality without imposing a universal visual style or dependency set. Existing product goals, brand, design system, accessibility requirements and technology choices come first.

## Workflow

1. Identify the affected app, framework, users, interaction frequency and existing design tokens.
2. Confirm the user-facing problem from code, screenshots, recordings or reproducible behavior.
3. Decide whether the highest-leverage improvement is deletion, simplification, clearer hierarchy, better feedback, motion, or performance work.
4. Reuse existing components, tokens and dependencies.
5. Validate with keyboard, pointer, touch, reduced motion and representative devices as applicable.

## Principles

- Every visual or motion detail should serve comprehension, feedback, continuity, accessibility or product character.
- Frequent interactions generally benefit from restrained, responsive feedback; rare moments have a larger delight budget.
- Match duration and easing to the component, distance, input and existing motion system. Avoid universal numeric laws.
- Anchored surfaces should preserve a clear spatial relationship with their trigger when the component API supports it.
- Gesture-controlled motion should remain interruptible and clean up pointer state on cancellation.
- Use physical springs only through the verified API of an existing library when velocity continuity matters.
- Prefer compositor-friendly properties as a starting point, then profile representative devices. CSS, WAAPI and JavaScript libraries are implementation choices, not performance guarantees.
- Treat blur, filters, large translucent surfaces and layout animation as effects requiring measurement and fallbacks.
- Support semantic controls, keyboard operation, focus, readable contrast and reduced-motion alternatives.
- Do not use motion as a substitute for destructive-action confirmation.

## Component Review

Check:

- Does the component respond immediately without committing an action too early?
- Does state remain understandable without animation?
- Are entry and exit paths coherent?
- Can rapid or reversed input interrupt motion without a jump?
- Are hover behaviors gated to devices that support hover?
- Are loading, error, empty and completion states explicit?
- Does typography preserve hierarchy and user text scaling?
- Are dependencies and APIs already established by the project?

When reviewing code, use a compact findings table:

| Location | Current behavior | Suggested change | Evidence |
| --- | --- | --- | --- |

Use exact values only when they come from project tokens, verified library documentation, or measured prototypes. If feel cannot be established from code, require a slow-motion, frame-by-frame or real-device check rather than guessing.

## Attribution

Partially adapted from `emilkowalski/skills`, `emil-design-eng`, commit
`e695d13cb298db0f46d5ef05be2ad13fa12908a6`, MIT License.

---
name: apple-design
description: Apply Apple-inspired web interaction and motion, including gestures, sheets, springs, and reduced motion.
---

# Apple Design

Build interfaces that respond immediately, preserve spatial continuity, and remain under user control. Treat Apple conventions as design references, not universal styling rules.

## Boundaries

- Follow the target project's existing framework, component library, design tokens, brand, accessibility rules, and browser matrix.
- Do not install or replace a motion or UI library unless the user explicitly requests it.
- Do not make an interface look Apple-like merely because this skill triggered. Use glass, springs, system fonts, and platform conventions only when they fit the product.
- Treat concrete API syntax and browser support as version-sensitive. Verify against the installed library and current primary documentation before implementation.
- Keep destructive actions safe: pointer-down may provide visual feedback, but activation still requires an accessible click or keyboard path and any required confirmation.

## Workflow

1. Identify the interaction's purpose, frequency, platform, input modes, and existing design language.
2. Decide whether motion improves feedback, spatial understanding, state legibility, or continuity. Remove decorative motion from frequent or information-dense workflows.
3. Preserve direct manipulation: track gestures continuously, respect the grab offset, and keep motion interruptible.
4. Reuse existing easing, duration, spring, component, and accessibility conventions.
5. Implement keyboard, pointer, touch, focus, cancellation, and reduced-motion behavior together.
6. Validate on supported browsers and real input devices. Inspect complex motion in slow motion or frame by frame.

## Interaction Principles

### Immediate response

- Show press feedback on pointer-down without committing the action early.
- Avoid artificial delay on the input path.
- During drag, update the controlled element continuously rather than animating only after release.

### Interruptibility and velocity

- Gesture-controlled motion must start from the element's current presented value and accept retargeting without a jump.
- Carry release velocity into the settling animation when the selected library supports it.
- For Motion or another spring library, distinguish duration-based springs from physical springs. Do not assume `duration` plus `bounce` preserves gesture velocity.
- When velocity continuity matters, use the library's verified physical-spring API (`stiffness`, `damping`, `mass`, and supported velocity input) or an equivalent already present in the project.
- Project momentum only when it helps the user predict the destination; clamp it to safe, reachable targets.

### Spatial consistency

- Enter and exit along compatible paths.
- Anchor menus, popovers, and sheets to their trigger or edge. Centered modals are a valid exception.
- Use progressive resistance at drag boundaries instead of a hard visual stop when the interaction is meant to feel physical.
- Keep background interaction blocked when required by modality, safety, focus management, or duplicate-submission prevention. Interruptibility applies to the animated control, not to bypassing these safeguards.

## Pointer and Gesture Implementation

When implementing native Pointer Events:

- Use pointer capture only for an active gesture.
- Handle `pointerup`, `pointercancel`, and `lostpointercapture`; release state and listeners on every exit path.
- Preserve the initial grab offset.
- Use a small movement threshold before committing to drag.
- Set `touch-action` narrowly for the controlled axis or gesture. Do not disable browser scrolling or zooming more broadly than necessary.
- Provide keyboard and non-gesture alternatives.

In React or Angular, keep listeners and mutable gesture state within the framework lifecycle. Clean up listeners, observers, animation frames, and captures when the component is destroyed or dependencies change.

## Motion Selection

Prefer the smallest mechanism that satisfies the interaction:

| Need | Preferred mechanism |
| --- | --- |
| Hover, color, or simple predetermined transition | Existing CSS transition and design tokens |
| Entry styling with supported browsers | CSS transition and `@starting-style` |
| Programmatic predetermined sequence | Web Animations API or existing project abstraction |
| Interruptible drag, swipe, or retargetable motion | Existing physical-spring or gesture library |
| Reduced-motion alternative | Short opacity or color transition; remove large spatial movement |

Animate `transform` and `opacity` by default. Treat layout properties, `filter`, blur, shadows, and large translucent surfaces as potentially expensive; profile them on representative devices before accepting them.

Use `will-change` only as a temporary, narrowly scoped optimization after measurement shows it helps. Remove it when the animation is idle.

## Materials and Depth

Translucency can communicate hierarchy, but it is optional:

- Provide an opaque, high-contrast fallback before using `backdrop-filter`.
- Gate enhanced effects with `@supports` when the supported browser matrix requires it.
- Verify text contrast against changing backgrounds.
- Avoid stacked translucent layers that reduce legibility.
- Do not animate blur radius by default; profile any exception.
- Check stacking contexts and backdrop roots when applying opacity, transforms, filters, or `will-change` to ancestors.

## Typography

- Use size-appropriate tracking and line height; large display text may need tighter tracking than body text.
- Build hierarchy with size, weight, spacing, and contrast as a system.
- Respect user text scaling and allow layouts to reflow.
- Prefer the project's established type system. Use a platform system font only when it fits the product and existing brand.

## Accessibility and Progressive Enhancement

- Support semantic controls, keyboard operation, visible focus, logical focus movement, and a non-gesture path.
- Honor `prefers-reduced-motion`; replace large movement, parallax, and elastic overshoot with gentler state feedback.
- Treat `prefers-reduced-transparency` as progressive enhancement because support is not universal. Always retain a readable fallback.
- Honor higher-contrast preferences where supported and test contrast independently.
- Treat vibration and web haptics as optional enhancements. Feature-detect them, never make functionality depend on them, and do not promise frame-perfect synchronization across devices.
- Avoid full-viewport continuous motion, abrupt brightness changes, and motion that blocks reading or interaction.

## Review Checklist

- Does every animation have a user-facing purpose?
- Is the motion appropriate for how frequently the interaction occurs?
- Can gesture-controlled motion be interrupted without jumping?
- Does release velocity flow into a verified physical spring when needed?
- Are pointer cancellation, cleanup, keyboard input, focus, and non-gesture alternatives covered?
- Are reduced-motion and unsupported-browser fallbacks present?
- Does the implementation reuse existing project dependencies and tokens?
- Have expensive blur, filter, translucency, and layout effects been profiled?
- Does the result fit the product's brand rather than merely imitate Apple?

## Attribution

Adapted from `emilkowalski/skills`, `skills/apple-design`, retrieved from commit
`e695d13cb298db0f46d5ef05be2ad13fa12908a6` under the MIT License. The adapted
version corrects library-specific spring guidance and adds projectD lifecycle,
accessibility, progressive-enhancement, and governance boundaries.

---
name: animation-vocabulary
description: Name interface motion effects when users ask what an animation is called.
---

# Animation Vocabulary

Name the closest established term first, explain it in one sentence, and give at most two alternatives when the description is ambiguous.

## Response Format

```text
Term — concise definition.

Close alternatives:
- Term — when this is the better match.
```

Treat this glossary as a practical reference, not an authority. Use a clear synonym when terminology varies across tools, and state when no exact standard term exists.

## Core Terms

### Entry and exit

- **Fade**: appearance or disappearance through opacity.
- **Slide**: entry, exit, or movement along an axis.
- **Scale in/out**: size change used with entry or exit.
- **Reveal**: content progressively uncovered, commonly by clipping or masking.
- **Pop**: quick scale-based entry that may include restrained overshoot.

### State and layout

- **Crossfade**: one state fades out while another fades in.
- **Morph**: one shape or visual form transforms into another.
- **Shared-element transition**: the same perceived element moves and changes across views.
- **Layout animation**: a position or size change is visually bridged instead of snapping.
- **Origin-aware animation**: motion begins from the control or location that caused it.

### Timing and sequencing

- **Easing**: how velocity changes over time.
- **Stagger**: related elements start in sequence.
- **Orchestration**: coordination of multiple motion events.
- **Asymmetric timing**: entry and exit use different timings.
- **Keyframes**: explicitly defined states across an animation timeline.

### Physical interaction

- **Spring**: motion modeled with spring-like physical parameters or a perceptual approximation.
- **Momentum**: continued movement influenced by release velocity.
- **Interruptible animation**: motion that can retarget smoothly from its current presented state.
- **Rubber-banding**: increasing resistance beyond a boundary followed by return.
- **Velocity handoff**: passing gesture velocity into the settling motion when the implementation supports it.

### Interaction patterns

- **Press feedback**: immediate visual response to activation.
- **Drag**: direct manipulation following pointer or touch movement.
- **Swipe to dismiss**: gesture that removes a surface along a direction.
- **Hold to confirm**: deliberate sustained activation; it still requires accessible keyboard and non-gesture alternatives.
- **Scroll-driven animation**: progress tied to scroll position.
- **Parallax**: layers move at different rates to suggest depth.

### Rendering concepts

- **Compositing**: browser composition of rendered layers; actual acceleration depends on property, browser, element and device.
- **Jank**: visible irregularity caused by missed rendering deadlines.
- **Layout-affecting animation**: motion that may trigger layout work; it is not automatically defective but requires appropriate measurement.
- **Reduced motion**: an accessibility preference requiring less vestibular movement while preserving necessary state feedback.

Do not turn a naming answer into implementation guidance unless asked. When implementation is requested, route to the project stack and verify current APIs and browser support.

## Attribution

Partially adapted from `emilkowalski/skills`, `animation-vocabulary`, commit
`e695d13cb298db0f46d5ef05be2ad13fa12908a6`, MIT License.

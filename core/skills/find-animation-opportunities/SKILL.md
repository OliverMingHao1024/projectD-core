---
name: find-animation-opportunities
description: Perform a read-only search for interface moments that would genuinely benefit from motion, while explicitly rejecting unjustified animation. Use when a user asks what could be animated, wants an interface to feel more responsive or alive, or needs evidence-based motion opportunities without implementation.
---

# Find Animation Opportunities

Report only. Do not modify source, install libraries, or write implementation plans.

## Reconnaissance

Identify:

- affected app and framework;
- existing components, motion tokens and libraries;
- input modes and accessibility requirements;
- frequency and purpose of each candidate interaction;
- browser and device constraints.

In a monorepo, inspect the affected app rather than assuming one stack for the repository.

## Opportunity Gate

Keep a candidate only when all are satisfied:

1. **Purpose**: motion improves feedback, state legibility, spatial continuity, explanation or a genuinely rare delight moment.
2. **Frequency**: the intensity is appropriate for how often users encounter it.
3. **Function**: motion does not hinder reading, precision, keyboard flow or task completion.
4. **Feasibility**: it can reuse existing technology and provide accessible fallbacks.
5. **Evidence**: cite the current behavior at `file:line` or another inspectable artifact.

Consider:

- missing press or state feedback;
- abrupt conditional content;
- surfaces disconnected from their trigger;
- incoherent enter and exit paths;
- gestures that snap or fail to handle cancellation;
- rare success, onboarding or explanatory moments.

Do not suggest animation merely because an element can move. Destructive actions require accessible activation and confirmation independent of motion.

## Output

Return at most 5–7 high-confidence opportunities:

| # | Location | Current behavior | Purpose | Frequency | Suggested direction |
| --- | --- | --- | --- | --- | --- |

Use project tokens and existing APIs. If exact values require prototyping, say so instead of inventing universal thresholds.

Also list 2–5 rejected candidates:

- `Location` — rejected because purpose, frequency, function, accessibility, or evidence did not pass the gate.

Close with the single highest-leverage opportunity and state that implementation or plan creation requires a separate explicit request.

## Attribution

Partially adapted from `emilkowalski/skills`, `find-animation-opportunities`, commit
`e695d13cb298db0f46d5ef05be2ad13fa12908a6`, MIT License.

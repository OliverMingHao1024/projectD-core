---
name: visual-direction
description: Establish or review an evidence-based visual direction for a web interface before implementation. Use for greenfield UI art direction, redesign direction, or an interface that feels generic or visually inconsistent; do not use for narrow implementation-only fixes.
---

# Visual Direction

Turn product context into a reviewable visual direction without imposing a universal
aesthetic, framework, or component library.

## Guardrails

- Treat the user's brief, confirmed product decisions, and the project's design system as
  authoritative.
- Ground visual choices in the product, audience, use context, and surface purpose. Do not
  select a style only because it is fashionable or familiar to the implementer.
- Preserve usability, accessibility, content truth, platform conventions, and performance.
  Distinctiveness does not override them.
- Do not invent brand claims, testimonials, metrics, or production content. Label placeholders.
- Produce a direction contract by default. Do not change code, dependencies, or assets unless
  the user also requests implementation.

## Classify the Work

Choose the smallest applicable scope:

- **Refinement** preserves identity, information architecture, content, and behavior while
  improving hierarchy, consistency, and craft.
- **Redesign** preserves product truth, required content, functions, and constraints but may
  replace the visual system and composition.
- **Greenfield** establishes a new direction from product evidence and explicit assumptions.

Identify the primary mode of the surface, not the entire product:

- **Persuade**: help a visitor understand, trust, decide, or act.
- **Operate**: help a user complete recurring or consequential tasks accurately.
- **Read**: help a user comprehend and navigate information.
- **Experience**: help a visitor explore, feel, or remember a subject.

When modes overlap, name the primary mode and the secondary constraint. Familiarity and
scanability usually deserve more weight in Operate surfaces; comprehension leads Read surfaces;
Persuade and Experience surfaces can support a larger expressive budget when it serves the job.

## Gather Evidence

Inspect or establish:

1. the product subject and the real mechanism or value it provides;
2. the audience, use scene, primary task, and desired outcome;
3. existing brand assets, tokens, components, content, and interaction conventions;
4. references that fit and anti-references that describe what to avoid;
5. accessibility, localization, browser, device, and performance constraints.

Ask one compact clarification round only when missing information would materially change the
direction. Otherwise state assumptions and continue.

## Write the Direction Contract

Define the following as one coherent system:

1. **Thesis**: one sentence connecting the product subject, audience, and surface job to the
   intended visual character.
2. **Visual sources**: subject-specific artifacts, materials, diagrams, environments, or cultural
   references that can inform the interface without literal imitation.
3. **System choices**:
   - color roles and contrast behavior;
   - typography roles, hierarchy, and reading rhythm;
   - layout, density, spacing rhythm, and responsive composition;
   - shape, borders, material, elevation, and depth;
   - imagery, iconography, data display, and content voice;
   - motion and feedback tone, when motion has a clear purpose.
4. **Signature element**: one memorable device that expresses the subject or improves the core
   task. Keep surrounding elements restrained enough for it to remain meaningful.
5. **Preserve/change boundary**: what must remain and what may change for the chosen scope.
6. **Validation signals**: observable evidence that the direction fits, and warning signs that it
   has become generic, distracting, inaccessible, or inconsistent with the product.

Prefer semantic roles over arbitrary hex values, font names, fixed animation durations, or
component counts unless the project already establishes those values.

## Run the Anti-Template Check

Revise the direction when any answer is unsupported:

- Could the same direction be moved unchanged to an unrelated product?
- Do layout and visual devices encode this content or merely decorate it?
- Is a category convention being followed without evidence that it helps this audience?
- Are repeated cards, grids, gradients, oversized headlines, or decorative motion coming from
  framework defaults rather than the product?
- Does the signature element improve recognition, comprehension, or task completion?
- Is copy written from the user's point of view and supported by real product facts?

These are diagnostic questions, not universal bans. Keep conventional patterns when they reduce
risk or cognitive load, especially in operational interfaces.

## Handoff Format

Return a compact, reviewable brief with:

- scope and primary surface mode;
- evidence and assumptions;
- direction thesis and visual sources;
- system choices and signature element;
- preserve/change boundary;
- accessibility and responsive constraints;
- risks, unresolved decisions, and validation checks.

If implementation is requested later, reuse existing tokens and components where they support
the direction, document intentional deviations, and verify the result in representative states
and viewport sizes.

## Research Basis

This workflow was independently rewritten for projectD after reviewing public design workflows,
including Anthropic's `frontend-design`, Leonxlnx's `taste-skill`, and pbakaus's `impeccable`.
Those third-party rules are research inputs, not projectD norms; project evidence and this Skill's
guardrails remain authoritative.

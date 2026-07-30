# React Capability Adapter

Read project evidence before selecting a capability. Give existing maintainable choices precedence.

| Capability | First checks | Conditional candidates |
| --- | --- | --- |
| Server state | Existing query/cache layer; SSR and invalidation needs | TanStack Query when the project needs client caching, invalidation and request coordination |
| Shared client state | Can component state, context or URL state suffice? | Existing Redux or Zustand; do not introduce both for the same data class |
| UI primitives | Existing design system and accessibility behavior | Existing component library; Base UI or Radix only when their API and styling model fit |
| Notifications | Existing design-system notification service | Existing solution; Sonner when React compatibility and its interaction model fit |
| Forms | Existing form convention; validation and SSR needs | Native forms or existing library; React Hook Form only when complexity justifies it |
| Motion | CSS and existing motion tokens first | Existing motion library; Motion only for gestures, layout animation or interruptible springs |
| Virtualization | Measured list size and row variability | Existing solution; Virtuoso or another verified library when native rendering is insufficient |
| Charts | Existing charting layer; accessibility and data volume | Existing solution; compare candidates from current primary documentation |

Do not place server data in Redux or Zustand merely because they are already installed. Do not add a
library for a simple transition, local component state, or a platform capability that already meets the
requirement.

Candidate examples were partially informed by `emilkowalski/skills`, `pick-ui-library`, commit
`e695d13cb298db0f46d5ef05be2ad13fa12908a6`, MIT License. Its closed recommendation list was not
adopted; every candidate remains conditional and requires current primary-source verification.

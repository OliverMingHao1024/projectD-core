# Angular Routing and Rendering

Inspect the existing router configuration, lazy-loading boundaries, authorization model,
rendering strategy, and hosting constraints before changing routes.

## Routes and navigation

- Put specific routes before broad parameter or wildcard routes when order affects matching.
- Use redirects deliberately and define full or prefix matching explicitly.
- Preserve existing eager and lazy feature boundaries; add lazy loading for a demonstrated
  bundle or ownership reason rather than by default.
- Prefer declarative links for normal navigation and the Router API for event-driven flows.
- Keep relative navigation anchored to an explicit route context.

## Guards and resolvers

- Use guards for navigation decisions and UX, never as the only authorization control.
  Enforce authorization again at the backend.
- Return the router-supported redirect value instead of imperatively navigating from a
  guard when the installed version supports that pattern.
- Use resolvers only when a route must not activate without the data. Prefer in-component
  loading when progressive rendering gives a better experience.
- Define error and cancellation behavior so navigation cannot hang indefinitely.

## Outlets and lifecycle

- Preserve the workspace's primary, nested, and named-outlet conventions.
- Keep route event subscriptions within Angular cleanup boundaries.
- When debugging navigation, observe the chronological route lifecycle and distinguish
  cancellation, redirect, guard rejection, resolver failure, and lazy-load failure.

## Rendering strategy

| Strategy | Use when |
| --- | --- |
| CSR | The application is highly interactive and server-rendered discovery is unnecessary |
| SSG/prerendering | Routes are known at build time and content changes with deployments |
| SSR | Per-request HTML, discovery, or first-render requirements justify server work |

- Preserve the existing CSR, SSG, or SSR decision unless the task explicitly changes it.
- For SSR or hydration, avoid browser-only APIs during server rendering, keep initial state
  deterministic, and test hydration rather than checking server HTML alone.
- Treat route transition APIs as version- and browser-dependent progressive enhancement;
  preserve reduced-motion behavior.

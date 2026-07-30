---
name: frontend-react
description: React application conventions and capability selection. Use when changing React components, hooks, effects, routing, client or server state, Lodash collection or object operations, rendering boundaries, tests, or build configuration.
---

# React Pack

Use with `frontend-core` for browser-facing work and `typescript` when the application
contains TypeScript.

## Establish the Baseline

- Read the React version, rendering model, router, state and data libraries, component
  system, test setup, and server or client boundary conventions.
- Inspect the Lodash version, package distribution, import convention, types, and bundler
  behavior before adding or changing utility operations.
- Inspect existing loading, error, suspense, caching, and form patterns.
- Preserve repository-level architecture and version constraints.

## Rules

- Keep server state in the established query or cache layer.
- Prefer component state, context, or URL state before introducing shared client state.
- Follow existing hook, effect, error-boundary, and component-composition conventions.
- Keep asynchronous effects cancellable and clean up subscriptions, listeners, and timers.
- Keep Lodash operations compatible with React immutability, stable callback identity,
  effect cleanup, and the repository's bundle strategy.
- Keep accessible structure and interaction behavior explicit.
- Do not introduce another frontend ecosystem or modernize dependencies incidentally.

## Verification

- Run the repository's focused tests, lint, type check, and production build.
- Verify the affected route or component, loading and error states, navigation, and cleanup.
- Check server rendering or hydration behavior when the application uses it.

## References

- Read [react-capabilities.md](references/react-capabilities.md) when selecting or changing
  a React-specific capability.
- Read [lodash.md](../frontend-core/references/lodash.md) when using Lodash collection,
  object, equality, cloning, debounce, or throttle operations.

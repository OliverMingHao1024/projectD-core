---
name: frontend-react
description: React application conventions and capability selection.
---

# React Pack

Use with `frontend-core` for React applications. Read the affected React version,
rendering model, router, state libraries, and existing component system first.

## Rules

- Keep server state in the established query/cache layer; do not move it into Redux or Zustand by default.
- Prefer component state, context, or URL state before introducing shared client state.
- Follow existing hook, effect, error-boundary, and component composition conventions.
- Keep asynchronous effects cancellable and clean up subscriptions, listeners, and timers.
- Preserve the repository's React and TypeScript versions; do not modernize dependencies incidentally.

## References

- Capability selection: `references/react-capabilities.md`

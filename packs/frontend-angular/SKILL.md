---
name: frontend-angular
description: Modern Angular application conventions and capability selection. Use when changing Angular components, directives, services, dependency injection, routing, forms, Signals or RxJS, Lodash collection or object operations, templates, tests, or build configuration; do not use for AngularJS 1.x.
---

# Angular Pack

Use with `frontend-core` for browser-facing work and `typescript` for language and
build-tool conventions. Treat modern Angular and AngularJS as separate frameworks.

## Establish the Baseline

- Read the Angular and TypeScript versions, module or standalone convention, providers,
  router, form strategy, rendering mode, test setup, and Signals or RxJS policy.
- Inspect the Lodash version, package distribution, import convention, types, and bundler
  behavior before adding or changing utility operations.
- Inspect the existing component system and state, data-access, error, and loading patterns.
- Preserve repository-level architecture and version constraints.

## Rules

- Preserve the established module or standalone component convention.
- Keep providers, subscriptions, listeners, and effects within Angular lifecycle and
  cleanup boundaries.
- Prefer the existing service, HttpClient, Signals or RxJS, and form conventions.
- Keep Lodash operations compatible with Angular change detection, Signals or RxJS
  identity, lifecycle cleanup, and the repository's bundle strategy.
- Keep templates accessible and avoid moving business logic into presentation code.
- Do not introduce another frontend ecosystem or modernize dependencies incidentally.

## Verification

- Run the repository's focused tests, lint, type check, and production build.
- Verify the affected route or component, loading and error states, navigation, and cleanup.
- Check server-rendering or hydration behavior when the application uses it.

## References

- Read [angular-capabilities.md](references/angular-capabilities.md) when selecting or
  changing an Angular-specific capability.
- Read [lodash.md](../frontend-core/references/lodash.md) when using Lodash collection,
  object, equality, cloning, debounce, or throttle operations.

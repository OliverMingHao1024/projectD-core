# Angular Testing

Inspect the configured runner, Angular testing APIs, DOM environment, fake-timer policy,
and existing helpers before writing tests. Do not replace Karma, Jasmine, Jest, Vitest, or
an E2E framework incidentally.

## Focused tests

- Test user-observable behavior and public contracts rather than component internals.
- Use TestBed only when Angular dependency injection, templates, rendering, or lifecycle is
  part of the behavior; keep plain unit tests plain.
- Prefer accessible queries and stable harness APIs over CSS selectors tied to markup.
- Make asynchronous stabilization explicit using the runner and Angular APIs supported by
  the workspace.
- Verify loading, success, empty, error, cancellation, navigation, and cleanup states that
  the changed behavior can reach.

## Component harnesses

- Reuse library-provided harnesses for Material, CDK, or Angular Aria components when
  available.
- Create a custom harness only when multiple tests need a stable interaction contract.
- Keep harness methods user-oriented, such as selecting an option or submitting a form,
  rather than exposing DOM structure.

## Router tests

- Use the router testing utilities supported by the installed version.
- Test the resulting URL and rendered component, including guard redirects, resolver
  failures, parameters, and nested outlets when affected.
- Avoid mocking the Router so deeply that matching and lifecycle behavior disappear.

## End-to-end tests

- Use the existing E2E framework and repository command.
- Add a framework only when none exists and the user has approved setup and dependency
  changes.
- Keep E2E coverage for critical cross-boundary paths; prefer focused component or router
  tests for narrower behavior.

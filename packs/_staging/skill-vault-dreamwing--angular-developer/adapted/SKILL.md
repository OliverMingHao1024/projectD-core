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
- Classify the work as greenfield or existing-project work before applying defaults.
  Greenfield means a new Angular workspace without repository, organization-template,
  compatibility, or architecture constraints. A new app or library inside an existing
  workspace is existing-project work.
- Inspect the Lodash version, package distribution, import convention, types, and bundler
  behavior before adding or changing utility operations.
- Inspect the existing component system and state, data-access, error, and loading patterns.
- Preserve repository-level architecture and version constraints.

## Greenfield Defaults

Apply these only when the work is genuinely greenfield and the user has not specified a
different constraint:

- Use the current stable Angular version and its supported TypeScript range.
- Prefer standalone architecture and Signals for local reactive state.
- Prefer Signal Forms for new forms when the selected Angular version supports them and
  no compatibility or product requirement favors another strategy.
- Prefer current framework-supported or native CSS animation APIs over a deprecated DSL.
- Use Angular CLI scaffolding when it is the selected workspace tool.
- Add Tailwind, Angular Aria, an E2E runner, or another dependency only for a demonstrated
  requirement and after applying the repository's dependency-change policy.

## Existing-Project Rules

- Preserve the established module or standalone component convention.
- Preserve the established template-driven, reactive, or Signal Forms strategy.
- Preserve the existing Signals, RxJS, test-runner, styling, and build conventions.
- Keep providers, subscriptions, listeners, and effects within Angular lifecycle and
  cleanup boundaries.
- Prefer the existing service, HttpClient, Signals or RxJS, and form conventions.
- Keep Lodash operations compatible with Angular change detection, Signals or RxJS
  identity, lifecycle cleanup, and the repository's bundle strategy.
- Keep templates accessible and avoid moving business logic into presentation code.
- Do not introduce another frontend ecosystem or modernize dependencies incidentally.
- Do not run migrations, upgrade Angular or Tailwind, replace the test runner, or add
  packages unless the task explicitly authorizes that change.

## Commands and External Tools

- Prefer repository scripts over raw `ng`, `npm`, or `npx` commands in an existing
  workspace.
- Treat `ng add`, `ng update`, migrations, deploy commands, and package installation as
  dependency or project mutations; inspect their scope and obtain any required approval.
- Do not configure or start Angular CLI MCP as part of ordinary Angular work. Route MCP
  enablement through the projectD-core MCP security boundary and explicit user approval.

## Verification

- Run the repository's focused tests, lint, type check, and production build.
- For greenfield CLI output, run the generated workspace's supported build and test
  commands; do not assume a particular runner when the selected Angular version differs.
- Verify the affected route or component, loading and error states, navigation, and cleanup.
- Check server-rendering or hydration behavior when the application uses it.

## References

- Read [angular-capabilities.md](references/angular-capabilities.md) when selecting or
  changing an Angular-specific capability.
- Read [angular-reactivity.md](references/angular-reactivity.md) for Signals, effects,
  resources, and HTTP reactivity.
- Read [angular-forms.md](references/angular-forms.md) when choosing or changing a form
  strategy.
- Read [angular-routing-rendering.md](references/angular-routing-rendering.md) for routes,
  navigation, guards, resolvers, SSR, SSG, and hydration.
- Read [angular-ui-accessibility.md](references/angular-ui-accessibility.md) for component
  composition, Angular Aria, styling, and animation choices.
- Read [angular-testing.md](references/angular-testing.md) for TestBed, harness, router,
  and E2E testing decisions.
- Read [angular-tooling.md](references/angular-tooling.md) for CLI, migrations, environment
  configuration, and mutation boundaries.
- Read [lodash.md](../../../frontend-core/references/lodash.md) when using Lodash collection,
  object, equality, cloning, debounce, or throttle operations.

## Source

The modern Angular reference topics were selectively adapted from Skill Vault
`dreamwing/angular-developer` version 1 (declared MIT; archive SHA-256 recorded in the
projectD Skill registry). The upstream snapshot remains isolated under `packs/_staging/`;
projectD precedence and authorization rules replace upstream absolute defaults.

---
name: frontend-angular
description: Angular application conventions and capability selection.
---

# Angular Pack

Use with `frontend-core` for Angular applications. Read the affected Angular and
TypeScript versions, module or standalone conventions, providers, router, and RxJS policy first.

## Rules

- Preserve the application's established module or standalone component convention.
- Keep providers, subscriptions, listeners, and effects within Angular lifecycle and cleanup rules.
- Prefer the existing service, HttpClient, Signals/RxJS, and form conventions before adding libraries.
- Do not introduce React ecosystem packages into an Angular application.
- Preserve the repository's Angular and TypeScript versions; do not modernize dependencies incidentally.

## References

- Capability selection: `references/angular-capabilities.md`

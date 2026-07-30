---
name: frontend-angularjs
description: AngularJS 1.x conventions for maintenance, bug fixes, testing, and incremental migration. Use when changing angular.module, controllers, services, factories, directives, components, filters, $scope, digest-cycle behavior, ngRoute, or UI-Router in a legacy AngularJS application; do not use for modern Angular.
---

# AngularJS 1.x Pack

Use with `frontend-core` for browser-facing work and `typescript` when the application
contains TypeScript. Treat AngularJS and modern Angular as separate frameworks.

## Establish the Baseline

- Read the AngularJS version, module declarations, bootstrap path, router, package manager,
  build pipeline, and test runner.
- Identify the established `$scope`, `controllerAs`, component, directive, JavaScript or
  TypeScript, and dependency-annotation conventions.
- Preserve APIs supported by the installed version and the application's existing boundaries.

## Rules

- Keep dependency injection minification-safe through the repository's array, `$inject`,
  or `ng-annotate` convention.
- Preserve component, directive, scope, routing, and lifecycle behavior unless the
  requirement explicitly changes it.
- Treat digest-cycle entry and resource cleanup as explicit integration boundaries.
- Keep shared state and business rules in services rather than controllers or DOM code.
- Preserve template escaping, request security, and interceptor behavior.
- Do not upgrade AngularJS, introduce modern Angular, or start a migration incidentally.

## Verification

- Run the repository's focused tests, lint, and production-mode build.
- Check annotation-sensitive or minified builds when dependency injection changes.
- Verify the affected route, loading and error states, navigation, and cleanup after
  repeated entry and exit.

## References

- Read [angularjs-maintenance.md](references/angularjs-maintenance.md) for digest,
  directive, security, testing, performance, and migration-sensitive work.

# AngularJS 1.x Maintenance

Read this reference for Lodash, digest-cycle, directive, security, testing, performance,
or migration-sensitive work.

## Digest and Lifecycle

- Prefer `$evalAsync` or `$applyAsync` when a callback enters from a non-AngularJS API.
  Avoid unconditional `$scope.$apply()` calls that can collide with an active digest.
- Keep `$http`, `$q`, `$timeout`, and `$interval` flows digest-aware. Wrap native or
  third-party callbacks only when they execute outside AngularJS.
- On `$destroy`, deregister scope and root-scope listeners, remove DOM listeners, cancel
  timers, abort requests where supported, and unsubscribe observers.
- Diagnose stale views, repeated requests, leaks, and digest-in-progress failures by
  tracing the async boundary and scope lifecycle before adding watchers or forced digests.

## Components and Directives

- Preserve isolate-scope bindings, controller aliases, `require` relationships,
  transclusion, and compile/link behavior unless the requirement changes them.
- Keep shared state and business rules in services instead of controllers, scopes, or
  DOM-manipulating directives.
- Keep direct DOM manipulation inside a directive that owns the affected DOM boundary.
- Do not assume `.component()` or lifecycle hooks exist before AngularJS 1.5.

## Lodash

- Read the shared Lodash reference from the `frontend-core` pack before changing utility
  operations.
- Preserve the existing global `_`, injected-service, or module-import convention and its
  script order.
- Keep repeated full-collection transforms out of templates and hot `$watch` expressions;
  compute them at an event, service, or controller boundary when possible.
- Route debounced or throttled callbacks through the correct digest boundary and cancel
  them when the owning scope is destroyed.

## Security

- Treat template HTML, URLs, and interpolated content as untrusted at system boundaries.
- Do not use `$sce.trustAs*` unless the value is validated for that exact context.
- Avoid runtime expression construction, arbitrary template compilation, and
  user-controlled directive or template URLs.
- Preserve CSRF, authentication, authorization, and interceptor behavior when changing
  `$http` calls.

## Tests and Performance

- Use the existing Jasmine, Karma, Mocha, Protractor, or other test setup.
- Test services through dependency injection and directives or components through the
  existing `$compile` or component helpers.
- Flush or settle `$httpBackend`, `$timeout`, `$interval`, and promise work explicitly.
- Measure watcher count and digest duration before changing binding or equality semantics.

## Migration

- Create seams around routes, services, and leaf components, then preserve observable
  behavior with focused tests before replacing each seam.
- Follow an existing hybrid bootstrap or adapter strategy; do not introduce a competing
  migration approach.
- Keep new framework-neutral domain logic isolated from `$scope`, DOM, and AngularJS
  globals when doing so is within scope.

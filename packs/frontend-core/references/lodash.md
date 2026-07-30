# Lodash in Browser Applications

Read this reference when a browser application uses Lodash for collection, object, path,
equality, cloning, timing, or aggregation operations.

## Establish the Baseline

- Read the installed version and determine whether the application uses global `_`,
  `lodash`, `lodash-es`, per-method packages, or a framework wrapper.
- Resolve the version independently for each repository and deployable entry point. Do not
  infer it from a sibling project, shared workspace, or another application's lockfile.
- For vendored browser scripts, inspect the loaded file header and page script order. For
  module builds, inspect the applicable manifest and resolved lockfile entry.
- Inspect the lockfile, type packages, bundler, browser targets, and existing import style.
- Preserve the established package and loading convention. Do not add a second Lodash
  distribution or mix global and module instances incidentally.

## Operation Semantics

- Prefer established Lodash operations for non-trivial collection and object work. Keep
  simple native code when it is clearer and supported by the target browsers.
- Use only signatures supported by the resolved version. For example, Lodash 4.x uses
  `uniqBy` for iteratee-based uniqueness, while older versions may expose a different
  `uniq` signature. Do not rewrite an existing call without checking its runtime version.
- Guard the result of `find` before reading a property. Use a `get` default only when a
  missing path has a defined fallback in the behavior contract.
- Use `isEmpty` for supported collections and objects, not as a generic truthiness test
  for numbers or booleans.
- Distinguish shallow `assign`, recursive `merge`, and `cloneDeep`. Do not introduce
  mutation, prototype loss, or shared-reference changes accidentally.
- Do not pass untrusted property paths or keys into object-writing helpers such as `set`
  or `merge`.
- Test empty, null, missing-match, duplicate-key, sparse, and nested-object cases.

## Cross-Version Work

- When shared code must run under multiple Lodash versions, use the verified lowest-common
  API or isolate version differences behind a small adapter owned by that shared boundary.
- Do not add runtime version branching throughout feature code or mutate the global `_`
  object to emulate missing methods.
- Keep upgrades, API migrations, and distribution changes as explicit dependency work.
  Do not mix them into an unrelated feature or bug fix.
- Run focused tests through every supported build or entry point; one repository's passing
  test does not establish compatibility for its siblings.

## Imports and Bundles

- Follow the repository's established import form and type declarations.
- Do not switch between `lodash` and `lodash-es` without confirming module format,
  test-runner compatibility, server rendering, and production bundling.
- Avoid importing the full library when the project intentionally uses method-level or
  tree-shakeable imports. Measure the production bundle before claiming an optimization.

## React

- Keep React state and props immutable. Use Lodash helpers without mutating objects owned
  by React, caches, or state libraries.
- Memoize expensive transforms only when measurement or stable identity requires it.
- Create debounced or throttled callbacks at a stable lifecycle boundary and call their
  `cancel` method during cleanup.

## Angular

- Keep repeated Lodash transforms out of templates and frequently evaluated getters.
  Precompute them in services, components, selectors, or pure pipes.
- Preserve Signals or RxJS identity and change-detection expectations when cloning,
  merging, debouncing, or comparing values.
- Cancel debounced and throttled callbacks when the owning component or service is destroyed.

## AngularJS

- When the application loads Lodash globally before transaction scripts, use the existing
  `_`; do not add `import`, `require`, or another bundled copy.
- Keep repeated full-collection transforms out of templates and hot `$watch` expressions.
- Preserve digest entry and cleanup behavior around debounced or throttled callbacks.

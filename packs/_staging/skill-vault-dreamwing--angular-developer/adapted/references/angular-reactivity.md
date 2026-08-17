# Angular Reactivity and Data Access

Read the installed Angular version and existing Signals or RxJS policy before choosing an
API. Treat version-specific APIs as conditional, not as migration instructions.

## State choices

- Use plain component fields for non-reactive constants.
- Use `signal` for local writable state and `computed` for values derived entirely from
  other reactive state.
- Use `linkedSignal` only when a derived default must remain writable; preserve the prior
  selection when it is still valid.
- Use the repository's established service, store, or router state for cross-feature state.
  Do not move RxJS state to Signals incidentally.

## Effects and cleanup

- Use `effect` for genuine side effects such as logging or integrating a non-Angular API,
  not for copying one signal into another.
- Prefer `computed` or `linkedSignal` for state derivation.
- Keep DOM work in the appropriate render lifecycle and ensure subscriptions, listeners,
  timers, and third-party resources are cleaned up.
- Avoid in-place mutation when identity changes are required by Signals, RxJS, or change
  detection.

## Async resources

- Use the project's established HttpClient or service layer first.
- Consider `resource` or `httpResource` only when supported by the installed version and
  consistent with the app's data-access policy.
- Cancel stale requests when inputs change, expose loading and error states, and validate
  untrusted response data at the application boundary.
- Prefer reactive resources for reads; keep mutations explicit and verify that the request
  is actually executed.

## HTTP boundaries

- Keep backend communication in injectable services rather than presentation components.
- Preserve the established interceptor order, XSRF configuration, credentials policy, and
  server-rendering behavior.
- Remember that HttpClient observables are cold and may issue a request per subscription.
- Do not hard-code bearer tokens, API keys, or environment secrets in examples or client
  configuration.

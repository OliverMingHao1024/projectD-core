# Angular Forms

Choose forms from project evidence. A new form inside an existing application is not a
greenfield application and normally follows the existing form strategy.

## Selection

| Context | Preferred direction |
| --- | --- |
| Existing application | Preserve its template-driven, reactive, or Signal Forms convention |
| Greenfield app on a version that supports Signal Forms | Prefer Signal Forms unless compatibility or product requirements favor another strategy |
| Simple form using an established template-driven convention | Continue template-driven forms |
| Complex typed validation using an established reactive convention | Continue reactive forms |

Do not migrate an existing app's forms merely to adopt a newer style. Confirm the selected
Angular version's supported APIs from current primary documentation.

## Model and validation

- Keep the domain model distinct from transient display state when their lifecycles differ.
- Define validation close to the form model and show errors only according to the existing
  interaction convention, such as touched, dirty, or submit-attempted state.
- Handle cross-field and asynchronous validation without creating circular reactive
  updates.
- Preserve disabled, readonly, and hidden semantics; do not use visual styling as the only
  state indicator.
- Treat server errors as external state and clear or retain them deliberately when inputs
  change.

## Submission

- Prevent duplicate submission while a request is active.
- Validate again at the server boundary; client validation is user feedback, not a security
  control.
- Preserve entered values on recoverable errors and focus or announce the first actionable
  error accessibly.
- Test valid, invalid, pending, server-error, reset, and repeated-submit paths relevant to
  the form.

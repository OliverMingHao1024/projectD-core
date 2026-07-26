# Frontend Capability Decision

Use this compact format only for a selection that should persist across future work. Store it in the
project's existing decision location; if none exists, propose `docs/decisions/frontend-capabilities.md`.

```yaml
capability: toast
scope: apps/customer-portal
implementation: existing-design-system-notification
status: accepted
decidedAt: YYYY-MM-DD
evidence:
  - Already used by all affected screens
  - Meets keyboard and screen-reader requirements
constraints:
  - No additional runtime dependency
tradeoffs:
  - Project-specific API reduces portability
exitCost: low
reconsiderWhen:
  - Existing implementation becomes unmaintained
  - Accessibility requirements are no longer met
```

Required fields are `capability`, `scope`, `implementation`, `status`, `decidedAt`, `evidence`,
`tradeoffs`, `exitCost`, and `reconsiderWhen`. Add fields only when the decision needs them.

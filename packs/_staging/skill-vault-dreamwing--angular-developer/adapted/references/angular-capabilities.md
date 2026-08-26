# Angular Capability Adapter

Read the affected Angular version, standalone or module convention, and existing providers
before selecting a capability. Give existing maintainable choices precedence.

| Capability | First checks | Conditional candidates |
| --- | --- | --- |
| Server state | Existing service, HttpClient, Signals/RxJS and caching policy | Extend the established service layer; add a query library only for demonstrated cache coordination needs |
| Shared client state | Can component state, Signals, a scoped service or router state suffice? | Existing NgRx or equivalent only when cross-feature complexity justifies it |
| UI primitives | Existing design system, Angular CDK/Material use and accessibility | Existing library; Angular CDK primitives when custom presentation is required |
| Notifications | Existing notification service or Material usage | Existing service; Material Snackbar when Angular Material is already an intentional dependency |
| Forms | Existing template-driven, reactive, or Signal Forms convention | Preserve an existing strategy; for a greenfield app, prefer Signal Forms when the selected Angular version supports them unless compatibility or product requirements favor template-driven or reactive forms |
| Motion | CSS and existing motion conventions first | Framework-supported or existing animation mechanism; avoid adding a React-oriented motion stack |
| Virtualization | Measured list size, variable height and interaction needs | Existing solution; Angular CDK Virtual Scroll when its constraints fit |
| Charts | Existing chart wrapper, SSR and accessibility requirements | Compare Angular-compatible maintained candidates from current primary documentation |

Do not introduce React ecosystem packages into Angular solely because an external recommendation lists
them. Keep providers, subscriptions, listeners and effects within Angular lifecycle and cleanup rules.

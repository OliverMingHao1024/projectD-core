# Angular UI, Accessibility, and Motion

Use `frontend-core` for general browser behavior. This reference adds Angular-specific
choices without replacing the project's design system or styling stack.

## Components

- Preserve the established standalone or NgModule convention.
- Prefer signal inputs and outputs only when supported and consistent with nearby code;
  do not migrate decorator-based APIs incidentally.
- Keep business rules out of templates and keep host bindings explicit.
- Use model-style two-way binding only when a component genuinely owns a writable value
  contract.

## Accessible primitives

- Prefer the existing accessible component library or Angular CDK/Material integration.
- Consider Angular Aria only when the installed Angular version supports it, the dependency
  is approved, and a headless primitive fits the design system.
- For accordion, listbox, combobox, menu, tabs, toolbar, tree, or grid patterns, verify
  keyboard behavior, focus management, roles, names, states, and screen-reader output.
- Style semantic states such as selected, expanded, disabled, current, and focus-visible;
  do not rely on color alone.
- Use component harnesses when the selected library provides them.

## Styling

- Preserve the existing global styles, encapsulation mode, preprocessors, tokens, and
  utility framework version.
- Do not introduce Tailwind or upgrade Tailwind as a side effect. For a greenfield project
  that intentionally selects Tailwind, use the setup supported by the selected Angular and
  Tailwind versions rather than copying a fixed-version recipe.
- Avoid piercing encapsulation unless integrating code that cannot expose a supported
  styling seam.

## Animation

- Prefer native CSS or the framework-supported enter/leave mechanism available in the
  installed Angular version.
- Preserve an existing legacy animation DSL until migration is explicitly requested.
- Keep motion purposeful, interruptible where users can reverse the interaction, and safe
  under reduced-motion preferences.
- For route transitions, preserve navigation continuity and ensure unsupported browsers
  retain a correct non-animated path.

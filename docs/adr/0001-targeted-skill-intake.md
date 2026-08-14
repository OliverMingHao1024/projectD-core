# Use targeted, governed Skill intake

projectD-core discovers external Skills through a targeted `skill-scout` workflow that accepts either a capability requirement or an exact GitHub source, returns at most three verified candidates, and never broadens scope, stages content, executes external code, or adopts changes without explicit user confirmation. Machine-readable lifecycle facts live in `skill-registry.json`, human decision rationale remains in `skill-candidates.md`, and upstream update detection is a separate `skill-update-check` capability. Adopted Skills become projectD-maintained CanonicalSkills whose location is determined by applicability—cross-stack in `core/skills/`, stack-specific in `packs/`—with immutable upstream and adapted staging snapshots retained during review.

Direct installs from an explicitly named non-GitHub registry follow that registry's
documented download and safety-review protocol. Record the provider coordinate,
immutable version and digest in the same registry before adoption. Providers without
an update adapter are reported as `skipped` by `skill-update-check`; they must never be
silently inspected through the GitHub path. A source without a declared SPDX license
may only be adopted as an explicitly user-authorized internal-use exception, must be
marked non-redistributable, and must not be represented as open source.

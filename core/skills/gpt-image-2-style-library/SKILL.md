---
name: gpt-image-2-style-library
description: Choose GPT-Image2 / gpt-image-2 visual styles and industrial prompt templates from the awesome-gpt-image-2 style library. Use when an agent needs to create, rewrite, classify, or improve image-generation prompts with repository-backed templates, categories, style tags, scene tags, pitfalls, and example cases.
---

# GPT-Image2 Style Library

Use this skill to turn a user's image-generation intent into a production-ready
GPT-Image2 prompt using the awesome-gpt-image-2 style library.

## Reference

- Read `references/style-library.md` before choosing a template or style.
- The reference is a pinned snapshot generated upstream from
  `data/style-library.json` in freestylefly/awesome-gpt-image-2. It does not
  auto-update; see `SOURCE.md` in the staging record for the pinned commit.
- Prefer the reference over memory when template names, categories, covers, or
  style tags matter.

## Workflow

1. Detect the user's language and answer in that language.
2. Identify the user's target output: product, poster, UI, infographic, brand,
   photo, illustration, character, scene, history, document, or special task.
3. Match the request in this order: template category, visual style tag,
   scene tag, then nearest example cases.
4. If one template is clearly strongest, use it directly. If several are
   plausible, present 2-3 options with short reasons and ask the user to
   choose.
5. Build the final prompt with these blocks:
   - subject and task
   - composition and layout
   - visual style and materials
   - text and label requirements
   - aspect ratio and output format
   - constraints and negative details
6. Include the selected template name and any useful example case IDs.

## Output Defaults

- Provide a copyable prompt first.
- Keep constraints concrete: exact text, aspect ratio, readable labels, layout
  hierarchy, and avoided artifacts.
- For Chinese requests, write the final prompt in Chinese unless the user asks
  for English.
- For English requests, write the final prompt in English unless the user
  asks for Chinese.
- When the user asks for multiple concepts, reuse one template and vary
  subject, composition, palette, and scene.

## Applicability

This skill assumes prompts are consumed by GPT-Image2 (or a compatible
image-generation model). It is a prompt-engineering aid, not a general visual
or brand-design skill — pair it with `design-engineering` or
`visual-direction` when the task also involves broader UI/brand judgment.

## Maintenance

This is a cross-agent adaptation staged from an upstream GitHub Skill. It has
no install script and no npm dependency: the reference file is read directly
from this skill's `references/` directory. To refresh from upstream, re-run
the `skill-scout` staging flow against the pinned source in `SOURCE.md` and
re-review before re-adopting.

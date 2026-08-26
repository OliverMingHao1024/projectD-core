---
name: resolving-merge-conflicts
description: Resolve an in-progress Git merge or rebase conflict.
---

1. **See the current state** of the merge/rebase. Check git history, and the conflicting files.

2. **Find the primary sources** for each conflict. Understand deeply why each change was made, and what the original intent was. Read the commit messages, check the PRs, check original issues/tickets.

3. **Resolve each hunk.** Preserve both intents where possible. Where incompatible, pick the one matching the merge's stated goal and note the trade-off. Do **not** invent new behaviour. Prefer resolving over aborting — but if a hunk's correct resolution genuinely can't be determined (source of truth unclear, both sides load-bearing and irreconcilable), stop and lay out the options for the user rather than guessing or unilaterally `--abort`ing. The choice to abort is the user's, not a fallback you reach for on your own.

4. Discover the project's **automated checks** and run them — typically typecheck, then tests, then format. Fix anything the merge broke.

5. **Finish the merge/rebase.** Stage only the files whose conflicts you resolved — never a blanket `git add -A`/`git add .` that could sweep in unrelated changes. Show the staged diff and a draft commit message, and get explicit confirmation before committing. If rebasing, `git rebase --continue` commits automatically as it proceeds — flag that up front so the user isn't surprised by commits they didn't individually approve — and continue until all commits are rebased.

## Source

Adapted for cross-agent discovery from
<https://github.com/mattpocock/skills/tree/ed37663cc5fbef691ddfecd080dff42f7e7e350d/skills/engineering/resolving-merge-conflicts>.
Licensed under MIT; see [LICENSE](LICENSE). The adapted version removes the blanket
"never abort" instruction (aborting is the user's call when a hunk truly can't be
resolved), and gates staging/committing behind explicit confirmation instead of
staging everything and committing unprompted.

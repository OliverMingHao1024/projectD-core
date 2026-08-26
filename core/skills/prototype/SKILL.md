---
name: prototype
description: Build a throwaway prototype to test a state model, logic, interaction, or UI direction.
---

# Prototype

A prototype is **throwaway code that answers a question**. The question decides the shape.

## Pick a branch

Identify which question is being answered — from the user's prompt, the surrounding code, or by asking if the user is around:

- **"Does this logic / state model feel right?"** → [LOGIC.md](LOGIC.md). Build an interactive demo that pushes the state machine through cases that are hard to reason about on paper. Use a project-native terminal app for a developer-local workflow, or a self-contained HTML file when a non-developer or asynchronous reviewer needs a no-install artifact.
- **"What should this look like?"** → [UI.md](UI.md). Generate several radically different UI variations on a single route, switchable via a URL search param and a floating bottom bar.

The two branches produce very different artifacts — getting this wrong wastes the whole prototype. If the question is genuinely ambiguous and the user isn't reachable, default to whichever branch better matches the surrounding code (a backend module → logic; a page or component → UI) and state the assumption at the top of the prototype.

## Rules that apply to both

1. **Throwaway from day one, and clearly marked as such.** Locate the prototype code close to where it will actually be used (next to the module or page it's prototyping for) so context is obvious — but name it so a casual reader can see it's a prototype, not production. For throwaway UI routes, obey whatever routing convention the project already uses; don't invent a new top-level structure. Before touching anything, list the existing files the prototype will sit next to or modify, so the user sees the footprint up front.
2. **Trivial to run.** A project-native prototype starts with one command from the existing task runner — `pnpm <name>`, `python <path>`, `bun <path>`, etc. A shareable logic demo is one HTML file that opens directly. The user or reviewer must be able to start it without thinking.
3. **No persistence by default.** State lives in memory. Persistence is the thing the prototype is _checking_, not something it should depend on. If the question explicitly involves a database, hit a scratch DB or a local file with a clear "PROTOTYPE — wipe me" name.
4. **Skip the polish.** No tests, no error handling beyond what makes the prototype _runnable_, no abstractions. The point is to learn something fast.
5. **Surface the state.** After every action (logic) or on every variant switch (UI), print or render the full relevant state so the user can see what changed.
6. **Capture it when done.** Fold any validated decision into the real code, then propose capturing the prototype itself as a **primary source**: creating a throwaway branch and committing it there, out of main, needs the user's confirmation like any other branch/commit. If the repo has an issue tracker, leave a context pointer to that branch on the relevant issue; if it doesn't, note the branch and the verdict in the commit message instead — don't assume an issue exists. The main branch keeps only the validated decision.

## Source

Adapted for cross-agent discovery from
<https://github.com/mattpocock/skills/tree/6654f6b60cd9d5be8b54c6fafe44346dabeb3b76/skills/engineering/prototype>.
Licensed under MIT; see [LICENSE](LICENSE). The adapted version requires listing the
files a prototype will touch before starting, gates the capture branch/commit behind
confirmation, and makes the "implementation issue" pointer conditional on an issue
tracker actually being in use. It preserves a project-native TUI for developer-local
logic work while adding the upstream single-file HTML shape for non-developer or
asynchronous review instead of making one artifact universal across technology stacks.

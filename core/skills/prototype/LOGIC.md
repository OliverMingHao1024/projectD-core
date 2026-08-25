# Logic Prototype

An interactive demo that lets someone drive a state model by hand. Use this when the question is about **business logic, state transitions, or data shape** — the kind of thing that looks reasonable on paper but only feels wrong once you push it through real cases.

## When this is the right shape

- "I'm not sure if this state machine handles the edge case where X then Y."
- "Does this data model actually let me represent the case where..."
- "I want to feel out what the API should look like before writing it."
- Anything where the user wants to **press buttons and watch state change**.

If the question is "what should this look like" — wrong branch. Use [UI.md](UI.md).

## Choose the delivery shape

Choose from the audience and handoff need, not from a universal technology preference:

- **Project-native terminal app** — use when a developer will run the prototype locally, matching the host runtime makes the logic easier to lift into production, or terminal interaction is already natural for the project.
- **Self-contained HTML file** — use when a PM, designer, domain expert, or asynchronous reviewer needs a no-install artifact that can be opened directly and shared as one file.

If both audiences matter, prefer the project-native logic module and add the smallest HTML shell that can call an equivalent pure JavaScript model. State explicitly that the two implementations must not be treated as one verified source of truth unless their behaviour is compared.

## Process

### 1. State the question

Before writing code, write down what state model and what question you're prototyping. One paragraph, in the prototype's README or a comment at the top of the file. A logic prototype that answers the wrong question is pure waste — make the question explicit so it can be checked later, whether the user is watching now or returning to it AFK.

### 2. Pick the language and artifact

For a terminal app, use whatever the host project uses. If the project has no obvious runtime (e.g. a docs repo), ask.

Match the project's existing conventions for tooling — don't add a new package manager or runtime just for the prototype.

For a shareable demo, use one plain HTML file with inline CSS and JavaScript: no framework, bundler, server, or external dependency. It must open directly from the filesystem.

### 3. Isolate the logic in a portable module

Put the actual logic — the bit that's answering the question — behind a small, pure interface that could be lifted out and dropped into the real codebase later. The terminal or HTML shell around it is throwaway; the logic module shouldn't be.

The right shape depends on the question:

- **A pure reducer** — `(state, action) => state`. Good when actions are discrete events and state is a single value.
- **A state machine** — explicit states and transitions. Good when "which actions are even legal right now" is part of the question.
- **A small set of pure functions** over a plain data type. Good when there's no implicit current state — just transformations.
- **A class or module with a clear method surface** when the logic genuinely owns ongoing internal state.

Pick whichever shape best fits the question being asked, *not* whichever is easiest to wire to a shell. Keep it pure: no I/O, terminal control flow, DOM access, or button handlers inside the model. The shell calls into it; nothing flows the other direction.

This is what makes the prototype useful past its own lifetime: when the question's been answered, the validated reducer / machine / function set can be lifted into the real module on its own.

### 4. Build the smallest shell that exposes the state

#### Terminal app

Build it as a **lightweight TUI** — on every tick, clear the screen (`console.clear()` / `print("\033[2J\033[H")` / equivalent) and re-render the whole frame. The user should always see one stable view, not an ever-growing scrollback.

Each frame has two parts, in this order:

1. **Current state**, pretty-printed and diff-friendly (one field per line, or formatted JSON). Use **bold** for field names or section headers and **dim** for less important context (timestamps, IDs, derived values). Native ANSI escape codes are fine — `\x1b[1m` bold, `\x1b[2m` dim, `\x1b[0m` reset. No need to pull in a styling library unless one is already in the project.
2. **Keyboard shortcuts**, listed at the bottom: `[a] add user  [d] delete user  [t] tick clock  [q] quit`. Bold the key, dim the description, or vice-versa — whatever reads cleanly.

Behaviour:

1. **Initialise state** — a single in-memory object/struct. Render the first frame on start.
2. **Read one keystroke (or one line)** at a time, dispatch to a handler that mutates state.
3. **Re-render** the full frame after every action — don't append, replace.
4. **Loop until quit.**

The whole frame should fit on one screen.

#### Shareable HTML

Write it for a non-developer in domain language rather than code terminology. Keep a clean top-to-bottom hierarchy:

1. **Question and purpose** — a visible title and one-line explanation of what the demo lets the reviewer explore.
2. **Current state** — labelled fields rather than a raw JSON dump, re-rendered after every action, with the most recent change called out when useful.
3. **Free play** — one button per action so the model can be explored in any order.
4. **Guided scenarios** — tabs or sections for the happy path, a difficult edge case, and an action that should be rejected. Starting a scenario resets to a known state; every step is a real action button.

Use restrained styling that keeps attention on the state and actions. Avoid animation and decorative interaction that could obscure the behaviour being evaluated.

### 5. Make it runnable in one command

For a terminal app, propose adding a script to the project's existing task runner (`package.json` scripts, `Makefile`, `justfile`, `pyproject.toml`) and confirm before editing that shared manifest — it's a file other work depends on, not scratch space. The user should run `pnpm run <prototype-name>` or equivalent — never need to remember a path.

If the host project has no task runner, or the user would rather not touch the manifest, just put the command at the top of the prototype's README.

For a shareable HTML demo, confirm that it opens directly without a server and does not make network requests.

### 6. Hand it over

Give the user the run command or HTML file. They'll drive it themselves; the interesting moments are when they say "wait, that shouldn't be possible" or "huh, I assumed X would be different" — those are the bugs in the _idea_, which is the whole point. If they want new actions or scenarios added, add them. Prototypes evolve.

### 7. Capture the answer and the prototype

Once the prototype has answered its question, capture the answer, then capture the prototype the way the [SKILL](SKILL.md) describes. The logic-specific mapping: the validated reducer / machine / function set lifts into the real module (the decision, absorbed); the terminal or HTML shell rides along to the throwaway branch that keeps the prototype as a primary source.

## Anti-patterns

- **Don't add tests.** A prototype that needs tests is no longer a prototype.
- **Don't wire it to the real database.** Use an in-memory store unless the question is specifically about persistence.
- **Don't generalise.** No "what if we wanted to support X later." The prototype answers one question.
- **Don't blur the logic and its shell together.** If the reducer / state machine references terminal escape codes, DOM APIs, or button handlers, it's no longer portable. Keep either shell thin over a pure module.
- **Don't add a framework or server to the shareable shape.** Requiring an install or dev command defeats the no-install handoff.
- **Don't ship the prototype shell into production.** The shell is optimised for manual exploration. The logic module behind it is the bit worth keeping.

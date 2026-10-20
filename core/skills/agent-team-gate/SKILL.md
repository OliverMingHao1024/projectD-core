---
name: agent-team-gate
description: Gate for starting multi-agent work; use when the user asks to start an agent team, parallelize with several agents, or asks whether to.
---

# Agent Team Gate

Delegating to several agents is a choice the user makes per task. Use this gate
whenever multi-agent work is requested or considered.

## Start gate

1. A request such as "start an agent team", "use multiple agents", or "parallelize"
   with no mode and no task: ask for the task first.
2. Task clear, mode not chosen: ask once for a mode, then stop.
   - **Balanced** (recommended): up to 3 concurrent subagents.
   - **Economy**: up to 2, lower-capability tier for routine work.
   - **Quality-first**: up to 3, highest-capability tier for hard or high-risk work.
   - The user may describe a custom mode instead.
3. The user's mode answer authorizes this task in this session only. Show the
   dispatch table, then start. Authorization does not carry to another task.
4. A mode named in the same sentence as the request skips the question.
5. "Do you recommend an agent team?" is advice, not authorization. Answer with
   trade-offs and do not start anything.
6. Choosing a mode does not authorize deletion, database writes, dependency
   installs, writes to shared core files, or external pushes. Each keeps its own gate.

## Dispatch table (show before starting)

```text
Agent Team: <mode>
- Lead: <capability tier> | owns: decisions and integration
- <role>: <tier> | scope: <paths> | writes: <yes/no>
Verification: <independent role> | <checkable condition>
Downgrades / unconfirmed: <omit if none>
```

If the table exposes a new high-risk action or overlapping paths, stop and return to
the relevant approval.

## Team rules

- Prefer parallelizing read-only work: exploration, document lookup, tests, log
  analysis, independent review.
- Writers get disjoint file or module allowlists. Two writers never touch one file.
- Planning, architecture decisions, and final integration stay with the lead.
- Each subagent gets a compact task packet: goal and motivation, allowed paths,
  prohibited actions, required sources, acceptance conditions, report format. It does
  not re-read the whole governance core.
- A writer never verifies its own work. Verification uses fresh context with only the
  acceptance conditions and output paths.
- Subagents do not delete files, install packages, write shared core files, or widen
  their allowlist unless the lead holds explicit authorization for it.

## Escalation and stopping

- Verify available models, effort levels, and concurrency in the current environment;
  never fill them in from memory. If the exact tier is unavailable, use the closest
  tier and say so. Never drop security review or independent verification because of
  a downgrade.
- A lower-tier agent that fails once is escalated with the error output, not retried.
  Two failures at the middle tier escalate with the full failure trace.
- At most two rounds in one direction; then stop and tell the user the direction or
  premise may be wrong.
- If work is not independent, write boundaries overlap, or coordination costs more
  than it saves, shrink the team or fall back to a single agent and say why.
- If the environment has no subagent capability, run in single-agent stages and do
  not claim a team was started.

## Reporting

- The main conversation keeps conclusions, decisions, risks, evidence, and next steps.
- Subagent reports stay within 30 lines; long output goes to a file and the report
  gives the path plus a short summary.
- Status is one of: done, partial, failed, with each acceptance condition marked.
- "Agents dispatched" is never a result. Only independently verified output counts.

This Skill is subordinate: the project constitution, nearer repository rules, and the
user's current explicit instructions take precedence.

## Source

Idea inspired by `vault/governance/agent-team-mode-policy.md` in
<https://github.com/pop15106/pixiu-core> (reviewed at
`f4d9aec06ef742723fc00f39639d42eb1a726cb6`). That repository has no LICENSE file, so
no text is copied: this Skill is an independent rewrite of the idea. Model names and
prices are intentionally left out because they go stale.

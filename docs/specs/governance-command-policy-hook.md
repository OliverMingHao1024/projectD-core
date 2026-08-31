# Governance Command Policy Hook

- Status: active
- Runtime authority: `scripts/governance-command-policy-hook.ps1`
- Security boundary: [DevSpace security boundary](devspace-security-boundary.md)
- Full decision history:
  [projectD-knowledge archive](https://github.com/OliverMingHao1024/projectD-knowledge/blob/main/archive/projectd-core/design/governance-command-policy-hook-full-history.md)

## Purpose

Enforce a small set of high-impact command and tool boundaries before execution
without changing the metadata-only operation-log hook.

## Effective rules

| Rule | Decision | Failure direction |
|---|---|---|
| Anonymous Dev Tunnel | Allow only the ADR 0017 exception for an explicitly personal repository or machine and an isolated DevSpace target. | Classification uncertainty denies. |
| TFS/Azure DevOps misuse | Deny recognized TFS/Azure DevOps write workflows when the current repository origin is GitHub. | Origin inspection uncertainty allows. |
| DevSpace access | Deny DevSpace MCP calls and recognized container/tunnel lifecycle commands unless repository or machine classification is explicitly personal. | Classification uncertainty denies. |
| Classification-registry tampering | Deny recognized direct edits or command writes to `vault/governance/project-classification.json`. | Inspection uncertainty denies. |

The anonymous-tunnel matcher covers supported long and short forms only when
they occur in the same command segment. Comments or unrelated segments must not
create a cross-command match.

## Classification

- Registry: `vault/governance/project-classification.json`
- Repository keys: SHA-256 of normalized origin URLs
- Machine keys: SHA-256 of normalized machine names
- Precedence: repository classification, then machine classification, then
  default `work`
- Only exact `personal` permits DevSpace or the narrow tunnel exception.
- Registration commands require a real interactive terminal. Agent-mediated
  redirected input is rejected.

The committed registry contains identifiers and classification only. It does
not grant filesystem isolation by itself.

## Hook contract

- Input is a PreToolUse event.
- A denied operation exits with code 2 and a specific explanation.
- Unrelated tools and commands pass through.
- Rule-specific failure direction is preserved; one outer catch must not turn
  fail-closed rules into fail-open behavior.
- The hook does not modify project files, start containers, open tunnels, or
  register machines/repositories during normal event handling.

## Implementation and verification

- Hook: `scripts/governance-command-policy-hook.ps1`
- Contract tests:
  `scripts/tests/governance-command-policy-hook.contract.ps1`
- Host wiring: `.claude/settings.json` and `.codex/hooks.json`
- Aggregate verification:
  `pwsh -File scripts/projectd-check.ps1 -GovernanceEvals`

Tests cover allowed and denied cases, classification failures, supported tunnel
forms, full-path TFS invocation, lifecycle commands, direct registry tampering,
and unrelated commands.

## Limitations

Command-text matching is not filesystem access control. Variable indirection,
byte-wise writes, wrapper scripts, or another unobserved execution path may
bypass textual detection. Container mounts, host permissions, repository
review, and the DevSpace isolation boundary remain independent controls.

Changes to security trade-offs require an ADR. Matcher and test maintenance may
update this contract without rewriting the archived decision history.

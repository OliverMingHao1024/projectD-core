---
status: accepted
date: 2026-08-29
domain: devspace-security
amends:
  - "0015"
current_authority: ../specs/devspace-security-boundary.md
---

# Allow `devtunnel --allow-anonymous` as a narrow exception when DevSpace runs inside its isolation container on a personal-registered repo/machine

`vault/governance/operating-model.md`'s anonymous-tunnel prohibition, and `scripts/governance-command-policy-hook.ps1`'s enforcement of it, was written as an absolute rule after the 2026/07/01 Offense 335495 incident, where `devtunnel.exe --allow-anonymous` exposed a host-installed, unisolated DevSpace's high-privilege capabilities to the Internet. That incident's actual failure mode was the combination of an anonymously reachable tunnel *and* no blast-radius containment behind it — an anonymous tunnel alone, pointed at a properly isolated target, is a materially different risk. `containers/devspace-isolation/` (built and verified per ADR 0015) now provides that containment: non-root process, dropped capabilities, single explicit bind-mount, no Docker socket, and no route to the internet except through an allowlisted egress proxy. Reaching DevSpace's MCP endpoint from a service like ChatGPT requires the tunnel to be anonymously connectable at the network layer — DevSpace cannot perform an interactive user login on ChatGPT's behalf — so real DevSpace usage needs `--allow-anonymous` (or an equivalent), the same way `pop15106/pixiu-core`'s reference deployment does with Microsoft Dev Tunnel.

`governance-command-policy-hook.ps1`'s anonymous-tunnel rule therefore gets one conditional exception, not a repeal: `devtunnel --allow-anonymous` is permitted only when the current repository or machine is registered `personal` in `vault/governance/project-classification.json` (the same check that already gates DevSpace MCP tool calls and DevSpace container/tunnel lifecycle commands). Every other anonymous-tunnel use — any repo/machine not registered personal, and any use unrelated to DevSpace — remains absolutely blocked, matching the original rule. The exception's own failure mode is fail-closed: if the personal/work check itself errors, the exception does not apply and the command is still blocked; only the rule's unrelated, pre-existing outer error handling remains fail-open, unchanged from before.

## Considered Options

- Keep the anonymous-tunnel rule absolute with no exceptions — rejected as the ongoing default: it would make DevSpace unreachable from ChatGPT even with `containers/devspace-isolation/` actually built, tested, and passing all isolation checks, for no remaining risk-reduction benefit once that containment exists.
- Repeal the anonymous-tunnel rule entirely (an earlier draft considered in this same conversation, never adopted) — rejected: it would also allow anonymous tunnels for unrelated, unisolated targets, which is exactly the original incident's failure mode; too broad.
- Bind the exception to a MAC address in addition to the existing repo/machine classification — rejected: a single machine commonly presents multiple MAC addresses (Wi-Fi, Ethernet, VPN adapters), MAC addresses are as easy to change as a hostname, and the added check would mainly cause false-negative failures (a registered personal machine failing the check because a different NIC was active) without raising the bar against a determined local actor, who already has the access needed to edit the registry file directly.

## Consequences

- `devtunnel --allow-anonymous` is usable for exposing `containers/devspace-isolation/`'s DevSpace MCP endpoint on any repository or machine explicitly registered `personal`.
- The rule's protection against the original incident pattern (anonymous tunnel onto an unisolated, host-installed target) is unchanged for every case outside that one exception.
- Registering a repository or machine `personal` now carries slightly more weight than before: it also grants this narrow anonymous-tunnel exception, not just DevSpace tool/lifecycle access. Both are gated by the same fact (this machine's exposure surface is bounded to personal use), so this is treated as one decision, not two.

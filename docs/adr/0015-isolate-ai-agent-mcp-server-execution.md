# Isolate AI-agent MCP server execution behind rootless containers and enforced egress

AI-agent MCP servers with file read/write and shell execution capability (e.g. DevSpace) must never be exposed through an anonymous public tunnel, and must run inside a non-root Docker container with a single explicit repo bind-mount, no Docker socket, and egress forced through a domain-allowlisted proxy container on an internal-only network — rather than relying on policy statements, host firewall rules, or WSL2/VM isolation. This follows the 2026/07/01 Offense 335495 incident, where `devtunnel.exe --allow-anonymous` exposed DevSpace's high-privilege capabilities to the Internet; the incident showed that "remember not to do X" is not a real control, and this repo's own convention (ADR 0010, bound local security scans and verify downloads) already favors enforced allowlists over trusted defaults.

## Considered Options

- **WSL2** — rejected as the default: its default `/mnt/c` auto-mount would let DevSpace's shell reach host `~/.ssh`/cloud credentials unless `/etc/wsl.conf` is manually hardened, which is exactly the kind of "remember to configure it" control this decision rejects.
- **Dedicated VM (Hyper-V)** — strongest isolation but rejected as the default for personal daily use given the added setup/maintenance cost; acceptable as an optional extra layer around the container if residual container-escape risk becomes a concern later.
- **Host firewall rules for egress** — rejected because npm/GitHub endpoints sit behind CDNs with churning IP ranges, making static IP allowlists unmaintainable; a domain-based proxy (squid) is far more durable and auditable.
- **Formal SOC pre-approval gate before every use** — rejected for this personal, single-user use: SOC involvement is passive/reactive (notified only if EDR/SOC alerts trigger again), not a go-live approval gate.

## Consequences

Reintroducing DevSpace (or any similarly privileged MCP server) is blocked until the isolation container is actually built and tested to confirm the shell cannot read host SSH/cloud credentials — this is a hard prerequisite, not a checklist item to complete alongside go-live. Adding a new MCP server with shell/write capability later must default to this same posture unless a documented reason overrides it.

## Addendum: single bind-mount amended to multiple bind-mounts per container, one container total (post-implementation)

The original text above required "a single explicit repo bind-mount" per container, and the initial implementation (`containers/devspace-isolation/` for projectD-core, then a second identical stack `containers/chouten-court-isolation/` for a second repo) followed that literally: one container, one repo, one blast-radius boundary each. Operating two (and, in practice, heading toward N) of these full stacks — separate container names, ports, devtunnel ports, OAuth tokens, and ChatGPT connectors per repo — turned out to be real, ongoing operational overhead disproportionate to the benefit for this personal, single-user context, and the installed `@waishnav/devspace@1.0.8` already natively supports serving several workspace roots from one process (`DEVSPACE_ALLOWED_ROOTS` takes a comma-separated list; confirmed against its v1.0.8-tagged docs).

Amended: **one container may bind-mount multiple repos**, each still an explicit, individually-reviewed line in `docker-compose.yml` (never a broader parent directory that would expose arbitrary sibling paths) — see `containers/devspace-isolation/README.md`'s "Multi-repo support" section for the mechanism and how to add a repo. The requirement this ADR actually protects — no Docker socket, egress forced through the allowlisted proxy, non-root, `cap_drop: ALL`, explicit reviewed bind-mounts rather than a broad host directory — is unchanged and still applies per container.

This is a conscious trade-off, not a silent weakening: a compromise of this one container now reaches every repo mounted into it, not just one, in exchange for adding a repo being a two-line config change instead of standing up a whole new stack. For this personal, single-user context that trade favors operational simplicity; a future multi-tenant or higher-threat context should reconsider the original one-container-per-repo posture instead of assuming this amendment still applies.

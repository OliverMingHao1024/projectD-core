# Isolate AI-agent MCP server execution behind rootless containers and enforced egress

AI-agent MCP servers with file read/write and shell execution capability (e.g. DevSpace) must never be exposed through an anonymous public tunnel, and must run inside a non-root Docker container with a single explicit repo bind-mount, no Docker socket, and egress forced through a domain-allowlisted proxy container on an internal-only network — rather than relying on policy statements, host firewall rules, or WSL2/VM isolation. This follows the 2026/07/01 Offense 335495 incident, where `devtunnel.exe --allow-anonymous` exposed DevSpace's high-privilege capabilities to the Internet; the incident showed that "remember not to do X" is not a real control, and this repo's own convention (ADR 0010, bound local security scans and verify downloads) already favors enforced allowlists over trusted defaults.

## Considered Options

- **WSL2** — rejected as the default: its default `/mnt/c` auto-mount would let DevSpace's shell reach host `~/.ssh`/cloud credentials unless `/etc/wsl.conf` is manually hardened, which is exactly the kind of "remember to configure it" control this decision rejects.
- **Dedicated VM (Hyper-V)** — strongest isolation but rejected as the default for personal daily use given the added setup/maintenance cost; acceptable as an optional extra layer around the container if residual container-escape risk becomes a concern later.
- **Host firewall rules for egress** — rejected because npm/GitHub endpoints sit behind CDNs with churning IP ranges, making static IP allowlists unmaintainable; a domain-based proxy (squid) is far more durable and auditable.
- **Formal SOC pre-approval gate before every use** — rejected for this personal, single-user use: SOC involvement is passive/reactive (notified only if EDR/SOC alerts trigger again), not a go-live approval gate.

## Consequences

Reintroducing DevSpace (or any similarly privileged MCP server) is blocked until the isolation container is actually built and tested to confirm the shell cannot read host SSH/cloud credentials — this is a hard prerequisite, not a checklist item to complete alongside go-live. Adding a new MCP server with shell/write capability later must default to this same posture unless a documented reason overrides it.

Building that isolation (container runtime install, application-control blocking of the tunnel binary) requires local administrator rights; without them none of these controls can be self-administered on a domain-joined machine. Applying this decision to DevSpace itself on 2026-08-14 found no local administrator rights available on the target machine, so the outcome was to not reintroduce DevSpace's shell/write capability there at all, rather than weaken the posture or request IT-administered setup. The same check (do you actually have the rights to build the isolation yourself?) must be run before reintroducing any future shell-capable MCP server under this ADR.

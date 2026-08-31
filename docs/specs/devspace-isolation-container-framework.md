# DevSpace Isolation Container Framework

- Status: implemented framework; operational readiness requires current checks
- Security authority: [DevSpace security boundary](devspace-security-boundary.md)
- Decision sources: ADR 0015 and ADR 0017
- Full implementation history:
  [projectD-knowledge archive](https://github.com/OliverMingHao1024/projectD-knowledge/blob/main/archive/projectd-core/design/devspace-isolation-container-framework-full-history.md)

## Purpose

Bound privileged DevSpace filesystem and shell capabilities with enforced
container, mount, network, and classification controls. An accepted ADR or a
present container definition does not prove the running deployment is ready.

## Required topology

- One non-root DevSpace service and one egress-proxy service.
- DevSpace uses an internal-only Docker network.
- The egress proxy is the only service attached to both internal and outbound
  networks.
- DevSpace has no Docker socket.
- Every repository is an individually reviewed bind mount; broad workspace or
  parent-directory mounts are prohibited.
- Multiple explicit repository mounts may share one personal-use container.
  This intentionally increases the within-container blast radius.

## Required container controls

- DevSpace runs as a non-root UID.
- `no-new-privileges:true`
- `cap_drop: [ALL]`
- Egress proxy starts as its unprivileged service user and also drops all
  capabilities.
- Neither service receives host credential directories.
- Direct DevSpace outbound traffic is unavailable.

## Egress policy

Squid permits only reviewed destination domains and rejects private, loopback,
link-local, and otherwise prohibited address ranges. Adding a domain requires
review of why the DevSpace runtime needs it.

The committed `allowed-domains.txt` may contain verification placeholders.
A placeholder allowlist is not production readiness and must not be represented
as a completed runtime configuration.

## Tunnel and classification

An anonymous Dev Tunnel is permitted only under the narrow conditions in ADR
0017 and the current DevSpace security boundary:

1. the target is this isolated service, not a host process;
2. repository or machine classification is explicitly `personal`;
3. current isolation and routing verification passes;
4. the tunnel exposes only the intended MCP endpoint.

All other anonymous-tunnel uses remain prohibited.

## Implementation map

- Container assets: `containers/devspace-isolation/`
- Compose topology:
  `containers/devspace-isolation/docker-compose.yml`
- Proxy policy:
  `containers/devspace-isolation/squid/`
- Verification:
  `containers/devspace-isolation/scripts/verify-isolation.ps1`
- Operations:
  `containers/devspace-isolation/README.md`
- Command boundary:
  `scripts/governance-command-policy-hook.ps1`

## Readiness checks

Before activation, current evidence must confirm:

- non-root UID, dropped capabilities, and no Docker socket;
- exact reviewed mount paths and no credential paths;
- direct egress denied;
- allowlisted proxy route succeeds and non-allowlisted/private routes fail;
- real required domains have replaced placeholders;
- the tunnel targets only the isolated endpoint;
- the personal registration path succeeds;
- lease expiry and scheduled-task operation are reported as operational
  limitations.

Any failed or unavailable check blocks a readiness claim.

## Change rule

Security-boundary changes require a new or amending ADR. Implementation and
verification improvements update this contract and tests. Historical
experiments, remediation narratives, and superseded alternatives belong in the
linked archive rather than this active specification.

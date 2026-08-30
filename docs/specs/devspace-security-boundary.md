# DevSpace Security Boundary

- Status: active decision contract
- Decision sources: ADR 0010, ADR 0015, and ADR 0017
- Scope: DevSpace and similarly privileged MCP servers with repository write or
  shell capability

## Effective rule

A privileged MCP endpoint may be exposed through an anonymous Dev Tunnel only
when all of the following are true:

1. The target is the isolated DevSpace container, not a host-installed process.
2. The repository or machine is explicitly registered as `personal`.
3. The registration check succeeds; errors and unknown classifications deny the
   exception.
4. The container runs non-root, drops capabilities, has no Docker socket, and
   mounts only individually reviewed repository paths.
5. A broad parent directory is never mounted. Multiple repositories may share
   one container only through separate explicit bind mounts.
6. Internet egress is forced through the configured domain-allowlisted proxy.
7. Current isolation and routing checks pass before tunnel activation.

All other anonymous-tunnel uses remain prohibited.

## Authority and precedence

- ADR 0010 supplies the allowlist and verified-download posture.
- ADR 0015 establishes enforced container isolation and egress controls.
- ADR 0017 narrowly amends ADR 0015's absolute anonymous-tunnel prohibition for
  personal registrations that satisfy this specification.
- This specification is the current operational interpretation when the
  historical wording in ADR 0015 conflicts with ADR 0017.

## Security properties

- No host SSH, cloud credential, Docker socket, or unrelated sibling repository
  is reachable through the MCP shell.
- Repository access is bounded by explicit bind mounts.
- Egress destinations are bounded by reviewed domains.
- Registration and preflight failures deny activation.
- Adding a repository, domain, MCP capability, or tunnel target requires an
  explicit review of the expanded blast radius.
- Multi-repository mounting accepts a larger within-container blast radius in
  exchange for operational simplicity; it is not suitable as an assumed
  default for multi-tenant or higher-threat environments.

## Readiness evidence

An accepted ADR records a decision; it does not prove deployment readiness.
Before activation, verification must establish at least:

- the running process is inside the intended container;
- UID/capability and Docker-socket checks pass;
- every mounted path matches the reviewed configuration;
- direct outbound access is blocked and approved proxy routes work;
- the allowlist contains the real required domains rather than placeholders;
- the tunnel targets only the isolated MCP endpoint;
- the personal registration path has been exercised successfully.

A scheduled task, expiring tunnel lease, placeholder domain, or untested
registration path must be reported as an operational limitation rather than
silently treated as compliant.

## Change rule

Changes that alter the security trade-off require a new ADR that names what it
amends. Implementation-only changes update the container specification and
tests while preserving this boundary.

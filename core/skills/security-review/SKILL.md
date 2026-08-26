---
name: security-review
description: Read-only security review for trust boundaries, secrets, sensitive data, files, APIs, or privileges.
---

# Security Review

Review only. Do not edit source, change configuration, install scanners, rotate
credentials, or mutate external systems while this Skill is active.

## Establish the scope

1. Identify the reviewed design, working tree, commit range, or pull request.
2. Read the applicable L0/L1 rules, repository standards, architecture evidence,
   and the technology pack for the affected files.
3. Separate pre-existing conditions from risks introduced or exposed by the
   reviewed scope. Do not turn a bounded diff review into a repository audit.
4. State when evidence is unavailable. Absence of a search hit is not proof that
   a control exists or a vulnerability is absent.

## Build the smallest useful threat model

For the changed path, identify only what is supported by evidence:

- assets and sensitive data;
- actors and privilege levels;
- entry points, trust boundaries, and data flows;
- externally observable state changes and failure consequences;
- attacker-controlled sources and security-sensitive sinks.

Ask four questions: what is changing, what can go wrong, what mitigates it, and
how the mitigation can be verified. Use STRIDE or another taxonomy only when it
improves coverage; never manufacture one finding per category.

## Select applicable controls

Review only categories reached by the changed data or control flow:

- **Identity and access:** authentication, authorization at the server-side
  operation and object level, tenant isolation, session lifecycle, privilege
  changes, and fail-closed behavior.
- **Untrusted data:** validation at the boundary, canonicalization, injection,
  output encoding, deserialization, template or command execution, and unsafe
  redirects.
- **Secrets and cryptography:** no embedded credentials, appropriate secret
  storage and rotation boundary, approved primitives, key handling, randomness,
  and transport protection. Do not prescribe fixed algorithms or work factors
  without current project or authoritative guidance.
- **Sensitive data and observability:** data minimization, exposure in responses,
  logs and errors, retention, audit usefulness, and log integrity.
- **State-changing web flows:** CSRF and origin protections where cookies or
  ambient authority apply; replay and idempotency where the operation needs them.
- **Files and paths:** size and type constraints, path traversal, archive
  expansion, storage permissions, and active-content handling.
- **Resources and business logic:** abuse cases, quotas or rate controls when
  justified, race conditions, transaction integrity, rollback, and workflow
  bypasses.
- **External services and APIs:** destination control, SSRF, timeouts, response
  validation, least-privilege credentials, unsafe consumption, and failure
  isolation. Apply the project's Source/Action boundary separately.
- **Dependencies, configuration, and deployment:** changed dependency risk,
  insecure defaults, debug exposure, environment separation, and least privilege.

Load framework-specific guidance from the applicable pack. Do not recommend a
library, header, storage mechanism, numeric threshold, or scanner merely because
it appears on a generic checklist.

## Verify findings

Prefer deterministic evidence: tests, configuration, data-flow traces, reachable
call paths, dependency manifests, and reproducible tool output. Run existing
read-only checks when they are safe and relevant. Installing tools, downloading
databases, sending code externally, active exploitation, destructive testing, or
testing production requires separate authorization.

Reject findings that have no plausible path from an attacker-controlled source
to an affected asset or control. When uncertainty remains material, report the
missing evidence and the smallest verification step instead of asserting a flaw.

## Report

Lead with findings ordered by security impact. For each finding include:

- `Material` or `Minor`, plus a conventional security severity when useful;
- the exact file, line, component, or design boundary;
- attacker prerequisites and a concrete exploit or failure path;
- the affected asset and observable impact;
- evidence and confidence;
- the smallest corrective direction and a verification method.

Distinguish confirmed vulnerabilities, defense-in-depth improvements, and
unverified questions. If no finding exists, say so and name the reviewed security
surfaces; do not claim the whole system is secure.

This focused review complements, but does not replace, the general `code-review`
Standards/Spec gate. Security fixes remain outside this read-only Skill and require
the normal implementation authorization and verification workflow.

## Sources

Method synthesized for projectD from primary guidance:

- OWASP [Secure Code Review Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secure_Code_Review_Cheat_Sheet.html)
- OWASP [Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)
- OWASP [Application Security Verification Standard](https://owasp.org/www-project-application-security-verification-standard/)
- OWASP [API Security Top 10 — 2023](https://owasp.org/API-Security/editions/2023/en/0x03-introduction/)

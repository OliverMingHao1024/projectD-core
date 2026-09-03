# ADR 0018 — Separate runtime policy from operation evidence

- Status: accepted
- Date: 2026-09-01
- Current authority: `../specs/agent-runtime-governance.md`

## Context

Phase 3 correctly introduced durable operation evidence, host hooks, recovery contracts and upgrade gates, but its live hook also classifies operations directly from host tool names. The operation-log schema therefore mixes three concerns: effect evidence, coarse Source/Action classification, and authorization state.

That coupling is too weak for agent runtime governance. A transport or product name does not determine authority: an MCP read, a network fetch, a repository push and an external message have different effects even when exposed through similarly named tools. Host permission is also not equivalent to projectD task authorization.

The previous rule freezing new Phase 3/4 schemas until a single-host pilot protected the project from speculative schema growth, but it also prevented a contract-level correction when a concrete architectural gap had already been demonstrated.

## Decision

Introduce a provider-neutral runtime policy decision contract separate from the durable operation log.

The policy contract represents:

- task/run/operation identity;
- policy identity and version/digest;
- requested capability and target class;
- effect properties;
- task-scoped authorization state and basis;
- allow/deny/require-authorization/observe-only outcome;
- classification/enforcement coverage;
- metadata-only privacy guarantees.

The initial canonical capability vocabulary is:

- `local-read`
- `workspace-write`
- `command-execute`
- `network-read`
- `external-write`
- `repository-mutate`
- `credential-use`
- `production-mutate`
- `unclassified-effect`

Source/Action remains a useful human-facing governance concept, but it is no longer the target runtime authorization taxonomy.

The Phase 3 operation log remains the evidence ledger. It must not become the policy engine. Existing Phase 3 schemas stay valid until a deliberate migration replaces them.

Repository-observable reads may remain advisory, but effectful or unclassified operations without a current task authorization envelope fail closed before intent/effect. Authorization envelopes bind the exact task/run and current policy id/version/digest, require bounded expiry, and cannot be issued through redirected agent/tool stdin. Writes to runtime authorization/evidence state are not grantable tool operations; writes to the live governance control plane require a separate `repository-mutate/governance-control` grant.

A host pilot remains mandatory before claiming live interception or enforcement coverage. It is not a freeze on deterministic contract evolution.

## Consequences

- Runtime authorization can become operation-aware without binding projectD to one host or MCP implementation.
- Host permission can be recorded separately from verified task authorization.
- Unknown operations can fail safely as `unclassified-effect` without pretending that a tool name is a complete security classification.
- Arbitrary command execution is treated as open-world external/destructive authority; a narrower grant must use a more specific capability rather than inheriting a benign-looking command example.
- Existing Phase 3 evidence and recovery work remains reusable.
- A later hook migration must translate host payloads into the runtime policy envelope before effect execution where the host exposes sufficient information.
- Cross-host mappings require evidence for each host-specific adapter; the policy vocabulary itself may remain host-neutral.

## Verification boundary

This ADR establishes an architecture decision, not proof of live enforcement. Contract/schema validation is deterministic evidence; only authorized host trials can establish interception coverage.

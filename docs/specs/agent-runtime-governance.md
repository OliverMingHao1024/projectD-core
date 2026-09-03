# Agent Runtime Governance

- Status: Runtime Governance v2 security-hardened contract active; current Codex build requires a new bounded live revalidation. Claude, recovery and cross-host integration remain pending. Existing Phase 3 contracts remain reusable evidence, not a freeze on necessary runtime evolution
- Scope: projectD-core agent execution across Codex, Claude, MCP/DevSpace and future hosts
- Parent governance: `vault/governance/operating-model.md`
- Runtime evidence: `docs/specs/governance-evals-v2-phase-3.md`

## Purpose

Turn projectD-core governance from prompt-level guidance into runtime-enforced boundaries without binding the core to one model, host, SDK or agent framework.

The runtime is not a new source of policy. L0-L6 remain authoritative. Runtime components only classify an intended effect, enforce already-defined authorization and containment boundaries, preserve durable evidence, and fail safely when the required facts are unavailable.

## Design model

Use four separated planes:

1. **Brain** — model plus host harness. It may plan, reason and request capabilities, but it is not itself an authority to grant them.
2. **Hands** — tools, MCP servers, shell, filesystem and external connectors. Every effectful operation passes through host-native permissions plus projectD runtime policy where observable.
3. **Session** — durable task/run state, checkpoint and metadata-only evidence. It is independent from model context and from the execution sandbox.
4. **Policy** — deterministic projectD decisions derived from L0-L6, repository/machine classification, task authorization and capability metadata.

The separation is deliberate: a model upgrade must not silently widen tool authority; replacing an execution environment must not erase session evidence; losing a session must not authorize replay of effects.

## Runtime invariants

### 1. Authority is capability-scoped

A tool being visible to an agent does not mean the agent is authorized to use every operation of that tool.

Runtime decisions should resolve to the smallest capability required by the current operation, for example:

- local read
- workspace write
- command execution
- network read
- external write/send
- repository mutation
- deployment/production mutation
- secret/credential access

Unknown or unclassified capabilities are treated as effectful until proven otherwise. Classification must be based on the concrete operation when host payloads expose enough information; product names alone are insufficient.

### 2. Authorization is task-scoped and non-transitive

Authorization belongs to `(task, capability, target, constraints)`, not to an agent identity or session globally.

Source access does not imply Action authority. An allowed read does not authorize a later write. A handoff to another agent does not transfer broader permissions than the parent task already holds.

High-risk or externally visible actions still require the explicit authorization defined by L0 even if host-native permission prompts are disabled or auto-approved.

### 3. Containment limits blast radius

Execution environments should provide independent technical containment:

- one authorized repository/workspace per execution boundary;
- non-root execution;
- no Docker socket, host SSH agent or broad home-directory credential mounts;
- egress deny-by-default with explicit destinations where practical;
- credentials held outside model-generated code and injected only for the narrow operation that needs them;
- separate policy/orchestration state from the sandbox performing generated commands.

Host permission prompts are UX controls, not containment.

### 4. Session state is durable; effect replay is not

The durable session/checkpoint stores enough metadata to resume reasoning and verify workspace identity, but does not store raw chain-of-thought or secrets.

Before recovery, projectD verifies checkpoint identity, workspace/repository identity, policy version and required smoke evidence. Live effects use replay policy `never`; after uncertainty or crash, recovery must determine observable final state rather than repeat the effect optimistically.

### 5. Evidence precedes trust claims

Runtime enforcement claims require observable host evidence. Static config, hook registration, contract tests and synthetic fixtures do not prove live interception.

Evidence should remain metadata-only and privacy-preserving while recording enough to establish:

- host/model/harness/adapter identity;
- task/run identity;
- requested capability and target class;
- authorization provenance;
- policy decision and rule/version;
- effect intent before execution;
- effect result or unresolved state;
- checkpoint/recovery relation;
- exclusions where the host provides no observable hook.

Raw prompts, chain-of-thought, secrets and unrestricted tool payloads are not governance evidence.

### 6. Policy must be deterministic before model-based guardrails

Known safety and authorization boundaries use deterministic rules first. Model-based classifiers may add defense in depth for ambiguous semantic risks such as prompt injection or goal drift, but cannot silently grant a capability denied or unverified by deterministic policy.

### 7. Budgets bound autonomous loops

Long-running and multi-agent work must have bounded execution budgets appropriate to the host: tool/action count, retries, elapsed time, approval burden and optionally token/cost limits when reliably observable.

Exceeding a safety or failure threshold ends or pauses the affected branch rather than allowing indefinite retry. Metrics that cannot be observed are `unavailable`, never guessed.

## Threat coverage

The existing projectD controls should be evaluated against these agentic threat classes:

| Threat class | projectD runtime control |
|---|---|
| Goal/instruction hijacking | task-scoped authority; deterministic policy is outside model context |
| Tool misuse / excessive agency | capability classification, authorization gate, sandbox containment |
| Identity / privilege abuse | repository and machine classification; least-privilege credentials; non-transitive handoffs |
| Memory poisoning | provenance-aware durable session; memory is not authority; raw external content does not become policy |
| Insecure inter-agent communication | bounded handoff envelope containing goal, scope, evidence, constraints and acceptance criteria |
| Cascading failures | retry/action budgets, checkpointing, fail-closed recovery and no effect replay |
| Supply-chain / MCP risk | explicit server/tool allowlists, source verification, constrained transport/egress and per-operation classification |
| Insufficient observability | durable metadata-only operation log plus live host evidence gate |

## projectD-core application

### Existing controls to keep

Do not replace these components:

- L0-L6 and TaskScopedProposalLoop
- Source/Action boundary as a human-facing governance simplification; runtime authorization uses the capability/effect contract below
- DevSpace/MCP container and egress isolation
- `governance-command-policy-hook.ps1`
- `governance-host-operation-hook.ps1`
- host adapters, run-plan integrity and paired upgrade gate
- metadata-only operation log and checkpoint recovery contracts

### Runtime policy contract

The canonical provider-neutral decision envelope is `evals/schemas/governance-runtime-policy-decisions.schema.json`. It deliberately sits beside, rather than inside, the Phase 3 operation-log schema.

The current capability vocabulary is `local-read`, `workspace-write`, `command-execute`, `network-read`, `external-write`, `repository-mutate`, `credential-use`, `production-mutate`, and the fail-safe `unclassified-effect` fallback. The schema enforces three minimum invariants directly: an unclassified effect cannot be allowed; host permission alone cannot become verified task authorization or an allow decision; and production mutation requires exact explicit current-task authorization.

Phase 3 operation logs remain durable evidence during migration. Their legacy `classification` field is compatibility metadata, not the runtime authorization authority. Host adapters should eventually normalize concrete operation payloads into the policy envelope before effect execution, while operation logs record the resulting intent/result evidence without owning policy semantics.

### Current implementation status

Runtime Governance v2 now has a provider-neutral policy decision schema and deterministic normalization module. The Codex/Claude pre-effect hook emits one metadata-only v2 decision per observed tool call before writing the legacy Phase 3 operation intent. Known operations are normalized to capability/effect metadata; command payloads may refine repository mutations; unresolved MCP/connector operations remain `unclassified-effect`.

The hook now supports task-scoped authorization envelopes. Local/network reads remain advisory `observe-only`; an unrelated effect grant never promotes them into verified authorization. Effectful or unclassified capabilities without an envelope fail closed with an enforced pre-effect `deny`. A validated envelope must be unexpired, bound to the exact task/host run and current policy id/version/digest, and contain a matching capability/target/effect grant. Unclassified, expired, mismatched, stale-policy, external/destructive-without-grant, or ungranted effects are denied before the legacy operation intent is written. Contract fixtures are accepted only through an explicit test-only hook switch that is restricted to the system temporary directory. Legacy operation-log classification remains a compatibility projection.

On 2026-09-03, trusted interactive Codex CLI `0.152.1` with `gpt-5.6-luna / medium` on Windows completed the hardened current-policy, same-session flow. A pinned metadata bootstrap produced one succeeded `network-read / observe-only` operation; an interactively issued exact task/run envelope authorized one built-in `apply_patch` as `workspace-write / enforced allow` with succeeded operation evidence; and an out-of-scope shell request was denied as `command-execute / capability-not-granted` before effect, with no command output or operation intent. Decision, authorization and operation evidence passed their schemas and metadata-only privacy checks. This verifies only the bounded Codex tool paths and model/effort exercised by the pilot; other Codex models, Claude, hosted/specialized tools, crash/reopen recovery, live observers and cross-host behavior remain unverified. The 2026-09-02 Codex CLI `0.145.0` run remains historical Windows transport evidence for an older policy digest.

`governance-task-authorization.ps1` is the bounded issuance path. It accepts only a current-policy decision from the selected host's ignored runtime-policy directory, derives task and host identity from that validated metadata-only evidence, rejects redirected stdin, and requires the user to type an exact confirmation phrase in a real interactive terminal. The policy digest covers the shared security helpers, normalizer, host hook, authorization issuer and both authorization/decision schemas. The resulting envelope expires within 24 hours and is written atomically to ignored local runtime state. It cannot authorize an unclassified effect. Production mutation and arbitrary command execution additionally require explicit external and destructive grants. The latter is intentionally an open-world boundary: once a user grants arbitrary command execution, narrower file-level hook classification is no longer a containment guarantee and independent sandbox/OS controls remain required.

### Corrections to make in the runtime architecture

1. **Refine tool classification from name-level to operation-level where host payload allows it.** A web fetch/read is not automatically equivalent to an external mutation; MCP is a transport/integration boundary, not a single Action class. Unknown remains fail-safe.
2. **Separate permission from authorization in every live path.** Host approval or auto mode must never be emitted as `authorization_verified=true` without task-scoped projectD evidence.
3. **Bind policy decisions to policy/version + task scope.** Recovery must detect stale policy or changed workspace identity before resuming.
4. **Make coverage exclusions first-class.** Unsupported hosted/specialized tool paths are reported as unobserved rather than implicitly covered.
5. **Add runtime budgets only after a host exposes reliable counters.** Do not introduce guessed token/cost data or a cross-host abstraction before evidence exists.

## Existing-rule review

The following projectD rules are not equally immutable. Runtime governance should distinguish principles that remain foundational from implementation choices that may evolve.

| Existing rule | Decision | Rationale |
|---|---|---|
| L0 explicit authorization for high-risk actions | Keep | This is a safety invariant, independent of host/runtime design. |
| Evidence-first and honest verification | Keep | Runtime claims without observable evidence are precisely the failure mode this architecture must prevent. |
| Source/Action binary classification | Replace as primary runtime model | Keep it as a human-facing simplification, but runtime enforcement needs capability/effect granularity because read/write/network/production/credential operations have materially different risk. |
| TaskScopedProposalLoop | Keep, simplify at runtime | Keep the outer governance lifecycle, but runtime hooks should evaluate concrete operations rather than reproduce the full conversational loop for each tool call. |
| Host permission is separate from projectD authorization | Keep and strengthen | Host UX approval cannot establish task-scoped project authority. |
| Metadata-only evidence | Keep with narrow extensibility | Privacy minimization is correct; add only fields required to establish authorization, capability, policy version, effect/result and recovery integrity. |
| `host-hook-unverified` until live evidence | Keep | Static wiring is not proof of interception. |
| Freeze Phase 3/4 schemas until a single-host pilot | Remove as a hard rule | It prevented speculative complexity, but it also blocks necessary contracts. New schemas/contracts may precede the pilot when they address a demonstrated gap and remain explicitly unverified live. |
| Wait for multiple hosts before every cross-host abstraction | Relax | Host-neutral concepts such as capability, effect and authorization may be defined once before multiple pilots; host-specific payload normalization should remain evidence-driven. |
| Unknown tool classification defaults to high-risk Action | Keep as fallback, narrow scope | Fail-safe defaults remain valuable, but known operations should not stay permanently overclassified simply because a tool name is broad. |
| No background monitoring / unbounded autonomous expansion | Keep | This limits runaway agency and unexpected resource or state changes. |

This review means projectD governance is constitutional at the principle level but evolutionary at the contract and runtime-mechanism level. ADR/spec decisions are revisable when new evidence shows a better control.

## Single-host pilot gate

The earlier Codex authorization slice has one historical bounded live pass. Because the security review changed policy identity, no-envelope behavior, protected-target classification and Codex error handling, the current build must repeat that pilot. The broader Phase 3 host pilot also remains open for recovery, observer and coverage items not exercised by that flow.

The pilot is successful only when all are demonstrated with real host evidence:

1. hook is actually loaded by the host;
2. a benign source operation is observed without widening authority;
3. a workspace write records intent before effect and result after effect;
4. a denied high-risk command is blocked by the command policy hook;
5. host permission/auto-approval cannot forge projectD task authorization;
6. crash/reopen does not replay an already-executed effect;
7. changed workspace identity or stale checkpoint fails closed;
8. raw prompts, secrets and unrestricted tool payloads do not enter durable governance evidence;
9. all unobservable paths are explicitly listed as coverage exclusions.

The pilot is an evidence gate for claims of live coverage, not a design freeze. A runtime-policy schema, normalized capability contract or observer contract may be introduced before the pilot when it closes a demonstrated architectural gap, has deterministic contract tests, and does not imply unverified live enforcement. Cross-host abstractions should still wait for evidence from more than one host unless they are deliberately host-neutral by construction.

## Evaluation model

Map runtime evaluation to the existing Governance Evals phases instead of creating a parallel suite:

- deterministic contract tests: policy parsing, classification, failure direction and recovery invariants;
- synthetic behavior cases: expected allow/deny/propose outcomes;
- live host trial: actual interception and observable final state;
- paired upgrade gate: same fixtures and graders across baseline/candidate host or model versions;
- cross-host matrix: only after at least two hosts have genuine live evidence.

A high/critical authorization, containment, privacy or replay regression blocks promotion independently of aggregate pass rate.

## External alignment

This design intentionally aligns with, without depending on, the following external practices:

- NIST AI RMF / Generative AI Profile: govern, map, measure and manage risks across the lifecycle.
- OWASP Top 10 for Agentic Applications 2026: goal hijacking, tool misuse, identity/privilege abuse, memory poisoning, inter-agent risks and cascading failures.
- MCP authorization guidance: transport authorization must use established OAuth security practices where HTTP authorization is used; transport authorization is not a substitute for task-scoped project policy.
- Current agent runtime engineering: separate model/harness from execution environments and durable sessions; use sandboxing, approvals, tracing/observability and resumable state.

External frameworks are references, not new L0 authorities. projectD-core remains provider-neutral and evidence-driven.

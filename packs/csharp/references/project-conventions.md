# C# Project Conventions

Read this reference when the task changes project structure, naming, tests, or build commands.

## Project Structure

- For ASP.NET Core APIs, preserve the established Controllers/Endpoints, Services, and
  Repositories boundaries.
- For .NET 8 console or worker applications, use the existing Generic Host,
  `IHostedService`, or `BackgroundService` pattern. Preserve the current structure in
  .NET Framework applications that do not use Generic Host.
- Keep one solution aligned to one logical product boundary. Extract genuinely shared
  behavior to a class library instead of copying it between executable projects.

## Naming

- Use PascalCase for types, methods, and properties; camelCase for parameters and locals;
  and the `I` prefix for interfaces.
- Suffix asynchronous methods with `Async` and return `Task` or `Task<T>`.
- Match public type names to filenames and avoid multiple public types in one file unless
  the repository already follows another convention.
- Do not fully qualify a type with its namespace when a `using` directive for that
  namespace is already present in the file — use the short type name (e.g. `FlowMessage`,
  not `Systex.ESOAF.Message.FlowMessage`, once `using Systex.ESOAF.Message;` is declared).
  Some legacy templates fully qualify everywhere out of habit even with the `using` in
  place; do not copy that verbosity into new code. Fully qualifying is still fine where it
  resolves an actual ambiguity between two imported namespaces.

## Copying From Legacy Templates

New files are often started by copying an existing legacy file in the same module (same
platform helper calls, same class shape) to stay consistent with the surrounding codebase.
That consistency is worth keeping for anything the platform actually depends on, but treat
every copied block as a hypothesis to check, not a given, for at least these three things:

- **Meaningless exception special-casing**: do not carry forward a `catch` that special-cases
  exception types which cannot occur on the new code's path (e.g. `DataSet`/`DataRelation`
  exceptions copied into a file that never merges tables or navigates relations). Collapse to
  a single `catch` that logs and rethrows instead of repeating dead branches for types that
  will never be thrown there.
- **N+1 access copied from a per-item loop**: when a legacy template issues one query per item
  in a loop, do not repeat that shape by default — batch it into a single parameterized `IN`
  clause, a temp table, or a table-valued parameter when the values are known up front. This
  applies to raw ADO.NET / hand-rolled data-access helpers exactly as much as it does to an
  ORM (see the N+1 review item below).
- **Mixed command-lifecycle style within one new file**: pick one pattern for a `SqlCommand`
  (or equivalent) — either one shared command reused with `Parameters.Clear()` between
  statements, or one command created per logical query — and use it consistently across the
  file. Do not let one branch reuse-and-clear while a sibling branch creates a fresh command
  per loop iteration; that inconsistency is a sign a block was pasted without checking it
  against the rest of the file.
- **Declare-then-immediately-overwrite locals**: check whether a copied local is actually read
  before its first reassignment. A template that does
  `var x = ExpensiveCall(); ... x = string.Format(..., ExpensiveCall(), ExpensiveCall());`
  is calling the expensive operation three times for one used result — collapse to a single
  call, store it once, and derive every value from that one result. This is common with
  reflection helpers like `MethodBase.GetCurrentMethod()` in logging boilerplate: call it once
  per method, not once per property read.
- **Declare-then-alias the same reference**: a local that is assigned once from a parameter or
  another variable, never reassigned to a different object, and only ever read via mutation
  (`local.Field = x`) or returned — is a redundant alias. Remove it and use the original
  reference directly. This is separate from “declared far from its first *use*” (a `SqlCommand`
  or `DataSet` that must live outside a `using` block for later code to read is not the
  problem); the problem is a variable that never earns its own identity in the first place.
  Also prefer declaring a resource directly in its `using (...)` header (`using (var cmd =
  db.CreateCommand(...))`) over pre-declaring it as `null` above the block and assigning it
  inside the `using(...)` expression, whenever nothing outside that block ever reads it.

Where changing a copied pattern would only affect the new file, change it. Where the platform
or sibling transactions may depend on the copied shape (a fixed error-code taxonomy, a
magic-string parameter convention used unchanged across every existing transaction), surface
the trade-off to the owner instead of silently diverging — matching one file's internal
consistency is not worth breaking cross-transaction consistency without a decision to do so.

## Review Checklist

- Reject `async void` except for event handlers.
- Catch exceptions at meaningful boundaries; do not silently swallow failures.
- Check EF or other ORM queries for N+1 access and unintended materialization; the same check
  applies to raw ADO.NET loops that issue one command per item instead of batching (see
  "Copying From Legacy Templates" above).
- Verify Singleton, Scoped, and Transient registrations against actual lifetimes.
- Validate API input at the boundary.
- Propagate and honor `CancellationToken` in long-running work.

## Tests and Commands

- Mirror the production project structure in `{ProjectName}.Tests`.
- Use the existing test framework. Use xUnit only when a new test project is explicitly
  approved and the repository has no established choice.
- Keep unit tests isolated from real databases and external services.
- Prefer `MethodName_Scenario_ExpectedResult` when the repository has no naming convention.
- Use `dotnet build` and `dotnet test` for supported SDK-style projects. Use the repository's
  established MSBuild invocation for .NET Framework solutions.

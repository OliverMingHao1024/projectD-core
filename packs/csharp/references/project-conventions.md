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

## Review Checklist

- Reject `async void` except for event handlers.
- Catch exceptions at meaningful boundaries; do not silently swallow failures.
- Check EF or other ORM queries for N+1 access and unintended materialization.
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

---
name: dotnet-clean-architecture
stacks: [dotnet]
description: "Author or audit a vertical slice in an ASP.NET Core Clean Architecture + CQRS codebase (Domain / Contracts / Application / Infrastructure / API, MediatR, EF Core + Npgsql, ErrorOr). Use when adding a feature, a command, a query or an endpoint to a .NET API; when reviewing whether a slice respects the layer contract; or when the user says 'clean architecture', 'CQRS', 'new endpoint', 'review the backend', 'add a command', 'is this in the right layer'."
trigger: /dotnet-clean-architecture
---

# .NET Clean Architecture

Two modes. Pick one before touching anything.

- **Author** — a new feature or endpoint. Follow the layout below; do not invent a new folder or a new pipeline behavior.
- **Audit** — an existing slice or a diff. Walk the checklist and report violations with `file:line`. Do not fix while auditing.

## Layer contract

```
API  ──►  Infrastructure  ──►  Application  ──►  Domain
 │                                 │
 └──────────►  Contracts  ◄────────┘
```

Direct project references only. `Application → Domain, Contracts`; `Infrastructure → Application`; `API → Application, Infrastructure`; tests → the project they test. `Domain` and `Contracts` reference no project. `Infrastructure → Domain` and `API → Domain|Contracts` arrive transitively — never write them.

| Layer | Owns | Must not |
|---|---|---|
| `Domain` | Entities, invariants (`static ErrorOr<T> Create`), `<Entity>Errors`, enums | Reference EF Core, ASP.NET, or any other layer. Depends on ErrorOr only |
| `Contracts` | `XxxRequest` in, `XxxResponse` out | Contain logic, or reference Domain types |
| `Application` | Commands, queries, handlers, validators, `XxxResult` records, behaviors, repository interfaces | Reference EF Core or HTTP |
| `Infrastructure` | `DbContext`, configurations, migrations, repositories, identity, interceptors, external services | Contain business rules |
| `API` | Carter modules, result mapping, auth policies, middleware, `Program.cs` | Contain business rules or touch `DbContext` |

## Layout

```
src/Application/UseCases/<Feature>/{Commands,Queries,Handlers,Validators,Common}
src/Contracts/<Feature>/Request/…   Response/…
src/Domain/<Aggregate>/<Entity>.cs, <Entity>Errors.cs
src/Infrastructure/Persistence/{Configurations,Repositories,Migrations}
src/API/Modules/<Resource>Module.cs
```

One type per file. `XxxCommand`/`XxxQuery` are `sealed record`; handlers and validators are `internal sealed class`. `net10.0`, `Nullable` and `ImplicitUsings` on, versions in `Directory.Packages.props`, one `DependencyInjection.cs` per layer.

## Endpoints (API)

- Carter module per resource, grouped under `/api/v{version}`, `RequireAuthorization()` by default; anonymous endpoints opt out explicitly.
- REST nouns, plural. Never RPC (`/get-all-students`).
- Every endpoint takes `CancellationToken` and passes it to `sender.Send`.
- Register a **method group**, never a lambda: `private static async Task<IResult> <Name>(ISender sender, …bound args…, CancellationToken ct)`. `ISender` first.
- Declare the wire contract: `.Produces<ApiSuccessResponse<XxxResponse>>(status)` per status the route can return, plus `.WithName("…")`. A file download declares its type too.
- Request → command with Mapster (`request.Adapt<XxxCommand>()`) **unless** a nullable request field feeds a non-nullable command field — there the manual `new XxxCommand(a, b, c)` with its `?? ""` is the behaviour, because Mapster would write null into a non-nullable string.
- One result mapper: success → `{ data }`, errors → ProblemDetails, validation → every error, not the first. Routes returning no body or a file keep an explicit `Match`.
- `201` through the project's `Created(uri, data)` helper.
- No `try/catch` in an endpoint. One `IExceptionHandler` behind `UseExceptionHandler()`; it never returns exception text to the client.

## CQRS (Application)

- Markers `ICommand<T>`, `ITransactionalCommand<T>`, `IQuery<T>`, all returning `ErrorOr<T>`. **The marker decides whether the pipeline saves**: a handler whose marker is not the one `PersistenceBehavior` matches answers 204 and persists nothing. When adding a behavior or a marker, check the pairing.
- Pipeline order: `ValidationBehavior` → `LoggingBehavior` → `PersistenceBehavior` (one `SaveChangesAsync` per successful command) → `TransactionBehavior` (only the transactional marker).
- Register validators with `includeInternalTypes: true`.
- Handler output is an Application `XxxResult`. The wire contract is the `Contracts` `XxxResponse`.
- The response side is implicit: the mapper finds the twin by name among `Contracts`. A trailing `Result` is optional, so `StudentResult` and `Student` both want `StudentResponse`. Nothing binds that name to the route's `.Produces<…>`, so renaming an Application record without its twin serializes the internal record while the spec keeps promising the contract, with no build error. Treat the `.Produces` type as part of the rename.
- A list is never adapted: for a `GET` returning a list declare `IReadOnlyList<XxxResponse>` and accept that it only types the spec.

## Domain and errors

- `static ErrorOr<T> Create(...)` enforces invariants. `private set` everywhere; state changes go through methods that return `ErrorOr<Success>`.
- `static class <Entity>Errors` with `public static readonly Error` fields. Domain invariants in Domain; lookup, auth and cross-entity errors in `Application/Common/Errors`.
- **Never throw for an expected business failure.** Return the error.
- `Error.Validation` is for a field the form shows. When the sentence itself is the payload the user must read, a validation error collapses into the generic title — use a custom 400 with its own code.

## Persistence (Infrastructure)

- EF Core + Npgsql, snake_case, one `IEntityTypeConfiguration<T>` per entity.
- Tenant isolation: every owned entity implements the scoping interface and gets a global query filter. Handlers never filter by tenant by hand. `IgnoreQueryFilters()` only in a handler that checks the privileged role.
- Tracking by default; reads `AsNoTracking()`. **A read that a write will edit must not be `AsNoTracking`** — add a tracked read beside the fast one.
- Optimistic concurrency on every editable entity: map a `Version` property as the row version (on Npgsql that is the `xmin` system column, no data column), return 409 on mismatch, never last-write-wins.
- A unique violation or a serialisation failure may arrive as a bare provider exception, **not** wrapped in `DbUpdateException`. Walk the exception chain and discriminate on the SQL state before letting it become a 500.
- Audit columns set by a `SaveChanges` interceptor, never by hand.
- Ownership lookups return Forbidden from a single query, so a caller cannot probe which ids exist.
- Migrations applied by the deployment (bundle) before the container swap.
- A custom `StringComparer` inside an `OrderBy` does not translate: project first, order in memory.

## Auth

- Identity with an `HttpOnly`, `SameSite=Lax`, `Secure` cookie; SPA and API on one origin.
- Antiforgery on every state-changing endpoint.
- Named policies, never inline role strings in a module. Every client-side role check gets its server-side policy.
- Current user and tenant come from the current-user abstraction, never from the request body.

## Config, logging, input

- Options: `SectionName` const, `ValidateDataAnnotations().ValidateOnStart()`.
- Serilog through a pipeline behavior; no manual logging in endpoints.
- Minimal API binding lets `null` into a non-nullable collection: guard `is not { Count: > 0 }` before `.Any()`/`.Select()`, or a malformed body is a 500.
- `Enum.TryParse` accepts out-of-range numerics (`"7"` into a four-value enum) and persists garbage. Pair every parse with `Enum.IsDefined`.

## Known defects — never copy

Guide projects are referenced for structure only, with these defects removed: a static shared exception field; `try/catch` in an endpoint leaking `ex.Message`; `UseExceptionHandler()` missing; only the first validation error returned; no `CancellationToken`; global `NoTracking`; `SameSite=None` without antiforgery; EF configuration inline in `OnModelCreating`; auth state read from local storage; status detected by matching messages; a base URL repeated per call; inline query keys.

## Audit scan

```bash
rg "PackageReference|ProjectReference" --glob "**/Domain*.csproj"    # only ErrorOr is allowed
rg "Infrastructure|EntityFrameworkCore" --glob "**/Application*.csproj"
rg "using .*Infrastructure|DbContext" --glob "src/Application/**/*.cs"
rg "DbContext|I\w+Repository" --glob "src/API/**/*.cs"
rg "throw new \w+Exception" --glob "src/Application/**/*.cs" --context 3
```

Report by finding with `file:line`, then ask which ones to fix. Fix in this order: project
references, Domain references, handlers, modules, exceptions. Run `dotnet build` and `dotnet test`
after each. One commit per kind of violation, prefix `fix(arch):`.

## Gate

`dotnet test` on the solution, `dotnet build` with zero warnings. Report the failing test name and the layer it belongs to, not the whole stack trace.

# Anti-patterns in .NET backends

Reference for `code-reviewer`. Not loaded into sessions; the short list Claude follows while writing
is `global/rules/dotnet.md`. When an entry contradicts the project's `CLAUDE.md` or the
`dotnet-clean-architecture` skill, the project wins. Entries that contradicted that skill
(Clean Architecture + CQRS + MediatR as over-engineering, MediatR by default, convention-based
mapping) were removed on purpose; do not add them back.

## How to prioritize

These six do the most damage in production; check them first in a code review.

1. Sync-over-async and a missing `CancellationToken`
2. N+1 queries and premature `ToList()` in EF Core
3. Misused `HttpClient` with no resilience
4. Captive dependencies and a badly scoped `DbContext`
5. Exposing EF entities directly in the API
6. Logging without structured templates, and exposed secrets

The rest of the document is grouped by topic. The more niche anti-patterns (cartesian explosion, Outbox, IDOR, etc.) appear next to the common ones in each category.

## Async and concurrency

- **`.Result` / `.Wait()` / `.GetAwaiter().GetResult()`** (sync-over-async): blocks ThreadPool threads and can cause deadlocks and thread starvation. Use `async/await` end to end.
- **`async void`** outside event handlers: exceptions can't be caught and they crash the process. Use `async Task`.
- **`Task.Run` inside controllers/handlers** to "make I/O code async": it only adds overhead. `Task.Run` is for CPU-bound work, and even then rarely in ASP.NET Core.
- **Forgetting the `CancellationToken`**: aborted requests keep running queries and HTTP calls. Propagate it down to EF Core / `HttpClient`.
- **Uncontrolled fire-and-forget** (`_ = DoSomethingAsync()`): lost exceptions and work cut off at shutdown. Use a `BackgroundService` with a `Channel<T>` or a real queue (Hangfire, MassTransit, etc.).
- **`lock` with `await` inside**: doesn't compile, and the temptation leads to misusing `Monitor`. Use `SemaphoreSlim`.
- **`ConfigureAwait(false)` in ASP.NET Core app code**: there is no `SynchronizationContext`, so it adds nothing and clutters the code. It does make sense in libraries.
- **`Task.WhenAll` over a shared `DbContext`**: running parallel queries on the same instance throws `InvalidOperationException`. Use one `DbContext` per task via `IDbContextFactory`.
- **`Parallel.ForEach` with async lambdas**: it doesn't await the tasks (behaves like `async void`). Use `Parallel.ForEachAsync` with `MaxDegreeOfParallelism`.
- **`Task.Run` + `.Result` to "fix" a deadlock**: hides the symptom, is still sync-over-async and burns threads.
- **`ValueTask` consumed twice or with `.Result` before completion**: it can only be awaited once. Use `ValueTask` only with evidence of a hot path.
- **Removing `async` from methods that just `return Task`**: valid to avoid the state machine, but an anti-pattern when there is a `using`/`try-catch` and the object is disposed before the task finishes.
- **`Task.Delay` as homegrown polling/retry**: use `PeriodicTimer` or Polly.
- **`BackgroundService` with an unhandled exception in `ExecuteAsync`**: since .NET 6 it takes down the host by default (`BackgroundServiceExceptionBehavior`). Wrap the loop in try/catch.
- **`BackgroundService` consuming scoped services directly**: captive dependency. Create a scope with `IServiceScopeFactory` per iteration.
- **`Thread.Sleep` in async code**: blocks the thread instead of releasing it. Use `await Task.Delay`.

## Entity Framework Core

- **N+1 queries**: iterating entities and accessing navigation properties (lazy loading) or running queries in a loop. Use `Include`, projections with `Select`, or `AsSplitQuery`.
- **Lazy loading enabled**: hides the N+1. Prefer explicit eager loading or projections.
- **Fetching full entities when you only need a few columns**: use `Select` into DTOs.
- **Not using `AsNoTracking()`** on read-only queries.
- **`ToList()` before filtering** (`context.Orders.ToList().Where(...)`): pulls the whole table into memory. Keep it `IQueryable` until the end.
- **Untranslatable C# functions "fixed" with `AsEnumerable()`**: you're back to pulling everything into memory.
- **Exposing `IQueryable` from repositories**: leaks the data layer and produces unpredictable queries.
- **`SaveChanges` inside a loop**: one round-trip per entity. Batch changes or use `ExecuteUpdate` / `ExecuteDelete` / bulk.
- **`DbContext` as a singleton or shared across threads**: it isn't thread-safe. It must be scoped (or use `IDbContextFactory`).
- **Generic repository over EF Core** (`IRepository<T>` with `GetAll`, `Add`...): it ends up a leaky, limiting abstraction. Declare one repository interface per aggregate, with the queries the use cases need, in the layer the project's architecture puts them.
- **Cartesian explosion** with multiple collection `Include`s: the JOIN multiplies rows. Use `AsSplitQuery` (aware of its consistency cost) or projections.
- **`Contains` with large lists**: generates huge SQL and non-cacheable plans. Use table-valued parameters, temp tables or `OPENJSON` depending on the provider.
- **`FirstOrDefault` without `OrderBy`**: non-deterministic results.
- **`Skip/Take` without a stable ordering** (ordering by a non-unique column): duplicate or missing rows across pages. On large tables offset pagination is slow: use keyset pagination.
- **`Count() > 0` instead of `Any()`**, or `Count()` on an already materialized `IEnumerable`.
- **Confusing `Find` with `FirstOrDefault`**: `Find` checks the change tracker first, and using it when you don't want that behavior gives stale reads.
- **Missing concurrency tokens** (`RowVersion`) on entities edited concurrently: silent lost updates.
- **Catching `DbUpdateConcurrencyException` and retrying** without reloading the entity.
- **`TransactionScope` + async** without `TransactionScopeAsyncFlowOption.Enabled`.
- **Mixing data and schema in migrations** (`HasData` for data that changes): fragile migrations that are hard to revert.
- **Ignoring compiled models / compiled queries** on high-frequency hot paths (only matters after measuring).
- **Value converters on columns used in filters**: if the conversion doesn't translate well, index usage is lost.
- **Forgotten global query filters** (soft delete, multi-tenant) and `IgnoreQueryFilters()` used for convenience: data leaks across tenants.
- **Entities with a public parameterless constructor + public setters**: allows invalid states. EF supports private constructors and backing fields.

## Dependency Injection

- **Service Locator** (`IServiceProvider.GetService` everywhere): hidden dependencies and code that is hard to test.
- **Captive dependency**: a singleton that depends on a scoped/transient service (e.g. a singleton holding a `DbContext`). Enable `ValidateScopes` and `ValidateOnBuild`.
- **Constructors with 8+ dependencies**: a sign the class violates SRP.
- **Using `new` for services with dependencies** instead of DI.
- **Registering everything as a singleton** "for performance" without considering shared state.
- **Filters with mutable state registered as singletons**: the state is shared across requests.

## HTTP and external communication

- **`new HttpClient()` per request**: socket exhaustion. Use `IHttpClientFactory` / typed clients.
- **Static `HttpClient` with DNS cached indefinitely**: use `SocketsHttpHandler` with `PooledConnectionLifetime`, or the factory.
- **No timeouts, retries or circuit breakers**: one failing service drags down the rest. Use Polly / `Microsoft.Extensions.Http.Resilience`.
- **Chained synchronous calls between microservices** (request cascades): temporal coupling. Consider messaging / events.
- **SSRF**: endpoints that receive a URL and call `HttpClient.GetAsync(url)` without an allowlist.

## ASP.NET Core and the pipeline

- **Wrong middleware order** (`UseAuthorization` before `UseRouting`/`UseAuthentication`, CORS after the endpoints).
- **Reading `Request.Body` without `EnableBuffering`** and expecting model binding to still work.
- **Middleware that replaces `Response.Body` with a `MemoryStream`** for logging: breaks streaming and eats memory.
- **Model validation disabled** (`SuppressModelStateInvalidFilter`) with no replacement.
- **Returning `200 OK` with `{ success: false }`** instead of real status codes and `ProblemDetails`.
- **Endpoints returning `IActionResult` without `[ProducesResponseType]`**: useless OpenAPI and generated clients typed as `object`.
- **`HttpContext` accessed from a background thread** (fire-and-forget): the context has already been recycled. Copy the data you need beforehand.
- **`IHttpContextAccessor` in domain/application layers**: hidden coupling to HTTP. Pass an abstract `ICurrentUser` instead.
- **Health checks that do heavy work** or don't distinguish liveness from readiness: Kubernetes kills healthy pods or routes traffic to pods that aren't ready.
- **In-memory-only rate limiting** with multiple instances: the effective limit is N times the configured one.
- **Output caching / response caching without a correct `Vary`**: one user's responses get served to another.
- **`[FromBody]` with domain types** and global `JsonSerializerOptions` forcibly changed just to "make it work".

## Architecture and design

- **Business logic in controllers** (fat controllers) or in stored procedures: hard to test and reuse.
- **Anemic Domain Model**: entities with only getters/setters and all the logic in "services". Move invariants into the entities.
- **Exposing EF entities directly in the API**: couples the public contract to the DB schema, with over-posting and data-leak risks. Use DTOs / request-response models.
- **Layers by technical concern instead of by feature** as the project grows (giant Controllers/Services/Repositories): consider vertical slices or domain modules.
- **Primitive obsession**: strings/ints for IDs, emails, amounts. Use value objects / strongly-typed IDs.
- **Feature flags as hardcoded `if`s** with no way to turn them off at runtime.

## Serialization

- **Mixing `Newtonsoft.Json` and `System.Text.Json`** without realizing it: attributes from one are ignored by the other.
- **Serializing enums as numbers** in public APIs: reordering them breaks contracts. Use `JsonStringEnumConverter`, mindful of compatibility.
- **Deserializing into `object`/`dynamic`/`JObject`** in the middle of the logic instead of using strong types.
- **Circular references "solved" with `ReferenceHandler.IgnoreCycles`** instead of fixing the model (it usually reveals that entities are being exposed).
- **`decimal` serialized as `double`** for money.
- **Serializing huge objects** without considering `System.Text.Json` source generators or streaming.

## Money, time, culture and types

- **`double`/`float` for amounts**: use `decimal`.
- **`DateTime` without `Kind` / without UTC** instead of `DateTimeOffset`: time zone bugs that only show up in production.
- **`DateTime.Now` / `DateTime.UtcNow` directly in the logic**: non-deterministic tests. Use `TimeProvider` (.NET 8+).
- **Comparing strings without `StringComparison`** or with `ToLower()`: culture-dependent (the famous Turkish-I problem) and allocates memory.
- **Implicit `CultureInfo`** when parsing/formatting numbers and dates: works on your machine and fails on the server with a different culture. Use `CultureInfo.InvariantCulture`.
- **`Guid.NewGuid()` as a clustered key in SQL Server**: index fragmentation. Use `Guid.CreateVersion7()` (.NET 9) or sequential GUIDs.
- **Enums without an explicit `0`/`Unknown` value**: `default(MyEnum)` accidentally becomes a valid business value.

## Error handling and logging

- **Empty `catch (Exception) { }`** or one that only logs and carries on.
- **`throw ex;`** instead of `throw;`: loses the stack trace.
- **Exceptions for control flow** (expected validations): expensive. Use the Result pattern or explicit validation.
- **Try/catch in every controller**: use global middleware / `IExceptionHandler` + `ProblemDetails`.
- **String interpolation in logs** (`_logger.LogInformation($"User {id}")`): breaks structured logging and always allocates. Use message templates: `LogInformation("User {UserId}", id)`.
- **Logging sensitive data** (tokens, passwords, PII).
- **Exceptions logged multiple times** (at every layer as they bubble up).

## Observability

- **No correlation IDs / tracing**: impossible to follow a request across services. Use OpenTelemetry.
- **High-cardinality metrics** (user id, full URL with IDs as a label): blows up the cost in Prometheus/App Insights.
- **Misused `LogLevel`**: everything at `Error` or everything at `Information`, or logging the full request body on every call.
- **`Activity`/spans without propagation** in background work or messaging: broken traces.
- **Logging inside hot loops** without the `LoggerMessage` source generator or an `IsEnabled` guard.

## Messaging and events

- **Publishing an event after `SaveChanges` without an Outbox**: if the process dies in between, state ends up inconsistent. Use the Transactional Outbox.
- **Non-idempotent consumers**: with at-least-once delivery, effects get duplicated. Store a message/idempotency key.
- **Infinite retries without a dead-letter queue**: poison messages that block the queue.
- **Two "atomic" writes to different systems** (DB + broker + external API) without a saga/compensation.
- **Messages that use internal domain entities/types as the contract**: coupling between services and impossible versioning.
- **Domain events dispatched inside a `SaveChanges` override** whose handlers have external side effects before the commit.

## Configuration and security

- **Secrets in `appsettings.json` or in the repo**: use User Secrets, Key Vault or environment variables.
- **Reading `IConfiguration["Key"]` everywhere**: use the Options pattern (`IOptions<T>`, `IOptionsSnapshot`, `ValidateOnStart`).
- **CORS `AllowAnyOrigin` in production.**
- **Concatenating SQL** with user input: use parameters (`FromSqlInterpolated`, Dapper with parameters).
- **Authorization only on the frontend** or scattered manual role checks: use policies and `[Authorize]`.
- **Validating only on the client** or not validating input at all.
- **Validating JWTs without checking `Audience`/`Issuer`/`ValidateLifetime`**, or with a huge `ClockSkew`.
- **Long-lived tokens with no refresh or revocation.**
- **IDOR** (Insecure Direct Object Reference): `GET /orders/{id}` without verifying the resource belongs to the user. Use resource-based authorization.
- **Mass assignment** with `TryUpdateModelAsync` or binding to entities.
- **Hashing passwords with SHA/MD5** or a homegrown scheme: use `PasswordHasher<T>`, Argon2 or bcrypt.
- **Inherited or forgotten `[AllowAnonymous]`** with no `FallbackPolicy` configured: set one so that secure is the default.
- **Data Protection keys not persisted or shared** across instances: invalid cookies/tokens after every deploy or between pods.
- **`BinaryFormatter`** and insecure deserialization of arbitrary types (`TypeNameHandling.All` in Newtonsoft).
- **Path traversal** when building file paths from user input without `Path.GetFullPath` + prefix validation.
- **Regex without a timeout** (ReDoS) on user input: use `RegexOptions.NonBacktracking` or `matchTimeout`.

## Performance and memory

- **Caching with no invalidation strategy**, or `IMemoryCache` in multi-instance apps without considering consistency. Use `HybridCache` / Redis as appropriate.
- **Loading huge collections into memory** instead of paginating or streaming (`IAsyncEnumerable`).
- **No pagination** on list endpoints.
- **String concatenation in loops** (use `StringBuilder`), heavy LINQ in hot paths and needless boxing.
- **Static mutable state** (`static Dictionary` without synchronization): race conditions.

## Testing and maintainability

- **Mocking `DbContext`/`IQueryable`**: mocks don't reproduce the real provider's behavior. Use Testcontainers, or SQLite/in-memory with care.
- **Tests coupled to the implementation** (verifying every mock call).
- **No controlled migrations**: manual changes to the production DB.
- **Applying migrations automatically at startup** with multiple instances: race conditions. Use a migration job or bundle.

## Deployment and operations

- **Apps without graceful shutdown**: the default `HostOptions.ShutdownTimeout` may be too short to drain work, and in Kubernetes `preStop` must be aligned with `terminationGracePeriodSeconds`.
- **Ignored Kestrel/thread pool configuration** in containers with CPU limits: check `Environment.ProcessorCount` and the GC mode (Server vs Workstation) against the container limit.
- **Docker images with the SDK at runtime** or running as root.
- **Environment differences handled with `#if DEBUG`** instead of configuration.
- **Ignored cold start** (JIT, `ReadyToRun`, warm-up) in serverless or aggressive autoscaling.

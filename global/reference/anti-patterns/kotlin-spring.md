# Anti-patterns in Kotlin APIs with Spring

Reference for `code-reviewer`. Not loaded into sessions; the short list Claude follows while writing
is `global/rules/kotlin-spring.md`. When an entry contradicts the project's `CLAUDE.md` or its
`.claude/rules/`, the project wins (for example `@Value` time windows, `REQUIRES_NEW` for best-effort
work, H2 in `@DataJpaTest`).

## How to prioritize

These six hurt most in production Spring APIs written in Kotlin; check them first in a code review.

1. N+1 queries and `spring.jpa.open-in-view` left enabled
2. Blocking calls inside coroutines or WebFlux handlers
3. `@Transactional` that silently doesn't apply (self-invocation, `private`/`final` methods, wrong scope)
4. Exposing JPA entities directly in the API (and Kotlin `data class` entities)
5. Missing timeouts, retries and circuit breakers on outbound calls
6. Secrets in `application.yml` and sensitive data in logs

The rest of the document is grouped by topic. Items assume Spring Boot 3.x, Kotlin 1.9+/2.x and Java 17+.

## Kotlin idioms in Spring

- **Not applying the `kotlin-spring` (all-open) and `kotlin-jpa` (no-arg) plugins**: Kotlin classes are `final` by default, so `@Transactional`, `@Cacheable`, `@Async` and lazy proxies fail or silently don't apply. Enable the plugins.
- **`!!` and `lateinit` as a way to satisfy the compiler**: NPEs and `UninitializedPropertyAccessException` at runtime. Model nullability honestly.
- **Platform types from Java APIs used unchecked**: `String!` can be null at runtime. Declare the nullability explicitly when receiving Java values.
- **Wrong nullability on request DTOs**: a non-null Kotlin property with Jackson and no Kotlin module yields confusing errors or nulls. Register `jackson-module-kotlin` (included with Boot) and validate.
- **Default parameter values hiding required input**: a missing JSON field silently takes the default. Decide which fields are truly optional.
- **`@Value` and `@ConfigurationProperties` with mutable `var` and defaults everywhere**: prefer immutable `data class` bound via constructor binding, with validation.
- **Scope functions abused** (`let`/`also`/`apply`/`run` chained several levels deep): code that's harder to read than plain statements.
- **Extension functions as a dumping ground** for business logic or hidden global behavior.
- **Top-level functions and `object` singletons holding mutable state or dependencies**: bypasses DI and makes testing hard.
- **`companion object` loggers created inconsistently**, or logging with string templates (`log.info("User $id")`): eager string building and no structured arguments. Use `logger.info { "..." }` (kotlin-logging) or parameterized messages.
- **Using `Optional` from Spring Data in Kotlin**: prefer nullable return types (`findByIdOrNull`).
- **Catching `Exception` broadly**, which also swallows `CancellationException` in coroutines.
- **Overusing sealed classes/`Result`** for every error path while still throwing exceptions in other layers: pick a consistent error model.

## JPA and Hibernate

- **N+1 queries**: iterating entities and touching lazy associations. Use `join fetch`, `@EntityGraph`, DTO projections or batch fetching (`@BatchSize`, `hibernate.default_batch_fetch_size`).
- **`spring.jpa.open-in-view` left at the default (`true`)**: keeps the persistence context open through view rendering, hiding lazy loading and holding DB connections too long. Disable it.
- **Kotlin `data class` as a JPA entity**: generated `equals`/`hashCode`/`toString` use all fields (including lazy relations and ids that change), `copy` breaks identity, and `final` classes defeat proxies. Use regular classes with identity-based `equals`/`hashCode`.
- **Bidirectional associations in `toString`/`hashCode`**: infinite recursion or accidental lazy loading.
- **`FetchType.EAGER` on collections or `@ManyToOne` defaults left eager**: cascades of joins on every query. Make associations lazy and fetch explicitly.
- **Cartesian products** from `join fetch` on multiple collections (`MultipleBagFetchException` or huge result sets): fetch in separate queries or use projections.
- **Returning entities when you need a few columns**: use interface/DTO projections or `select new`.
- **Loading entire tables** (`findAll()`) without pagination or streaming.
- **`Pageable` with unstable sorting** (non-unique sort keys) or deep offset pagination on large tables: use keyset pagination.
- **`CascadeType.ALL` and `orphanRemoval` by reflex**: accidental deletes and surprising persistence. Cascade only along real aggregate boundaries.
- **`@OneToMany` with `List` and no `@OrderColumn`/ordering**, or `Set` with a broken `hashCode`.
- **Saving in a loop** (`save` per entity): use batch inserts (`hibernate.jdbc.batch_size`) and be aware that `IDENTITY` ids disable batching.
- **Missing optimistic locking** (`@Version`) on concurrently edited entities: silent lost updates.
- **Native queries with string concatenation**: SQL injection. Use named parameters.
- **Relying on `ddl-auto=update`** outside local development: unmanaged schema changes. Use Flyway or Liquibase.
- **Long-lived entity references across transactions** (detached entities merged blindly): overwriting newer data.

## Transactions

- **Self-invocation**: calling a `@Transactional` method from another method of the same class bypasses the proxy, so no transaction starts. Move it to another bean or use programmatic transactions (`TransactionTemplate`).
- **`@Transactional` on `private`/`final` methods or non-Spring-managed classes**: ignored (or needs the all-open plugin in Kotlin).
- **Transaction on the controller** or around entire request flows: connections held while doing slow work. Put it on the service layer around the smallest unit of work.
- **Remote calls inside a transaction** (HTTP, messaging, email): long-held connections and inconsistent state when the remote call succeeds and the commit fails. Call after commit (`@TransactionalEventListener(AFTER_COMMIT)`) or use an Outbox.
- **Checked exceptions don't roll back by default** (`rollbackFor` needed), and in Kotlin all exceptions are unchecked at the language level, which makes this easy to forget: be explicit about which failures must roll back.
- **Catching the exception inside the transactional method** and continuing: the transaction is marked rollback-only and fails at commit with `UnexpectedRollbackException`.
- **Missing `readOnly = true`** on query-only services (no flush, possible routing to replicas) or using it while writing.
- **`REQUIRES_NEW` used to "fix" problems**: separate connections, deadlock risk and partial commits. Use it intentionally (e.g. audit logs).
- **`@Transactional` on suspend functions with coroutines** without understanding context propagation: transaction context is bound to the coroutine context, not the thread. Use Spring's coroutine support with reactive transaction managers, or keep blocking JPA code off coroutine dispatchers.
- **`@Async` + `@Transactional`** assuming the new thread shares the caller's transaction: it doesn't.
- **Lazy loading outside a transaction** (`LazyInitializationException`) "fixed" by enabling open-in-view or `EAGER`: fetch what you need inside the service.
- **Distributed transactions faked with try/catch** across DB and broker: use Outbox/saga patterns.

## Coroutines and WebFlux

- **Blocking calls inside coroutines or reactive handlers** (JDBC/JPA, `Thread.sleep`, blocking HTTP clients, file I/O): starves the event loop threads. Wrap unavoidable blocking code in `withContext(Dispatchers.IO)` or use non-blocking drivers (R2DBC, WebClient).
- **`runBlocking` inside request handlers or suspend code**: defeats the purpose and can deadlock. Use it only at program boundaries (e.g. `main`, tests).
- **`GlobalScope.launch`** for background work: unstructured, leaks and ignores cancellation. Use a scope tied to the component's lifecycle (`CoroutineScope` with `SupervisorJob`, cancelled on shutdown) or Spring's `@Async`/scheduling.
- **Swallowing `CancellationException`** with `catch (e: Exception)`: breaks cancellation. Rethrow it.
- **Mixing Spring MVC (blocking) and WebFlux** in the same app without a clear reason: the reactive stack gives no benefit if the data layer blocks.
- **Choosing WebFlux by default** when the team and workload don't need it: virtual threads (Java 21, `spring.threads.virtual.enabled=true`) or plain MVC with proper pools may be simpler.
- **Unbounded concurrency** (`async` for every item in a huge collection, `flatMap` without concurrency limits): memory spikes and downstream overload. Limit with `Semaphore`, `chunked`, or `flatMapMerge(concurrency)`.
- **`async { }` immediately followed by `await()`** (sequential in disguise) or sequential `suspend` calls that could run in parallel with `coroutineScope { async { } }`.
- **Wrong dispatcher**: CPU-bound work on `Dispatchers.IO`, or blocking work on `Dispatchers.Default`.
- **Lost context** (MDC, security context, tracing) across coroutine boundaries: propagate with `MDCContext` and Micrometer context propagation.
- **`Flow` collected multiple times** (cold flows re-execute) or exposed from repositories with no backpressure strategy.
- **Not setting timeouts** (`withTimeout`, WebClient `timeout`, connection pool sizes): stuck requests pile up.
- **Returning `Mono`/`Flux` from non-reactive code**, or calling `.block()` in the middle of a reactive chain.

## Dependency injection and configuration

- **Field injection (`@Autowired lateinit var`)**: hidden dependencies, mutable state and hard-to-test classes. Use constructor injection with `val` properties.
- **Constructors with 8+ dependencies**: a sign the class violates SRP.
- **Service locator via `ApplicationContext.getBean`** scattered in code.
- **Circular dependencies "fixed" with `@Lazy`** or setter injection instead of redesigning the relationship.
- **Stateful singleton beans** (mutable fields shared across requests): race conditions. Beans are singletons by default.
- **Captive dependencies**: a singleton holding a `prototype`/request-scoped bean directly. Use `ObjectProvider` or scoped proxies.
- **Component scanning the whole classpath** with a broad base package, or `@Component` on everything: slow startup and accidental beans. Keep packages and `@Configuration` boundaries intentional.
- **`@Configuration` classes with business logic** or `@Bean` methods with side effects.
- **Reading `Environment`/`@Value("\${...}")` all over the code** instead of typed `@ConfigurationProperties` with validation (`@Validated`).
- **Properties without defaults or validation**: failures show up in production, not at startup. Fail fast.
- **Profiles used as feature flags** or for too many environment forks: configuration drift. Externalize config and keep profiles small.
- **Secrets in `application.yml`/the repo**: use environment variables, a secrets manager (Vault, AWS/GCP secrets) or Kubernetes secrets.
- **`@SpringBootTest` for the setup of every test** because the app can't start in a slice: modularize configuration.
- **Conditional beans (`@ConditionalOnProperty`) multiplied** so nobody knows which beans are active in each environment.

## REST API design

- **Exposing JPA entities directly in responses and requests**: couples the contract to the schema, risks over-posting and lazy-loading serialization errors. Use request/response DTOs.
- **Mapping DTOs by hand everywhere, or by reflection magic**: prefer explicit mapping functions or a compile-time mapper (MapStruct, Mapperly-style generators) with tests.
- **No input validation** or validating only in the service: use Bean Validation on DTOs (`@Valid`, `@field:NotBlank`). In Kotlin, remember the **use-site target** (`@field:`/`@get:`), otherwise the annotation doesn't apply.
- **Returning `200 OK` with an error body**, or inconsistent error formats: use proper status codes and RFC 9457 `ProblemDetail` via `@RestControllerAdvice`.
- **`try/catch` in every controller** instead of a global exception handler.
- **Leaking internal details** in error responses (stack traces, SQL messages, class names).
- **No pagination on list endpoints**, or unbounded `size` parameters: cap page size and sort fields.
- **Using `PUT`/`POST` loosely**, non-idempotent `PUT`, or state changes via `GET`.
- **Verbs in URLs and inconsistent naming** (`/getUsers`, `/user/{id}/delete`): use resource-oriented routes.
- **Breaking changes with no versioning strategy**: removing or renaming fields in place. Version the API or evolve it additively.
- **Returning `null`/missing collections** instead of empty lists, or mixing `null` and absent fields without a documented convention.
- **Serializing dates as local strings without zone** or as epoch values inconsistently: use ISO-8601 with offsets (`Instant`/`OffsetDateTime`).
- **Enums serialized by ordinal** or unknown enum values crashing deserialization: configure tolerant handling and use string values.
- **Undocumented or hand-written OpenAPI that drifts from the code**: generate it (springdoc) and run contract tests.
- **Idempotency ignored for payments and creates**: support `Idempotency-Key` for retried POSTs.

## Architecture and design

- **Business logic in controllers or repositories**: keep controllers thin and put rules in services or the domain model.
- **Anemic domain model**: entities with only properties and every rule in `*Service` classes. Move invariants into the domain.
- **"Service" classes that are giant grab-bags** (`UserService` with 40 methods): split by use case or capability.
- **Layers by technical type** (`controller/`, `service/`, `repository/`) in a big codebase: prefer package-by-feature with clear module boundaries (Spring Modulith can enforce them).
- **Over-engineering**: hexagonal + CQRS + event sourcing + mappers between every layer for a simple CRUD. Match the architecture to the problem.
- **Interfaces with a single implementation for everything**, and `*Impl` suffixes without a real seam.
- **Generic repository/CRUD base classes** that leak persistence concerns and hide intent. Spring Data repositories are already the abstraction.
- **Spring Data repository method names that grow into unreadable queries** (`findByAAndBOrCAndDOrderByE`): use `@Query` or Specifications/QueryDSL.
- **Entities shared between modules or microservices**: coupling through the database model. Share contracts, not entities.
- **Primitive obsession**: `String`/`Long` for ids, emails and money. Use value classes (`@JvmInline value class`) where they are supported by your serialization and persistence setup.
- **`Double` for money**: use `BigDecimal` or integer minor units.
- **Time via `Instant.now()` / `LocalDateTime.now()` everywhere**: untestable logic. Inject a `Clock`.
- **God `utils` packages and static helper objects** with hidden dependencies.
- **Microservices by default**: distributed monolith with shared databases and synchronous call chains. Start modular and split with a reason.

## Security

- **Authorization only at the edge** (URL matchers) with no method-level or resource-level checks: IDOR. Verify that the resource belongs to the caller (`@PreAuthorize`, ownership checks).
- **`permitAll()` and `anyRequest().permitAll()` left over** from development, or no default-deny rule: end with `anyRequest().authenticated()`.
- **Disabling CSRF globally** for cookie-based sessions (it's fine for stateless token APIs, but decide deliberately).
- **JWT validated without checking issuer, audience, expiry and signature algorithm**, or accepting `none`/weak algorithms. Use Spring's resource server support and a trusted JWKS.
- **Long-lived tokens with no refresh/revocation strategy**, or tokens stored client-side where scripts can read them.
- **Roles/authorities checked by string literals** scattered everywhere: centralize permissions and test them.
- **Passwords hashed with SHA/MD5** or custom schemes: use `DelegatingPasswordEncoder`, bcrypt, Argon2 or scrypt.
- **CORS `allowedOrigins("*")` with credentials** or reflecting any `Origin`.
- **Actuator endpoints exposed publicly** (`management.endpoints.web.exposure.include=*`) leaking env, heap dumps and metrics: expose minimal endpoints and secure them.
- **Mass assignment**: binding request bodies directly to entities or allowing clients to set fields like `role` and `id`.
- **SQL injection** via string-concatenated JPQL/native queries or `Specification` built from raw input.
- **SSRF**: fetching user-supplied URLs without an allowlist.
- **Insecure deserialization and Jackson default typing** (`activateDefaultTyping`) on untrusted input.
- **Logging sensitive data** (tokens, passwords, PII) and returning detailed errors to clients.
- **Secrets in the repo, images or `application.yml`**: use a secrets manager and rotate.
- **Outdated dependencies with known CVEs**: automate updates and run dependency scanning (OWASP Dependency-Check, Dependabot).
- **Rate limiting and brute-force protection missing** on login and expensive endpoints.

## Performance, caching and resilience

- **No timeouts on outbound calls** (`RestTemplate`/`RestClient`/`WebClient`/Feign defaults are often infinite or very long): set connect, read and response timeouts.
- **No retries, circuit breakers or bulkheads** (Resilience4j): one slow dependency exhausts your threads.
- **Retrying non-idempotent calls blindly**, or retrying without backoff and jitter: retry storms.
- **Creating a new HTTP client per request**: lose connection pooling. Reuse configured beans.
- **Default connection pool sizes** (HikariCP, HTTP clients) never tuned or measured; or pools much larger than the DB can handle.
- **Thread pool defaults ignored** (Tomcat max threads, `@Async` executor, scheduler pool of size 1): tasks queue up or block each other. Define bounded, named executors.
- **`@Cacheable` with no TTL, size limit or invalidation strategy**, caching mutable or user-specific data under shared keys.
- **Caching on self-invoked or `private` methods**: the proxy is bypassed (same issue as transactions).
- **Local caches in multi-instance deployments** without considering inconsistency: use Redis or a distributed cache where needed.
- **Cache stampede** on expiry for hot keys: use request coalescing, jittered TTLs or refresh-ahead.
- **Large payloads returned in full** instead of pagination, compression or streaming.
- **Serialization of large object graphs** with default Jackson settings and unused fields: use DTOs and `@JsonInclude`.
- **Unindexed queries and `SELECT *` on large tables**: check execution plans (`EXPLAIN`) and add indexes deliberately.
- **Premature optimization**: tuning without profiling. Measure with JFR, async-profiler and Micrometer first.
- **JVM defaults ignored in containers**: set memory limits and heap sizing (`-XX:MaxRAMPercentage`) and watch GC behavior.

## Messaging, scheduling and observability

- **Publishing an event after committing the DB transaction without an Outbox**: a crash in between loses or duplicates events. Use the Transactional Outbox.
- **Non-idempotent consumers** with at-least-once delivery (Kafka, RabbitMQ): store an idempotency key or make handlers idempotent.
- **Infinite retries with no dead-letter topic/queue**: poison messages block partitions.
- **Auto-commit offsets** while processing is still in flight: lost messages on failure. Commit after successful handling.
- **Kafka consumers doing slow work inside `poll` loops** and exceeding `max.poll.interval.ms`: rebalances and duplicates.
- **Messages using internal entities as the contract**: no schema evolution. Use versioned schemas (Avro/Protobuf/JSON Schema) and a registry.
- **`@Scheduled` jobs running on every instance** of a multi-instance deployment: duplicate work. Use a distributed lock (ShedLock) or a dedicated job runner.
- **`@Scheduled` tasks with a single-thread default scheduler** blocking each other, and `fixedRate` jobs that overlap when slow.
- **`@Async` with the default executor** or without error handling: lost exceptions (void methods) and unbounded queues.
- **`@EventListener` for critical side effects** inside the transaction thread: a failing listener breaks the caller. Choose transactional event phases deliberately.
- **Logging with string interpolation** and no structure: use parameterized/structured logging (JSON) with correlation ids.
- **Missing correlation/trace ids** across services: use Micrometer Tracing/OpenTelemetry.
- **High-cardinality metric tags** (user ids, raw URLs): explodes the metrics backend. Use route templates.
- **No health probes separation** (liveness vs readiness) or health checks that call every dependency on each probe.
- **Catching and logging the same exception at each layer**: duplicate noise. Log once where it's handled.

## Testing, migrations and deployment

- **`@SpringBootTest` for everything**: slow suites. Use slices (`@WebMvcTest`, `@DataJpaTest`, `@JsonTest`) and plain unit tests where possible.
- **Using H2 in place of the production database** for repository tests: dialect and behavior differences hide bugs. Use Testcontainers with the real engine.
- **Mocking repositories and entity managers** so heavily that tests only verify the mock interactions.
- **Overusing MockK/Mockito `verify`** on every call: tests coupled to the implementation.
- **Shared mutable test data and test ordering dependencies**: flaky tests. Isolate with transactions/cleanup or per-test containers.
- **`Thread.sleep` in tests**: use Awaitility or coroutine test utilities (`runTest`, virtual time).
- **No contract tests** between services or with the frontend: breaking changes slip through (Spring Cloud Contract, Pact).
- **No security tests**: verify authorization rules with `@WithMockUser` and slice tests.
- **Schema managed by `ddl-auto`** or hand-edited in production: use Flyway/Liquibase, versioned and reviewed.
- **Destructive migrations in a single step** (rename/drop columns while old instances still run): use expand/contract and backward-compatible migrations.
- **Running migrations at startup on every instance** at once: lock contention and race conditions. Use a migration job or rely on the tool's locking carefully.
- **Fat JARs with slow, huge Docker images** and running as root: use layered JARs/buildpacks or jlib-style slim images, and a non-root user.
- **No graceful shutdown** (`server.shutdown=graceful`) and misaligned Kubernetes termination settings: dropped in-flight requests during deploys.
- **Ignoring startup time** (classpath scanning, heavy auto-configuration): consider lazy initialization, AOT/GraalVM native images or CRaC where it matters.
- **Environment-specific code paths** instead of configuration, and "works on my machine" setups with no reproducible local environment (Docker Compose, Testcontainers dev services).

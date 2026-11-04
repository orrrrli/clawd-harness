---
paths:
  - "**/backend/src/**/*.kt"
---

# Kotlin + Spring API anti-patterns

Shapes you would otherwise write. Budget: 10 lines; a new one displaces the weakest.
The glob needs the Spring module in a `backend/` folder, so Android apps never load it.

- Never wrap a call to a `@Transactional` bean or a repository in `runCatching`/`catch (e: Exception)` inside a transaction to make it best-effort: the tx is already rollback-only and fails at commit. Run it before the tx, in `REQUIRES_NEW` on another bean, or `AFTER_COMMIT`.
- Never call an annotated method of the same bean, from the class or from a default interface method. It runs past the proxy, so `@Transactional` does not apply. Move it to another bean.
- Never write a Kotlin default parameter that reads a field of a Spring bean. Through the CGLIB proxy the field is null. Declare `x: T? = null` and resolve it in the body.
- Never make an HTTP call or file upload inside a `@Transactional` method. Do it before the transaction, or `AFTER_COMMIT`/outbox.
- Never put `@Transactional` or entity writes on a controller. The controller calls one service method; the service owns the transaction.
- Never call `repository.save()` per element in a loop, or on an entity already managed in this transaction. Dirty checking writes it; for new rows, collect them and `saveAll`.
- Never call `Instant.now()` in service or job logic. Take `clock: Clock = Clock.systemUTC()` in the constructor and call `clock.instant()`.
- Never write `x!!`. Use `requireNotNull(x) { "..." }`, `?: throw`, or a smart-cast null check.

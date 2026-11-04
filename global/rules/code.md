---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,cs,go,kt,kts,swift,py,java}"
---

# Code anti-patterns (every stack)

Shapes you would otherwise write. Budget: 10 lines; a new one displaces the weakest.

- Never create an interface with one implementation unless it is a real seam: an outside dependency (I/O, HTTP, email, payments, storage, queues, clock, random, id generation), a contract an inner layer owns and an outer layer implements, or a published library contract. A business-logic `IFooService` with one `FooService` is slop: use the class, and extract the interface when a seam appears.
- Never write a catch that only rethrows, only logs, or swaps the error for generic text. Handle it, or let it propagate to the layer that can.
- Never name a type `*Manager`, `*Helper`, `*Utils`, or a `*Service` that groups unrelated methods. Name it after what it does.
- Never nest conditionals more than 2 levels. Use guard clauses and early returns.
- Never skip input validation on an API endpoint.

---
name: audit-layer-boundaries
stacks: [web]
description: Scan the codebase for the three architectural violations that break a layered TypeScript contract. Use when adding new features, after a large refactor, or whenever you suspect imports have drifted.
---

# Audit Layer Boundaries

Scan for violations of the layer contract. This project enforces a strict import direction:

```
app/api/       ← composition root — imports ONLY from use-cases/
    ↓
use-cases/     ← business logic — imports ONLY from repositories/ and domain/
    ↓
repositories/  ← data access — imports ONLY from infrastructure/ and domain/
    ↓
infrastructure/← clients (prisma, redis, stripe, cloudinary, resend, etc.)
```

`domain/` and `shared/` are dependency-free and importable from any layer.

---

## The Three Patterns to Find

### Pattern 1 — Use-case imports from infrastructure

A use-case file (`use-cases/**`) contains `from '@/infrastructure/`.

**Why it breaks things:** The repository layer is the only place that should know about concrete infrastructure clients. A use-case that bypasses it couples business logic to implementation details — you can't swap the underlying client without editing use-case code.

**Fix:** Create or update a repository file that re-exports (or wraps) the infrastructure function. Update the use-case to import from the repository.

---

### Pattern 2 — Repository imports from another repository

A repository file (`repositories/**`) contains `from '@/repositories/`.

**Why it breaks things:** Repositories are supposed to be independent units that each wrap one concern. Cross-importing creates hidden coupling — a change to `order.repository.ts` can silently break `order-lifecycle.repository.ts`. It also makes it impossible to test either repository in isolation.

**Fix:** Inline the needed function directly in the importing repository. If both repositories need shared logic (e.g., a Prisma mapper), extract it to a `repositories/shared/` or `repositories/*.mapper.ts` file — which is a pure utility, not a repository.

---

### Pattern 3 — Business logic inside a repository

A repository method does more than data access: it validates invariants, accumulates business errors, or makes decisions about domain state.

Signals to look for:
- A method checks multiple conditions BEFORE writing (non-atomic pre-check)
- A method throws a domain error class (e.g., `InsufficientStockError`) outside of a tx race-condition handler
- A method validates that fields satisfy a business rule (e.g., `totalPrice === itemsPrice + taxPrice + shippingPrice`)

**Why it breaks things:** Repositories should be dumb — they execute operations, they don't decide whether to. Business rules belong in use-cases where they can be tested independently of Prisma.

**Fix:**
1. Add a query method to the repository that reads the data needed for the check (pure data access, no decision).
2. Add the method to the corresponding `I*Repository` interface in `domain/`.
3. Move the decision logic into the service's method — call the query method, evaluate the result, throw if violated, then call the repository operation.

Note: throwing `InsufficientStockError` INSIDE an atomic transaction (race-condition safety net) is acceptable — that is still the repository reacting to a write conflict, not making a business decision.

---

## Process

### 1. Scan

Run these searches and record every match:

```bash
# Pattern 1: use-cases importing from infrastructure
rg "from '@/infrastructure/" use-cases/

# Pattern 2: repositories importing from other repositories
rg "from '@/repositories/" repositories/

# Pattern 3: domain error classes thrown from repositories (outside tx context)
rg "throw new.*Error" repositories/ --context 5
```

For Pattern 3, also scan for:
- Calls to `prisma.inventoryItem.findMany` (or similar) BEFORE a `prisma.$transaction` in the same method — this is usually a non-atomic pre-check
- Arithmetic comparisons on money or other domain fields inside repository methods

### 2. Report

Present violations grouped by pattern. For each violation:
- **File + line** of the import or the rule
- **What it does** (one sentence)
- **Which fix applies** (from the three patterns above)

Do NOT automatically fix. Show the list and ask: "Which violations do you want me to fix?"

### 3. Fix

For each approved fix, follow the pattern exactly:

**Pattern 1 fix steps:**
1. Check if a repository adapter already exists for this infrastructure module.
   - If yes: add the needed export to the existing repository file.
   - If no: create `repositories/<name>.repository.ts` with re-exports from infrastructure.
2. Update the use-case import.
3. Run the project's test command — confirm no regressions.

**Pattern 2 fix steps:**
1. Copy the function body from the imported repository into the importing one (inline it).
2. If both repositories now duplicate a mapper or small utility, extract it to a `repositories/*.mapper.ts` file. Both import from there — that is NOT a cross-repository import.
3. Remove all `from '@/repositories/*'` imports from the repository.
4. Remove the exported functions from the source repository if nothing else imports them.
5. Run `pnpm test` — confirm no regressions.

**Pattern 3 fix steps:**
1. Extract the data-reading part of the pre-check into a new method (e.g., `checkStockAvailability`).
2. Add the new method signature to the corresponding `I*Repository` interface in `domain/`.
3. Implement the method in the repository — it returns the issues array, NOT throws.
4. In the use-case, call `this.repo.checkStockAvailability(...)`, then evaluate the result, then throw if needed.
5. Remove the pre-check and invariant validation from the repository method.
6. Run `pnpm test` — confirm no regressions.

### 4. Commit

One commit per pattern. Prefix: `fix(arch):`.

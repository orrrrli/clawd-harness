---
paths:
  - "**/*.swift"
---

# Swift (iOS) anti-patterns

Shapes you would otherwise write. Budget: 10 lines; a new one displaces the weakest.

- Never `try? await` a server mutation or a load that fills the screen and carry on as if it worked. Use `do/catch` and show the failure; `try?` only where nil is a real answer.
- Never set error state in a `catch` inside a cancellable task (`.task(id:)`, debounced search, replaced `Task`) without `guard !Task.isCancelled else { return }` or `catch is CancellationError` first.
- Never reload on `.onChange(of: x) { Task { state = await load() } }`, and never write a `.task` that ignores an input it reads. Use `.task(id:)` with every input in the id.
- Never measure a view with `GeometryReader { Color.clear.preference(key:) }`. Use `.onGeometryChange(for:of:action:)`.
- Never write `default:` in a switch over an enum the app owns. List every case, so a new case fails to compile.
- Never add a type to a file named for another type or past ~1000 lines. Create `<TypeName>.swift`.
- Never type a view parameter or return value as `AnyView`. Take a generic `@ViewBuilder content: () -> Content`.
- In tests, never wait with `Task.sleep` loops or polling helpers. Await the work, or use `confirmation` or an injected clock.

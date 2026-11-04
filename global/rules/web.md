---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs}"
---

# Web anti-patterns (TypeScript / JavaScript)

Shapes you would otherwise write. Budget: 10 lines; a new one displaces the weakest.
`any` is banned in `behavior.md`, so it holds in every file type.

- Never call `fetch` or write an inline `queryKey: [...]` in a component. Go through the project's API client and its query hooks / key factory.
- Never cast external data at the call site (`await res.json() as T`, untyped `res.json()`, `data!`, `session.user!`). Type it once in the API client and narrow with a guard clause.
- Never hardcode colors (`text-[#101010]`, `style={{ color: '#...' }}`). Use the project's tokens or CSS variables.
- Never put `onClick` on a `div`/`span`/`tr`, and never navigate with `onClick={() => router.push()}`. Use `<button>` or `<Link>`.
- Never put the HTTP status in an error message and branch on `message.includes('401')`. Throw an error that carries `status`.
- (React) Never mirror a prop into state with `useEffect(() => setX(prop), [prop])`, and never disable `exhaustive-deps` or `set-state-in-effect`. Derive it in render or reset with `key`.
- Never hand-roll a modal (`fixed inset-0` div + backdrop `onClick`). Use the project's Dialog primitive or `<dialog>`, and give icon-only buttons an `aria-label`.
- (Zustand) Never destructure the whole store (`const { a } = useStore()`). Select a slice: `useStore(s => s.a)`.
- Never compute money with floats and `toFixed`. Use integer cents.

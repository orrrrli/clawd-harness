# Anti-patterns in web frontends

Reference for `code-reviewer`. Not loaded into sessions; the short list Claude follows while writing
is `global/rules/web.md`. When an entry contradicts the project's `CLAUDE.md` or the
`audit-layer-boundaries` skill, the project wins. Feature-based folders as the only valid layout
were removed on purpose: layered projects (domain / use-cases / repositories / presentation) are a
deliberate choice; do not add them back.

## How to prioritize

These six hurt users most in production; check them first in a code review.

1. Oversized JavaScript bundles and render-blocking work on the main thread
2. Request waterfalls and data fetching with no caching or cancellation
3. Inaccessible markup (div soup, missing labels, broken keyboard navigation)
4. XSS vectors and tokens stored in `localStorage`
5. Server state copied into global client state and kept in sync by hand
6. `useEffect` used for everything (derived state, data sync, event handling)

The rest of the document is grouped by topic. Examples use React and TypeScript where a framework matters, but most items apply to any modern stack.

## JavaScript and TypeScript

- **`any` everywhere**: turns TypeScript into JavaScript with extra steps. Use `unknown` plus narrowing, and generics where needed.
- **Type assertions (`as Foo`) instead of validation**: API responses are not typed just because you said so. Validate at the boundary (Zod, Valibot, etc.).
- **Turning off `strict`** or sprinkling `// @ts-ignore`: the bugs come back at runtime. Prefer `@ts-expect-error` with a reason, and enable `strict`.
- **Mutating state or props directly** (`arr.push`, `obj.x = 1`) in frameworks that rely on reference equality: missed updates and stale UI.
- **Unhandled promise rejections** and missing `await` in async handlers: silent failures. Handle errors explicitly and lint for floating promises.
- **`async` callbacks passed to `forEach`**: it doesn't await them. Use `for...of` or `Promise.all` with `map`.
- **Sequential `await` for independent calls**: use `Promise.all` / `Promise.allSettled`.
- **Loose equality and truthiness checks** (`if (count)` when `0` is valid, `==` between types): use explicit comparisons.
- **Floating-point money math** (`0.1 + 0.2`): use integer minor units or a decimal library.
- **Date handling with raw `Date` and string parsing**: time zone bugs. Use `Intl`, `Temporal` (when available) or a library, and store UTC.
- **Deep cloning with `JSON.parse(JSON.stringify(x))`**: drops `Date`, `undefined`, `Map`, `Set`. Use `structuredClone`.
- **Enums and string literals mixed without a single source of truth**: prefer union types derived from a `const` object.
- **Barrel files (`index.ts`) re-exporting everything**: defeat tree shaking and slow down builds and tests.
- **Giant utility files (`utils.ts`, `helpers.ts`)**: no cohesion, circular imports. Name each function by what it does and place it where the project's structure puts that concern.

## Component architecture and rendering

- **`useEffect` for derived state**: computing values from props/state inside an effect and storing them in more state causes extra renders and sync bugs. Compute during render (`useMemo` only if measured).
- **`useEffect` for event handling**: logic that belongs in an event handler runs on the wrong trigger. Reserve effects for synchronizing with external systems.
- **Missing or wrong dependency arrays**: stale closures and infinite loops. Enable `react-hooks/exhaustive-deps` and fix the cause instead of silencing it.
- **Missing cleanup in effects** (listeners, timers, subscriptions, fetches): memory leaks and updates on unmounted components.
- **Array index as `key`** in lists that reorder, insert or delete: wrong state attached to wrong rows. Use stable IDs.
- **Defining components inside components**: a new component type on every render, so state is lost and the subtree remounts.
- **Inline objects/functions as props to memoized children**: defeats `React.memo`. Memoize only where profiling shows a problem.
- **`useMemo`/`useCallback` everywhere "just in case"**: noise and overhead without evidence. Measure first.
- **Prop drilling through many layers**, or the opposite, putting everything in context: context changes re-render every consumer. Use composition, colocated state, or split contexts.
- **God components** (500+ lines mixing fetching, state, layout and business logic): split into hooks and presentational components.
- **Copying props into state** (`useState(props.value)`): the state goes stale when the prop changes. Use a controlled component or a `key` to reset.
- **Direct DOM manipulation** (`document.querySelector`) inside framework code: fights the renderer. Use refs.
- **Rendering huge lists without virtualization**: thousands of DOM nodes. Use windowing (e.g. TanStack Virtual) or pagination.

## State management

- **Global store for everything**: local UI state (open/closed, input values) doesn't belong in Redux/Zustand. Keep state as close to where it's used as possible.
- **Server state copied into a client store** and synced by hand: stale data, manual loading/error flags. Use a data-fetching cache (TanStack Query, SWR, RTK Query).
- **Duplicated sources of truth**: the same data in a store, in component state and in the URL. Pick one owner.
- **Derived data stored instead of computed**: `fullName` kept in state next to `firstName` and `lastName`. Derive it with selectors.
- **Filters, tabs and pagination not in the URL**: refresh and share links lose the view. Put shareable state in search params.
- **Boolean explosion** (`isLoading`, `isError`, `isSuccess`, `isEmpty` combinations that can't all be true): impossible states. Use a discriminated union or a state machine.
- **Over-broad selectors** (`useStore(state => state)`): every update re-renders the component. Select only what you need.
- **Persisting sensitive or huge state** to `localStorage` without versioning or expiry: stale shapes break the app after a deploy.
- **Optimistic updates without rollback**: the UI lies when the request fails.

## Data fetching and networking

- **Request waterfalls**: a child component fetches only after its parent finishes, serializing independent requests. Fetch in parallel, hoist fetches, or use route-level loaders.
- **Fetching in `useEffect` by hand** with no cache, deduplication, retries or cancellation: use a data-fetching library or framework loaders.
- **No request cancellation** (`AbortController`): stale responses overwrite newer ones (race conditions on fast typing or navigation).
- **No debounce/throttle on search-as-you-type** inputs: a request per keystroke.
- **Over-fetching and under-fetching**: endpoints returning entire objects for a list view, or N calls to render one screen. Agree on view-shaped endpoints or use GraphQL/BFF where it fits.
- **Polling when push is available**, or polling with no backoff and no pause when the tab is hidden.
- **Ignoring HTTP caching** (`Cache-Control`, `ETag`): everything refetched on every visit.
- **Retrying non-idempotent requests blindly**: duplicate orders or payments. Use idempotency keys.
- **Treating `fetch` as throwing on HTTP errors**: it only rejects on network failure. Check `response.ok`.
- **Hardcoded API URLs** scattered through components instead of a single API client with interceptors for auth and errors.
- **No loading, empty or error states**: blank screens and infinite spinners.

## Performance and Core Web Vitals

- **Shipping one giant bundle**: no code splitting by route or heavy component. Use dynamic `import()` and lazy loading.
- **Importing whole libraries for one function** (`import _ from 'lodash'`, full icon packs, `moment` with all locales): analyze the bundle and import only what you use.
- **Unoptimized images**: huge PNGs/JPEGs, no `srcset`/`sizes`, no modern formats (WebP/AVIF), no explicit `width`/`height`. Hurts LCP and causes layout shift (CLS).
- **Lazy loading the LCP image** (or lazy loading everything): the hero image should be eager with `fetchpriority="high"`; below-the-fold images should be lazy.
- **Layout shift from late-loading content**: ads, embeds, banners and web fonts with no reserved space. Reserve dimensions and use `font-display` with size-adjusted fallbacks.
- **Blocking the main thread** with long synchronous tasks (big JSON parsing, heavy loops, large re-renders): poor INP. Break up work, use Web Workers or `scheduler.yield`.
- **Render-blocking scripts and CSS** in the head with no `defer`/`async`.
- **Third-party scripts loaded eagerly** (analytics, chat widgets, tag managers): often the biggest cost. Load them after interaction or idle, and audit regularly.
- **Animating layout properties** (`top`, `left`, `width`, `height`) instead of `transform`/`opacity`: forces layout and paint every frame.
- **Scroll/resize listeners without throttling or passive flags**, instead of `IntersectionObserver`/`ResizeObserver`.
- **No caching headers for static assets** or no content hashes in filenames: users redownload everything, or get stale files after a deploy.
- **Optimizing without measuring**: guessing instead of using Lighthouse, WebPageTest, the Performance panel and real-user monitoring (RUM).

## HTML, CSS and accessibility

- **Div soup**: clickable `<div>`s instead of `<button>`/`<a>`, no landmarks (`<main>`, `<nav>`), no heading hierarchy. Use semantic elements first; ARIA is the last resort.
- **Click handlers on non-interactive elements** with no keyboard support, role or focus: unusable without a mouse.
- **Removing focus outlines** (`outline: none`) with no replacement: keyboard users get lost. Use `:focus-visible` styles.
- **Missing labels**: inputs without `<label>`, icon-only buttons without accessible names, images without `alt` (or with decorative images not marked `alt=""`).
- **Color as the only signal**, or low contrast text: fails WCAG contrast ratios and color-blind users.
- **Modals and menus without focus management**: no focus trap, no return of focus, no `Escape` to close.
- **Disabling zoom** (`user-scalable=no`) or using fixed `px` for text: breaks user scaling preferences. Use `rem`.
- **Ignoring `prefers-reduced-motion`** for large animations.
- **`!important` and over-specific selectors** to win specificity fights: use a clear cascade, CSS layers or scoped styles.
- **Magic numbers and hardcoded colors/spacing** instead of design tokens or CSS variables.
- **Fixed heights on containers with dynamic content**, and `100vh` on mobile (address bar issues): use `min-height` and `dvh`.
- **Desktop-first layouts patched with breakpoints**, or layouts that only work at specific device widths: build fluid layouts with flexbox/grid and test real viewports.
- **Huge CSS-in-JS runtime cost** in hot paths: prefer compile-time or static CSS where possible.

## Security

- **`dangerouslySetInnerHTML` / `innerHTML` with unsanitized input**: XSS. Sanitize with a vetted library (DOMPurify) or avoid raw HTML entirely.
- **Building URLs or HTML with string concatenation** from user input: use URL APIs and framework escaping.
- **Storing auth tokens in `localStorage`**: any XSS steals them. Prefer `HttpOnly`, `Secure`, `SameSite` cookies set by the server.
- **Secrets in the frontend bundle**: API keys, private tokens and `.env` values with a public prefix are visible to everyone. Anything shipped to the browser is public.
- **Trusting client-side checks**: hiding a button is not authorization. Enforce permissions on the server.
- **No Content Security Policy**, or one with `unsafe-inline`/`unsafe-eval` everywhere: it removes your best XSS mitigation.
- **`target="_blank"` without `rel="noopener"`** on untrusted links (older browsers) and open redirects built from query params.
- **`postMessage` without checking `event.origin`**, or with `*` as the target origin.
- **Wide-open CORS** (`*` with credentials) or confusing CORS errors "fixed" by disabling security in the browser.
- **CSRF unprotected** on cookie-authenticated endpoints: use `SameSite` cookies and CSRF tokens.
- **Third-party scripts and CDNs without Subresource Integrity (SRI)**: a compromised host runs code on your origin.
- **Outdated and unvetted dependencies**: run `npm audit`, pin versions with a lockfile, and watch for typosquatting and malicious postinstall scripts.
- **Logging PII or tokens** to the console or error trackers.

## Rendering strategy and SEO

- **Client-side rendering for content that needs SEO or fast first paint**: crawlers and slow devices see an empty shell. Use SSR/SSG/ISR where content matters.
- **SSR for everything**, including pages that are fully personalized and uncacheable: unnecessary server cost and latency. Choose per route.
- **Hydration mismatches**: rendering different output on server and client (`Date.now()`, `window`, `Math.random()` during render). Gate client-only values behind effects.
- **Hydrating the whole page** when only small parts are interactive: consider islands or partial hydration, and server components where available.
- **Accessing `window`/`document` during SSR** without guards: crashes on the server.
- **Missing or duplicated metadata**: no unique `<title>`, meta description, canonical URL or Open Graph tags per page.
- **Content only reachable via JS-driven navigation** (no real `<a href>`): crawlers and users with JS issues can't follow it.
- **Soft 404s**: returning `200` with a "not found" view instead of a real 404 status.
- **Blocking crawlers by accident** (`noindex` or `robots.txt` shipped from staging to production).
- **Hash-based routing** (`/#/page`) for public sites: poor SEO and sharing.

## Forms and UX

- **Validating only on the client**, or only on the server: do both. Client validation is UX; server validation is security.
- **Validating on every keystroke** before the user has finished typing: validate on blur/submit, then live once the field has been touched.
- **Controlled inputs for huge forms** causing a re-render per keystroke: use uncontrolled inputs or a form library (React Hook Form, etc.).
- **Error messages that don't say how to fix the problem**, shown only by color or placed far from the field. Link them with `aria-describedby`.
- **Disabling the submit button with no explanation**, and no protection against double submits: disable after the first click and use idempotency on the server.
- **Using the wrong input types** (`type="text"` for email, phone, numbers): lose mobile keyboards and autofill. Set `type`, `inputmode` and `autocomplete`.
- **Placeholder as label**: disappears on focus and fails accessibility.
- **Losing user input on error or navigation**: warn on unsaved changes and keep values after failed submits.
- **Infinite scroll with no way to reach the footer, no URL state and no keyboard access**: offer pagination or a "load more" button.
- **Blocking the UI with spinners** for everything: use skeletons and optimistic updates where appropriate.
- **Custom controls that reimplement native ones badly** (selects, date pickers, scrollbars): prefer native elements unless there is a strong reason.

## Build, dependencies and deployment

- **Adding a dependency for trivial things** (`left-pad` style): every package is bundle size, supply-chain risk and upgrade work.
- **No lockfile committed**, or mixing package managers: non-reproducible builds.
- **Never updating dependencies**, then facing a painful multi-major upgrade. Update continuously with automation (Renovate/Dependabot) and good tests.
- **Duplicate versions of the same library in the bundle** (two Reacts, multiple date libraries): analyze with a bundle visualizer.
- **Shipping source maps publicly** when the code is sensitive, or not shipping them to the error tracker so stack traces are unreadable.
- **Environment variables baked into the build** per environment: one build per environment instead of build once, configure at deploy or runtime.
- **No content hashing + immutable caching** for assets, with `index.html` cached too long: users stuck on old versions or broken chunk loads after a deploy. Cache HTML briefly and handle chunk-load errors with a reload prompt.
- **Deploying without preview environments** or without checks in CI (lint, type check, tests, bundle size budget, accessibility checks).
- **Not setting performance budgets**: bundle size grows unnoticed until it's a crisis.
- **Polyfilling and transpiling for browsers you don't support**: extra kilobytes. Align `browserslist` with real analytics.
- **Monorepo or micro-frontend complexity adopted without need**: version skew, duplicated runtimes and slow builds.

## Error handling and observability

- **No error boundaries**: one component throwing blanks the whole page. Add boundaries around routes and risky widgets, with a recovery action.
- **Swallowing errors** (`catch {}`) or only `console.log`-ing them: nobody finds out. Report to an error tracker (Sentry or similar).
- **Generic "Something went wrong" for every failure**, with no retry and no differentiation between offline, 4xx and 5xx.
- **No global handlers** for `window.onerror` and `unhandledrejection`.
- **Errors without context**: no release version, user/session ID, route or breadcrumbs, and no source maps uploaded.
- **Relying only on lab metrics**: no real-user monitoring for Core Web Vitals, so you don't see what actual devices and networks experience.
- **No feature flags or gradual rollout** for risky changes: every deploy is all or nothing.
- **Analytics events inconsistent or scattered** through components: define a typed tracking layer.
- **`console.log` left in production**, sometimes leaking sensitive data.

## Testing and maintainability

- **Testing implementation details** (internal state, method calls, snapshot of entire trees): tests break on every refactor. Test behavior the way a user interacts (Testing Library).
- **Huge snapshot tests** nobody reads: approved blindly on every change.
- **Mocking everything**, including your own modules: tests pass while the app is broken. Mock at the network boundary (MSW) instead.
- **Relying on end-to-end tests only**, or on unit tests only: keep a balance, with a few critical-path E2E tests (Playwright/Cypress).
- **Flaky tests with arbitrary `sleep`/timeouts**: wait for conditions or use auto-waiting.
- **No accessibility checks in CI** (axe, linting for jsx-a11y): regressions ship unnoticed.
- **No visual regression testing** for a design system or critical pages.
- **Copy-pasted components with small variations** instead of composable primitives and variants.
- **Premature abstraction**: generic components with 20 props and many boolean flags to cover every case. Prefer composition and duplication until the pattern is clear.
- **Undocumented design system or no Storybook-style catalog**: teams rebuild the same button repeatedly.

# Anti-patterns in Swift (iOS)

Reference for `code-reviewer`. Not loaded into sessions; the short list Claude follows while writing
is `global/rules/ios.md`. When an entry contradicts the project's `CLAUDE.md` or the `write-swift`
skill, the project wins. Check the project's `SWIFT_VERSION` and default actor isolation before
flagging a concurrency entry: several depend on them. Entries that contradicted `write-swift`
(serial queues, `OperationQueue`, typed throws on public API, `@StateObject` for new code,
`deinit` prints) were rewritten or removed on purpose; do not add them back.

## How to prioritize

These six hurt most in production iOS apps; check them first in a code review.

1. Retain cycles in closures, delegates and Combine/`Task` captures
2. Work on the main thread (I/O, JSON decoding, image processing) and UI updates off it
3. Force unwraps (`!`) and `try!` on data you don't control
4. Massive view controllers / views that mix UI, networking and business logic
5. Mixing GCD, completion handlers and `async/await` without a clear concurrency model
6. Secrets and tokens in `UserDefaults`, plist files or the bundle instead of the Keychain

The rest of the document is grouped by topic. Items assume Swift 5.9+ and note where Swift 6 strict concurrency changes the advice.

## Memory management

- **Strong reference cycles in closures**: `self` captured strongly by a stored closure, a timer, `NotificationCenter` observer or `Task`. Restructure first so the closure does not need `self`; use `[weak self]` only for a real cycle, and check the object graph with the Memory Graph Debugger.
- **Strong `delegate` properties**: the delegate and its owner retain each other. Declare delegates `weak` and constrain the protocol to `AnyObject`.
- **`[weak self]` everywhere by reflex**: needless in short-lived, non-stored closures (`map`, `filter`, `UIView.animate`) and can hide logic bugs when `self` becomes `nil` mid-operation.
- **`[unowned self]` where the lifetime isn't guaranteed**: crashes when the object goes away first.
- **Combine subscriptions not stored** (or stored without cancellation) and sinks capturing `self` strongly inside `AnyCancellable` sets owned by `self`.
- **Unstructured `Task { }` capturing `self` strongly in long-running work**: the task keeps the object alive until it finishes. Cancel tasks on deinit/disappear and capture weakly where needed.
- **Observers never removed** (`NotificationCenter` block-based API, KVO tokens): leaks and duplicate callbacks.
- **Timers retaining their target** (`Timer.scheduledTimer(target:)`) and never invalidated.
- **Singletons holding references to view controllers or large objects** forever.
- **Caching images or data in dictionaries without eviction**: use `NSCache` and respond to memory warnings.
- **Large objects copied around as value types** unintentionally (big arrays inside structs mutated in a loop): copy-on-write helps, but profile with Instruments.

## Concurrency

- **Mixing GCD, completion handlers, Combine and `async/await`** in the same layer with no clear boundary: hard to reason about cancellation and errors. Pick `async/await` for new code and wrap legacy APIs with continuations.
- **UI updates off the main thread**: purple runtime warnings, crashes and glitches. Without default MainActor isolation, annotate UI types with `@MainActor`; with it on (Swift 6.2 Approachable Concurrency), the annotation is redundant.
- **`DispatchQueue.main.async` sprinkled everywhere** instead of isolating UI code with `@MainActor`.
- **Blocking the main thread**: `DispatchQueue.main.sync` from the main thread (deadlock), semaphores waiting on async work, synchronous network or disk I/O.
- **`DispatchSemaphore` / `.wait()` to "make async synchronous"**: deadlocks and thread starvation in the cooperative pool. Never block cooperative threads.
- **Misusing `Task.detached`**: it drops actor context, priority and task-locals. Prefer structured concurrency (`async let`, `TaskGroup`). For CPU work off the main actor on Swift 6.2+, use `@concurrent`; a plain `Task` inherits the main actor there.
- **Unstructured tasks fired and forgotten**, with no cancellation or error handling: leaks and lost failures. Keep handles, cancel on teardown, and handle `CancellationError`.
- **Ignoring cancellation**: long loops that never call `Task.checkCancellation()` or check `Task.isCancelled`.
- **Data races on shared mutable state** (class properties mutated from multiple queues): use actors or `@MainActor` and enable strict concurrency checking. No new `DispatchQueue` for this.
- **Actors used as locks around everything**, creating serial bottlenecks and reentrancy surprises: remember that state can change across any `await` inside an actor.
- **`@unchecked Sendable` to silence warnings** without making the type actually thread-safe.
- **Creating a `DispatchQueue` per task** or unbounded concurrent work (thread explosion): limit concurrency with `TaskGroup` batching.
- **Using `async` APIs inside `onAppear`/`viewDidLoad` without cancellation**: use SwiftUI's `.task` modifier, which cancels automatically.

## Optionals, error handling and type safety

- **Force unwrapping (`!`)** on values you don't fully control (JSON, `URL(string:)` from user input, `as!` casts, IBOutlets accessed too early): crashes in production. Use `guard let`, `if let`, `??` or throw.
- **`try!` and `fatalError` as error handling** outside of truly unrecoverable programmer errors.
- **Implicitly unwrapped optionals (`Type!`)** as a convenience for properties that are set "later": prefer proper initialization or a real optional.
- **`try?` swallowing errors** and then treating `nil` as "no data": you lose why it failed. Catch and log or surface the error.
- **Empty `catch {}` blocks.**
- **Stringly-typed code**: raw strings for keys, notification names, segue identifiers, analytics events and user defaults keys. Use enums, constants or typed wrappers.
- **Optional chaining so deep that failures vanish silently**: decide where `nil` is legitimate and where it's a bug.
- **`Any` / `[String: Any]` models** passed around instead of typed structs.
- **`NSObject`/Objective-C style inheritance** where a struct or protocol would do.
- **Large enums with associated values and a catch-all `default:`** in switches: new cases compile silently into the wrong branch. Prefer exhaustive switches (`@unknown default` for non-frozen system enums).
- **Throwing generic `Error`** or `NSError` with codes instead of an error enum with context. Keep public API on untyped `throws`; typed throws only inside a module.
- **Overusing `class`** for models: unintended shared mutation. Prefer structs for value semantics and make mutation explicit.

## SwiftUI

- **Wrong property wrapper**: `@ObservedObject` for an object the view creates (it's recreated and loses state on every refresh). Use `@State` with an `@Observable` type for owned objects; `@StateObject` only in existing `ObservableObject` code.
- **Everything in `@State`/`@Published` on one giant view model**: any change invalidates a huge part of the tree. Split state by feature and scope observation narrowly.
- **Heavy work in `body`**: sorting, filtering, formatting, creating `DateFormatter`s or decoding on every render. `body` must be cheap and side-effect free.
- **Side effects in `body`** or initializers (network calls, mutating state): triggers loops and undefined ordering. Use `.task`, `.onChange` and explicit actions.
- **Unstable identity in `ForEach`/`List`**: using `id: \.self` on non-unique values or `UUID()` generated inline, causing lost state, animations and poor diffing. Use stable `Identifiable` IDs.
- **Massive view `body`s** with deeply nested modifiers: split into small subviews (which also narrows invalidation).
- **`AnyView` everywhere**: erases type information and hurts diffing. Prefer `@ViewBuilder` and generics.
- **`GeometryReader` overuse** for layout that stacks, grids or `Layout` could handle; it also greedily takes all offered space.
- **State duplicated between parent and child** instead of using `@Binding` or a single source of truth.
- **Navigation state hidden inside views** with deprecated `NavigationLink` patterns, making deep links and testing hard. Use `NavigationStack` with a path model.
- **Using `onAppear` for async loading** with no cancellation: prefer `.task(id:)`.
- **Fighting the framework with UIKit wrappers** when native SwiftUI has since caught up (and the reverse: reimplementing complex UIKit controls badly).
- **Previews that don't build** or are stale: they stop being a feedback tool. Keep preview data and mocks separate and compiling.
- **Ignoring Dynamic Type, accessibility labels and dark mode** because the preview looked fine.

## UIKit and legacy patterns

- **Massive View Controller**: networking, parsing, business rules, navigation and layout in one class. Extract view models/presenters, services and coordinators.
- **View controllers navigating to each other directly** (pushing concrete types): tight coupling and untestable flows. Use coordinators or routers.
- **Reloading the entire table/collection view** (`reloadData()`) for small changes: flicker and lost scroll state. Use diffable data sources and batch updates.
- **Heavy work in `cellForRowAt`**: decoding images, formatting, synchronous I/O. Prepare data beforehand and cancel work in `prepareForReuse`.
- **Not resetting cell state in `prepareForReuse`**: wrong images or content appearing on reused cells.
- **Storing state in views** (reading values back from labels and switches) instead of in a model.
- **Auto Layout conflicts ignored** in the console, or constraints added repeatedly (every `viewDidLayoutSubviews`/`updateConstraints`): layout bugs and leaks.
- **Hardcoded frames and magic numbers** instead of constraints, safe areas and `UIStackView`.
- **Fixed font sizes** with no `UIFontMetrics` support for Dynamic Type.
- **Storyboard merge conflicts** with huge storyboards: split into per-feature storyboards, XIBs or programmatic UI.
- **Doing work in `viewDidLoad` that depends on final geometry** (bounds are not final yet): use `viewDidLayoutSubviews` or layout-driven code.
- **Overriding `layoutSubviews` and calling `setNeedsLayout` inside it** (loops) or forcing `layoutIfNeeded` constantly.
- **Method swizzling and runtime hacks** for convenience: fragile across OS updates.

## Architecture and design

- **Singletons for everything** (`Manager.shared`): hidden dependencies, global mutable state and untestable code. Inject dependencies through initializers or an environment.
- **Service locator / global container accessed from anywhere** instead of explicit injection.
- **Over-engineered architecture** (VIPER, Clean Swift, TCA, coordinators and use cases) for a small app: boilerplate with no payoff. Match the pattern to the team and app size.
- **Under-engineered architecture**: all logic in views and view controllers until nothing can be tested or reused.
- **Protocols for every class "for testability"** with a single implementation and no real seam.
- **Massive protocols** with many requirements: split them (interface segregation) or use composition.
- **Inheritance hierarchies** instead of protocol composition and value types.
- **Utility/extension dumping grounds** (`Extensions.swift`, `Helpers.swift`) and extensions on `String`/`UIView` that leak app logic into system types.
- **Business logic in `AppDelegate`/`SceneDelegate`**: they turn into god objects. Keep them as thin entry points.
- **Modularizing too late (or too early)**: one huge target with slow builds and circular dependencies, or dozens of micro-modules with heavy overhead. Use Swift Packages with clear boundaries once the app grows.
- **Leaking DTOs/Core Data entities into the UI layer**: couples screens to the backend and persistence schema. Map to domain or view models.
- **Feature flags and environment config via `#if DEBUG` scattered in code**: centralize configuration and use build configurations/xcconfig.

## Networking and data

- **Hand-rolled `URLSession` calls duplicated across the app**: inconsistent error handling, auth and retries. Build one API client layer with typed endpoints.
- **Ignoring HTTP status codes**: assuming any response with data is success. Validate the status and map errors.
- **Decoding on the main thread** or decoding huge payloads synchronously.
- **Fragile `Codable` models**: one missing or null field fails the whole response. Use optionals where the backend isn't guaranteed, custom `init(from:)`, and test with real payloads.
- **`JSONSerialization` and `[String: Any]` parsing** where `Codable` would do, or force-casting nested dictionaries.
- **`JSONDecoder`/`DateFormatter` created per call**: expensive. Reuse configured instances (and set `ISO8601` or custom strategies explicitly).
- **Date and time zone assumptions**: parsing without a fixed locale (`en_US_POSIX`) or time zone.
- **No timeouts, retries or backoff**, and retrying non-idempotent requests blindly.
- **No cancellation of in-flight requests** when the screen goes away or the query changes.
- **Ignoring connectivity**: no handling of offline, `NWPathMonitor` use without hysteresis, or blocking UI on reachability checks. Handle failures instead of pre-checking.
- **Token refresh races**: several 401s trigger several refreshes. Serialize refresh with an actor.
- **Disabling App Transport Security** (`NSAllowsArbitraryLoads`) globally instead of fixing the endpoint.
- **No caching strategy** (`URLCache`, ETags) and refetching everything on each launch or screen visit.
- **Floating-point money** (`Double`) from the API: use `Decimal` or integer minor units.

## Persistence

- **`UserDefaults` as a database**: large or sensitive data, no migration story, and everything loaded at launch. Use it only for small preferences.
- **Secrets or tokens in `UserDefaults`, plist files or `@AppStorage`**: use the Keychain with an appropriate accessibility class.
- **Core Data `viewContext` used for heavy work** (imports, large fetches): blocks the UI. Use background contexts with `perform`.
- **Passing `NSManagedObject`s across threads/contexts**: crashes. Pass `NSManagedObjectID`s or value types.
- **Fetching everything and filtering in memory**, with no predicates, fetch limits, batch sizes or indexes.
- **Faulting storms**: accessing relationships in a loop without prefetching (`relationshipKeyPathsForPrefetching`): the Core Data equivalent of N+1.
- **Saving after every single change** or never saving: batch saves sensibly and handle merge conflicts.
- **No schema migration plan**: changing the model with no versioning and crashing on update. Use lightweight migrations or staged migrations deliberately and test upgrades from old store versions.
- **SwiftData `@Model` classes treated like plain structs** (mutated off the right context, shared across actors) or `@Query` over huge unfiltered data in views.
- **Storing images and blobs inside the database** without external storage, or storing large files in `Documents` that should be in `Caches`/`tmp` (and not excluded from backup).
- **Writing files synchronously on the main thread**, or non-atomic writes that corrupt data on interruption.
- **Treating iCloud/CloudKit sync as automatic** with no conflict resolution or schema constraints (CloudKit requires optional/default attributes).

## Performance and app lifecycle

- **Heavy work at launch** (`didFinishLaunching`, SDK initializations, synchronous migrations, big file reads): slow launch and watchdog kills. Defer what isn't needed for the first screen and measure with Instruments and MetricKit.
- **Initializing every third-party SDK eagerly** (analytics, ads, crash, feature flags): lazy-initialize or defer after first render.
- **Decoding and resizing large images on the main thread**, or displaying full-resolution images in small views. Downsample with ImageIO and cache.
- **Overdraw and offscreen rendering**: shadows without `shadowPath`, `cornerRadius` + `masksToBounds` on many layers, blur and transparency everywhere. Profile with Core Animation instruments.
- **Animating with `layoutIfNeeded` loops or heavy layout recalculation** on every frame.
- **Creating expensive objects repeatedly** (`DateFormatter`, `NumberFormatter`, `NSRegularExpression`, `JSONEncoder`): cache and reuse them.
- **Excessive `Array`/`String` copies and O(n²) algorithms** in hot paths (`contains` on arrays in loops instead of `Set`; `String` indexing with `count` repeatedly).
- **Not responding to memory warnings** or holding large caches in the background: the OS terminates the app. Use `NSCache` and clear on warnings.
- **Background work abuse**: continuous location, timers or polling that drain battery. Use significant-change, push notifications, `BGTaskScheduler` and coalesced work.
- **Ignoring app lifecycle**: not saving state on backgrounding, assuming the app stays alive, or doing long work in `applicationDidEnterBackground` without a background task.
- **Optimizing without measuring**: use Instruments (Time Profiler, Allocations, Leaks), Xcode Organizer metrics and MetricKit instead of guessing.
- **Debug-only behavior shipping to release**: logging, assertions and test hooks that affect performance or leak data.

## Security and privacy

- **Secrets hardcoded in the app** (API keys, client secrets, signing keys): anything in the binary can be extracted. Keep real secrets on the server and use short-lived tokens.
- **Tokens and credentials outside the Keychain**, or Keychain items with overly permissive accessibility (`kSecAttrAccessibleAlways`).
- **Sensitive data in logs** (`print`, `NSLog`, `os_log` without privacy annotations), crash reports or analytics events.
- **Sensitive data in screenshots/app switcher snapshots**: hide content when the app resigns active.
- **Disabling certificate validation** or trusting all certificates to "fix" a staging issue and shipping it. Consider certificate pinning only with a rotation plan.
- **Disabling App Transport Security globally.**
- **Custom URL schemes handling sensitive actions** without validation: use Universal Links and validate every parameter.
- **Trusting deep link and pasteboard input**: validate and sanitize before acting.
- **Web views with JavaScript bridges exposed to untrusted content**, or loading arbitrary URLs inside `WKWebView` with full privileges.
- **Rolling your own cryptography**: use CryptoKit and platform APIs.
- **Requesting permissions at launch** with no context, or collecting more data than needed: review rejection and user distrust. Request just in time and explain why.
- **Missing or inaccurate privacy manifest and Privacy Nutrition Labels**, including for third-party SDKs: App Store review issues.
- **Biometric checks implemented only as a boolean flag** (`evaluatePolicy` result gating UI) instead of tying secrets to Keychain access controls.
- **Jailbreak/tamper detection as the only protection**: it's bypassable; enforce rules server-side.

## Testing, dependencies and release

- **No tests for business logic** because it lives in view controllers and views: extract it so it can be tested without UI.
- **UI tests as the only safety net**: slow and flaky. Keep a pyramid with fast unit tests and a few critical UI flows.
- **Tests that depend on real network, time, `UserDefaults`, the Keychain or the singleton state** left by other tests: inject clocks, stores and clients; reset state between tests.
- **`sleep`/arbitrary waits in async tests**: use `await` with async test functions, expectations or confirmations.
- **Mocking so heavily that tests only mirror the implementation.**
- **Snapshot tests without fixed devices, OS versions and locales**: flaky diffs.
- **Too many third-party dependencies** for small tasks, unmaintained pods, or unpinned versions. Prefer Swift Package Manager, pin versions and review licenses and privacy manifests.
- **Dependencies that wrap system APIs poorly** (and become migration blockers when the OS evolves).
- **Unversioned or hand-edited `project.pbxproj` conflicts** with many contributors: use SPM, xcconfig and generators (XcodeGen/Tuist) if the pain justifies it.
- **Manual release process**: certificates, provisioning and builds done by hand on one laptop. Automate with CI (fastlane, Xcode Cloud, GitHub Actions) and keep signing reproducible.
- **No staged rollout, feature flags or remote kill switch** for risky features: every App Store release is all-or-nothing and slow to revert.
- **Not testing on real devices and older OS/hardware** you still support, or ignoring `Deployment Target` implications for APIs.
- **Ignoring compiler warnings and deprecations** until a major OS release forces a rewrite. Treat new warnings as errors in CI.
- **No crash reporting with symbolication** (dSYMs uploaded) or no analytics on real-world failures.

# Harbor - Context for Agents

Instructions for AI agents working on this repository. To write code that uses Harbor, read `.agents/skills/harbor/SKILL.md`. To migrate code from Harbor 3, read `.agents/skills/harbor-migration-v3-to-v4/SKILL.md`.

## Overview
Harbor is a lightweight networking library for Swift, built for Swift 6 strict concurrency (Swift 6 language mode, iOS 15+ / macOS 14+). It relies on `async/await` and a global actor (`@HRequestManagerActor`) to provide a thread-safe environment for REST requests, JSON-RPC 2.0 requests and WebSocket connections. Products: `Harbor` (REST), `HarborJRPC` (depends on `Harbor`, since a JSON-RPC call is a REST POST) and `HarborWebSocket`. They share `HarborCore`, an implementation module that is not a product; the only external dependency is [LogBird](https://github.com/javiermanzo/LogBird).

## Design rules
Keep these invariants when changing the library. Their details live in the deep dives listed at the end.

1. **Protocols, not classes.** Requests are `Sendable` structs conforming to one protocol per HTTP method. Every requirement is get-only, so a computed `bodyParameters` keeps a request `Sendable` without `@unchecked`. New requirements need a default implementation in the protocol extension.
2. **Results, not throws.** REST `request()` never throws: GET returns `HResponseWithResult<Model>`, the other methods return `HResponse`. JSON-RPC `request()` (`async throws`; `requestResult()` doesn't throw) and WebSocket (`connect()`, `send`, `ping()` and the `messages` stream throw `HWebSocketError`) are the exceptions: a connection has several failing operations and wrapping each in a `Result` would be noise.
3. **Actor isolation.** Global state lives in `HConfig.shared` (shared by every product), `HRESTConfig.shared` (REST only) and the `Harbor` enum, all isolated to `@HRequestManagerActor`. Public configuration is exposed as `static func setX(...)`, not as settable properties (Swift forbids mutating actor-isolated static properties from outside the actor). Response decoding runs off the actor.
4. **No callbacks.** No escaping closures for requests. Cancellation is `Task` cancellation (`.cancelled`); cancelling the task iterating `HWebSocket.messages` closes the connection.
5. **Safe by default.** Logged values are redacted, credentials are stripped on cross-origin redirects, cached `needsAuth` responses are namespaced per credential, mocks are off in release builds. Don't weaken these defaults.
6. **Public API is documented.** Every public symbol has a DocC `///` comment.

## Code Organization
Every Swift file in `Sources/` follows the same layout:
```swift
{VISIBILITY} {ENTITY}                      // the type: declaration, stored properties, initializers

// MARK: - {Feature}
{VISIBILITY} extension {ENTITY}            // one extension per feature (no conformance)

// MARK: - {Protocol}
extension {ENTITY}: {PROTOCOL}             // one extension per protocol conformance
```
- `{VISIBILITY}` is `public`, `package`, `internal`, `private`, etc., and `{ENTITY}` is `enum`, `struct`, `class`, `actor` or `protocol`. Swift does not allow an access modifier on an extension that declares a conformance: there the conformance takes the lower visibility of the type and the protocol.
- **Modules and where code goes.** `HarborCore` holds what more than one product needs (auth provider and refresh, security, logging and redaction, the `URLSession` pool, retry policy and attempt loop, URL composition, the shared `Harbor.setX(_:)` configuration, shared errors and entities). `Harbor` holds what only REST needs (request protocols and execution, cache, mocks, multipart, `HRESTConfig`, REST-only `Harbor` setters such as `setDefaultCacheType`). `HarborJRPC` depends on `Harbor`; `HarborWebSocket` depends only on `HarborCore`, and a new product that does not need REST should do the same. `HarborCore` must never reference a REST type: if shared code needs something REST-specific, pass it in through a neutral type (see `HSessionProfile`) or let the REST side follow a neutral signal (see `HRequestManager.authGeneration`).
- **Visibility.** `HarborCore` internals are `package`, never `public`. What was already public stays public there (`HRetryPolicy`, `HRequestError`, `HAuthProviderProtocol`, `HDebugRequestProtocol`, `HMTLS`, `HURLSessionDelegate`, the shared `Harbor` setters, ...) and is re-exported with `@_exported import HarborCore` by `Harbor` and `HarborWebSocket`, so `import Harbor` or `import HarborWebSocket` is enough for users. Imports are per file: every source file that uses Core declares `import HarborCore`. Widen a declaration to `package` only when another module needs it; never to `public` unless it is user-facing API.
- Code outside the actor reads the shared configuration with `await HRequestManagerActor.run { HConfig.shared.x }`: `HConfig` is isolated to the actor and cannot be read directly across modules.
- Conformances live in their own extension (`Error`, `LocalizedError`, `Equatable`, `Hashable`, `Codable`/`HModel`, `CustomStringConvertible`, `URLSessionTaskDelegate`, ...) together with the members that implement them.
- They stay on the declaration: `Sendable`, a raw type (`: String`, `: Int`), a superclass (`: NSObject`) and protocol inheritance (`protocol HGetRequestProtocol: HRequestWithResultProtocol`), because Swift requires them there or they describe the type itself.
- Every extension is preceded by a `// MARK: - {Feature or Protocol}` line followed by a blank line.
- One top-level type or protocol per file, named after it (`HGetRequestProtocol.swift`). Large types are split into `Type+Feature.swift` files (see `HRequestManager+Execution.swift`, `+Auth`, `+Retry`, `+Mock`, `+URLSessionPool`, `+AttemptLoop`, and `+RESTState`, `+RESTSession` for the REST-only parts of a type that lives in `HarborCore`). Small private helper types and wrappers that only make sense next to their type may share its file.
- Shared mutable state stays in the type's main file (stored properties cannot move across files without widening their visibility); code that is not a stored property goes to the extension of its feature. State that only one product needs goes in that product's extension of the type (static stored properties are allowed in extensions, e.g. `HRequestManager+RESTState.swift`), not in the shared declaration.
- Mutable state shared across threads uses `HLockedState` (`Utils/HLockedState.swift`), not a hand-rolled `NSLock`. Build-configuration checks use `HBuild.isDebug` (`Utils/HBuild.swift`) when a value is enough; keep `#if DEBUG` when the code itself must not be compiled in release (e.g. log statements that include error details).
- Source folders: `Sources/HarborCore/{Auth,Config,Debug,Request,Utils}`, `Sources/Harbor/{Cache,Config,Debug,Mock,Request,Utils}`, `Sources/HarborJRPC/{Config,Request}` and `Sources/HarborWebSocket/{Config,Connection,Debug,Request}`; `HarborCore/Harbor.swift` (shared setters), `Harbor/Harbor+REST.swift`, `HarborJRPC.swift` and `HarborWebSocket.swift` hold the public configuration APIs. `.agents/skills/harbor/architecture.md` maps the request flow onto these files.

## Testing
- Tests live in `Tests/HarborTests`, `Tests/HarborJRPCTests` and `Tests/HarborWebSocketTests`; tests of `HarborCore` internals use `@testable import HarborCore` (REST internals: `@testable import Harbor`), and `HarborWebSocketTests` never import `Harbor`; shared fixtures are in `Tests/HarborTests/Helpers`, `Tests/HarborTests/Mocks` and `Tests/HarborWebSocketTests/Helpers` (a loopback WebSocket server on `NWProtocolWebSocket` and a raw HTTP responder for rejected handshakes).
- WebSocket tests must be `async` methods: `XCTestCase` subclasses isolated to `@HRequestManagerActor` crash on synchronous test methods.
- Harbor's mocks (`HMock`, `HMockSequence`) short-circuit inside the request pipeline and don't use `URLProtocol`. To exercise the real transport, tests install `URLProtocol` stubs through the `package` hook `Harbor.setProtocolClasses` (`@testable import HarborCore`); see `.agents/skills/harbor/testing.md`.
- Real-service tests run only with `HARBOR_RUN_NETWORK_TESTS=1`.
- Add or update tests for every behavior change, and reset global state (mocks, cache, auth provider, custom session) in `setUp` / `tearDown`.

## Example App
`Example/HarborExample` showcases every feature (GET, POST incl. `rawBody` and multipart, caching, streaming, JSON-RPC, WebSocket, auth with token refresh, retry, mTLS, SSL pinning, mocking). It is built in Swift 6 language mode (`SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`). When modifying it:
- Keep UI state in `@State` (or `@StateObject` for classes) to prevent lifecycle reference leaks across SwiftUI render passes.
- Isolate networking calls with `Task { await ... }`. If passing closures to a `Task` inside a SwiftUI View, mark the closure `@Sendable` to detach it from the view's implicit `@MainActor`, and read `@State` values on the main actor before handing them to the closure.
- Read global configuration (like `Harbor.mocksEnabled`) with `await` so it doesn't trigger Main Actor warnings.
- A custom `URLSession` (e.g. with stub `URLProtocol`s in `protocolClasses`) must be created with `delegate: await Harbor.makeURLSessionDelegate()` so pinning, mTLS and the redirect policy stay active.

## CI & Workflow
- Commits follow Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`). Record user-facing changes in the `[Unreleased]` section of `CHANGELOG.md`.
- Everything must build under Swift 6 strict concurrency without warnings: CI builds the package and fails on any compiler `warning:` emitted for files under this repository's `Sources/` (warnings from dependencies are ignored).
- Test every change before pushing it, even refactors that only move code: `swift build` (no warnings under `Sources/`), `swift test` and `xcodebuild test` in the Example App (`CONTRIBUTING.md` has the command).
- Workflows in `.github/workflows/`: `ci.yml` (unit tests with coverage and the Example App tests), `lint.yml` (SwiftLint `--strict`) and `network-tests.yml` (manual/weekly real-service tests).
- When behavior or public API changes, update the docs in the same change: `README.md`, `.agents/skills/` and, for breaking changes, the migration skill.

## Internal deep-dive documentation
Implementation details live in `.agents/skills/harbor/`:
- `architecture.md`: request flow, actor lifecycle, session management.
- `cache.md`: cache storage, HTTP freshness semantics, ETags, offline behavior.
- `security.md`: pinning, mTLS, redirects, custom sessions, auth flow, log redaction.
- `testing.md`: mocks and the test suite's `URLProtocol` stubs.
- `protocols.md`: every request protocol, default, response and error type.
- `examples/websocket.md`: the WebSocket product (`HWebSocketRequestProtocol`, `HWebSocket`, lifecycle, pings, reconnection pattern).

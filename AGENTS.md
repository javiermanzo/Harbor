# Harbor - Context for Agents

Instructions for AI agents working on this repository. To write code that uses Harbor, read `.agents/skills/harbor/SKILL.md`. To migrate code from Harbor 3, read `.agents/skills/harbor-migration-v3-to-v4/SKILL.md`.

## Overview
Harbor is a lightweight networking library for Swift, built for Swift 6 strict concurrency (Swift 6 language mode, iOS 15+ / macOS 14+). It relies on `async/await` and a global actor (`@HRequestManagerActor`) to provide a thread-safe environment for REST and JSON-RPC 2.0 requests. Products: `Harbor` and `HarborJRPC` (depends on `Harbor`); the only dependency is [LogBird](https://github.com/javiermanzo/LogBird).

## Design rules
Keep these invariants when changing the library. Their details live in the deep dives listed at the end.

1. **Protocols, not classes.** Requests are `Sendable` structs conforming to one protocol per HTTP method. Every requirement is get-only, so a computed `bodyParameters` keeps a request `Sendable` without `@unchecked`. New requirements need a default implementation in the protocol extension.
2. **Results, not throws.** REST `request()` never throws: GET returns `HResponseWithResult<Model>`, the other methods return `HResponse`. JSON-RPC `request()` is the exception (`async throws`; `requestResult()` doesn't throw).
3. **Actor isolation.** Global state lives in `HConfig.shared` and the `Harbor` enum, both isolated to `@HRequestManagerActor`. Public configuration is exposed as `static func setX(...)`, not as settable properties (Swift forbids mutating actor-isolated static properties from outside the actor). Response decoding runs off the actor.
4. **No callbacks.** No escaping closures for requests. Cancellation is `Task` cancellation (`.cancelled`).
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
- `{VISIBILITY}` is `public`, `internal`, `private`, etc., and `{ENTITY}` is `enum`, `struct`, `class`, `actor` or `protocol`. Swift does not allow an access modifier on an extension that declares a conformance: there the conformance takes the lower visibility of the type and the protocol.
- Conformances live in their own extension (`Error`, `LocalizedError`, `Equatable`, `Hashable`, `Codable`/`HModel`, `CustomStringConvertible`, `URLSessionTaskDelegate`, ...) together with the members that implement them.
- They stay on the declaration: `Sendable`, a raw type (`: String`, `: Int`), a superclass (`: NSObject`) and protocol inheritance (`protocol HGetRequestProtocol: HRequestWithResultProtocol`), because Swift requires them there or they describe the type itself.
- Every extension is preceded by a `// MARK: - {Feature or Protocol}` line followed by a blank line.
- One top-level type or protocol per file, named after it (`HGetRequestProtocol.swift`). Large types are split into `Type+Feature.swift` files (see `HRequestManager+Execution.swift`, `+Auth`, `+Retry`, `+Mock`, `+URLSessionPool`). Small private helper types and wrappers that only make sense next to their type may share its file.
- Shared mutable state stays in the type's main file (stored properties cannot move across files without widening their visibility); code that is not a stored property goes to the extension of its feature.
- Mutable state shared across threads uses `HLockedState` (`Utils/HLockedState.swift`), not a hand-rolled `NSLock`. Build-configuration checks use `HBuild.isDebug` (`Utils/HBuild.swift`) when a value is enough; keep `#if DEBUG` when the code itself must not be compiled in release (e.g. log statements that include error details).
- Source folders: `Sources/Harbor/{Auth,Cache,Config,Debug,Mock,Request,Utils}` and `Sources/HarborJRPC/{Config,Request}`; `Harbor.swift` holds the public configuration API. `.agents/skills/harbor/architecture.md` maps the request flow onto these files.

## Testing
- Tests live in `Tests/HarborTests` and `Tests/HarborJRPCTests`; shared fixtures are in `Tests/HarborTests/Helpers` and `Tests/HarborTests/Mocks`.
- Harbor's mocks (`HMock`, `HMockSequence`) short-circuit inside the request pipeline and don't use `URLProtocol`. To exercise the real transport, tests install `URLProtocol` stubs through the internal hook `Harbor.setProtocolClasses` (`@testable import Harbor`); see `.agents/skills/harbor/testing.md`.
- Real-service tests run only with `HARBOR_RUN_NETWORK_TESTS=1`.
- Add or update tests for every behavior change, and reset global state (mocks, cache, auth provider, custom session) in `setUp` / `tearDown`.

## Example App
`Example/HarborExample` showcases every feature (GET, POST incl. `rawBody` and multipart, caching, streaming, JSON-RPC, auth with token refresh, retry, mTLS, SSL pinning, mocking). It is built in Swift 6 language mode (`SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`). When modifying it:
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

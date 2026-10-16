# HarborCore split: analysis and plan

Date: 2026-10-16. Status: proposal, nothing implemented. Builds on PR #67 (HarborWebSocket).

## Goal

A hidden `HarborCore` target holds what every product needs; `Harbor` keeps what only REST needs; `HarborJRPC` and `HarborWebSocket` depend on the narrowest module that serves them. Internals stay `package`, so nothing becomes public that is not public today.

## What the code says today (measured)

- `Harbor`: 52 files, 7,146 lines, 55 top-level types.
- `HarborWebSocket` uses 17 of them (9 public, 8 `package`). `HarborJRPC` uses 9 and **no internal at all**: it only uses the public REST API (`HPostRequestProtocol`, `HRequestWithResultProtocol`, `HResponseWithResult`, ...), because a JSON-RPC call *is* a REST POST wrapped in an envelope.
- A naive "move what WebSocket needs" drags **44 of 52 files** (comments ignored), because a handful of edges tie the shared infrastructure to the REST layer. The split is therefore a decoupling job, not a file move. Roughly 2,400 lines are Core as they stand, ~2,450 are REST-only (cache 1,836, mocks 307, request protocols ~300), and ~2,000 sit in six mixed files that must be cut.

### The coupling edges (the seams to cut)

| # | Edge | Where | Cut |
|---|---|---|---|
| 1 | `HConfig.cacheType: HCache.CacheType` | `Config/HConfig.swift:70` | Move REST-only fields (`cacheType`) to a REST config type in `Harbor`; Core `HConfig` keeps auth, headers, timeouts, mTLS, pins, custom session, logging, cookies |
| 2 | Session pool picks the `URLCache` from `HGetRequestProtocol.cacheType` | `HRequestManager+URLSessionPool.swift` (`cacheType(for:)`, `SessionPurpose.request`) | The pool already has `SessionPurpose` from PR #67: replace `.request(cacheType:)` by a neutral `HSessionProfile` (`urlCache` + policy, or none). REST computes the profile from the request; Core never sees `HGetRequestProtocol` |
| 3 | `HRequestManager` is one namespace with shared state (`connectivityMonitor`, `inFlightAuthFailures`, `maxAuthRetries`) and REST-cache state (`rememberedAuthHeaders`, `cacheGeneration`) | `HRequestManager.swift`, `+Auth.swift` | Stored properties cannot live in cross-module extensions, so split the type: Core `HTransport` (connectivity, session pool, auth refresh, error mapping, retry delay, `runAttemptLoop`), REST keeps `HRequestManager` with the cache state and execution |
| 4 | `HURLBuilder` mixes URL composition with building from request protocols, multipart and cache validators | `Utils/HURLBuilder.swift` | `compositeURL` + percent-encoding to Core; `build(request:)`, multipart, validators to `Harbor` (`HURLBuilder+Request.swift`) |
| 5 | `HDebugRequestProtocol` extension logs requests by casting to REST protocols (`HGetRequestProtocol`, `HRequestWithBodyProtocol`) | `Debug/HDebugRequestProtocol.swift:71-95` | Protocol + `HDebugRequestType` to Core; `logRequest/logResponse/generateCurl` to `Harbor` |
| 6 | `HRetryPolicy` takes `HHttpMethod` | `Request/HRetryPolicy.swift` | `HHttpMethod` (22 lines, public) moves to Core |
| 7 | `runAttemptLoop`/`HAttemptOutcome` live in `+Execution.swift` next to REST status handling | `+Execution.swift` | Own file in Core (already generic after PR #67) |

Everything else is a clean move: `HLogger`, `HRedactionPolicy`, `HJSONRedactor`, `HRequestError`, `HAuthProviderProtocol`, `HURLSessionDelegate`, `HTaskDelegateContext`, `HMTLS`, `PKCS12`, `HSPKI`, `SHA256`, `HLockedState`, `HRequestManagerMonitor`.

## The design question that decides the value: where does public configuration live?

Auth, default headers, timeouts, mTLS, pinning, custom session and logging are configured through `public enum Harbor` (`Harbor.setAuthProvider(_:)`...). A WebSocket-only app needs those setters. If `Harbor` stays in the `Harbor` module, that app must `import Harbor` anyway and the split saves nothing for it.

**Recommended (A):** the shared setters move to Core as a `public enum Harbor` declaration; `Harbor` (module) extends it with the REST-only setters (`setDefaultCacheType`, mocks, `clearAllCache`, resource timeout...). `Harbor` and `HarborWebSocket` both `@_exported import HarborCore`, so `Harbor.setAuthProvider` keeps working from either import and the source API does not change. Core is **not** a product; its internals are `package`; only the types that were already public (`HRetryPolicy`, `HRequestError`, `HAuthProviderProtocol`, `HAuthorizationHeader`, `HDebugRequestProtocol`, `HDebugRequestType`, `HLoggingSensitiveKeyAction`, `HMTLS`/`HMTLSError`, `HURLSessionDelegate`, `HHttpMethod`, `HRequestManagerActor`, shared `Harbor` setters) are public there.

Alternative (B): Core as a visible product, users `import HarborCore` explicitly. Cleaner (no `@_exported`, which is underscored API) but adds a fourth product to the public surface, which is what we wanted to avoid.

## JSON-RPC

Keep `HarborJRPC → Harbor`. It needs the REST pipeline (decode, mocks excluded, retry, auth). Putting it on Core alone means a generic "HTTP exchange" engine in Core (perform a `URLRequest` with auth, retry, 401 refresh, session lease; return `(Data, HTTPURLResponse)`) with REST and JSON-RPC as two clients. That is cleaner in theory but rewrites `executeOnce`, the most tested path, to save JSON-RPC from linking cache/mocks. **Recommendation: not now.** Revisit only if a third HTTP-based product appears.

## Honest cost/benefit

Benefits: the compiler enforces the layering (WebSocket cannot touch REST types by accident); WebSocket-only apps stop seeing and linking cache, mocks, multipart and request protocols (~45% of the code); the public surface a WebSocket user sees shrinks to what applies to them; modules build and test independently.

Costs and risks:
1. **Module-qualified names change** (`Harbor.HRetryPolicy` becomes `HarborCore.HRetryPolicy`; also reflection/`String(reflecting:)`). Unqualified use is untouched by the re-export. 4.0.0 is unreleased, so this is the cheapest moment to do it, and never gets cheaper.
2. **Duplicated singletons if Core ends up embedded twice** (hypothesis, unverified): Xcode can build package targets as dynamic frameworks (`PackageFrameworks` appeared in the Example build log); a non-product Core compiled into two frameworks would give two `HConfig.shared`. Needs a spike before committing to (A).
3. **28 test files use `@testable import Harbor`, 21 touch internals** (`HConfig`, `HRequestManager`, `HCache.Manager`, `HURLBuilder`, `HRedactionPolicy`, `HLogger`): they need `@testable import HarborCore` and renames for the `HTransport` split. Mechanical, large diff.
4. Regression risk concentrates on the session pool and the attempt loop (covered by 449 tests + TSan).
5. DocC/SPI: public Core symbols document under the Core module; check how re-exported symbols render.

## Plan (each step ends green: build without warnings, `swift test`, SwiftLint, TSan on WebSocket)

**Step 0, spike (gate).** Throwaway: Core as a non-product target, `@_exported` from `Harbor` and `HarborWebSocket`; build the Example app in the simulator embedding both products and assert at runtime that `Harbor.setAuthProvider` is observed by a WebSocket handshake (one `HConfig.shared`). Also confirm `import HarborWebSocket` alone exposes `Harbor.setX`. Outcome: (A) confirmed, or fall back to (B) / Core as a hidden-but-declared product.

**Step 1, cut the seams inside the single module** (no module change, behavior identical; one commit per seam, in this order):
1. Split `HURLBuilder` files (edge 4). 2. `HSessionProfile` in the pool (2). 3. Split `HRequestManager` into `HTransport` + `HRequestManager` (3, 7). 4. Split `HConfig` (1). 5. Split `HDebugRequestProtocol` (5). 6. Group the `Harbor` setters into shared vs REST-only files (design question). 7. Add `scripts/check_core_closure.py` (the closure analysis used here) and make it assert that the Core file set references no REST type; it becomes the guard until the compiler takes over.

**Step 2, create the module.** `Package.swift`: target `HarborCore` (LogBird), `Harbor` depends on it, `@_exported import`; `git mv` the Core files; promote exactly the already-public symbols to `public`, the rest `package`; fix imports; tests: `@testable import HarborCore` where needed.

**Step 3, retarget.** `HarborWebSocket` and its tests depend on `HarborCore` only; `HarborJRPC` unchanged (`→ Harbor`).

**Step 4, prove it.** A fixture consumer target that imports only `HarborWebSocket`, calls `Harbor.setAuthProvider` and connects against the loopback server; build it and check with `nm` that no `HGetRequestProtocol`/`HCache`/`HMocker` symbols are linked. Full suite + TSan + Example app + SwiftLint.

**Step 5, docs.** `AGENTS.md` (modules, `package` rule, one file/one type per module, where new shared code goes), `architecture.md` (module diagram and request flow with `HTransport`), README (unchanged install; note WebSocket-only usage), skills, CHANGELOG (module names under *Changed* for 4.0.0; no behavior change).

Delivery: a new PR **stacked on #67** (branch from `feature/harbor-websocket`, base `release/4.0.0` after #67 merges) so #67 stays reviewable on its own. Estimate: step 0 half a day; step 1 about 1.5 days (7 seams); steps 2-5 about 1.5 days including the test-file churn. Most of the risk is in step 1.3 and 1.2.

## Decisions (taken)

1. Re-export (A): shared public setters and entities live in `HarborCore` and are re-exported by `Harbor` and `HarborWebSocket`.
2. `HarborJRPC` stays on `Harbor`.
3. Done before 4.0.0 ships, on `refactor/harbor-core`, branched from `feature/harbor-websocket` (stacked on #67).
4. Names: `HarborCore` (module) and `HTransport` (Core manager).

Original questions, kept for reference:

1. Re-export (A, recommended) or a visible Core product (B)?
2. `HarborJRPC` stays on `Harbor` (recommended) or moves to Core with a generic HTTP engine?
3. Do it before 4.0.0 ships (recommended: names change only once) or defer to a later major?
4. Internal names: `HTransport` for the Core manager; `HarborCore` as the module. Any preference?

## Outcome (implemented on `refactor/harbor-core`)

Done as planned (steps 1-5), with these deviations and findings:

- **No `HTransport` type.** Swift allows static stored properties in extensions, including from another module, so `HRequestManager` stays in `HarborCore` and `Harbor` extends it with the REST-only state (`HRequestManager+RESTState.swift`, `+RESTSession.swift`). Splitting the type would have renamed hundreds of references across 21 test files for no benefit.
- **`authGeneration` instead of a hook.** `Harbor.setAuthProvider(_:)` (shared, in Core) bumps `HRequestManager.authGeneration`; the REST state derives `cacheGeneration` from it and drops its remembered credentials lazily. Same observable behavior, no REST callback in Core.
- **`HSessionProfile`** (`defaults`, `urlCache`, `isolated`, `webSocket`) replaces the request-aware session selection; REST maps a request to a profile.
- **`HHTTPDate`** (Core) replaces `HCache.Manager.parseHTTPDate` for `Retry-After`; the cache keeps a thin wrapper.
- **`HRequestManagerActor.run`** (`package`): `HConfig` is isolated to the actor and, now that it lives in another module, can no longer be read with `await HConfig.shared.x` from non-isolated code.
- **Guards:** `scripts/check_core_independence.sh` (no REST names in `Sources/HarborCore`) and `scripts/check_websocket_only_link.sh` (the `Fixtures/WebSocketOnly` consumer imports only `HarborWebSocket`; 1,488 Core symbols, 0 REST symbols, and the handshake sees `Harbor.setAuthProvider`), both run in CI. A cross-product test in the Example app checks, in the simulator, that `Harbor` and `HarborWebSocket` share one configuration.
- **Process finding:** earlier "no warnings" checks used a pattern that never matched the compiler's output order (path first). The real CI pattern found an unused-result warning in PR #67, fixed in `88bb088`.

---
name: harbor-migration-v3-to-v4
description: Guide for migrating Harbor code from v3 to v4, addressing all breaking changes.
---

# Harbor v3 to v4 Migration Guide

This skill provides instructions on how to migrate code that uses Harbor v3 to the new Harbor v4 API.

## Breaking Changes & Migration Steps

### 1. `HAuthProviderProtocol` Return Type
**v3:** `func getAuthorizationHeader() async -> HAuthorizationHeader`
**v4:** `func getAuthorizationHeader() async -> HAuthorizationHeader?`
**Migration:** Change the return signature to optional. If no credentials exist, return `nil`.

### 2. `Harbor.setMTLS` Signature
**v3:** `Harbor.setMTLS(_ identity: HmTLS)` (synchronous)
**v4:** `Harbor.setMTLS(_ identity: HMTLS)` (async throws)
**Migration:** 
- Await the call: `try await Harbor.setMTLS(...)`. 
- Rename `HmTLS` to `HMTLS`.
- The `passwordProvider` closure is now `async throws`.

### 3. SSL Pinning Configuration
**v3:** `Harbor.setSSlPinningSHA256(_ pin: String?)` or `setSSlPinningKeys(...)` passing raw public key hashes.
**v4:** `Harbor.setSSLPinningKeys([String]?)` (or with `forHosts:`). 
**Migration:**
- Rename method to `setSSLPinningKeys`.
- **CRITICAL:** The pins must now be `base64(SHA256(SPKI))`. Old hashes of raw public keys will fail. Generate new pins using: `Harbor.computePin(for: certificate)`.

### 4. Cache Management Methods
**v3:** `Harbor.clearAllCache()` (synchronous). `TimeInterval.none`.
**v4:** `Harbor.clearAllCache()` is `async`. `TimeInterval.none` is `TimeInterval.noExpiration`.
**Migration:** Await `clearAllCache()`. Update `TimeInterval` references.

### 5. Error Enum Cases Renamed
**v3:** `.apiError`, `.codableError`, `.noConnectionError`, `.malformedRequestError`, `.timeoutError`
**v4:** `.api`, `.codable`, `.noConnection`, `.malformedRequest`, `.timeout`
**Migration:** Update switch statements and error handling to the new shorter case names.

### 6. JSON-RPC `parameters` Type
**v3:** `var parameters: [String: Any]?`
**v4:** `var parameters: HJRPCParams?`
**Migration:** Wrap parameters in `.named(dict)` or `.positioned(array)`. Remove `@unchecked Sendable` from your JRPC request structs since the new enum is fully `Sendable`.

### 7. JSON-RPC Request Execution
**v3:** `request()` returned an `HJRPCResponse` containing success/error cases without throwing.
**v4:** `request()` now throws on failure and directly returns the decoded `Model`. 
**Migration:** 
- Wrap `request()` in `do/catch`.
- If you prefer the old non-throwing behavior returning a response object, use `requestResult()` instead.

### 8. Protocol Properties Get-Only
**v3:** `var retries: Int? { get set }`, `var headers: [String: String]? { get set }`
**v4:** These protocol requirements are now `{ get }` only.
**Migration:** If you were modifying a request object's properties after initialization, you must now create a new request or use a builder pattern. Requests should generally be immutable `Sendable` structs.

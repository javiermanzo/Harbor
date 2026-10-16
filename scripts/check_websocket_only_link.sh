#!/bin/sh
# A WebSocket-only app must link none of Harbor's REST code (cache, mocks, request protocols,
# multipart). Builds Fixtures/WebSocketOnly, which imports only HarborWebSocket, and inspects the
# symbols of the resulting binary.
set -eu
cd "$(dirname "$0")/../Fixtures/WebSocketOnly"
swift build 2>&1 | tail -1
BIN=$(find .build -name WebSocketOnly -type f -perm +111 | head -1)
[ -n "$BIN" ] || { echo "error: fixture binary not found" >&2; exit 1; }

SYMBOLS=$(nm -U "$BIN" | swift demangle)
REST=$(echo "$SYMBOLS" | grep -cE 'HCache|HMocker|HGetRequestProtocol|HPostRequestProtocol|HFormValue|HRequestWithResultProtocol|HRESTConfig' || true)
CORE=$(echo "$SYMBOLS" | grep -c 'HarborCore' || true)
echo "HarborCore symbols: $CORE, REST symbols: $REST"
[ "$CORE" -gt 0 ] || { echo "error: HarborCore is not linked" >&2; exit 1; }
[ "$REST" -eq 0 ] || { echo "error: REST code is linked into a WebSocket-only binary" >&2; exit 1; }

OUTPUT=$("$BIN" 2>&1)
echo "$OUTPUT"
echo "$OUTPUT" | grep -q "authProviderNeeded" || { echo "error: the handshake did not see the shared configuration" >&2; exit 1; }
echo "WebSocket-only link check passed"

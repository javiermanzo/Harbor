#!/bin/sh
# HarborCore must not reference REST types: it is compiled before Harbor and WebSocket-only
# apps link it without Harbor. The compiler already enforces this through the target graph; this
# script gives a readable message and also catches REST names added in comments or strings.
set -eu
cd "$(dirname "$0")/.."
PATTERN='\b(HGetRequestProtocol|HPostRequestProtocol|HPutRequestProtocol|HPatchRequestProtocol|HDeleteRequestProtocol|HRequestWithBodyProtocol|HRequestWithResultProtocol|HRequestWithEmptyResponseProtocol|HRequestBaseRequestProtocol|HResponseWithResult|HResponse|HCache|HMocker|HMock|HMockSequence|HFormValue|HRESTConfig|HModel)\b'
if grep -rnE "$PATTERN" Sources/HarborCore | grep -v '^\S*:\s*[0-9]*:\s*///'; then
  echo "error: HarborCore references REST types (see above)" >&2
  exit 1
fi
echo "HarborCore is REST-free"

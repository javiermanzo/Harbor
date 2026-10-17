//
//  MTLSRequest.swift
//  HarborExample
//
//  Created by Jalil on 15/12/25.
//

import Harbor

/// GET request to certauth.cryptomix.com, a free public test server that requires a
/// client TLS certificate and echoes the TLS connection and client certificate details
/// back as JSON. The client identity is configured from the certificate.p12 bundled
/// with the app (valid until December 15, 2026) before this request runs.
struct MTLSRequest: HGetRequestProtocol {
    typealias Model = MtlsModel
    let url: String = "https://certauth.cryptomix.com/json"
}

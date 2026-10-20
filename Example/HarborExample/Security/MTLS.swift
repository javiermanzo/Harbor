//
//  MTLS.swift
//  HarborExample
//
//  Created by Jalil on 15/12/25.
//

import Foundation

// MARK: - Mtls
struct MtlsModel: Codable, Sendable {
    let user, home, httpAcceptLanguage, httpAcceptEncoding: String?
    let httpSECFetchDest, httpSECFetchUser, httpSECFetchMode, httpSECFetchSite: String?
    let httpAccept, httpUserAgent, httpUpgradeInsecureRequests, httpDnt: String?
    let httpSECChUaPlatform, httpSECChUaMobile, httpSECChUa, httpConnection: String?
    let httpHost, sslClientIDNCN, sslClientSDNCN, sslClientIDN: String?
    let sslClientSDN, sslClientVerify, sslClientVEnd, sslClientVStart: String?
    let sslClientSerial, sslClientFingerprint, sslSessionID, sslServerName: String?
    let sslCipher, sslProtocol, https, pathInfo: String?
    let serverName, serverPort, serverAddr, remotePort: String?
    let remoteAddr, serverProtocol, documentURI, requestURI: String?
    let contentLength, contentType, requestMethod, queryString: String?
    let serverSoftware, gatewayInterface, fcgiRole: String?
    let requestTimeFloat: Double?
    let requestTime: Int?

    enum CodingKeys: String, CodingKey {
        case user = "USER"
        case home = "HOME"
        case httpAcceptLanguage = "HTTP_ACCEPT_LANGUAGE"
        case httpAcceptEncoding = "HTTP_ACCEPT_ENCODING"
        case httpSECFetchDest = "HTTP_SEC_FETCH_DEST"
        case httpSECFetchUser = "HTTP_SEC_FETCH_USER"
        case httpSECFetchMode = "HTTP_SEC_FETCH_MODE"
        case httpSECFetchSite = "HTTP_SEC_FETCH_SITE"
        case httpAccept = "HTTP_ACCEPT"
        case httpUserAgent = "HTTP_USER_AGENT"
        case httpUpgradeInsecureRequests = "HTTP_UPGRADE_INSECURE_REQUESTS"
        case httpDnt = "HTTP_DNT"
        case httpSECChUaPlatform = "HTTP_SEC_CH_UA_PLATFORM"
        case httpSECChUaMobile = "HTTP_SEC_CH_UA_MOBILE"
        case httpSECChUa = "HTTP_SEC_CH_UA"
        case httpConnection = "HTTP_CONNECTION"
        case httpHost = "HTTP_HOST"
        case sslClientIDNCN = "SSL_CLIENT_I_DN_CN"
        case sslClientSDNCN = "SSL_CLIENT_S_DN_CN"
        case sslClientIDN = "SSL_CLIENT_I_DN"
        case sslClientSDN = "SSL_CLIENT_S_DN"
        case sslClientVerify = "SSL_CLIENT_VERIFY"
        case sslClientVEnd = "SSL_CLIENT_V_END"
        case sslClientVStart = "SSL_CLIENT_V_START"
        case sslClientSerial = "SSL_CLIENT_SERIAL"
        case sslClientFingerprint = "SSL_CLIENT_FINGERPRINT"
        case sslSessionID = "SSL_SESSION_ID"
        case sslServerName = "SSL_SERVER_NAME"
        case sslCipher = "SSL_CIPHER"
        case sslProtocol = "SSL_PROTOCOL"
        case https = "HTTPS"
        case pathInfo = "PATH_INFO"
        case serverName = "SERVER_NAME"
        case serverPort = "SERVER_PORT"
        case serverAddr = "SERVER_ADDR"
        case remotePort = "REMOTE_PORT"
        case remoteAddr = "REMOTE_ADDR"
        case serverProtocol = "SERVER_PROTOCOL"
        case documentURI = "DOCUMENT_URI"
        case requestURI = "REQUEST_URI"
        case contentLength = "CONTENT_LENGTH"
        case contentType = "CONTENT_TYPE"
        case requestMethod = "REQUEST_METHOD"
        case queryString = "QUERY_STRING"
        case serverSoftware = "SERVER_SOFTWARE"
        case gatewayInterface = "GATEWAY_INTERFACE"
        case fcgiRole = "FCGI_ROLE"
        case requestTimeFloat = "REQUEST_TIME_FLOAT"
        case requestTime = "REQUEST_TIME"
    }
}

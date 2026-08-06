import Foundation

/// A URLProtocol stub that intercepts requests to pokeapi.co and stream.example.com
/// and returns recorded responses, allowing tests to run without network access.
final class LocalStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [URL: (Data, HTTPURLResponse, Error?)] = [:]
    
    static func registerStub(for url: URL, data: Data, response: HTTPURLResponse, error: Error? = nil) {
        lock.lock()
        defer { lock.unlock() }
        responses[url] = (data, response, error)
    }
    
    static func clearStubs() {
        lock.lock()
        defer { lock.unlock() }
        responses.removeAll()
    }
    
    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return url.host == "pokeapi.co" || url.host == "stream.example.com"
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let url = request.url else { return }
        
        LocalStubURLProtocol.lock.lock()
        let stub = LocalStubURLProtocol.responses[url]
        LocalStubURLProtocol.lock.unlock()
        
        if let (data, response, error) = stub {
            if let error = error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            
            // Handle ETag / 304 Not Modified
            if let etag = response.value(forHTTPHeaderField: "ETag"),
               let clientETag = request.value(forHTTPHeaderField: "If-None-Match"),
               etag == clientETag {
                let notModified = HTTPURLResponse(url: url, statusCode: 304, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: notModified, cacheStoragePolicy: .allowed)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            let error = URLError(.fileDoesNotExist)
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
}

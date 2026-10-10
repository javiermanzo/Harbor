//
//  HRequestManager+Mock.swift
//  Harbor
//
//  Created by Javier Manzo on 16/02/2023.
//

import Foundation

// MARK: - Mocks
extension HRequestManager {
    /// Resolves the registered mock for one attempt, applying its delay and configured error.
    /// Failures are not logged here: `mockFailureOutcome` logs them once the attempt finishes.
    /// - Parameter request: The request being mocked.
    /// - Returns: The resolved mock, or the error the attempt failed with.
    static func resolveMock(for request: any HRequestBaseRequestProtocol) async -> Result<HMock, HRequestError> {
        guard let mock = HMocker.mock(request: request) else {
            return .failure(.malformedRequest(reason: "No mock is registered for \(type(of: request))"))
        }

        if let delay = mock.delay, !(await sleep(seconds: delay)) {
            return .failure(.cancelled)
        }

        if let hError = mock.error {
            return .failure(hError)
        }

        return .success(mock)
    }

    /// Outcome of a mocked attempt that failed: a mocked error is classified by the retry
    /// policy exactly like the real failure it stands for (see
    /// `HRetryPolicy.shouldRetry(mockedError:method:)`), so a registered `HMockSequence` can
    /// script a transient failure followed by a success.
    /// - Parameters:
    ///   - hError: The error the attempt failed with.
    ///   - request: The request being mocked.
    ///   - canRetry: Whether further retry attempts are available.
    ///   - errorResponse: Maps the error to the response type.
    /// - Returns: `.retry` for a retryable error while attempts remain, `.finish` otherwise.
    static func mockFailureOutcome<Response: Sendable>(_ hError: HRequestError, request: any HRequestBaseRequestProtocol, canRetry: Bool, errorResponse: (HRequestError) -> Response) async -> HAttemptOutcome<Response> {
        if hError != .cancelled, !Task.isCancelled, canRetry,
           request.retryPolicy?.shouldRetry(mockedError: hError, method: request.httpMethod) == true {
            return .retry(after: nil)
        }
        await logError(hError, request: request)
        return .finish(errorResponse(hError))
    }

    /// Builds the URL used for synthetic mock responses: the request's composite URL (path and,
    /// for GET requests, query parameters applied), or `file:///` when it cannot be built.
    /// - Parameter request: The mocked request.
    /// - Returns: The URL of the synthetic `HTTPURLResponse`.
    static func mockURL(for request: any HRequestBaseRequestProtocol) -> URL {
        if let getRequest = request as? any HGetRequestProtocol,
           let url = try? HURLBuilder.compositeURL(url: getRequest.url, pathParameters: getRequest.pathParameters, queryParameters: getRequest.queryParameters) {
            return url
        }
        return (try? HURLBuilder.compositeURL(url: request.url, pathParameters: request.pathParameters)) ?? URL(fileURLWithPath: "/")
    }
}

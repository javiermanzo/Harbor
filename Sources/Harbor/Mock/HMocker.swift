//
//  HMocker.swift
//  Harbor
//
//  Created by Javier Manzo on 06/11/2024.
//

import Foundation

/// In-memory registry of mocks. All access is serialized through `@HRequestManagerActor`.
/// Mocks are keyed by request metatype identity (via `ObjectIdentifier`), so identically
/// named types in different modules never collide.
@HRequestManagerActor
enum HMocker {
    /// Single mocks, keyed by request type.
    private static var mocks: [ObjectIdentifier: HMock] = [:]
    /// Mock sequences, keyed by request type.
    private static var sequences: [ObjectIdentifier: HMockSequence] = [:]
    /// Index of the next response of each sequence.
    private static var sequenceIndexes: [ObjectIdentifier: Int] = [:]
    /// Number of mocked attempts per request type.
    private static var callCounts: [ObjectIdentifier: Int] = [:]

    /// The registry key of a request type.
    private static func key(for requestType: HRequestBaseRequestProtocol.Type) -> ObjectIdentifier {
        ObjectIdentifier(requestType)
    }

    /// Registers a single mock response. Any existing mock or sequence for the same request type is removed.
    /// - Parameter mock: The response to answer requests of `mock.request` with.
    static func register(mock: HMock) {
        let id = key(for: mock.request)
        mocks[id] = mock
        sequences.removeValue(forKey: id)
        sequenceIndexes.removeValue(forKey: id)
    }

    /// Registers a scripted sequence of responses. Each resolution advances the sequence;
    /// after the last response is consumed it repeats indefinitely. A sequence with no
    /// responses is ignored.
    /// - Parameter mockSequence: The responses to play back for requests of `mockSequence.request`.
    static func register(mockSequence: HMockSequence) {
        guard !mockSequence.responses.isEmpty else { return }
        let id = key(for: mockSequence.request)
        sequences[id] = mockSequence
        sequenceIndexes[id] = 0
        mocks.removeValue(forKey: id)
    }

    /// Removes any registered mock or sequence for the given request type.
    /// - Parameter requestType: The request type that stops being mocked.
    static func removeMock(for requestType: HRequestBaseRequestProtocol.Type) {
        let id = key(for: requestType)
        mocks.removeValue(forKey: id)
        sequences.removeValue(forKey: id)
        sequenceIndexes.removeValue(forKey: id)
    }

    /// Clears all registered mocks, sequences, and call counts.
    static func removeAll() {
        mocks.removeAll()
        sequences.removeAll()
        sequenceIndexes.removeAll()
        callCounts.removeAll()
    }

    /// Resolves the mock for the given request instance, advancing any registered sequence.
    /// - Parameter request: The request instance whose type selects the mock.
    /// - Returns: The mock answering this attempt, or `nil` when the request type is not mocked.
    static func mock(request: HRequestBaseRequestProtocol) -> HMock? {
        let id = ObjectIdentifier(type(of: request))

        if let index = sequenceIndexes[id],
           let sequence = sequences[id] {
            callCounts[id, default: 0] += 1
            let response = sequence.response(at: index)
            sequenceIndexes[id] = min(index + 1, max(sequence.responses.count - 1, 0))
            return HMock(request: type(of: request),
                         statusCode: response.statusCode,
                         jsonResponse: response.jsonResponse,
                         error: response.error,
                         delay: response.delay,
                         headers: response.headers)
        }

        if let mock = mocks[id] {
            callCounts[id, default: 0] += 1
            return mock
        }

        return nil
    }

    /// Number of times the given request type has been resolved through a mock.
    /// - Parameter requestType: The request type whose mock resolutions are counted.
    static func callCount(for requestType: HRequestBaseRequestProtocol.Type) -> Int {
        callCounts[key(for: requestType)] ?? 0
    }

    /// Whether a mock (single or sequenced) is currently registered for the request type.
    /// - Parameter requestType: The request type to look up.
    static func isRegistered(_ requestType: HRequestBaseRequestProtocol.Type) -> Bool {
        let id = key(for: requestType)
        return mocks[id] != nil || sequences[id] != nil
    }
}

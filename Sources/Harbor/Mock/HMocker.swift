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
    private static var mocks: [ObjectIdentifier: HMock] = [:]
    private static var sequences: [ObjectIdentifier: HMockSequence] = [:]
    private static var sequenceIndexes: [ObjectIdentifier: Int] = [:]
    private static var callCounts: [ObjectIdentifier: Int] = [:]

    private static func key(for requestType: HRequestBaseRequestProtocol.Type) -> ObjectIdentifier {
        ObjectIdentifier(requestType)
    }

    static func register(mock: HMock) {
        let id = key(for: mock.request)
        mocks[id] = mock
        sequences.removeValue(forKey: id)
        sequenceIndexes.removeValue(forKey: id)
    }

    /// Registers a scripted sequence of responses. Each resolution advances the sequence;
    /// after the last response is consumed it repeats indefinitely.
    static func registerSequence(_ sequence: HMockSequence) {
        guard !sequence.responses.isEmpty else { return }
        let id = key(for: sequence.request)
        sequences[id] = sequence
        sequenceIndexes[id] = 0
        mocks.removeValue(forKey: id)
    }

    static func remove(mock: HMock) {
        let id = key(for: mock.request)
        mocks.removeValue(forKey: id)
        sequences.removeValue(forKey: id)
        sequenceIndexes.removeValue(forKey: id)
    }

    static func removeAll() {
        mocks.removeAll()
        sequences.removeAll()
        sequenceIndexes.removeAll()
        callCounts.removeAll()
    }

    /// Resolves the mock for the given request instance, advancing any registered sequence.
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
    static func callCount(for requestType: HRequestBaseRequestProtocol.Type) -> Int {
        callCounts[key(for: requestType)] ?? 0
    }

    /// Whether a mock (single or sequenced) is currently registered for the request type.
    static func isRegistered(_ requestType: HRequestBaseRequestProtocol.Type) -> Bool {
        let id = key(for: requestType)
        return mocks[id] != nil || sequences[id] != nil
    }
}

import XCTest
import SIPDomain
import SIPInfrastructure
@testable import UniversalSIPKit

final class UniversalSIPKitTests: XCTestCase {

    private func makeSDK(
        providerID: String = "sip.inmemory"
    ) -> (UniversalSIPKit, InMemoryVoiceProvider) {
        let provider = InMemoryVoiceProvider(providerID: providerID)
        let container = SIPDependencyContainer(provider: provider, credentialStore: InMemoryCredentialStore())
        return (UniversalSIPKit(container: container), provider)
    }

    private let config = SIPConfiguration(server: "sip.example.com", domain: "example.com", port: 5060, transport: .udp)

    func testOutgoingCallFlowEmitsExpectedEvents() async throws {
        let (sdk, _) = makeSDK()

        try await sdk.configure(configuration: config)
        try await sdk.addAccount(SIPAccountConfiguration(username: "1001", password: "secret"))

        // Subscribe before performing actions so no events are missed.
        let stream = await sdk.observeEvents()

        try await sdk.connect()
        let call = try await sdk.call(to: "1002")
        XCTAssertEqual(call.remoteNumber, "1002")

        let events = try await collect(from: stream, count: 5)

        XCTAssertTrue(events.contains { if case .registrationChanged(_, .registered) = $0 { return true }; return false },
                      "Expected a registered event")
        XCTAssertTrue(events.contains { if case .outgoingCallStarted = $0 { return true }; return false },
                      "Expected an outgoingCallStarted event")
        XCTAssertTrue(events.contains { if case .callConnected = $0 { return true }; return false },
                      "Expected a callConnected event")

        let current = await sdk.currentCalls()
        XCTAssertEqual(current.count, 1)
    }

    func testCallWithoutRegisteredAccountThrows() async throws {
        let (sdk, _) = makeSDK()
        try await sdk.configure(configuration: config)

        do {
            _ = try await sdk.call(to: "1002")
            XCTFail("Expected accountNotRegistered")
        } catch {
            XCTAssertEqual(error as? SIPError, .accountNotRegistered)
        }
    }

    func testIncomingCallSurfacesThroughSDK() async throws {
        let (sdk, provider) = makeSDK()
        try await sdk.configure(configuration: config)
        let accountConfig = SIPAccountConfiguration(username: "1001", password: "secret")
        try await sdk.addAccount(accountConfig)
        try await sdk.connect()

        let stream = await sdk.observeEvents()
        let incoming = await provider.simulateIncomingCall(accountID: accountConfig.id, from: "2000")

        let events = try await collect(from: stream, count: 1)
        XCTAssertEqual(events.first, .incomingCall(incoming))

        try await sdk.answer(callID: incoming.id)
        let current = await sdk.currentCalls()
        XCTAssertEqual(current.first?.state, .connected)
    }

    /// Proves the SDK drives a non-SIP (token-based) provider through the same
    /// public API, using the generic account path and an access-token credential.
    func testNonSIPProviderAccountFlow() async throws {
        let (sdk, _) = makeSDK(providerID: "twilio")
        let providerID = await sdk.providerID
        XCTAssertEqual(providerID, "twilio")

        try await sdk.initialize()

        let account = VoiceAccount(providerID: "twilio", identity: "alice", settings: ["region": "us1"])
        await sdk.addAccount(account, credential: .accessToken("test.jwt.token"))

        let stream = await sdk.observeEvents()
        try await sdk.connect()
        let call = try await sdk.call(to: "bob")
        XCTAssertEqual(call.accountID, account.id)

        let events = try await collect(from: stream, count: 5)
        XCTAssertTrue(events.contains { if case .registrationChanged(_, .registered) = $0 { return true }; return false },
                      "Expected the token account to reach registered")
        XCTAssertTrue(events.contains { if case .callConnected = $0 { return true }; return false },
                      "Expected a callConnected event on the non-SIP provider")
    }

    // MARK: - Helpers

    /// Collects up to `count` events from a stream, failing after a timeout so
    /// tests never hang.
    private func collect(
        from stream: AsyncStream<SIPEvent>,
        count: Int,
        timeout: TimeInterval = 2
    ) async throws -> [SIPEvent] {
        try await withThrowingTaskGroup(of: [SIPEvent].self) { group in
            group.addTask {
                var collected: [SIPEvent] = []
                for await event in stream {
                    collected.append(event)
                    if collected.count >= count { break }
                }
                return collected
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw SIPError.internalError
            }
            let result = try await group.next() ?? []
            group.cancelAll()
            return result
        }
    }
}

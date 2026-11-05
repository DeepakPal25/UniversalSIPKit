import XCTest
import SIPDomain
import SIPInfrastructure
@testable import SIPData

final class SIPDataTests: XCTestCase {

    private let account = SIPAccount(username: "1001", domain: "example.com")
        .asVoiceAccount(providerID: "sip.inmemory")
    private let credential = ProviderCredential.sip(SIPCredentials(authName: "1001", password: "secret"))

    func testAddAccountPersistsCredentialAndRegisters() async throws {
        let provider = InMemoryVoiceProvider()
        try await provider.initialize()
        let store = InMemoryCredentialStore()
        let repository = AccountRepositoryImpl(provider: provider, credentialStore: store)

        try await repository.addAccount(account, credential: credential)

        let stored = try await store.credential(for: account.id)
        XCTAssertEqual(stored, credential)

        let accounts = await repository.registeredAccounts()
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.id, account.id)
    }

    func testAddAccountRollsBackCredentialWhenRegistrationFails() async throws {
        let provider = FailingProvider()
        let store = InMemoryCredentialStore()
        let repository = AccountRepositoryImpl(provider: provider, credentialStore: store)

        do {
            try await repository.addAccount(account, credential: credential)
            XCTFail("Expected registration to fail")
        } catch {
            XCTAssertEqual(error as? SIPError, .registrationFailed)
        }

        // Credential must have been rolled back.
        let stored = try await store.credential(for: account.id)
        XCTAssertNil(stored)

        let accounts = await repository.registeredAccounts()
        XCTAssertTrue(accounts.isEmpty)
    }

    func testRemoveUnknownAccountThrows() async {
        let provider = InMemoryVoiceProvider()
        let store = InMemoryCredentialStore()
        let repository = AccountRepositoryImpl(provider: provider, credentialStore: store)

        do {
            try await repository.removeAccount(id: UUID())
            XCTFail("Expected accountNotFound")
        } catch {
            XCTAssertEqual(error as? SIPError, .accountNotFound)
        }
    }
}

/// A provider whose registration always fails, for exercising rollback.
private actor FailingProvider: VoiceProviderProtocol {
    nonisolated let providerID = "test.failing"
    private let broadcaster = EventBroadcaster()
    func initialize() async throws {}
    func shutdown() async throws {}
    func events() async -> AsyncStream<SIPCallEvent> { await broadcaster.subscribe() }
    func register(account: VoiceAccount, credential: ProviderCredential) async throws {
        throw SIPError.registrationFailed
    }
    func unregister(accountID: UUID) async throws {}
    func makeCall(accountID: UUID, destination: String) async throws -> SIPCall {
        throw SIPError.callFailed
    }
    func answerCall(callID: UUID) async throws {}
    func rejectCall(callID: UUID) async throws {}
    func endCall(callID: UUID) async throws {}
    func setMuted(callID: UUID, muted: Bool) async throws {}
    func setHeld(callID: UUID, held: Bool) async throws {}
    func currentCalls() async -> [SIPCall] { [] }
}

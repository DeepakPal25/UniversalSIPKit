import Foundation
import SIPDomain
import SIPData
import SIPInfrastructure

/// The composition root. Wires a concrete ``VoiceProviderProtocol`` and the
/// Data implementations to the Domain protocols, and vends configured use cases.
///
/// The provider is swappable: use ``inMemory()`` for demos/tests, or construct
/// with ``BaresipAdapter`` / ``PJSIPAdapter`` (SIP) or ``TwilioVoiceProvider``
/// (non-SIP) once their dependencies are vendored.
public struct SIPDependencyContainer: Sendable {

    public let provider: VoiceProviderProtocol
    public let credentialStore: CredentialStoreProtocol
    public let accountRepository: AccountRepositoryProtocol
    public let callRepository: CallRepositoryProtocol

    public init(
        provider: VoiceProviderProtocol,
        credentialStore: CredentialStoreProtocol
    ) {
        self.provider = provider
        self.credentialStore = credentialStore
        self.accountRepository = AccountRepositoryImpl(
            provider: provider,
            credentialStore: credentialStore
        )
        self.callRepository = CallRepositoryImpl(provider: provider)
    }

    /// Convenience root using the in-memory provider. Suitable for demos/tests.
    public static func inMemory() -> SIPDependencyContainer {
        SIPDependencyContainer(
            provider: InMemoryVoiceProvider(),
            credentialStore: InMemoryCredentialStore()
        )
    }

    // MARK: - Use case factories

    public func makeInitializeUseCase() -> InitializeSIPUseCase {
        InitializeSIPUseCase(engine: provider)
    }

    public func makeRegisterUseCase() -> RegisterAccountUseCase {
        RegisterAccountUseCase(repository: accountRepository)
    }

    public func makeUnregisterUseCase() -> UnregisterAccountUseCase {
        UnregisterAccountUseCase(repository: accountRepository)
    }

    public func makeMakeCallUseCase() -> MakeCallUseCase {
        MakeCallUseCase(engine: provider)
    }

    public func makeAnswerCallUseCase() -> AnswerCallUseCase {
        AnswerCallUseCase(engine: provider)
    }

    public func makeRejectCallUseCase() -> RejectCallUseCase {
        RejectCallUseCase(engine: provider)
    }

    public func makeEndCallUseCase() -> EndCallUseCase {
        EndCallUseCase(engine: provider)
    }

    public func makeHoldCallUseCase() -> HoldCallUseCase {
        HoldCallUseCase(engine: provider)
    }

    public func makeMuteCallUseCase() -> MuteCallUseCase {
        MuteCallUseCase(engine: provider)
    }

    public func makeObserveCallEventsUseCase() -> ObserveCallEventsUseCase {
        ObserveCallEventsUseCase(repository: callRepository)
    }
}

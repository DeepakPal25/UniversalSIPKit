// UniversalSIPKit — a provider-independent, open-source iOS calling SDK.
// SIP (Baresip/PJSIP) is one provider; token-based vendors (Twilio, …) are
// first-class too. See README for architecture and integration.

import Foundation
@_exported import SIPDomain
import SIPData
import SIPInfrastructure

/// The public entry point to the SDK.
///
/// The SDK owns the calling infrastructure (provider engine, registration, call
/// lifecycle) while the host application owns its user experience.
///
/// SIP flow: ``configure(configuration:)`` → ``addAccount(_:)`` →
/// ``connect()`` → ``call(to:)``.
///
/// Non-SIP flow (e.g. Twilio): construct with a container whose provider is the
/// vendor adapter, then ``initialize()`` → ``addAccount(_:credential:)`` →
/// ``connect()``. The rest of the API is identical.
public actor UniversalSIPKit {

    /// Shared singleton. Hosts may also construct their own instance with a
    /// custom ``SIPDependencyContainer`` for testing or a non-default provider.
    public static let shared = UniversalSIPKit()

    private var container: SIPDependencyContainer
    private var configuration: SIPConfiguration?

    /// Accounts added but not yet registered, keyed by account id.
    private var pendingAccounts: [UUID: (account: VoiceAccount, credential: ProviderCredential)] = [:]
    /// Accounts currently registered, keyed by account id.
    private var registeredAccounts: [UUID: VoiceAccount] = [:]

    private var isInitialized = false

    public init(container: SIPDependencyContainer = .inMemory()) {
        self.container = container
    }

    /// The active provider's identifier, e.g. `sip.baresip`, `twilio`.
    public var providerID: String { container.provider.providerID }

    // MARK: - Lifecycle

    /// Initializes the underlying provider engine. Idempotent. Required before
    /// adding accounts on the non-SIP path; ``configure(configuration:)`` calls
    /// it for you on the SIP path.
    public func initialize() async throws {
        guard !isInitialized else { return }
        try await container.makeInitializeUseCase()()
        isInitialized = true
    }

    /// Configures SIP server defaults and initializes the provider.
    public func configure(configuration: SIPConfiguration) async throws {
        self.configuration = configuration
        try await initialize()
    }

    /// Replaces the dependency container. Only valid before initialization.
    public func useContainer(_ container: SIPDependencyContainer) throws {
        guard !isInitialized else { throw SIPError.unsupportedOperation }
        self.container = container
    }

    // MARK: - Accounts

    /// Adds a SIP account to be registered on the next ``connect()``.
    /// Requires ``configure(configuration:)`` to have been called.
    public func addAccount(_ accountConfig: SIPAccountConfiguration) throws {
        guard let configuration else { throw SIPError.invalidConfiguration }
        let sipAccount = accountConfig.makeAccount(using: configuration)
        try SIPAccountValidator.validate(sipAccount)
        let account = accountConfig.makeVoiceAccount(
            using: configuration,
            providerID: container.provider.providerID
        )
        pendingAccounts[account.id] = (account, accountConfig.makeProviderCredential())
    }

    /// Adds any provider's account (SIP or non-SIP) to be registered on the
    /// next ``connect()``. Use this for token-based vendors such as Twilio.
    public func addAccount(_ account: VoiceAccount, credential: ProviderCredential) {
        pendingAccounts[account.id] = (account, credential)
    }

    /// Unregisters and removes an account.
    public func removeAccount(id: UUID) async throws {
        pendingAccounts[id] = nil
        if registeredAccounts[id] != nil {
            try await container.makeUnregisterUseCase()(accountID: id)
            registeredAccounts[id] = nil
        }
    }

    // MARK: - Connection

    /// Registers all pending accounts with their provider.
    public func connect() async throws {
        guard isInitialized else { throw SIPError.notInitialized }
        let register = container.makeRegisterUseCase()
        for (id, entry) in pendingAccounts {
            try await register(account: entry.account, credential: entry.credential)
            registeredAccounts[id] = entry.account
            pendingAccounts[id] = nil
        }
    }

    /// Unregisters all accounts.
    public func disconnect() async throws {
        let unregister = container.makeUnregisterUseCase()
        for id in registeredAccounts.keys {
            try await unregister(accountID: id)
        }
        registeredAccounts.removeAll()
    }

    // MARK: - Calls

    /// Places an outgoing call from the first registered account.
    @discardableResult
    public func call(to destination: String) async throws -> SIPCall {
        guard let accountID = registeredAccounts.keys.first else {
            throw SIPError.accountNotRegistered
        }
        return try await container.makeMakeCallUseCase()(accountID: accountID, destination: destination)
    }

    /// Places an outgoing call from a specific account.
    @discardableResult
    public func call(to destination: String, from accountID: UUID) async throws -> SIPCall {
        guard registeredAccounts[accountID] != nil else {
            throw SIPError.accountNotRegistered
        }
        return try await container.makeMakeCallUseCase()(accountID: accountID, destination: destination)
    }

    public func answer(callID: UUID) async throws {
        try await container.makeAnswerCallUseCase()(callID: callID)
    }

    public func reject(callID: UUID) async throws {
        try await container.makeRejectCallUseCase()(callID: callID)
    }

    public func endCall(callID: UUID) async throws {
        try await container.makeEndCallUseCase()(callID: callID)
    }

    public func setMuted(_ muted: Bool, callID: UUID) async throws {
        try await container.makeMuteCallUseCase()(callID: callID, muted: muted)
    }

    public func setHeld(_ held: Bool, callID: UUID) async throws {
        try await container.makeHoldCallUseCase()(callID: callID, held: held)
    }

    public func currentCalls() async -> [SIPCall] {
        await container.callRepository.currentCalls()
    }

    // MARK: - Events

    /// An independent stream of SDK events. Each call returns a new stream.
    public func observeEvents() async -> AsyncStream<SIPEvent> {
        await container.makeObserveCallEventsUseCase()()
    }
}

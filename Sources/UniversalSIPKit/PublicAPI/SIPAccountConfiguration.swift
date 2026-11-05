import Foundation
import SIPDomain

/// Per-account configuration supplied by the host app, including the secret
/// that the SDK immediately routes into secure storage.
public struct SIPAccountConfiguration: Sendable {

    public let id: UUID
    public let username: String
    public let password: String
    public let authName: String?

    public init(
        id: UUID = UUID(),
        username: String,
        password: String,
        authName: String? = nil
    ) {
        self.id = id
        self.username = username
        self.password = password
        self.authName = authName
    }

    /// Builds the publicly observable SIP account entity for the given server config.
    func makeAccount(using configuration: SIPConfiguration) -> SIPAccount {
        SIPAccount(
            id: id,
            username: username,
            domain: configuration.domain,
            port: configuration.port,
            transport: configuration.transport
        )
    }

    /// Projects into the provider-neutral ``VoiceAccount`` for the given provider.
    func makeVoiceAccount(using configuration: SIPConfiguration, providerID: String) -> VoiceAccount {
        makeAccount(using: configuration).asVoiceAccount(providerID: providerID)
    }

    /// Builds the secret credentials for secure storage.
    func makeCredentials() -> SIPCredentials {
        SIPCredentials(
            authName: authName ?? username,
            password: password,
            realm: nil
        )
    }

    /// Builds the provider-neutral credential for secure storage.
    func makeProviderCredential() -> ProviderCredential {
        .sip(makeCredentials())
    }
}

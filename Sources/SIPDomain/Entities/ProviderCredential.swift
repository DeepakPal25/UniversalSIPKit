import Foundation

/// Provider-neutral authentication material.
///
/// SIP providers use digest credentials; token-based vendors (Twilio, Vonage,
/// Agora) use a short-lived access token issued by the host's backend. The
/// `.custom` case carries arbitrary key/value secrets for other providers.
///
/// Like ``SIPCredentials``, instances are routed straight into secure storage
/// and never surface in public account metadata, logs, or events.
public enum ProviderCredential: Sendable, Equatable, Codable {
    case sip(SIPCredentials)
    case accessToken(String)
    case custom([String: String])

    /// Whether this credential carries any secret material.
    public var isEmpty: Bool {
        switch self {
        case .sip(let credentials): return credentials.password.isEmpty
        case .accessToken(let token): return token.isEmpty
        case .custom(let values): return values.isEmpty
        }
    }
}

extension ProviderCredential: CustomStringConvertible {
    /// Redacts all secret material so credentials are never printed by accident.
    public var description: String {
        switch self {
        case .sip(let credentials): return "ProviderCredential.sip(\(credentials))"
        case .accessToken: return "ProviderCredential.accessToken(<redacted>)"
        case .custom(let values): return "ProviderCredential.custom(keys: \(values.keys.sorted()))"
        }
    }
}

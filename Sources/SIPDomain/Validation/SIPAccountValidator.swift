import Foundation

/// Stateless business validation for SIP account configuration.
public enum SIPAccountValidator {

    /// Validates an account's configuration, throwing ``SIPError/invalidConfiguration``
    /// if any field is unusable.
    public static func validate(_ account: SIPAccount) throws {
        let username = account.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = account.domain.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !username.isEmpty else { throw SIPError.invalidConfiguration }
        guard !domain.isEmpty, domain.contains(".") else { throw SIPError.invalidConfiguration }
        guard (1...65535).contains(account.port) else { throw SIPError.invalidConfiguration }
    }
}

import Foundation

/// The registration state of a SIP account with its server.
public enum SIPRegistrationState: Sendable, Equatable {
    case unregistered
    case registering
    case registered
    case failed(reason: String)
}

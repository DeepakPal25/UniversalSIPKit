import Foundation

/// The unified public error type surfaced by the SDK.
///
/// Internal engine / PJSIP status codes are mapped into these cases so that
/// host applications never need to understand SIP protocol internals.
public enum SIPError: Error, Sendable, Equatable {
    case invalidConfiguration
    case invalidCredentials
    case registrationFailed
    case registrationTimeout
    case accountNotRegistered
    case accountNotFound
    case invalidDestination
    case callFailed
    case callNotFound
    case networkUnavailable
    case authenticationFailed
    case audioSessionFailed
    case pushRegistrationFailed
    case unsupportedOperation
    case notInitialized
    case internalError
}

extension SIPError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "The SIP configuration is invalid."
        case .invalidCredentials: return "The supplied SIP credentials are invalid."
        case .registrationFailed: return "SIP registration failed."
        case .registrationTimeout: return "SIP registration timed out."
        case .accountNotRegistered: return "The account is not registered."
        case .accountNotFound: return "The requested account does not exist."
        case .invalidDestination: return "The call destination is invalid."
        case .callFailed: return "The call failed."
        case .callNotFound: return "The requested call does not exist."
        case .networkUnavailable: return "The network is unavailable."
        case .authenticationFailed: return "Authentication with the SIP server failed."
        case .audioSessionFailed: return "The audio session could not be configured."
        case .pushRegistrationFailed: return "VoIP push registration failed."
        case .unsupportedOperation: return "This operation is not supported."
        case .notInitialized: return "The SIP engine has not been initialized."
        case .internalError: return "An internal error occurred."
        }
    }
}

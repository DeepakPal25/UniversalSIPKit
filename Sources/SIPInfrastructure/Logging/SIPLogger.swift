import Foundation
import OSLog

/// Centralized logging for the SDK built on `OSLog`.
///
/// Callers must never pass credentials or other secrets to these APIs. Values
/// are logged as `private` by the unified logging system by default.
public struct SIPLogger: Sendable {

    public enum Category: String, Sendable {
        case engine
        case registration
        case call
        case audio
        case push
        case callkit
        case security
    }

    private let logger: Logger

    public init(category: Category) {
        self.logger = Logger(subsystem: "com.universalsipkit", category: category.rawValue)
    }

    public func debug(_ message: String) { logger.debug("\(message, privacy: .public)") }
    public func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    public func error(_ message: String) { logger.error("\(message, privacy: .public)") }
    public func fault(_ message: String) { logger.fault("\(message, privacy: .public)") }
}

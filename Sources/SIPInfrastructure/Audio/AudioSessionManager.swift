import Foundation
import SIPDomain

/// Abstraction over audio-session control so higher layers never touch
/// `AVAudioSession` directly.
public protocol AudioSessionProtocol: Sendable {
    func activate() async throws
    func deactivate() async throws
    func setSpeakerEnabled(_ enabled: Bool) async throws
}

#if os(iOS)
import AVFoundation

/// Configures `AVAudioSession` for VoIP playback and recording.
///
/// Activation and deactivation must be coordinated with CallKit: when CallKit
/// is in use, the provider's `didActivate`/`didDeactivate` audio-session
/// callbacks drive activation, and this manager only configures the category
/// and routing. It must not independently fight CallKit over the session.
public actor AudioSessionManager: AudioSessionProtocol {

    private let session = AVAudioSession.sharedInstance()
    private let logger = SIPLogger(category: .audio)

    public init() {}

    /// Configures the VoIP audio category. Call this before reporting calls to
    /// CallKit; CallKit then owns actual activation.
    public func configureForCall() throws {
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
        } catch {
            logger.error("Failed to configure audio category: \(error.localizedDescription)")
            throw SIPError.audioSessionFailed
        }
    }

    public func activate() async throws {
        do {
            try configureForCall()
            try session.setActive(true, options: [])
        } catch {
            logger.error("Failed to activate audio session: \(error.localizedDescription)")
            throw SIPError.audioSessionFailed
        }
    }

    public func deactivate() async throws {
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
            throw SIPError.audioSessionFailed
        }
    }

    public func setSpeakerEnabled(_ enabled: Bool) async throws {
        do {
            try session.overrideOutputAudioPort(enabled ? .speaker : .none)
        } catch {
            logger.error("Failed to override audio port: \(error.localizedDescription)")
            throw SIPError.audioSessionFailed
        }
    }
}
#endif

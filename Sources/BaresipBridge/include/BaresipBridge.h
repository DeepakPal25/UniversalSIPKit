// BaresipBridge — C surface between libre/baresip and Swift.
//
// This header defines a small, stable C API over baresip. It never exposes
// baresip/libre types, so Swift (and the Domain layer above it) stay free of
// engine-specific symbols. The implementation in BaresipBridge.m compiles in
// one of two modes:
//
//   * If <baresip.h> is available (the XCFramework is linked), it calls into
//     baresip for real.
//   * Otherwise it compiles as a stub where every call returns
//     USK_BARESIP_ENOTAVAIL, so the whole package builds before the engine
//     binary is produced.
//
// All functions are synchronous and return a status code. Asynchronous SIP /
// call lifecycle is delivered through the event callback.

#ifndef USK_BARESIP_BRIDGE_H
#define USK_BARESIP_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Result codes. Mapped to SIPError on the Swift side.
typedef enum {
    USK_BARESIP_OK          =  0,
    USK_BARESIP_ENOTAVAIL   = -1, ///< baresip is not linked into this build
    USK_BARESIP_EINVAL      = -2, ///< invalid argument
    USK_BARESIP_EAUTH       = -3, ///< authentication failed
    USK_BARESIP_EREG        = -4, ///< registration failed
    USK_BARESIP_ECALL       = -5, ///< call operation failed
    USK_BARESIP_ENOTFOUND   = -6, ///< unknown call / account
    USK_BARESIP_EINTERNAL   = -7  ///< internal engine error
} usk_baresip_status;

/// Coarse event types surfaced to Swift. Mapped to SIPCallEvent.
typedef enum {
    USK_BARESIP_EV_REG_OK        = 1,
    USK_BARESIP_EV_REG_FAIL      = 2,
    USK_BARESIP_EV_REG_GONE      = 3,
    USK_BARESIP_EV_CALL_INCOMING = 10,
    USK_BARESIP_EV_CALL_RINGING  = 11,
    USK_BARESIP_EV_CALL_PROGRESS = 12,
    USK_BARESIP_EV_CALL_ESTABLISHED = 13,
    USK_BARESIP_EV_CALL_CLOSED   = 14
} usk_baresip_event;

/// Event callback.
/// @param ctx      Opaque context registered with usk_baresip_set_event_handler.
/// @param event    The event type.
/// @param aor      Account-of-record ("sip:user@domain"), or NULL.
/// @param call_id  Engine-assigned call id, or NULL for registration events.
/// @param peer     Remote party URI/number, or NULL.
/// @param code     SIP status code or engine error code (0 if n/a).
///
/// The callback may be invoked on an internal engine thread; the Swift side is
/// responsible for hopping onto its own executor before mutating state.
typedef void (*usk_baresip_event_cb)(void *ctx,
                                     usk_baresip_event event,
                                     const char *aor,
                                     const char *call_id,
                                     const char *peer,
                                     int code);

// MARK: - Lifecycle

/// Creates and starts the baresip endpoint. Call once before anything else.
usk_baresip_status usk_baresip_init(void);

/// Registers the event handler. Pass NULL to clear.
void usk_baresip_set_event_handler(usk_baresip_event_cb cb, void *ctx);

/// Drives the engine's run loop for up to `timeout_ms`. On iOS this is pumped
/// from a dedicated thread; exposed here so the Swift layer owns the cadence.
usk_baresip_status usk_baresip_poll(int timeout_ms);

/// Stops the endpoint and frees all resources.
usk_baresip_status usk_baresip_shutdown(void);

// MARK: - Accounts

/// Registers a SIP account. `transport` is one of "udp", "tcp", "tls".
usk_baresip_status usk_baresip_register(const char *aor,
                                        const char *auth_user,
                                        const char *password,
                                        const char *transport);

/// Unregisters a previously registered account.
usk_baresip_status usk_baresip_unregister(const char *aor);

// MARK: - Calls

/// Places an outgoing call. On success, writes the engine call id into
/// `out_call_id` (NUL-terminated, up to `out_len` bytes).
usk_baresip_status usk_baresip_make_call(const char *aor,
                                         const char *destination,
                                         char *out_call_id,
                                         int out_len);

usk_baresip_status usk_baresip_answer(const char *call_id);
usk_baresip_status usk_baresip_hangup(const char *call_id);
usk_baresip_status usk_baresip_set_mute(const char *call_id, int mute);
usk_baresip_status usk_baresip_set_hold(const char *call_id, int hold);

// MARK: - Audio / CallKit coordination
//
// On iOS, CallKit owns AVAudioSession activation. baresip must NOT open or
// close the audio device on its own; instead the Swift layer calls these in
// response to CXProviderDelegate's didActivate / didDeactivate callbacks.

/// Starts baresip's audio streams against the already-active audio session.
usk_baresip_status usk_baresip_audio_start(const char *call_id);

/// Stops baresip's audio streams ahead of audio-session deactivation.
usk_baresip_status usk_baresip_audio_stop(const char *call_id);

/// Reports whether this build was compiled with baresip linked. Returns 1 when
/// real, 0 when the stub is active. Lets Swift pick a fallback provider.
int usk_baresip_is_available(void);

#ifdef __cplusplus
}
#endif

#endif /* USK_BARESIP_BRIDGE_H */

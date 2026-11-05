// BaresipBridge implementation.
//
// Compiles against baresip when <baresip.h> is available (the XCFramework is
// linked); otherwise compiles as a no-op stub so the package builds before the
// engine binary exists. Flip the switch by adding the Baresip binary target and
// its header search paths (see docs/BARESIP-POC.md).

#import "BaresipBridge.h"
#import <string.h>

#if __has_include(<baresip.h>) && __has_include(<re.h>)
#  define USK_BARESIP_LINKED 1
#  include <re.h>
#  include <baresip.h>
#else
#  define USK_BARESIP_LINKED 0
#endif

static usk_baresip_event_cb g_event_cb = NULL;
static void *g_event_ctx = NULL;

void usk_baresip_set_event_handler(usk_baresip_event_cb cb, void *ctx) {
    g_event_cb = cb;
    g_event_ctx = ctx;
}

int usk_baresip_is_available(void) {
    return USK_BARESIP_LINKED;
}

#if USK_BARESIP_LINKED

// MARK: - Real implementation
//
// TODO(PoC): fill these in against baresip once the XCFramework is produced.
// The skeleton below documents the intended mapping; each function must:
//   - marshal C strings into baresip calls,
//   - translate baresip return codes into usk_baresip_status,
//   - forward baresip events (ua_event handler) to g_event_cb.
//
// Keep all baresip symbols confined to this file.

usk_baresip_status usk_baresip_init(void) {
    // int err = libre_init(); baresip_init(conf_config()); ua_init(...);
    return USK_BARESIP_EINTERNAL; // not yet implemented
}

usk_baresip_status usk_baresip_poll(int timeout_ms) {
    (void)timeout_ms;
    // re_main() is typically run on a dedicated thread; pump here if needed.
    return USK_BARESIP_EINTERNAL;
}

usk_baresip_status usk_baresip_shutdown(void) {
    // ua_stop_all(true); ua_close(); baresip_close(); libre_close();
    return USK_BARESIP_EINTERNAL;
}

usk_baresip_status usk_baresip_register(const char *aor,
                                        const char *auth_user,
                                        const char *password,
                                        const char *transport) {
    (void)aor; (void)auth_user; (void)password; (void)transport;
    return USK_BARESIP_EINTERNAL;
}

usk_baresip_status usk_baresip_unregister(const char *aor) {
    (void)aor;
    return USK_BARESIP_EINTERNAL;
}

usk_baresip_status usk_baresip_make_call(const char *aor,
                                         const char *destination,
                                         char *out_call_id,
                                         int out_len) {
    (void)aor; (void)destination;
    if (out_call_id && out_len > 0) out_call_id[0] = '\0';
    return USK_BARESIP_EINTERNAL;
}

usk_baresip_status usk_baresip_answer(const char *call_id) {
    (void)call_id; return USK_BARESIP_EINTERNAL;
}
usk_baresip_status usk_baresip_hangup(const char *call_id) {
    (void)call_id; return USK_BARESIP_EINTERNAL;
}
usk_baresip_status usk_baresip_set_mute(const char *call_id, int mute) {
    (void)call_id; (void)mute; return USK_BARESIP_EINTERNAL;
}
usk_baresip_status usk_baresip_set_hold(const char *call_id, int hold) {
    (void)call_id; (void)hold; return USK_BARESIP_EINTERNAL;
}
usk_baresip_status usk_baresip_audio_start(const char *call_id) {
    (void)call_id; return USK_BARESIP_EINTERNAL;
}
usk_baresip_status usk_baresip_audio_stop(const char *call_id) {
    (void)call_id; return USK_BARESIP_EINTERNAL;
}

#else

// MARK: - Stub implementation (baresip not linked)
//
// Every operation reports ENOTAVAIL so the Swift layer can fail fast and fall
// back to another provider. No events are ever emitted.

usk_baresip_status usk_baresip_init(void)      { return USK_BARESIP_ENOTAVAIL; }
usk_baresip_status usk_baresip_poll(int t)     { (void)t; return USK_BARESIP_ENOTAVAIL; }
usk_baresip_status usk_baresip_shutdown(void)  { return USK_BARESIP_ENOTAVAIL; }

usk_baresip_status usk_baresip_register(const char *aor,
                                        const char *auth_user,
                                        const char *password,
                                        const char *transport) {
    (void)aor; (void)auth_user; (void)password; (void)transport;
    return USK_BARESIP_ENOTAVAIL;
}

usk_baresip_status usk_baresip_unregister(const char *aor) {
    (void)aor; return USK_BARESIP_ENOTAVAIL;
}

usk_baresip_status usk_baresip_make_call(const char *aor,
                                         const char *destination,
                                         char *out_call_id,
                                         int out_len) {
    (void)aor; (void)destination;
    if (out_call_id && out_len > 0) out_call_id[0] = '\0';
    return USK_BARESIP_ENOTAVAIL;
}

usk_baresip_status usk_baresip_answer(const char *call_id)   { (void)call_id; return USK_BARESIP_ENOTAVAIL; }
usk_baresip_status usk_baresip_hangup(const char *call_id)   { (void)call_id; return USK_BARESIP_ENOTAVAIL; }
usk_baresip_status usk_baresip_set_mute(const char *c, int m){ (void)c; (void)m; return USK_BARESIP_ENOTAVAIL; }
usk_baresip_status usk_baresip_set_hold(const char *c, int h){ (void)c; (void)h; return USK_BARESIP_ENOTAVAIL; }
usk_baresip_status usk_baresip_audio_start(const char *c)    { (void)c; return USK_BARESIP_ENOTAVAIL; }
usk_baresip_status usk_baresip_audio_stop(const char *c)     { (void)c; return USK_BARESIP_ENOTAVAIL; }

#endif

# Baresip Integration PoC — Runbook

**Goal:** prove that libre/baresip can establish a **two-way audio call that
coordinates correctly with CallKit** on a physical iPhone, before committing to
the full SDK. Success here commits UniversalSIPKit to Baresip; failure triggers
the PJSIP fallback (cheap, because the engine sits behind `VoiceProviderProtocol`).

> Scope discipline: **do not** build PushKit, the backend gateway, or the full
> public API during the PoC. Prove audio + CallKit first.

---

## 0. What already exists (build-green today)

The Swift/C scaffold is in place and compiles on macOS **and** iOS with no
engine binary, because the C bridge is guarded by `#if __has_include(<baresip.h>)`
and compiles as a stub that returns `ENOTAVAIL`:

| Piece | Path | State |
|---|---|---|
| C bridge header | `Sources/BaresipBridge/include/BaresipBridge.h` | ✅ stable C API |
| C bridge impl | `Sources/BaresipBridge/BaresipBridge.m` | ✅ stub + real-path TODOs |
| Swift engine | `Sources/SIPInfrastructure/Baresip/BaresipEngine.swift` | ✅ full control flow; C calls pending |
| Event bridge | `Sources/SIPInfrastructure/Baresip/BaresipEventBridge.swift` | ✅ C events → `SIPCallEvent` |
| Build scripts | `Scripts/build-baresip-ios.sh`, `Scripts/create-xcframework.sh` | ✅ scaffold + TODOs |
| Package wiring | `Package.swift` (`BaresipBridge` target) | ✅ binary target documented, commented |

`BaresipEngine.isEngineAvailable` returns `false` until the XCFramework is
linked; the composition root can use that to fall back to `InMemoryVoiceProvider`.

---

## 1. License audit (do first, gate for distribution)

- [ ] Record exact libre + baresip commit hashes used (in `Vendor/README.md`).
- [ ] Confirm both are BSD-3-Clause at those commits.
- [ ] Enumerate every baresip **module** compiled in; confirm each is BSD/MIT/ISC.
- [ ] Keep codecs to **Opus + G.711** only. No G.729/AMR/H.264 in the default build.
- [ ] Note TLS/SRTP dependency (OpenSSL/BoringSSL) and its license.
- [ ] Produce a THIRD-PARTY-NOTICES draft from the above.

If any default-on dependency is copyleft or patent-encumbered, stop and resolve
before packaging.

---

## 2. Vendor the source

```sh
git clone https://github.com/baresip/re.git      Vendor/re
git clone https://github.com/baresip/baresip.git Vendor/baresip
```

(There is no `librem` — it was merged into `re`/libre.)

## 3. Build per-slice static libs

```sh
Scripts/build-baresip-ios.sh
```

**Verify (the script's TODOs):**
- [ ] libre cross-compiles for `iphoneos/arm64`, `iphonesimulator/arm64`, `iphonesimulator/x86_64`.
- [ ] baresip links against that libre build with a minimal, royalty-free module set.
- [ ] `.a` outputs and public headers land under `.build-baresip/artifacts/<slice>/`.

## 4. Package the XCFramework

```sh
Scripts/create-xcframework.sh   # -> Frameworks/Baresip.xcframework
```

- [ ] The two simulator slices are merged with `lipo` before `-create-xcframework`.
- [ ] `xcodebuild -create-xcframework` succeeds with device + simulator libraries.

## 5. Flip the bridge to the real engine

In `Package.swift`:

```swift
.binaryTarget(name: "Baresip", path: "Frameworks/Baresip.xcframework"),

.target(name: "BaresipBridge", dependencies: ["Baresip"]),
```

- [ ] Rebuild. `usk_baresip_is_available()` now returns 1; `#if __has_include`
      compiles the real branch of `BaresipBridge.m`.

## 6. Implement the native bridge body

Fill in `BaresipBridge.m`'s `#if USK_BARESIP_LINKED` branch:

- [ ] `usk_baresip_init`: `libre_init()` → `baresip_init(conf_config())` → `ua_init(...)`; start `re_main` on a dedicated thread (or pump via `usk_baresip_poll`).
- [ ] `usk_baresip_register`: build a `ua`/account from aor + auth, kick off REGISTER.
- [ ] Install a `uag_event_register` / `bevent` handler that maps baresip events to `g_event_cb` with the coarse `usk_baresip_event` types.
- [ ] `usk_baresip_make_call`: `ua_connect(...)`; write the call id into `out_call_id`.
- [ ] `answer`/`hangup`/`set_mute`/`set_hold`: map to `ua_answer`/`ua_hangup`/`call_mute`/`call_hold`.
- [ ] **Audio:** route baresip audio through the `audiounit`/coreaudio module but
      keep the audio unit **stopped** until `usk_baresip_audio_start` is called.

The Swift layer (`BaresipEngine` + `BaresipEventBridge`) needs no changes — it is
already written against this C API.

## 7. CallKit audio handoff — the critical gate 🔴

baresip must **never** activate/deactivate `AVAudioSession` itself. CallKit owns
it. Wire the sequence:

```
Outgoing:
  CXStartCallAction            -> BaresipEngine.makeCall(...)
  CXProvider didActivate audio -> BaresipEngine.startAudio(callID:)   // baresip audio unit starts
  call ends / CXEndCallAction  -> BaresipEngine.endCall(...)
  CXProvider didDeactivate     -> BaresipEngine.stopAudio(callID:)

Incoming:
  VoIP push (later) / INVITE   -> SIPCallEvent.incomingCall -> report to CallKit
  CXAnswerCallAction           -> BaresipEngine.answerCall(...)
  CXProvider didActivate audio -> BaresipEngine.startAudio(callID:)
```

`AudioSessionManager.configureForCall()` sets the category BEFORE reporting to
CallKit; CallKit then performs activation and fires `didActivate`.

**Pass criteria:** audio flows only after `didActivate`, stops cleanly on
`didDeactivate`, and survives route changes (speaker/AirPods). This is the make-
or-break measurement — a successful REGISTER proves nothing about audio.

---

## 8. Validation gates (all on a physical iPhone)

| # | Test | Pass criteria |
|---|---|---|
| 1 | iOS build | Device + simulator slices build; app links the XCFramework |
| 2 | SIP registration | `registrationChanged(.registered)` against a real server |
| 3 | Bad credentials | Maps to `SIPError.authenticationFailed`, no crash |
| 4 | Outgoing call | INVITE → answered → `callConnected` |
| 5 | Incoming call | INVITE → `incomingCall` reported to CallKit UI |
| 6 | **Audio activation** 🔴 | Audio starts only on CallKit `didActivate` |
| 7 | **Two-way audio** 🔴 | Both parties hear each other clearly |
| 8 | Route change | Speaker/AirPods switch keeps audio intact |
| 9 | Termination | BYE → `callEnded`; audio unit + SIP resources freed |
| 10 | License | §1 audit complete and clean |

---

## 9. Decision

- **All gates pass →** commit to Baresip; proceed to flesh out `BaresipEngine`
  edge cases, then PushKit + backend gateway + public API hardening.
- **Audio gate (6/7) fails and can't be resolved at acceptable cost →** switch
  the composition root to `PJSIPAdapter`. No Domain/Data/API changes required;
  that is the entire point of the `VoiceProviderProtocol` seam.

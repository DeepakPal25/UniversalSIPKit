# Engine Evaluation & Gap Analysis

**Project:** UniversalSIPKit
**Status:** Decision record — supersedes the PJSIP assumption in the original spec
**Last updated:** 2026-11-05

This document records *which calling engine UniversalSIPKit should build on*, *why*, and *exactly which modules we build vs. reuse*. It covers two independent axes:

1. **Which SIP engine** (Baresip vs PJSIP vs Linphone) — a licensing + integration-cost decision.
2. **SIP vs. non-SIP vendors** (Twilio/Vonage/Agora) — why the SDK's engine seam is provider-neutral, not SIP-only.

> TL;DR — **Baresip (+ libre)** is the preferred SIP engine because it is the only permissively-licensed option (BSD-3-Clause), which is a hard requirement for a reusable open-source SDK that closed-source apps can adopt. The engine boundary is generalized to `VoiceProviderProtocol` so SIP is *one* provider and token-based vendors (Twilio, …) are first-class. The single biggest unvalidated risk is handing Baresip's audio device over to CallKit's `AVAudioSession`; a proof-of-concept must clear that gate before we commit.

---

## 1. Product constraints that drive the decision

From the project charter, the non-negotiables are:

- **Reusable open-source SDK** integrable into *commercial, closed-source* apps.
- **Provider independence** — not tied to one SIP server or vendor.
- **Replaceable engine** behind a stable Swift public API.
- Native **CallKit** + **PushKit/APNs** incoming calls.
- Clean Architecture, Swift 6 concurrency, SPM + XCFramework distribution.

The first bullet is the dominant constraint: **the engine's license must permit closed-source redistribution without a per-app commercial fee.** This single requirement eliminates two of the three SIP engines.

---

## 2. SIP engine comparison

### 2.1 Licensing (the deciding factor)

| Engine | License | Closed-source app without a paid license? | Verdict |
|---|---|---|---|
| **Baresip** (+ libre) | **BSD-3-Clause** | ✅ Yes | **Chosen** |
| **PJSIP** (pjproject) | **Dual: GPLv2+ / commercial** | ❌ No — GPL would force every consuming app to be GPL; closed-source needs a Teluu commercial license | Fallback only |
| **Linphone** (liblinphone) | **Dual: AGPLv3 / commercial** | ❌ No — AGPL is more viral still; closed-source needs a Belledonne license | Rejected |

Under GPL/AGPL, UniversalSIPKit *itself* becomes (A)GPL, and so does any app that links it — which directly defeats "any iOS developer can integrate, including commercial apps." Only BSD-licensed Baresip preserves the product vision.

**Codec caveat (applies to all three):** royalty-free codecs (Opus, G.711) are clean. Patent-encumbered codecs (G.729, AMR, H.264) carry separate licensing obligations regardless of the engine license. **UniversalSIPKit ships Opus + G.711 only by default**; any non-free codec is an explicit opt-in the host is responsible for licensing.

### 2.2 Integration & engineering cost

| Criterion | Baresip | PJSIP | Linphone |
|---|---|---|---|
| Language / API | C (libre async core) | C with C++ `pjsua2` wrapper | C with prebuilt Swift/iOS SDK |
| iOS prior art | Sparse; no turnkey SPM XCFramework | Extensive (CSipSimple lineage, many wrappers) | Extensive; ships a ready iOS SDK |
| We build the XCFramework? | **Yes** (libre + baresip, device + sim slices) | Yes, but well-trodden | No — prebuilt, but heavy & (A)GPL |
| "Replaceable engine" fit | Excellent (modular, minimal) | Excellent | Poor (monolithic mediastreamer2 stack) |
| Audio model on iOS | Opens its own audio device — must defer to CallKit | Same concern, but more worked examples | Handles internally (less control) |
| Time-to-first-call | Longest | Shortest | Short |
| License fit | ✅ | ❌ | ❌ |

**Reading:** PJSIP and Linphone are *easier*, but their licenses are disqualifying for this product. Baresip's cost is real and concentrated in two places: (1) producing and maintaining the iOS XCFramework, and (2) the CallKit audio handoff. The architecture (`VoiceProviderProtocol`) means that if the Baresip PoC fails on cost, we can drop in `PJSIPAdapter` **without touching Domain, Data, use cases, or the public API** — the fallback is cheap precisely because the seam is clean.

### 2.3 Corrections to common comparisons

- **There is no `librem`.** Baresip's media library was merged into **`libre`** years ago. The dependency set is `libre` + `baresip` (+ optional modules).
- **The old `BelledonneCommunications/liblinphone` repo is a mirror/dev source**; current development is consolidated in `linphone-sdk`. Immaterial to the licensing conclusion.
- **"Fewer iOS examples" understates the Baresip cost** — the real gap is the *absence of a maintained, SPM-distributable Baresip-for-iOS binary*. We own that.

---

## 3. The second axis: SIP vs. non-SIP vendors

The original spec assumed "the engine == a SIP stack." That is too narrow. **Twilio Voice, Vonage, and Agora are not SIP from the app's perspective:**

| Concept | SIP (Baresip/PJSIP) | Twilio / Vonage / Agora |
|---|---|---|
| Auth | Digest (username/password) + REGISTER | Short-lived **access token** minted by *your* backend |
| Server coordinates | domain / port / transport | Vendor cloud + app identity / region |
| Signaling | SIP INVITE/BYE on the wire | Vendor-proprietary SDK |
| Incoming call wake-up | Your push gateway → APNs VoIP | Vendor's push + `handleNotification` |

A "bypass SIP" flag cannot express this — the account and credential *shapes* differ. So the engine boundary is **provider-neutral**:

- `VoiceProviderProtocol` — universal verbs (`register`, `makeCall`, `answer`, `end`, `mute`, `hold`, `events`). `register` means "REGISTER" for SIP and "prepare this identity / register push creds" for a vendor.
- `VoiceAccount` — `providerID` + `identity` + `settings` dictionary (SIP domain/port/transport, or vendor region).
- `ProviderCredential` — `.sip(SIPCredentials)` / `.accessToken(String)` / `.custom([String:String])`.

This is the architectural differentiator over PJSIP/Linphone/Baresip wrappers, which are all SIP-locked: **UniversalSIPKit is a universal calling abstraction where SIP engines and vendor SDKs are interchangeable behind one public API.** Proven today by `testNonSIPProviderAccountFlow`, which drives a `"twilio"`-tagged provider with an access-token credential through the same `addAccount → connect → call` path.

### 3.1 "FreeSip" clarification
FreeSip is an **end-user AGPLv3 iPhone app** (notable for bundling its own VoIP-push server), **not an SDK**. There is nothing to integrate as a library; it is useful only as a reference for the push-wake-up UX, not as a dependency.

---

## 4. Build vs. reuse — module by module

Legend: **Reuse** = provided by the engine/vendor, do not reimplement. **Build** = UniversalSIPKit owns it (the SDK's actual value). **Config** = host responsibility.

| Module | SIP (Baresip) | Twilio/vendor | UniversalSIPKit decision |
|---|---|---|---|
| SIP registration / signaling | Reuse (baresip) | N/A (vendor) | **Reuse** — never hand-roll SIP |
| SDP / RTP / RTCP | Reuse (libre/baresip) | Reuse (vendor) | **Reuse** |
| SRTP / TLS | Reuse (baresip) | Reuse (vendor) | **Reuse** |
| NAT traversal (STUN/TURN/ICE) | Reuse (libre) | Reuse (vendor) | **Reuse** |
| Codecs (Opus/G.711) | Reuse | Reuse | **Reuse**; non-free codecs opt-in only |
| Engine build → iOS XCFramework | — | prebuilt | **Build** (Baresip) — *the main new work* |
| Swift ⇄ C bridge, actor-safe | — | thin | **Build** — `BaresipAdapter` / vendor adapter |
| `VoiceProviderProtocol` seam | — | — | **Build** ✅ done |
| Clean Architecture (Domain/Data/DI) | — | — | **Build** ✅ done |
| Public Swift API + events | — | — | **Build** ✅ done |
| CallKit integration | custom | custom | **Build** ✅ skeleton (`CallKitManager`) |
| PushKit integration | custom | custom | **Build** ✅ skeleton (`VoIPPushManager`) |
| APNs push gateway (SIP only) | — | vendor handles | **Build or integrate** (server-side) |
| `AVAudioSession` ↔ CallKit coordination | custom | partly vendor | **Build** ✅ skeleton (`AudioSessionManager`) |
| Keychain credential storage | — | ephemeral tokens | **Build** ✅ (`KeychainCredentialStore`) |
| Multi-account registry | — | — | **Build** ✅ (`AccountRepositoryImpl`) |
| SPM / XCFramework packaging | — | — | **Build** |

**Net:** the signaling/media stack is 100% reuse. Everything the engines deliberately leave to the app — the iOS calling fabric and a clean replaceable abstraction — is exactly what UniversalSIPKit builds, and most of it already compiles and is tested against `InMemoryVoiceProvider`.

---

## 5. Risks & open questions (ranked)

1. **🔴 Baresip audio ↔ CallKit handoff.** Baresip opens its own audio device; on iOS it must *not* activate/deactivate `AVAudioSession` itself — CallKit's `didActivate`/`didDeactivate` must drive it. **This is the PoC's pass/fail gate.** Unknown until measured on-device.
2. **🟠 iOS XCFramework build.** libre + baresip for arm64 device + arm64/x86_64 simulator, modern Xcode, no bitcode, reproducible in CI. Maintenance burden is ongoing, not one-time.
3. **🟠 Force-quit / background delivery.** VoIP push → CallKit report within the PushKit window, including after the app is suspended. iOS gives no guarantee after a *user* force-quit — must be tested and documented, not assumed.
4. **🟡 Token lifecycle for vendors.** Access tokens expire; the SDK needs a host-supplied token-provider hook (refresh on demand) rather than persisting tokens. Design pending for the Twilio adapter.
5. **🟡 Codec licensing hygiene.** Keep non-free codecs opt-in and documented so the BSD cleanliness isn't silently lost.

---

## 6. Decision & sequencing

| Decision | Choice |
|---|---|
| Preferred SIP engine | **Baresip (+ libre)**, BSD-3-Clause |
| Fallback SIP engine | PJSIP (only if Baresip PoC fails on cost; architecture makes the swap cheap) |
| Non-SIP support | First-class via `VoiceProviderProtocol`; Twilio is the reference vendor adapter |
| SDK license | MIT or BSD-3-Clause (pending final dependency audit) |
| Default codecs | Opus + G.711 only |

**Recommended order:**

1. ✅ **Provider-neutral architecture** (done — `VoiceProviderProtocol`, generic account/credential, tested).
2. **This gap analysis** (done — this document).
3. **Baresip iOS PoC** → the decision gate: build the XCFramework, register one account against a real SIP server, establish two-way audio on a physical iPhone **through CallKit's audio session**. Succeed here before writing the full adapter.
4. **`BaresipAdapter`** — flesh out the skeleton against the verified PoC (actor-safe callback bridging → `SIPCallEvent`).
5. **iOS calling fabric** — complete CallKit/PushKit/audio/Keychain + the push gateway contract.
6. **Twilio adapter** — prove the non-SIP path end-to-end (token provider hook + vendor push handling).

> The PoC (step 3) is the real commitment point. Everything above it is reversible at near-zero cost because the Domain contracts never mention a specific engine.

---

## 7. Current implementation status

- **Done & tested (16 tests, macOS + iOS build green):** Domain, Data, DI, public API, event stream, provider-neutral seam, `InMemoryVoiceProvider` (functional), credential stores.
- **Skeletons (throw `.unsupportedOperation` until deps vendored):** `BaresipAdapter`, `PJSIPAdapter`, `TwilioVoiceProvider`, plus iOS-guarded `CallKitManager` / `VoIPPushManager` / `AudioSessionManager`.
- **Not started:** engine XCFramework builds, the C bridge target, the server-side push gateway, demo app, README/LICENSE.

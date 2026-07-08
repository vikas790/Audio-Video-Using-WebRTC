# AudioVideo Task — Implementation Guide

A 1-to-1 voice calling app with live presence and in-call text chat. Built with Flutter, WebRTC, and Firebase Firestore for signalling.

This repo has a BLoC + GetIt scaffold with the folder structure and screen shells in place. Firebase, WebRTC, and permissions still need to be wired — this guide covers what to build next, in what order, and how.

---

## Overview

**What you're building**

- A lobby screen showing who is online
- 1-to-1 audio calls between two clients (video is a stretch goal)
- Text chat during an active call
- Clear call states: ringing, connecting, connected, ended, declined, failed

**What you're not building**

- Login or authentication (name entry is enough)
- Group calls, call history, push notifications
- Production-grade backend scaling

**Platform focus**

- Android is the primary target. iOS is optional.
- Test on two emulators, two physical devices, or one of each.

**Build order**

Ship audio + presence + chat first. Add video and the native bridge bonus only after the core works.

### Evaluation weights

| Area | Weight |
|------|--------|
| WebRTC calling + lifecycle | 35% |
| Presence + in-call chat | 20% |
| Architecture + tests | 20% |
| UI/UX + edge cases | 15% |
| Code quality + docs | 10% |
| Native bridge (bonus) | +10% |

---

## Prerequisites

- Flutter SDK `^3.9.2`
- Android Studio with at least one emulator (two for call testing)
- A Firebase project with Cloud Firestore enabled
- Basic familiarity with BLoC and WebRTC concepts

### Current dependencies

Already in `pubspec.yaml`:

```yaml
dependencies:
  get_it: ^8.0.3
  flutter_bloc: ^9.1.0
```

### Packages to add

Add these to `pubspec.yaml` as you reach each phase:

```yaml
dependencies:
  # Signalling + presence
  firebase_core: ^3.0.0
  cloud_firestore: ^5.0.0

  # WebRTC media
  flutter_webrtc: ^0.12.0

  # Permissions
  permission_handler: ^11.0.0

  # Optional — video stretch goal only
  # camera: ^0.11.0
```

Run `flutter pub get` after each batch of additions.

---

## Architecture

The project uses a layered structure. Screen shells and service stubs are already in place — implement the `TODO` items in each phase below.

```
lib/
├── config/
│   ├── locator.dart           # GetIt setup
│   ├── common_di.dart         # Service + repository registration
│   └── firebase_config.dart   # Firebase init (placeholder)
├── data/
│   ├── models/
│   │   ├── user_model.dart
│   │   ├── call_state_model.dart
│   │   ├── chat_message_model.dart
│   │   └── signalling_message_model.dart
│   ├── repositories/
│   │   ├── presence_repository.dart
│   │   ├── signalling_repository.dart
│   │   └── chat_repository.dart
│   └── services/
│       ├── presence_service.dart          # stub — wire Firestore in Phase 1
│       ├── firestore_signalling_service.dart
│       └── webrtc_service.dart
├── routing/
│   └── navigation_service.dart
├── ui/
│   ├── base/                  # BaseCubit, ApiRenderState
│   ├── core/themes/           # AppTheme
│   └── screens/
│       ├── name_entry/        # First launch
│       ├── lobby/             # Online users list
│       ├── pre_join/          # Mic check before call
│       └── call/              # In-call UI + chat
└── utils/
    ├── constant.dart
    └── local_storage.dart     # deviceId + display name
```

### App flow

```
NameEntryScreen  →  LobbyScreen  →  PreJoinScreen  →  CallScreen
     (no name)        (home)         (tap user)        (in call)
```

No dashboard tabs. After name entry, the lobby is the main screen.

### State management

Use **BLoC/Cubit** throughout (already in the project). One cubit per feature:

| Cubit | Responsibility |
|-------|----------------|
| `PresenceCubit` | Stream of online/offline users |
| `CallCubit` | Call lifecycle state machine |
| `ChatCubit` | In-call message list |

### Key rule

WebRTC and Firestore logic live in `data/services/`. Widgets read state and dispatch events. They never create or own `RTCPeerConnection` instances.

### Call lifecycle

```
Idle
  → Ringing        (outgoing or incoming call)
  → Connecting     (callee accepted, ICE negotiating)
  → Connected      (media flowing)
  → Ended          (hang up or remote ended)
  → Declined       (callee rejected)
  → Failed         (ICE error, network drop, timeout)
```

Each state must be visible in the UI — status text, button states, or a simple indicator bar.

### Signalling flow (Firestore)

```
Caller                          Firestore                         Callee
  |                                |                                |
  |-- create call doc + offer ---->|                                |
  |                                |--- snapshot listener --------->|
  |                                |<-- write answer ---------------|
  |<-- answer received ------------|                                |
  |-- trickle ICE candidates ----->|                                |
  |                                |--- ICE candidates ----------->|
  |<=========== audio media (P2P, not through Firestore) =========>|
```

Firestore carries SDP and ICE only. Audio travels peer-to-peer once the connection is established.

---

## Firebase Setup

### 1. Create the project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project (e.g. `audiovideo-task`)
3. Enable **Cloud Firestore** (start in test mode for development)

### 2. Add Android app

1. Register app with your Android package name (check `android/app/build.gradle.kts` for `applicationId`)
2. Download `google-services.json`
3. Place it at `android/app/google-services.json`
4. Add the Google Services plugin to `android/build.gradle.kts` and `android/app/build.gradle.kts` (follow Firebase setup wizard)

### 3. Initialize in Flutter

Uncomment and wire `lib/config/firebase_config.dart`, then call it in `lib/main.dart` before `setupLocator()`:

```dart
import 'config/firebase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeFirebase();
  await setupLocator();
  runApp(const MyApp());
}
```

### 4. Firestore collections

**`users`** — presence

| Field | Type | Notes |
|-------|------|-------|
| `name` | string | Display name entered by user |
| `isOnline` | bool | `true` while app is in foreground |
| `lastSeen` | timestamp | Updated on disconnect |
| `deviceId` | string | Unique per install (UUID) |

Document ID = `deviceId`.

**`calls/{callId}`** — signalling

| Field | Type | Notes |
|-------|------|-------|
| `callerId` | string | `deviceId` of caller |
| `calleeId` | string | `deviceId` of callee |
| `offer` | map | `{ sdp, type }` from `createOffer()` |
| `answer` | map | `{ sdp, type }` from `createAnswer()` |
| `status` | string | `ringing`, `connecting`, `connected`, `ended`, `declined` |
| `createdAt` | timestamp | Call start time |

**`calls/{callId}/ice`** — ICE trickle

| Field | Type | Notes |
|-------|------|-------|
| `candidate` | string | ICE candidate string |
| `sdpMid` | string | Media stream ID |
| `sdpMLineIndex` | int | Line index |
| `fromUserId` | string | Who sent this candidate |

**`calls/{callId}/messages`** — chat fallback (optional)

| Field | Type | Notes |
|-------|------|-------|
| `senderId` | string | `deviceId` |
| `text` | string | Message body |
| `timestamp` | timestamp | Server timestamp |

Prefer WebRTC data channel for chat. Use this collection only as a fallback (see trade-off note below).

### 5. Dev security rules

Use permissive rules during development. **Do not ship these to production.**

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

For production, restrict writes so users can only update their own `users` doc and only read/write `calls` where they are `callerId` or `calleeId`.

### 6. Presence reconnection

When a user opens the app:

1. Write `users/{deviceId}` with `isOnline: true`
2. Set `lastSeen` to `FieldValue.serverTimestamp()`

When the app goes to background or closes:

1. Set `isOnline: false` and update `lastSeen`

On Firestore listener error or network drop:

1. Show a "Reconnecting…" banner in the lobby
2. Retry the snapshot listener with exponential backoff (1s, 2s, 4s, max 30s)
3. Re-write presence doc once reconnected

A simple heartbeat (update `lastSeen` every 30s while online) helps detect stale entries if `onDisconnect` is not available on mobile.

### 7. Chat transport trade-off

| Approach | Pros | Cons |
|----------|------|------|
| WebRTC data channel (preferred) | Low latency, no extra Firestore writes | Lost if connection drops before reconnect |
| Firestore subcollection (fallback) | Persists messages, works without P2P | Higher latency, more reads/writes, costs scale |

Implement data channel first. Add Firestore fallback only if data channel proves unreliable in testing.

---

## Implementation Phases

Work through these in order. Each phase has a clear done-when criterion.

### Phase 1 — Identity + presence lobby

**Goal:** User enters a name and sees a live list of online users.

| Task | File | Status |
|------|------|--------|
| Name entry screen | `lib/ui/screens/name_entry/name_entry_screen.dart` | Scaffolded |
| Save name + deviceId locally | `lib/utils/local_storage.dart` | Scaffolded (in-memory) |
| Wire name entry as first screen | `lib/main.dart` | Done |
| Presence service (write + listen) | `lib/data/services/presence_service.dart` | Stub — wire Firestore |
| Presence repository | `lib/data/repositories/presence_repository.dart` | Done |
| Presence cubit + state | `lib/ui/screens/lobby/view_model/presence_cubit.dart` | Scaffolded |
| Lobby UI | `lib/ui/screens/lobby/lobby_screen.dart` | Scaffolded |
| Register services in DI | `lib/config/common_di.dart` | Done |

**Your work in this phase**

1. Add `firebase_core` + `cloud_firestore` to `pubspec.yaml`
2. Add `google-services.json` and uncomment Firebase init in `main.dart` / `firebase_config.dart`
3. Implement `PresenceService.watchUsers()`, `setOnline()`, `setOffline()` against the `users` collection
4. Optionally swap `LocalStorage` to `shared_preferences` for persistence across restarts

**Lobby UI basics**

- List of users with name, online dot (green/grey), last seen for offline users
- Tap an online user to start a call (wired in Phase 2)
- Exclude self from the list

**Done when:** Two clients on the same Firebase project see each other appear and disappear within ~2 seconds.

---

### Phase 2 — WebRTC audio calling

**Goal:** Two users complete a full audio call with visible lifecycle states.

| Task | File | Status |
|------|------|--------|
| WebRTC service | `lib/data/services/webrtc_service.dart` | Stub |
| Firestore signalling service | `lib/data/services/firestore_signalling_service.dart` | Stub |
| Call models | `lib/data/models/call_state_model.dart`, `signalling_message_model.dart` | Done |
| Call cubit | `lib/ui/screens/call/view_model/call_cubit.dart` | Scaffolded |
| Pre-join screen | `lib/ui/screens/pre_join/pre_join_screen.dart` | Scaffolded |
| In-call screen | `lib/ui/screens/call/call_screen.dart` | Scaffolded |
| Android permissions | `android/app/src/main/AndroidManifest.xml` | Not added yet |

**Android permissions to add**

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
<uses-permission android:name="android.permission.CAMERA"/>  <!-- only if video enabled -->
```

**WebRTC service responsibilities**

- Create `RTCPeerConnection` with ICE servers
- Add local audio track from `getUserMedia({ audio: true, video: false })`
- Handle `onIceCandidate` → write to Firestore
- Listen for remote ICE → `addCandidate()`
- Expose: `createOffer()`, `createAnswer()`, `setRemoteDescription()`, `hangUp()`

**STUN config**

```dart
final iceServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
  ],
};
```

**Call flow**

1. Caller taps user in lobby → navigate to pre-join → create call doc with offer
2. Callee's listener picks up ringing call → show incoming call UI
3. Callee accepts → write answer → both sides exchange ICE
4. `onConnectionState` reaches `connected` → show in-call screen
5. Either side taps end → update status to `ended`, dispose peer connection

**Done when:** Ringing → connecting → connected → ended works on two devices. Each state is visible. Audio is audible both ways.

---

### Phase 3 — In-call chat + reconnection

**Goal:** Text messages during a call. Graceful recovery when Firestore drops.

| Task | File | Status |
|------|------|--------|
| Chat cubit | `lib/ui/screens/call/view_model/chat_cubit.dart` | Scaffolded |
| Chat panel UI | `lib/ui/screens/call/call_screen.dart` | Scaffolded |
| Data channel | `lib/data/services/webrtc_service.dart` | Not implemented |
| Chat repository | `lib/data/repositories/chat_repository.dart` | Stub |
| Reconnection banner | `lib/ui/screens/lobby/lobby_screen.dart` | UI ready, needs Firestore |
| Edge case messages | Pre-join + call screens | Partial |

**Edge cases to handle visibly**

| Situation | UI response |
|-----------|-------------|
| Mic permission denied | Block pre-join; show "Microphone access required" + open settings hint |
| Mic permanently denied | Same as above with "Open Settings" button via `permission_handler` |
| Callee offline | Snackbar: "User is offline" |
| Call declined | Show "Call declined" on caller side, return to lobby |
| Network drop mid-call | Show "Connection lost" → attempt ICE restart or end call |
| Call timeout (no answer in 30s) | Auto-end with "No answer" message |

**Done when:** Messages appear on both sides within 1 second. Firestore reconnect restores presence without app restart.

---

### Phase 4 — UI polish

Keep the UI simple. It should look like a working tool, not a marketing page.

**Theme changes** (`lib/ui/core/themes/app_theme.dart`)

- Replace `Colors.deepPurple` seed with a muted teal or blue (`Color(0xFF2D6A7E)`)
- Background: `#F5F5F5` (light), `#121212` (dark)
- Cards: white / `#1E1E1E` with a 1px border, no drop shadows

**Screen layouts**

| Screen | Layout |
|--------|--------|
| Name entry | Centered text field, single "Continue" button |
| Lobby | `ListView` of rows: circle avatar (initials), name, status dot |
| Pre-join | Mic toggle icon (large), short permission note, "Join call" button |
| In-call | Peer name + timer at top; control bar at bottom (mute, speaker, end) |
| Chat | Simple `ListView` of bubbles, text input + send icon at bottom |

**In-call controls (required)**

- Mute / unmute microphone
- Speaker on / off
- End call (red button)

Add camera flip only if video is implemented.

**What to avoid**

- Gradients, glassmorphism, hero images
- Custom fonts (use system default)
- Long explanatory paragraphs on every screen
- Animations beyond a simple fade or slide

**Done when:** All screens are consistent, readable, and handle the edge cases from Phase 3 without crashing.

---

### Phase 5 — Unit tests

Add at least 2–3 tests under `test/`. These test logic, not widgets.

**1. `test/call_cubit_test.dart`**

Test state transitions without real WebRTC:

```dart
// idle → ringing when startCall()
// ringing → connected when onConnected()
// connected → ended when hangUp()
// ringing → declined when onDeclined()
```

Use `bloc_test` package or manual `expect` on emitted states.

**2. `test/signalling_message_parser_test.dart`**

Test parsing Firestore maps into typed models:

```dart
// parse offer map → SignallingMessage with type 'offer'
// parse ICE candidate map → IceCandidate model
// handle missing fields gracefully
```

**3. `test/presence_cubit_test.dart`**

Mock `PresenceRepository` stream:

```dart
// emit list of users → cubit state updates
// user goes offline → list removes them
// empty stream → empty state, no crash
```

Run tests:

```bash
flutter test
```

**Done when:** All 3 test files pass. `flutter test` reports green.

---

## UI Guidelines

These rules keep the app looking clean and intentional.

- **Spacing:** 8dp grid. Standard horizontal padding: 16dp.
- **Typography:** Default Material text styles. Title = 18sp medium. Body = 14sp regular. Caption = 12sp grey.
- **Colors:** One accent color. Grey for secondary text (`#757575`). Green dot for online, grey for offline.
- **Icons:** Material icons only (`Icons.mic`, `Icons.call_end`, etc.).
- **Copy:** Short labels. "Online", "Ringing…", "Call ended", "Reconnecting…".
- **Lists:** Flat rows, no card-per-item with heavy elevation.
- **Buttons:** Filled for primary action, outlined for secondary. One primary button per screen.
- **Dark mode:** Supported via existing `AppTheme.darkTheme`. Test both.

---

## How to Run

```bash
# 1. Install dependencies
cd sourcecode
flutter pub get

# 2. Add Firebase config
#    Place google-services.json in android/app/

# 3. List available devices
flutter devices

# 4. Run on client A
flutter run -d <device-id-a>

# 5. Run on client B (separate terminal)
flutter run -d <device-id-b>
```

Both clients must use the same Firebase project. Enter different display names on each.

### Two-client test checklist

- [ ] User A and B appear in each other's lobby
- [ ] A calls B → B sees incoming call → B accepts → audio works both ways
- [ ] Mute, speaker, and end call buttons work
- [ ] Text message sent during call appears on the other side
- [ ] B closes app → A's lobby shows B as offline
- [ ] B declines call → A sees "Call declined"
- [ ] Revoke mic permission → pre-join shows a clear error with settings hint
- [ ] Toggle airplane mode briefly → app shows reconnecting, then recovers

---

## Task Checklist

Maps directly to the technical task requirements. Tick off as you complete each item.

### Real-time calling (35%)

- [ ] 1-to-1 audio call between two clients
- [ ] SDP offer/answer exchange over Firestore
- [ ] ICE candidate trickling over Firestore
- [ ] Call lifecycle: ringing → connecting → connected → ended
- [ ] Declined and failed states handled
- [ ] Google STUN server configured
- [ ] Video calling (stretch goal)

### Presence + chat (20%)

- [ ] Lobby with live online/offline status
- [ ] Status updates when user connects or disconnects
- [ ] In-call text chat (WebRTC data channel)
- [ ] Firestore reconnection on network drop

### Architecture + tests (20%)

- [ ] Layered structure: presentation / domain / data
- [ ] BLoC used consistently
- [ ] WebRTC and Firestore logic outside widgets
- [ ] At least 2–3 meaningful unit tests

### UI/UX (15%)

- [ ] Pre-join screen with mic toggle
- [ ] Permission request with denied / permanently-denied handling
- [ ] In-call controls: mute, speaker, end call
- [ ] Edge cases surfaced visibly (offline, declined, network drop)

### Code quality + docs (10%)

- [ ] This README kept up to date
- [ ] Honest notes on what is complete vs partial
- [ ] Known issues documented

### Native bridge bonus (+10%)

- [ ] Not started / in progress / done (see below)

---

## Production Notes

These are not required for the task but expected in the README.

### Adding TURN

STUN alone fails when both peers are behind symmetric NAT. For production:

```dart
{'urls': 'turn:your-turn-server.com:3478', 'username': 'user', 'credential': 'pass'}
```

Options: [Twilio TURN](https://www.twilio.com/docs/stun-turn), [Coturn](https://github.com/coturn/coturn) (self-hosted), or cloud provider TURN services.

### Scaling signalling

Firestore works for a demo and low-traffic apps. At scale, move signalling to a dedicated WebSocket or Socket.IO server. Firestore billing grows with document writes — ICE trickle generates many writes per call.

### Security

- Replace dev Firestore rules with participant-scoped rules
- Validate that only `callerId` or `calleeId` can read/write a call doc
- Do not store credentials in the app binary
- Use Firebase App Check in production

### Tested on

| Platform | Device | Status |
|----------|--------|--------|
| Android | Emulator API 34 | _fill in after testing_ |
| Android | Physical device | _fill in after testing_ |
| iOS | — | Not tested (optional) |

---

## Optional Bonus — Native Bridge

Only attempt this after the core call flow is stable. Worth +10% if working, partial credit for an honest attempt.

**Recommended:** Native audio-level meter via platform channel.

| Layer | File |
|-------|------|
| Dart service | `lib/data/services/audio_meter_service.dart` |
| Android (Kotlin) | `android/app/src/main/kotlin/.../MainActivity.kt` |
| iOS (Swift) | `ios/Runner/AppDelegate.swift` (if building for iOS) |

**How it works**

1. Platform side reads mic amplitude (e.g. `AudioRecord` on Android)
2. Expose via `MethodChannel` or `EventChannel` as a stream of float values 0.0–1.0
3. Flutter widget shows a simple bar or circle that reacts to the level during a call

**Build notes**

- Android: add `RECORD_AUDIO` permission (already needed for calls)
- iOS: add `NSMicrophoneUsageDescription` to `Info.plist`
- Document any build steps or known platform quirks in this section

If time runs out, write what you attempted and what blocked you. That scores better than silence.

---

## Project Status

| Feature | Status |
|---------|--------|
| Folder structure + layered architecture | Done |
| BLoC + GetIt DI | Done |
| Name entry screen | Scaffolded |
| Lobby screen + PresenceCubit | Scaffolded (no Firestore yet) |
| Pre-join + call screens | Scaffolded |
| Chat UI + ChatCubit | Scaffolded |
| Firebase / Firestore presence | Not started |
| WebRTC audio calling | Not started |
| In-call data channel chat | Not started |
| Permission handling | Not started |
| Unit tests (logic) | Not started |
| Video calling | Not started |
| Native bridge bonus | Not started |

Update this table as you complete each phase.

---

## AI Tool Usage

_Fill this in before submission._

Briefly note what you used AI assistants for (e.g. README structure, WebRTC boilerplate) and what you wrote or debugged yourself. Using AI is fine — explain your judgement.

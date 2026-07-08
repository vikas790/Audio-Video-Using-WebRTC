# Audio Video Task

This project is a Flutter-based real-time communication app with:
- live user presence,
- 1-to-1 audio calling using WebRTC,
- in-call text chat,
- and call lifecycle handling (ringing, connecting, connected, ended, declined, failed).

## How to Run the App

### Prerequisites
- Flutter SDK (Dart `^3.9.2`)
- Android Studio
- Firebase project with Firestore enabled

### Setup
```bash
flutter pub get
```

Ensure Firebase files are present:
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist` (if iOS build is needed later)

### Run
```bash
# Check connected/emulated devices
flutter devices

# Run app
flutter run -d <device-id>
```

For call testing, run two app instances on two Android emulators using the same Firebase project.

## How to Run the Server/Backend

This submission does not use a separate custom server process.

Backend/signaling is handled by Firebase Firestore (managed service), so there is no local Node/Go/Python server to start.

## Tested On

- Android Emulator (primary)
- iOS not included in current test scope

## Architecture Decisions

- **Layered structure:** Code is organized into `ui`, `data`, `config`, and `utils` layers for clear responsibilities.
- **State management:** `flutter_bloc` (Cubit) is used for feature-level state (`PresenceCubit`, `CallCubit`, `ChatCubit`).
- **Dependency injection:** `get_it` is used to register services and repositories, keeping screens lightweight.
- **Real-time signaling:** Firestore is used for presence and signaling document exchange.
- **Media transport:** WebRTC handles peer-to-peer media; Firestore carries metadata/signaling only.
- **Separation of concerns:** Networking and WebRTC logic are kept in services/repositories, not inside widgets.

## Project Status (Complete vs Partial)

### Complete
- Project structure with layered organization
- AppLifecycle Handle
- BLoC + DI scaffolding
- Firebase, Firestore, WebRTC, and permission packages integrated
- Main app screens and feature flow scaffolding

### Partial / In Progress
- End-to-end stability hardening for all call edge cases
- Expanded unit tests beyond baseline starter tests
- Full production-ready signaling and error-recovery coverage
- iOS validation and cross-device validation matrix



## Production Readiness Plan (TURN, Scaling, Security)

### TURN Strategy
- Add TURN servers (for example Coturn or managed TURN provider) in addition to STUN.
- Use credential rotation and environment-based configuration for TURN secrets.

### Scaling Strategy
- Keep Firestore for early-stage signaling, then move high-frequency signaling to a dedicated realtime service when concurrency grows.
- Reduce write-amplification for ICE and presence updates using batching/throttling strategies.
- Add observability metrics for connection setup time, call success rate, and reconnect rate.

### Security Strategy
- Replace open dev rules with strict participant-scoped Firestore rules.
- Enforce access controls so only call participants can read/write signaling docs.
- Add App Check and environment-based secret management.
- Add audit logging and abuse/rate-limit protections for signaling endpoints.

## Project Links

- Here is Video Demo: [Watch demo](https://drive.google.com/file/d/1-0kXkGAkHsc0vfkwYAkMOYiPO0OsbiAm/view?usp=sharing)
- Here is APK build: [Download APK](https://drive.google.com/file/d/1-0kXkGAkHsc0vfkwYAkMOYiPO0OsbiAm/view?usp=sharing)
- Here is the GitHub repo: [Audio-Video-Using-WebRTC](https://github.com/vikas790/Audio-Video-Using-WebRTC)






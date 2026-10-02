# Live Screen Mirroring & Gesture Sync

A Flutter app for mirroring a live screen from Device A to Device B using WebSocket or Firebase Cloud Firestore, with a museum dashboard and interactive map experience.

## Features

- Device A broadcaster mode
- Device B receiver mode
- WebSocket local IP transport
- Firebase Cloud Firestore transport
- Dashboard with live status, controls, highlights, and drawing pad
- Museum map navigation and POI details
- QR code sharing for connection setup

## Project Structure

- `lib/main.dart` — app bootstrap
- `lib/screens/` — role selection, Device A, Device B
- `lib/services/` — Firebase and networking logic
- `lib/widgets/` — reusable UI components
- `lib/models/` — protocols and museum data
- `test/` — widget tests
- `integration_test/` — app flow integration tests

## Prerequisites

Before running the app, install:

- Flutter SDK
- Dart SDK
- Android Studio or Xcode (for device emulators/simulators)
- VS Code or Android Studio with Flutter plugin

Verify installation:

```bash
flutter --version
flutter doctor
```

## Setup

From the project root:

```bash
flutter pub get
```

If Firebase configuration is missing or needs to be regenerated:

```bash
flutterfire configure
```

## Run the app

### Android / iOS / desktop

```bash
flutter run
```

### Specific device

```bash
flutter devices
flutter run -d <device-id>
```

### Web

```bash
flutter run -d chrome
```

## Testing

### Analyze code

```bash
flutter analyze
```

### Run widget tests

```bash
flutter test
```

### Run a specific widget test file

```bash
flutter test test/widget_test.dart
```

### Run integration tests

```bash
flutter test integration_test/app_test.dart
```

### Run integration tests with expanded output

```bash
flutter test integration_test/app_test.dart -r expanded
```

## Typical app flow

1. Launch the app.
2. Choose the role: Device A or Device B.
3. Select the connection mode:
   - WebSocket (IP)
   - Firebase (Cloud)
4. For Device A, start the broadcaster and share the QR code or IP/channel.
5. For Device B, connect using the received address or channel ID.
6. Use the dashboard or museum map to monitor the stream.

## Notes

- For local WebSocket mode, Device A should run on a local network-capable device.
- For Firebase mode, Firebase must already be configured for the project.
- The app is designed for demonstration and live mirroring workflows in a real device environment.

## Useful commands

```bash
flutter clean
flutter pub get
flutter test
flutter analyze
```

## License

This project is for local development and demonstration use.



# Implementation Plan: Live Screen Mirroring & Gesture Detection App (Device A to Device B)

Build a cross-platform Flutter application enabling **Device A** (Mobile) to broadcast its screen stream, live touch gestures (taps, holds, drags), and scroll events to **Device B** (Mobile or Windows Desktop) in real-time over Local Wi-Fi / LAN using high-performance WebSockets.

---

## User Review Required

> [!IMPORTANT]
> - **Local Wi-Fi Network**: Both Device A and Device B must be connected to the same local network (Wi-Fi or LAN) for zero-latency direct WebSocket streaming without third-party cloud servers.
> - **Platform Compatibility**: Fully supports Android Mobile, iOS Mobile, and Windows Desktop. Device A acts as the WebSocket Host/Sender, and Device B acts as the Receiver/Viewer.

---

## Proposed Architecture & Features

```
+------------------------------------+          Local Wi-Fi (WebSocket ws://)          +------------------------------------+
|       DEVICE A (Broadcaster)       | ----------------------------------------------> |         DEVICE B (Receiver)        |
|  - RepaintBoundary Frame Capturer  |   1. Screen Frame Buffer (JPEG Bytes Stream)    |  - Real-time Frame Decoder Canvas  |
|  - Pointer Listener (Tap/Scroll)   |   2. Gesture Data (Tap, Drag, Scroll Delta)     |  - Animated Gesture Trail Overlay  |
|  - Local WebSocket Server (8080)   |                                                |  - Latency & FPS Dashboard         |
|  - Interactive Showcase Demo App   |                                                |  - Aspect Ratio Fitting Modes      |
+------------------------------------+                                                +------------------------------------+
```

### Key Components

1. **Networking & Protocol Layer (`lib/services/network_service.dart`, `lib/models/mirror_protocol.dart`)**:
   - Local WebSocket Server hosted directly on Device A using native `dart:io` `HttpServer`.
   - Automatic local IPv4 detection across network interfaces with QR Code & IP pairing address.
   - Dual stream serializer:
     - **Frame Packets**: Binary JPEG screen buffers with timestamp and aspect ratio.
     - **Gesture Packets**: Normalized touch coordinates $(x, y \in [0, 1])$, pointer event types (`down`, `move`, `up`, `scroll`), pointer IDs, and scroll delta vectors $(dx, dy)$.

2. **Gesture Detection & Frame Capture Engine (`lib/services/gesture_tracker.dart`, `lib/services/frame_streamer.dart`)**:
   - `Listener` widget capturing raw pointer down, drag/move, release, and mouse/touch scroll events on Device A.
   - `RepaintBoundary` rendering pipeline to capture frame buffers at configurable target frame rates (15 - 60 FPS).
   - Aspect ratio normalization to ensure accurate pointer alignment across different screen aspect ratios (e.g. 19.5:9 phone screen rendered on 16:9 Windows monitor).

3. **Interactive Showcase App on Device A (`lib/widgets/interactive_showcase.dart`)**:
   - Built-in interactive test suite inside Device A featuring scrollable news feeds, image galleries, drawing canvas, interactive buttons, slider controls, and tap counters so the user can immediately test live scrolling and multi-touch interactions.

4. **Device B Receiver & Real-Time Viewer (`lib/screens/device_b_screen.dart`, `lib/widgets/gesture_overlay_painter.dart`)**:
   - Adaptive view canvas with resolution scaling (Fit, Fill, Stretch, Center).
   - **Gesture Overlay Renderer**: Custom painter rendering glowing touch points, animated ripple rings on tap, dynamic drag trailing paths, and directional scroll animation vectors.
   - **Telemetry Dashboard**: Displays live FPS, latency (ms), received frame resolution, bitrate, active touch pointer count, and recent gesture logs.
   - **Snapshot & Recording**: Quick button to capture high-res frame snapshots on Device B.

---

## Proposed Changes

### Configuration & Dependencies
#### [MODIFY] [pubspec.yaml](file:///d:/flutterProjets/rndscreeningap/pubspec.yaml)
- Add dependencies for QR code generation (`qr_flutter`) and icons/utilities if required.

### Core Application & UI
#### [NEW] [lib/models/mirror_protocol.dart](file:///d:/flutterProjets/rndscreeningap/lib/models/mirror_protocol.dart)
- Data structures for `FramePacket`, `GesturePacket`, and `PointerActionType`.

#### [NEW] [lib/services/network_service.dart](file:///d:/flutterProjets/rndscreeningap/lib/services/network_service.dart)
- `WebSocketServerService`: Listens for connections on port 8080, broadcasts stream.
- `WebSocketClientService`: Connects Device B to Device A IP address with auto-reconnect.
- `IPHelper`: Discovers device local IPv4 address.

#### [NEW] [lib/services/frame_streamer.dart](file:///d:/flutterProjets/rndscreeningap/lib/services/frame_streamer.dart)
- `FrameStreamerController`: Manages `RepaintBoundary` screenshot generation and JPEG stream pipeline.

#### [NEW] [lib/services/gesture_tracker.dart](file:///d:/flutterProjets/rndscreeningap/lib/services/gesture_tracker.dart)
- Intercepts pointer events (`down`, `move`, `up`, `cancel`, `scroll`) and normalizes coordinates.

#### [NEW] [lib/theme/app_theme.dart](file:///d:/flutterProjets/rndscreeningap/lib/theme/app_theme.dart)
- Futuristic dark theme palette, glassmorphic cards, custom button styles.

#### [NEW] [lib/widgets/gesture_overlay_painter.dart](file:///d:/flutterProjets/rndscreeningap/lib/widgets/gesture_overlay_painter.dart)
- Renders glowing pointer spots, tap ripple animations, drag trails, and scroll vectors on Device B.

#### [NEW] [lib/widgets/interactive_showcase.dart](file:///d:/flutterProjets/rndscreeningap/lib/widgets/interactive_showcase.dart)
- Interactive test application for Device A (Feed, Gallery, Canvas, Controls).

#### [NEW] [lib/screens/role_selection_screen.dart](file:///d:/flutterProjets/rndscreeningap/lib/screens/role_selection_screen.dart)
- Main launch screen to choose **Device A (Broadcaster)** or **Device B (Receiver)**.

#### [NEW] [lib/screens/device_a_screen.dart](file:///d:/flutterProjets/rndscreeningap/lib/screens/device_a_screen.dart)
- Broadcaster view displaying live server IP, connection code, connected clients list, stream statistics, and embedded showcase UI.

#### [NEW] [lib/screens/device_b_screen.dart](file:///d:/flutterProjets/rndscreeningap/lib/screens/device_b_screen.dart)
- Receiver view with IP connection panel, live mirrored screen viewer, real-time gesture overlay layer, and telemetry toolbar.

#### [MODIFY] [lib/main.dart](file:///d:/flutterProjets/rndscreeningap/lib/main.dart)
- App entry point initialized with dark theme and `RoleSelectionScreen`.

---

## Verification Plan

### Automated Build & Static Analysis
- Run `flutter analyze` to ensure zero Dart lint errors or type warnings.
- Build project for Windows (`flutter build windows` or `flutter run -d windows`) to ensure Windows receiver functionality.

### Manual Verification Scenarios
1. **Device A Setup & Server Hosting**:
   - Launch app on Device A -> Select "Device A (Broadcaster)".
   - Verify local IPv4 address (e.g. `192.168.1.50:8080`) is detected and displayed cleanly.
2. **Device B Pairing**:
   - Launch app on Device B (Mobile or Windows) -> Select "Device B (Receiver)".
   - Input Device A IP address and click "Connect".
   - Confirm connection handshakes immediately and client status updates on Device A.
3. **Live Tap & Scroll Mirroring Verification**:
   - Perform tap gestures on Device A -> Verify real-time tap ripple animation appears at exact relative coordinates on Device B.
   - Perform scroll gestures (up, down, fling) on Device A -> Verify screen scroll content updates smoothly on Device B with scroll directional vectors.
   - Perform drag/draw actions on Device A -> Verify trailing gesture paths render on Device B.
4. **Telemetry & Viewport Controls**:
   - Verify FPS, latency (ms), and active pointers display correctly on Device B toolbar.
   - Toggle screen fit modes (Fit / Fill / Stretch) and gesture overlay visibility.

# BcgCam 📷

**BcgCam** is a native-powered background video recording application built with **Flutter**, **Dart**, and **Android Kotlin**. It enables reliable video recording for user-selected durations even when the application is minimized or the device screen is turned off.

Developed by **Lajeesh**.

---

## ✨ Features

- **True Background & Screen-Off Recording**:
  - Leverages Android Foreground Service (`camera` & `microphone` service types).
  - Holds a partial wake lock to keep video encoding alive when the display is locked or turned off.
  - Displays a persistent ongoing notification with live elapsed time, remaining countdown, and a one-tap **Stop Recording** action.
- **Material 3 Interface**:
  - Clean, intuitive interface with dark & light theme support.
  - Camera Selection: Seamlessly toggle between **Rear Camera** and **Front Camera**.
  - Recording Duration: Presets (1m, 5m, 10m, 15m, 30m) or Custom duration with validation.
  - Video Quality: Choose between 480p SD, 720p HD, and 1080p Full HD (auto-adapts to camera hardware capabilities).
  - Audio Toggle: Option to record with or without microphone audio.
  - Storage space indicators and warnings when storage is low (< 500 MB).
- **Recordings Gallery**:
  - Visual gallery of all saved recordings with auto-generated video thumbnails.
  - Shows file size, duration, resolution, and timestamp.
  - Fullscreen In-App Video Player with playback controls and scrubbing.
  - Native Android share-sheet integration (`share_plus`).
  - Delete recordings with confirmation.
- **Scoped Storage & MediaStore**:
  - Videos are indexed and synced to the device's public `Movies/BcgCam` folder, making them instantly visible in Google Photos, Samsung Gallery, and file managers.
- **Privacy & Android Compliance**:
  - Full compliance with Android 14 (API 34) and Android 15 foreground service policies.
  - Transparent ongoing notifications and respects OS privacy indicators.

---

## 🛠️ Architecture

```
Flutter Application (UI & State)
       │
       ▼ MethodChannel ("com.example.bcgcam/recorder")
MainActivity.kt
       │
       ▼ ContextCompat.startForegroundService()
BackgroundRecordingService.kt  (Foreground Service)
 ├── Type: camera | microphone (Android 14 API 34 compliant)
 ├── Partial WakeLock (keeps CPU active when display is turned off)
 ├── Persistent Ongoing Notification (Live timer + Stop Recording PendingIntent action)
 └── CameraRecorderEngine.kt (Android Camera2 API + MediaRecorder + Offscreen Surface)
       │
       ▼ Finalization on stop / duration expiry
MediaFileManager.kt
 ├── Direct POSIX recording to external app Movies/BcgCam directory
 ├── MediaStore sync to public Movies/BcgCam (Scoped Storage compliant)
 └── MediaMetadataRetriever (auto-generates cached JPEG thumbnails)
```

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.24+ recommended)
- Android SDK with Platform 34+
- Java JDK 17 or 21

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/lajeesh1/BcgCam.git
   cd BcgCam
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run on connected Android device:
   ```bash
   flutter run
   ```

---

## 📦 Building Releases

### Split-per-ABI APK (Recommended for smallest size ~19 MB):
```bash
flutter build apk --release --split-per-abi
```
Output: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

### Universal APK (Works on any Android phone):
```bash
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

### Android App Bundle (For Google Play Store ~12-15 MB download):
```bash
flutter build appbundle --release
```
Output: `build/app/outputs/bundle/release/app-release.aab`

---

## 🔋 Battery Optimization Note

Some Android device manufacturers (e.g., Samsung, Xiaomi, Oppo) enforce aggressive battery savers that terminate long background processes.
To ensure uninterrupted background recording for sessions longer than 5 minutes:
- Go to **Settings** in BcgCam -> **Open Battery Optimization Settings** -> select **Unrestricted**.

---

## 👤 Author

**Lajeesh**  
- GitHub: [@lajeesh1](https://github.com/lajeesh1)

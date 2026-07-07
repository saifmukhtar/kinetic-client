<div align="center">
  <img src="https://raw.githubusercontent.com/saifmukhtar/kinetic/main/kinetic-logo.svg" width="120" height="120" alt="Kinetic Logo">
  <h1>Kinetic Client Ecosystem</h1>
  <p><strong>The official mobile, browser, and desktop clients for the Kinetic Decentralized Network.</strong></p>
</div>

---

This repository houses all user-facing clients for the Kinetic Network. By utilizing **Flutter** for UI and **Rust FFI** for cryptographic heavy lifting, the client apps provide a unified, extremely performant experience across all major platforms.

## 📦 Repository Structure

- **`mobile/`**: The primary Flutter application. Compiles to native iOS and Android apps, allowing users to register `.kin` domains, manage their wallet, and interact with the network natively.
- **`kinetic-ffi/`**: The Rust core for the clients. It bridges the native `kinetic-daemon` and `kinetic-core` logic to Flutter and WebAssembly using `flutter_rust_bridge`.
- **`extension/`**: (WIP) The browser extension for Chrome/Firefox to natively intercept and resolve `.kin` domains right in the browser URL bar.

---

## 📱 Mobile Client (`mobile/`)

The mobile client brings decentralized DNS to your smartphone. It runs a Light Client version of the Kinetic protocol in the background via Rust FFI.

### Architecture
- **Framework:** Flutter (Dart)
- **Native Bridge:** `flutter_rust_bridge` automatically generates Dart bindings for our `kinetic-ffi` Rust library.
- **Supported Platforms:** 
  - Android (API 21+)
  - iOS (12.0+)

### 🚀 Building from Source

To build the mobile app, you must have [Flutter](https://flutter.dev/docs/get-started/install) and [Rust](https://rustup.rs/) installed.

1. **Install rust bridge generator:**
   ```bash
   cargo install flutter_rust_bridge_codegen
   ```
2. **Generate the FFI bindings:**
   ```bash
   cd mobile
   flutter_rust_bridge_codegen generate
   ```
3. **Build the app:**
   ```bash
   flutter pub get
   flutter run # To run on a connected emulator/device
   ```

---

## 🌍 Distribution & Releases

The Kinetic Client is designed to be accessible to everyone, everywhere. We support multiple distribution channels to ensure censorship resistance.

### Android Distribution
1. **Google Play Store:** The official release channel. We utilize Android App Bundles (`.aab`) for optimized delivery.
2. **F-Droid:** We maintain an F-Droid compatible repository for the open-source community.
3. **Direct APK / GitHub Releases:** For users who wish to sideload, every release on GitHub includes a universally signed `.apk`.

*To build the release APK:*
```bash
cd mobile
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### iOS Distribution
1. **Apple App Store:** The official iOS release channel, distributed via App Store Connect.
2. **TestFlight:** Used for beta testing new network features before public release.

*To build the release IPA (Requires macOS & Xcode):*
```bash
cd mobile
flutter build ipa --release
# Distribute the resulting .xcarchive via Xcode Organizer
```

---

## 🛡️ Security & Privacy
The Kinetic clients are purely non-custodial. All private keys and identity materials generated via `kinetic-ffi` remain strictly on the device's secure enclave (iOS Keychain / Android Keystore). The client communicates directly with the Kinetic DHT network without routing through centralized analytics servers.

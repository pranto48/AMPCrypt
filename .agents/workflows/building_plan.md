---
description: AMPCrypt Zero-Trust Development Strategy and Building Plan
---
# Workflow: Build AMPCrypt System

Follow these phases strictly to build the AMPCrypt ecosystem. Do not proceed to the next phase until the current one is tested and approved by the user.

## Phase 1: Web App & Zero-Cost Infrastructure (GitHub + Firebase)
- [ ] Initialize the Flutter cross-platform project using Clean Architecture.
- [ ] Set up Firebase Auth and Firestore (Spark Plan) for Trusted Device Hash management.
- [ ] Implement the AMPCrypt core logic: SLIP39 Master Recovery Phrase generation (Offline).
- [ ] Implement Argon2id password hashing for the first SSS share.
- [ ] Build the AMPCrypt Web UI (Create Vault, Lock/Unlock, Recovery Mode).
- [ ] Setup GitHub Actions CI/CD to auto-build Flutter Web and deploy to `gh-pages`.
- [ ] Provide instructions to the user for setting up the custom CNAME/A record for their subdomain.

## Phase 2: Desktop Integration & Heuristic Anomaly Detection (Windows/macOS)
- [ ] Enable Flutter Desktop support.
- [ ] Integrate local TFLite MobileFaceNet for Face Verification (AMPCrypt Vision Factor).
- [ ] Implement `Directory.watch` to monitor the local file system.
- [ ] Build the Unsupervised Machine Learning (Isolation Forest) background task to detect ransomware behavior (unauthorized edit/delete/move).
- [ ] Test the full AMPCrypt offline vault encryption/decryption on Desktop.

## Phase 3: Mobile Biometrics & Final 4FA Interlocking (Android/iOS)
- [ ] Optimize the AMPCrypt UI for mobile screens.
- [ ] Integrate the `local_auth` package to bind the Hardware Fingerprint factor.
- [ ] Integrate TFLite Conformer-based Speaker Encoder for Voice Verification.
- [ ] Finalize the Shamir's Secret Sharing (SSS) interlocking: The Master Key must only reconstruct when Password, Face, Fingerprint, and Voice shares are simultaneously validated.
- [ ] Configure GitHub Actions to build the release APK/AAB and iOS IPA.

## Phase 4: AMPCrypt Official Landing Page (Cryptomator style)
- [ ] Create a responsive Landing Page UI in Flutter Web and set it as the initial default route (/).
- [ ] Move the actual AMPCrypt Vault application to a separate secure route (e.g., /vault).
- [ ] Design a modern, dark-themed Tailwind-style Hero Section with the title "AMPCrypt: Zero-Trust Data Safety".
- [ ] Add a "Security Features" section explaining 4-Factor Auth (4FA), Shamir's Secret Sharing (SSS), and Ransomware Behavior Detection.
- [ ] Add a "Downloads" section with prominent buttons for Windows (.msix/.exe), macOS, Linux, Android (.apk), and iOS.
- [ ] Ensure SEO metadata, title, and open-graph tags are properly configured in web/index.html.
- [ ] Test responsiveness for mobile and desktop browsers, then commit and push to trigger GitHub Pages CI/CD.

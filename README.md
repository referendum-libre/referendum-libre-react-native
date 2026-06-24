# Referendum Libre

A React Native/Expo application for secure digital voting using passport NFC verification and zero-knowledge proofs.

> **Fork notice.** Referendum Libre is an independent, community-maintained fork of
> [Referendum Citoyen](https://github.com/ReferendumCitoyen/referendum-citoyen-react-native)
> (GPL-3.0). It is **not affiliated with or endorsed by** the original project or its
> publisher. Branding, contact details, and infrastructure (build, signing, proposal
> index) are the fork's own. Like the upstream project, it is licensed under
> [GPL-3.0](./LICENSE).

## Features

- Passport MRZ scanning via camera (TD1 ID cards, TD3 passports)
- NFC passport chip reading with BAC authentication
- Zero-knowledge identity verification via Rarimo protocol
- Multi-step voting flow with video guidance
- Bilingual support (French/English)

## Prerequisites

- **Node.js** 20+
- **Expo** — no global CLI needed; the project uses the local CLI via `npx expo` (Expo SDK 54)
- **iOS**: Xcode 16+, CocoaPods
- **Android**: Android Studio, NDK 27.1.12297006

## Installation

```bash
# Install dependencies (also runs patch-package + the aligned-noir postinstall)
npm install

# Generate native projects (android/ and ios/ are gitignored).
# Use --clean after changing app.config.ts or the config plugins.
npx expo prebuild

# Run on iOS
npx expo run:ios

# Run on Android
npx expo run:android

# Release build (Android, local — no EAS)
ANDROID_HOME=$ANDROID_HOME npx expo run:android --variant release
```

## Project Structure

```
referendum-libre-react-native/
├── app/                    # Expo Router screens
├── components/             # React components
│   ├── voting-modal/       # Voting flow components
│   └── icons/              # SVG icons
├── contexts/               # React context providers
├── hooks/                  # Custom React hooks
├── utils/                  # Utility functions
├── constants/              # Theme and content constants
├── modules/                # Native modules
│   └── e-document/         # NFC passport reading module
├── locales/                # i18n translations
└── assets/                 # Images, fonts, videos
```

## Development

```bash
# Start Expo development server
npm start

# Run linter
npm run lint

# Format code
npm run format

# Run tests
npm test
```

## Documentation

- [Integration Guide](./INTEGRATION_GUIDE.md) - Detailed setup for native modules
- [Versioning & update notice](./docs/versioning.md) - How to bump the app version, and when to raise `min_supported_app_versions` (only after the stores are live — never at the same time as the version bump)
- [Roadmap](./TODO.md) - Development roadmap and tasks

## Technologies

- [Expo](https://expo.dev/) - React Native framework
- [Expo Router](https://docs.expo.dev/router/introduction/) - File-based routing
- [react-native-vision-camera](https://mrousavy.com/react-native-vision-camera/) - Camera and OCR
- [react-native-nfc-manager](https://github.com/revtel/react-native-nfc-manager) - NFC access
- [@rarimo/rarime-rn-sdk](https://github.com/rarimo/rarime-rn-sdk) - Zero-knowledge identity

## Community

Join us on Matrix to discuss development, ask questions, and help shape the project:
[**#referendum-libre:matrix.org**](https://matrix.to/#/#referendum-libre:matrix.org).

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

You can support with donations: 
- XMR: 8AJcjG2wi9M98sAmCnwQp3FtQqeTNns1TM9qatAN149gguYNBorFDwjVgCZtGMCyNHAwM5kvD4sTw4NSr5JEMSEH69HFSYX 
- BTC: bc1qvgu3emmlusemt8q9l8pueg70auny88pgvsg7fp

## License

[GPL-3.0](./LICENSE)

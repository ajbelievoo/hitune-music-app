# HiTune Music

A Flutter music streaming app backed by the BusyOwlFramework.

## Getting Started

### Requirements

- Flutter 3.29.3+ / Dart 3.7.2+
- Android SDK with NDK 26.3.11579264
- JDK 21 (path configured in `android/gradle.properties`)

### Setup

1. Clone or open the project.
2. Copy `.env.example` to `.env` and add the real API sign keys:
   ```bash
   cp .env.example .env
   ```
3. Run the app:
   ```bash
   # macOS/Linux
   ./run.sh

   # Windows
   run.bat
   ```

For VS Code, use the provided `hitune_music` launch configuration.

### Build

```bash
flutter build apk --release
```

### Configuration

App branding, feature flags, and ad unit IDs are loaded from:

- `lib/core/config/app_config.dart` (compile-time constants via `--dart-define`)
- `.env` (loaded by `--dart-define-from-file`)

See `.env.example` for the available environment variables.

### Project structure

- `lib/core/` - API, security, storage, logging, theme, ads
- `lib/features/` - Screens and services (auth, home, player, library, profile, etc.)
- `lib/features/player/` - Audio player, queue, and mini player
- `lib/features/home/` - Home feed and side drawer
- `lib/features/search/` - Search and suggestions

See `AGENTS.md` for development notes.

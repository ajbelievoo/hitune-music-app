# HiTune Music - Agent Notes

## Build & Run

This project uses Flutter 3.29.3 with Dart 3.7.2.

### Environment setup

1. Copy `.env.example` to `.env` and fill in real values:
   - `HITUNE_SIGN_KEY` and `HITUNE_ADMIN_SIGN_KEY` from the admin panel.
   - Optionally override AdMob IDs.
2. Run using the wrapper script or launch configuration:
   - Windows: `run.bat`
   - macOS/Linux: `run.sh`
   - VS Code: use the `hitune_music` launch configuration (already provided in `.vscode/launch.json`).
   - Manual: `flutter run --dart-define-from-file .env`

### Android build

The project uses Gradle 8.14 with the JDK at `C:\jdk21\jdk-21.0.5+11`. This is configured in `android/gradle.properties`.

```bash
flutter build apk --debug --dart-define-from-file .env
```

(The `--dart-define-from-file` flag is required — `AppConfig.signKey` is a
compile-time `String.fromEnvironment`, so an APK built without it has no sign
key and every signed API request fails with "API sign key is not configured".)

### Important file layout

- `lib/core/utils/cover_image_extractor.dart` extracts cover URLs from the
  backend's HTML/picture payloads, upgrades CDN thumbnails to hi-res
  (i.scdn.co 64/300 → 640px token swap, mzstatic `NxNbb` → `600x600bb`) and
  rejects backend `dummy_*`/`/placeholder/` art so cards fall back cleanly.
- `lib/core/ui/cover_image.dart` + `lib/core/utils/artwork_lookup.dart` —
  shared cover widget; when a card has no cover (or it 404s) it resolves
  real artwork via the iTunes Search API (in-memory cached).
- `lib/core/config/app_config.dart` reads sign keys and feature flags from `--dart-define`.
- `lib/core/utils/app_logger.dart` is the central logger. It only emits logs in debug mode.
- `lib/core/network/api_service.dart` no longer logs full headers, cookies, or signatures.
- `.env` is gitignored and must not be committed.

### Feature gating & subscriptions

- `lib/features/subscription/subscription_service.dart` reads `plan_features`
  and the user's plan from `client_config`. Feature keys live in `AppFeatures`.
- `lib/features/subscription/feature_gate.dart` exposes `FeatureGate.require(...)`
  and `FeatureGateWidget` to lock premium features.
- The backend sends `plan_features` (`free`/`premium` lists) live. If it ever
  stops sending them, the service is **fail-open** (all features allowed).
- Backend contract for every new feature lives in `docs/BACKEND_REQUIREMENTS.md`.

### Live API smoke test

`tool/api_smoke.dart` replays the app's request signing against
`https://music.hitune.in/api/` to verify endpoint contracts without the app:

```bash
dart tool/api_smoke.dart
```

Verified live (2026-09): `client_config` (`plan_features`, `user.plan`,
`setting.default_plan`, `setting.iap_enabled`), `radios`, `recommendations`,
`daily_mix`, `recommendations_because`, `track_lyrics` (`{type,lyrics,lrc}`),
`comments` (`{items,has_more,page}`), `muse_request_source` (`loudness`,
premium-gated `download_url`). Auth endpoints return `{"message":"403"}`
for guests. All requests must use `x-bof-platform: web` — any other value
causes a silent empty 200 (`request_extend::insert_log` requires
`x_bof_device_*` headers for non-web platforms).

### Playback pipeline (player_service.dart)

- URL resolution is parallelized: `muse_request_source` fires the requested
  quality AND `audio_quality_2` together; YouTube raaz sources resolve via
  `muse_solve_raaz` (backend proxy) and explode/piped **in parallel**.
- `auto` quality prefers a fast direct URL over a slow hi-res raaz chain.
- `SongCacheService` caches resolved URLs for 8h (googlevideo URLs cap at
  their `expire` param) and `getAnySongUrl()` serves any cached quality for
  instant play.
- `playQueue`/`playTrack` emit `_current` immediately on tap (perceived
  instant play) and are generation-guarded — a newer play call cancels the
  stale one's remaining work.
- Data saving: audio bytes go through `LockCachingAudioSource` (replays
  don't re-download). Video tracks resolve an audio-only stream for
  just_audio plus a separate video rendition list; the video surface in
  `player_screen.dart` starts only when the user picks Video mode
  (`_videoWanted`). `VideoQuality` caps the rendition — `auto` = WiFi up
  to 4K, mobile data 480p; manual tiers override.
- `RecommendationsService` caches its ~300KB payloads in memory for 20 min;
  `BrowseFeedService` caches the home payload for 10 min.
- `next()`/`previous()`/`skipToIndex()` stay responsive while resolving: they
  reroute through `_intendedTracks` (the full tapped list) via `playQueue`.
- `_fillQueueAround` resolves the NEXT sibling first and inserts each track
  into the playlist as it resolves (queue grows live).

### New feature modules

- `lib/features/downloads/` - offline downloads (path_provider + http stream).
- `lib/features/player/queue_sheet.dart`, `sleep_timer_sheet.dart`,
  `sound_controls_sheet.dart`, `lyrics_screen.dart`, `track_actions_sheet.dart`
  - player extras (speed/pitch via just_audio; EQ via `core/audio/audio_enhancer.dart`).
- `lib/features/notifications/` - in-app notification inbox.
- `lib/features/comments/` - comments sheet.
- `lib/features/home/made_for_you_section.dart` - recommendations rail
  (renders only when backend returns items).
- `lib/core/l10n/` - minimal localization (en/hi) via `LocaleService`.
- `lib/core/network/connectivity_service.dart` + `lib/core/ui/offline_banner.dart`
  - offline indicator in `app_shell.dart`.
- `lib/core/cast/cast_service.dart` - casting facade (native Cast SDK pending).
- `lib/features/premium/purchase_service.dart` - IAP facade (store products pending).
- `lib/features/developer/` - public Developer API portal (third-party apps,
  API keys, usage, plans). Menu entry in Profile → Account Settings is hidden
  until `client_config.setting.developer_portal` is true. Full spec:
  `docs/DEVELOPER_API.md`; backend contract: `docs/BACKEND_REQUIREMENTS.md`
  section 15.

### Analysis

```bash
flutter analyze --no-pub
```

## Known remaining issues

- Some `BuildContext` async gaps are not fully guarded yet (`use_build_context_synchronously` warnings).
- Large widgets (`artist_screen.dart`, `home_screen.dart`, `player_service.dart`) should be split into smaller files over time.
- Several UI screens still hardcode colors instead of using `Theme.of(context).colorScheme`.
- Casting (`CastService`) and store IAP (`PurchaseService`) are facades pending native SDK / store-product wiring.
- `withOpacity` deprecation warnings remain in some screens; the most frequently used files have been migrated to `withValues`.

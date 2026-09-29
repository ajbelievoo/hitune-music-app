@echo off
echo Building release APK with .env...
flutter build apk --release --dart-define-from-file .env --no-tree-shake-icons
echo.
echo APK: build\app\outputs\flutter-apk\app-release.apk

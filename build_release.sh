#!/bin/sh
echo "Building release APK with .env..."
flutter build apk --release --dart-define-from-file .env
echo ""
echo "APK: build/app/outputs/flutter-apk/app-release.apk"

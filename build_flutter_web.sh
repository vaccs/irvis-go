#!/bin/bash
set -e

# Build Flutter web app with custom base href
FLUTTER_DIR=~/irvis_flutter
TARGET_DIR="$(pwd)/visual"
BASE_HREF="/irvis/visual"

cd "$FLUTTER_DIR"
flutter build web --base-href "$BASE_HREF/"

# Create target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Copy build output
cp -r build/web/* "$TARGET_DIR/"

echo "Flutter web build copied to $TARGET_DIR"

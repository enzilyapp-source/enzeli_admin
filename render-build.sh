#!/usr/bin/env bash
set -euo pipefail

FLUTTER_DIR="${RENDER_PROJECT_DIR:-$PWD}/.render/flutter"

if [ ! -d "$FLUTTER_DIR" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

flutter config --enable-web
flutter pub get
flutter build web --release \
  --dart-define=API_BASE_URL="${API_BASE_URL:-https://inzeli-api-6heq.onrender.com/api}"

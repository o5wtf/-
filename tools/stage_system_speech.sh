#!/usr/bin/env bash
# Кладёт исходник плагина в kotlin-исходники gradle-проекта, чтобы он попал в APK.
set -euo pipefail
root="${1:-android/build}"
src="addons/system_speech/src/SystemSpeechPlugin.kt"
if [ ! -f "$src" ]; then
  echo "нет $src" >&2
  exit 1
fi
if [ ! -f "$root/build.gradle" ] && [ ! -f "$root/build.gradle.kts" ]; then
  echo "не найден gradle-проект в $root" >&2
  find "$root" -maxdepth 2 -type d | head -40 >&2
  exit 1
fi
dest="$root/src/main/kotlin/com/o5wtf/detective/speech"
mkdir -p "$dest"
cp "$src" "$dest/SystemSpeechPlugin.kt"
echo "system speech -> $dest/SystemSpeechPlugin.kt"

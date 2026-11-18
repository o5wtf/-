#!/usr/bin/env bash
# Кладёт исходник плагина в gradle-проект экспорта, чтобы он собрался в APK.
set -euo pipefail
root="${1:-android/build}"
src="addons/system_speech/src/SystemSpeechPlugin.kt"
if [ ! -f "$src" ]; then
  echo "нет $src" >&2
  exit 1
fi
dest=""
if [ -d "$root/src/main/java" ]; then
  dest="$root/src/main/java/com/o5wtf/detective/speech"
elif [ -d "$root/src/main/kotlin" ]; then
  dest="$root/src/main/kotlin/com/o5wtf/detective/speech"
else
  echo "не найден src/main в $root" >&2
  find "$root" -maxdepth 3 -type d | head -40 >&2
  exit 1
fi
mkdir -p "$dest"
cp "$src" "$dest/SystemSpeechPlugin.kt"
echo "system speech -> $dest/SystemSpeechPlugin.kt"

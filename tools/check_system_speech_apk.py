#!/usr/bin/env python3
"""Проверяет, что APK содержит плагин SpeechRecognizer и queries на RecognitionService."""

import subprocess
import sys
import zipfile
from pathlib import Path


def fail(message: str) -> None:
    print(f"ПРОВЕРКА РЕЧИ: {message}", file=sys.stderr)
    raise SystemExit(1)


def dex_has_plugin(apk: Path) -> bool:
    with zipfile.ZipFile(apk) as archive:
        dexes = [name for name in archive.namelist() if name.endswith(".dex")]
        if not dexes:
            return False
        blob = b"".join(archive.read(name) for name in dexes)
    return b"SystemSpeechPlugin" in blob


def manifest_text(apk: Path) -> str:
    aapt = _aapt()
    if aapt is not None:
        try:
            xml = subprocess.check_output(
                [aapt, "dump", "xmltree", str(apk), "AndroidManifest.xml"],
                stderr=subprocess.STDOUT,
            )
            return xml.decode("utf-8", "replace")
        except subprocess.CalledProcessError as exc:
            raw = _raw_manifest(apk)
            if raw:
                return raw
            detail = exc.output.decode("utf-8", "replace") if exc.output else str(exc)
            fail(f"aapt не прочитал манифест: {detail}")
    return _raw_manifest(apk)


def _raw_manifest(apk: Path) -> str:
    with zipfile.ZipFile(apk) as archive:
        if "AndroidManifest.xml" not in archive.namelist():
            return ""
        raw = archive.read("AndroidManifest.xml")
    if raw.startswith(b"<") or b"RecognitionService" in raw or b"SystemSpeech" in raw:
        return raw.decode("utf-8", "replace")
    utf16 = raw.decode("utf-16le", "replace")
    if "RecognitionService" in utf16 or "SystemSpeech" in utf16:
        return utf16
    return ""


def manifest_ok(text: str) -> tuple[bool, bool, bool]:
    queries = "android.speech.RecognitionService" in text
    plugin = "SystemSpeechPlugin" in text or "org.godotengine.plugin.v2.SystemSpeech" in text
    audio_settings = "android.permission.MODIFY_AUDIO_SETTINGS" in text
    return queries, plugin, audio_settings


def check(apk: Path) -> None:
    if not apk.is_file():
        fail(f"нет файла {apk}")
    if not dex_has_plugin(apk):
        fail("в classes.dex нет com.o5wtf.detective.speech.SystemSpeechPlugin")
    text = manifest_text(apk)
    queries, plugin, audio_settings = manifest_ok(text)
    if not queries:
        fail("в манифесте нет queries на android.speech.RecognitionService")
    if not plugin:
        fail("в манифесте нет meta-data плагина SystemSpeech")
    if not audio_settings:
        fail("в манифесте нет android.permission.MODIFY_AUDIO_SETTINGS")
    print("речь: плагин и RecognitionService есть в APK")


def _aapt() -> str | None:
    import os
    import shutil

    found = shutil.which("aapt")
    if found:
        return found
    home = os.environ.get("ANDROID_HOME", "")
    if not home:
        return None
    matches = sorted(Path(home).glob("build-tools/*/aapt"))
    return str(matches[-1]) if matches else None


def main() -> None:
    if len(sys.argv) != 2:
        fail("укажите путь к apk")
    check(Path(sys.argv[1]))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Проверяет, что в APK/PCK есть дело и нет ключа, dev.cfg, docs и tools."""

import re
import struct
import sys
import zipfile
from pathlib import Path

MAGIC = b"GDPC"
FORBIDDEN_PREFIXES = (
    "res://config/",
    "res://docs/",
    "res://tools/",
    "res://tests/",
    "res://.github/",
)
KEY_RE = re.compile(br"AIza[0-9A-Za-z_\-]{20,}")
FILLED_KEY_RE = re.compile(br"api_key\"\s*[:=]\s*\"[^\"]+\"")


def fail(message: str) -> None:
    print(f"ПРОВЕРКА СБОРКИ: {message}", file=sys.stderr)
    raise SystemExit(1)


def pck_paths(data: bytes) -> list[str]:
    start = data.find(MAGIC)
    if start < 0:
        fail("в пакете нет заголовка PCK")
    pos = start + 4
    version, _major, _minor, _patch = struct.unpack_from("<IIII", data, pos)
    pos += 16
    _flags, = struct.unpack_from("<I", data, pos)
    pos += 4
    pos += 8  # file base
    if version not in (3, 4):
        fail(f"неподдержанная версия PCK: {version}")
    dir_offset, = struct.unpack_from("<Q", data, pos)
    pos = start + dir_offset
    count, = struct.unpack_from("<I", data, pos)
    pos += 4
    if count < 0 or count > 100000:
        fail("каталог PCK не читается")
    paths: list[str] = []
    for _ in range(count):
        length, = struct.unpack_from("<I", data, pos)
        pos += 4
        if length > 4096 or pos + length > len(data):
            fail("путь в PCK повреждён")
        path = data[pos : pos + length].decode("utf-8", "replace")
        pos += length + 8 + 8 + 16 + 4
        paths.append(path.replace("\\", "/"))
    return paths


def pck_bytes(path: Path) -> list[tuple[str, bytes]]:
    raw = path.read_bytes()
    if path.suffix.lower() == ".apk":
        found: list[tuple[str, bytes]] = []
        with zipfile.ZipFile(path) as archive:
            names = [name for name in archive.namelist() if name.endswith(".pck")]
            if not names:
                fail("в APK нет файла .pck")
            for name in names:
                found.append((name, archive.read(name)))
        if b"android.permission.INTERNET" not in raw:
            fail("в APK нет разрешения INTERNET")
        if b"supports-screens" not in raw and "supports-screens".encode("utf-16le") not in raw:
            fail("в манифесте APK нет supports-screens")
        return found
    return [(path.name, raw)]


def check_file(path: Path) -> None:
    for label, blob in pck_bytes(path):
        if KEY_RE.search(blob) or FILLED_KEY_RE.search(blob):
            fail(f"{label}: в пакете найден ключ API")
        paths = pck_paths(blob)
        for packed in paths:
            lowered = packed.lower()
            if any(lowered.startswith(prefix) for prefix in FORBIDDEN_PREFIXES):
                fail(f"в сборку попал запрещённый путь: {packed}")
            if lowered.endswith("dev.cfg") or lowered.endswith(".keystore") or "export_credentials" in lowered:
                fail(f"в сборку попал запрещённый путь: {packed}")
        cases = [packed for packed in paths if "/cases/" in packed and packed.endswith(".json")]
        if not cases:
            fail(f"{label}: в PCK нет json дела")
        print(f"{path.name}: файлов {len(paths)}, дел {len(cases)}")


def main() -> None:
    if len(sys.argv) < 2:
        fail("укажите apk или pck")
    for arg in sys.argv[1:]:
        check_file(Path(arg))


if __name__ == "__main__":
    main()

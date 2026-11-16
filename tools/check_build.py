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
        path = data[pos : pos + length].split(b"\x00", 1)[0].decode("utf-8", "replace")
        pos += length + 8 + 8 + 16 + 4
        paths.append(path.replace("\\", "/"))
    return paths


def forbidden(path: str) -> bool:
    lowered = path.lower().replace("\\", "/")
    if any(lowered.startswith(prefix) or f"/{prefix.removeprefix('res://')}" in lowered for prefix in FORBIDDEN_PREFIXES):
        return True
    return lowered.endswith("dev.cfg") or lowered.endswith(".keystore") or "export_credentials" in lowered


def check_paths(label: str, paths: list[str], blobs: list[bytes]) -> None:
    for blob in blobs:
        if KEY_RE.search(blob) or FILLED_KEY_RE.search(blob):
            fail(f"{label}: в пакете найден ключ API")
    for packed in paths:
        if forbidden(packed):
            fail(f"в сборку попал запрещённый путь: {packed}")
    cases = [packed for packed in paths if "/cases/" in packed.replace("\\", "/") and packed.endswith(".json")]
    if not cases:
        fail(f"{label}: в пакете нет json дела")
    print(f"{label}: файлов {len(paths)}, дел {len(cases)}")


def check_apk(path: Path) -> None:
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        pcks = [name for name in names if name.endswith(".pck")]
        if pcks:
            for name in pcks:
                blob = archive.read(name)
                check_paths(name, pck_paths(blob), [blob])
            return
        assets = [name for name in names if name.startswith("assets/") and not name.endswith("/")]
        if not assets:
            fail("в APK нет ни .pck, ни assets проекта")
        blobs = [archive.read(name) for name in assets if name.startswith("assets/cases/") or name.endswith(".cfg")]
        check_paths(path.name, assets, blobs)


def check_file(path: Path) -> None:
    if path.suffix.lower() == ".apk":
        check_apk(path)
        return
    blob = path.read_bytes()
    check_paths(path.name, pck_paths(blob), [blob])


def main() -> None:
    if len(sys.argv) < 2:
        fail("укажите apk или pck")
    for arg in sys.argv[1:]:
        check_file(Path(arg))


if __name__ == "__main__":
    main()

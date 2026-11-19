#!/usr/bin/env python3
"""В блоках repositories { } ставит google() перед остальными репозиториями."""

import pathlib
import re
import sys

pattern = re.compile(r"repositories\s*\{([^{}]*)\}")


def prefer_google(body: str) -> str:
    lines = body.splitlines(keepends=True)
    google = [line for line in lines if "google()" in line]
    rest = [line for line in lines if "google()" not in line]
    return "".join(google + rest)


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "android/build")
    if not root.is_dir():
        print(f"нет каталога {root}", file=sys.stderr)
        return 1
    for path in root.rglob("*"):
        if path.suffix not in {".gradle", ".kts"}:
            continue
        text = path.read_text(encoding="utf-8")
        updated = pattern.sub(lambda match: "repositories {" + prefer_google(match.group(1)) + "}", text)
        if updated != text:
            path.write_text(updated, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())

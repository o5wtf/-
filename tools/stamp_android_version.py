#!/usr/bin/env python3
"""Ставит version/code у Android-пресета. Пакет не меняет."""

import sys


def stamp(text: str, code: int) -> str:
	section = ""
	lines = text.splitlines()
	done = False
	out = []
	for line in lines:
		stripped = line.strip()
		if stripped.startswith("[") and stripped.endswith("]"):
			section = stripped
		if not done and section == "[preset.0.options]" and stripped.startswith("version/code="):
			line = "version/code=%d" % code
			done = True
		out.append(line)
	if not done:
		raise SystemExit("В пресете Android нет version/code")
	suffix = "\n" if text.endswith("\n") else ""
	return "\n".join(out) + suffix


def main() -> None:
	if len(sys.argv) != 3:
		raise SystemExit("usage: stamp_android_version.py export_presets.cfg CODE")
	path, raw = sys.argv[1], sys.argv[2]
	code = int(raw)
	if code < 1:
		raise SystemExit("versionCode должен быть больше нуля")
	with open(path, "r", encoding="utf-8") as handle:
		original = handle.read()
	updated = stamp(original, code)
	if "package/unique_name=\"com.o5wtf.detective\"" not in updated:
		raise SystemExit("Имя пакета изменилось")
	with open(path, "w", encoding="utf-8") as handle:
		handle.write(updated)


if __name__ == "__main__":
	main()

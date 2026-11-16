#!/usr/bin/env python3
"""Пишет пути keystore для Godot. Пароли берёт из окружения и не печатает."""

import os
from pathlib import Path


def q(value: str) -> str:
	return value.replace("\\", "\\\\").replace('"', '\\"')


def main() -> None:
	path = os.environ["KS_PATH"]
	alias = q(os.environ["KS_ALIAS"])
	store = q(os.environ["KS_STORE"])
	key = q(os.environ["KS_KEY"])
	java = q(os.environ.get("JAVA_HOME", ""))
	android = q(os.environ.get("ANDROID_HOME", ""))
	Path(".godot").mkdir(exist_ok=True)
	Path(".godot/export_credentials.cfg").write_text(
		"[preset.0]\n\n"
		f'keystore/debug="{path}"\n'
		f'keystore/debug_user="{alias}"\n'
		f'keystore/debug_password="{store}"\n'
		f'keystore/release="{path}"\n'
		f'keystore/release_user="{alias}"\n'
		f'keystore/release_password="{key}"\n',
		encoding="utf-8",
	)
	editor = Path.home() / ".config/godot"
	editor.mkdir(parents=True, exist_ok=True)
	(editor / "editor_settings-4.7.tres").write_text(
		'[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
		f'"export/android/java_sdk_path" = "{java}"\n'
		f'"export/android/android_sdk_path" = "{android}"\n'
		f'"export/android/debug_keystore" = "{path}"\n'
		f'"export/android/debug_keystore_user" = "{alias}"\n'
		f'"export/android/debug_keystore_pass" = "{store}"\n',
		encoding="utf-8",
	)
	github_env = os.environ.get("GITHUB_ENV", "")
	if github_env:
		with Path(github_env).open("a", encoding="utf-8") as env:
			env.write(f"GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD={os.environ['KS_STORE']}\n")
			env.write(f"GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD={os.environ['KS_KEY']}\n")


if __name__ == "__main__":
	main()

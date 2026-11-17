@tool
extends EditorExportPlugin
## Вставляет <queries> в корень AndroidManifest при экспорте APK.
## Работает и без Gradle-сборки: Godot добавляет фрагмент в шаблонный манифест.


func _get_name() -> String:
	return "TtsServiceQuery"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _get_android_manifest_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	return TtsManifest.queries_xml()

@tool
extends EditorExportPlugin
## Регистрирует системный распознаватель как плагин Godot 4.7 v2.


func _get_name() -> String:
	return "SystemSpeech"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _get_android_manifest_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	return "<queries><intent><action android:name=\"android.speech.RecognitionService\"/></intent></queries>"


func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	return "<meta-data android:name=\"org.godotengine.plugin.v2.SystemSpeech\" android:value=\"com.o5wtf.detective.speech.SystemSpeechPlugin\" />"

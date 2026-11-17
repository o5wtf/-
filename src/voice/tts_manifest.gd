class_name TtsManifest
extends RefCounted
## Запрос видимости сервиса TTS. На Android 11+ без него список голосов пустой.


static func queries_xml() -> String:
	return "<queries><intent><action android:name=\"android.intent.action.TTS_SERVICE\"/></intent></queries>"

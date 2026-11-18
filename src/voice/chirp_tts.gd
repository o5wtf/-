class_name ChirpTts
extends RefCounted
## Cloud Text-to-Speech v1, один запрос text:synthesize. LINEAR16 24 кГц.


const URL := "https://texttospeech.googleapis.com/v1/text:synthesize"
const SAMPLE_RATE := 24000


static func request_body(text: String, voice_name: String, rate: float) -> String:
	return JSON.stringify({
		"input": {"text": text},
		"voice": {"languageCode": "ru-RU", "name": voice_name},
		"audioConfig": {
			"audioEncoding": "LINEAR16",
			"sampleRateHertz": SAMPLE_RATE,
			"speakingRate": rate,
		},
	})


static func synthesize(host: Node, text: String, voice_name: String, rate: float) -> Dictionary:
	var auth: Dictionary = await ChirpAuth.access_token(host)
	if not auth.get("ok", false):
		return auth
	var response: Dictionary = await ChirpAuth._post(
		host,
		URL,
		request_body(text, voice_name, rate),
		PackedStringArray(["Authorization: Bearer %s" % str(auth.get("token", "")), "Content-Type: application/json"])
	)
	var status := int(response.get("status", 0))
	var raw := str(response.get("body", ""))
	if status == 429:
		return {"ok": false, "error": "rate_limited", "status": status, "retry_after": 1.0}
	if status == 401:
		ChirpAuth.reset()
		return {"ok": false, "error": "chirp_auth", "status": status, "message": ChirpAuth.message_for("chirp_auth", status, raw)}
	if status == 403:
		var kind := "chirp_api" if _api_disabled(raw) else "chirp_denied"
		return {"ok": false, "error": kind, "status": status, "message": ChirpAuth.message_for(kind, status, raw)}
	if status != 200:
		return {"ok": false, "error": "network" if status == 0 else "bad_response", "status": status, "message": ChirpAuth.message_for("network", status, "")}
	var pcm := pcm_from_json(raw)
	if pcm.is_empty():
		return {"ok": false, "error": "no_audio", "status": status}
	return {"ok": true, "status": status, "pcm": pcm}


static func pcm_from_json(raw: String) -> PackedByteArray:
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is not Dictionary:
		return PackedByteArray()
	var audio := str((parsed as Dictionary).get("audioContent", ""))
	if audio == "":
		return PackedByteArray()
	return linear16_pcm(Marshalls.base64_to_raw(audio))


static func linear16_pcm(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.size() < 12 or bytes[0] != 82 or bytes[1] != 73 or bytes[2] != 70 or bytes[3] != 70:
		return bytes
	var index := 12
	while index + 8 <= bytes.size():
		var ident := bytes.slice(index, index + 4).get_string_from_ascii()
		var size := int(bytes[index + 4]) | (int(bytes[index + 5]) << 8) | (int(bytes[index + 6]) << 16) | (int(bytes[index + 7]) << 24)
		if ident == "data":
			var start := index + 8
			return bytes.slice(start, mini(start + size, bytes.size()))
		var step := size + (size % 2)
		index += 8 + step
	return PackedByteArray()


static func _api_disabled(raw: String) -> bool:
	var lower := raw.to_lower()
	return lower.contains("service_disabled") or lower.contains("has not been used") or lower.contains("is disabled")

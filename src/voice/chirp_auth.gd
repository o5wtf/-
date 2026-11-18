class_name ChirpAuth
extends RefCounted
## OAuth сервисного аккаунта для Cloud Text-to-Speech. Токен только в памяти.
## Ключ и сам токен в журнал не пишутся.


const TOKEN_URL := "https://oauth2.googleapis.com/token"
const SCOPE := "https://www.googleapis.com/auth/cloud-platform"
const AUD := "https://oauth2.googleapis.com/token"
const TTL_S := 3600
const SKEW_S := 300

static var now_override: int = -1
## null — читать настройки. Пустая строка — ключа нет.
static var key_override = null
static var transport: Object = null
static var _token: String = ""
static var _expires_at: int = 0


static func reset() -> void:
	_token = ""
	_expires_at = 0


static func now_unix() -> int:
	if now_override >= 0:
		return now_override
	return int(Time.get_unix_time_from_system())


static func account_json() -> String:
	if key_override != null:
		return str(key_override)
	return SettingsStore.load_current().chirp_key


static func ready() -> bool:
	return bool(parse(account_json()).get("ok", false))


static func parse(raw: String) -> Dictionary:
	var text := raw.strip_edges()
	if text == "":
		return {"ok": false, "error": "chirp_key", "message": "Нет ключа Chirp"}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		return {"ok": false, "error": "bad_json", "message": "Ключ Chirp: это не JSON сервисного аккаунта"}
	var body: Dictionary = parsed
	var email := str(body.get("client_email", "")).strip_edges()
	var private_key := str(body.get("private_key", "")).strip_edges()
	if email == "" or private_key == "" or not private_key.contains("PRIVATE KEY"):
		return {"ok": false, "error": "bad_json", "message": "Ключ Chirp: в JSON нет client_email или private_key"}
	return {"ok": true, "email": email, "private_key": private_key}


static func message_for(error: String, status: int, body: String) -> String:
	var lower := body.to_lower()
	if status == 403 and (lower.contains("service_disabled") or lower.contains("has not been used") or lower.contains("is disabled")):
		return "Cloud Text-to-Speech API выключен в проекте"
	match error:
		"chirp_key":
			return "Нет ключа Chirp"
		"bad_json":
			return "Ключ Chirp: это не JSON сервисного аккаунта"
		"chirp_auth":
			return "Ключ Chirp отклонён (%d)" % status if status > 0 else "Ключ Chirp отклонён"
		"chirp_denied":
			return "Ключ Chirp: доступ запрещён (%d)" % status if status > 0 else "Ключ Chirp: доступ запрещён"
		"chirp_api":
			return "Cloud Text-to-Speech API выключен в проекте"
		"sign":
			return "Ключ Chirp: не удалось подписать запрос"
		_:
			return "Голос Chirp: ошибка сети" if status == 0 else "Голос Chirp: ошибка %d" % status


static func build_jwt(email: String, pem: String, issued_at: int) -> Dictionary:
	var key := CryptoKey.new()
	var normalized := _loadable_pem(pem)
	if normalized == "" or key.load_from_string(normalized, false) != OK:
		return {"ok": false, "error": "sign", "message": message_for("sign", 0, "")}
	var header := _b64url('{"alg":"RS256","typ":"JWT"}'.to_utf8_buffer())
	var payload := '{"iss":"%s","scope":"%s","aud":"%s","iat":%d,"exp":%d}' % [
		email, SCOPE, AUD, issued_at, issued_at + TTL_S,
	]
	var claim := _b64url(payload.to_utf8_buffer())
	var signing := "%s.%s" % [header, claim]
	var digest := _sha256(signing.to_utf8_buffer())
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, digest, key)
	if signature.is_empty():
		return {"ok": false, "error": "sign", "message": message_for("sign", 0, "")}
	return {"ok": true, "token": "%s.%s" % [signing, _b64url(signature)], "digest": digest}


static func access_token(host: Node) -> Dictionary:
	var now := now_unix()
	if _token != "" and now < _expires_at - SKEW_S:
		return {"ok": true, "token": _token, "refreshed": false}
	var account := parse(account_json())
	if not account.get("ok", false):
		return account
	var built := build_jwt(str(account.get("email", "")), str(account.get("private_key", "")), now)
	if not built.get("ok", false):
		return built
	var form := "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=%s" % str(built.get("token", "")).uri_encode()
	var response: Dictionary = await _post(host, TOKEN_URL, form, PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]))
	var status := int(response.get("status", 0))
	var raw := str(response.get("body", ""))
	if status == 401:
		return {"ok": false, "error": "chirp_auth", "status": status, "message": message_for("chirp_auth", status, raw)}
	if status == 403:
		var denied := raw.to_lower()
		var kind := "chirp_denied"
		if denied.contains("service_disabled") or denied.contains("has not been used") or denied.contains("is disabled"):
			kind = "chirp_api"
		return {"ok": false, "error": kind, "status": status, "message": message_for(kind, status, raw)}
	if status != 200:
		return {"ok": false, "error": "network" if status == 0 else "bad_response", "status": status, "message": message_for("network", status, "")}
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is not Dictionary or str((parsed as Dictionary).get("access_token", "")) == "":
		return {"ok": false, "error": "bad_response", "status": status, "message": message_for("bad_response", status, "")}
	var granted: Dictionary = parsed
	_token = str(granted.get("access_token", ""))
	var ttl := int(granted.get("expires_in", TTL_S))
	if ttl <= 0:
		ttl = TTL_S
	_expires_at = now + ttl
	if is_instance_valid(Speaker):
		Speaker.note_line("chirp token refresh")
	return {"ok": true, "token": _token, "refreshed": true}


static func _post(host: Node, url: String, body: String, headers: PackedStringArray) -> Dictionary:
	if transport != null and transport.has_method("post"):
		var pending: Variant = transport.call("post", url, body, headers)
		if pending is Dictionary:
			return pending
		return await pending
	return await _live_post(host, url, body, headers)


static func _live_post(host: Node, url: String, body: String, headers: PackedStringArray) -> Dictionary:
	var request := HTTPRequest.new()
	host.add_child(request)
	var err := request.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		request.queue_free()
		return {"status": 0, "body": ""}
	var args: Array = await request.request_completed
	request.queue_free()
	var bytes: PackedByteArray = args[3]
	return {"status": int(args[1]), "body": bytes.get_string_from_utf8()}


static func _sha256(bytes: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish()


static func _b64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")


## Godot читает PKCS#1. Ключ Google — PKCS#8, внутренний ключ вынимается без сторонней библиотеки.
static func _loadable_pem(pem: String) -> String:
	if pem.contains("BEGIN RSA PRIVATE KEY"):
		return pem
	if not pem.contains("BEGIN PRIVATE KEY"):
		return ""
	var inner := _pkcs1_from_pkcs8(_pem_body(pem))
	if inner.is_empty():
		return ""
	return _pem_armor(inner, "RSA PRIVATE KEY")


static func _pem_body(pem: String) -> PackedByteArray:
	var joined := ""
	for line in pem.split("\n"):
		var clean := line.strip_edges()
		if clean == "" or clean.begins_with("-----"):
			continue
		joined += clean
	return Marshalls.base64_to_raw(joined)


static func _pem_armor(der: PackedByteArray, label: String) -> String:
	var raw := Marshalls.raw_to_base64(der)
	var body := ""
	var index := 0
	while index < raw.length():
		body += raw.substr(index, 64) + "\n"
		index += 64
	return "-----BEGIN %s-----\n%s-----END %s-----\n" % [label, body, label]


static func _pkcs1_from_pkcs8(der: PackedByteArray) -> PackedByteArray:
	if der.size() < 8 or der[0] != 0x30:
		return PackedByteArray()
	var outer: Dictionary = _der_len(der, 1)
	var index: int = int(outer.get("next", 0))
	if index >= der.size() or der[index] != 0x02:
		return PackedByteArray()
	var version: Dictionary = _der_len(der, index + 1)
	index = int(version.get("next", 0)) + int(version.get("len", 0))
	if index >= der.size() or der[index] != 0x30:
		return PackedByteArray()
	var algorithm: Dictionary = _der_len(der, index + 1)
	index = int(algorithm.get("next", 0)) + int(algorithm.get("len", 0))
	if index >= der.size() or der[index] != 0x04:
		return PackedByteArray()
	var secret: Dictionary = _der_len(der, index + 1)
	var start: int = int(secret.get("next", 0))
	var end: int = start + int(secret.get("len", 0))
	if end > der.size():
		return PackedByteArray()
	return der.slice(start, end)


static func _der_len(bytes: PackedByteArray, index: int) -> Dictionary:
	var first := int(bytes[index])
	if first < 0x80:
		return {"len": first, "next": index + 1}
	var count := first & 0x7f
	var value := 0
	for step in count:
		value = (value << 8) | int(bytes[index + 1 + step])
	return {"len": value, "next": index + 1 + count}

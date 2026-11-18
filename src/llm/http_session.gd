class_name HttpSession
extends RefCounted
## Одно живое соединение на хост. Повторный запрос не делает новый TLS.
## После обрыва следующее обращение соединяется заново.


const HOST := "generativelanguage.googleapis.com"

static var last_reused: bool = false
static var maker: Callable = Callable()
static var _idle: Dictionary = {}


static func reset() -> void:
	for host in _idle.keys():
		var pool: Array = _idle[host]
		for client in pool:
			_close(client)
	_idle.clear()
	last_reused = false


static func checkout(host: String) -> Dictionary:
	var pool: Array = _idle.get(host, [])
	while not pool.is_empty():
		var existing: Object = pool.pop_back()
		_idle[host] = pool
		if _status(existing) == HTTPClient.STATUS_CONNECTED:
			last_reused = true
			TurnTiming.note_reused(true)
			return {"client": existing, "reused": true, "host": host}
		_close(existing)
	var fresh: Object = _create(host)
	last_reused = false
	TurnTiming.note_reused(false)
	return {"client": fresh, "reused": false, "host": host}


static func checkin(host: String, client: Object, alive: bool) -> void:
	if client == null:
		return
	if not alive or _status(client) != HTTPClient.STATUS_CONNECTED:
		_close(client)
		return
	var pool: Array = _idle.get(host, [])
	pool.append(client)
	_idle[host] = pool


static func prewarm(node: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var slot := checkout(HOST)
	var http: Object = slot.client
	if _status(http) == HTTPClient.STATUS_CONNECTED:
		checkin(HOST, http, true)
		return
	var err := int(http.call("connect_to_host", HOST, 443, TLSOptions.client()))
	if err != OK:
		checkin(HOST, http, false)
		return
	var deadline := Time.get_ticks_msec() + 4000
	while _status(http) == HTTPClient.STATUS_CONNECTING or _status(http) == HTTPClient.STATUS_RESOLVING:
		if Time.get_ticks_msec() >= deadline:
			checkin(HOST, http, false)
			return
		http.call("poll")
		if node != null and node.is_inside_tree():
			await node.get_tree().process_frame
		else:
			break
	checkin(HOST, http, _status(http) == HTTPClient.STATUS_CONNECTED)


static func exchange(node: Node, url: String, headers: PackedStringArray, body: String, timeout_s: float) -> Dictionary:
	var parts := split_url(url)
	var host := str(parts.get("host", ""))
	var slot := checkout(host)
	var http: Object = slot.client
	var reused: bool = bool(slot.get("reused", false))
	var deadline := Time.get_ticks_msec() + int(maxf(timeout_s, 1.0) * 1000.0)
	if _status(http) != HTTPClient.STATUS_CONNECTED:
		var err := FAILED
		if bool(parts.get("tls", false)):
			err = int(http.call("connect_to_host", host, int(parts.get("port", 443)), TLSOptions.client()))
		else:
			err = int(http.call("connect_to_host", host, int(parts.get("port", 80))))
		if err != OK:
			checkin(host, http, false)
			return _fail("offline", reused)
		while _status(http) == HTTPClient.STATUS_CONNECTING or _status(http) == HTTPClient.STATUS_RESOLVING:
			if Time.get_ticks_msec() >= deadline:
				checkin(host, http, false)
				return _fail("timeout", reused)
			http.call("poll")
			if node != null and node.is_inside_tree():
				await node.get_tree().process_frame
			else:
				break
		if _status(http) != HTTPClient.STATUS_CONNECTED:
			checkin(host, http, false)
			return _fail("offline", reused)
	var request_err := int(http.call("request", HTTPClient.METHOD_POST, str(parts.get("path", "/")), headers, body))
	if request_err != OK:
		checkin(host, http, false)
		return _fail("offline", reused)
	while _status(http) == HTTPClient.STATUS_REQUESTING:
		if Time.get_ticks_msec() >= deadline:
			checkin(host, http, false)
			return _fail("timeout", reused)
		http.call("poll")
		if node != null and node.is_inside_tree():
			await node.get_tree().process_frame
		else:
			break
	var status := int(http.call("get_response_code"))
	var buf := PackedByteArray()
	while _status(http) == HTTPClient.STATUS_BODY:
		if Time.get_ticks_msec() >= deadline:
			checkin(host, http, false)
			return _fail("timeout", reused)
		http.call("poll")
		var chunk: PackedByteArray = http.call("read_response_body_chunk")
		if chunk.is_empty():
			if _status(http) != HTTPClient.STATUS_BODY:
				break
			if node != null and node.is_inside_tree():
				await node.get_tree().process_frame
			else:
				break
			continue
		buf.append_array(chunk)
	var alive := _status(http) == HTTPClient.STATUS_CONNECTED
	checkin(host, http, alive)
	return {
		"ok": true,
		"status": status,
		"body": buf.get_string_from_utf8(),
		"headers": {},
		"error": "",
		"reused": reused,
	}


static func split_url(url: String) -> Dictionary:
	var tls := url.begins_with("https://")
	var rest := url.trim_prefix("https://").trim_prefix("http://")
	var slash := rest.find("/")
	var hostport := rest if slash < 0 else rest.substr(0, slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	var host := hostport
	var port := 443 if tls else 80
	var colon := hostport.rfind(":")
	if colon > 0:
		host = hostport.substr(0, colon)
		port = int(hostport.substr(colon + 1))
	return {"host": host, "port": port, "tls": tls, "path": path}


static func _create(host: String) -> Object:
	if maker.is_valid():
		return maker.call(host)
	var http := HTTPClient.new()
	return http


static func _status(client: Object) -> int:
	if client == null or not client.has_method("get_status"):
		return HTTPClient.STATUS_DISCONNECTED
	return int(client.call("get_status"))


static func _close(client: Object) -> void:
	if client != null and client.has_method("close"):
		client.call("close")


static func _fail(kind: String, reused: bool) -> Dictionary:
	return {"ok": false, "status": 0, "body": "", "headers": {}, "error": kind, "reused": reused}

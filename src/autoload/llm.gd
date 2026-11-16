extends Node
## Автозагрузка LLM: mock или Gemini по настройкам. Ключ не печатается.

var client: LLMClient


func _ready() -> void:
	reload_client()


func reload_client() -> void:
	if client != null and is_instance_valid(client):
		client.queue_free()
	var config := LLMConfig.load_settings()
	client = LLMConfig.create_client(config)
	add_child(client)

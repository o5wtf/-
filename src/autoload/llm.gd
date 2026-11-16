extends Node
## Автозагрузка LLM: mock или Gemini по настройкам. Ключ не печатается.

var client: LLMClient


func _ready() -> void:
	var config := LLMConfig.load_settings()
	client = LLMConfig.create_client(config)
	add_child(client)

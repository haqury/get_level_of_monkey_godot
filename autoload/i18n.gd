extends Node

signal locale_changed(locale: String)

var _locale: String = "en"
var _strings: Dictionary = {}


func _ready() -> void:
	set_locale(str(ConfigLoader.game_config.get("locale", "en")), false)


func set_locale(code: String, persist: bool = true) -> void:
	var next := code if code in ["en", "ru"] else "en"
	if next == _locale and not _strings.is_empty():
		return
	_locale = next
	var path := "res://config/locale/%s.json" % _locale
	_strings = {}
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_strings = _flatten(parsed)
	if _strings.is_empty() and _locale != "en":
		set_locale("en", persist)
		return
	if persist:
		ConfigLoader.save_user_settings({"locale": _locale})
	locale_changed.emit(_locale)


func tr_key(key: String, fallback: String = "") -> String:
	var text: String = str(_strings.get(key, ""))
	if text.is_empty() and _locale != "en":
		text = str(_strings.get(key, ""))
	if text.is_empty():
		return fallback if fallback != "" else key
	return text


func tr_format(key: String, fallback: String, params: Dictionary) -> String:
	var text := tr_key(key, fallback)
	for k in params.keys():
		text = text.replace("{%s}" % k, str(params[k]))
	return text


func locale() -> String:
	return _locale


func _flatten(data: Dictionary, prefix: String = "") -> Dictionary:
	var out: Dictionary = {}
	for k in data.keys():
		var full_key := "%s.%s" % [prefix, k] if prefix != "" else str(k)
		var v = data[k]
		if typeof(v) == TYPE_DICTIONARY:
			out.merge(_flatten(v, full_key))
		else:
			out[full_key] = str(v)
	return out

@tool
class_name StrudelSpeech
extends RefCounted

## `speak` — произнести значение события вслух (`core/speak.mjs`).
##
## В браузере это `speechSynthesis`; в Godot ту же работу делает
## `DisplayServer.tts_*`. Голоса берутся у системы, поэтому набор языков
## зависит от машины, а не от плагина.
##
## 🔴 Без графической подсистемы (запуск с `--headless`) речи нет вовсе:
## `tts_get_voices` там пуст. Партия при этом играет дальше — предупреждение
## печатается ОДИН РАЗ, иначе оно забьёт лог на каждой ноте.

static var _warned := false


static func speak(pat: StrudelPattern, lang: Variant = null,
		voice: Variant = null) -> StrudelPattern:
	return pat.with_hap(func(hap: StrudelHap) -> StrudelHap:
		_say(StrudelUtil.text(_text_of(hap.value)),
			StrudelUtil.text(lang), StrudelUtil.text(voice))
		return hap
	)


static func _text_of(value: Variant) -> Variant:
	if value is Dictionary:
		var d: Dictionary = value
		return d.get("value", d.get("s", d.get("note", "")))
	return value


static func _say(text: String, lang: String, voice_name: String) -> void:
	if text == "":
		return
	var voices := DisplayServer.tts_get_voices()
	if voices.is_empty():
		if not _warned:
			_warned = true
			push_warning("Strudel: голосов в системе нет — speak() молчит")
		return
	var chosen := ""
	for v in voices:
		var d: Dictionary = v
		if voice_name != "" and String(d.get("name", "")) == voice_name:
			chosen = String(d.get("id", ""))
			break
		if lang != "" and String(d.get("language", "")).begins_with(lang):
			chosen = String(d.get("id", ""))
			break
	if chosen == "":
		chosen = String((voices[0] as Dictionary).get("id", ""))
	DisplayServer.tts_speak(text, chosen)

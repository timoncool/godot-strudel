@tool
extends EditorPlugin

## Включение плагина Strudel.
##
## Плагин ничего не прописывает в настройки проекта и не оставляет следов:
## снятие галочки убирает узел из списка «Создать узел», и на этом всё.

const _NODE_NAME := "StrudelPlayer"
const _SCRIPT_PATH := "res://addons/strudel/strudel_player.gd"
const _ICON_PATH := "res://addons/strudel/icons/strudel_player.svg"


func _enter_tree() -> void:
	var script: Script = load(_SCRIPT_PATH)
	if script == null:
		push_error("Strudel: не нашёл %s — плагин не включён" % _SCRIPT_PATH)
		return
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON_PATH):
		icon = load(_ICON_PATH)
	add_custom_type(_NODE_NAME, "Node", script, icon)


func _exit_tree() -> void:
	remove_custom_type(_NODE_NAME)

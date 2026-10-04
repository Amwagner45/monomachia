class_name PauseScreen
extends MenuScreen
## The pause menu over the frozen match (port of showPause() in
## src/ui/menus.ts): 休止 over "Paused", then Resume, Move list, Controls,
## Settings, Restart and Quit to menu. main.gd answers each entry: the three
## middle ones open their screens over this one (Back returns here), Restart
## and Quit to menu act at once. Back resumes, as the pause binding, Esc and
## Start do in the host.

signal resume_requested
signal move_list
signal controls
signal settings
signal restart
signal quit_to_menu

var resume_button: Button
var move_list_button: Button
var controls_button: Button
var settings_button: Button
var restart_button: Button
var quit_button: Button


func _init() -> void:
	super()
	var kanji: Label = add_label("休止", UiTheme.KANJI, 48)
	kanji.name = "Kanji"
	kanji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var heading: Label = add_heading("Paused")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resume_button = add_button("Resume", "", func() -> void: resume_requested.emit())
	move_list_button = add_button("Move list", "", func() -> void: move_list.emit())
	controls_button = add_button("Controls", "", func() -> void: controls.emit())
	settings_button = add_button("Settings", "", func() -> void: settings.emit())
	restart_button = add_button("Restart", "", func() -> void: restart.emit())
	quit_button = add_button("Quit to menu", "", func() -> void: quit_to_menu.emit())
	back_pops = false
	back_requested.connect(func() -> void: resume_requested.emit())

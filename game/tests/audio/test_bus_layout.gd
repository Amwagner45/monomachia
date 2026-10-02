extends GutTest
## The default bus layout: Master > Music, Ambience, SFX > Arena > Combat,
## Foley, and UI; a compressor on Master, and on the Arena bus a reverb that
## keeps the dry sound and adds the arena's room to every combat and foley
## sound. (Godot 4.7's Area3D reverb takes a 3D sound off its own bus, so the
## reverb sits on the bus chain instead.)

const SENDS: Dictionary = {
	&"Music": &"Master",
	&"Ambience": &"Master",
	&"SFX": &"Master",
	&"Combat": &"Arena",
	&"Foley": &"Arena",
	&"Arena": &"SFX",
	&"UI": &"Master",
}


func _has_effect(bus: StringName, type: String) -> bool:
	var index := AudioServer.get_bus_index(bus)
	for i in AudioServer.get_bus_effect_count(index):
		if AudioServer.get_bus_effect(index, i).is_class(type):
			return true
	return false


func test_the_project_uses_the_default_bus_layout() -> void:
	assert_true(ResourceLoader.exists("res://default_bus_layout.tres"))
	assert_true(load("res://default_bus_layout.tres") is AudioBusLayout)


func test_every_bus_exists_and_sends_to_its_parent() -> void:
	for bus: StringName in SENDS:
		var index := AudioServer.get_bus_index(bus)
		assert_true(index > 0, "bus %s is missing" % bus)
		assert_eq(AudioServer.get_bus_send(index), SENDS[bus], "bus %s sends to the wrong parent" % bus)


func test_every_bus_sends_to_one_mixed_after_it() -> void:
	# Godot mixes the buses from the last to the first: a send to a bus later
	# in the list would be dropped.
	for i in range(1, AudioServer.bus_count):
		var send := AudioServer.get_bus_index(AudioServer.get_bus_send(i))
		assert_lt(send, i, "bus %s sends to %s, listed after it" % [AudioServer.get_bus_name(i), AudioServer.get_bus_send(i)])


func test_the_arena_reverb_keeps_the_dry_sound_and_adds_a_little_room() -> void:
	var arena := AudioServer.get_bus_index(&"Arena")
	assert_eq(AudioServer.get_bus_volume_db(arena), 0.0, "the bus passes its sounds at their level")
	var reverb: AudioEffectReverb = null
	for i in AudioServer.get_bus_effect_count(arena):
		if AudioServer.get_bus_effect(arena, i) is AudioEffectReverb:
			reverb = AudioServer.get_bus_effect(arena, i)
	assert_not_null(reverb)
	if reverb != null:
		assert_eq(reverb.dry, 1.0, "the dry sound passes untouched")
		assert_between(reverb.wet, 0.05, 0.4, "with a little room")


func test_master_has_a_compressor_and_the_arena_a_reverb() -> void:
	assert_true(_has_effect(&"Master", "AudioEffectCompressor"))
	assert_true(_has_effect(&"Arena", "AudioEffectReverb"))


func test_sound_bank_buses_exist() -> void:
	for bus: StringName in SoundBank.BUSES:
		assert_true(AudioServer.get_bus_index(bus) >= 0, "SoundBank bus %s missing" % bus)

extends GutTest
## The default bus layout: Master > Music, Ambience, SFX (> Combat, Foley,
## Arena), UI; a compressor on Master and a reverb on the Arena bus.

const SENDS: Dictionary = {
	&"Music": &"Master",
	&"Ambience": &"Master",
	&"SFX": &"Master",
	&"Combat": &"SFX",
	&"Foley": &"SFX",
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


func test_master_has_a_compressor_and_the_arena_a_reverb() -> void:
	assert_true(_has_effect(&"Master", "AudioEffectCompressor"))
	assert_true(_has_effect(&"Arena", "AudioEffectReverb"))


func test_sound_bank_buses_exist() -> void:
	for bus: StringName in SoundBank.BUSES:
		assert_true(AudioServer.get_bus_index(bus) >= 0, "SoundBank bus %s missing" % bus)

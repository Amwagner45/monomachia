extends GutTest
## Controller seats (binding at match start, hot-plugging, unplugging never
## swapping players) and pause edge detection.

var fake: FakeDeviceState
var input: InputDevices
var p1: ControlProfile
var p2: ControlProfile


func before_each() -> void:
	fake = FakeDeviceState.new()
	input = InputDevices.new(fake)
	p1 = ControlProfile.create("Player 1")
	p2 = ControlProfile.create("Player 2")


func _versus(d1: String, d2: String) -> void:
	var devices: Array[String] = [d1, d2]
	var profiles: Array[ControlProfile] = [p1, p2]
	input.set_versus(devices, profiles)


func _jumping(player: int) -> bool:
	return (input.sample(player).buttons & Btn.bit(Btn.JUMP)) != 0


func test_without_seats_controllers_follow_connection_order() -> void:
	fake.plug_pad(0)
	fake.plug_pad(1)
	assert_false(input.seats_bound())
	assert_eq(input.pad_for(0), 0)
	assert_eq(input.pad_for(1), 1)
	fake.unplug_pad(0)
	assert_eq(input.pad_for(0), 1, "menus: the remaining controller is controller 1")
	assert_eq(input.pad_for(1), -1)


func test_versus_binds_each_seat_to_a_controller() -> void:
	fake.plug_pad(0)
	fake.plug_pad(1)
	_versus(InputDevices.PAD0, InputDevices.PAD1)
	assert_true(input.seats_bound())
	fake.press_button(1, JOY_BUTTON_A)
	assert_false(_jumping(0))
	assert_true(_jumping(1))
	fake.press_button(0, JOY_BUTTON_A)
	assert_true(_jumping(0))


func test_unplugging_controller_1_never_hands_player_2s_controller_to_player_1() -> void:
	fake.plug_pad(0)
	fake.plug_pad(1)
	_versus(InputDevices.PAD0, InputDevices.PAD1)
	fake.unplug_pad(0)
	fake.press_button(1, JOY_BUTTON_A)
	assert_false(_jumping(0), "player 1 has no controller now")
	assert_true(_jumping(1), "player 2 keeps theirs")
	assert_eq(input.pad_for(0), -1)
	assert_eq(input.pad_for(1), 1)
	assert_false(input.pad_connected(0))


func test_a_replugged_controller_returns_to_its_seat() -> void:
	fake.plug_pad(0)
	fake.plug_pad(1)
	_versus(InputDevices.PAD0, InputDevices.PAD1)
	fake.unplug_pad(0)
	fake.plug_pad(0)
	fake.press_button(0, JOY_BUTTON_A)
	assert_true(_jumping(0))
	assert_false(_jumping(1))


func test_a_controller_plugged_in_mid_match_fills_the_empty_seat() -> void:
	fake.plug_pad(0)
	_versus(InputDevices.PAD0, InputDevices.PAD1)
	assert_eq(input.pad_for(1), -1)
	fake.plug_pad(1)
	assert_eq(input.pad_for(0), 0)
	assert_eq(input.pad_for(1), 1)
	fake.press_button(1, JOY_BUTTON_A)
	assert_true(_jumping(1))
	assert_false(_jumping(0))


func test_hot_plugged_controllers_fill_seat_1_then_seat_2() -> void:
	_versus(InputDevices.PAD0, InputDevices.PAD1)
	fake.plug_pad(3)
	fake.plug_pad(5)
	assert_eq(input.pad_for(0), 3)
	assert_eq(input.pad_for(1), 5)


func test_an_empty_seat_also_fills_without_the_signal() -> void:
	fake.plug_pad(0)
	_versus(InputDevices.PAD0, InputDevices.PAD1)
	fake.plug_pad(2, "Pad", {}, false)
	assert_eq(input.pad_for(1), 2)
	assert_eq(input.pad_for(0), 0)


func test_a_new_controller_does_not_take_a_seat_whose_controller_is_unplugged() -> void:
	fake.plug_pad(0)
	fake.plug_pad(1)
	_versus(InputDevices.PAD0, InputDevices.PAD1)
	fake.unplug_pad(1)
	fake.plug_pad(2)
	fake.press_button(2, JOY_BUTTON_A)
	assert_false(_jumping(0))
	assert_false(_jumping(1), "seat 2 waits for its own controller")
	assert_eq(input.pad_for(1), -1)


func test_player_2_on_controller_1_while_player_1_uses_keyboard() -> void:
	fake.plug_pad(0)
	_versus(InputDevices.KBM, InputDevices.PAD0)
	fake.press_button(0, JOY_BUTTON_A)
	fake.press_key(KEY_K)
	assert_eq(input.sample(0).buttons, Btn.bit(Btn.HEAVY))
	assert_eq(input.sample(1).buttons, Btn.bit(Btn.JUMP))


func test_single_player_unbinds_the_seats() -> void:
	fake.plug_pad(0)
	fake.plug_pad(1)
	_versus(InputDevices.PAD0, InputDevices.PAD1)
	input.set_single_player(p1)
	assert_false(input.seats_bound())
	fake.unplug_pad(0)
	fake.press_button(1, JOY_BUTTON_A)
	assert_true(_jumping(0), "single player reads the first connected controller")


func test_pause_fires_once_per_press() -> void:
	input.set_single_player(p1)
	fake.press_key(KEY_ESCAPE)
	assert_true(input.pause_pressed(0))
	assert_false(input.pause_pressed(0), "held")
	assert_false(input.pause_pressed(0), "still held")
	fake.release_key(KEY_ESCAPE)
	assert_false(input.pause_pressed(0))
	fake.press_key(KEY_P)
	assert_true(input.pause_pressed(0))


func test_pause_on_a_controller() -> void:
	fake.plug_pad(0)
	input.set_single_player(p1)
	fake.press_button(0, JOY_BUTTON_START)
	assert_true(input.pause_pressed(0))
	assert_false(input.pause_pressed(0))


func test_a_button_held_on_resume_does_not_pause_again() -> void:
	fake.plug_pad(0)
	input.set_single_player(p1)
	assert_false(input.pause_pressed(0))
	# the game paused; the player closes the menu with Options and keeps holding it
	fake.press_button(0, JOY_BUTTON_START)
	input.rearm_pause()
	assert_false(input.pause_pressed(0), "held through the resume")
	assert_false(input.any_pause_pressed())
	fake.release_button(0, JOY_BUTTON_START)
	assert_false(input.pause_pressed(0))
	fake.press_button(0, JOY_BUTTON_START)
	assert_true(input.pause_pressed(0), "a fresh press pauses")


func test_pause_edges_are_per_device() -> void:
	fake.plug_pad(0)
	_versus(InputDevices.KBM, InputDevices.PAD0)
	fake.press_key(KEY_ESCAPE)
	assert_true(input.any_pause_pressed())
	fake.press_button(0, JOY_BUTTON_START)
	assert_false(input.pause_pressed(0), "player 1 is still holding Esc")
	assert_true(input.pause_pressed(1), "player 2's first press")
	assert_false(input.any_pause_pressed())


func test_any_pause_pressed_updates_every_player() -> void:
	fake.plug_pad(0)
	_versus(InputDevices.KBM, InputDevices.PAD0)
	fake.press_key(KEY_ESCAPE)
	fake.press_button(0, JOY_BUTTON_START)
	assert_true(input.any_pause_pressed())
	assert_false(input.pause_pressed(0))
	assert_false(input.pause_pressed(1), "both edges were taken by the same call")

extends GutTest
## The GameServices autoload: one ControlProfiles, one InputDevices with its
## InputFeed in the tree for the whole game, and a pause when the window loses
## focus during a match.


func _services() -> Node:
	return get_tree().root.get_node_or_null("GameServices")


func _host() -> MatchHost:
	var host: MatchHost = MatchHost.new()
	host.auto_run = false
	host.input = InputDevices.new(FakeDeviceState.new())
	host.profiles = ControlProfiles.new()
	add_child_autofree(host)
	return host


func test_the_autoload_is_registered() -> void:
	var services: Node = _services()
	assert_not_null(services, "GameServices is an autoload")
	assert_eq(ProjectSettings.get_setting("autoload/GameServices"), "*res://core/game_services.gd")


func test_it_owns_one_input_with_its_feed_in_the_tree() -> void:
	var services: Node = _services()
	var input: InputDevices = services.get("input")
	var feed: InputFeed = services.get("feed")
	var profiles: ControlProfiles = services.get("profiles")
	assert_not_null(input)
	assert_not_null(profiles)
	assert_not_null(feed)
	assert_true(feed.is_inside_tree(), "the feed sees every event")
	assert_eq(feed.get_parent(), services)
	assert_same(feed.input, input, "the feed hands events to the shared input")
	assert_eq(services.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_a_host_without_its_own_input_takes_the_shared_one() -> void:
	var host: MatchHost = MatchHost.new()
	host.auto_run = false
	add_child_autofree(host)
	host.start(MatchConfig.default_watch())
	assert_same(host.input, _services().get("input"))
	assert_same(host.profiles, _services().get("profiles"))


func test_losing_focus_pauses_a_match_being_played() -> void:
	var host: MatchHost = _host()
	host.start(MatchConfig.default_duel())
	assert_same(_services().call("current_match"), host)
	assert_true(host.is_playing())
	(_services().get("feed") as InputFeed).focus_lost.emit()
	assert_true(host.is_paused(), "focus loss paused the match")


func test_losing_focus_leaves_the_duel_behind_the_menus_running() -> void:
	var host: MatchHost = _host()
	host.start(MatchConfig.attract(), true)
	assert_null(_services().call("current_match"))
	(_services().get("feed") as InputFeed).focus_lost.emit()
	assert_false(host.is_paused())


func test_a_stopped_match_is_forgotten() -> void:
	var host: MatchHost = _host()
	host.start(MatchConfig.default_duel())
	host.stop()
	assert_null(_services().call("current_match"))
	(_services().get("feed") as InputFeed).focus_lost.emit()
	assert_false(host.is_paused())

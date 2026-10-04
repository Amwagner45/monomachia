class_name WeaponCardRow
extends PanelContainer
## The loadout panel's weapon cards (the demo's .cards): one card per playable
## weapon with its kanji and class, its name and the five stat bars
## (MenuData), and, where the side may leave it to chance, a Random card at
## the end. Like an OptionRow it is a single item on its MenuPage: left and
## right (and OK, which steps on) move the choice, wrapping round, and a click
## on a card picks it. Lit like a menu entry while focused.
##
## Emits changed when the choice changes by the player's hand, not when
## set_choice() is called.

signal changed(choice: StringName)

## The choice that leaves the weapon to chance.
const RANDOM: StringName = &"random"
const CARD_SIZE: Vector2 = Vector2(176.0, 168.0)

## The cards' choices in order: the playable weapons, then RANDOM if offered.
var choices: Array[StringName] = []
var cards: Array[Button] = []
var choice: StringName = &""
var _random_card: Button


func _init() -> void:
	theme_type_variation = UiTheme.MENU_ROW
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	for id: StringName in Moves.PLAYABLE_WEAPONS:
		row.add_child(_card(id))
	_random_card = _random()
	row.add_child(_random_card)
	focus_entered.connect(func() -> void: theme_type_variation = UiTheme.MENU_ROW_LIT)
	focus_exited.connect(func() -> void: theme_type_variation = UiTheme.MENU_ROW)
	offer_random(false)


## Shows or hides the Random card (the Duel opponent's only).
func offer_random(on: bool) -> void:
	_random_card.visible = on
	choices.assign(Moves.PLAYABLE_WEAPONS)
	if on:
		choices.append(RANDOM)
	if not choices.has(choice) and not choices.is_empty():
		set_choice(choices[0])


## Lights a choice (a weapon id or RANDOM) without emitting changed.
func set_choice(c: StringName) -> void:
	if not choices.has(c):
		return
	choice = c
	for card: Button in cards:
		card.theme_type_variation = UiTheme.OPTION_ON if card.get_meta(&"choice") == c else UiTheme.OPTION


func card_of(c: StringName) -> Button:
	for card: Button in cards:
		if card.get_meta(&"choice") == c:
			return card
	return null


## Left (-1) or right (+1), wrapping round. Returns whether the choice moved.
func nav_step(dir: int) -> bool:
	if choices.size() < 2:
		return false
	set_choice(choices[posmod(choices.find(choice) + dir, choices.size())])
	changed.emit(choice)
	return true


## OK steps on to the next card.
func nav_press() -> void:
	if nav_step(1):
		GameServices.play_ui(&"ui_move")


func _on_card(c: StringName) -> void:
	if not has_focus():
		grab_focus()
	GameServices.play_ui(&"ui_select")
	if c == choice:
		return
	set_choice(c)
	changed.emit(choice)


func _card(id: StringName) -> Button:
	var info: MenuData.WeaponInfo = MenuData.weapon(id)
	var card: Button = _blank(id)
	var box: VBoxContainer = card.get_child(0)
	box.add_child(_text("%s · %s" % [info.kanji, info.cls], UiTheme.MUTED, 15))
	box.add_child(_text(Moves.WEAPONS[id].name, UiTheme.DISPLAY, 22))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 3)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for stat: StringName in MenuData.STATS:
		var caption: Label = _text(MenuData.STAT_LABELS[stat], UiTheme.MUTED, 13)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(caption)
		var bar: StatBar = StatBar.new()
		bar.name = "Stat_%s" % stat
		bar.value = info.stats[stat]
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(bar)
	box.add_child(grid)
	return card


func _random() -> Button:
	var card: Button = _blank(RANDOM)
	var box: VBoxContainer = card.get_child(0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_text("?", UiTheme.DISPLAY, 44))
	box.add_child(_text("Random weapon", UiTheme.MUTED, 15))
	return card


func _blank(c: StringName) -> Button:
	var card: Button = Button.new()
	card.name = "Card_%s" % c
	card.set_meta(&"choice", c)
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = CARD_SIZE
	card.theme_type_variation = UiTheme.OPTION
	card.pressed.connect(_on_card.bind(c))
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	cards.append(card)
	return card


static func _text(t: String, variation: StringName, font_size: int) -> Label:
	var l: Label = UiTheme.label(t, variation, font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

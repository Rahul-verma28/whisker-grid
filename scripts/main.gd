extends Control
## Whisker Grid app shell. Builds every screen in code:
##   home · levels map · friends shop · settings · game, plus popup and level-complete celebration.

const SAVE_PATH := "user://save.cfg"
const MAX_LIVES := 3
const HINT_COST := 60
const PRAISE := ["Nice!", "Great!", "Awesome!", "Clever!", "Brilliant!", "Super!", "Sharp eyes!"]
const BAND_NAMES := ["Easy", "Warm-up", "Medium", "Tricky", "Hard", "Expert", "Master"]

## Screen to reopen after the scene reloads (used when switching themes).
static var reopen := ""

# ---- theme colours (filled from Pal in _ready)
var BG: Color
var CARD: Color
var INK: Color
var SOFT: Color
var ACCENT: Color
var BLUE: Color
var PINK: Color
var GREEN: Color
var RED: Color
var NEUTRAL: Color
var GOLD: Color

# ---- saved state
var level := 1                 # highest unlocked campaign level (101 = all done)
var points := 0
var stars := {}                # "12" -> 0..3
var daily_done := ""
var owned: Array = ["cat"]
var selected := "cat"
var theme_id := "cream"
var hints := 3                 # hint stock (saved); refilled by videos, coins or the daily gift
var gift_date := ""

# ---- round state
var playing := 1
var daily := false
var lives := MAX_LIVES
var hints_used := 0
var mistakes := 0
var earned := 0
var elapsed := 0.0
var last_find_time := 0.0
var running := false
var hinting := false
var revived := false
var level_reward := 0
var doubled := false
var shown_points := 0.0
var head_pop := {}
var bg_time := 0.0

var font_body: FontVariation
var font_bold: FontVariation
var generator := PuzzleGenerator.new()
var current: Control
var home: Control
var levels_screen: Control
var shop: Control
var settings: Control
var game: Control
var fx: Control
var backdrop: Control
var board: Board
var point_labels: Array = []
var star_labels: Array = []

var stage: Control
var stage_view: CharacterView
var stage_name: Label
var play_title: Label
var play_sub: Label
var daily_btn: Button
var daily_sub: Label
var shop_sub: Label
var levels_sub: Label
var level_scroll: ScrollContainer
var level_tiles := {}
var shop_cards := {}

var level_title: Label
var level_value: Label
var time_label: Label
var hearts: Control
var heads: Control
var rule_labels := {}
var rule_icons := {}
var hint_button: Button

var popup: Control
var popup_panel: Control
var popup_icon: TextureRect
var popup_title: Label
var popup_text: Label
var popup_primary: Button
var popup_secondary: Button
var popup_actions: Array = [Callable(), Callable()]

var win: Control
var win_panel: Control
var win_rays: Control
var win_view: CharacterView
var win_title: Label
var win_sub: Label
var win_stars: Control
var win_stats: Label
var win_unlock: Label
var win_bar: Control
var win_primary: Button
var win_replay: Button
var win_levels: Button
var win_star_count := 0
var win_star_anim := [0.0, 0.0, 0.0]
var win_unlock_frac := 0.0
var win_next: Callable
var win_double: Button
var coin_ad_btn: Button


func _ready() -> void:
	_load()
	Pal.use(theme_id)
	for k in ["bg", "card", "ink", "soft", "accent", "blue", "pink", "green", "red", "neutral", "gold"]:
		set(k.to_upper(), Pal.c(k))
	RenderingServer.set_default_clear_color(BG)
	_make_fonts()
	theme = _make_theme()
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	backdrop = Control.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.draw.connect(_draw_backdrop)
	add_child(backdrop)
	_build_home()
	_build_levels()
	_build_shop()
	_build_settings()
	_build_game()
	_build_popup()
	_build_win()
	fx = Control.new()
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx)
	_apply_character()
	Sfx.set_music(Sfx.music_on)
	Ads.notice.connect(func(t: String): _float_text(t, get_viewport_rect().size * Vector2(0.5, 0.45), RED, 38))
	if gift_date != _today():   # small daily gift brings players back
		gift_date = _today()
		hints = mini(hints + 1, 9)
		_save()
		get_tree().create_timer(1.2).timeout.connect(_daily_gift_toast)
	match reopen:
		"settings": _go(settings, false)
		_: _go(home, false)
	reopen = ""


func _daily_gift_toast() -> void:
	_float_text("Daily gift: +1 hint", get_viewport_rect().size * Vector2(0.5, 0.42), GREEN, 44)


func _process(delta: float) -> void:
	bg_time += delta
	if current != game:
		backdrop.queue_redraw()
	if current == home:
		_update_daily()
	if running:
		elapsed += delta
		time_label.text = _fmt_time(elapsed)
	if not head_pop.is_empty():
		for k in head_pop.keys():
			head_pop[k] -= delta
			if head_pop[k] <= 0.0:
				head_pop.erase(k)
		heads.queue_redraw()
	if win.visible:
		win_rays.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:   # Android back button
		if popup.visible and current != game:
			popup.visible = false
		elif current == game or current == home:
			if current == home:
				get_tree().quit()
			else:
				_go_home()
		else:
			_go_home()


# ================================================================ look & feel

func _make_fonts() -> void:
	var base := load("res://assets/fonts/Fredoka.ttf") as FontFile
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	font_body = FontVariation.new()
	font_body.base_font = base
	font_body.variation_opentype = {wght: 500}
	font_bold = FontVariation.new()
	font_bold.base_font = base
	font_bold.variation_opentype = {wght: 640}


func _box(color: Color, radius := 28, shadow := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 8
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	if shadow:
		sb.shadow_color = Color(0, 0, 0, 0.28) if Pal.dark() else Color(0.35, 0.2, 0.1, 0.14)
		sb.shadow_size = 8
		sb.shadow_offset = Vector2(0, 5)
	return sb


func _button_box(color: Color, radius: int) -> StyleBoxFlat:
	# chunky "candy" button: lighter face with a darker bottom lip
	var sb := _box(color, radius)
	sb.border_width_bottom = 7
	sb.border_color = color.darkened(0.22)
	return sb


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_body
	t.default_font_size = 34
	t.set_color("font_color", "Label", INK)
	t.set_font("font", "Button", font_bold)
	_theme_button(t, ACCENT)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.85))
	return t


func _theme_button(t: Theme, color: Color) -> void:
	t.set_stylebox("normal", "Button", _button_box(color, 30))
	t.set_stylebox("hover", "Button", _button_box(color.lightened(0.06), 30))
	var pressed := _button_box(color.darkened(0.06), 30)
	pressed.border_width_bottom = 2
	pressed.content_margin_top = 19
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", _button_box(NEUTRAL.lerp(BG, 0.3), 30))


func _style_button(b: Button, color: Color, radius := 30) -> void:
	b.add_theme_stylebox_override("normal", _button_box(color, radius))
	b.add_theme_stylebox_override("hover", _button_box(color.lightened(0.06), radius))
	var pressed := _button_box(color.darkened(0.06), radius)
	pressed.border_width_bottom = 2
	pressed.content_margin_top = 19
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", _button_box(NEUTRAL.lerp(BG, 0.3), radius))


func _label(text: String, font_size := 34, color := INK, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font_bold)
	return l


## Every button squishes when pressed, springs back, and clicks.
func _juice(b: Control, sound := true) -> void:
	b.resized.connect(func(): b.pivot_offset = b.size / 2.0)
	if b is BaseButton:
		(b as BaseButton).button_down.connect(func():
			if sound:
				Sfx.play("click", randf_range(0.95, 1.05), -3.0)
			create_tween().tween_property(b, "scale", Vector2(0.94, 0.94), 0.07))
		(b as BaseButton).button_up.connect(func():
			create_tween().tween_property(b, "scale", Vector2.ONE, 0.3) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


func _button(text: String, cb: Callable, color := Color(), height := 96) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if color != Color():
		_style_button(b, color)
	b.pressed.connect(cb)
	_juice(b)
	return b


## Big button with a title and a smaller second line. Returns [button, title, subtitle].
func _big_button(title: String, sub: String, cb: Callable, color: Color, height := 128, title_size := 44) -> Array:
	var b := _button("", cb, color, height)
	_style_button(b, color, 36)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_bottom = -6
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := _label(title, title_size, Color.WHITE, true)
	v.add_child(t)
	var s := _label(sub, 22, Color(1, 1, 1, 0.9))
	v.add_child(s)
	b.add_child(v)
	return [b, t, s]


## Round icon button: "back", "gear" or a single character.
func _icon_button(kind: String, cb: Callable, color := Color()) -> Button:
	var col := NEUTRAL if color == Color() else color
	var b := _button("", cb, col, 84)
	b.custom_minimum_size = Vector2(84, 84)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_style_button(b, col, 42)
	b.draw.connect(_draw_icon_button.bind(b, kind, col))
	return b


func _draw_icon_button(b: Button, kind: String, col: Color) -> void:
	var c := b.size / 2.0 - Vector2(0, 3)
	match kind:
		"back":
			b.draw_polyline(PackedVector2Array([c + Vector2(8, -15), c + Vector2(-8, 0), c + Vector2(8, 15)]), Color.WHITE, 7.0, true)
		"gear":
			for k in 8:
				var a := TAU * k / 8.0
				b.draw_circle(c + Vector2(cos(a), sin(a)) * 17.0, 6.5, Color.WHITE)
			b.draw_circle(c, 17.0, Color.WHITE)
			b.draw_circle(c, 7.0, col)
		_:
			var w := font_bold.get_string_size(kind, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
			b.draw_string(font_bold, c + Vector2(-w / 2.0, 14), kind, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color.WHITE)


## Button showing a drawn icon (optionally with a short label and a corner badge).
func _glyph_button(kind: String, cb: Callable, color: Color, height := 96, label := "") -> Button:
	var b := _button("", cb, color, height)
	b.set_meta("glyph", kind)
	b.set_meta("label", label)
	b.set_meta("badge", "")
	b.draw.connect(_draw_glyph_button.bind(b))
	return b


func _draw_glyph_button(b: Button) -> void:
	var ctr := b.size / 2.0 - Vector2(0, 3)
	var s := minf(b.size.y * 0.5, 50.0)
	var label: String = b.get_meta("label")
	var col := Color(1, 1, 1, 0.55) if b.disabled else Color.WHITE
	if label == "":
		_draw_glyph(b, b.get_meta("glyph"), ctr, s, col)
	else:
		var fs := 30
		var tw := font_bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x0 := ctr.x - (s + 12 + tw) / 2.0
		_draw_glyph(b, b.get_meta("glyph"), Vector2(x0 + s / 2.0, ctr.y), s, col)
		b.draw_string(font_bold, Vector2(x0 + s + 12, ctr.y + 11), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	var badge: String = b.get_meta("badge")
	if badge != "":
		var bc := Vector2(b.size.x - 30, 18)
		b.draw_circle(bc, 21, RED if badge == "ad" else GOLD)
		b.draw_arc(bc, 21, 0, TAU, 24, Color.WHITE, 3.0, true)
		if badge == "ad":
			_draw_glyph(b, "play", bc, 22, Color.WHITE)
		else:
			var w := font_bold.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
			b.draw_string(font_bold, bc + Vector2(-w / 2.0, 9), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)


func _arrow_head(c: CanvasItem, tip: Vector2, dir: Vector2, s: float, col: Color) -> void:
	var d := dir.normalized()
	var n := Vector2(-d.y, d.x)
	c.draw_colored_polygon(PackedVector2Array([tip, tip - d * s + n * s * 0.75, tip - d * s - n * s * 0.75]), col)


## Small icon set drawn in code, so it stays crisp at any size and follows the theme.
func _draw_glyph(c: CanvasItem, kind: String, ctr: Vector2, s: float, col: Color) -> void:
	var w := maxf(3.0, s * 0.14)
	match kind:
		"undo":
			var r := s * 0.34
			var o := ctr + Vector2(0.06 * s, 0.05 * s)
			c.draw_arc(o, r, PI * 1.05, PI * 2.3, 24, col, w, true)
			var a := PI * 1.05
			var p := o + Vector2(cos(a), sin(a)) * r
			_arrow_head(c, p + Vector2(0, s * 0.16), Vector2(-0.25, 1), s * 0.22, col)
		"replay":
			var r := s * 0.34
			c.draw_arc(ctr, r, PI * 0.35, PI * 1.85, 24, col, w, true)
			var a := PI * 1.85
			var tan := Vector2(-sin(a), cos(a))
			var p := ctr + Vector2(cos(a), sin(a)) * r
			_arrow_head(c, p + tan * s * 0.16, tan, s * 0.22, col)
		"erase":
			c.draw_set_transform(ctr - Vector2(0, s * 0.06), -0.65, Vector2.ONE)
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(int(s * 0.08))
			sb.bg_color = col
			c.draw_style_box(sb, Rect2(-s * 0.38, -s * 0.18, s * 0.76, s * 0.36))
			sb.bg_color = Color(col, 0.45)
			c.draw_style_box(sb, Rect2(-s * 0.38, -s * 0.18, s * 0.3, s * 0.36))
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			c.draw_line(ctr + Vector2(-s * 0.4, s * 0.4), ctr + Vector2(s * 0.4, s * 0.4), col, w * 0.7, true)
		"bulb":
			var b := ctr - Vector2(0, s * 0.1)
			c.draw_circle(b, s * 0.27, col)
			c.draw_rect(Rect2(ctr.x - s * 0.13, ctr.y + s * 0.1, s * 0.26, s * 0.2), col)
			c.draw_line(ctr + Vector2(-s * 0.1, s * 0.37), ctr + Vector2(s * 0.1, s * 0.37), col, w * 0.7, true)
			for k in 5:
				var a := PI + PI * k / 4.0
				var d := Vector2(cos(a), sin(a))
				c.draw_line(b + d * s * 0.36, b + d * s * 0.48, col, w * 0.6, true)
		"grid":
			var q := s * 0.2
			for r in 3:
				for k in 3:
					c.draw_rect(Rect2(ctr + Vector2((k - 1.5) * q * 1.3 + q * 0.15, (r - 1.5) * q * 1.3 + q * 0.15), Vector2(q, q)), col)
		"play":
			c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(-s * 0.22, -s * 0.28), ctr + Vector2(s * 0.3, 0), ctr + Vector2(-s * 0.22, s * 0.28)]), col)
		"video":
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(int(s * 0.14))
			sb.draw_center = false
			sb.set_border_width_all(int(w * 0.8))
			sb.border_color = col
			c.draw_style_box(sb, Rect2(ctr - Vector2(s * 0.42, s * 0.3), Vector2(s * 0.84, s * 0.6)))
			_draw_glyph(c, "play", ctr + Vector2(s * 0.03, 0), s * 0.62, col)
		"coin":
			_draw_coin(c, ctr, s * 0.42)


func _draw_coin(c: CanvasItem, ctr: Vector2, r: float) -> void:
	c.draw_circle(ctr + Vector2(0, r * 0.12), r, GOLD.darkened(0.25))
	c.draw_circle(ctr, r, GOLD)
	c.draw_circle(ctr, r * 0.72, GOLD.lightened(0.18))
	_draw_star(c, ctr, r * 0.48, GOLD.darkened(0.12))


func _drawn(min_size: Vector2, painter: Callable) -> Control:
	var c := Control.new()
	c.custom_minimum_size = min_size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(painter.bind(c))
	return c


func _pill(icon: String, value: String, into: Array) -> Control:
	var p := PanelContainer.new()
	var sb := _box(CARD, 40)
	sb.content_margin_left = 14
	sb.content_margin_right = 22
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	if icon == "coin":
		h.add_child(_drawn(Vector2(40, 44), func(c: Control): _draw_coin(c, c.size / 2.0, 17.0)))
	else:
		h.add_child(_drawn(Vector2(40, 44), func(c: Control): _draw_star(c, c.size / 2.0, 18.0, GOLD)))
	var l := _label(value, 30, INK, true)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(l)
	p.add_child(h)
	into.append(l)
	return p


func _card(sep := 14) -> Array:
	var p := PanelContainer.new()
	var sb := _box(CARD, 30)
	sb.set_content_margin_all(22)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	p.add_child(v)
	return [p, v]


func _screen(separation := 18) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	var inset := _safe_insets()
	margin.add_theme_constant_override("margin_top", int(maxf(52.0, inset.x + 20.0)))
	margin.add_theme_constant_override("margin_bottom", int(maxf(34.0, inset.y + 16.0)))
	margin.visible = false
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	margin.add_child(v)
	return v


## Space taken by camera cut-outs / gesture bars, in UI units: (top, bottom).
func _safe_insets() -> Vector2:
	var screen := DisplayServer.screen_get_size()
	if not OS.has_feature("mobile") or screen.y <= 0:
		return Vector2.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var k := get_viewport_rect().size.y / float(screen.y)
	return Vector2(safe.position.y * k, maxf(0.0, screen.y - safe.end.y) * k)


func _top_bar(title: String, back: Callable, right: Control = null) -> HBoxContainer:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	top.add_child(_icon_button("back", back))
	var t := _label(title, 52, ACCENT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	if right:
		top.add_child(right)
	else:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(84, 0)
		top.add_child(gap)
	return top


# ================================================================ navigation

func _go(screen: Control, animate := true) -> void:
	for s in [home, levels_screen, shop, settings, game]:
		s.visible = s == screen
	current = screen
	popup.visible = false
	win.visible = false
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if animate:
		screen.modulate.a = 0.0
		screen.position.y = 40.0
		var tw := create_tween().set_parallel()
		tw.tween_property(screen, "modulate:a", 1.0, 0.22)
		tw.tween_property(screen, "position:y", 0.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _go_home() -> void:
	running = false
	_refresh_home()
	_go(home)


func _char() -> Dictionary:
	return Characters.get_info(selected)


func _apply_character() -> void:
	board.cat_tex = Characters.icon(selected)
	board.queue_redraw()
	popup_icon.texture = Characters.icon(selected)
	var animal: String = _char()["animal"]
	rule_labels["color"].text = "1 %s per colour" % animal
	rule_labels["line"].text = "1 %s per row & column" % animal
	rule_labels["touch"].text = "%ss can't touch" % animal.capitalize()
	for k in rule_icons:
		rule_icons[k].queue_redraw()
	stage_view.show_character(selected)
	win_view.show_character(selected)
	stage.queue_redraw()
	_refresh_home()


# ================================================================ home

func _build_home() -> void:
	var v := _screen(14)
	home = v.get_parent() as Control

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.add_child(_pill("coin", str(points), point_labels))
	top.add_child(_pill("star", "0", star_labels))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	top.add_child(_icon_button("gear", func(): _go(settings)))
	v.add_child(top)

	var title := _label("Whisker Grid", 88, ACCENT, true)
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_outline_color", CARD)
	v.add_child(title)
	v.add_child(_label("Find the hidden friends!", 28, SOFT))

	stage = Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size = Vector2(0, 360)
	stage.draw.connect(_draw_stage)
	stage.gui_input.connect(_on_stage_input)
	stage_view = CharacterView.new(selected)
	stage_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(stage_view)
	v.add_child(stage)

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 14)
	stage_name = _label("", 34, INK, true)
	stage_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_row.add_child(stage_name)
	var change := _button("Change", _open_shop, PINK, 60)
	change.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	change.add_theme_font_size_override("font_size", 24)
	_style_button(change, PINK, 30)
	name_row.add_child(change)
	v.add_child(name_row)

	var play: Array = _big_button("Play", "", _on_play, ACCENT, 140, 54)
	play_title = play[1]
	play_sub = play[2]
	v.add_child(play[0])

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var lv: Array = _big_button("Levels", "", _open_levels, GREEN, 112, 32)
	levels_sub = lv[2]
	row.add_child(lv[0])
	var d: Array = _big_button("Daily", "", _on_daily, BLUE, 112, 32)
	daily_btn = d[0]
	daily_sub = d[2]
	row.add_child(daily_btn)
	var s: Array = _big_button("Friends", "", _open_shop, PINK, 112, 32)
	shop_sub = s[2]
	row.add_child(s[0])
	v.add_child(row)


func _on_stage_input(e: InputEvent) -> void:
	var mb := e as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		stage_view.cheer()
		Sfx.play("place", randf_range(1.1, 1.3), -4.0)
		Sfx.vibrate(20)


func _refresh_home() -> void:
	if play_sub == null:
		return
	if level > PuzzleGenerator.LEVEL_COUNT:
		play_title.text = "All done!"
		play_sub.text = "Replay any level for more stars"
	else:
		var size := PuzzleGenerator.size_for_level(level)
		play_title.text = "Play"
		play_sub.text = "Level %d   ·   %d×%d" % [level, size, size]
	var c := _char()
	stage_name.text = "%s the %s" % [c["name"], c["animal"]]
	shop_sub.text = "%d / %d friends" % [owned.size(), Characters.LIST.size()]
	levels_sub.text = "%d / %d stars" % [_total_stars(), PuzzleGenerator.LEVEL_COUNT * 3]
	_update_points_labels()
	for l in star_labels:
		(l as Label).text = str(_total_stars())
	_update_daily()


func _update_daily() -> void:
	var t := Time.get_time_dict_from_system()
	var left: int = 86400 - (int(t.hour) * 3600 + int(t.minute) * 60 + int(t.second))
	var clock := "%02d:%02d:%02d" % [left / 3600, (left / 60) % 60, left % 60]
	var done := daily_done == _today()
	daily_btn.disabled = done
	daily_sub.text = ("Next " if done else "") + clock


func _total_stars() -> int:
	var total := 0
	for k in stars:
		total += int(stars[k])
	return total


# ================================================================ levels map

func _build_levels() -> void:
	var v := _screen(16)
	levels_screen = v.get_parent() as Control
	v.add_child(_top_bar("Levels", _go_home, _pill("star", "0", star_labels)))
	level_scroll = ScrollContainer.new()
	level_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	level_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(level_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	level_scroll.add_child(list)

	for bi in PuzzleGenerator.BANDS.size():
		var band: Array = PuzzleGenerator.BANDS[bi]
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		var size_l := _label("%d×%d" % [band[0], band[0]], 40, INK, true)
		size_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		head.add_child(size_l)
		var tag := PanelContainer.new()
		var tsb := _box(Pal.tiles()[bi % 10], 18, false)
		tsb.content_margin_top = 4
		tsb.content_margin_bottom = 4
		tsb.content_margin_left = 14
		tsb.content_margin_right = 14
		tag.add_theme_stylebox_override("panel", tsb)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var tl := _label(BAND_NAMES[bi], 22, Color.WHITE, true)
		tl.autowrap_mode = TextServer.AUTOWRAP_OFF
		tag.add_child(tl)
		head.add_child(tag)
		var range_l := _label("Levels %d–%d" % [band[1], band[2]], 22, SOFT)
		range_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		range_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(range_l)
		list.add_child(head)

		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 14)
		for lv in range(band[1], band[2] + 1):
			var b := Button.new()
			b.custom_minimum_size = Vector2(110, 124)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for st in ["normal", "hover", "pressed", "disabled", "focus"]:
				b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
			b.draw.connect(_draw_level_tile.bind(b, lv))
			b.pressed.connect(_on_level_tile.bind(lv))
			_juice(b)
			grid.add_child(b)
			level_tiles[lv] = b
		list.add_child(grid)
	list.add_child(_spacer(20))


func _spacer(h := 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if h == 0:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


func _open_levels() -> void:
	for lv in level_tiles:
		(level_tiles[lv] as Button).queue_redraw()
	_refresh_home()
	_go(levels_screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var target: Button = level_tiles[clampi(level, 1, PuzzleGenerator.LEVEL_COUNT)]
	var y := target.get_global_rect().position.y - level_scroll.get_global_rect().position.y + level_scroll.scroll_vertical
	level_scroll.scroll_vertical = int(maxf(0.0, y - 260.0))


func _on_level_tile(lv: int) -> void:
	if lv > level:
		Sfx.play("wrong", 1.3, -6.0)
		var b: Button = level_tiles[lv]
		var tw := create_tween()
		tw.tween_property(b, "rotation", 0.12, 0.05)
		tw.tween_property(b, "rotation", -0.12, 0.08)
		tw.tween_property(b, "rotation", 0.0, 0.05)
		return
	_play_level(lv)


func _draw_level_tile(b: Button, lv: int) -> void:
	var r := Rect2(Vector2(4, 0), Vector2(b.size.x - 8, b.size.x - 8))
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(26)
	sb.corner_detail = 8
	var got := int(stars.get(str(lv), 0))
	var locked := lv > level
	var is_next := lv == level
	var col := CARD
	if locked:
		col = NEUTRAL.lerp(BG, 0.55)
	elif is_next:
		col = ACCENT
	sb.bg_color = col
	sb.border_width_bottom = 6
	sb.border_color = col.darkened(0.18)
	sb.shadow_color = Color(0, 0, 0, 0.12)
	sb.shadow_size = 4 if not locked else 0
	b.draw_style_box(sb, r)
	var ctr := r.get_center() - Vector2(0, 3)
	if locked:
		_draw_lock(b, ctr, 16.0, NEUTRAL.darkened(0.1))
	else:
		var txt := str(lv)
		var fs := 40
		var w := font_bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		b.draw_string(font_bold, ctr + Vector2(-w / 2.0, 14), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color.WHITE if is_next else INK)
	if not locked and not is_next or got > 0:
		for k in 3:
			var p := Vector2(b.size.x / 2.0 + (k - 1) * 26, b.size.x + 4)
			_draw_star(b, p, 11.0, GOLD if k < got else NEUTRAL.lerp(BG, 0.4))


# ================================================================ shop

func _build_shop() -> void:
	var v := _screen(20)
	shop = v.get_parent() as Control
	v.add_child(_top_bar("Friends", _go_home, _pill("coin", str(points), point_labels)))
	v.add_child(_label("Earn coins by solving puzzles, then unlock new friends.\nYour pick appears on the board and home screen.", 24, SOFT))
	coin_ad_btn = _glyph_button("video", _on_coin_ad, GOLD.darkened(0.08), 84, "")
	v.add_child(coin_ad_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	scroll.add_child(grid)
	for info in Characters.LIST:
		var id: String = info["id"]
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)
		var portrait := _drawn(Vector2(0, 200), _draw_shop_portrait.bind(id))
		cv.add_child(portrait)
		cv.add_child(_label(info["name"], 36, INK, true))
		cv.add_child(_label("the " + info["animal"], 22, SOFT))
		var btn := _button("", _on_shop_button.bind(id), ACCENT, 76)
		btn.add_theme_font_size_override("font_size", 26)
		cv.add_child(btn)
		grid.add_child(card)
		shop_cards[id] = {"card": card, "button": btn, "portrait": portrait}
		_juice(card, false)


func _on_coin_ad() -> void:
	if Ads.coin_ads_left() <= 0:
		return
	if await Ads.rewarded("coins"):
		Ads.note_coin_ad()
		_add_points(Ads.COINS_PER_AD, false)
		Sfx.play("unlock")
		_float_text("+%d coins" % Ads.COINS_PER_AD, coin_ad_btn.get_global_rect().get_center() - Vector2(0, 50), GOLD.darkened(0.2), 46)
		_refresh_shop()


func _open_shop() -> void:
	_refresh_shop()
	_go(shop)


func _refresh_shop() -> void:
	for info in Characters.LIST:
		var id: String = info["id"]
		var e: Dictionary = shop_cards[id]
		var card: PanelContainer = e["card"]
		var btn: Button = e["button"]
		var sel := id == selected
		var sb := _box(CARD, 30)
		sb.set_content_margin_all(16)
		if sel:
			sb.border_color = ACCENT
			sb.set_border_width_all(5)
		card.add_theme_stylebox_override("panel", sb)
		if sel:
			btn.text = "Selected"
			btn.disabled = true
		elif owned.has(id):
			btn.text = "Use"
			btn.disabled = false
			_style_button(btn, GREEN)
		else:
			btn.text = "Unlock  %d" % info["price"]
			btn.disabled = points < int(info["price"])
			_style_button(btn, ACCENT)
		(e["portrait"] as Control).queue_redraw()
	var left := Ads.coin_ads_left()
	coin_ad_btn.set_meta("label", ("Free %d coins  (%d left today)" % [Ads.COINS_PER_AD, left]) if left > 0 else "More free coins tomorrow")
	coin_ad_btn.disabled = left <= 0
	coin_ad_btn.queue_redraw()
	_update_points_labels()


func _on_shop_button(id: String) -> void:
	var info := Characters.get_info(id)
	var card: Control = shop_cards[id]["card"]
	if not owned.has(id):
		if points < int(info["price"]):
			return
		points -= int(info["price"])
		shown_points = points
		owned.append(id)
		Sfx.play("unlock")
		_float_text("New friend!", card.get_global_rect().get_center() - Vector2(0, 60), GREEN, 46)
		_confetti(card.get_global_rect().get_center())
	else:
		Sfx.play("place", 1.2, -4.0)
	selected = id
	_save()
	_apply_character()
	_refresh_shop()
	var tw := create_tween()
	tw.tween_property(card, "scale", Vector2(1.06, 1.06), 0.1)
	tw.tween_property(card, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	Sfx.vibrate(30)


func _set_points_text(v: float) -> void:
	for l in point_labels:
		(l as Label).text = str(int(v))


func _update_points_labels() -> void:
	_set_points_text(points)


# ================================================================ settings

func _build_settings() -> void:
	var v := _screen(18)
	settings = v.get_parent() as Control
	v.add_child(_top_bar("Settings", _go_home))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 18)
	scroll.add_child(list)

	# --- sound & feel
	var c1: Array = _card(10)
	c1[1].add_child(_section_title("Sound & feel"))
	c1[1].add_child(_toggle_row("Music", Sfx.music_on, func(on: bool):
		Sfx.set_music(on)
		_save()))
	c1[1].add_child(_toggle_row("Sound effects", Sfx.sfx_on, func(on: bool):
		Sfx.sfx_on = on
		Sfx.play("click")
		_save()))
	c1[1].add_child(_toggle_row("Vibration", Sfx.vibe_on, func(on: bool):
		Sfx.vibe_on = on
		Sfx.vibrate(40)
		_save()))
	list.add_child(c1[0])

	# --- theme picker (only changes when the player taps one)
	var c2: Array = _card(14)
	c2[1].add_child(_section_title("Theme"))
	var tg := GridContainer.new()
	tg.columns = 2
	tg.add_theme_constant_override("h_separation", 14)
	tg.add_theme_constant_override("v_separation", 14)
	for tid in Pal.THEMES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 150)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		b.draw.connect(_draw_theme_swatch.bind(b, tid))
		b.pressed.connect(_on_theme.bind(tid))
		_juice(b)
		tg.add_child(b)
	c2[1].add_child(tg)
	list.add_child(c2[0])

	# --- more
	var c3: Array = _card(14)
	c3[1].add_child(_section_title("More"))
	c3[1].add_child(_button("How to play", _show_help, BLUE, 84))
	c3[1].add_child(_button("Reset progress", _confirm_reset, RED.lerp(NEUTRAL, 0.35), 84))
	list.add_child(c3[0])
	list.add_child(_label("Whisker Grid  v%s\nMade with Godot & Blender" % ProjectSettings.get_setting("application/config/version", "1.0"), 22, SOFT))


func _section_title(text: String) -> Label:
	var l := _label(text, 34, INK, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


func _toggle_row(text: String, on: bool, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	var l := _label(text, 30, INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var sw := Button.new()
	sw.toggle_mode = true
	sw.button_pressed = on
	sw.custom_minimum_size = Vector2(112, 64)
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		sw.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	sw.set_meta("k", 1.0 if on else 0.0)
	sw.draw.connect(_draw_switch.bind(sw))
	sw.toggled.connect(_on_switch.bind(sw, cb))
	h.add_child(sw)
	return h


func _draw_switch(sw: Button) -> void:
	var k: float = sw.get_meta("k")
	var r := Rect2(Vector2(0, 8), Vector2(sw.size.x, sw.size.y - 16))
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(r.size.y / 2))
	sb.bg_color = NEUTRAL.lerp(GREEN, k)
	sw.draw_style_box(sb, r)
	var x := lerpf(r.position.x + r.size.y / 2.0, r.end.x - r.size.y / 2.0, k)
	sw.draw_circle(Vector2(x, r.get_center().y + 2), r.size.y / 2.0 - 5, Color(0, 0, 0, 0.12))
	sw.draw_circle(Vector2(x, r.get_center().y), r.size.y / 2.0 - 5, Color.WHITE)


func _on_switch(pressed: bool, sw: Button, cb: Callable) -> void:
	create_tween().tween_method(_set_switch.bind(sw), float(sw.get_meta("k")), 1.0 if pressed else 0.0, 0.18)
	cb.call(pressed)


func _set_switch(v: float, sw: Button) -> void:
	sw.set_meta("k", v)
	sw.queue_redraw()


func _draw_theme_swatch(b: Button, tid: String) -> void:
	var sel := tid == theme_id
	var r := Rect2(Vector2(4, 4), b.size - Vector2(8, 8))
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(24)
	sb.corner_detail = 8
	sb.bg_color = Pal.preview(tid, "bg")
	sb.border_color = ACCENT if sel else Pal.preview(tid, "neutral")
	sb.set_border_width_all(6 if sel else 2)
	b.draw_style_box(sb, r)
	var tiles: Array = Pal.THEMES[tid]["tiles"]
	for k in 4:
		var tr := Rect2(r.position + Vector2(18 + k * 40, 20), Vector2(34, 34))
		var tsb := StyleBoxFlat.new()
		tsb.set_corner_radius_all(9)
		tsb.bg_color = Color(tiles[k])
		b.draw_style_box(tsb, tr)
	b.draw_circle(r.position + Vector2(r.size.x - 34, 37), 17, Pal.preview(tid, "accent"))
	var name: String = Pal.THEMES[tid]["name"]
	b.draw_string(font_bold, r.position + Vector2(18, r.size.y - 26), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Pal.preview(tid, "ink"))
	if sel:
		b.draw_string(font_body, r.position + Vector2(18, r.size.y - 62), "In use", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Pal.preview(tid, "soft"))


func _on_theme(tid: String) -> void:
	if tid == theme_id:
		return
	theme_id = tid
	_save()
	reopen = "settings"
	get_tree().reload_current_scene.call_deferred()


func _show_help() -> void:
	var a: String = _char()["animal"]
	_show_popup("How to play",
		"Hide one %s in every row, every column and every colour.\n%ss can't touch - not even diagonally.\n\nTap = X    Double-tap = %s    Drag = paint X's\n\nNo mistakes and no hints = 3 stars.\nStars earn coins, and coins unlock friends!" % [a, a.capitalize(), a],
		"Got it!", func(): popup.visible = false)


func _confirm_reset() -> void:
	_show_popup("Reset progress?", "This clears your levels, stars, points and friends. It can't be undone.",
		"Keep my progress", func(): popup.visible = false,
		"Reset", func():
			level = 1
			points = 0
			stars = {}
			owned = ["cat"]
			selected = "cat"
			daily_done = ""
			hints = 3
			_save()
			_apply_character()
			popup.visible = false
			_go_home())


# ================================================================ game screen

func _build_game() -> void:
	var v := _screen(14)
	game = v.get_parent() as Control

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.add_child(_icon_button("back", _leave_game))
	var lv := VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_theme_constant_override("separation", -8)
	level_title = _label("Level", 24, SOFT)
	level_value = _label("1", 44, INK, true)
	lv.add_child(level_title)
	lv.add_child(level_value)
	top.add_child(lv)
	var pv := VBoxContainer.new()
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.add_theme_constant_override("separation", -8)
	pv.add_child(_label("Coins", 24, SOFT))
	var pts := _label("0", 44, RED, true)
	pv.add_child(pts)
	point_labels.append(pts)
	top.add_child(pv)
	time_label = _label("0:00", 30, SOFT, true)
	time_label.custom_minimum_size.x = 84
	top.add_child(time_label)
	v.add_child(top)

	hearts = _drawn(Vector2(0, 40), _draw_hearts)
	v.add_child(hearts)

	var rules := HBoxContainer.new()
	rules.add_theme_constant_override("separation", 10)
	for kind in ["color", "line", "touch"]:
		var card := PanelContainer.new()
		var sb := _box(CARD, 18, false)
		sb.set_content_margin_all(10)
		card.add_theme_stylebox_override("panel", sb)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var icon := _drawn(Vector2(52, 52), _draw_rule_icon.bind(kind))
		h.add_child(icon)
		var l := _label("", 19, INK)
		l.custom_minimum_size.x = 120
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		card.add_child(h)
		rules.add_child(card)
		rule_icons[kind] = icon
		rule_labels[kind] = l
	v.add_child(rules)

	heads = _drawn(Vector2(0, 56), _draw_heads)
	v.add_child(heads)

	board = Board.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.changed.connect(heads.queue_redraw)
	board.cat_placed.connect(_on_cat_placed)
	board.solved.connect(_on_solved)
	v.add_child(board)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	bottom.add_child(_glyph_button("undo", board.undo, BLUE))
	bottom.add_child(_glyph_button("erase", _on_clear_x, NEUTRAL))
	hint_button = _glyph_button("bulb", _on_hint, GREEN)
	bottom.add_child(hint_button)
	v.add_child(bottom)


func _on_clear_x() -> void:
	board.clear_marks()
	Sfx.play("erase")


func _leave_game() -> void:
	if daily:
		_go_home()
	else:
		_open_levels()


# ================================================================ popup

func _build_popup() -> void:
	popup = ColorRect.new()
	(popup as ColorRect).color = Color(0.1, 0.07, 0.05, 0.5)
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.visible = false
	add_child(popup)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)
	var panel := PanelContainer.new()
	var pbox := _box(BG, 44)
	pbox.set_content_margin_all(40)
	panel.add_theme_stylebox_override("panel", pbox)
	panel.custom_minimum_size = Vector2(600, 0)
	center.add_child(panel)
	popup_panel = panel
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 18)
	panel.add_child(pv)
	popup_icon = TextureRect.new()
	popup_icon.custom_minimum_size = Vector2(0, 150)
	popup_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	popup_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pv.add_child(popup_icon)
	popup_title = _label("", 52, ACCENT, true)
	pv.add_child(popup_title)
	popup_text = _label("", 28)
	pv.add_child(popup_text)
	popup_primary = _button("", func(): popup_actions[0].call())
	pv.add_child(popup_primary)
	popup_secondary = _button("", func(): popup_actions[1].call(), NEUTRAL, 76)
	popup_secondary.add_theme_font_size_override("font_size", 26)
	pv.add_child(popup_secondary)


func _show_popup(title: String, text: String, primary: String, action: Callable,
		secondary := "", action2 := Callable(), title_color := Color()) -> void:
	popup_title.text = title
	popup_title.add_theme_color_override("font_color", ACCENT if title_color == Color() else title_color)
	popup_text.text = text
	popup_primary.text = primary
	popup_secondary.text = secondary
	popup_secondary.visible = secondary != ""
	popup_actions = [action, action2]
	popup.visible = true
	popup.modulate.a = 0.0
	create_tween().tween_property(popup, "modulate:a", 1.0, 0.18)
	popup_panel.pivot_offset = popup_panel.size / 2.0
	popup_panel.scale = Vector2(0.75, 0.75)
	create_tween().tween_property(popup_panel, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ================================================================ level complete celebration

func _build_win() -> void:
	win = ColorRect.new()
	(win as ColorRect).color = Color(0.1, 0.07, 0.05, 0.55)
	win.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.visible = false
	add_child(win)
	win_rays = Control.new()
	win_rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_rays.draw.connect(_draw_rays)
	win.add_child(win_rays)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.add_child(center)
	var panel := PanelContainer.new()
	var pbox := _box(BG, 48)
	pbox.set_content_margin_all(34)
	pbox.content_margin_top = 10
	panel.add_theme_stylebox_override("panel", pbox)
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	win_panel = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	win_view = CharacterView.new(selected, true, 1.25)
	win_view.custom_minimum_size = Vector2(0, 320)
	v.add_child(win_view)
	win_title = _label("", 64, ACCENT, true)
	win_title.add_theme_constant_override("outline_size", 12)
	win_title.add_theme_color_override("font_outline_color", CARD)
	v.add_child(win_title)
	win_sub = _label("", 30, INK, true)
	v.add_child(win_sub)
	win_stars = _drawn(Vector2(0, 96), _draw_win_stars)
	v.add_child(win_stars)
	win_stats = _label("", 26, SOFT)
	v.add_child(win_stats)
	win_unlock = _label("", 22, SOFT)
	v.add_child(win_unlock)
	win_bar = _drawn(Vector2(0, 22), _draw_unlock_bar)
	v.add_child(win_bar)
	v.add_child(_spacer(4))
	win_primary = _button("Next level", func(): win_next.call(), ACCENT, 104)
	win_primary.add_theme_font_size_override("font_size", 40)
	v.add_child(win_primary)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	win_replay = _glyph_button("replay", func(): _play_level(playing), NEUTRAL, 84)
	win_replay.size_flags_stretch_ratio = 0.55
	row.add_child(win_replay)
	win_double = _glyph_button("video", _on_double, PINK, 84, "x2 coins")
	row.add_child(win_double)
	win_levels = _glyph_button("grid", _open_levels, BLUE, 84)
	win_levels.size_flags_stretch_ratio = 0.55
	row.add_child(win_levels)
	v.add_child(row)


func _celebrate(title: String, sub: String, star_count: int, primary: String, next: Callable) -> void:
	win_title.text = title
	win_sub.text = sub
	win_star_count = star_count
	win_star_anim = [0.0, 0.0, 0.0]
	win_stats.text = "Time %s     ·     +%d coins" % [_fmt_time(elapsed), earned]
	win_double.disabled = false
	win_double.set_meta("label", "x2 coins")
	win_double.queue_redraw()
	win_primary.text = primary
	win_next = next
	win_replay.visible = not daily
	win_levels.visible = not daily
	# progress towards the next friend
	win_unlock.text = ""
	win_unlock_frac = -1.0
	for info in Characters.LIST:
		if not owned.has(info["id"]):
			var price: int = int(info["price"])
			win_unlock_frac = clampf(float(points) / price, 0.0, 1.0)
			win_unlock.text = ("%s the %s is ready to unlock!" % [info["name"], info["animal"]]) if points >= price \
				else ("Next friend: %s  ·  %d / %d coins" % [info["name"], points, price])
			break
	win_bar.visible = win_unlock_frac >= 0.0
	win.visible = true
	win.modulate.a = 0.0
	create_tween().tween_property(win, "modulate:a", 1.0, 0.25)
	win_panel.pivot_offset = win_panel.size / 2.0
	win_panel.scale = Vector2(0.6, 0.6)
	create_tween().tween_property(win_panel, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	win_view.cheer()
	Sfx.play("win")
	Sfx.vibrate(60)
	var vp := get_viewport_rect().size
	_confetti(Vector2(vp.x * 0.2, vp.y * 0.55))
	_confetti(Vector2(vp.x * 0.8, vp.y * 0.55))
	get_tree().create_timer(0.45).timeout.connect(func(): _confetti(Vector2(vp.x * 0.5, vp.y * 0.35)))
	for k in 3:
		get_tree().create_timer(0.55 + k * 0.32).timeout.connect(_pop_star.bind(k))


func _pop_star(k: int) -> void:
	if not win.visible:
		return
	if k < win_star_count:
		Sfx.play("star", 1.0 + k * 0.12)
		Sfx.vibrate(25)
	create_tween().tween_method(_set_star_anim.bind(k), 0.0, 1.0, 0.45)


func _set_star_anim(t: float, k: int) -> void:
	win_star_anim[k] = t
	win_stars.queue_redraw()


# ================================================================ drawing

func _draw_backdrop() -> void:
	var step := 120.0
	var off := Vector2(fmod(bg_time * 10.0, step), fmod(bg_time * 6.0, step))
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(14)
	var tiles := Pal.tiles()
	var alpha := 0.09 if Pal.dark() else 0.13
	var cols := int(backdrop.size.x / step) + 2
	var rows := int(backdrop.size.y / step) + 2
	for r in range(-1, rows):
		for c in range(-1, cols):
			var k := posmod(r * 3 + c * 5, tiles.size())
			sb.bg_color = Color(tiles[k], alpha)
			var p := Vector2(c * step, r * step) + off + Vector2((r % 2) * step / 2.0, 0)
			backdrop.draw_style_box(sb, Rect2(p, Vector2(54, 54)))
	if Pal.dark():   # twinkling stars for the night theme
		for i in 40:
			var p := Vector2(fposmod(i * 197.3, backdrop.size.x), fposmod(i * 311.7, backdrop.size.y))
			var a := 0.25 + 0.25 * sin(bg_time * 1.5 + i)
			backdrop.draw_circle(p, 2.0 + (i % 3), Color(1, 1, 0.85, a))


func _draw_stage(_c: Control = null) -> void:
	var s := stage.size
	var col: Color = _char()["color"]
	var center := Vector2(s.x / 2.0, s.y * 0.52)
	var r := minf(s.x, s.y) * 0.44
	stage.draw_circle(center, r, Color(col, 0.2))
	stage.draw_circle(center, r * 0.78, Color(col, 0.18))
	var pts := PackedVector2Array()
	for k in 32:
		var a := TAU * k / 32.0
		pts.append(Vector2(s.x / 2.0, s.y * 0.9) + Vector2(cos(a) * r * 0.55, sin(a) * r * 0.1))
	stage.draw_colored_polygon(pts, Color(0, 0, 0, 0.12))


func _draw_rays() -> void:
	var c := win_rays.size / 2.0 - Vector2(0, 230)
	var rot := bg_time * 0.25
	for k in 14:
		var a := rot + TAU * k / 14.0
		var w := 0.11
		var pts := PackedVector2Array([c, c + Vector2(cos(a - w), sin(a - w)) * 1400.0, c + Vector2(cos(a + w), sin(a + w)) * 1400.0])
		win_rays.draw_colored_polygon(pts, Color(GOLD, 0.16))


func _draw_win_stars(c: Control) -> void:
	for k in 3:
		var big := 40.0 if k == 1 else 32.0
		var p := Vector2(c.size.x / 2.0 + (k - 1) * 96, c.size.y / 2.0 + (0 if k == 1 else 10))
		_draw_star(c, p, big, NEUTRAL.lerp(BG, 0.35))
		var t: float = win_star_anim[k]
		if k < win_star_count and t > 0.0:
			var s: float = big * (1.0 + sin(t * PI) * 0.45) * minf(1.0, t * 3.0)
			_draw_star(c, p, s, GOLD)
			_draw_star(c, p + Vector2(-s * 0.18, -s * 0.2), s * 0.28, Color(1, 1, 1, 0.55))


func _draw_unlock_bar(c: Control) -> void:
	var r := Rect2(Vector2(40, 4), Vector2(c.size.x - 80, 14))
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(7)
	sb.bg_color = NEUTRAL.lerp(BG, 0.5)
	c.draw_style_box(sb, r)
	sb.bg_color = PINK
	c.draw_style_box(sb, Rect2(r.position, Vector2(maxf(14.0, r.size.x * win_unlock_frac), r.size.y)))


func _draw_shop_portrait(c: Control, id: String) -> void:
	var info := Characters.get_info(id)
	var center := c.size / 2.0
	var r := minf(c.size.x, c.size.y) * 0.46
	c.draw_circle(center, r, Color(info["color"], 0.35))
	var sz := Vector2(r, r) * 1.85
	var unlocked := owned.has(id)
	c.draw_texture_rect(Characters.icon(id), Rect2(center - sz / 2.0, sz), false,
		Color.WHITE if unlocked else Color(0.25, 0.22, 0.22, 0.55))
	if not unlocked:
		var lc := Vector2(center.x + r * 0.62, center.y + r * 0.62)
		c.draw_circle(lc, 26, INK)
		_draw_lock(c, lc, 11.0, Color.WHITE)


func _draw_lock(c: CanvasItem, ctr: Vector2, s: float, col: Color) -> void:
	c.draw_arc(ctr + Vector2(0, -s * 0.5), s * 0.75, PI, TAU, 16, col, s * 0.35, true)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(s * 0.3))
	sb.bg_color = col
	c.draw_style_box(sb, Rect2(ctr + Vector2(-s, -s * 0.5), Vector2(s * 2, s * 1.5)))


func _draw_paw(c: Control, center: Vector2, r: float, col: Color) -> void:
	c.draw_circle(center + Vector2(0, r * 0.28), r * 0.48, col)
	for k in 4:
		var a := deg_to_rad(-150 + k * 40)
		c.draw_circle(center + Vector2(cos(a), sin(a)) * r * 0.62 + Vector2(0, r * 0.1), r * 0.2, col)


func _draw_star(c: CanvasItem, center: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI / 2.0 + TAU * k / 10.0
		var rr := r if k % 2 == 0 else r * 0.48
		pts.append(center + Vector2(cos(a), sin(a)) * rr)
	c.draw_colored_polygon(pts, col)


func _draw_hearts(c: Control) -> void:
	var r := 15.0
	var spacing := 52.0
	var start := c.size.x / 2.0 - spacing * (MAX_LIVES - 1) / 2.0
	for i in MAX_LIVES:
		var center := Vector2(start + i * spacing, c.size.y / 2.0)
		var col := RED if i < lives else NEUTRAL.lerp(BG, 0.4)
		var pts := PackedVector2Array()
		for k in 32:
			var t := TAU * k / 32.0
			var x := 16.0 * pow(sin(t), 3)
			var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
			pts.append(center + Vector2(x, -y) * (r / 16.0))
		c.draw_colored_polygon(pts, col)


func _draw_rule_icon(c: Control, kind: String) -> void:
	var tex := Characters.icon(selected)
	var cells := 2 if kind == "color" else 3
	var s := c.size.x / cells
	var tiles := Pal.tiles()
	for r in cells:
		for k in cells:
			var rect := Rect2(Vector2(k, r) * s, Vector2(s, s)).grow(-1.0)
			c.draw_rect(rect, tiles[0] if kind == "color" else NEUTRAL)
			var mid := 0 if kind == "color" else 1
			var is_main := r == mid and k == mid
			var is_x := not is_main
			if kind == "line":
				is_x = (r == 1 or k == 1) and not is_main
			if is_main:
				c.draw_texture_rect(tex, rect.grow(3), false)
			elif is_x:
				var d := s * 0.2
				var ctr := rect.get_center()
				c.draw_line(ctr - Vector2(d, d), ctr + Vector2(d, d), Color.WHITE, 2.0, true)
				c.draw_line(ctr + Vector2(-d, d), ctr + Vector2(d, -d), Color.WHITE, 2.0, true)


func _draw_heads(c: Control) -> void:
	if board == null or board.state.is_empty():
		return
	var tex := Characters.icon(selected)
	var n := board.n
	var d := minf(52.0, (c.size.x - 6.0 * (n - 1)) / n)
	var spacing := d + 6.0
	var start := c.size.x / 2.0 - spacing * (n - 1) / 2.0
	for reg in n:
		var center := Vector2(start + reg * spacing, c.size.y / 2.0)
		var col := board.region_color(reg)
		var found := board.found_regions.has(reg)
		var k := 1.0
		if head_pop.has(reg):
			k += sin(head_pop[reg] / 0.35 * PI) * 0.35
		c.draw_circle(center, d / 2.0 * k, col if found else Color(col, 0.35))
		var sz := Vector2(d, d) * 1.05 * k
		c.draw_texture_rect(tex, Rect2(center - sz / 2.0, sz), false, Color(1, 1, 1, 1.0 if found else 0.22))


# ================================================================ game flow

func _on_play() -> void:
	if level > PuzzleGenerator.LEVEL_COUNT:
		_open_levels()
	else:
		_play_level(level)


func _play_level(lv: int) -> void:
	daily = false
	playing = lv
	_begin(PuzzleGenerator.campaign_level(lv), lv)


func _on_daily() -> void:
	daily = true
	var d := Time.get_date_dict_from_system()
	var seed_value: int = int(d.year) * 10000 + int(d.month) * 100 + int(d.day)
	_begin(generator.generate(7, seed_value), seed_value)


func _begin(puzzle: Dictionary, color_seed: int) -> void:
	board.setup(puzzle, color_seed)
	lives = MAX_LIVES
	revived = false
	doubled = false
	hints_used = 0
	mistakes = 0
	earned = 0
	elapsed = 0.0
	last_find_time = 0.0
	running = true
	level_title.text = "Daily" if daily else "Level"
	level_value.text = _today().substr(5) if daily else str(playing)
	shown_points = points
	_update_points_labels()
	time_label.text = "0:00"
	_refresh_hud()
	_go(game)
	board.pivot_offset = board.size / 2.0
	board.scale = Vector2(0.9, 0.9)
	board.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(board, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(board, "modulate:a", 1.0, 0.25)


func _restart() -> void:
	if daily:
		_on_daily()
	else:
		_play_level(playing)


func _refresh_hud() -> void:
	hint_button.set_meta("badge", str(hints) if hints > 0 else "ad")
	hint_button.queue_redraw()
	hearts.queue_redraw()
	heads.queue_redraw()


func _on_cat_placed(idx: int, correct: bool, rule: String) -> void:
	var pos := board.cell_center_global(idx)
	if correct:
		last_find_time = elapsed
		if not hinting:
			_float_text(PRAISE.pick_random(), pos + Vector2(0, -74), ACCENT, 50)
		head_pop[board.regions[idx]] = 0.35
	else:
		lives -= 1
		mistakes += 1
		var msg := {"touch": "Too close!", "line": "Row / column taken!", "color": "Colour taken!"}
		_float_text(msg.get(rule, "Not here!"), pos + Vector2(0, -50), RED, 40)
		if rule_icons.has(rule):
			var card: Control = (rule_icons[rule] as Control).get_parent().get_parent()
			card.modulate = Color(1.0, 0.5, 0.5)
			create_tween().tween_property(card, "modulate", Color.WHITE, 0.9)
		var tw := create_tween()
		tw.tween_property(hearts, "position:x", hearts.position.x + 10, 0.05)
		tw.tween_property(hearts, "position:x", hearts.position.x - 10, 0.08)
		tw.tween_property(hearts, "position:x", hearts.position.x, 0.05)
		if lives <= 0:
			running = false
			board.locked = true
			await get_tree().create_timer(0.7).timeout
			Sfx.play("lose")
			if not revived:
				_show_popup("Out of hearts", "Watch a short video to get 1 heart\nand keep your progress.", "Keep going (+1 heart)",
					_revive, "Start over", _restart, RED)
			else:
				_show_popup("Out of hearts", "Those friends are good at hiding.\nHave another go!", "Try again", _restart,
					"Home" if daily else "Levels", _go_home if daily else _open_levels, RED)
	_refresh_hud()


func _on_hint() -> void:
	if board.locked:
		return
	if hints > 0:
		hints -= 1
		_save()
		_give_hint()
		return
	_show_popup("Need a hint?", "Watch a short video for a free hint,\nor spend %d coins." % HINT_COST,
		"Watch video", _hint_from_video,
		("Use %d coins" % HINT_COST) if points >= HINT_COST else "Not now", _hint_from_coins)


func _hint_from_video() -> void:
	popup.visible = false
	if await Ads.rewarded("hint"):
		_give_hint()


func _hint_from_coins() -> void:
	popup.visible = false
	if points < HINT_COST:
		return
	_add_points(-HINT_COST, false)
	_give_hint()


func _give_hint() -> void:
	hints_used += 1
	hinting = true
	Sfx.play("hint")
	board.hint()
	hinting = false
	_refresh_hud()


func _revive() -> void:
	popup.visible = false
	if await Ads.rewarded("revive"):
		revived = true
		lives = 1
		board.locked = false
		running = true
		Sfx.play("unlock")
		_refresh_hud()
	else:   # no video: fall back to the normal out-of-hearts choice
		revived = true
		_show_popup("Out of hearts", "Those friends are good at hiding.
Have another go!", "Try again", _restart,
			"Home" if daily else "Levels", _go_home if daily else _open_levels, RED)


func _add_points(pts: int, count_earned := true) -> void:
	points = maxi(0, points + pts)
	if count_earned:
		earned += pts
	create_tween().tween_method(_set_points_text, shown_points, float(points), 0.5)
	shown_points = points
	_save()


func _on_solved() -> void:
	running = false
	var penalty := mistakes + hints_used
	var got := 3 if penalty == 0 else (2 if penalty <= 2 else 1)
	if daily:
		level_reward = 60 + got * 10
		_add_points(level_reward)
		daily_done = _today()
		_save()
		await get_tree().create_timer(1.1).timeout
		_celebrate("Daily done!", "Come back tomorrow for a new one", got, "Home", _go_home)
		return
	var first := playing >= level
	level_reward = (20 + got * 10) if first else (5 + got * 5)
	_add_points(level_reward)
	Ads.level_completed()
	stars[str(playing)] = maxi(got, int(stars.get(str(playing), 0)))
	if first:
		level = playing + 1
	_save()
	await get_tree().create_timer(1.1).timeout
	if playing >= PuzzleGenerator.LEVEL_COUNT:
		_celebrate("Champion!", "You beat all 100 levels!", got, "Levels", _open_levels)
	else:
		_celebrate(_char()["win"], "Level %d complete" % playing, got, "Next level", _next_level)


## Next level, with a break ad only when the frequency rules allow it.
func _next_level() -> void:
	win.visible = false
	await Ads.maybe_interstitial(playing + 1)
	_play_level(playing + 1)


func _on_double() -> void:
	if doubled:
		return
	if await Ads.rewarded("double"):
		doubled = true
		_add_points(level_reward)
		win_stats.text = "Time %s     ·     +%d coins  (doubled!)" % [_fmt_time(elapsed), earned]
		win_double.disabled = true
		win_double.set_meta("label", "Doubled")
		win_double.queue_redraw()
		Sfx.play("unlock")
		_confetti(win_double.get_global_rect().get_center())


func _float_text(text: String, global_pos: Vector2, color: Color, font_size: int) -> void:
	var l := _label(text, font_size, color, true)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_constant_override("outline_size", 12)
	l.add_theme_color_override("font_outline_color", CARD)
	fx.add_child(l)
	l.reset_size()
	var local := fx.get_global_transform().affine_inverse() * global_pos
	l.position = local - l.size / 2.0
	l.position.x = clampf(l.position.x, 8.0, maxf(8.0, fx.size.x - l.size.x - 8.0))
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2(0.6, 0.6)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 90.0, 1.1).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.7)
	tw.chain().tween_callback(l.queue_free)


func _confetti(global_pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = fx.get_global_transform().affine_inverse() * global_pos
	p.one_shot = true
	p.amount = 90
	p.lifetime = 1.8
	p.explosiveness = 0.95
	p.direction = Vector2.UP
	p.spread = 65.0
	p.initial_velocity_min = 500.0
	p.initial_velocity_max = 950.0
	p.gravity = Vector2(0, 1100)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 7.0
	p.scale_amount_max = 14.0
	var tiles := Pal.tiles()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	grad.colors = PackedColorArray([tiles[0], tiles[2], tiles[3], tiles[1], tiles[4], GOLD])
	p.color_initial_ramp = grad
	fx.add_child(p)
	p.emitting = true
	get_tree().create_timer(2.2).timeout.connect(p.queue_free)


# ================================================================ helpers

func _today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func _fmt_time(t: float) -> String:
	var s := int(t)
	return "%d:%02d" % [s / 60, s % 60]


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		level = int(cfg.get_value("progress", "level", 1))
		points = int(cfg.get_value("progress", "score", 0))
		stars = cfg.get_value("progress", "stars", {})
		daily_done = str(cfg.get_value("progress", "daily_done", ""))
		owned = cfg.get_value("progress", "owned", ["cat"])
		selected = str(cfg.get_value("progress", "selected", "cat"))
		theme_id = str(cfg.get_value("settings", "theme", "cream"))
		hints = int(cfg.get_value("progress", "hints", 3))
		gift_date = str(cfg.get_value("progress", "gift_date", ""))
		Sfx.music_on = bool(cfg.get_value("settings", "music", true))
		Sfx.sfx_on = bool(cfg.get_value("settings", "sfx", true))
		Sfx.vibe_on = bool(cfg.get_value("settings", "vibration", true))
	level = clampi(level, 1, PuzzleGenerator.LEVEL_COUNT + 1)
	if not owned.has(selected):
		selected = "cat"


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "level", level)
	cfg.set_value("progress", "score", points)
	cfg.set_value("progress", "stars", stars)
	cfg.set_value("progress", "daily_done", daily_done)
	cfg.set_value("progress", "owned", owned)
	cfg.set_value("progress", "selected", selected)
	cfg.set_value("progress", "hints", hints)
	cfg.set_value("progress", "gift_date", gift_date)
	cfg.set_value("settings", "theme", theme_id)
	cfg.set_value("settings", "music", Sfx.music_on)
	cfg.set_value("settings", "sfx", Sfx.sfx_on)
	cfg.set_value("settings", "vibration", Sfx.vibe_on)
	cfg.save(SAVE_PATH)

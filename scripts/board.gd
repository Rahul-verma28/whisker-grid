class_name Board
extends Control
## Draws the puzzle grid and handles touch input.
##   Tap        -> toggle X
##   Double-tap -> place a cat (checked instantly: right cats lock in, wrong ones cost a life)
##   Drag       -> paint X's (or erase them if the drag starts on an X)

signal changed
signal solved
signal cat_placed(idx: int, correct: bool, broken_rule: String)

const EMPTY := 0
const MARK := 1
const CAT := 2
const DOUBLE_TAP_SEC := 0.32

const PALETTE := [
	Color("#f29bb2"), Color("#8fd19e"), Color("#f5c85c"),
	Color("#8cb8ee"), Color("#b99be6"), Color("#f5a46b"),
	Color("#6fcbc3"), Color("#d4d77a"), Color("#d2a98c"),
]

var n: int = 5
var regions: Array = []
var solution: Array = []
var colors: Array = []
var state: Array = []
var locked := false
var found_regions := {}         # region -> true

var cat_tex: Texture2D
var _history: Array = []        # Array of actions; action = Array of [idx, old_value]
var _action: Array = []
var _press_idx := -1
var _last_idx := -1
var _dragging := false
var _drag_value := -1
var _last_tap_idx := -1
var _last_tap_time := -10.0
var _last_tap_old := EMPTY
var _pop := {}                  # idx -> time left (cat pop-in)
var _shake := {}                # idx -> time left (wrong cat)
var _glow := {}                 # region -> time left (region cleared flash)
var _xpop := {}                 # idx -> time left (X mark pop-in)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if cat_tex == null:
		cat_tex = Characters.icon("cat")
	resized.connect(queue_redraw)


func setup(puzzle: Dictionary, color_seed: int) -> void:
	n = puzzle["size"]
	regions = puzzle["regions"]
	solution = puzzle["solution"]
	var rng := RandomNumberGenerator.new()
	rng.seed = color_seed
	colors = Pal.tiles()
	for i in range(colors.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = colors[i]
		colors[i] = colors[j]
		colors[j] = t
	state = []
	state.resize(n * n)
	state.fill(EMPTY)
	found_regions.clear()
	_history.clear()
	_pop.clear()
	_shake.clear()
	_glow.clear()
	_xpop.clear()
	_last_tap_idx = -1
	locked = false
	queue_redraw()
	changed.emit()


func region_color(region: int) -> Color:
	return colors[region % colors.size()]


func cell_center_global(idx: int) -> Vector2:
	var cs := _cell_size()
	return get_global_transform() * (_origin() + Vector2(idx % n + 0.5, idx / n + 0.5) * cs)


func cat_count() -> int:
	return state.count(CAT)


# ------------------------------------------------------------------ geometry

func _cell_size() -> float:
	return floor(min(size.x, size.y) / n)


func _origin() -> Vector2:
	var cs := _cell_size()
	return ((size - Vector2(cs * n, cs * n)) / 2.0).floor()


func _cell_at(pos: Vector2) -> int:
	var cs := _cell_size()
	var p := (pos - _origin()) / cs
	if p.x < 0 or p.y < 0 or p.x >= n or p.y >= n:
		return -1
	return int(p.y) * n + int(p.x)


# ------------------------------------------------------------------ input

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _gui_input(event: InputEvent) -> void:
	if locked or state.is_empty():
		return
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			var idx := _cell_at(mb.position)
			if idx < 0:
				return
			_press_idx = idx
			_last_idx = idx
			_dragging = false
			_action = []
			match int(state[idx]):
				EMPTY: _drag_value = MARK
				MARK: _drag_value = EMPTY
				_: _drag_value = -1
		elif _press_idx >= 0:
			if not _dragging:
				_tap(_press_idx)
			_commit()
			_press_idx = -1
		accept_event()
	elif mm and _press_idx >= 0:
		# Walk the segment since the last event so fast swipes don't skip cells.
		var from := mm.position - mm.relative
		var steps := maxi(1, ceili(mm.relative.length() / (_cell_size() * 0.25)))
		for s in range(1, steps + 1):
			var idx := _cell_at(from.lerp(mm.position, float(s) / steps))
			if idx >= 0 and idx != _last_idx:
				if not _dragging:
					_dragging = true
					_last_tap_idx = -1
					_paint(_press_idx)
				_paint(idx)
				_last_idx = idx
		accept_event()


func _tap(idx: int) -> void:
	if state[idx] == CAT:
		return
	var t := _now()
	if idx == _last_tap_idx and t - _last_tap_time < DOUBLE_TAP_SEC:
		# second tap of a double-tap: undo the first tap's X, then try a cat
		_last_tap_idx = -1
		if not _history.is_empty():
			_history.pop_back()
		state[idx] = _last_tap_old
		try_cat(idx)
		return
	_last_tap_idx = idx
	_last_tap_time = t
	_last_tap_old = state[idx]
	var marking: bool = state[idx] == EMPTY
	_set_cell(idx, MARK if marking else EMPTY)
	Sfx.play("mark" if marking else "erase", randf_range(0.95, 1.08))
	Sfx.vibrate(12)


func _paint(idx: int) -> void:
	if _drag_value < 0:
		return
	if _drag_value == MARK and state[idx] == EMPTY:
		_set_cell(idx, MARK)
		Sfx.play("mark", randf_range(0.9, 1.15), -4.0)
	elif _drag_value == EMPTY and state[idx] == MARK:
		_set_cell(idx, EMPTY)
		Sfx.play("erase", randf_range(0.9, 1.15), -4.0)


func _set_cell(idx: int, value: int) -> void:
	if state[idx] == value:
		return
	_action.append([idx, state[idx]])
	state[idx] = value
	if value == MARK:
		_xpop[idx] = 0.14
		set_process(true)
	queue_redraw()
	changed.emit()


func _commit() -> void:
	if not _action.is_empty():
		_history.append(_action)
	_action = []


## Places a cat if it's the right cell; otherwise reports which rule it broke.
func try_cat(idx: int) -> bool:
	var r := idx / n
	if int(solution[r]) == idx % n:
		state[idx] = CAT
		_pop[idx] = 0.35
		var reg: int = regions[idx]
		found_regions[reg] = true
		_glow[reg] = 0.6
		_strip_history(idx)
		Sfx.play("place", randf_range(0.97, 1.05))
		Sfx.vibrate(35)
		set_process(true)
		queue_redraw()
		cat_placed.emit(idx, true, "")
		changed.emit()
		if cat_count() == n:
			locked = true
			for i in n * n:
				if state[i] == CAT:
					_pop[i] = 0.35 + 0.5 + (i / n) * 0.09   # a bouncing wave, row by row
			solved.emit()
		return true
	state[idx] = MARK      # wrong spot: leave an X so the player learns from it
	_strip_history(idx)
	_shake[idx] = 0.45
	Sfx.play("wrong")
	Sfx.vibrate(120)
	set_process(true)
	queue_redraw()
	cat_placed.emit(idx, false, _broken_rule(idx))
	changed.emit()
	return false


func _strip_history(idx: int) -> void:
	# cats and judged cells are final, so undo should never touch them
	for act in _history:
		for i in range(act.size() - 1, -1, -1):
			if act[i][0] == idx:
				act.remove_at(i)
	_history = _history.filter(func(a): return not a.is_empty())


func _broken_rule(idx: int) -> String:
	var r := idx / n
	var c := idx % n
	for i in n * n:
		if state[i] != CAT:
			continue
		var ri := i / n
		var ci := i % n
		if absi(ri - r) <= 1 and absi(ci - c) <= 1:
			return "touch"
		if ri == r or ci == c:
			return "line"
		if regions[i] == regions[idx]:
			return "color"
	return ""


# ------------------------------------------------------------------ actions

func undo() -> void:
	if locked or _history.is_empty():
		return
	var act: Array = _history.pop_back()
	for i in range(act.size() - 1, -1, -1):
		state[act[i][0]] = act[i][1]
	queue_redraw()
	changed.emit()


func clear_marks() -> void:
	if locked:
		return
	_action = []
	for i in n * n:
		if state[i] == MARK:
			_set_cell(i, EMPTY)
	_commit()


## Reveals one correct cat. Returns its index, or -1 if nothing to do.
func hint() -> int:
	if locked:
		return -1
	for r in n:
		var good := r * n + int(solution[r])
		if state[good] != CAT:
			try_cat(good)
			return good
	return -1


# ------------------------------------------------------------------ drawing

func _process(delta: float) -> void:
	var busy := false
	for d in [_pop, _shake, _glow, _xpop]:
		for k in d.keys():
			d[k] -= delta
			if d[k] <= 0.0:
				d.erase(k)
		busy = busy or not d.is_empty()
	queue_redraw()
	if not busy:
		set_process(false)


func _draw() -> void:
	if state.is_empty():
		return
	var cs := _cell_size()
	var o := _origin()
	var total := cs * n
	var gap := maxf(2.0, round(cs * 0.06))
	var radius := int(cs * 0.16)

	# board backing card
	var back := StyleBoxFlat.new()
	back.bg_color = Pal.c("board")
	back.set_corner_radius_all(int(cs * 0.3))
	back.shadow_color = Color(0.3, 0.2, 0.1, 0.15)
	back.shadow_size = 10
	back.shadow_offset = Vector2(0, 6)
	draw_style_box(back, Rect2(o - Vector2(gap * 2, gap * 2), Vector2(total, total) + Vector2(gap * 4, gap * 4)))

	var tile := StyleBoxFlat.new()
	tile.set_corner_radius_all(radius)
	tile.corner_detail = 5
	for i in n * n:
		var r := i / n
		var c := i % n
		var reg: int = regions[i]
		var rect := Rect2(o + Vector2(c, r) * cs, Vector2(cs, cs)).grow(-gap / 2.0)
		if _shake.has(i):
			rect.position.x += sin(_shake[i] * 50.0) * cs * 0.08
		var col := region_color(reg)
		if found_regions.has(reg):
			col = col.lerp(Color.WHITE, 0.25)
		if _glow.has(reg):
			col = col.lerp(Color.WHITE, _glow[reg] / 0.6 * 0.7)
		if _shake.has(i):
			col = col.lerp(Color("#ff4d4d"), 0.7)
		# soft bottom edge gives the tiles a little depth
		tile.bg_color = col.darkened(0.12)
		draw_style_box(tile, Rect2(rect.position + Vector2(0, gap * 0.6), rect.size))
		tile.bg_color = col
		draw_style_box(tile, rect)

		var center := rect.get_center()
		match int(state[i]):
			MARK:
				var k: float = 1.0 - (float(_xpop[i]) / 0.14 if _xpop.has(i) else 0.0)
				var d := cs * 0.17 * (0.4 + 0.6 * k)
				var w := maxf(3.0, cs * 0.09) * (0.5 + 0.5 * k)
				var xc := Color(1, 1, 1, 0.95)
				draw_line(center - Vector2(d, d), center + Vector2(d, d), xc, w, true)
				draw_line(center + Vector2(-d, d), center + Vector2(d, -d), xc, w, true)
			CAT:
				var s := 0.9
				if _pop.has(i):
					s += sin(minf(float(_pop[i]), 0.35) / 0.35 * PI) * 0.25
				var sz := Vector2(cs, cs) * s
				draw_texture_rect(cat_tex, Rect2(center - sz / 2.0, sz), false)

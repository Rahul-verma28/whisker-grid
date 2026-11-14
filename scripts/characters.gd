class_name Characters
extends RefCounted
## Every buyable character. Art lives in assets/characters/<id>_icon.png and <id>.glb
## (made by blender/make_characters.py). To add one: build it in that script, then add a row here.

const LIST := [
	{"id": "cat", "name": "Mochi", "animal": "cat", "price": 0,
		"color": Color("#f5a46b"), "win": "Purr-fect!"},
	{"id": "dog", "name": "Biscuit", "animal": "dog", "price": 600,
		"color": Color("#d9a46f"), "win": "Paw-some!"},
	{"id": "bunny", "name": "Clover", "animal": "bunny", "price": 1200,
		"color": Color("#f2a7bf"), "win": "Hop-tastic!"},
	{"id": "mouse", "name": "Pip", "animal": "mouse", "price": 2000,
		"color": Color("#a9a9c4"), "win": "Squeak-tacular!"},
]

static var _icons := {}


static func get_info(id: String) -> Dictionary:
	for c in LIST:
		if c["id"] == id:
			return c
	return LIST[0]


static func icon(id: String) -> Texture2D:
	if not _icons.has(id):
		_icons[id] = load("res://assets/characters/%s_icon.png" % id)
	return _icons[id]


static func model(id: String) -> PackedScene:
	return load("res://assets/characters/%s.glb" % id) as PackedScene

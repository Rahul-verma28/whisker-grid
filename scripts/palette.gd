class_name Pal
extends RefCounted
## Colour themes. The player picks one in Settings; "cream" is the default.

const THEMES := {
	"cream": {
		"name": "Cozy Cream", "dark": false,
		"bg": "#fbf1e4", "card": "#fffaf3", "ink": "#4a3a35", "soft": "#8c7b72",
		"accent": "#f08a2c", "blue": "#8c9ff0", "pink": "#ef8fb0", "green": "#3fa45b",
		"red": "#e5484d", "neutral": "#b9a99b", "gold": "#f5b82e", "board": "#fffaf3",
		"tiles": ["#f29bb2", "#8fd19e", "#f5c85c", "#8cb8ee", "#b99be6", "#f5a46b", "#6fcbc3", "#d4d77a", "#d2a98c", "#9fb3c8"],
	},
	"night": {
		"name": "Starry Night", "dark": true,
		"bg": "#1c2240", "card": "#283058", "ink": "#f4efe9", "soft": "#a9b0d8",
		"accent": "#ffad4d", "blue": "#6f86ff", "pink": "#ff7eb3", "green": "#47c47a",
		"red": "#ff5d6c", "neutral": "#4b5486", "gold": "#ffd166", "board": "#232a50",
		"tiles": ["#e86f93", "#58c27d", "#e9b844", "#5b8fe0", "#9a74e0", "#ec8a4f", "#3fb5ab", "#b9bd57", "#c08a6a", "#7d93b0"],
	},
	"mint": {
		"name": "Mint Garden", "dark": false,
		"bg": "#e8f6ee", "card": "#fbfffc", "ink": "#23443a", "soft": "#6b8a80",
		"accent": "#22a884", "blue": "#6aa8e8", "pink": "#f08fae", "green": "#22a884",
		"red": "#e5484d", "neutral": "#9db5ab", "gold": "#f2b632", "board": "#fbfffc",
		"tiles": ["#f4a6bd", "#7fd3a0", "#f6d36b", "#86bdf0", "#bda4ea", "#f7ad7c", "#5cc9c0", "#c9d97a", "#d6b08f", "#a4bccf"],
	},
	"sakura": {
		"name": "Sakura", "dark": false,
		"bg": "#fdeef3", "card": "#fffafc", "ink": "#5a3343", "soft": "#a37888",
		"accent": "#ec6a98", "blue": "#9a9cf2", "pink": "#ec6a98", "green": "#4cae72",
		"red": "#e5484d", "neutral": "#c9a9b5", "gold": "#f2b632", "board": "#fffafc",
		"tiles": ["#f7a1bf", "#9ad6a8", "#f7cf74", "#9cc1ef", "#c6a6ec", "#f6b08a", "#7fd0c6", "#d8dc8a", "#ddb49a", "#b0bfd2"],
	},
}

static var id := "cream"


static func use(theme_id: String) -> void:
	id = theme_id if THEMES.has(theme_id) else "cream"


static func c(key: String) -> Color:
	return Color(THEMES[id][key])


static func dark() -> bool:
	return THEMES[id]["dark"]


static func tiles() -> Array:
	return THEMES[id]["tiles"].map(func(h): return Color(h))


static func preview(theme_id: String, key: String) -> Color:
	return Color(THEMES[theme_id][key])

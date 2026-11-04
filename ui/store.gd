extends RefCounted
## Local persistence: balance overrides (debug menu), settings and play statistics.
## On the web build user:// is stored in the browser (IndexedDB).

const OVERRIDES := "user://balance_override.json"
const SETTINGS := "user://settings.json"
const STATS := "user://stats.json"


static func read(path: String, fallback: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(path):
		return fallback.duplicate(true)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return fallback.duplicate(true)
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else fallback.duplicate(true)


static func write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


static func settings() -> Dictionary:
	var d := read(SETTINGS, {})
	var defaults := {"crt": true, "sound": true, "night": false, "force_theme": "", "force_mod": ""}
	for k in defaults.keys():
		if not d.has(k):
			d[k] = defaults[k]
	return d


static func save_settings(d: Dictionary) -> void:
	write(SETTINGS, d)


static func overrides() -> Dictionary:
	return read(OVERRIDES, {})


static func save_overrides(d: Dictionary) -> void:
	write(OVERRIDES, d)


static func stats() -> Dictionary:
	var d := read(STATS, {})
	for k in ["runs", "wins"]:
		if not d.has(k):
			d[k] = 0
	for k in ["loss_floor", "theme", "mod"]:
		if not d.has(k):
			d[k] = {}
	return d


## Record a finished run. Keys are strings because JSON objects only have string keys.
static func record_run(state) -> void:
	var d := stats()
	var won: bool = state.result == "win"
	d["runs"] = int(d["runs"]) + 1
	if won:
		d["wins"] = int(d["wins"]) + 1
	else:
		var f := str(state.floor_num)
		d["loss_floor"][f] = int(d["loss_floor"].get(f, 0)) + 1
	for pair in [["theme", state.theme_suit], ["mod", state.mod_suit]]:
		var bucket: Dictionary = d[pair[0]]
		var v: Array = bucket.get(pair[1], [0, 0])
		v = [int(v[0]) + (1 if won else 0), int(v[1]) + 1]
		bucket[pair[1]] = v
	write(STATS, d)


static func reset_stats() -> void:
	write(STATS, {})

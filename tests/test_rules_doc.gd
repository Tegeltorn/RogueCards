extends "res://tests/test_base.gd"
## RULES.md (the tabletop rule sheet) must show the same numbers as config/balance.json.


func test_rules_md_matches_balance() -> void:
	var f := FileAccess.open("res://RULES.md", FileAccess.READ)
	check(f != null, "RULES.md exists")
	if f == null:
		return
	var b := Balance.load_json(Balance.BALANCE_PATH)
	var re := RegEx.new()
	re.compile("^\\| `(\\w+)` \\| ([^|]+) \\|")
	var seen := 0
	for line in f.get_as_text().split("\n"):
		var m := re.search(line)
		if m == null:
			continue
		var key := m.get_string(1)
		check(b.has(key), "unknown key %s in RULES.md" % key)
		if not b.has(key):
			continue
		seen += 1
		var doc := m.get_string(2).strip_edges().replace(" ", "")
		eq(doc, _fmt(b[key]), "RULES.md value for %s" % key)
	check(seen >= 8, "balance table found in RULES.md")


func _fmt(v) -> String:
	if typeof(v) == TYPE_ARRAY:
		return "[" + ",".join(v.map(func(x): return _fmt(x))) + "]"
	if typeof(v) == TYPE_FLOAT and v == floor(v):
		return str(int(v))
	return str(v)

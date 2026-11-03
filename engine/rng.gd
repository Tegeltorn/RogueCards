extends RefCounted
## Seeded RNG wrapper. Every random decision in a run goes through this.

var _rng := RandomNumberGenerator.new()
var seed_value: int = 0


func _init(p_seed: int = 0) -> void:
	seed_value = p_seed
	_rng.seed = p_seed


func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)


## In-place Fisher-Yates shuffle.
func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[_rng.randi_range(0, arr.size() - 1)]

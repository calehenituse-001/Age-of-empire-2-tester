class_name CheatPolicy
extends RefCounted
## Per-owner transaction/progress policy. Never mutates global unit definitions.
const FLAGS := ["food", "wood", "gold", "stone", "resource_multiplier", "instant_build", "build_multiplier", "free_build", "instant_train", "train_multiplier", "instant_upgrade", "instant_research", "research_multiplier", "free_research", "population_override"]
const FACTORS := [2, 5, 10, 25, 50, 100]
var values: Dictionary = {}
var offline := false
var safe_mode := false
var session_check: Callable

func configure(data: Dictionary) -> void:
	values.clear()
	for key in FLAGS:
		values[key] = data.get(key) is bool and data.get(key, false) == true
	for kind in ["resource", "build", "train", "research"]:
		var n: Variant = data.get(kind + "_factor", 2)
		values[kind + "_factor"] = int(n) if (n is int or n is float) and int(n) in FACTORS and float(n) == float(int(n)) else 2
	var limit: Variant = data.get("population_limit", 500)
	values.population_limit = clampi(int(limit), 1, 1000) if limit is int or limit is float else 500

func eligible(team := 0) -> bool:
	return team == 0 and offline and not safe_mode and (not session_check.is_valid() or bool(session_check.call()))

func enabled(key: String, team := 0) -> bool:
	return eligible(team) and bool(values.get(key, false))

func factor(kind: String, team := 0) -> float:
	return float(values.get(kind + "_factor", 2)) if enabled(kind + "_multiplier", team) else 1.0

func charged(cost: Dictionary, team := 0, category := "") -> Dictionary:
	var out := {}
	for resource: String in cost:
		var free := enabled(resource, team) or (category == "build" and enabled("free_build", team)) or (category == "research" and enabled("free_research", team))
		out[resource] = 0 if free else maxi(0, int(cost[resource]))
	return out

func can_afford(stock: Dictionary, cost: Dictionary, team := 0, category := "") -> bool:
	var bill := charged(cost, team, category)
	for resource: String in bill:
		if int(stock.get(resource, 0)) < int(bill[resource]):
			return false
	return true

func spend(stock: Dictionary, cost: Dictionary, team := 0, category := "") -> Dictionary:
	var bill := charged(cost, team, category)
	for resource: String in bill:
		stock[resource] = int(stock.get(resource, 0)) - int(bill[resource])
	return bill

func income(amount: int, team := 0) -> int:
	return mini(1000000000, int(amount * factor("resource", team))) if amount > 0 else amount

func advance(kind: String, progress: float, required: float, dt: float, team := 0, upgrade := false) -> float:
	if dt <= 0.0:
		return progress
	var instant := "instant_upgrade" if kind == "research" and upgrade else "instant_" + kind
	return maxf(progress, required) if enabled(instant, team) else progress + dt * factor(kind, team)

func combat_value(_stat: String, original: float, _team: int) -> float:
	# Reserved owner-scoped hook; no combat cheat is advertised or enabled yet.
	return original

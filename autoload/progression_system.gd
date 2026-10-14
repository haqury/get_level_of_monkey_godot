extends Node

signal level_up(new_level: int)

var level: int = 1
var current_xp: int = 0
var upgrade_levels: Dictionary = {
	"max_hp": 0,
	"max_energy": 0,
	"energy_regen": 0,
	"move_speed": 0,
}


func _ready() -> void:
	pass


func required_xp_for_level(lvl: int) -> int:
	var base := float(ConfigLoader.balance.get("progression", {}).get("level_xp_base", 100))
	return int(floor(base * pow(float(lvl), 1.5)))


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	current_xp += amount
	while current_xp >= required_xp_for_level(level):
		current_xp -= required_xp_for_level(level)
		level += 1
		level_up.emit(level)


func upgrade_cost(stat_id: String) -> int:
	var upgrades: Dictionary = ConfigLoader.balance.get("progression", {}).get("upgrades", {})
	if not upgrades.has(stat_id):
		return 999999
	var u: Dictionary = upgrades[stat_id]
	var lvl: int = int(upgrade_levels.get(stat_id, 0))
	return int(u.get("cost_per_level", 50)) * (lvl + 1)


func try_upgrade(stat_id: String) -> bool:
	var cost := upgrade_cost(stat_id)
	if current_xp < cost:
		return false
	current_xp -= cost
	upgrade_levels[stat_id] = int(upgrade_levels.get(stat_id, 0)) + 1
	return true


func apply_to_player(player: Node) -> void:
	if player == null:
		return
	var upgrades: Dictionary = ConfigLoader.balance.get("progression", {}).get("upgrades", {})
	if upgrades.has("max_hp") and player.has_method("set_max_hp"):
		var base_hp := int(ConfigLoader.game_config.get("player", {}).get("initial_hp", 3))
		var bonus: int = int(upgrade_levels.get("max_hp", 0)) * int(upgrades["max_hp"].get("value_per_level", 1))
		player.set_max_hp(base_hp + bonus)
	if upgrades.has("max_energy") and player.has_method("set_max_energy"):
		var base_e := float(ConfigLoader.game_config.get("player", {}).get("initial_energy", 100))
		var bonus_e: float = float(upgrade_levels.get("max_energy", 0)) * float(upgrades["max_energy"].get("value_per_level", 10))
		player.set_max_energy(base_e + bonus_e)
	if upgrades.has("energy_regen") and player.has_method("set_energy_regen"):
		var base_r := float(ConfigLoader.game_config.get("player", {}).get("energy_regen_rate", 5.0))
		var bonus_r: float = float(upgrade_levels.get("energy_regen", 0)) * float(upgrades["energy_regen"].get("value_per_level", 0.5))
		player.set_energy_regen(base_r + bonus_r)
	if upgrades.has("move_speed") and player.has_method("set_move_speed"):
		var base_s := float(ConfigLoader.game_config.get("player", {}).get("move_speed", 5.0))
		var bonus_s: float = float(upgrade_levels.get("move_speed", 0)) * float(upgrades["move_speed"].get("value_per_level", 0.2))
		player.set_move_speed(base_s + bonus_s)


func to_save_dict() -> Dictionary:
	return {"level": level, "current_xp": current_xp, "upgrade_levels": upgrade_levels.duplicate()}


func from_save_dict(data: Dictionary) -> void:
	level = int(data.get("level", 1))
	current_xp = int(data.get("current_xp", 0))
	var ul = data.get("upgrade_levels", {})
	if typeof(ul) == TYPE_DICTIONARY:
		upgrade_levels = ul.duplicate()

extends Node3D

var cash := 0
var total_cash := 0
var deaths := 0
var currentGun := 0
var gambleUnlock := false

@onready var cash_display = get_node_or_null("CashDisplay/Label")
@onready var gun_purchase_prompt_name = get_node_or_null("GunPedestal/GunPurchasePrompt/Name")
@onready var gun_purchase_prompt_value = get_node_or_null("GunPedestal/GunPurchasePrompt/Value")
@onready var gun_purchase_prompt_rate = get_node_or_null("GunPedestal/GunPurchasePrompt/Rate")
@onready var gun_purchase_prompt_chance = get_node_or_null("GunPedestal/GunPurchasePrompt/Chance")
@onready var gun_purchase_prompt_cost = get_node_or_null("GunPedestal/GunPurchasePrompt/Cost")
@onready var gun_purchase_prompt_power = get_node_or_null("GunPedestal/GunPurchasePrompt/Power")
@onready var death_screen_deaths = get_node_or_null("DeathScreen/Deaths")
@onready var death_screen_earnings = get_node_or_null("DeathScreen/Earnings")


signal updateGunValues
signal unlockGamble
signal gameOver

const gunProgression = ["Revolver_1", "Revolver_2", "Revolver_3", "Revolver_4", "Revolver_5", "Pistol_1", "Pistol_2", "Pistol_3", "Pistol_4", "Pistol_5"]
const gunValue = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]
const gunRate = [1.0, 1.0, 1.0, 1.0, 1.0, 0.8, 0.8, 0.8, 0.8, 0.8]
const gunChance = [[1,6], [1,6], [1,6], [1,6], [1,6], [1,5], [1,5], [1,5], [1,5], [1,5]]
# Death knockback (launch speed) per gun. Revolver_1..5 as requested; the Pistol_1..5
# values are placeholders that keep climbing — tweak to taste.
const gunPower = [20, 40, 60, 80, 300, 400, 500, 600, 800, 1000]

const MISS_WIN_BONUS := 0.5
const HIT_WIN_BONUS := 2.0

func _ready() -> void:
	_update_gun()
	_update_gun_pedestal()
	print("Roulette-CMPM80K loaded")

func _on_player_died() -> void:
	deaths += 1
	_update_cash(gunValue[currentGun])

func _update_cash(amount : int) -> void:
	cash += amount
	if amount > 0:
		total_cash += amount
	if cash_display:
		cash_display.text = "Cash: $" + str(cash)
	if (not gambleUnlock) and cash > 7:
		gambleUnlock = true
		unlockGamble.emit()
	if cash < 0:
		gameOver.emit()
		death_screen_deaths.text = "Deaths: " + String.num_int64(deaths)
		death_screen_earnings.text = "Total Earnings: $" + String.num_int64(total_cash)

func _get_gun_cost(i : int) -> int:
	return floor(5 * pow(2, i))

func _update_gun_pedestal() -> void:
	var nextGun = currentGun + 1
	
	if (nextGun >= gunProgression.size()):
		for node in get_tree().get_nodes_in_group("shop_guns"):
			node.visible = false
			
		if gun_purchase_prompt_name:
			gun_purchase_prompt_name.text = "MAX GUN"
		if gun_purchase_prompt_value:
			gun_purchase_prompt_value.visible = false
		if gun_purchase_prompt_rate:
			gun_purchase_prompt_rate.visible = false
		if gun_purchase_prompt_chance:
			gun_purchase_prompt_chance.visible = false
		if gun_purchase_prompt_cost:
			gun_purchase_prompt_cost.visible = false
		if gun_purchase_prompt_power:
			gun_purchase_prompt_power.visible = false

		return
		
	var gunName = gunProgression[nextGun]
	for node in get_tree().get_nodes_in_group("shop_guns"):
		node.visible = node.name == gunName
	
	if gun_purchase_prompt_name:
		gun_purchase_prompt_name.text = str(gunProgression[nextGun])
	if gun_purchase_prompt_value:
		gun_purchase_prompt_value.text = "$" + str(gunValue[nextGun]) + " per kill"
	if gun_purchase_prompt_rate:
		gun_purchase_prompt_rate.text = "Rate: " + str(gunRate[nextGun]) + "s"
	if gun_purchase_prompt_chance:
		gun_purchase_prompt_chance.text = "Chance: " + str(gunChance[nextGun][0]) + "/" + str(gunChance[nextGun][1])
	if gun_purchase_prompt_cost:
		gun_purchase_prompt_cost.text = "Cost: $" + str(_get_gun_cost(currentGun))
	if gun_purchase_prompt_power:
		gun_purchase_prompt_power.visible = true
		gun_purchase_prompt_power.text = "Power: " + str(gunPower[nextGun])

func _update_gun() -> void:
	var gunName = gunProgression[currentGun]
	for node in get_tree().get_nodes_in_group("table_guns"):
		node.visible = node.name == gunName
	updateGunValues.emit(gunRate[currentGun], gunChance[currentGun], gunPower[currentGun])
	
func _on_player_purchase_gun() -> void:
	if (cash < _get_gun_cost(currentGun) or currentGun == gunProgression.size()-1):
		return
	_update_cash(_get_gun_cost(currentGun) * -1)
	currentGun += 1
	_update_gun_pedestal()
	_update_gun()

func _on_player_gun_shoot(wager : int, choice : bool, result : bool) -> void:
	if choice == result:
		if choice:
			_update_cash(floor(wager * HIT_WIN_BONUS))
		else:
			_update_cash(floor(wager * MISS_WIN_BONUS))
	else:
		_update_cash(-wager)

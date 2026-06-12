extends Node3D

var cash := 0
var total_cash := 0
var deaths := 0
var currentGun := 0
var gambleUnlock := false

@onready var cash_display = get_node_or_null("CashDisplay/Label")
@onready var death_screen_deaths = get_node_or_null("DeathScreen/Deaths")
@onready var death_screen_earnings = get_node_or_null("DeathScreen/Earnings")

@onready var pedestal_0 : Node3D = get_node_or_null("ShopPedestal_0")
@onready var pedestal_1 : Node3D = get_node_or_null("ShopPedestal_1")
@onready var pedestal_2 : Node3D = get_node_or_null("ShopPedestal_2")
@onready var pedestal_3 : Node3D = get_node_or_null("ShopPedestal_3")
@onready var pedestal_4 : Node3D = get_node_or_null("ShopPedestal_4")
var pedestals

signal updateGunValues
signal unlockGamble
signal gameOver

const gunNames = ["Revolver","Pistol","SubmachineGun","AssaultRifle","Shotgun"]
const groupNames = ["revolvers", "pistols", "smgs", "rifles", "shotguns"]

const revolver_value = [1, 2, 3, 5, 8]
const revolver_rate = [1.0, 1.0, 1.0, 0.9, 0.8]
const revolver_chance = [6, 6, 6, 6, 6]
const revolver_cost = [0, 5, 10, 20, 40]
# Death knockback (launch speed) per upgrade level. Revolver values as requested.
const revolver_power = [20, 40, 60, 80, 300]

const pistol_value = [5, 8, 13, 21, 34]
const pistol_rate = [1.2, 1.2, 1.1, 1.0, 0.9]
const pistol_chance = [5, 5, 5, 5, 5]
const pistol_cost = [30, 60, 120, 240, 480]
const pistol_power = [400, 500, 600, 800, 1000]

const smg_value = [3, 8, 21, 55, 144]
const smg_rate = [0.25, 0.25, 0.25, 0.25, 0.2]
const smg_chance = [20, 20, 18, 16, 12]
const smg_cost = [100, 200, 400, 800, 1600]
# Placeholder power for the new categories — keeps climbing, tweak to taste.
const smg_power = [1200, 1400, 1600, 1800, 2000]

const ar_value = [34, 55, 89, 144, 233]
const ar_rate = [0.5, 0.5, 0.5, 0.45, 0.4]
const ar_chance = [15, 15, 12, 10, 8]
const ar_cost = [500, 1000, 2000, 4000, 8000]
const ar_power = [2500, 3000, 3500, 4000, 5000]

const shotgun_value = [144, 233, 377, 610, 987]
const shotgun_rate = [2.0, 1.8, 1.6, 1.4, 1.2]
const shotgun_chance = [4, 4, 4, 3, 2]
const shotgun_cost = [2500, 5000, 10000, 20000, 40000]
const shotgun_power = [6000, 7000, 8000, 9000, 10000]

var gun_info = [
	[revolver_value, revolver_rate, revolver_chance, revolver_cost, 0, revolver_power],
	[pistol_value, pistol_rate, pistol_chance, pistol_cost, -1, pistol_power],
	[smg_value, smg_rate, smg_chance, smg_cost, -1, smg_power],
	[ar_value, ar_rate, ar_chance, ar_cost, -1, ar_power],
	[shotgun_value, shotgun_rate, shotgun_chance, shotgun_cost, -1, shotgun_power]
]

const MISS_WIN_BONUS := 0.5
const HIT_WIN_BONUS := 2.0

func _ready() -> void:
	while true:
		if pedestal_0 and pedestal_1 and pedestal_2 and pedestal_3 and pedestal_4:
			break
		await get_tree().create_timer(1.0).timeout
	pedestals = [pedestal_0, pedestal_1, pedestal_2, pedestal_3, pedestal_4]
	_update_gun()
	_update_all_pedestals()
	print("Roulette-CMPM80K loaded")

func _on_player_died() -> void:
	deaths += 1
	_update_cash(_get_gun_info(currentGun)[0])

func _get_gun_info(gun : int):
	var upg = gun_info[gun][4]
	if upg < 0:
		upg = 0
	return [gun_info[gun][0][upg], gun_info[gun][1][upg], gun_info[gun][2][upg], gun_info[gun][3][upg], gun_info[gun][4], gun_info[gun][5][upg]]

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

func _update_gun_pedestal(num : int) -> void:
	var pedestal = pedestals[num]
	if not pedestal:
		return

	var info = _get_gun_info(num)
	var gunName = gunNames[num] + "_"
	if info[4] < 0:
		gunName += str(info[4] + 2)
	else:
		gunName += str(info[4] + 1)
	var group = groupNames[num]

	for node in get_tree().get_nodes_in_group(group):
		node.visible = node.name == gunName

	var prompt = pedestal.find_child("GunPurchasePrompt_" + str(num), true)
	if not prompt:
		return
	var value = prompt.find_child("Value", true)
	var rate = prompt.find_child("Rate", true)
	var chance = prompt.find_child("Chance", true)
	var cost = prompt.find_child("Cost", true)
	var power = prompt.find_child("Power", true)
	var E = prompt.find_child("E", true)
	if value:
		value.text = "$" + str(info[0]) + " per kill"
	if rate:
		rate.text = "Rate: " + str(info[1]) + "s"
	if chance:
		chance.text = "Chance: 1/" + str(info[2])
	if power:
		power.text = "Power: " + str(info[5])
	if cost:
		if info[4] < 4:
			cost.text = "Cost: $" + str(gun_info[num][3][info[4]+1])
		else:
			cost.text = "Cost: MAXED"
	if E:
		if info[4] < 0:
			E.text = "E to buy"
		elif currentGun != num:
			E.text = "E to switch"
		elif info[4] < 4:
			E.text = "E to upg"
		else:
			E.text = "MAXED"

func _update_all_pedestals() -> void:
	_update_gun_pedestal(0)
	_update_gun_pedestal(1)
	_update_gun_pedestal(2)
	_update_gun_pedestal(3)
	_update_gun_pedestal(4)

func _update_gun() -> void:
	var info = _get_gun_info(currentGun)
	var gunName = gunNames[currentGun] + "_"
	if info[4] < 0:
		gunName += str(info[4] + 2)
	else:
		gunName += str(info[4] + 1)
	for node in get_tree().get_nodes_in_group("table_guns"):
		node.visible = node.name == gunName
	updateGunValues.emit(info[1], info[2], info[5])

func _on_player_purchase_gun(num : int) -> void:
	var info = _get_gun_info(num)
	if currentGun != num and gun_info[currentGun][4] > -1:
		var prev = currentGun
		currentGun = num
		_update_gun_pedestal(num)
		_update_gun_pedestal(prev)
		_update_gun()
		return
	var cost = gun_info[num][3][info[4]+1]
	if (cash < cost or info[4] >= 4): # least confusing line of code ever
		return

	var prev = currentGun
	currentGun = num
	gun_info[num][4] += 1
	_update_cash(-cost)
	_update_gun_pedestal(num)
	_update_gun_pedestal(prev)
	_update_gun()

func _on_player_gun_shoot(wager : int, choice : bool, result : bool) -> void:
	if choice == result:
		if choice:
			_update_cash(floor(wager * HIT_WIN_BONUS))
		else:
			_update_cash(floor(wager * MISS_WIN_BONUS))
	else:
		_update_cash(-wager)

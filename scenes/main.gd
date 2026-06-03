extends Node3D

var cash := 0
var deaths := 0

@onready var cash_display = get_node_or_null("CashDisplay/Label")

func _on_player_died() -> void:
	deaths += 1
	update_cash(1)

func update_cash(amount : int) -> void:
	cash += amount
	print(cash)
	if cash_display:
		cash_display.text = "Cash: $" + str(cash)

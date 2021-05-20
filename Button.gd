extends Button

func _pressed():
	$"../../../Gift".chat($"../LineEdit".text)
	$"../LineEdit".text = ""

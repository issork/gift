class_name CommandInfo
extends RefCounted

var sender_data : SenderData
var command : String
var whisper : bool

func _init(sndr_dt : SenderData, cmd : String, whspr : bool):
	sender_data = sndr_dt
	command = cmd
	whisper = whspr

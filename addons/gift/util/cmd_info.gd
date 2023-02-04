extends RefCounted
class_name CommandInfo

var sender_data : SenderData
var command : String
var whisper : bool

func _init(sndr_dt, cmd, whspr):
	sender_data = sndr_dt
	command = cmd
	whisper = whspr


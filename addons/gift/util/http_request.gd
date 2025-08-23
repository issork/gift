class_name GiftRequest
extends RefCounted

signal response

var method : int
var url : String
var headers : PackedStringArray
var body : String

func _init(method : int, url : String, headers : PackedStringArray, body : String = "") -> void:
	self.method = method
	self.url = url
	self.headers = headers
	self.body = body

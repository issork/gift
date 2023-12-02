class_name TwitchOAuthFlow
extends RefCounted

signal token_received(token_data)

var peer : StreamPeerTCP

func _create_peer() -> StreamPeerTCP:
	return null

func poll() -> void:
	if (!peer):
		peer = _create_peer()
		if (peer && peer.get_status() == StreamPeerTCP.STATUS_CONNECTED):
			_poll_peer()
	elif (peer.get_status() == StreamPeerTCP.STATUS_CONNECTED):
		_poll_peer()

func _poll_peer() -> void:
	peer.poll()
	if (peer.get_available_bytes() > 0):
		var response = peer.get_utf8_string(peer.get_available_bytes())
		_process_response(response)

func _process_response(response : String) -> void:
	pass

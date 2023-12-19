class_name RedirectingFlow
extends TwitchOAuthFlow

var server : TCPServer

var tcp_port : int
var redirect_url : String

func _init(port : int = 18297, redirect : String = "http://localhost:%s" % port) -> void:
	tcp_port = port
	redirect_url = redirect

func _create_peer() -> StreamPeerTCP:
	return server.take_connection()

func start_tcp_server() -> void:
	if (server == null):
		server = TCPServer.new()
		if (server.listen(tcp_port) != OK):
			print("Could not listen to port %d" % tcp_port)

func send_response(response : String, body : PackedByteArray) -> void:
	peer.put_data(("HTTP/1.1 %s\r\n" % response).to_utf8_buffer())
	peer.put_data("Server: GIFT (Godot Engine)\r\n".to_utf8_buffer())
	peer.put_data(("Content-Length: %d\r\n"% body.size()).to_utf8_buffer())
	peer.put_data("Connection: close\r\n".to_utf8_buffer())
	peer.put_data("Content-Type: text/html; charset=UTF-8\r\n".to_utf8_buffer())
	peer.put_data("\r\n".to_utf8_buffer())
	peer.put_data(body)

func _process_response(response : String) -> void:
	if (response == ""):
		print("Empty response. Check if your redirect URL is set to %s." % redirect_url)
		return
	var start : int = response.substr(0, response.find("\n")).find("?")
	if (start == -1):
		_handle_empty_response()
	else:
		response = response.substr(start + 1, response.find(" ", start) - start)
		var data : Dictionary = {}
		for entry in response.split("&"):
			var pair = entry.split("=")
			data[pair[0]] = pair[1] if pair.size() > 0 else ""
		if (data.has("error")):
			_handle_error(data)
		else:
			_handle_success(data)
	peer.disconnect_from_host()
	peer = null

func _handle_empty_response() -> void:
	print ("Response from Twitch does not contain the required data.")

func _handle_success(data : Dictionary) -> void:
	data["scope"] = data["scope"].uri_decode().split(" ")
	print("Success.")
	send_response("200 OK", "<html><head><title>Twitch Login</title></head><body onload=\"javascript:close()\">Success!</body></html>".to_utf8_buffer())

func _handle_error(data : Dictionary) -> void:
	var msg = "Error %s: %s" % [data["error"], data["error_description"]]
	print(msg)
	send_response("400 BAD REQUEST",  msg.to_utf8_buffer())

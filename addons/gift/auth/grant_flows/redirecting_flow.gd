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

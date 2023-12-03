class_name TwitchEventSubConnection
extends RefCounted

const TEN_MINUTES_S : int = 600

# The id has been received from the welcome message.
signal session_id_received(id)
signal events_revoked(type, status)
signal event(type, event_data)

enum ConnectionState {
	DISCONNECTED,
	CONNECTED,
	CONNECTION_FAILED,
	RECONNECTING
}

var connection_state : ConnectionState = ConnectionState.DISCONNECTED

var eventsub_messages : Dictionary = {}
var eventsub_reconnect_url : String = ""
var session_id : String = ""
var keepalive_timeout : int = 0
var last_keepalive : int = 0

var last_cleanup : int = 0

var websocket : WebSocketPeer

var api : TwitchAPIConnection

func _init(twitch_api_connection : TwitchAPIConnection) -> void:
	api = twitch_api_connection
	api.id_conn.polled.connect(poll)

func connect_to_eventsub(url : String = "wss://eventsub.wss.twitch.tv/ws") -> void:
	if (websocket == null):
		websocket = WebSocketPeer.new()
	websocket.connect_to_url(url)
	print("Connecting to Twitch EventSub")
	await(session_id_received)

func poll() -> void:
	if (websocket != null):
		websocket.poll()
		var state := websocket.get_ready_state()
		match state:
			WebSocketPeer.STATE_OPEN:
				if (!connection_state == ConnectionState.CONNECTED):
					connection_state = ConnectionState.CONNECTED
					print("Connected to EventSub.")
				else:
					while (websocket.get_available_packet_count()):
						process_event(websocket.get_packet())
			WebSocketPeer.STATE_CLOSED:
				if(connection_state != ConnectionState.CONNECTED):
					print("Could not connect to EventSub.")
					websocket = null
					connection_state = ConnectionState.CONNECTION_FAILED
				elif(connection_state == ConnectionState.RECONNECTING):
					print("Reconnecting to EventSub")
					websocket.close()
					connect_to_eventsub(eventsub_reconnect_url)
				else:
					print("Disconnected from EventSub.")
					connection_state = ConnectionState.DISCONNECTED
					print("Connection closed! [%s]: %s"%[websocket.get_close_code(), websocket.get_close_reason()])
					websocket = null
		var t : int = Time.get_ticks_msec() / 1000 - TEN_MINUTES_S
		if (last_cleanup < t):
			last_cleanup = Time.get_ticks_msec() / 1000
			var to_remove : Array = []
			for msg in eventsub_messages:
				if (eventsub_messages[msg] < Time.get_unix_time_from_system() - TEN_MINUTES_S):
					to_remove.append(msg)
			for e in to_remove:
				eventsub_messages.erase(e)

func process_event(data : PackedByteArray) -> void:
	var msg : Dictionary = JSON.parse_string(data.get_string_from_utf8())
	if (eventsub_messages.has(msg["metadata"]["message_id"]) || Time.get_unix_time_from_datetime_string(msg["metadata"]["message_timestamp"]) < Time.get_unix_time_from_system() - TEN_MINUTES_S):
		return
	eventsub_messages[msg["metadata"]["message_id"]] = Time.get_unix_time_from_datetime_string(msg["metadata"]["message_timestamp"])
	var payload : Dictionary = msg["payload"]
	last_keepalive = Time.get_ticks_msec()
	match msg["metadata"]["message_type"]:
		"session_welcome":
			session_id = payload["session"]["id"]
			keepalive_timeout = payload["session"]["keepalive_timeout_seconds"]
			session_id_received.emit(session_id)
		"session_keepalive":
			if (payload.has("session")):
				keepalive_timeout = payload["session"]["keepalive_timeout_seconds"]
		"session_reconnect":
			connection_state = ConnectionState.RECONNECTING
			eventsub_reconnect_url = payload["session"]["reconnect_url"]
		"revocation":
			events_revoked.emit(payload["subscription"]["type"], payload["subscription"]["status"])
		"notification":
			var event_data : Dictionary = payload["event"]
			event.emit(payload["subscription"]["type"], event_data)

# Refer to https://dev.twitch.tv/docs/eventsub/eventsub-subscription-types/ for details on
# which API versions are available and which conditions are required.
func subscribe_event(event_name : String, version : String, conditions : Dictionary) -> void:
	var data : Dictionary = {}
	data["type"] = event_name
	data["version"] = version
	data["condition"] = conditions
	data["transport"] = {
		"method":"websocket",
		"session_id":session_id
	}
	var response = await(api.create_eventsub_subscription(data))
	if (response.has("error")):
		print("Subscription failed for event '%s'. Error %s (%s): %s" % [event_name, response["status"], response["error"], response["message"]])
		return
	elif (response.is_empty()):
		return
	print("Now listening to '%s' events." % event_name)

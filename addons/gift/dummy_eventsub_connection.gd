class_name DummyEventSubConnection
extends TwitchEventSubConnection

###	HOW TO USE:
###	1. Download the TwitchCLI (https://github.com/twitchdev/twitch-cli/releases)
###	2. Start the websocket server by executing 'twitch event websocket start-server'
###	3. Connect to the websocket server using the connect_to_eventsub function
###	4. Copy the session id printed in the console of the websocket server
###	5. From a seperate console, you can now trigger events. e.g.: 'twitch event trigger channel.follow --session <insert session id from above>
###	For more information, see https://github.com/twitchdev/twitch-cli/blob/main/docs/event.md
func connect_to_eventsub(url : String = "ws://127.0.0.1:8080/ws", poll_signal : Signal = Engine.get_main_loop().process_frame) -> void:
	poll_signal.connect(poll)
	super(url)

func subscribe_event(event_name : String, version : String, conditions : Dictionary) -> void:
	pass

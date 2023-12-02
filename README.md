# GIFT
Godot IRC For Twitch addon

To use this plugin, you need to create a new application on dev.twitch.tv to get a client ID and possibly a client secret (depending on which authentication method you choose). The redirect URL of your App has to be http://localhost:18297 or the URL you specify in the RedirectingFlow constructor.

If you require help, feel free to join my >[Discord Server](https://discord.gg/28DQbuwMM2)< and ask your questions <3

Below is a working example of this plugin, which is included in this project. A replication of the twitch chat. Most information about the Twitch API can be found in the [official documentation](https://dev.twitch.tv/docs/).

[Example.gd](https://github.com/issork/gift/blob/master/Example.gd)

![image](https://user-images.githubusercontent.com/12477395/119052327-b9fc9980-b9c4-11eb-8f45-a2a8f2d98977.png)


### Utility Classes

***

#### CommandData
##### Data required to store, execute and handle commands properly.
- **func_ref** : Callable - Function that is called by the command.
- **permission_level** : int - Permission level required by the command.
- **max_args** : int - Maximum number of arguments this command accepts. cmd_invalid_argcount is emitted if above this number.
- **min_args** : int - Minimum number of arguments this command accepts. cmd_invalid_argcount is emitted if below this number.
- **where** : int - Where the command should be received (0 = Chat, 1 = Whisper)

***

#### CommandInfo
##### Info about the command that was executed.
- **sender_data** : SenderData - Associated data with the sender.
- **command** : String - Name of the command that has been called.
- **whisper** : bool - true if the command was sent as a whisper message.

***

#### SenderData
##### Data of the sender
- **user** : String - The lowercase username of the sender. Use tags["display-name"] for the case sensitive name.
- **channel** : String - The channel in which the data was sent.
- **tags** : Dictionary - Refer to the Tags documentation; https://dev.twitch.tv/docs/irc/tags


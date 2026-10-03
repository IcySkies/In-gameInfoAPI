# VividStasis Game Info Relay

The relay is the required local transport for the vivid/stasis in-game
information API. It owns `127.0.0.1:28745` for the game connection and fans
the original length-prefixed protocol-v1 frames out to any number of desktop
subscribers. It opens a status window showing the game connection, subscriber
count, ports, and configured path. Closing that window stops the relay and
removes its discovery file.

Desktop applications launch or reuse the relay with:

```text
VividStasisGameInfoRelay.exe --game-path <game-directory>
```

The relay writes `AutoChartSwitchV2/bridge-relay.json` under that game
directory. Subscribers read the dynamic subscriber port from this file. The
relay keeps a bounded journal for late subscribers and independent bounded
queues for each connected subscriber.

## Connection refused

A discovery file may remain after a crash or forced process exit. It is not
proof that a relay is running, and its subscriber port changes on restart.
Start the relay with the configured game directory and keep it running;
AutoChartFill can also start its bundled relay automatically. AutoChartSwitch
V2 expects the relay to be started independently.

Consumers retry discovery and skip refused endpoints so a stale game-directory
file cannot hide a live relay advertised in
`%LOCALAPPDATA%/SVC-AS/VividStasisGameInfoRelay/bridge-relay.json`.
Use `bridge-relay.log` in the game's `AutoChartSwitchV2` directory to check the
current listening ports and subscriber connections. Port `28745` is the game
producer port, not the desktop subscriber port.

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

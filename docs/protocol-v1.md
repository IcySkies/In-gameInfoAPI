# vivid/stasis In-game Information API Protocol v1

The API currently uses the AutoChartSwitch-compatible transport so existing
desktop integrations remain working during the rebrand.

The installed loader package is `VividStasisGameInfoAPI v3.0.0`; the old
`AutoChartSwitch Game Bridge v2.0.0` directory is retired.

## Transport

- GameMaker opens an asynchronous TCP connection to the required relay at
  `127.0.0.1:28745`. Desktop consumers connect to the relay's discovered
  subscriber port; they do not bind the game port.
- Each message is UTF-8 JSON preceded by a 4-byte little-endian payload length.
- The payload length excludes the 4-byte prefix.
- Consumers must read the prefix and payload fully; TCP packet boundaries are
  not message boundaries.

## Envelope

Required compatibility fields:

```json
{
  "protocolVersion": 1,
  "sequence": 12,
  "kind": "Selection",
  "chart": {}
}
```

Optional API fields:

| Field | Meaning |
| --- | --- |
| `sessionId` | Identifies one game process/session. Changes on game restart. |
| `eventId` | Stable identifier formed from session and sequence. |
| `game` | Source game identifier, currently `vivid/stasis`. |
| `state` | `Idle`, `Selection`, `Lobby`, `Loading`, `Gameplay`, `Exiting`, or `Ended`. |
| `stateChangedAtMs` | GameMaker `current_time` when the state last changed. |
| `gameTimeMs` | GameMaker `current_time` when the envelope was created. |
| `replay` | `true` when the latest state is replayed after reconnect. |
| `capabilities` | Features currently available from the mod. |
| `droppedEvents` | Number of queued events discarded due to the bounded journal. |

## Existing event kinds

`ChartInfo`, `Selection`, `LobbySelection`, `ChartLoadingStarted`, `ChartStarted`,
`ChartExitTransitionStarted`, and `GameplayEnded` are supported event kinds. Consumers
must ignore unknown optional properties and should treat `chart` as nullable on
lifecycle events.

`WorldcrossRoom` and `WorldcrossGameplay` are additive telemetry events. They
carry no chart and include an optional `worldcross.players` array. Each player
has `steamId64` (string), `name`, `state` (`unready`, `ready`, or `playing`),
`rating`, numeric `class`, live `score`, finalized `lastPlayScore`, and `label`
(`FC`, `AC`, `VS`, or an empty string). NPC entries are omitted. Consumers that
do not use Worldcross telemetry can ignore these event kinds.

## Delivery behavior

Events receive monotonically increasing `sequence` values within a session.
ChartInfo snapshots are coalesced while disconnected. Lifecycle events are
retained preferentially. Reconnect replays the most recent state/chart and
then flushes queued events in sequence order.

`ChartInfo` carries the currently highlighted chart and may occur repeatedly as
the player browses. A confirmed single-player choice is represented by a
chartless `Selection` event immediately after the relevant `ChartInfo`; the
selection marker confirms the latest highlighted chart. `LobbySelection`
continues to carry the confirmed Worldcross chart. AutoChartSwitch may display
`ChartInfo` as preview data but must not publish it to live OBS until
`Selection` or `LobbySelection` arrives. AutoChartFill captures every delivered
`ChartInfo` while recording.

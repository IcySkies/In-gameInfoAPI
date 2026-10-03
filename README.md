# vivid/stasis In-game Information API

The vivid/stasis In-game Information API is the authoritative realtime game
information source for vivid/stasis integrations. It currently publishes
highlighted chart info, confirmed selection, Worldcross lobby decisions, chart loading, gameplay start,
chart-exit transition, and gameplay-end information over the legacy
AutoChartSwitch Game Bridge transport.

The legacy name and wire contract are intentionally retained so existing
consumers, including AutoChartSwitchV2 and AutoChartFill, continue to work
without changes.

## Compatibility contract

- Transport remains an outbound raw TCP connection from GameMaker to
  `127.0.0.1:28745` by default.
- Frames remain little-endian, 32-bit length-prefixed UTF-8 JSON.
- `protocolVersion` remains `1`.
- Existing lifecycle and lobby event kinds remain unchanged; `ChartInfo` adds
  highlight snapshots and `Selection` confirms the latest snapshot.
- New envelope properties (`sessionId`, `eventId`, `state`, `game`,
  `capabilities`, `replay`, and diagnostics) are optional extensions.

## Delivery guarantees

The API keeps a bounded in-game event journal. Events created while the
consumer is unavailable are queued and flushed in sequence order after a
reconnect. Repeated chart-info snapshots are coalesced; lifecycle events are
preserved preferentially. If the queue reaches its limit, the oldest
non-lifecycle event is discarded and the next envelope reports the dropped
event count. The latest state and chart snapshot are replayed after reconnect.

The transport is asynchronous and never blocks the game thread. Retry delay
uses bounded backoff and resets after a successful connection.

## State model

The optional `state` property reports `Idle`, `Selection`, `Lobby`, `Loading`,
`Gameplay`, `Exiting`, or `Ended`. State changes are idempotent at the hook
boundary, so duplicate room or transition callbacks do not create duplicate
lifecycle effects in consumers.

## Future extensions

The capability list and optional envelope properties provide the compatibility
surface for future gameplay telemetry such as score, combo, judgement, gauge,
and progress. Those additions should use new optional payload fields or a
coordinated protocol version rather than changing the existing event meanings.

## Legacy bridge behavior

This mod emits highlighted chart info and a chartless confirmed selection marker, Worldcross lobby decisions, chart
loading, gameplay start, chart-exit transition, and gameplay exit events to
AutoChartSwitch V2 over a raw localhost TCP connection. Worldcross decisions
are observed from the settled lobby queue for both local and remote choices.
Packet encoding is left to the game and other mods; unresolved custom charts
are not published until their chart ID resolves to a local song.

Before publishing a Worldcross decision, the bridge runs the game's native
`GetSongStats` calculation for the chosen song and difficulty. This keeps all
six tech statistics aligned with the title, credits, difficulty, and jacket;
if chart details cannot be loaded, the event reports zeroes instead of stale
statistics from the previously viewed song.
The calculation lets the native function initialize its outputs without
requiring preexisting stat globals or the unused `ss_notecount` global.
It saves and restores existing stats, totals, temporary levels, and the
`has_mods` flag; events read a private copy. Loading and gameplay-start
snapshots calculate stats for their current chart rather than copying
potentially stale selector globals.

The chart loading event is emitted when `o_transitionsong` is created. It
triggers the Auto-Switch entry scene before the gameplay room is created;
gameplay start only refreshes chart metadata and arms gameplay-exit detection.
The exit event that switches OBS scenes is emitted when the guarded
`o_transition_diamond` chart-exit transition is created. A gameplay exit that
does not show that transition only resets lifecycle state.

In single-player song select, `ChartInfo` is emitted when the highlighted
song/difficulty changes. Pressing Confirm emits a chartless `Selection` marker;
consumers associate it with the most recent `ChartInfo`. AutoChartSwitch uses
that marker to update live OBS output, while AutoChartFill records each received
`ChartInfo` while recording. On reconnect, the mod replays `ChartInfo` followed
by `Selection` when the latest highlight was confirmed.

Supported game version: vivid/stasis 6.2.2.2 [F3D3B703]. The relay listens on
port 28745 by default. A `AutoChartSwitchV2/bridge.ini` file in the game
working directory can override the port:

```ini
[bridge]
port=28745
jacket_path=AutoChartSwitchV2/Jackets
```

On each new chart/difficulty selection, the bridge exports the native jacket
sprite on demand as a 500x500 PNG in GameMaker's
`%LOCALAPPDATA%\VIVIDSTASIS\AutoChartSwitchV2\Jackets` sandbox. Scaling uses
nearest-neighbor sampling. The desktop app resolves the relative event path and
copies valid exports into its configured output folder. If the song has no
valid jacket sprite, the event contains an empty jacket path and the desktop
app uses `Memories_Sacrifice_jacket.png` from its configured directory. Missing
jackets are never loaded or rendered by the game.

Events include raw and optional formatted variants for title, artist, charter,
and illustrator so the desktop app can select text compatible with its OBS font.

The installed package is named `VividStasisGameInfoAPI v3.0.0`. The loader
processes it in its alphabetical position after the existing gameplay mods;
its patches use stable object and code anchors and the loader log must confirm
that every patch applies. The app writes the port file under the configured
game path.

The game uses GameMaker's raw asynchronous TCP connection to the required local
relay. The relay fans frames out to all desktop subscribers. Connection
attempts never block the game thread; the game and relay can be started in
either order. When the relay starts or restarts, the mod reconnects and sends
its latest chart and lifecycle state. If the relay is unavailable, the mod
logs a nonblocking warning and retries. While VS Online's WebSocket is
connecting, the bridge defers its TCP connection attempt.

Worldcross telemetry is published as additive `WorldcrossRoom` and
`WorldcrossGameplay` events. The optional `worldcross.players` array contains
non-NPC members with their SteamID64, name, readiness/play state, rating,
numeric class, live score, finalized last-play score, and FC/AC/VS label.

# AutoChartSwitch Game Bridge v2.0.0

This mod emits highlighted chart selection, Worldcross lobby decisions, chart
loading, gameplay start, chart-exit transition, and gameplay exit events to
AutoChartSwitch V2 over a raw localhost TCP connection. Worldcross decisions
are emitted both when the local player sends a choice and when a choice is
received from another client.

Before publishing a Worldcross decision, the bridge runs the game's native
`GetSongStats` calculation for the chosen song and difficulty. This keeps all
six tech statistics aligned with the title, credits, difficulty, and jacket;
if chart details cannot be loaded, the event reports zeroes instead of stale
statistics from the previously viewed song.

The chart loading event is emitted when `o_transitionsong` is created. It
triggers the Auto-Switch entry scene before the gameplay room is created;
gameplay start only refreshes chart metadata and arms gameplay-exit detection.
The exit event that switches OBS scenes is emitted when the guarded
`o_transition_diamond` chart-exit transition is created. A gameplay exit that
does not show that transition only resets lifecycle state.

Supported game version: vivid/stasis 6.2.2.2 [F3D3B703]. The app listens on
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

The loader processes this package before the existing alphabetical mod names;
its patches use insertion points that remain valid when the later song and
gameplay mods are applied. The app writes the port file under the configured
game path.

The game uses GameMaker's raw asynchronous TCP connection because the app is a
.NET listener rather than another GameMaker game. Connection attempts never
block the game thread. The game and app can be started in either order. When
the app starts or restarts, the mod reconnects and sends its latest chart and
lifecycle state.

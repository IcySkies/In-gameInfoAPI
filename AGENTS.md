# Repository Instructions

## Source of truth

- This repository is the only editable source for the vivid/stasis in-game information mod.
- Do not edit the installed VividStasisModLoader mirror directly.
- The installed package name is `VividStasisGameInfoAPI v3.0.0`.
- The legacy `AutoChartSwitch Game Bridge` name is retained only for protocol and consumer compatibility.

## Synchronization

After changing mod files, synchronize the package with:

```powershell
.\tools\Sync-ModToLoader.ps1
.\tools\Verify-ModSync.ps1
```

The mirror is `..\SourceFiles\VividStasisModLoader\mods\VividStasisGameInfoAPI v3.0.0`.
The old `AutoChartSwitch Game Bridge v2.0.0` mirror must not exist.

## Validation

- After every change to this mod or its transport contract, rebuild both affected
  desktop consumers in Release configuration:

  ```powershell
  dotnet build ..\AutoChartSwitchV2\AutoChartSwitchV2.sln --configuration Release --no-restore
  dotnet build ..\AutoChartFill\AutoChartFill.sln --configuration Release --no-restore
  ```

- Confirm the rebuilt outputs include the complete relay runtime beside each
  desktop application: `VividStasisGameInfoRelay.exe`, `.dll`,
  `.runtimeconfig.json`, and `.deps.json` before testing runtime connectivity.
- When validating relay startup, launch each desktop app with the configured
  game path and verify `AutoChartSwitchV2\bridge-relay.json` is created and the
  relay log records one subscriber connection per app. Discovery JSON uses
  camelCase property names and consumers must deserialize it with web defaults.
- Relay event parsing must retain the `JsonStringEnumConverter` because the
  protocol encodes `kind` as strings (`Selection`, `LobbySelection`, and the
  lifecycle event names).
- Keep relay subscribers tolerant of both string and numeric enum encodings;
  the GameMaker wire producer has emitted both forms across supported builds.
- Keep `protocolVersion` and `sequence` tolerant of both JSON numbers and
  numeric strings as well, including integral decimal forms such as `1.0`.
- Relay subscribers must monitor the read side of each TCP connection so a
  parser failure or consumer exit removes the subscriber instead of creating a
  reconnect-count leak.
- Run the VividStasisModLoader against the configured vivid/stasis 6.2.2.2 installation.
- Verify the newest loader log ends with `Patch flow completed`.
- Verify there are no missing-entry, patch, or compile errors.
- Treat the mod as loaded only after the loader run creates a newest log that
  satisfies both checks above; do not rely on a successful synchronization alone.
- Preserve protocol version 1, existing event kinds, port 28745, and legacy jacket/configuration paths.

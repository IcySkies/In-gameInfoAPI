var _acs_ws_connecting = false;
if (variable_global_exists("vs_ws") && is_struct(global.vs_ws))
    _acs_ws_connecting = variable_struct_exists(global.vs_ws, "state") && global.vs_ws.state == 1;
if (!acs_connected && !acs_connecting && !_acs_ws_connecting)
{
    acs_retry -= 1;
    if (acs_retry <= 0)
    {
        if (acs_socket >= 0)
        {
            try { network_destroy(acs_socket); } catch (e) { }
            acs_socket = -1;
        }
        acs_socket = network_create_socket(network_socket_tcp);
        if (acs_socket >= 0)
        {
            var _connectResult = network_connect_raw_async(acs_socket, "127.0.0.1", acs_port);
            acs_connecting = _connectResult >= 0;
            if (!acs_connecting) acs_reset_connection(acs_retry_delay);
        }
        else
        {
            acs_reset_connection(acs_retry_delay);
        }
    }
}

if (acs_gameplay_active && !instance_exists(cc))
{
    EmitGameplayEnded();
}

var _acs_in_worldcross = variable_global_exists("multiplayerLobby") && global.multiplayerLobby;
if (!_acs_in_worldcross && !acs_gameplay_active)
{
    acs_last_lobby_key = "";
    acs_last_lobby_song = undefined;
    acs_last_room_signature = "";
    acs_last_gameplay_signature = "";
    acs_last_play_scores = [];
}
else if (acs_gameplay_active)
{
    try { acs_emit_worldcross_snapshot(true); } catch (e) { }
}
else
{
    if (!instance_exists(o_transitionsong) && !instance_exists(o_transition_diamond))
        try { EmitLobbySelectionFromQueue(); } catch (e) { }
    try { acs_emit_worldcross_snapshot(false); } catch (e) { }
}

try { acs_flush_events(); } catch (e) { acs_reset_connection(acs_retry_delay); }

if (!acs_connected && !acs_connecting)
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
            if (!acs_connecting) acs_reset_connection(60);
        }
        else
        {
            acs_retry = 60;
        }
    }
}

if (acs_gameplay_active && !instance_exists(cc))
{
    EmitGameplayEnded();
}

if (!variable_global_exists("multiplayerLobby") || !global.multiplayerLobby)
    acs_last_lobby_key = "";

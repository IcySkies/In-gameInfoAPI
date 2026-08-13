var _type = ds_map_find_value(async_load, "type");
var _id = ds_map_find_value(async_load, "id");
if (_type == network_type_non_blocking_connect && _id == acs_socket)
{
    var _succeeded = ds_map_find_value(async_load, "succeeded");
    if (_succeeded == 1)
    {
        acs_connecting = false;
        acs_connected = true;
        if (acs_last_chart != undefined) SendEvent(acs_last_kind, acs_last_chart);
    }
    else
    {
        acs_reset_connection(60);
    }
}
else if (_type == network_type_disconnect && _id == acs_socket)
{
    acs_reset_connection(60);
}

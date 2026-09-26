var _type = ds_map_find_value(async_load, "type");
var _id = ds_map_find_value(async_load, "id");
if (_type == network_type_non_blocking_connect && _id == acs_socket)
{
    var _succeeded = ds_map_find_value(async_load, "succeeded");
    if (_succeeded == 1)
    {
        acs_connecting = false;
        acs_connected = true;
        acs_relay_warning = false;
        acs_warning_shown = false;
        acs_retry_delay = 60;
        if (acs_last_kind == "Selection" && acs_last_chart_info != undefined)
        {
            acs_queue_event(acs_build_envelope("ChartInfo", acs_last_chart_info, true));
            acs_queue_event(acs_build_envelope("Selection", undefined, true));
        }
        else if (acs_last_chart != undefined)
            acs_queue_event(acs_build_envelope(acs_last_kind, acs_last_chart, true));
        acs_flush_events();
    }
    else
    {
        acs_reset_connection(acs_retry_delay);
    }
}
else if (_type == network_type_disconnect && _id == acs_socket)
{
    acs_reset_connection(60);
}

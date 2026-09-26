var _acs_highlighted_song = {};
var _acs_highlighted_difficulty = 0;
var _acs_highlighted_backstage = false;

if (variable_instance_exists(id, "selected_song"))
    _acs_highlighted_song = variable_instance_get(id, "selected_song");
else if (variable_global_exists("selected_song"))
    _acs_highlighted_song = variable_global_get("selected_song");

if (variable_instance_exists(id, "selected_song_has_backstage"))
    _acs_highlighted_backstage = variable_instance_get(id, "selected_song_has_backstage");
else if (variable_global_exists("selected_song_has_backstage"))
    _acs_highlighted_backstage = variable_global_get("selected_song_has_backstage");

if (variable_instance_exists(id, "song_objects") && variable_instance_exists(id, "cursor_pos"))
{
    var _acs_song_objects = variable_instance_get(id, "song_objects");
    var _acs_cursor_pos = variable_instance_get(id, "cursor_pos");
    if (is_array(_acs_song_objects) && _acs_cursor_pos >= 0 && _acs_cursor_pos < array_length(_acs_song_objects))
    {
        var _acs_song_object = _acs_song_objects[_acs_cursor_pos];
        if (instance_exists(_acs_song_object) && variable_instance_exists(_acs_song_object, "diff"))
            _acs_highlighted_difficulty = variable_instance_get(_acs_song_object, "diff");
    }
}

var _acs_is_worldcross = variable_global_exists("multiplayerLobby") && global.multiplayerLobby;
if (!_acs_is_worldcross && instance_exists(o_autochartswitch_bridge))
    o_autochartswitch_bridge.EmitChartInfo(_acs_highlighted_song, _acs_highlighted_difficulty, _acs_highlighted_backstage);

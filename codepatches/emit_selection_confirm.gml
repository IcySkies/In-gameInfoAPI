var _acs_selected_song = {};
var _acs_selected_difficulty = 0;
var _acs_selected_backstage = false;

if (variable_instance_exists(id, "song"))
    _acs_selected_song = variable_instance_get(id, "song");
else if (variable_global_exists("selected_song"))
    _acs_selected_song = variable_global_get("selected_song");

if (variable_instance_exists(id, "selected_difficulty"))
    _acs_selected_difficulty = variable_instance_get(id, "selected_difficulty");
else if (variable_global_exists("songselect_difficulty"))
    _acs_selected_difficulty = variable_global_get("songselect_difficulty");

if (variable_instance_exists(id, "selected_backstage"))
    _acs_selected_backstage = variable_instance_get(id, "selected_backstage");
else if (variable_global_exists("selected_song_has_backstage"))
    _acs_selected_backstage = variable_global_get("selected_song_has_backstage");

// The confirmation menu initializes selected_difficulty to OPENING. The
// selector's current song object contains the difficulty that was highlighted
// when the player pressed Confirm.
if (instance_exists(o_songselect))
{
    var _acs_selector = instance_find(o_songselect, 0);
    if (variable_instance_exists(_acs_selector, "selected_song"))
        _acs_selected_song = variable_instance_get(_acs_selector, "selected_song");
    if (variable_instance_exists(_acs_selector, "selected_song_has_backstage"))
        _acs_selected_backstage = variable_instance_get(_acs_selector, "selected_song_has_backstage");
    if (variable_instance_exists(_acs_selector, "song_objects") && variable_instance_exists(_acs_selector, "cursor_pos"))
    {
        var _acs_song_objects = variable_instance_get(_acs_selector, "song_objects");
        var _acs_cursor_pos = variable_instance_get(_acs_selector, "cursor_pos");
        if (is_array(_acs_song_objects) && _acs_cursor_pos >= 0 && _acs_cursor_pos < array_length(_acs_song_objects))
        {
            var _acs_song_object = _acs_song_objects[_acs_cursor_pos];
            if (instance_exists(_acs_song_object) && variable_instance_exists(_acs_song_object, "diff"))
                _acs_selected_difficulty = variable_instance_get(_acs_song_object, "diff");
        }
    }
}

var _acs_is_worldcross = variable_global_exists("multiplayerLobby") && global.multiplayerLobby;
if (!_acs_is_worldcross && instance_exists(o_autochartswitch_bridge))
    o_autochartswitch_bridge.EmitSelection(_acs_selected_song, _acs_selected_difficulty, _acs_selected_backstage);

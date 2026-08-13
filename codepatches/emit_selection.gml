var _acs_selected_song = {};
var _acs_selected_difficulty = 0;
var _acs_selected_backstage = false;
if (variable_instance_exists(id, "selected_song"))
    _acs_selected_song = variable_instance_get(id, "selected_song");
else if (variable_global_exists("selected_song"))
    _acs_selected_song = variable_global_get("selected_song");
if (variable_instance_exists(id, "song_objects") && variable_instance_exists(id, "cursor_pos"))
{
    var _acs_song_object = song_objects[cursor_pos];
    if (instance_exists(_acs_song_object) && variable_instance_exists(_acs_song_object, "diff"))
        _acs_selected_difficulty = variable_instance_get(_acs_song_object, "diff");
}
if (variable_instance_exists(id, "selected_song_has_backstage"))
    _acs_selected_backstage = variable_instance_get(id, "selected_song_has_backstage");

if (instance_exists(o_autochartswitch_bridge))
    o_autochartswitch_bridge.EmitSelection(_acs_selected_song, _acs_selected_difficulty, _acs_selected_backstage);

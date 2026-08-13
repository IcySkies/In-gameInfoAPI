persistent = true;
acs_port = 28745;
acs_socket = -1;
acs_connecting = false;
acs_connected = false;
acs_retry = 0;
acs_sequence = 0;
acs_gameplay_active = false;
acs_last_chart = undefined;
acs_last_kind = "Selection";
acs_last_sent_key = "";
acs_last_lobby_key = "";
acs_jacket_dir = "AutoChartSwitchV2/Jackets";

acs_reset_connection = function(_retrySteps)
{
    acs_connected = false;
    acs_connecting = false;
    acs_retry = max(0, floor(_retrySteps));
    if (acs_socket >= 0)
    {
        try { network_destroy(acs_socket); } catch (e) { }
        acs_socket = -1;
    }
};

acs_safe_number = function(_value, _fallback)
{
    if (is_undefined(_value)) return _fallback;
    return real(_value);
};

acs_global_number = function(_name, _fallback)
{
    return variable_global_exists(_name) ? acs_safe_number(variable_global_get(_name), _fallback) : _fallback;
};

acs_refresh_tech_stats = function(_song, _rawDifficulty)
{
    global.note_stat = 0;
    global.tech_stat = 0;
    global.speed_stat = 0;
    global.multi_stat = 0;
    global.fill_stat = 0;
    global.gimmick_stat = 0;
    try { GetSongStats(_song, _rawDifficulty); }
    catch (e) { }
};

acs_song_value = function(_song, _name, _difficultyIndex, _fallback)
{
    if (!is_struct(_song)) return _fallback;
    var _value = variable_struct_exists(_song, _name) ? variable_struct_get(_song, _name) : _fallback;
    if (_difficultyIndex == 3 && variable_struct_exists(_song, "enc_data"))
    {
        var _encore = variable_struct_get(_song, "enc_data");
        if (is_struct(_encore) && variable_struct_exists(_encore, _name))
            _value = variable_struct_get(_encore, _name);
    }
    return _value;
};

acs_difficulty_name = function(_index, _backstage)
{
    switch (_index)
    {
        case 1: return "MIDDLE";
        case 2: return "FINALE";
        case 3: return _backstage ? "BACKSTAGE" : "ENCORE";
        default: return "OPENING";
    }
};

acs_difficulty_index = function(_rawDifficulty)
{
    switch (string_upper(string(_rawDifficulty)))
    {
        case "MIDDLE": return 1;
        case "FINALE": return 2;
        case "ENCORE": return 3;
        case "BACKSTAGE": return 3;
        default: return 0;
    }
};

acs_safe_filename = function(_value)
{
    var _source = string(_value);
    var _result = "";
    for (var _i = 1; _i <= string_length(_source); _i++)
    {
        var _character = string_char_at(_source, _i);
        var _code = ord(_character);
        var _allowed = (_code >= ord("0") && _code <= ord("9")) || (_code >= ord("A") && _code <= ord("Z")) || (_code >= ord("a") && _code <= ord("z")) || _character == "-" || _character == "_";
        _result += _allowed ? _character : "_";
    }
    return string_length(_result) > 0 ? _result : "unknown";
};

acs_path_join = function(_directory, _filename)
{
    if (string_length(_directory) == 0) return _filename;
    var _last = string_char_at(_directory, string_length(_directory));
    return (_last == "/" || _last == "\\") ? _directory + _filename : _directory + "/" + _filename;
};

acs_formatted_song_value = function(_song, _name, _difficultyIndex)
{
    var _value = acs_song_value(_song, "formatted_" + _name, _difficultyIndex, "");
    if (string_length(string(_value)) == 0)
        _value = acs_song_value(_song, _name + "_formatted", _difficultyIndex, "");
    return string(_value);
};

acs_export_jacket = function(_song, _difficultyIndex, _chartId, _rawDifficulty)
{
    if (!directory_exists(acs_jacket_dir))
    {
        try { directory_create(acs_jacket_dir); } catch (e) { }
    }
    if (!directory_exists(acs_jacket_dir)) return "";

    var _target = acs_path_join(acs_jacket_dir, acs_safe_filename(_chartId) + "-" + acs_safe_filename(_rawDifficulty) + ".png");
    if (file_exists(_target)) return _target;

    var _sprite = -1;
    try { _sprite = song_get_info(_song, "jacket", _difficultyIndex); }
    catch (e) { _sprite = acs_song_value(_song, "jacket", _difficultyIndex, -1); }
    if (_sprite == song_generic) return "";

    var _surface = -1;
    try { _surface = surface_create(500, 500); }
    catch (e) { return ""; }
    if (!surface_exists(_surface))
        return "";

    var _filtering = true;
    var _targeted = false;
    try
    {
        var _width = sprite_get_width(_sprite);
        var _height = sprite_get_height(_sprite);
        if (_width <= 0 || _height <= 0)
        {
            surface_free(_surface);
            return "";
        }
        _filtering = gpu_get_texfilter();
        surface_target(_surface);
        _targeted = true;
        draw_clear_alpha(c_black, 0);
        gpu_set_texfilter(false);
        draw_sprite_part_ext(_sprite, 0, 0, 0, _width, _height, 0, 0, 500 / _width, 500 / _height, c_white, 1);
        gpu_set_texfilter(_filtering);
        surface_untarget();
        _targeted = false;
        surface_save(_surface, _target);
    }
    catch (e)
    {
        if (_targeted)
        {
            try { surface_untarget(); } catch (ignored) { }
        }
        try { gpu_set_texfilter(_filtering); } catch (ignored) { }
        if (file_exists(_target)) try { file_delete(_target); } catch (ignored) { }
    }
    if (surface_exists(_surface)) surface_free(_surface);

    if (!file_exists(_target))
    {
        try { sprite_save(_sprite, 0, _target); }
        catch (e) { }
    }

    return file_exists(_target) ? _target : "";
};

acs_chart_snapshot = function(_song, _rawDifficulty, _difficultyIndex)
{
    if (!is_struct(_song)) _song = {};
    if (is_undefined(_difficultyIndex)) _difficultyIndex = 0;
    _difficultyIndex = clamp(floor(_difficultyIndex), 0, 3);

    var _chartId = variable_struct_exists(_song, "chart_id") ? variable_struct_get(_song, "chart_id") : (variable_struct_exists(_song, "song_id") ? variable_struct_get(_song, "song_id") : "");
    var _title = acs_song_value(_song, "name", _difficultyIndex, "");
    var _formattedTitle = acs_song_value(_song, "formatted_name", _difficultyIndex, "");
    var _artist = acs_song_value(_song, "artist", _difficultyIndex, "");
    var _illustrator = acs_song_value(_song, "jacket_artist", _difficultyIndex, "");
    var _formattedIllustrator = acs_formatted_song_value(_song, "jacket_artist", _difficultyIndex);
    var _difficultyKey = string("difficulty_constant_{0}", _difficultyIndex + 1);
    var _charterKey = string("note_designer_{0}", _difficultyIndex + 1);
    var _difficultyNumber = acs_song_value(_song, _difficultyKey, _difficultyIndex, 0);
    var _charter = acs_song_value(_song, _charterKey, _difficultyIndex, "");
    var _formattedCharter = acs_formatted_song_value(_song, _charterKey, _difficultyIndex);
    if (_difficultyIndex == 3 && is_struct(_song) && variable_struct_exists(_song, "enc_data"))
    {
        var _encoreData = variable_struct_get(_song, "enc_data");
        if (is_struct(_encoreData))
        {
            if (variable_struct_exists(_encoreData, "jacket_designer"))
                _illustrator = variable_struct_get(_encoreData, "jacket_designer");
            if (variable_struct_exists(_encoreData, "formatted_jacket_designer"))
                _formattedIllustrator = variable_struct_get(_encoreData, "formatted_jacket_designer");
            if (variable_struct_exists(_encoreData, "note_designer"))
                _charter = variable_struct_get(_encoreData, "note_designer");
            if (variable_struct_exists(_encoreData, "formatted_note_designer"))
                _formattedCharter = variable_struct_get(_encoreData, "formatted_note_designer");
        }
    }
    var _jacket = acs_export_jacket(_song, _difficultyIndex, _chartId, _rawDifficulty);

    return {
        chartId: _chartId,
        rawDifficultyName: _rawDifficulty,
        difficultyCode: _rawDifficulty,
        title: _title,
        formattedTitle: _formattedTitle,
        artist: _artist,
        formattedArtist: acs_formatted_song_value(_song, "artist", _difficultyIndex),
        illustrator: _illustrator,
        formattedIllustrator: _formattedIllustrator,
        charter: _charter,
        formattedCharter: _formattedCharter,
        difficultyNumber: acs_safe_number(_difficultyNumber, 0),
        jacketPath: _jacket,
        techStats: {
            chip: acs_global_number("note_stat", 0),
            tech: acs_global_number("tech_stat", 0),
            stream: acs_global_number("speed_stat", 0),
            chord: acs_global_number("multi_stat", 0),
            burst: acs_global_number("fill_stat", 0),
            gimmick: acs_global_number("gimmick_stat", 0)
        }
    };
};

if (file_exists("AutoChartSwitchV2/bridge.ini"))
{
    ini_open("AutoChartSwitchV2/bridge.ini");
    acs_port = ini_read_real("bridge", "port", acs_port);
    var _configuredJacketDir = ini_read_string("bridge", "jacket_path", "");
    if (string_length(_configuredJacketDir) > 0) acs_jacket_dir = _configuredJacketDir;
    ini_close();
}

EmitSelection = function(_song)
{
    if (!is_struct(_song)) _song = {};
    var _index = argument_count > 1 ? argument[1] : 0;
    var _backstage = argument_count > 2 ? argument[2] : false;
    _index = clamp(floor(_index), 0, 3);
    var _raw = acs_difficulty_name(_index, _backstage);
    var _chartId = variable_struct_exists(_song, "chart_id") ? variable_struct_get(_song, "chart_id") : (variable_struct_exists(_song, "song_id") ? variable_struct_get(_song, "song_id") : "");
    var _key = string("{0}|{1}", _chartId, _raw);
    var _changed = _key != acs_last_sent_key;

    if (!_changed && acs_last_kind == "Selection") return;

    var _chart = acs_chart_snapshot(_song, _raw, _index);
    acs_last_chart = _chart;
    acs_last_kind = "Selection";
    if (_changed)
    {
        acs_last_sent_key = _key;
        SendEvent("Selection", _chart);
    }
};

EmitLobbySelection = function(_song, _difficultyIndex)
{
    if (!is_struct(_song)) _song = {};
    _difficultyIndex = clamp(floor(_difficultyIndex), 0, 3);
    var _raw = acs_difficulty_name(_difficultyIndex, false);
    acs_refresh_tech_stats(_song, _raw);
    var _chart = acs_chart_snapshot(_song, _raw, _difficultyIndex);
    acs_last_chart = _chart;
    acs_last_kind = "LobbySelection";
    SendEvent("LobbySelection", _chart);
};

EmitLobbySelectionFromChoice = function(_choice)
{
    if (!is_struct(_choice)) return;
    var _songId = variable_struct_exists(_choice, "songId") ? variable_struct_get(_choice, "songId") : -1;
    var _difficulty = variable_struct_exists(_choice, "difficulty") ? variable_struct_get(_choice, "difficulty") : 0;
    var _song = {};
    try
    {
        if (variable_global_exists("song_list")) _song = global.song_list[_songId];
    }
    catch (e) { _song = {}; }
    var _chartId = variable_struct_exists(_song, "chart_id") ? variable_struct_get(_song, "chart_id") : string(_songId);
    var _key = string("{0}|{1}", _chartId, floor(_difficulty));
    if (_key == acs_last_lobby_key) return;
    acs_last_lobby_key = _key;
    EmitLobbySelection(_song, _difficulty);
};

EmitLobbySelectionFromQueue = function()
{
    if (!instance_exists(o_st_handle) || !variable_instance_exists(o_st_handle, "songQueue")) return;
    var _queue = o_st_handle.songQueue;
    if (!is_array(_queue) || array_length(_queue) == 0)
    {
        acs_last_lobby_key = "";
        return;
    }
    EmitLobbySelectionFromChoice(_queue[0]);
};

EmitStarted = function()
{
    var _song = struct_get_fallback(global, "currentSongInfo", {});
    var _raw = struct_get_fallback(global, "df_load", "OPENING");
    if (string_length(_raw) == 0) _raw = "OPENING";
    acs_last_chart = acs_chart_snapshot(_song, _raw, acs_difficulty_index(_raw));
    acs_last_kind = "ChartStarted";
    acs_gameplay_active = true;
    SendEvent("ChartStarted", acs_last_chart);
};

EmitLoadingStarted = function()
{
    var _song = struct_get_fallback(global, "currentSongInfo", undefined);
    var _raw = struct_get_fallback(global, "df_load", "OPENING");
    if (string_length(_raw) == 0) _raw = "OPENING";
    if (is_struct(_song))
        acs_last_chart = acs_chart_snapshot(_song, _raw, acs_difficulty_index(_raw));
    else if (is_undefined(acs_last_chart))
        acs_last_chart = acs_chart_snapshot({}, _raw, acs_difficulty_index(_raw));
    acs_last_kind = "ChartLoadingStarted";
    SendEvent("ChartLoadingStarted", acs_last_chart);
};

EmitExitTransitionStarted = function()
{
    if (!acs_gameplay_active) return;
    acs_gameplay_active = false;
    acs_last_kind = "ChartExitTransitionStarted";
    SendEvent("ChartExitTransitionStarted", acs_last_chart);
};

EmitGameplayEnded = function()
{
    if (!acs_gameplay_active) return;
    acs_gameplay_active = false;
    acs_last_lobby_key = "";
    acs_last_kind = "GameplayEnded";
    SendEvent("GameplayEnded", acs_last_chart);
};

SendEvent = function(_kind, _chart)
{
    acs_sequence += 1;
    var _envelope = {
        protocolVersion: 1,
        sequence: acs_sequence,
        kind: _kind,
        chart: _chart
    };
    var _json = json_stringify(_envelope);
    if (acs_connected)
    {
        var _size = string_byte_length(_json);
        var _buffer = buffer_create(4 + _size + 1, buffer_grow, 1);
        buffer_seek(_buffer, buffer_seek_start, 4);
        buffer_write(_buffer, buffer_text, _json);
        var _payloadSize = buffer_tell(_buffer) - 4;
        buffer_seek(_buffer, buffer_seek_start, 0);
        buffer_write(_buffer, buffer_u32, _payloadSize);
        var _frameSize = 4 + _payloadSize;
        var _sent = -1;
        try { _sent = network_send_raw(acs_socket, _buffer, _frameSize); }
        catch (e) { }
        buffer_delete(_buffer);
        if (_sent != _frameSize) acs_reset_connection(60);
    }
};

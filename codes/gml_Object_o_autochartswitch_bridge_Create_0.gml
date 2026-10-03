persistent = true;
acs_port = 28745;
acs_socket = -1;
acs_connecting = false;
acs_connected = false;
acs_retry = 0;
acs_retry_delay = 60;
acs_sequence = 0;
acs_session_id = string("{0}-{1}", current_time, irandom(2147483647));
acs_gameplay_active = false;
acs_state = "Idle";
acs_state_changed_at = current_time;
acs_last_chart = undefined;
acs_last_kind = "Selection";
acs_last_chart_info = undefined;
acs_last_chart_info_key = "";
acs_selection_confirmed = false;
acs_last_sent_key = "";
acs_last_lobby_key = "";
acs_last_lobby_song = undefined;
acs_last_room_signature = "";
acs_last_gameplay_signature = "";
acs_last_play_scores = [];
acs_jacket_dir = "AutoChartSwitchV2/Jackets";
acs_event_queue = [];
acs_event_queue_limit = 32;
acs_dropped_events = 0;
acs_source = "vivid/stasis";
acs_capabilities = ["chart-selection", "worldcross-selection", "worldcross-room", "worldcross-gameplay", "lifecycle", "tech-stats", "jacket-export"];
acs_relay_warning = false;
acs_warning_shown = false;
acs_stats = {};

acs_reset_connection = function(_retrySteps)
{
    acs_connected = false;
    acs_connecting = false;
    acs_retry = max(0, floor(_retrySteps));
    acs_retry_delay = min(600, max(60, floor(acs_retry_delay * 2)));
    acs_relay_warning = true;
    if (!acs_warning_shown)
    {
        acs_warning_shown = true;
        show_debug_message("VividStasis game information relay is unavailable; retrying in the background.");
    }
    if (acs_socket >= 0)
    {
        try { network_destroy(acs_socket); } catch (e) { }
        acs_socket = -1;
    }
};

acs_set_state = function(_state)
{
    acs_state = string(_state);
    acs_state_changed_at = current_time;
};

acs_is_important_kind = function(_kind)
{
    return _kind == "ChartLoadingStarted" || _kind == "ChartStarted" || _kind == "ChartExitTransitionStarted" || _kind == "GameplayEnded";
};

acs_queue_event = function(_envelope)
{
    // ChartInfo and telemetry updates are snapshots. Keep only the newest queued one.
    if (_envelope.kind == "ChartInfo" || _envelope.kind == "Selection" || _envelope.kind == "WorldcrossRoom" || _envelope.kind == "WorldcrossGameplay")
    {
        var _selectionQueue = [];
        for (var _i = 0; _i < array_length(acs_event_queue); _i++)
            if (acs_event_queue[_i].kind != _envelope.kind) array_push(_selectionQueue, acs_event_queue[_i]);
        acs_event_queue = _selectionQueue;
    }

    while (array_length(acs_event_queue) >= acs_event_queue_limit)
    {
        var _removed = false;
        for (var _j = 0; _j < array_length(acs_event_queue); _j++)
        {
            if (!acs_is_important_kind(acs_event_queue[_j].kind))
            {
                array_delete(acs_event_queue, _j, 1);
                _removed = true;
                break;
            }
        }
        if (!_removed) array_delete(acs_event_queue, 0, 1);
        acs_dropped_events += 1;
    }
    array_push(acs_event_queue, _envelope);
};

acs_send_envelope = function(_envelope)
{
    if (!acs_connected || acs_socket < 0) return false;
    var _json = json_stringify(_envelope);
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
    if (_sent != _frameSize)
    {
        acs_reset_connection(acs_retry_delay);
        return false;
    }
    return true;
};

acs_flush_events = function()
{
    while (acs_connected && array_length(acs_event_queue) > 0)
    {
        var _event = acs_event_queue[0];
        if (!acs_send_envelope(_event)) return;
        array_delete(acs_event_queue, 0, 1);
    }
};

acs_build_envelope = function(_kind, _chart, _replay)
{
    acs_sequence += 1;
    var _envelope = {
        protocolVersion: 1,
        sequence: acs_sequence,
        sessionId: acs_session_id,
        eventId: string("{0}:{1}", acs_session_id, acs_sequence),
        game: acs_source,
        kind: _kind,
        state: acs_state,
        stateChangedAtMs: acs_state_changed_at,
        gameTimeMs: current_time,
        replay: _replay,
        capabilities: acs_capabilities,
        droppedEvents: acs_dropped_events,
        chart: _chart
    };
    if (argument_count > 3 && !is_undefined(argument[3]))
        variable_struct_set(_envelope, "worldcross", argument[3]);
    acs_dropped_events = 0;
    return _envelope;
};

acs_safe_number = function(_value, _fallback)
{
    if (is_undefined(_value)) return _fallback;
    var _number = real(_value);
    // GameMaker can expose NaN/Infinity when a Shatter stat has no source
    // value. Never put a non-finite value on the JSON wire.
    if (_number != _number || _number > 100000000 || _number < -100000000) return _fallback;
    return _number;
};

acs_safe_score = function(_value, _fallback)
{
    if (is_undefined(_value)) return _fallback;
    var _number = real(_value);
    // Worldcross's legitimate maximum score is 1,010,000. Keep a broad
    // finite bound here; the generic helper is also used for chart stats.
    if (_number != _number || _number > 1010000 || _number < 0) return _fallback;
    return _number;
};

acs_global_number = function(_name, _fallback)
{
    return variable_global_exists(_name) ? acs_safe_number(variable_global_get(_name), _fallback) : _fallback;
};

acs_refresh_tech_stats = function(_song, _rawDifficulty)
{
    var _names = ["note_stat", "tech_stat", "speed_stat", "multi_stat", "fill_stat", "gimmick_stat",
        "stat_total", "stat_total_v2", "stat_total_v3", "temp_level_note", "temp_level_speed",
        "temp_level_tech", "temp_level_multi", "has_mods"];
    var _original = [];
    var _existed = [];
    acs_stats = {};
    // GetSongStats initializes its outputs itself. ss_notecount is not a
    // prerequisite in 6.2.2.2; requiring it skips every normal selection.
    for (var _i = 0; _i < array_length(_names); _i++)
    {
        var _exists = variable_global_exists(_names[_i]);
        array_push(_existed, _exists);
        array_push(_original, _exists ? variable_global_get(_names[_i]) : undefined);
        if (_exists && _i < 6) variable_global_set(_names[_i], 0);
    }
    try
    {
        var _statsDifficulty = string_upper(string(_rawDifficulty)) == "BACKSTAGE" ? "ENCORE" : _rawDifficulty;
        GetSongStats(_song, _statsDifficulty);
        for (var _k = 0; _k < 6; _k++)
            variable_struct_set(acs_stats, _names[_k], acs_global_number(_names[_k], 0));
    }
    catch (e) { acs_stats = {}; }
    for (var _r = 0; _r < array_length(_names); _r++)
    {
        if (_existed[_r]) variable_global_set(_names[_r], _original[_r]);
    }
};

acs_stat = function(_name)
{
    return variable_struct_exists(acs_stats, _name) ? variable_struct_get(acs_stats, _name) : 0;
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

acs_is_shatter_song = function(_song)
{
    return is_struct(_song) && variable_struct_exists(_song, "difficulty_name") && variable_struct_exists(_song, "note_designer");
};

acs_song_difficulty_name = function(_song, _difficultyIndex, _backstage)
{
    if (acs_is_shatter_song(_song))
    {
        var _shatterName = variable_struct_get(_song, "difficulty_name");
        if (string_length(string(_shatterName)) > 0) return string(_shatterName);
    }
    return acs_difficulty_name(_difficultyIndex, _backstage);
};

acs_difficulty_name = function(_index, _backstage)
{
    switch (_index)
    {
        case 1: return "MIDDLE";
        case 2: return "FINALE";
        case 3: return _backstage ? "BACKSTAGE" : "ENCORE";
        case 4: return "PRELUDE";
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
        case "PRELUDE": return 4;
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
    if (_sprite == song_generic || !sprite_exists(_sprite)) return "";

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
        var _temporaryTarget = _target + ".tmp.png";
        if (file_exists(_temporaryTarget)) file_delete(_temporaryTarget);
        surface_save(_surface, _temporaryTarget);
        if (file_exists(_temporaryTarget)) file_rename(_temporaryTarget, _target);
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
    _difficultyIndex = clamp(floor(_difficultyIndex), 0, 4);

    var _chartId = variable_struct_exists(_song, "chart_id") ? variable_struct_get(_song, "chart_id") : (variable_struct_exists(_song, "song_id") ? variable_struct_get(_song, "song_id") : "");
    var _title = acs_song_value(_song, "name", _difficultyIndex, "");
    var _formattedTitle = acs_song_value(_song, "formatted_name", _difficultyIndex, "");
    var _artist = acs_song_value(_song, "artist", _difficultyIndex, "");
    var _illustrator = acs_song_value(_song, "jacket_artist", _difficultyIndex, "");
    var _formattedIllustrator = acs_formatted_song_value(_song, "jacket_artist", _difficultyIndex);
    var _difficultyKey = string("difficulty_constant_{0}", _difficultyIndex + 1);
    var _charterKey = string("note_designer_{0}", _difficultyIndex + 1);
    var _difficultyNumber = acs_is_shatter_song(_song)
        ? acs_song_value(_song, "difficulty_number", _difficultyIndex, 0)
        : acs_song_value(_song, _difficultyKey, _difficultyIndex, 0);
    var _charter = acs_is_shatter_song(_song)
        ? acs_song_value(_song, "note_designer", _difficultyIndex, "")
        : acs_song_value(_song, _charterKey, _difficultyIndex, "");
    var _formattedCharter = acs_is_shatter_song(_song)
        ? acs_formatted_song_value(_song, "note_designer", _difficultyIndex)
        : acs_formatted_song_value(_song, _charterKey, _difficultyIndex);
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
    var _jacket = "";
    try { _jacket = acs_export_jacket(_song, _difficultyIndex, _chartId, _rawDifficulty); }
    catch (e) { }

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
            chip: acs_stat("note_stat"),
            tech: acs_stat("tech_stat"),
            stream: acs_stat("speed_stat"),
            chord: acs_stat("multi_stat"),
            burst: acs_stat("fill_stat"),
            gimmick: acs_stat("gimmick_stat")
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

acs_member_value = function(_member, _name, _fallback)
{
    if (!is_struct(_member) || !variable_struct_exists(_member, _name)) return _fallback;
    var _value = variable_struct_get(_member, _name);
    return is_undefined(_value) ? _fallback : _value;
};

acs_worldcross_member_score = function(_member, _fallback)
{
    // Better Worldcross renames the live score field to score_ and leaves
    // the legacy score field at zero. Prefer the renamed field when present.
    if (is_struct(_member) && variable_struct_exists(_member, "score_"))
        return acs_safe_score(variable_struct_get(_member, "score_"), _fallback);
    return acs_safe_score(acs_member_value(_member, "score", _fallback), _fallback);
};

acs_worldcross_score_index = function(_id)
{
    var _key = string(_id);
    for (var _i = 0; _i < array_length(acs_last_play_scores); _i++)
    {
        var _cached = acs_last_play_scores[_i];
        if (is_struct(_cached) && variable_struct_exists(_cached, "steamId64") && string(variable_struct_get(_cached, "steamId64")) == _key)
            return _i;
    }
    return -1;
};

acs_worldcross_cached_score = function(_index)
{
    if (_index < 0 || _index >= array_length(acs_last_play_scores)) return 0;
    var _cached = acs_last_play_scores[_index];
    if (!is_struct(_cached) || !variable_struct_exists(_cached, "score")) return 0;
    return acs_safe_score(variable_struct_get(_cached, "score"), 0);
};

acs_worldcross_cache_score = function(_member)
{
    var _key = string(acs_member_value(_member, "id", ""));
    if (string_length(_key) == 0) return;
    var _score = acs_worldcross_member_score(_member, 0);
    var _index = acs_worldcross_score_index(_key);
    if (_index < 0) array_push(acs_last_play_scores, { steamId64: _key, score: _score });
    else
    {
        var _cached = acs_last_play_scores[_index];
        if (is_struct(_cached)) variable_struct_set(_cached, "score", _score);
        else acs_last_play_scores[_index] = { steamId64: _key, score: _score };
    }
};

acs_worldcross_capture_scores = function()
{
    if (!instance_exists(o_st_handle) || !variable_instance_exists(o_st_handle, "lobbyMembers")) return;
    var _members = o_st_handle.lobbyMembers;
    if (!is_array(_members)) return;
    for (var _i = 0; _i < array_length(_members); _i++)
    {
        var _member = _members[_i];
        if (!acs_member_value(_member, "npc", false)) acs_worldcross_cache_score(_member);
    }
};

acs_worldcross_label = function(_flag)
{
    var _text = string(_flag);
    if (_text == "FC" || _text == "AC" || _text == "VS") return _text;
    if (string_pos("Value_2", _text) > 0 || real(_flag) == 2) return "FC";
    if (string_pos("Value_3", _text) > 0 || real(_flag) == 3) return "AC";
    if (string_pos("Value_4", _text) > 0 || real(_flag) == 4) return "VS";
    return "";
};

acs_worldcross_state = function(_ready)
{
    var _value = acs_safe_number(_ready, 0);
    if (_value == 2) return "playing";
    if (_value == 1) return "ready";
    return "unready";
};

acs_worldcross_snapshot = function()
{
    var _players = [];
    if (!instance_exists(o_st_handle) || !variable_instance_exists(o_st_handle, "lobbyMembers")) return { players: _players };
    var _members = o_st_handle.lobbyMembers;
    if (!is_array(_members)) return { players: _players };
    for (var _i = 0; _i < array_length(_members); _i++)
    {
        var _member = _members[_i];
        if (!is_struct(_member) || acs_member_value(_member, "npc", false)) continue;
        var _id = string(acs_member_value(_member, "id", ""));
        var _last = 0;
        var _index = acs_worldcross_score_index(_id);
        if (_index >= 0) _last = acs_worldcross_cached_score(_index);
        array_push(_players, {
            steamId64: _id,
            name: string(acs_member_value(_member, "name", "")),
            state: acs_worldcross_state(acs_member_value(_member, "ready", 0)),
            rating: acs_safe_number(acs_member_value(_member, "rate", 0), 0),
            class: floor(acs_safe_number(acs_member_value(_member, "class", 0), 0)),
            score: acs_worldcross_member_score(_member, 0),
            lastPlayScore: _last,
            label: acs_worldcross_label(acs_member_value(_member, "scoreFlag", ""))
        });
    }
    return { players: _players };
};

SendTelemetry = function(_kind, _worldcross)
{
    var _envelope = acs_build_envelope(_kind, undefined, false, _worldcross);
    acs_queue_event(_envelope);
    acs_flush_events();
};

acs_emit_worldcross_snapshot = function(_gameplay)
{
    var _worldcross = acs_worldcross_snapshot();
    var _signature = json_stringify(_worldcross);
    if (_gameplay)
    {
        if (_signature == acs_last_gameplay_signature) return;
        SendTelemetry("WorldcrossGameplay", _worldcross);
        acs_last_gameplay_signature = _signature;
    }
    else
    {
        if (_signature == acs_last_room_signature) return;
        SendTelemetry("WorldcrossRoom", _worldcross);
        acs_last_room_signature = _signature;
    }
};

EmitChartInfo = function(_song)
{
    if (!is_struct(_song)) _song = {};
    var _index = argument_count > 1 ? argument[1] : 0;
    var _backstage = argument_count > 2 ? argument[2] : false;
    _index = clamp(floor(_index), 0, 3);
    var _raw = acs_song_difficulty_name(_song, _index, _backstage);
    var _chartId = variable_struct_exists(_song, "chart_id") ? variable_struct_get(_song, "chart_id") : (variable_struct_exists(_song, "song_id") ? variable_struct_get(_song, "song_id") : "");
    var _key = string("{0}|{1}", _chartId, _raw);
    var _changed = _key != acs_last_sent_key;

    if (!_changed && acs_last_chart_info != undefined) return;

    acs_refresh_tech_stats(_song, _raw);
    var _chart = acs_chart_snapshot(_song, _raw, _index);
    acs_last_chart = _chart;
    acs_last_chart_info = _chart;
    acs_last_chart_info_key = _key;
    acs_last_kind = "ChartInfo";
    acs_set_state("Selection");
    if (_changed)
    {
        acs_last_sent_key = _key;
        SendEvent("ChartInfo", _chart);
    }
};

EmitSelection = function(_song)
{
    // Ensure the confirmed chart is represented by a preceding ChartInfo
    // snapshot, then emit a chartless confirmation marker.
    EmitChartInfo(_song, argument_count > 1 ? argument[1] : 0, argument_count > 2 ? argument[2] : false);
    acs_selection_confirmed = true;
    acs_last_kind = "Selection";
    acs_set_state("Selection");
    SendEvent("Selection", undefined);
};

EmitLobbySelection = function(_song, _difficultyIndex)
{
    if (!is_struct(_song)) _song = {};
    var _requestedDifficulty = floor(_difficultyIndex);
    var _raw = acs_song_difficulty_name(_song, _requestedDifficulty, false);
    _difficultyIndex = clamp(_requestedDifficulty, 0, 4);
    acs_refresh_tech_stats(_song, _raw);
    var _chart = acs_chart_snapshot(_song, _raw, _difficultyIndex);
    acs_last_chart = _chart;
    acs_last_chart_info = _chart;
    acs_last_chart_info_key = string("{0}|{1}", variable_struct_exists(_song, "chart_id") ? variable_struct_get(_song, "chart_id") : (variable_struct_exists(_song, "song_id") ? variable_struct_get(_song, "song_id") : ""), _raw);
    acs_selection_confirmed = true;
    acs_last_kind = "LobbySelection";
    acs_set_state("Lobby");
    SendEvent("LobbySelection", _chart);
};

EmitLobbySelectionFromChoice = function(_choice)
{
    var _previousKey = acs_last_lobby_key;
    var _previousSong = acs_last_lobby_song;
    acs_last_lobby_key = "";
    acs_last_lobby_song = undefined;
    if (!is_struct(_choice)) return;
    var _songId = variable_struct_exists(_choice, "songId") ? variable_struct_get(_choice, "songId") : -1;
    var _difficulty = variable_struct_exists(_choice, "difficulty") ? variable_struct_get(_choice, "difficulty") : 0;
    if (!is_real(_difficulty) || _difficulty != _difficulty) return;
    var _song = undefined;
    var _chartId = variable_struct_exists(_choice, "chart_id") && !is_undefined(_choice.chart_id) ? string(_choice.chart_id) : "";
    if (_chartId == "generic") _chartId = "";
    if (_chartId != "")
    {
        var _lists = [];
        if (variable_global_exists("song_list") && is_array(global.song_list)) array_push(_lists, global.song_list);
        if (variable_global_exists("shatter_list") && is_array(global.shatter_list)) array_push(_lists, global.shatter_list);
        if (is_real(_songId) && _songId >= 0 && _songId == floor(_songId))
        {
            for (var _k = 0; _k < array_length(_lists); _k++)
            {
                var _indexed = _lists[_k];
                if (_songId < array_length(_indexed) && is_struct(_indexed[_songId])
                    && variable_struct_exists(_indexed[_songId], "chart_id")
                    && string_lower(string(_indexed[_songId].chart_id)) == string_lower(_chartId))
                {
                    _song = _indexed[_songId];
                    break;
                }
            }
        }
        for (var _l = 0; _l < array_length(_lists) && is_undefined(_song); _l++)
        {
            var _list = _lists[_l];
            for (var _i = 0; _i < array_length(_list); _i++)
            {
                var _candidate = _list[_i];
                if (is_struct(_candidate) && variable_struct_exists(_candidate, "chart_id")
                    && string_lower(string(variable_struct_get(_candidate, "chart_id"))) == string_lower(_chartId))
                {
                    _song = _candidate;
                    break;
                }
            }
        }
    }
    else if (variable_global_exists("op_vs_custom_server") && global.op_vs_custom_server == 1)
        return;
    else if (is_real(_songId) && _songId >= 0 && _songId == floor(_songId))
    {
        var _source = _difficulty < 0 && variable_global_exists("shatter_list") ? global.shatter_list
            : (variable_global_exists("song_list") ? global.song_list : undefined);
        if (is_array(_source) && _songId < array_length(_source) && is_struct(_source[_songId]))
            _song = _source[_songId];
    }
    if (!is_struct(_song) || (variable_struct_exists(_song, "is_missing") && _song.is_missing)) return;
    if (_chartId == "") _chartId = string(variable_struct_exists(_song, "chart_id") ? _song.chart_id : _songId);
    var _raw = acs_song_difficulty_name(_song, _difficulty, false);
    var _key = string("{0}|{1}|{2}", _chartId, _raw, _difficulty);
    if (_key == _previousKey && _song == _previousSong)
    {
        acs_last_lobby_key = _key;
        acs_last_lobby_song = _song;
        return;
    }
    EmitLobbySelection(_song, _difficulty);
    acs_last_lobby_key = _key;
    acs_last_lobby_song = _song;
};

EmitLobbySelectionFromQueue = function()
{
    if (!instance_exists(o_st_handle) || !variable_instance_exists(o_st_handle, "songQueue")) return;
    var _queue = o_st_handle.songQueue;
    if (!is_array(_queue) || array_length(_queue) == 0 || !is_struct(_queue[0]))
    {
        acs_last_lobby_key = "";
        acs_last_lobby_song = undefined;
        return;
    }
    EmitLobbySelectionFromChoice(_queue[0]);
};

EmitStarted = function()
{
    acs_last_room_signature = "";
    acs_last_gameplay_signature = "";
    var _song = struct_get_fallback(global, "currentSongInfo", {});
    var _raw = struct_get_fallback(global, "df_load", "OPENING");
    if (string_length(_raw) == 0) _raw = "OPENING";
    acs_refresh_tech_stats(_song, _raw);
    acs_last_chart = acs_chart_snapshot(_song, _raw, acs_difficulty_index(_raw));
    acs_last_kind = "ChartStarted";
    acs_set_state("Gameplay");
    acs_gameplay_active = true;
    SendEvent("ChartStarted", acs_last_chart);
};

EmitLoadingStarted = function()
{
    var _song = struct_get_fallback(global, "currentSongInfo", undefined);
    var _raw = struct_get_fallback(global, "df_load", "OPENING");
    if (string_length(_raw) == 0) _raw = "OPENING";
    if (is_struct(_song))
    {
        acs_refresh_tech_stats(_song, _raw);
        acs_last_chart = acs_chart_snapshot(_song, _raw, acs_difficulty_index(_raw));
    }
    else if (is_undefined(acs_last_chart))
    {
        acs_stats = {};
        acs_last_chart = acs_chart_snapshot({}, _raw, acs_difficulty_index(_raw));
    }
    acs_last_kind = "ChartLoadingStarted";
    acs_set_state("Loading");
    SendEvent("ChartLoadingStarted", acs_last_chart);
};

EmitExitTransitionStarted = function()
{
    if (!acs_gameplay_active) return;
    acs_worldcross_capture_scores();
    acs_gameplay_active = false;
    acs_selection_confirmed = false;
    acs_last_kind = "ChartExitTransitionStarted";
    acs_set_state("Exiting");
    SendEvent("ChartExitTransitionStarted", acs_last_chart);
};

EmitGameplayEnded = function()
{
    if (!acs_gameplay_active) return;
    acs_worldcross_capture_scores();
    acs_gameplay_active = false;
    acs_last_lobby_key = "";
    acs_selection_confirmed = false;
    acs_last_kind = "GameplayEnded";
    acs_set_state("Ended");
    SendEvent("GameplayEnded", acs_last_chart);
};

SendEvent = function(_kind, _chart)
{
    var _envelope = acs_build_envelope(_kind, _chart, false);
    acs_queue_event(_envelope);
    acs_flush_events();
};

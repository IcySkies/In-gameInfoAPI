const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");

// Execute the JavaScript-compatible subset of the actual GML with GM API mocks.
// Compilation and runner-specific behavior are validated separately by the loader.
const source = fs.readFileSync(path.join(__dirname, "../codes/gml_Object_o_autochartswitch_bridge_Create_0.gml"), "utf8");
const step = fs.readFileSync(path.join(__dirname, "../codes/gml_Object_o_autochartswitch_bridge_Step_0.gml"), "utf8");
function context() {
    const ctx = vm.createContext({
        global: {}, acs_stats: {}, acs_last_lobby_key: "", acs_last_lobby_song: undefined,
        is_struct: v => v !== null && typeof v === "object" && !Array.isArray(v),
        is_array: Array.isArray, is_real: v => typeof v === "number", is_undefined: v => v === undefined,
        array_length: a => a.length, array_push: (a, v) => a.push(v),
        variable_struct_exists: (s, k) => Object.hasOwn(s, k),
        variable_struct_get: (s, k) => s[k], variable_struct_set: (s, k, v) => { s[k] = v; },
        floor: Math.floor, max: Math.max, min: Math.min, abs: Math.abs, real: Number,
        clamp: (v, lo, hi) => Math.min(hi, Math.max(lo, v)),
        string_upper: v => String(v).toUpperCase(), string_lower: v => String(v).toLowerCase(),
        string_length: v => String(v).length,
        string: (v, ...args) => args.length ? String(v).replace(/\{(\d+)\}/g, (_, n) => String(args[n])) : String(v),
        LoadSongDataNoteCount: () => 10, GetSongStats: () => {},
        EmitLobbySelection: () => {},
    });
    ctx.variable_global_exists = k => Object.hasOwn(ctx.global, k);
    ctx.variable_global_get = k => ctx.global[k];
    ctx.variable_global_set = (k, v) => { ctx.global[k] = v; };
    for (const name of [
        "acs_safe_number", "acs_global_number", "acs_refresh_tech_stats", "acs_stat",
        "acs_is_shatter_song", "acs_song_difficulty_name", "acs_difficulty_name",
        "EmitLobbySelectionFromChoice", "EmitLobbySelectionFromQueue",
    ]) {
        const start = source.indexOf(`${name} = function(`);
        assert.notEqual(start, -1, `Missing GML function ${name}`);
        const end = source.indexOf("\n};", start) + 3;
        vm.runInContext(source.slice(start, end), ctx);
    }
    return ctx;
}
const song = (id, extra = {}) => ({ chart_id: id, name: id, ...extra });

test("chart ID takes precedence over a mismatched numeric index without mutating queue", () => {
    const ctx = context();
    ctx.global.song_list = [song("wrong"), song("right")];
    const choice = { songId: 0, difficulty: 3, chart_id: "RIGHT" };
    const before = JSON.stringify(choice);
    const events = [];
    ctx.EmitLobbySelection = (...args) => events.push(args);
    ctx.EmitLobbySelectionFromChoice(choice);
    ctx.EmitLobbySelectionFromChoice(choice);
    assert.equal(events.length, 1);
    assert.equal(events[0][0], ctx.global.song_list[1]);
    assert.equal(JSON.stringify(choice), before);
});

test("unresolved, missing and sparse entries emit nothing, and resolved replacements re-emit", () => {
    const ctx = context();
    ctx.global.op_vs_custom_server = 1;
    ctx.global.song_list = [0, undefined];
    const events = [];
    ctx.EmitLobbySelection = (...args) => events.push(args);
    const choice = { songId: 0, difficulty: 2, chart_id: "custom" };
    ctx.EmitLobbySelectionFromChoice(choice);
    ctx.EmitLobbySelectionFromChoice({ songId: 0, difficulty: 2 });
    ctx.global.song_list.push(song("custom", { is_missing: true }));
    ctx.EmitLobbySelectionFromChoice(choice);
    assert.equal(events.length, 0);
    ctx.global.song_list[2] = song("custom");
    ctx.EmitLobbySelectionFromChoice(choice);
    ctx.global.song_list[2] = song("custom", { artist: "new metadata" });
    ctx.EmitLobbySelectionFromChoice(choice);
    choice.difficulty = 3;
    ctx.EmitLobbySelectionFromChoice(choice);
    assert.equal(events.length, 3);
});

test("legacy indices, Shatter and queue clear/reselect remain supported", () => {
    const ctx = context();
    ctx.global.song_list = [song("official")];
    ctx.global.shatter_list = [song("shatter", { difficulty_name: "SHATTER", note_designer: "author" })];
    const events = [];
    ctx.EmitLobbySelection = (...args) => events.push(args);
    for (const id of [-1, 0.5, 2, "0", NaN]) ctx.EmitLobbySelectionFromChoice({ songId: id, difficulty: 0 });
    assert.equal(events.length, 0);
    ctx.EmitLobbySelectionFromChoice({ songId: 0, difficulty: 0 });
    ctx.EmitLobbySelectionFromChoice({ songId: 0, difficulty: -1 });
    assert.equal(events[1][0], ctx.global.shatter_list[0]);
    ctx.o_st_handle = { songQueue: [] };
    ctx.instance_exists = () => true;
    ctx.variable_instance_exists = (s, k) => Object.hasOwn(s, k);
    ctx.EmitLobbySelectionFromQueue();
    ctx.o_st_handle.songQueue = [{ songId: 0, difficulty: -1 }];
    ctx.EmitLobbySelectionFromQueue();
    assert.equal(events.length, 3);
});

const statNames = ["note_stat", "tech_stat", "speed_stat", "multi_stat", "fill_stat", "gimmick_stat", "ss_notecount"];
test("successful calculation publishes private stats and restores all native globals", () => {
    const ctx = context();
    statNames.forEach((k, i) => { ctx.global[k] = 100 + i; });
    const before = { ...ctx.global };
    ctx.GetSongStats = (_, difficulty) => {
        assert.equal(difficulty, "ENCORE");
        assert.equal(ctx.global.ss_notecount, before.ss_notecount);
        statNames.slice(0, 6).forEach((k, i) => { ctx.global[k] = i + 1; });
    };
    ctx.acs_refresh_tech_stats(song("backstage"), "BACKSTAGE");
    assert.deepEqual(ctx.global, before);
    assert.equal(ctx.acs_stat("note_stat"), 1);
    assert.equal(ctx.acs_stat("gimmick_stat"), 6);
});

test("native errors restore globals and never publish partially calculated stats", () => {
    const ctx = context();
    statNames.forEach((k, i) => { ctx.global[k] = i; });
    const before = { ...ctx.global };
    ctx.GetSongStats = () => { ctx.global.note_stat = 99; throw new Error("missing chart"); };
    ctx.acs_refresh_tech_stats(song("missing"), "FINALE");
    assert.deepEqual(ctx.global, before);
    assert.equal(ctx.acs_stat("note_stat"), 0);
});

test("uninitialized stat globals do not prevent the native calculation", () => {
    const ctx = context();
    ctx.global.note_stat = 9;
    ctx.GetSongStats = () => { ctx.global.tech_stat = 12; };
    ctx.acs_refresh_tech_stats(song("early"), "OPENING");
    assert.deepEqual(ctx.global, { note_stat: 9, tech_stat: 12 });
    assert.equal(ctx.acs_stat("tech_stat"), 12);
});

function stepContext(overrides = {}) {
    const ctx = {
        global: { multiplayerLobby: true, vs_ws: { state: 1 } },
        variable_global_exists: k => Object.hasOwn(ctx.global, k),
        variable_struct_exists: (s, k) => Object.hasOwn(s, k),
        is_struct: v => v !== null && typeof v === "object",
        acs_connected: false, acs_connecting: false, acs_retry: 0, acs_socket: -1,
        acs_gameplay_active: false, acs_state: "Lobby",
        cc: "cc", o_transitionsong: "loading", o_transition_diamond: "exiting", instance_exists: () => false,
        network_create_socket: () => { ctx.attempts++; return 5; },
        network_connect_raw_async: () => 0, network_socket_tcp: 1, acs_port: 28745,
        EmitLobbySelectionFromQueue: () => { ctx.selections++; },
        acs_emit_worldcross_snapshot: () => {}, acs_flush_events: () => {},
        acs_reset_connection: () => {}, attempts: 0, selections: 0,
        ...overrides,
    };
    return vm.createContext(ctx);
}
test("connecting WebSocket defers relay attempts, then allows reconnect without blocking selection", () => {
    const ctx = stepContext();
    vm.runInContext(step, ctx);
    assert.equal(ctx.attempts, 0);
    assert.equal(ctx.selections, 1);
    ctx.global.vs_ws.state = 3;
    vm.runInContext(step, ctx);
    assert.equal(ctx.attempts, 1);
});

test("queue publication waits for transitions and resumes on return to the lobby", () => {
    for (const transition of ["loading", "exiting"]) {
        const ctx = stepContext({ instance_exists: object => object === transition });
        vm.runInContext(step, ctx);
        assert.equal(ctx.selections, 0);
        ctx.instance_exists = () => false;
        vm.runInContext(step, ctx);
        assert.equal(ctx.selections, 1);
    }
});

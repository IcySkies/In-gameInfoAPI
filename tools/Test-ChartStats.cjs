const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");

const source = fs.readFileSync(path.join(__dirname, "../codes/gml_Object_o_autochartswitch_bridge_Create_0.gml"), "utf8");
const stats = ["note_stat", "tech_stat", "speed_stat", "multi_stat", "fill_stat", "gimmick_stat"];
const nativeGlobals = [...stats, "stat_total", "stat_total_v2", "stat_total_v3",
    "temp_level_note", "temp_level_speed", "temp_level_tech", "temp_level_multi", "has_mods"];

function context() {
    const ctx = vm.createContext({
        global: {}, acs_stats: {}, argument_count: 3, argument: [undefined, 2, false],
        acs_last_sent_key: "", acs_last_chart_info: undefined, acs_last_chart: undefined,
        is_struct: v => v !== null && typeof v === "object" && !Array.isArray(v),
        is_undefined: v => v === undefined,
        array_length: a => a.length, array_push: (a, v) => a.push(v),
        variable_struct_exists: (s, k) => Object.hasOwn(s, k),
        variable_struct_get: (s, k) => s[k], variable_struct_set: (s, k, v) => { s[k] = v; },
        floor: Math.floor, max: Math.max, min: Math.min, abs: Math.abs, real: Number,
        clamp: (v, lo, hi) => Math.min(hi, Math.max(lo, v)),
        string_upper: v => String(v).toUpperCase(), string_length: v => String(v).length,
        string: (v, ...args) => args.length ? String(v).replace(/\{(\d+)\}/g, (_, n) => String(args[n])) : String(v),
        struct_get_fallback: (s, k, fallback) => s[k] ?? fallback,
        LoadSongDataNoteCount: () => 10,
        acs_set_state: () => {}, SendEvent: () => {},
    });
    ctx.variable_global_exists = k => Object.hasOwn(ctx.global, k);
    ctx.variable_global_get = k => ctx.global[k];
    ctx.variable_global_set = (k, v) => { ctx.global[k] = v; };
    ctx.GetSongStats = () => {
        nativeGlobals.forEach((k, i) => { ctx.global[k] = i + 1; });
    };
    for (const name of ["acs_safe_number", "acs_global_number", "acs_refresh_tech_stats", "acs_stat",
        "acs_song_value", "acs_is_shatter_song", "acs_song_difficulty_name", "acs_difficulty_name",
        "acs_difficulty_index", "acs_formatted_song_value", "acs_chart_snapshot", "EmitChartInfo",
        "EmitLobbySelection", "EmitLoadingStarted", "EmitStarted"]) {
        const start = source.indexOf(`${name} = function(`);
        assert.notEqual(start, -1, `Missing GML function ${name}`);
        const end = source.indexOf("\n};", start) + 3;
        vm.runInContext(source.slice(start, end), ctx);
    }
    ctx.acs_export_jacket = () => "";
    return ctx;
}

const song = { chart_id: "stats-regression", name: "Stats Regression", audio_id: 1 };
test("normal selectors do not require the unused ss_notecount global", () => {
    const ctx = context();
    stats.forEach((k, i) => { ctx.global[k] = 100 + i; });
    const before = { ...ctx.global };
    ctx.acs_refresh_tech_stats(song, "FINALE");
    assert.deepEqual(stats.map(k => ctx.acs_stat(k)), [1, 2, 3, 4, 5, 6]);
    stats.forEach(k => assert.equal(ctx.global[k], before[k]));
    assert.equal(Object.hasOwn(ctx.global, "ss_notecount"), false);
});

test("first native calculation initializes stats without preexisting globals", () => {
    const ctx = context();
    ctx.acs_refresh_tech_stats(song, "OPENING");
    assert.deepEqual(stats.map(k => ctx.acs_stat(k)), [1, 2, 3, 4, 5, 6]);
});

test("all existing native calculation globals are restored after success or failure", () => {
    for (const fail of [false, true]) {
        const ctx = context();
        nativeGlobals.forEach((k, i) => { ctx.global[k] = 100 + i; });
        ctx.global.ss_notecount = 999;
        const before = { ...ctx.global };
        const native = ctx.GetSongStats;
        ctx.GetSongStats = () => { native(); if (fail) throw new Error("chart unavailable"); };
        ctx.acs_refresh_tech_stats(song, "FINALE");
        assert.deepEqual(ctx.global, before);
        assert.deepEqual(stats.map(k => ctx.acs_stat(k)), fail ? [0, 0, 0, 0, 0, 0] : [1, 2, 3, 4, 5, 6]);
    }
});

test("single-player, lobby, loading and gameplay snapshots carry calculated stats", () => {
    for (const emit of ["EmitChartInfo", "EmitLobbySelection", "EmitLoadingStarted", "EmitStarted"]) {
        const ctx = context();
        ctx.global.currentSongInfo = song;
        ctx.global.df_load = "FINALE";
        const events = [];
        ctx.SendEvent = (kind, chart) => events.push({ kind, chart });
        ctx[emit](song, 2);
        assert.equal(events.length, 1, emit);
        assert.deepEqual(Object.values(events[0].chart.techStats), [1, 2, 3, 4, 5, 6], emit);
    }
});

test("missing charts cannot publish the previous chart's stats", () => {
    const ctx = context();
    nativeGlobals.forEach(k => { ctx.global[k] = 99; });
    ctx.GetSongStats = () => { stats.forEach(k => { ctx.global[k] = 0; }); };
    ctx.acs_refresh_tech_stats(song, "MIDDLE");
    assert.deepEqual(stats.map(k => ctx.acs_stat(k)), [0, 0, 0, 0, 0, 0]);
    assert.equal(ctx.global.note_stat, 99);
});

test("BACKSTAGE calculates against ENCORE while keeping its published label", () => {
    const ctx = context();
    const native = ctx.GetSongStats;
    ctx.GetSongStats = (_, difficulty) => { assert.equal(difficulty, "ENCORE"); native(); };
    ctx.acs_refresh_tech_stats(song, "BACKSTAGE");
    assert.equal(ctx.acs_chart_snapshot(song, "BACKSTAGE", 3).rawDifficultyName, "BACKSTAGE");
    assert.equal(ctx.acs_stat("tech_stat"), 2);
});

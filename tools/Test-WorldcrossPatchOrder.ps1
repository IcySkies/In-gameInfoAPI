[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ours = Get-Content -LiteralPath (Join-Path $sourceRoot "codepatches.json") -Raw | ConvertFrom-Json
$onlinePath = Join-Path $sourceRoot "..\SourceFiles\VividStasisModLoader\mods\VSOnlineMod v1.3.2\codepatches.json"
$online = Get-Content -LiteralPath $onlinePath -Raw | ConvertFrom-Json

$packetEntry = "gml_GlobalScript_AddSongPacket"
if (@($ours | Where-Object Entry -eq $packetEntry).Count -ne 0) {
    throw "The API must not patch ${packetEntry}: VS Online extends its wire packet using exact code anchors."
}

$anchors = @(
    "o_st_handle.songQueue = [arg0];",
    "buffer_write(buffer, buffer_s8, arg0.difficulty);`n        return buffer;",
    "obj.difficulty = buffer_read(arg0, buffer_s8);`n        buffer_delete(arg0);"
)
foreach ($anchor in $anchors) {
    if (-not @($online | Where-Object { $_.Entry -eq $packetEntry -and $_.Find -eq $anchor }).Count) {
        throw "VS Online's $packetEntry anchor changed: $anchor"
    }
}

# Representative vanilla serializer/reader anchors, including constructor and apply.
$fixture = @'
function AddSongPacket(arg0) : BasePacket(arg0, true, 3) constructor
{
    write = function()
    {
        buffer_write(buffer, buffer_s8, arg0.difficulty);
        return buffer;
    };
    read = function()
    {
        obj.difficulty = buffer_read(arg0, buffer_s8);
        buffer_delete(arg0);
    };
    apply = function()
    {
        o_st_handle.songQueue = [arg0];
    };
}
'@
$fixture = $fixture.Replace("`r`n", "`n")
function Apply-PacketPatches([string]$code, $patches) {
    foreach ($patch in @($patches | Where-Object Entry -eq $packetEntry)) {
        if ($patch.Type -ne 0 -or $patch.ExternalFile) {
            throw "Unsupported packet patch in regression fixture."
        }
        $code = $code.Replace([string]$patch.Find, [string]$patch.Value)
    }
    return $code
}
$baseline = Apply-PacketPatches $fixture $online
$apiFirst = Apply-PacketPatches (Apply-PacketPatches $fixture $ours) $online
$onlineFirst = Apply-PacketPatches (Apply-PacketPatches $fixture $online) $ours
if ($apiFirst -cne $baseline -or $onlineFirst -cne $baseline) {
    throw "API patch order changed VS Online's packet serializer, reader or apply behavior."
}
foreach ($required in @(
    "buffer_write(buffer, buffer_string, vs_online_queue_chart_id(arg0));",
    "vs_lobby_queue_read_chart_ext(obj, arg0);",
    "BasePacket(arg0, true, 3, buffer_grow)"
)) {
    if (-not $baseline.Contains($required)) { throw "VS Online extension did not apply: $required" }
}

$lobbyStep = "gml_Object_obj_multiplayer_lobby_Step_0"
if (@($ours | Where-Object Entry -eq $lobbyStep).Count -ne 0) {
    throw "The API must observe the settled queue from its own Step, not patch VS Online's lobby Step."
}

Write-Output "Worldcross patch order verified in both orders: VS Online chart-ID serializer/reader and growable buffer match its standalone baseline."

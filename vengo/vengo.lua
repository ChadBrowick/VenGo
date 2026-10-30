--[[
  VenGo - the CatsEyeXI ventures board, live, with one-click warps to the VNM.
  A VanaCore addon (the client the CatsEyeXI launcher starts), styled after YunaUI.

  Install: unzip so you have VanaCore\addons\vanacore\vengo\vengo.lua
  Load:    /addon load vengo vanacore   (add that line to your startup script)
  Window:  /vengo opens or closes it

  GO warps you toward a venture's VNM with the Uberwarp plugin: stand at a
  Home Point, Survival Guide or Unity NPC and press GO, and it uses the warp
  of that kind that lands closest to the VNM. Pressed anywhere else, GO waits
  and warps the moment you walk up to one. VenGo never moves your character.

  Typed commands (optional):
    /vengo <shorthand|nm|zone>   warp toward it (e.g. /vengo b4, /vengo ooze)
    /vengo current | next | cancel | ventures | mode ace|cw | update | reload
    /vengo testalert | where

  VenGo is free software under the GNU GPL v3 (see LICENSE). native.lua and the
  look of the window come from YunaUI by Yunas (GPL v3). The font is TeX Gyre
  Adventor by GUST (GUST Font License). The venture board layout and VNM list
  come from the ventures addon (Commandobill, Seekey, Phatty). Warps go through
  Uberwarp by Thorny, which is installed separately. VanaCore is Vekkien's project.
]]

addon.name    = 'vengo';
addon.author  = 'Chadbrowick';
addon.version = '4.26';
addon.desc    = 'One-click runs to Venture Seals, with the ventures list, in YunaUI style.';
addon.link    = '';

-- VenGo is a VanaCore addon: VanaCore\addons\vanacore\vengo. Its code uses Ashita's addon API names; native.lua sets
-- them up from VanaCore's own Ashita layer (the same start-up YunaUI uses).
if rawget(_G, 'vana') == nil then
    print('VenGo is a VanaCore addon: put it in VanaCore\\addons\\vanacore\\vengo, then /addon load vengo vanacore');
    return;
end
if rawget(_G, 'AshitaCore') == nil then
    local src = (debug.getinfo(1, 'S').source or ''):gsub('^@', '');
    local dir = src:match('^(.*)[\\/][^\\/]+$') or (vana.paths.addons .. '\\vanacore\\vengo');
    assert(loadfile(dir .. '\\native.lua'))(dir);
end

if addon.path == nil then                                    -- (native.lua sets it; this is just in case)
    local src = (debug.getinfo(1, 'S').source or ''):gsub('^@', '');
    addon.path = (src:match('^(.*[\\/])') or '');
end

require('common');
local chat  = require('chat');
local bit   = require('bit');
local imgui = require('imgui');

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
local MAX_ENTITY_IDX = 2303;

local config = {
    transparent = false,       -- see-through window
    minimized = false,         -- shrunk to the little VenGo tag
    alerts = true,             -- watch chat for VNM announcements
    alert_sound = true,        -- play a sound with the alert
    alert90 = true,            -- a chat heads-up when a venture reaches 90%
    mode = 'ACE',              -- ACE or CW venture zones
    pool = 'all',              -- all | A | B
    sort = 'pct',              -- pct (100% on top) | tier
    website = true,            -- update from catseyexi.com/events after each reset
    login_refresh = true,      -- type !ventures once when you log in
    logo_anim = true,          -- shine and petals on the logo
    trail = true,              -- the glowing path on the ground to the VNM
    trail_glow = true,         -- its glow
    trail_color = 'pink',      -- the chevrons' colour
    trail_style = 'solid',     -- lines | bands | solid
    theme = 'pink',            -- the window's accent colours (Settings > Colours)
    lite = false,              -- Lightweight mode: a quick preset for the sliders below
    seal_check = 0.25,         -- seconds between looks at the Venture Seal's own slot
    seal_scan = 0.5,           -- seconds between searches of the whole list for it
    cam_every = 1,             -- read the camera every N frames (the last one is kept in between)
    trail_range = 90,          -- yalms of arrows ahead of you
    trail_scale = 1.0,         -- arrow size
    trail_spacing = 1.0,       -- space between arrows
    trail_speed = 5,           -- how fast they crawl (yalms a second)
    glow_q = 2,                -- glow passes (1 lighter, 2 fuller)
    bg = 'violet',             -- the window's background
    trail_size = 'medium',     -- small | medium | large
};

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local ventures = {};   -- everything you can Go to (EXP ventures + HVNM)
local vdata = {};      -- what's shown: the live board when there is one, else ventures.lua
local vfile = {};      -- ventures.lua as written

local state = { swap = false };

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local ui = { open = { true }, last = 'Pick a venture and press GO.', tab = 1 };

local function msg(text)
    ui.last = text;
    print(chat.header(addon.name):append(chat.message(text)));
end

local function mm() return AshitaCore:GetMemoryManager(); end

local function zone()
    return mm():GetParty():GetMemberZone(0);
end

local function myIndex()
    return mm():GetParty():GetMemberTargetIndex(0);
end

local function norm(s)
    local r = (s or ''):lower():gsub('[^%w]', '');
    return r;
end

local function dist2d(ax, ay, bx, by)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2);
end

-- Horizontal x, horizontal y, height for an entity index (nil if not valid)
local function entPos(idx)
    if idx == nil or idx == 0 then return nil; end
    local e = mm():GetEntity();
    local x, y, z = e:GetLocalPositionX(idx), e:GetLocalPositionY(idx), e:GetLocalPositionZ(idx);
    if x == nil or (x == 0 and y == 0 and z == 0) then return nil; end
    if state.swap then return x, z, y; end
    return x, y, z;
end

local function pos()
    return entPos(myIndex());
end

local function command(text)
    AshitaCore:GetChatManager():QueueCommand(1, text);
end

------------------------------------------------------------------------
-- VenGo's own settings (vengo_settings.lua next to vengo.lua)
------------------------------------------------------------------------
local function settingsFile() return addon.path .. 'vengo_settings.lua'; end

local function loadSettings()
    local chunk = loadfile(settingsFile());
    if chunk == nil then return; end
    local ok, t = pcall(chunk);
    if not ok or type(t) ~= 'table' then return; end
    for k, v in pairs(t) do if config[k] ~= nil then config[k] = v; end end
end

local function saveSettings()
    local f = io.open(settingsFile(), 'w');
    if f == nil then return; end
    f:write('-- VenGo settings (changed from the window)\nreturn {\n');
    for _, k in ipairs({ 'transparent', 'minimized', 'alerts', 'alert_sound', 'alert90', 'mode', 'pool', 'sort', 'website', 'login_refresh', 'logo_anim', 'trail', 'trail_glow', 'trail_color', 'trail_style', 'trail_size', 'theme', 'bg', 'lite',
                           'seal_check', 'seal_scan', 'cam_every', 'trail_range', 'trail_scale', 'trail_spacing', 'trail_speed', 'glow_q' }) do
        local v = config[k];
        f:write(('    %s = %s,\n'):format(k, type(v) == 'string' and ('%q'):format(v) or tostring(v)));
    end
    f:write('};\n');
    f:close();
end

------------------------------------------------------------------------
-- Ventures data
------------------------------------------------------------------------
local function loadVentures()
    local chunk = loadfile(addon.path .. 'ventures.lua');
    if chunk == nil then msg('ventures.lua not found next to vengo.lua.'); ventures = {}; return; end
    local ok, data = pcall(chunk);
    if not ok or type(data) ~= 'table' then msg('ventures.lua has an error.'); ventures = {}; return; end
    -- Old format was a plain list of EXP ventures
    if data[1] ~= nil then data = { exp = data }; end
    vfile = data;
    vdata = {};
    for k, v in pairs(data) do vdata[k] = v; end
    ventures = {};
    for _, v in ipairs(data.exp or {}) do ventures[#ventures + 1] = v; end
    if data.hvnm then ventures[#ventures + 1] = data.hvnm; end
end

local function entryKeys(e)
    local keys = { e.key, e.nm, e.zone_name };
    for w in e.nm:gmatch('[%a\']+') do keys[#keys + 1] = w; end
    for _, a in ipairs(e.aliases or {}) do keys[#keys + 1] = a; end
    return keys;
end

local function resolve(query)
    local q = norm(query);
    if q == '' then return {}; end
    local hits = {};
    for _, e in ipairs(ventures) do
        for _, k in ipairs(entryKeys(e)) do
            if norm(k) == q then hits[#hits + 1] = e; break; end
        end
    end
    if #hits == 0 then
        for _, e in ipairs(ventures) do
            if norm(e.nm):find(q, 1, true) or norm(e.zone_name):find(q, 1, true) then
                hits[#hits + 1] = e;
            end
        end
    end
    return hits;
end

local function describe(e)
    return ('%s [%s] - %s (%s), %d%%'):fmt(e.nm, e.key, e.zone_name, e.grid, e.progress or 0);
end

local function venturesInZone(z)
    local list = {};
    for _, v in ipairs(ventures) do if v.zone == z then list[#list + 1] = v; end end
    return list;
end

local gridToWorld, worldToGrid;
do
------------------------------------------------------------------------
-- The game's map table: turns a map grid square (e.g. "I-7") into a spot
-- in the world. Same table YunaUI's minimap reads (zone, floor, scale, offsets).
-- Map pictures are 512 px; the grid is 15 x 15 squares of 32 px after a 16 px edge.
------------------------------------------------------------------------
local GRID_EDGE = 16;   -- px before square A / row 1
local GRID_SIZE = 32;   -- px per square

local MAPS = { tp = nil };

local function mapTable()
    if MAPS.tp == nil then
        MAPS.tp = 0;
        pcall(function ()
            local at = ashita.memory.find('FFXiMain.dll', 0, '8A0D????????5333C05684C95774??8A5424188B7424148B7C2410B9', 0, 0);
            if at ~= 0 then MAPS.tp = ashita.memory.read_uint32(at + 0x1C); end
        end);
    end
    return MAPS.tp;
end

-- Every map of a zone: { floor, scale, ox, oy }
local function mapEntries(zid)
    local out = {};
    local tp = mapTable();
    if tp == 0 then return out; end
    pcall(function ()
        for i = 0, 1999 do
            local b = tp + i * 0x0E;
            local z = ashita.memory.read_uint16(b);
            local dat = ashita.memory.read_uint16(b + 8);
            if z == 0 and dat == 0 and i > 10 then break; end
            if z == zid then
                local s = ashita.memory.read_uint8(b + 5);
                out[#out + 1] = { floor = ashita.memory.read_uint8(b + 2), scale = (s >= 0x80) and (s - 0x100) or s,
                                  ox = ashita.memory.read_int16(b + 0x0A), oy = ashita.memory.read_int16(b + 0x0C) };
            end
        end
    end);
    return out;
end

-- "I-7" -> column 8, row 6 (0-based); "G-10" works too
local function parseGrid(g)
    local l, n = tostring(g or ''):upper():match('^%s*(%a)%s*%-?%s*(%d+)');
    if not l then return nil; end
    return l:byte() - 65, tonumber(n) - 1;
end

local function mapK(e) return math.abs(e.scale) / 2560 * 512; end

-- Map pixels <-> world (x east, y north), as the game's map draws it
local function mapToWorld(e, mx, my)
    local k = mapK(e);
    if k == 0 then return nil; end
    return (mx + e.ox) / k, -(my + e.oy) / k;
end
local function worldToMap(e, wx, wy)
    local k = mapK(e);
    return wx * k - e.ox, -wy * k - e.oy;
end

-- The world spot at the middle of a grid square, on the zone's first map (or map number mapNo, 1-based)
gridToWorld = function(zid, grid, mapNo)
    local col, row = parseGrid(grid);
    if col == nil then return nil; end
    local maps = mapEntries(zid);
    local e = maps[mapNo or 1] or maps[1];
    if e == nil then return nil; end
    local mx = GRID_EDGE + col * GRID_SIZE + GRID_SIZE / 2;
    local my = GRID_EDGE + row * GRID_SIZE + GRID_SIZE / 2;
    return mapToWorld(e, mx, my);
end

-- Which grid square a world spot is in (for checking the math in game)
worldToGrid = function(zid, wx, wy)
    local e = mapEntries(zid)[1];
    if e == nil then return nil; end
    local mx, my = worldToMap(e, wx, wy);
    local col = math.floor((mx - GRID_EDGE) / GRID_SIZE);
    local row = math.floor((my - GRID_EDGE) / GRID_SIZE);
    if col < 0 or col > 25 or row < 0 then return '?'; end
    return ('%s-%d'):fmt(string.char(65 + col), row + 1);
end

end

local popWords, checkSealText, fmtLeft, savePops, loadPops, popLeft, dropsOf, raiseAlert, checkAnnouncement, tickAlert, liveFile, u16, u8, zoneKey, zoneNameOf, loadTable, loadVnmDb, splitList, fillFromDb, fileEntry, POP_DELAY, ALERT, LAST_ANNOUNCE, POPS, TIER_LEVELS, LIVE, LIVEV, VNMDB, VNMDB_FROM;
do
------------------------------------------------------------------------
-- VNM alerts: Populox announces a spawning VNM in Unity chat, and it pops
-- 10 minutes later. VenGo watches chat for that, alerts you, marks the
-- venture 100% and points GO at it.
------------------------------------------------------------------------
POP_DELAY = 600;                 -- seconds from the announcement to the pop
ALERT = nil;                     -- { v, at, pop_at, line, warned }
LAST_ANNOUNCE = nil;             -- the last Populox line seen (shown in Settings)

local function cleanChat(t)
    t = tostring(t or '');
    t = t:gsub('[\30\31\127].', '');            -- the game's colour / style codes
    t = t:gsub('\239[\39\40]', '');              -- auto-translate brackets
    t = t:gsub('[%z\1-\8\11-\31]', '');
    return t;
end

-- spaces kept, everything else that isn't a letter or digit dropped, lower case
local function loose(t)
    local r = (' ' .. tostring(t or ''):lower():gsub('[^%w]+', ' ') .. ' ');
    return r;
end

local function playAlertSound()
    if not config.alert_sound then return; end
    local win = (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Media\\';
    local file = nil;
    for _, n in ipairs({ addon.path .. 'alert.wav', win .. 'Windows Notify System Generic.wav', win .. 'notify.wav',
                         win .. 'chimes.wav', win .. 'Windows Ding.wav' }) do
        local f = io.open(n, 'rb');
        if f then f:close(); file = n; break; end
    end
    if file == nil then return; end
    local ok = pcall(function () ashita.misc.play_sound(file); end);
    if ok then return; end
    pcall(function ()
        local ffi = require('ffi');
        pcall(ffi.cdef, 'int __stdcall PlaySoundA(const char* pszSound, void* hmod, uint32_t fdwSound);');
        ffi.load('winmm').PlaySoundA(file, nil, 0x00020001);   -- SND_FILENAME | SND_ASYNC
    end);
end

-- Which venture a chat line is about: an NM name first, then a zone name
local function ventureInLine(line)
    local L = loose(line);
    for _, v in ipairs(ventures) do
        if L:find(loose(v.nm), 1, true) then return v; end
    end
    local hits = {};
    for _, v in ipairs(ventures) do
        local zn = loose((v.zone_name or ''):gsub('%[S%]', ''));
        if #zn > 3 and L:find(zn, 1, true) then hits[#hits + 1] = v; end
    end
    table.sort(hits, function (a, b) return (a.progress or 0) > (b.progress or 0); end);
    return hits[1];
end

fmtLeft = function(sec)
    if sec <= 0 then return 'up now'; end
    return ('%d:%02d'):fmt(math.floor(sec / 60), sec % 60);
end

-- "Pops in 4:32", or "Spawning in now" once the time is up
popWords = function(left)
    if left == nil then return 'Pop time unknown'; end
    if left <= 0 then return 'Spawning in now'; end
    return 'Pops in ' .. fmtLeft(left);
end

------------------------------------------------------------------------
-- Pop timers, one per venture at 100%. Set from the board reaching 100%,
-- Populox's callout, or (most exact) what the Venture Seal says when you
-- talk to it. Kept in pops.lua so a reload doesn't lose them.
------------------------------------------------------------------------
POPS = {};              -- key -> { at = os.time() of the pop, zone, src = 'board'|'chat'|'seal' }

local function popsFile() return addon.path .. 'pops.lua'; end

savePops = function()
    local f = io.open(popsFile(), 'w');
    if f == nil then return; end
    f:write('-- VNM pop timers (rewritten by VenGo)\nreturn {\n');
    for k, p in pairs(POPS) do
        f:write(('  [%q] = { at=%d, zone=%d, src=%q },\n'):format(k, p.at, p.zone or 0, p.src or ''));
    end
    f:write('}\n');
    f:close();
end

loadPops = function()
    local chunk = loadfile(popsFile());
    if chunk == nil then return; end
    local ok, t = pcall(chunk);
    if not ok or type(t) ~= 'table' then return; end
    local now = os.time();
    for k, p in pairs(t) do
        if type(p) == 'table' and tonumber(p.at) and p.at > now - 1800 then POPS[k] = p; end
    end
end

-- Seconds to the pop (negative once it's up), or nil if no timer
popLeft = function(v)
    local p = v and v.key and POPS[v.key];
    if p == nil or (p.zone and p.zone ~= 0 and p.zone ~= v.zone) then return nil; end
    return p.at - os.time();
end

local function setPop(v, at, src)
    if v == nil or v.key == nil then return; end
    POPS[v.key] = { at = at, zone = v.zone, src = src };
    if ALERT and ALERT.v == v then ALERT.pop_at = at; ALERT.warned = (at - os.time()) <= 60; end
    savePops();
end

-- What a VNM drops, as text ('' if unknown)
dropsOf = function(v)
    if v == nil then return ''; end
    if v.drops and v.drops ~= '' then return v.drops; end
    if type(v.loot) == 'table' and #v.loot > 0 then return table.concat(v.loot, ', '); end
    return '';
end

raiseAlert = function(v, line, source)
    local now = os.time();
    v.progress = 100;
    local left = popLeft(v);
    local popAt = (left and left > -600) and (now + left) or (now + POP_DELAY);   -- (a seal time already known wins)
    ALERT = { v = v, at = now, pop_at = popAt, line = line, warned = false, source = source or 'chat' };
    if left == nil or left <= -600 then setPop(v, popAt, source or 'chat'); end
    local d = dropsOf(v);
    msg(('VNM ALERT: %s in %s (%s) pops in about %s.%s Press GO in VenGo.'):fmt(v.nm, v.zone_name, v.grid or '?',
        fmtLeft(popAt - now), (d ~= '') and (' Drops: ' .. d .. '.') or ''));
    playAlertSound();
end

local function logAnnouncement(line)
    pcall(function ()
        local f = io.open(addon.path .. 'announcements.txt', 'a');
        if f then f:write(os.date('%Y-%m-%d %H:%M:%S') .. '  ' .. line .. '\n'); f:close(); end
    end);
end

-- Called for every incoming chat line
checkAnnouncement = function(mode, raw)
    if not config.alerts then return; end
    local line = cleanChat(raw);
    local low = line:lower();
    local fromPopulox = low:find('populox', 1, true) ~= nil;
    local unity = (mode == 211 or mode == 212);
    if not fromPopulox and not unity then return; end
    local v = ventureInLine(line);
    if fromPopulox then
        LAST_ANNOUNCE = line;
        logAnnouncement(line);
    end
    if v == nil then return; end
    -- a Unity line that names a venture but isn't Populox: only if it sounds like a spawn
    if not fromPopulox and not (low:find('spawn', 1, true) or low:find('appear', 1, true) or low:find('venture', 1, true)) then
        return;
    end
    if ALERT and ALERT.v == v and os.time() - ALERT.at < 900 then
        -- already alerted (the board hit 100%): Populox's callout sets the exact 10 minutes
        if ALERT.source ~= 'chat' and not ALERT.confirmed then
            ALERT.confirmed = true;
            if not (POPS[v.key] and POPS[v.key].src == 'seal') then
                setPop(v, os.time() + POP_DELAY, 'chat');
            end
        end
        return;
    end
    raiseAlert(v, line, 'chat');
end

-- One minute before the pop: a second sound. 15 minutes after: the alert goes away.
tickAlert = function()
    if ALERT == nil then return; end
    local av = ALERT.v;
    if (av.progress or 0) < 100 and (av.prog_at or 0) > ALERT.at then
        msg(('%s is no longer at 100%% (killed or reset). Alert closed.'):fmt(av.nm or 'The VNM'));
        ALERT = nil;
        return;
    end
    local pl = popLeft(ALERT.v);
    if pl then ALERT.pop_at = os.time() + pl; end
    local left = ALERT.pop_at - os.time();
    if left <= 60 and not ALERT.warned then
        ALERT.warned = true;
        msg(('%s pops in about a minute (%s).'):fmt(ALERT.v.nm, ALERT.v.zone_name));
        playAlertSound();
    end
    if left < -900 then ALERT = nil; end
end

do
------------------------------------------------------------------------
-- Talking to a Venture Seal: whatever time it gives ("in 6 minutes",
-- "4:30", "45 seconds") resets that venture's pop timer when it's off.
-- Every seal line is saved to seal_lines.txt so the wording can be matched exactly.
------------------------------------------------------------------------
local SEAL_TALK = { idx = nil, at = 0 };

local function targetName()
    local n = nil;
    pcall(function ()
        local t = AshitaCore:GetMemoryManager():GetTarget();
        local idx = t:GetTargetIndex(t:GetIsSubTargetActive() == 1 and 1 or 0);
        if idx and idx > 0 then n = AshitaCore:GetMemoryManager():GetEntity():GetName(idx); end
    end);
    return n;
end

-- "6 minutes", "6 min", "45 seconds", "4:30", "1 minute and 20 seconds"
local function secondsIn(line)
    local low = line:lower();
    local m, sec = low:match('(%d+):(%d%d)');
    if m then return tonumber(m) * 60 + tonumber(sec); end
    local mins = tonumber(low:match('(%d+)%s*min'));
    local secs = tonumber(low:match('(%d+)%s*sec'));
    if mins or secs then return (mins or 0) * 60 + (secs or 0); end
    if low:find('appeared', 1, true) or low:find('is here', 1, true) or low:find('has spawned', 1, true) then return 0; end
    return nil;
end

-- The venture this seal belongs to: the one in your zone at 100%, else the highest
local function ventureHere()
    local z, best = zone(), nil;
    for _, v in ipairs(ventures) do
        if v.zone == z and (best == nil or (v.progress or 0) > (best.progress or 0)) then best = v; end
    end
    return best;
end

checkSealText = function(mode, raw)
    local now = os.clock();
    local tn = targetName();
    if tn and tn:lower():find('venture seal', 1, true) then SEAL_TALK.at = now; end
    if now - SEAL_TALK.at > 15 then return; end                      -- (only while you're at the seal)
    local line = cleanChat(raw);
    if line == '' then return; end
    pcall(function ()
        local f = io.open(addon.path .. 'seal_lines.txt', 'a');
        if f then f:write(os.date('%Y-%m-%d %H:%M:%S') .. '  [' .. tostring(mode) .. ']  ' .. line .. '\n'); f:close(); end
    end);
    local secs = secondsIn(line);
    if secs == nil or secs > 3600 then return; end
    local v = ventureHere();
    if v == nil then return; end
    local at = os.time() + secs;
    local old = popLeft(v);
    if old ~= nil and math.abs((os.time() + old) - at) <= 20 then return; end   -- (already right)
    setPop(v, at, 'seal');
    if secs > 0 then
        msg(('Venture Seal: %s pops in %s. Timer %s.'):fmt(v.nm or '?', fmtLeft(secs), old and 'corrected' or 'set'));
    else
        msg(('Venture Seal: %s is up.'):fmt(v.nm or '?'));
    end
end

end

------------------------------------------------------------------------
-- Live ventures: the server sends the whole venture board in packet 0x1A3
-- (two pools x six tiers, each with an ACE zone, a CW zone and the progress,
-- plus the HVNM's zone and progress). VenGo reads it the moment it arrives,
-- so the list and the percentages stay current with no editing.
-- Packet layout as documented by the "ventures" addon (Commandobill).
------------------------------------------------------------------------
TIER_LEVELS = { '10-19', '20-29', '30-39', '40-49', '50-59', '60-69' };
LIVE = nil;             -- { at = os.time(), exp = { {pool, tier, ace, cw, progress}, ... }, hvnm = { zone, progress } }
LIVEV = {};             -- key -> the venture table shown (kept, so GO and alerts keep pointing at it)
VNMDB = nil;            -- drops, positions and notes per zone: { [zone name] = { {name, level_range, position, ...} } }
VNMDB_FROM = 'none';

liveFile = function() return addon.path .. 'live_ventures.lua'; end

u16 = function(d, off) return (d:byte(off + 1) or 0) + (d:byte(off + 2) or 0) * 256; end
u8 = function(d, off) return d:byte(off + 1) or 0; end

-- "Crawlers' Nest", "Crawlers Nest", "East Ronfaure [S]", "East Ronfaure S" all match
zoneKey = function(name)
    local r = tostring(name or ''):lower():gsub('%[s%]', 's'):gsub('[^%w]', '');
    return r;
end

zoneNameOf = function(zid)
    local n = nil;
    pcall(function () n = AshitaCore:GetResourceManager():GetString('zones.names', zid); end);
    if n and n ~= '' then return n; end
    for _, v in ipairs(vdata.exp or {}) do if v.zone == zid then return v.zone_name; end end
    if vdata.hvnm and vdata.hvnm.zone == zid then return vdata.hvnm.zone_name; end
    return ('Zone %d'):fmt(zid);
end

------------------------------------------------------------------------
-- VNM details (name, grid, drops, notes): the ventures addon's community data.
-- Looked for in VenGo's folder, then the ventures addon's own folder, then
-- downloaded from its public page.
------------------------------------------------------------------------
local VNMDB_URL = 'http://raw.githubusercontent.com/commandobill/ventures/main/data/vnms.lua';

loadTable = function(path)
    local chunk = loadfile(path);
    if chunk == nil then return nil; end
    local ok, t = pcall(chunk);
    if ok and type(t) == 'table' then return t; end
    return nil;
end

local function indexDb(raw)
    local db = {};
    for zname, list in pairs(raw) do
        if type(list) == 'table' then db[zoneKey(zname)] = list; end
    end
    return db;
end

local function downloadDb()
    local ok, err = pcall(function ()
        local http = require('socket.http');
        local okl, ltn12 = pcall(require, 'ltn12');
        if not okl then ltn12 = require('socket.ltn12'); end
        local old = http.TIMEOUT;
        http.TIMEOUT = 6;
        local chunks = {};
        local r, code = http.request({ url = VNMDB_URL, sink = ltn12.sink.table(chunks) });
        http.TIMEOUT = old;
        if not r or tonumber(code) ~= 200 then error('status ' .. tostring(code)); end
        local body = table.concat(chunks);
        local fn = loadstring(body);
        if fn == nil then error('bad file'); end
        local okt, t = pcall(fn);
        if not okt or type(t) ~= 'table' then error('bad file'); end
        local f = io.open(addon.path .. 'vnms_cache.lua', 'wb');
        if f then f:write(body); f:close(); end
    end);
    return ok, err;
end

loadVnmDb = function(tryDownload)
    if tryDownload then downloadDb(); end
    local paths = { { addon.path .. 'vnms.lua', 'vnms.lua in the vengo folder' },
                    { addon.path .. 'vnms_cache.lua', 'downloaded' } };
    pcall(function ()
        local root = (addon.path:gsub('[\\/]+$', '')):match('^(.*)[\\/][^\\/]+[\\/][^\\/]+$');   -- ...\addons
        if root then
            for _, sub in ipairs({ '\\ashita\\ventures\\data\\', '\\vanacore\\ventures\\data\\', '\\ventures\\data\\' }) do
                paths[#paths + 1] = { root .. sub .. 'vnms_remote.lua', 'the ventures addon' };
                paths[#paths + 1] = { root .. sub .. 'vnms.lua', 'the ventures addon' };
            end
        end
    end);
    for _, p in ipairs(paths) do
        local t = loadTable(p[1]);
        if t then VNMDB, VNMDB_FROM = indexDb(t), p[2]; return true; end
    end
    VNMDB, VNMDB_FROM = nil, 'none';
    return false;
end

local function vnmInfo(zoneName, levels)
    if VNMDB == nil then return nil; end
    local list = VNMDB[zoneKey(zoneName)];
    if list == nil then return nil; end
    for _, e in ipairs(list) do if e.level_range == levels then return e; end end
    return nil;
end

splitList = function(s)
    local out = {};
    for part in tostring(s or ''):gmatch('[^,]+') do
        local t = part:gsub('^%s+', ''):gsub('%s+$', '');
        if t ~= '' then out[#out + 1] = t; end
    end
    return out;
end

------------------------------------------------------------------------
-- Building the list from the live board
------------------------------------------------------------------------
fillFromDb = function(v, levels)
    local info = vnmInfo(v.zone_name, levels);
    v.nm = (info and info.name and info.name ~= '') and info.name or (v.nm_file or '?');
    v.grid = (info and info.position and info.position ~= '') and info.position or v.grid_file;
    v.notes = info and info.notes or '';
    v.drops = info and info.equipment or '';
    v.element = info and info.element or '';
    v.crest = info and info.crest or '';
    local mapNo = tostring(v.notes or ''):match('[Mm]ap%s*(%d+)');
    v.map = mapNo and tonumber(mapNo) or v.map_file;
end

fileEntry = function(key)
    if key == 'hvnm' then return vfile.hvnm; end
    for _, v in ipairs(vfile.exp or {}) do if v.key == key then return v; end end
    return nil;
end

end

local saveTrends, loadTrends, recordTrend, trendOf, trendText;
do
------------------------------------------------------------------------
-- How fast each venture is climbing: every change seen on the board is kept
-- (with its time) for 3 hours, in trend.lua, so it survives reloads.
--   fast    : climbing at least TREND_FAST % an hour
--   slow    : climbing, but slower than that
--   stalled : no change for TREND_STALL minutes
--   watching: not enough seen yet
------------------------------------------------------------------------
local TREND_FAST   = 6;       -- % per hour that counts as fast
local TREND_STALL  = 30;      -- minutes without a change that count as stalled
local TREND_WINDOW = 60;      -- minutes looked back over for the speed
local TREND_KEEP   = 180;     -- minutes of history kept

local TRENDS = {};            -- key -> { zone, first, pts = { { t, p }, ... } }

local function trendFile() return addon.path .. 'trend.lua'; end

saveTrends = function()
    local f = io.open(trendFile(), 'w');
    if f == nil then return; end
    f:write('-- How the ventures have been moving (rewritten by VenGo)\nreturn {\n');
    for key, tr in pairs(TRENDS) do
        f:write(('  [%q] = { zone=%d, first=%d, pts={'):format(key, tr.zone or 0, tr.first or 0));
        for _, pt in ipairs(tr.pts) do f:write(('{%d,%s},'):format(pt[1], tostring(pt[2]))); end
        f:write('} },\n');
    end
    f:write('}\n');
    f:close();
end

loadTrends = function()
    local chunk = loadfile(trendFile());
    if chunk == nil then return; end
    local ok, t = pcall(chunk);
    if ok and type(t) == 'table' then TRENDS = t; end
end

-- A board arrived: note this venture's progress
recordTrend = function(key, zid, progress)
    local now = os.time();
    local tr = TRENDS[key];
    if tr == nil or tr.zone ~= zid then
        tr = { zone = zid, first = now, pts = {} };
        TRENDS[key] = tr;
    end
    local last = tr.pts[#tr.pts];
    if last == nil or last[2] ~= progress then
        tr.pts[#tr.pts + 1] = { now, progress };
        if last and progress < last[2] then tr.pts = { { now, progress } }; tr.first = now; end   -- (the VNM was killed: it started again)
    end
    while #tr.pts > 1 and tr.pts[1][1] < now - TREND_KEEP * 60 do table.remove(tr.pts, 1); end
end

-- { kind = 'fast'|'slow'|'stalled'|'watching'|'full', rate (% an hour), since (seconds since the last change) }
trendOf = function(v)
    if (v.progress or 0) >= 100 then return { kind = 'full' }; end
    local tr = v.key and TRENDS[v.key];
    if tr == nil or tr.zone ~= v.zone or #tr.pts == 0 then return { kind = 'watching' }; end
    local now = os.time();
    local last = tr.pts[#tr.pts];
    local since = now - last[1];
    if #tr.pts == 1 then
        -- one value seen: stalled once it has sat there long enough, else still watching
        if now - (tr.first or now) >= TREND_STALL * 60 then return { kind = 'stalled', since = now - tr.first }; end
        return { kind = 'watching' };
    end
    if since >= TREND_STALL * 60 then return { kind = 'stalled', since = since }; end
    -- the speed: from the oldest point inside the window (or the one just before it) to now
    local from = tr.pts[1];
    for i = #tr.pts, 1, -1 do
        from = tr.pts[i];
        if tr.pts[i][1] <= now - TREND_WINDOW * 60 then break; end
    end
    local hours = math.max((now - from[1]) / 3600, 1 / 60);
    local rate = (last[2] - from[2]) / hours;
    return { kind = (rate >= TREND_FAST) and 'fast' or 'slow', rate = rate, since = since };
end

trendText = function(t)
    local function ago(sec)
        sec = math.max(0, sec or 0);
        if sec < 90 then return 'just now'; end
        if sec < 3600 then return ('%d min ago'):fmt(math.floor(sec / 60)); end
        return ('%dh %02dm ago'):fmt(math.floor(sec / 3600), math.floor(sec % 3600 / 60));
    end
    if t.kind == 'full' then return 'At 100%: the VNM is up or about to be'; end
    if t.kind == 'fast' then return ('Rising fast: about +%.1f%% an hour (last change %s)'):fmt(t.rate, ago(t.since)); end
    if t.kind == 'slow' then return ('Rising slowly: about +%.1f%% an hour (last change %s)'):fmt(t.rate, ago(t.since)); end
    if t.kind == 'stalled' then return ('Stalled: no change for %s'):fmt(ago(t.since):gsub(' ago', '')); end
    return 'Watching: not enough seen yet to tell how fast it\'s moving';
end

end

local crossed, applyLive, loadLive, onVenturePacket, pollBoard, loginTick, refreshBoard, liveAge, heads, LOGIN_ASK;
do
heads = {};   -- key -> highest heads-up already given (90 / 100)

crossed = function(v, before)
    local now = v.progress or 0;
    if before == nil then before = heads[v.key] and 100 or 0; end
    if now >= 100 and before < 100 then
        heads[v.key] = 100;
        if not (ALERT and ALERT.v == v and os.time() - ALERT.at < 900) then raiseAlert(v, '(venture board)', 'board'); end
    elseif now >= 90 and before < 90 and now < 100 and config.alert90 then
        msg(('%s (%s) is at %d%%.'):fmt(v.nm, v.zone_name, now));
    end
end

applyLive = function(alerts)
    if LIVE == nil then return; end
    local mode = (config.mode == 'CW') and 'cw' or 'ace';
    local list = {};
    for _, r in ipairs(LIVE.exp or {}) do
        local key = (r.pool == 1 and 'b' or 'a') .. tostring(r.tier);
        local v = LIVEV[key] or { key = key };
        LIVEV[key] = v;
        local before = v.progress;
        local zid = r[mode];
        if v.zone ~= zid then before = nil; end           -- (a new zone in this slot: no "crossed" from the old one)
        local f = fileEntry(key);
        v.pool, v.tier, v.levels = (r.pool == 1) and 'B' or 'A', r.tier, TIER_LEVELS[r.tier];
        v.zone, v.zone_name = zid, zoneNameOf(zid);
        v.nm_file = (f and f.zone == zid) and f.nm or nil;
        v.grid_file = (f and f.zone == zid) and f.grid or nil;
        v.map_file = (f and f.zone == zid) and f.map or nil;
        local keepNm, keepGrid, keepMap = v.site_nm, v.site_grid, v.site_map;
        fillFromDb(v, TIER_LEVELS[r.tier]);
        if v.site_zone == zid then                                    -- (the website's names and spots are the current ones)
            v.nm, v.grid, v.map = keepNm or v.nm, keepGrid or v.grid, keepMap or v.map;
        end
        v.progress = r.progress;
        v.prog_at, v.prog_zone = LIVE.at or os.time(), zid;
        if alerts then recordTrend(key, zid, r.progress); end
        if (r.progress or 0) < 100 and POPS[key] then POPS[key] = nil; savePops(); end
        v.live = true;
        list[#list + 1] = v;
        if alerts then crossed(v, before); end
    end
    if #list > 0 then vdata.exp = list; end

    if LIVE.hvnm and LIVE.hvnm.zone and LIVE.hvnm.zone > 0 then
        local h = LIVEV.hvnm or { key = 'hvnm', aliases = { 'hv' } };
        LIVEV.hvnm = h;
        local before = h.progress;
        if h.zone ~= LIVE.hvnm.zone then before = nil; end
        local f = fileEntry('hvnm');
        h.zone, h.zone_name = LIVE.hvnm.zone, zoneNameOf(LIVE.hvnm.zone);
        h.nm_file = (f and f.zone == h.zone) and f.nm or nil;
        h.grid_file = (f and f.zone == h.zone) and f.grid or nil;
        if h.site_zone == h.zone then
            -- the website already filled in this HVNM: keep its name, spot, level, HP, next one and loot
            local keep = { h.nm, h.grid, h.level, h.hp, h.next_up, h.loot, h.drops };
            fillFromDb(h, 'HVNM');
            h.nm, h.grid, h.level, h.hp, h.next_up, h.loot, h.drops = keep[1], keep[2], keep[3], keep[4], keep[5], keep[6], keep[7];
        else
            fillFromDb(h, 'HVNM');
            local same = f and f.nm == h.nm;
            h.level, h.hp, h.next_up = same and f.level or nil, same and f.hp or nil, same and f.next_up or nil;
            h.loot = splitList(h.drops ~= '' and h.drops or (same and table.concat(f.loot or {}, ',') or ''));
        end
        h.progress = LIVE.hvnm.progress;
        h.prog_at, h.prog_zone = LIVE.at or os.time(), h.zone;
        if alerts then recordTrend('hvnm', h.zone, h.progress); end
        if (h.progress or 0) < 100 and POPS.hvnm then POPS.hvnm = nil; savePops(); end
        h.live = true;
        vdata.hvnm = h;
        if alerts then crossed(h, before); end
    end

    ventures = {};
    for _, v in ipairs(vdata.exp or {}) do ventures[#ventures + 1] = v; end
    if vdata.hvnm then ventures[#ventures + 1] = vdata.hvnm; end
end

local function saveLive()
    if LIVE == nil then return; end
    local f = io.open(liveFile(), 'w');
    if f == nil then return; end
    f:write('-- The last venture board VenGo saw (rewritten by VenGo)\nreturn {\n');
    f:write(('  at = %d,\n  exp = {\n'):format(LIVE.at));
    for _, r in ipairs(LIVE.exp) do
        f:write(('    { pool=%d, tier=%d, ace=%d, cw=%d, progress=%d },\n'):format(r.pool, r.tier, r.ace, r.cw, r.progress));
    end
    f:write('  },\n');
    if LIVE.hvnm then
        f:write(('  hvnm = { zone=%d, progress=%s },\n'):format(LIVE.hvnm.zone, tostring(LIVE.hvnm.progress)));
    end
    f:write('}\n');
    f:close();
end

loadLive = function()
    local t = loadTable(liveFile());
    if t and type(t.exp) == 'table' then LIVE = t; end
end

local LIVE_RAW = nil;         -- the last board processed (so the same one isn't read twice)

onVenturePacket = function(data)
    if data == nil or #data < 0x54 then return; end
    if data == LIVE_RAW then
        if LIVE then LIVE.at = os.time(); end                         -- (the same board again: still current)
        return;
    end
    LIVE_RAW = data;
    local exp = {};
    for pool = 0, 1 do
        for tier = 0, 5 do
            local off = 0x08 + pool * 0x24 + tier * 6;
            exp[#exp + 1] = { pool = pool, tier = tier + 1, ace = u16(data, off), cw = u16(data, off + 2), progress = u8(data, off + 4) };
        end
    end
    local hp = u8(data, 0x52) / 2;
    LIVE = { at = os.time(), exp = exp, hvnm = { zone = u16(data, 0x50), progress = (hp == math.floor(hp)) and hp or tonumber(('%.1f'):format(hp)) } };
    saveLive();
    applyLive(true);
    saveTrends();
end

-- Look at the last board VanaCore has seen, in case one came in that the
-- packet event didn't hand us (before VenGo loaded, or while reloading)
local BOARD_POLL = 5;         -- seconds between looks
local pollAt = 0;
pollBoard = function(now)
    if now - pollAt < BOARD_POLL then return; end
    pollAt = now;
    if rawget(_G, 'vana') == nil or vana.packets == nil or vana.packets.last == nil then return; end
    local ok, data = pcall(vana.packets.last, true, 0x1A3);
    if ok and type(data) == 'string' and data ~= LIVE_RAW then pcall(onVenturePacket, data); end
end

-- Once per log-in: ask the server for the board, a few seconds after the
-- character is in the world (also when VenGo loads after you're already in)
LOGIN_ASK = { done = false, at = nil };
loginTick = function()
    if LOGIN_ASK.done or not config.login_refresh then return; end
    local inWorld = false;
    pcall(function () inWorld = (vana.game.character() ~= nil) and not vana.game.zoning(); end);
    if not inWorld then LOGIN_ASK.at = nil; return; end
    LOGIN_ASK.at = LOGIN_ASK.at or (os.time() + 8);
    if os.time() >= LOGIN_ASK.at then
        LOGIN_ASK.done = true;
        command('!ventures');
        msg('Asked the server for the venture board (!ventures).');
    end
end

-- Ask the server for the board (the same as typing !ventures)
local refreshAt = 0;
refreshBoard = function()
    if os.time() - refreshAt < 10 then msg('Just asked; give it a moment.'); return; end
    refreshAt = os.time();
    command('!ventures');
    pollAt = 0;
end

liveAge = function()
    if LIVE == nil then return nil; end
    local s = os.time() - (LIVE.at or os.time());
    if s < 60 then return 'just now'; end
    if s < 3600 then return ('%d min ago'):fmt(math.floor(s / 60)); end
    return ('%dh %02dm ago'):fmt(math.floor(s / 3600), math.floor(s % 3600 / 60));
end

end

local SITE, applySite, siteLoadCache, siteTick, siteAge;
do
------------------------------------------------------------------------
-- catseyexi.com/events: the same board the website shows, from its own
-- data feed (https://catseyexi.com/api/ventures). It fills in what the game's
-- board doesn't have: the HVNM's level, HP, next one and loot, each
-- venture's mobs, HELM, Fishing and Dynamis, and the next reset.
-- Fetched with Windows' own curl.exe, in the background (the game never waits):
-- at load if the saved copy is from before the last reset, then a couple of
-- minutes after every reset (ventures rotate daily), and at least once a week.
------------------------------------------------------------------------
local SITE_URL   = 'https://catseyexi.com/api/ventures';
local SITE_AFTER_RESET = 120; -- seconds after a reset before asking (the site needs a moment)
local SITE_MAX_AGE = 7 * 86400; -- never older than a week
local SITE_WAIT  = 20;        -- seconds to wait for an answer

SITE = { data = nil, at = nil, asked = nil, pending = false, err = nil, resetAt = nil, nextAt = 1 };   -- nextAt 0 = now

local function siteFile() return addon.path .. 'site_ventures.json'; end
local function siteTmp() return addon.path .. 'site_ventures.tmp'; end

local function readAll(path)
    local f = io.open(path, 'rb');
    if f == nil then return nil; end
    local d = f:read('*a');
    f:close();
    return d;
end

local function jsonDecode(text)
    if text == nil or text == '' then return nil; end
    local ok, t = pcall(function ()
        if rawget(_G, 'vana') and vana.json and vana.json.decode then return vana.json.decode(text); end
        return require('json').decode(text);
    end);
    if ok and type(t) == 'table' then return t; end
    return nil;
end

-- zone name -> zone id, from the game's own zone list
local ZONE_IDS = nil;
local function zoneIdOf(name)
    if ZONE_IDS == nil then
        ZONE_IDS = {};
        for id = 1, 1023 do
            local n = nil;
            pcall(function () n = AshitaCore:GetResourceManager():GetString('zones.names', id); end);
            if n and n ~= '' and ZONE_IDS[zoneKey(n)] == nil then ZONE_IDS[zoneKey(n)] = id; end
        end
    end
    local id = ZONE_IDS[zoneKey(name)];
    if id == nil then
        pcall(function () id = vana.gamedata.find('zones', name); end);
    end
    return id;
end

-- "(G-9)" -> 'G-9'; "Map 3 (I-8)" -> 'I-8', 3
local function parseLoc(loc)
    loc = tostring(loc or '');
    local grid = loc:match('(%a%-%d+)');
    local mapNo = tonumber(loc:match('[Mm]ap%s*(%d+)'));
    return grid, mapNo;
end

-- "2026-10-26T15:00:00.000Z" -> seconds (only used for differences, so the time zone doesn't matter)
local function isoSeconds(s)
    local y, mo, d, h, mi, se = tostring(s or ''):match('(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)');
    if not y then return nil; end
    return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(se) });
end

local function mobList(d)
    local out = {};
    for _, m in ipairs((d and d.mobs) or {}) do
        out[#out + 1] = (tostring(m.name or ''):gsub('_', ' ')) .. (m.level and (' (' .. m.level .. ')') or '');
    end
    for _, m in ipairs((d and d.dynamic) or {}) do
        local lv = type(m.level) == 'table' and (m.level[1] .. '-' .. m.level[2]) or m.level;
        out[#out + 1] = tostring(m.name or '') .. (lv and (' (' .. lv .. ')') or '');
    end
    return out;
end

local function itemList(items)
    local out = {};
    for _, it in ipairs(items or {}) do
        out[#out + 1] = tostring(it.name or '?') .. (it.points and (' (' .. it.points .. ' pt)') or '');
    end
    return table.concat(out, ', ');
end

-- Put the website's board into the list
applySite = function(alerts)
    local r = SITE.data;
    if r == nil or type(r.ventures) ~= 'table' then return; end
    local V = r.ventures;
    local mode = (config.mode == 'CW') and 'cw' or 'ace';

    local list = {};
    for _, pool in ipairs({ 'a', 'b' }) do
        local P = V.exp and V.exp[pool];
        for tier = 1, 6 do
            local e = P and (P[tostring(tier)] or P[tier]);
            local d = e and e[mode];
            if d and d.area then
                local key = pool .. tier;
                local v = LIVEV[key] or { key = key };
                LIVEV[key] = v;
                local zid = zoneIdOf(d.area) or v.zone or 0;
                local before = (v.zone == zid) and v.progress or nil;
                v.pool, v.tier = pool:upper(), tier;
                v.levels = tostring(e.level or TIER_LEVELS[tier] or ''):gsub('[()]', '');
                v.zone, v.zone_name = zid, d.area;
                fillFromDb(v, TIER_LEVELS[tier]);                 -- (drops, notes, element, crest)
                local grid, mapNo = parseLoc(d.bossLoc);
                v.nm = d.bossName or v.nm;
                v.grid = grid or v.grid;
                v.map = mapNo or v.map;
                v.mobs = mobList(d);
                v.site_zone, v.site_nm, v.site_grid, v.site_map = zid, v.nm, v.grid, v.map;
                if (v.prog_at or 0) <= (SITE.at or 0) or v.zone ~= v.prog_zone then
                    v.progress = tonumber(e.bossProgress) or v.progress or 0;
                    v.prog_at, v.prog_zone = SITE.at or os.time(), zid;
                end
                v.live = true;
                list[#list + 1] = v;
                if alerts then recordTrend(key, zid, v.progress); crossed(v, before); end
                if (v.progress or 0) < 100 and POPS[key] then POPS[key] = nil; savePops(); end
            end
        end
    end
    if #list > 0 then vdata.exp = list; end

    local H = r.hvnm;
    if type(H) == 'table' and H.area then
        local h = LIVEV.hvnm or { key = 'hvnm', aliases = { 'hv' } };
        LIVEV.hvnm = h;
        local zid = zoneIdOf(H.area) or h.zone or 0;
        local before = (h.zone == zid) and h.progress or nil;
        h.zone, h.zone_name = zid, H.area;
        fillFromDb(h, 'HVNM');
        local grid = parseLoc(H.loc);
        h.nm = H.name or h.nm;
        h.grid = grid or h.grid;
        h.level, h.hp = H.level, H.hp;
        h.next_up = (type(H.next) == 'table' and H.next.name) and (H.next.name .. (H.next.area and (' (' .. H.next.area .. ')') or '')) or nil;
        h.loot = (type(H.loot) == 'table' and #H.loot > 0) and H.loot or splitList(h.drops);
        h.lootItems = {};                                            -- (id and rarity per loot name, for the tooltips)
        for _, it in ipairs((type(H.lootItems) == 'table') and H.lootItems or {}) do
            if it.name then h.lootItems[it.name] = it; end
        end
        h.drops = table.concat(h.loot or {}, ', ');
        if (h.prog_at or 0) <= (SITE.at or 0) or h.zone ~= h.prog_zone then
            h.progress = tonumber(H.progress) or h.progress or 0;
            h.prog_at, h.prog_zone = SITE.at or os.time(), zid;
        end
        h.site_zone = zid;
        h.live = true;
        vdata.hvnm = h;
        if alerts then recordTrend('hvnm', zid, h.progress); crossed(h, before); end
        if (h.progress or 0) < 100 and POPS.hvnm then POPS.hvnm = nil; savePops(); end
    end

    -- HELM, Fishing, Dynamis
    local helm = {};
    for _, kind in ipairs({ 'harvesting', 'excavation', 'logging', 'mining' }) do
        local K = V[kind];
        for t = 1, 6 do
            local row = K and (K[tostring(t)] or K[t]);
            if row and row.area then
                helm[#helm + 1] = { kind:sub(1, 1):upper() .. kind:sub(2), row.tierName or ('Tier ' .. t), row.area,
                                    row.exp and (row.exp .. ' exp') or '', itemList(row.items) };
            end
        end
    end
    if #helm > 0 then vdata.helm_rows = helm; end
    local fish = {};
    for t = 1, 6 do
        local row = V.fishing and (V.fishing[tostring(t)] or V.fishing[t]);
        if row and row.fish then
            fish[#fish + 1] = { 'Tier ' .. t, tostring(row.name or ''):gsub('[()]', ''), row.fish.name or '?', 'x' .. tostring(row.fish.qty or '?') };
        end
    end
    if #fish > 0 then vdata.fishing_rows = fish; end
    local dyna = {};
    for t = 1, 6 do
        local row = V.dynamis and (V.dynamis[tostring(t)] or V.dynamis[t]);
        if row and row.area then
            dyna[#dyna + 1] = { 'Dynamis - ' .. row.area, 'Tier ' .. tostring(row.tier or t), 'x' .. tostring(row.qty or '?'), row.exp and (row.exp .. ' exp') or '' };
        end
    end
    if #dyna > 0 then vdata.dynamis_rows = dyna; end

    -- the next reset, as a time on this PC's clock
    local nr, now = isoSeconds(V.nextReset), isoSeconds(r.currentTime);
    if nr and now then SITE.resetAt = (SITE.at or os.time()) + (nr - now); end

    ventures = {};
    for _, v in ipairs(vdata.exp or {}) do ventures[#ventures + 1] = v; end
    if vdata.hvnm then ventures[#ventures + 1] = vdata.hvnm; end
end

-- Start a download in the background (curl.exe, no window)
local function siteAsk()
    if SITE.pending then return; end
    os.remove(siteTmp());
    local ok, err = pcall(function ()
        local ffi = require('ffi');
        pcall(ffi.cdef, 'void* __stdcall ShellExecuteA(void* hwnd, const char* op, const char* file, const char* params, const char* dir, int show);');
        local args = ('-s -f -L -m %d -A "VenGo/%s" -o "%s" "%s"'):format(SITE_WAIT - 2, addon.version, siteTmp(), SITE_URL);
        local r = ffi.load('shell32').ShellExecuteA(nil, 'open', 'curl.exe', args, nil, 0);
        if tonumber(ffi.cast('intptr_t', r)) <= 32 then error('curl.exe could not be started'); end
    end);
    if not ok then
        SITE.err = tostring(err);
        return;
    end
    SITE.pending, SITE.asked = true, os.time();
end

local function siteMetaFile() return addon.path .. 'site_meta.lua'; end

-- When the saved copy was fetched and when the next reset after it is
local function saveSiteMeta()
    local f = io.open(siteMetaFile(), 'w');
    if f == nil then return; end
    f:write(('return { at = %d, resetAt = %d }\n'):format(SITE.at or 0, SITE.resetAt or 0));
    f:close();
end

-- See whether the download has finished
local function siteCheck(alerts)
    if not SITE.pending then return; end
    local data = jsonDecode(readAll(siteTmp()));
    if data and data.ventures then
        SITE.pending = false;
        SITE.data, SITE.at, SITE.err = data, os.time(), nil;
        pcall(function ()
            local f = io.open(siteFile(), 'wb');
            if f then f:write(readAll(siteTmp())); f:close(); end
        end);
        os.remove(siteTmp());
        applySite(alerts);
        saveSiteMeta();
        saveTrends();
    elseif os.time() - (SITE.asked or 0) > SITE_WAIT then
        SITE.pending = false;
        SITE.err = 'no answer from catseyexi.com';
        os.remove(siteTmp());
    end
end

-- The last download, so the list is filled in right after a reload
siteLoadCache = function()
    local data = jsonDecode(readAll(siteFile()));
    if data and data.ventures then
        SITE.data = data;
        local chunk = loadfile(siteMetaFile());
        local ok, m = false, nil;
        if chunk then ok, m = pcall(chunk); end
        SITE.at = (ok and type(m) == 'table' and tonumber(m.at) and m.at > 0) and m.at or (os.time() - SITE_MAX_AGE);
        applySite(false);                                            -- (also works out resetAt from the copy)
    end
end

-- Due: never fetched, the copy is from before the last reset, or it's a week old
local function siteDue()
    if SITE.at == nil then return true; end
    local now = os.time();
    if now - SITE.at >= SITE_MAX_AGE then return true; end
    if SITE.resetAt and now >= SITE.resetAt + SITE_AFTER_RESET then return true; end
    return false;
end

local siteTickAt = 0;
siteTick = function(now)
    if not config.website then return; end
    if now - siteTickAt < 1 then return; end
    siteTickAt = now;
    siteCheck(true);
    pcall(SITE.xTick);
    if SITE.pending then return; end
    local now2 = os.time();
    if now2 >= (SITE.nextAt or 0) and (SITE.nextAt == 0 or siteDue()) then
        SITE.nextAt = now2 + 300;                                    -- (a failed try waits 5 minutes)
        siteAsk();
    end
end

-- Hunter of the week and Summit of the Stars, from the same site (its Events page feeds): fetched together in the
-- background at load, again the moment the Summit's target changes, and every 30 minutes
SITE.x = { pending = false, at = nil, asked = nil, hunter = nil, summit = nil, summitEnd = nil, nextAt = 0 };
local X_URLS = { hunter = 'https://catseyexi.com/api/events/hunter', summit = 'https://catseyexi.com/api/summit' };
function SITE.xFile(k, tmp) return addon.path .. 'site_' .. k .. (tmp and '.tmp' or '.json'); end
function SITE.xApply(k, data, at)
    local X = SITE.x;
    if k == 'hunter' and type(data) == 'table' and (data.ace or data.cw) then X.hunter = data; end
    if k == 'summit' and type(data) == 'table' and data.currentObjective then
        X.summit = data;
        local tr = data.currentObjective.timeRemaining;
        local secs = type(tr) == 'table' and tonumber(tr.total) or nil;
        X.summitEnd = secs and (at + secs) or nil;
    end
end
function SITE.xAsk()
    local X = SITE.x;
    if X.pending then return; end
    os.remove(SITE.xFile('hunter', true)); os.remove(SITE.xFile('summit', true));
    local ok = pcall(function ()
        local ffi = require('ffi');
        pcall(ffi.cdef, 'void* __stdcall ShellExecuteA(void* hwnd, const char* op, const char* file, const char* params, const char* dir, int show);');
        local args = ('-s -f -L -m %d -A "VenGo/%s" -o "%s" "%s" -o "%s" "%s"'):format(SITE_WAIT - 2, addon.version,
            SITE.xFile('hunter', true), X_URLS.hunter, SITE.xFile('summit', true), X_URLS.summit);
        local r = ffi.load('shell32').ShellExecuteA(nil, 'open', 'curl.exe', args, nil, 0);
        if tonumber(ffi.cast('intptr_t', r)) <= 32 then error('curl.exe could not be started'); end
    end);
    if ok then X.pending, X.asked = true, os.time(); end
end
function SITE.xCheck()
    local X = SITE.x;
    if not X.pending then return; end
    local now = os.time();
    local h = jsonDecode(readAll(SITE.xFile('hunter', true)));
    local s = jsonDecode(readAll(SITE.xFile('summit', true)));
    if (h and s) or now - (X.asked or 0) > SITE_WAIT then
        X.pending = false;
        for k, d in pairs({ hunter = h, summit = s }) do
            if d then
                SITE.xApply(k, d, now);
                pcall(function ()
                    local f = io.open(SITE.xFile(k), 'wb');
                    if f then f:write(readAll(SITE.xFile(k, true)) or ''); f:close(); end
                end);
            end
            os.remove(SITE.xFile(k, true));
        end
        if h or s then
            X.at = now;
            local f = io.open(addon.path .. 'site_x_meta.lua', 'w');
            if f then f:write(('return { at = %d }\n'):format(now)); f:close(); end
        end
    end
end
function SITE.xLoadCache()
    local at = os.time();
    pcall(function () local m = loadfile(addon.path .. 'site_x_meta.lua'); if m then local t_ = m(); at = tonumber(t_.at) or at; end end);
    for _, k in ipairs({ 'hunter', 'summit' }) do
        local d = jsonDecode(readAll(SITE.xFile(k)));
        if d then SITE.xApply(k, d, at); SITE.x.at = at; end
    end
end
function SITE.xTick()
    local X = SITE.x;
    SITE.xCheck();
    if X.pending then return; end
    local now = os.time();
    local due = (X.at == nil) or (now - X.at >= 1800) or (X.summitEnd and now >= X.summitEnd + 20 and now - X.at > 60);
    if due and now >= (X.nextAt or 0) then
        X.nextAt = now + 60;                                         -- (a failed try waits a minute)
        SITE.xAsk();
    end
end

siteAge = function()
    if SITE.at == nil then return nil; end
    local s = os.time() - SITE.at;
    if s < 60 then return 'just now'; end
    if s < 3600 then return ('%d min ago'):fmt(math.floor(s / 60)); end
    return ('%dh %02dm ago'):fmt(math.floor(s / 3600), math.floor(s % 3600 / 60));
end

end

local function pickCurrent()
    if ALERT then return ALERT.v; end
    local best = nil;
    for _, e in ipairs(ventures) do
        if e.key ~= 'hvnm' and (best == nil or (e.progress or 0) > (best.progress or 0)) then best = e; end
    end
    return best;
end

local SYSTEMS, SYS_NAME, WARPS, WARPS_FROM, loadWarps, nearSystem, warpOptions, LASTWARP, ARMED, warpTo, warpNext, tickArm;
local TRF = {};                  -- the trail's GO / STOP and its venture (filled in by the trail module below)
do
------------------------------------------------------------------------
-- Warping, through the Uberwarp plugin (/uw). GO picks the warp that lands
-- closest to the VNM in the venture's zone, using the warp NPC you're
-- standing at: Home Point -> Home Point, Survival Guide -> Survival Guide,
-- Unity NPC -> Unity warp. Not standing at one yet: GO waits, and warps the
-- moment you walk up to one (for 3 minutes).
-- Destinations and NPC spots are read from Uberwarp's own files.
------------------------------------------------------------------------
local WARP_NEAR  = 6.0;       -- yalms: close enough to use a warp NPC (Uberwarp needs ~5.5)
local ARM_TIME   = 180;       -- seconds GO keeps waiting for you to reach a warp NPC
SYSTEMS    = { 'hp', 'sg', 'uc' };
SYS_NAME   = { hp = 'Home Point', sg = 'Survival Guide', uc = 'Unity warp' };
local SYS_FILES  = { hp = { 'homepoint.xml', 'uwHomePoints.xml' }, sg = { 'survivalguide.xml', 'uwSurvivalGuides.xml' },
                     uc = { 'unitywarp.xml', 'uwUnity.xml' } };

-- Zones where the closest warp is in another zone. Listed per warp kind, in order
-- of preference, by Uberwarp's alias. Unity warps aren't changed.
local WARP_OVERRIDES = {
    [72] = { name = 'Aht Urhgan Whitegate',                           -- Alzadaal Undersea Ruins
             hp = { 'Aht Urhgan Whitegate2' },                        --   Whitegate Home Point #2
             sg = { 'Aht Urhgan Whitegate' } },                       --   Whitegate Survival Guide
    [52] = { name = 'Aht Urhgan Whitegate',                           -- Bhaflau Thickets
             hp = { 'Aht Urhgan Whitegate' } },                       --   Whitegate Home Point #1
    [51] = { name = 'Aht Urhgan Whitegate',                           -- Wajaom Woodlands
             hp = { 'Aht Urhgan Whitegate' } },                       --   Whitegate Home Point #1
    [79] = { name = 'Nashmau',                                        -- Caedarva Mire
             hp = { 'Nashmau' } },                                    --   Nashmau Home Point
};

WARPS = nil;            -- { hp = { dest = {...}, npc = {...} }, sg = ..., uc = ... }
WARPS_FROM = nil;       -- the folder they were read from

local function readXml(path)
    local f = io.open(path, 'rb');
    if f == nil then return nil; end
    local s = f:read('*a');
    f:close();
    s = s:gsub('<!%-%-.-%-%->', '');
    local out = {};
    for attrs in s:gmatch('<entry%s+(.-)/>') do
        local e = {};
        for k, v in attrs:gmatch('([%w_]+)%s*=%s*"([^"]*)"') do e[k] = v; end
        e.zone = tonumber(e.zone);
        e.x, e.y = tonumber(e.posx), tonumber(e.posy);
        out[#out + 1] = e;
    end
    return out;
end

local function warpBases()
    local list = {};
    local function add(p)
        if p and p ~= '' then
            p = p:gsub('[\\/]+$', '') .. '\\';
            list[#list + 1] = p;
        end
    end
    add(addon.path);                                                  -- (copied next to VenGo)
    pcall(function () add(AshitaCore:GetInstallPath()); end);
    pcall(function () add(vana.paths.install); end);
    pcall(function () add((addon.path:gsub('[\\/]+$', '')):match('^(.*)[\\/][^\\/]+[\\/][^\\/]+[\\/][^\\/]+$')); end);   -- VanaCore\ from addons\vanacore\vengo
    return list;
end

loadWarps = function()
    WARPS, WARPS_FROM = nil, nil;
    for _, base in ipairs(warpBases()) do
        local root = base .. 'resources\\ashitahelper\\';
        if readXml(root .. 'uberwarp\\homepoint.xml') then
            local w = {};
            for _, sys in ipairs(SYSTEMS) do
                w[sys] = { dest = readXml(root .. 'uberwarp\\' .. SYS_FILES[sys][1]) or {},
                           npc = readXml(root .. 'entities\\' .. SYS_FILES[sys][2]) or {} };
            end
            WARPS, WARPS_FROM = w, root;
            return true;
        end
    end
    return false;
end

-- Uberwarp takes names without spaces or punctuation ("uleguerandrange3")
local function compact(s)
    local r = tostring(s or ''):lower():gsub('[^%w]', '');
    return r;
end

-- Which warp system's NPC you're standing next to (nil if none)
nearSystem = function()
    local z = zone();
    local x, y = pos();
    if x == nil or WARPS == nil then return nil; end
    local best, bestD = nil, WARP_NEAR;
    for _, sys in ipairs(SYSTEMS) do
        for _, n in ipairs(WARPS[sys].npc) do
            if n.zone == z and n.x then
                local d = dist2d(x, y, n.x, n.y);
                if d <= bestD then best, bestD = sys, d; end
            end
        end
    end
    if best then return best; end
    -- not in Uberwarp's list: look at the NPCs loaded around you
    pcall(function ()
        local ent = mm():GetEntity();
        local unity = {};
        for _, n in ipairs(WARPS.uc.npc) do unity[(n.name or ''):lower()] = true; end
        for i = 1, MAX_ENTITY_IDX do
            local nm = ent:GetName(i);
            if nm ~= nil and nm ~= '' then
                local low = nm:lower();
                local sys = (low:find('^home point') and 'hp') or (low == 'survival guide' and 'sg') or (unity[low] and 'uc') or nil;
                if sys then
                    local ex, ey = entPos(i);
                    if ex and dist2d(x, y, ex, ey) <= bestD then best, bestD = sys, dist2d(x, y, ex, ey); end
                end
            end
        end
    end);
    return best;
end

-- Every warp into the venture's zone, per system, closest to the VNM first
warpOptions = function(v)
    local out = { hp = {}, sg = {}, uc = {} };
    if WARPS == nil or v == nil then return out; end
    local ov = WARP_OVERRIDES[v.zone];
    if ov then
        for _, sys in ipairs({ 'hp', 'sg' }) do
            for _, alias in ipairs(ov[sys] or {}) do
                out[sys][#out[sys] + 1] = { sys = sys, alias = alias, via = ov.name };
            end
        end
    end
    local tx, ty = gridToWorld(v.zone, v.grid, v.map);
    for _, sys in ipairs({ 'hp', 'sg' }) do
        if not (ov and ov[sys]) then                                 -- (a kind with an override uses only that)
            for _, d in ipairs(WARPS[sys].dest) do
                if d.zone == v.zone then
                    out[sys][#out[sys] + 1] = { sys = sys, alias = d.alias,
                        dist = (tx and d.x) and dist2d(tx, ty, d.x, d.y) or nil };
                end
            end
            table.sort(out[sys], function (a, b) return (a.dist or 1e9) < (b.dist or 1e9); end);
        end
    end
    local zk = zoneKey(v.zone_name);
    for _, d in ipairs(WARPS.uc.dest) do
        if zoneKey(d.alias) == zk then
            out.uc[#out.uc + 1] = { sys = 'uc', alias = d.alias };
            break;                                                    -- (a zone listed twice: the first one)
        end
    end
    return out;
end

local function warpSummary(opts)
    local have = {};
    for _, sys in ipairs(SYSTEMS) do
        if #opts[sys] > 0 then have[#have + 1] = SYS_NAME[sys] .. ((#opts[sys] > 1) and ('s (' .. #opts[sys] .. ')') or ''); end
    end
    return (#have > 0) and table.concat(have, ', ') or 'none';
end

-- The warp you just did, so "next closest" can try the one after it
LASTWARP = nil;         -- { v, sys, list, i, at }

local function doWarp(v, sys, list, i)
    local w = list[i];
    if w == nil then return false; end
    local where = '';
    if w.dist then where = (' (about %d yalms from %s)'):fmt(math.floor(w.dist + 0.5), v.grid or 'the VNM'); end
    if w.via then where = (', the closest way to %s'):fmt(v.zone_name or 'the VNM'); end
    msg(('Warping by %s to %s%s.'):fmt(SYS_NAME[sys], w.alias, where));
    command(('/uw %s %s'):fmt(sys, compact(w.alias)));
    LASTWARP = { v = v, sys = sys, list = list, i = i, at = os.time() };
    return true;
end

ARMED = nil;            -- { v, until } : GO pressed away from a warp NPC

-- GO: warp toward a venture (or wait for a warp NPC)
warpTo = function(v)
    if v == nil then return; end
    TRF.trailPick(v);
    if WARPS == nil and not loadWarps() then
        msg('Uberwarp\'s files weren\'t found. Install Uberwarp (its resources folder goes in the VanaCore folder), or copy its "resources" folder into the vengo folder.');
        return;
    end
    local ov = WARP_OVERRIDES[v.zone];
    local ovZone = nil;
    if ov then
        for _, d in ipairs(WARPS.hp.dest) do if d.alias == (ov.hp or {})[1] then ovZone = d.zone; end end
    end
    if ov and ovZone and zone() == ovZone then
        msg(('You\'re in %s. Head into %s; %s is at %s.'):fmt(ov.name, v.zone_name, v.nm or 'the VNM', v.grid or '?'));
        return;
    end
    if zone() == v.zone then
        ARMED = nil;
        if TRF.trailGo(v) then return; end                       -- (in the zone: GO / STOP turns the arrows on and off)
        msg(('You\'re already in %s. %s is at %s%s.'):fmt(v.zone_name, v.nm or 'The VNM', v.grid or '?',
            (v.notes and v.notes ~= '') and (' (' .. v.notes .. ')') or ''));
        return;
    end
    local opts = warpOptions(v);
    local sys = nearSystem();
    if sys == nil then
        ARMED = { v = v, untilT = os.time() + ARM_TIME };
        msg(('Walk up to a warp for %s: %s. VenGo warps the moment you\'re there.'):fmt(v.zone_name, warpSummary(opts)));
        return;
    end
    ARMED = nil;
    if #opts[sys] == 0 then
        msg(('No %s goes to %s. It has: %s.'):fmt(SYS_NAME[sys], v.zone_name, warpSummary(opts)));
        return;
    end
    doWarp(v, sys, opts[sys], 1);
end

-- The closest one isn't unlocked: try the next one
warpNext = function()
    local L = LASTWARP;
    if L == nil then return; end
    if not doWarp(L.v, L.sys, L.list, L.i + 1) then
        msg(('No other %s goes to %s.'):fmt(SYS_NAME[L.sys], L.v.zone_name));
        LASTWARP = nil;
    end
end

-- Waiting after GO: warp as soon as you're at a warp NPC that goes there
local armCheckAt = 0;
tickArm = function(now)
    if ARMED == nil or now - armCheckAt < 0.5 then return; end
    armCheckAt = now;
    if os.time() > ARMED.untilT then
        msg('Stopped waiting for a warp NPC.');
        ARMED = nil;
        return;
    end
    local sys = nearSystem();
    if sys == nil then return; end
    local v = ARMED.v;
    ARMED = nil;
    warpTo(v);
end


end

------------------------------------------------------------------------
-- The VenGo window, in YunaUI's style: a near-black rounded panel with a soft
-- violet glow and pink edge, a sidebar (VEN GO, the tabs) with a slanted edge,
-- spaced capitals, pill switches, violet-edged buttons, pink-to-violet bars.
-- (Drawing helpers adapted from YunaUI by Yunas, GPL v3.)
------------------------------------------------------------------------
local C = {
    text   = { 0.910, 0.922, 0.957, 1.00 },
    muted  = { 0.545, 0.576, 0.667, 1.00 },
    acc    = { 0.74, 0.66, 0.95, 1.00 },        -- soft lavender
    pbg    = { 0.068, 0.066, 0.088 },
    pframe = { 0.165, 0.158, 0.205 },
    hp     = { 1.000, 0.36, 0.62 },             -- pink
    mp2    = { 0.62, 0.40, 1.00 },              -- violet
    here   = { 0.55, 0.90, 0.68, 1.00 },        -- a venture in your zone
    active = { 1.00, 0.80, 0.45, 1.00 },        -- the venture you're running to
    seal   = { 0.62, 0.80, 1.00, 1.00 },
    lav    = { 0.76, 0.70, 0.98, 1.00 },        -- values on the right (ChadcoreMenu style)
    label  = { 0.72, 0.66, 0.95, 1.00 },        -- the small spaced capitals
    gold   = { 0.96, 0.76, 0.32, 1.00 },
    green  = { 0.48, 0.92, 0.58, 1.00 },
    panel  = { 0.090, 0.084, 0.115 },           -- the panel
    well   = { 0.060, 0.056, 0.080 },           -- the darker boxes in it
    rall   = ImDrawFlags_RoundCornersAll or ImDrawCornerFlags_All or 15,
};
local NEON  = { 0.86, 0.24, 0.86 };
local NEON2 = { 1.00, 0.42, 0.72 };

-- Colour themes (Settings > Colours). The colours are changed in place, so everything drawn with them follows.
-- Accent: { main, second, soft }; background: { panel bg, frames, panel, wells }.
C.accents = {
    { 'pink',    'Pink & violet', { 1.00, 0.42, 0.72 }, { 0.62, 0.40, 1.00 }, { 0.74, 0.66, 0.95 } },
    { 'ocean',   'Ocean',         { 0.35, 0.70, 1.00 }, { 0.25, 0.90, 0.85 }, { 0.66, 0.82, 0.98 } },
    { 'emerald', 'Emerald',       { 0.40, 0.92, 0.60 }, { 0.25, 0.78, 0.92 }, { 0.70, 0.92, 0.80 } },
    { 'sunset',  'Sunset',        { 1.00, 0.55, 0.25 }, { 1.00, 0.32, 0.45 }, { 1.00, 0.80, 0.66 } },
    { 'gold',    'Gold',          { 0.98, 0.78, 0.30 }, { 0.95, 0.52, 0.20 }, { 0.98, 0.88, 0.66 } },
    { 'crimson', 'Crimson',       { 1.00, 0.30, 0.36 }, { 0.72, 0.22, 0.50 }, { 0.98, 0.72, 0.76 } },
    { 'ice',     'Ice',           { 0.80, 0.90, 1.00 }, { 0.50, 0.62, 0.85 }, { 0.82, 0.86, 0.94 } },
};
C.bgs = {
    { 'violet',   'Violet black', { 0.068, 0.066, 0.088 }, { 0.165, 0.158, 0.205 }, { 0.090, 0.084, 0.115 }, { 0.060, 0.056, 0.080 } },
    { 'black',    'Black',        { 0.045, 0.045, 0.048 }, { 0.140, 0.140, 0.150 }, { 0.065, 0.065, 0.070 }, { 0.035, 0.035, 0.040 } },
    { 'navy',     'Navy',         { 0.045, 0.065, 0.105 }, { 0.130, 0.170, 0.240 }, { 0.065, 0.090, 0.140 }, { 0.035, 0.050, 0.085 } },
    { 'charcoal', 'Charcoal',     { 0.105, 0.105, 0.115 }, { 0.210, 0.210, 0.230 }, { 0.130, 0.130, 0.142 }, { 0.080, 0.080, 0.090 } },
    { 'plum',     'Plum',         { 0.090, 0.050, 0.085 }, { 0.215, 0.140, 0.205 }, { 0.120, 0.070, 0.112 }, { 0.070, 0.038, 0.066 } },
    { 'forest',   'Forest',       { 0.045, 0.075, 0.060 }, { 0.130, 0.190, 0.160 }, { 0.065, 0.100, 0.082 }, { 0.035, 0.058, 0.046 } },
};
function C.find(list, key) for _, e in ipairs(list) do if e[1] == key then return e; end end return list[1]; end
function C.apply()
    local function set(dst, src, k) dst[1], dst[2], dst[3] = src[1] * (k or 1), src[2] * (k or 1), src[3] * (k or 1); end
    local a = C.find(C.accents, config.theme);
    local m, s2, soft = a[3], a[4], a[5];
    set(NEON2, m);
    set(C.hp, { math.min(1, m[1] * 1.0), m[2] * 0.86, m[3] * 0.86 });
    set(C.mp2, s2);
    set(NEON, { (m[1] + s2[1]) / 2 * 0.95, (m[2] + s2[2]) / 2 * 0.62, (m[3] + s2[3]) / 2 * 0.98 });
    set(C.acc, soft); set(C.label, { soft[1] * 0.97, soft[2] * 0.99, soft[3] }); set(C.lav, { math.min(1, soft[1] * 1.03), math.min(1, soft[2] * 1.06), math.min(1, soft[3] * 1.03) });
    local b = C.find(C.bgs, config.bg);
    set(C.pbg, b[3]); set(C.pframe, b[4]); set(C.panel, b[5]); set(C.well, b[6]);
end

local SW, ROW_W, MARGIN = 200, 760, 8;
local FULL_ROW = 760;                                   -- width the venture rows need
local WIN_W = SW + 30 + MARGIN + FULL_ROW + 50;         -- starting size; the window can be resized
local WIN_H = 700;
local MIN_W, MIN_H = 640, 460;

local TABS = { 'VENTURES', 'HELM', 'FISHING', 'DYNAMIS', 'HUNTER', 'SUMMIT', 'SETTINGS', 'SPECIAL THANKS' };
ui.tab = ui.tab or 1;

local function statusText()
    if ARMED then return 'Waiting for a warp NPC', ARMED.v; end
    if LASTWARP and os.time() - LASTWARP.at < 20 then return 'Warping', LASTWARP.v; end
    return 'Ready', nil;
end

local function u32(c) return imgui.GetColorU32(c); end
local function tip(t) if imgui.IsItemHovered() then imgui.SetTooltip(t); end end

-- Fonts: the panel in TeX Gyre Adventor (the fonts folder), VEN GO in Bahnschrift, as YunaUI
local fonts = {};
local function loadFonts()
    local win = (os.getenv('WINDIR') or 'C:\\Windows') .. '\\Fonts\\';
    local function add(path, size)
        local f = io.open(path, 'rb');
        if f == nil then return nil; end
        f:close();
        local ok, font = pcall(imgui.AddFontFromFileTTF, path, size);
        return (ok and font) or nil;
    end
    fonts.panel = add(addon.path .. 'fonts\\texgyreadventor-regular.otf', 16)
        or add(win .. 'GOTHIC.TTF', 18) or add(win .. 'segoeui.ttf', 17);
    fonts.title = add(addon.path .. 'fonts\\texgyreadventor-regular.otf', 22) or add(win .. 'bahnschrift.ttf', 22);
    fonts.big   = add(addon.path .. 'fonts\\texgyreadventor-regular.otf', 24) or fonts.title;
end
local function newFont(f)
    local ok, ls = pcall(function () return f.LegacySize; end);
    return ok and ls ~= nil;
end
local function pushFont(f, size)
    if f == nil then return false; end
    if newFont(f) then return (pcall(imgui.PushFont, f, size)); end
    return (pcall(imgui.PushFont, f));
end

local function pushTheme()
    local cols = {
        { ImGuiCol_WindowBg, { C.pbg[1], C.pbg[2], C.pbg[3], 0.92 } }, { ImGuiCol_ChildBg, { 0, 0, 0, 0 } },
        { ImGuiCol_PopupBg, { C.pbg[1], C.pbg[2], C.pbg[3], 0.98 } }, { ImGuiCol_Border, { 1, 1, 1, 0.08 } },
        { ImGuiCol_Text, C.text }, { ImGuiCol_TextDisabled, C.muted },
        { ImGuiCol_FrameBg, { C.pframe[1], C.pframe[2], C.pframe[3], 0.70 } },
        { ImGuiCol_FrameBgHovered, { 0.22, 0.21, 0.27, 1 } }, { ImGuiCol_FrameBgActive, { 0.22, 0.21, 0.27, 1 } },
        { ImGuiCol_Button, { 1, 1, 1, 0.035 } }, { ImGuiCol_ButtonHovered, { 1, 1, 1, 0.08 } }, { ImGuiCol_ButtonActive, { 1, 1, 1, 0.12 } },
        { ImGuiCol_Separator, { 1, 1, 1, 0.07 } }, { ImGuiCol_ScrollbarBg, { 0, 0, 0, 0 } },
        { ImGuiCol_ScrollbarGrab, { C.acc[1], C.acc[2], C.acc[3], 0.30 } },
        { ImGuiCol_ScrollbarGrabHovered, { C.acc[1], C.acc[2], C.acc[3], 0.50 } },
    };
    local nc, nv = 0, 0;
    for _, c in ipairs(cols) do if c[1] ~= nil then imgui.PushStyleColor(c[1], c[2]); nc = nc + 1; end end
    local vars = {
        { ImGuiStyleVar_WindowRounding, 12 }, { ImGuiStyleVar_FrameRounding, 8 },
        { ImGuiStyleVar_WindowPadding, { 0, 0 } }, { ImGuiStyleVar_FramePadding, { 10, 6 } },
        { ImGuiStyleVar_ItemSpacing, { 8, 8 } }, { ImGuiStyleVar_WindowBorderSize, 0 }, { ImGuiStyleVar_FrameBorderSize, 0 },
        { ImGuiStyleVar_ScrollbarSize, 6 }, { ImGuiStyleVar_ScrollbarRounding, 3 },
    };
    for _, v in ipairs(vars) do if v[1] ~= nil then imgui.PushStyleVar(v[1], v[2]); nv = nv + 1; end end
    return nc, nv;
end

-- Text with letter spacing (section names, buttons)
local function spaced(dl, x, y, str, col, gap)
    local cx = x;
    for i = 1, #str do
        local ch = str:sub(i, i);
        dl:AddText({ cx, y }, col, ch);
        cx = cx + imgui.CalcTextSize(ch) + gap;
    end
    return cx - x - gap;
end
local function spacedW(str, gap)
    local w = 0;
    for i = 1, #str do w = w + imgui.CalcTextSize(str:sub(i, i)) + gap; end
    return w - gap;
end

-- A pill switch: on = deep violet with a white knob on the right, off = dark with a grey knob
local function switch(id, on)
    local x, y = imgui.GetCursorScreenPos();
    local w, h = 52, 26;
    local clicked = imgui.InvisibleButton(id, { w, h });
    local hov = imgui.IsItemHovered();
    local dl = imgui.GetWindowDrawList();
    dl:AddRectFilled({ x, y }, { x + w, y + h }, u32(on and { NEON[1] * 0.42, NEON[2] * 0.42, NEON[3] * 0.42, 1 }
        or (hov and { 0.14, 0.13, 0.18, 1 } or { 0.10, 0.095, 0.13, 1 })), h / 2);
    dl:AddCircleFilled({ on and (x + w - h / 2) or (x + h / 2), y + h / 2 }, h / 2 - 4,
        u32(on and { 1, 1, 1, 1 } or { 0.55, 0.53, 0.62, 1 }), 24);
    return clicked;
end

local function rowSwitch(id, text, on, hint)
    local x0 = imgui.GetCursorPosX();
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.text, text);
    if hint then tip(hint); end
    imgui.SameLine(x0 + ROW_W - 52);
    return switch(id, on);
end

-- A section name: spaced capitals, then a faint line to the edge
local function section(text)
    imgui.Spacing(); imgui.Spacing();
    local dl = imgui.GetWindowDrawList();
    local x0, y0 = imgui.GetCursorScreenPos();
    local lh = imgui.GetTextLineHeight();
    local tw = spaced(dl, x0, y0, text:upper(), u32(C.label), 2.5);
    dl:AddLine({ x0 + tw + 14, y0 + lh / 2 }, { x0 + ROW_W, y0 + lh / 2 }, u32({ 1, 1, 1, 0.06 }), 1);
    imgui.Dummy({ ROW_W, lh + 2 });
end

local function hint(t)
    imgui.PushTextWrapPos(imgui.GetCursorPosX() + ROW_W);
    imgui.TextColored(C.muted, t);
    imgui.PopTextWrapPos();
end

-- A rounded button: pink-edged (main) or dark (quiet = true), its name in spaced capitals
local function button(label, size, quiet, small)
    -- the label, measured at the size it's drawn: the button is never narrower than it
    local name = label:gsub('##.*$', ''):upper();
    local sp = small and 2 or 3;
    if small then imgui.SetWindowFontScale(0.82); end
    local lw = spacedW(name, sp);
    local lh = imgui.GetTextLineHeight();
    if small then imgui.SetWindowFontScale(1); end
    local pad = small and 24 or 36;
    local w = (size and size[1] and size[1] > 0) and size[1] or 0;
    w = math.max(w, lw + pad * 2);
    local h = (size and size[2] and size[2] > 0) and size[2] or math.floor(imgui.GetFrameHeight() * (small and 0.95 or 1.25));
    h = math.max(h, lh + (small and 8 or 12));
    local x, y = imgui.GetCursorScreenPos();
    local clicked = imgui.InvisibleButton(label, { w, h });
    local hov, act = imgui.IsItemHovered(), imgui.IsItemActive();
    local dl = imgui.GetWindowDrawList();
    local rr = 6;
    local fill = { 0.12, 0.11, 0.155, 1 };
    if hov or act then fill = act and { 0.18, 0.17, 0.23, 1 } or { 0.15, 0.14, 0.19, 1 }; end
    dl:AddRectFilled({ x, y }, { x + w, y + h }, u32(fill), rr);
    local ec = u32(quiet and { 1, 1, 1, hov and 0.25 or 0.14 } or { NEON2[1], NEON2[2], NEON2[3], hov and 1 or 0.8 });
    dl:AddRect({ x, y }, { x + w, y + h }, ec, rr, C.rall, quiet and 1 or 1.3);
    if small then imgui.SetWindowFontScale(0.82); end
    spaced(dl, x + (w - lw) / 2, y + (h - lh) / 2, name, u32({ 0.93, 0.91, 0.98, 1 }), sp);
    if small then imgui.SetWindowFontScale(1); end
    return clicked;
end

-- A thin pink-to-violet bar on a dark track, drawn where the cursor is
-- The progress bar with its speed shown:
--   fast    : bright, a quick light sweeping along it, a soft glow pulsing
--   slow    : a slow sweep
--   stalled : dimmed to grey-violet, just a faint breathing
--   watching: plain
--   100%    : full, pulsing pink
local function trendBar(w, frac, trend, h)
    h = h or 6;
    local lh = imgui.GetFrameHeight();
    local x, y = imgui.GetCursorScreenPos();
    imgui.Dummy({ w, lh });
    if trend then tip(trendText(trend)); end
    local dl = imgui.GetWindowDrawList();
    local cy = y + lh / 2;
    local y1, y2 = cy - h / 2, cy + h / 2;
    frac = math.max(0, math.min(1, frac or 0));
    local kind = trend and trend.kind or 'watching';
    local t = os.clock();
    local fw = w * frac;

    dl:AddRectFilled({ x, y1 }, { x + w, y2 }, u32({ 0.20, 0.19, 0.25, 1 }), h / 2);
    if fw <= 0 then return; end

    if kind == 'stalled' then
        local a = 0.45 + 0.10 * math.sin(t * 1.2);
        dl:AddRectFilled({ x, y1 }, { x + fw, y2 }, u32({ 0.42, 0.40, 0.52, a }), h / 2);
        return;
    end

    local c1, c2 = C.hp, C.mp2;
    local ok = pcall(function ()
        dl:AddRectFilledMultiColor({ x, y1 }, { x + fw, y2 }, u32(c1), u32(c2), u32(c2), u32(c1));
    end);
    if not ok then dl:AddRectFilled({ x, y1 }, { x + fw, y2 }, u32(NEON), h / 2); end

    if kind == 'full' then
        local a = 0.35 + 0.35 * math.sin(t * 5);
        dl:AddRect({ x - 2, y1 - 2 }, { x + w + 2, y2 + 2 }, u32({ NEON2[1], NEON2[2], NEON2[3], a }), h, C.rall, 2);
        return;
    end
    if kind ~= 'fast' and kind ~= 'slow' then return; end

    -- a band of light sweeping left to right across the filled part
    local speed = (kind == 'fast') and 1.1 or 0.35;
    local band = math.max(10, fw * 0.25);
    local u = (t * speed) % 1.4 - 0.2;
    local bx = x + u * fw;
    local a1, a2 = math.max(x, bx - band), math.min(x + fw, bx);
    local b1, b2 = math.max(x, bx), math.min(x + fw, bx + band);
    local clear, glow = u32({ 1, 1, 1, 0 }), u32({ 1, 1, 1, (kind == 'fast') and 0.75 or 0.45 });
    pcall(function ()
        if a2 > a1 then dl:AddRectFilledMultiColor({ a1, y1 }, { a2, y2 }, clear, glow, glow, clear); end
        if b2 > b1 then dl:AddRectFilledMultiColor({ b1, y1 }, { b2, y2 }, glow, clear, clear, glow); end
    end);
    if kind == 'fast' then
        local a = 0.10 + 0.12 * (0.5 + 0.5 * math.sin(t * 4));
        dl:AddRect({ x - 2, y1 - 2 }, { x + fw + 2, y2 + 2 }, u32({ C.hp[1], C.hp[2], C.hp[3], a }), h, C.rall, 3);
    end
end

local function pctText(p)
    p = tonumber(p) or 0;
    if p == math.floor(p) then return ('%d%%'):fmt(p); end
    return ('%.1f%%'):fmt(p);
end

-- At 100% the bar becomes the pop timer: it fills as the pop gets closer,
-- the time left is shown beside it, and it pulses bright once the VNM is up.
local function popBar(w, v, h)
    h = h or 6;
    local lh = imgui.GetFrameHeight();
    local x, y = imgui.GetCursorScreenPos();
    imgui.Dummy({ w, lh });
    local left = popLeft(v);
    if left == nil then
        tip('At 100%. No pop time yet: talk to the Venture Seal (or wait for Populox) and the timer starts.');
    elseif left > 0 then
        tip(('Pops in %s (from %s)'):fmt(fmtLeft(left),
            ({ seal = 'the Venture Seal', chat = 'Populox', board = 'the board hitting 100%' })[POPS[v.key].src] or 'VenGo'));
    else
        tip(('Up since %s ago'):fmt(fmtLeft(-left)));
    end
    local dl = imgui.GetWindowDrawList();
    local cy = y + lh / 2;
    local y1, y2 = cy - h / 2, cy + h / 2;
    local t = os.clock();
    dl:AddRectFilled({ x, y1 }, { x + w, y2 }, u32({ 0.20, 0.19, 0.25, 1 }), h / 2);
    local frac = 1;
    if left and left > 0 then frac = math.max(0.02, math.min(1, 1 - left / math.max(POP_DELAY, left))); end
    local fw = w * frac;
    local up = (left ~= nil and left <= 0);
    local c1 = up and { 1, 0.85, 0.40, 1 } or C.hp;
    local c2 = up and NEON2 or C.mp2;
    local ok = pcall(function ()
        dl:AddRectFilledMultiColor({ x, y1 }, { x + fw, y2 }, u32(c1), u32(c2), u32(c2), u32(c1));
    end);
    if not ok then dl:AddRectFilled({ x, y1 }, { x + fw, y2 }, u32(NEON), h / 2); end
    -- the leading edge glows while it counts down; the whole bar pulses once it's up
    if left and left > 0 then
        local a = 0.45 + 0.35 * math.sin(t * 3);
        dl:AddCircleFilled({ x + fw, cy }, h * 0.9, u32({ 1, 1, 1, a }), 12);
    else
        local a = 0.30 + 0.40 * (0.5 + 0.5 * math.sin(t * (up and 6 or 3)));
        dl:AddRect({ x - 2, y1 - 2 }, { x + w + 2, y2 + 2 }, u32({ NEON2[1], NEON2[2], NEON2[3], a }), h, C.rall, 2);
    end
end

-- What goes in the % column: the % until 100, then the pop time
local function progressLabel(v)
    if (v.progress or 0) < 100 then return pctText(v.progress), nil; end
    local left = popLeft(v);
    if left == nil then return '100%', { NEON2[1], NEON2[2], NEON2[3], 1 }; end
    if left > 0 then return fmtLeft(left), { 1, 0.85, 0.45, 1 }; end
    local a = 0.6 + 0.4 * math.sin(os.clock() * 6);
    return 'UP', { 1, 0.9, 0.5, a };
end

local function bar(w, frac, h)
    h = h or 6;
    local lh = imgui.GetFrameHeight();
    local x, y = imgui.GetCursorScreenPos();
    imgui.Dummy({ w, lh });
    local dl = imgui.GetWindowDrawList();
    local cy = y + lh / 2;
    frac = math.max(0, math.min(1, frac or 0));
    dl:AddRectFilled({ x, cy - h / 2 }, { x + w, cy + h / 2 }, u32({ 0.20, 0.19, 0.25, 1 }), h / 2);
    if frac > 0 then
        local ok = pcall(function ()
            dl:AddRectFilledMultiColor({ x, cy - h / 2 }, { x + w * frac, cy + h / 2 },
                u32(C.hp), u32(C.mp2), u32(C.mp2), u32(C.hp));
        end);
        if not ok then dl:AddRectFilled({ x, cy - h / 2 }, { x + w * frac, cy + h / 2 }, u32(NEON), h / 2); end
    end
end

-- Little rounded tags in a row (the HVNM's loot)
-- What the game knows about an item, for the loot tooltips (looked up once)
local JOB_ABBR = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM',
                   'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' };
local ITEMS = {};

local function gameText(t)
    if t == nil then return nil; end
    t = tostring(t);
    local ok, u = pcall(function () return vana.encoding.from_shift_jis(t); end);
    if ok and type(u) == 'string' then t = u; end
    t = t:gsub('[%z\1-\9\11-\31]', ''):gsub('\r', '');
    return t;
end

local function itemInfo(name, meta)
    local key = tostring(name or '');
    if ITEMS[key] ~= nil then return ITEMS[key] or nil; end
    ITEMS[key] = false;
    local info = nil;
    pcall(function ()
        local rm = AshitaCore:GetResourceManager();
        local item = nil;
        if meta and tonumber(meta.id) then item = rm:GetItemById(tonumber(meta.id)); end
        if item == nil then
            local nm = key:gsub("Archers", "Archer's"):gsub("Furys", "Fury's");
            item = rm:GetItemByName(nm, 0) or rm:GetItemByName(key, 0);
        end
        if item == nil then return; end
        local function field(f) local ok, v = pcall(function () return item[f]; end); return ok and v or nil; end
        local nameT = field('Name');
        local descT = field('Description');
        info = {
            name  = gameText(type(nameT) == 'table' and (nameT[1] or nameT[0]) or nameT) or key,
            desc  = gameText(type(descT) == 'table' and (descT[1] or descT[0]) or descT),
            level = tonumber(field('Level')),
            ilvl  = tonumber(field('ItemLevel')),
            jobs  = tonumber(field('Jobs')),
            races = tonumber(field('Races')),
            id    = tonumber(field('Id')),
        };
    end);
    if info then
        if info.jobs and info.jobs > 0 then
            local list = {};
            for j = 1, #JOB_ABBR do
                if bit.band(info.jobs, bit.lshift(1, j)) ~= 0 then list[#list + 1] = JOB_ABBR[j]; end
            end
            info.jobText = (#list >= 22) and 'All jobs' or table.concat(list, ' ');
        end
        ITEMS[key] = info;
    end
    return info;
end

local RARITY = { very_rare = 'Very rare', rare = 'Rare', uncommon = 'Uncommon', common = 'Common', very_common = 'Very common' };

-- The item's icon from the game (loaded once, the way YunaUI does it)
local ICONS = {};
local function itemIcon(id)
    id = tonumber(id);
    if id == nil or id <= 0 then return nil; end
    if ICONS[id] ~= nil then return ICONS[id] or nil; end
    ICONS[id] = false;
    pcall(function ()
        local ffi = require('ffi');
        local d3d = require('d3d8');
        local it = AshitaCore:GetResourceManager():GetItemById(id);
        if it == nil or it.Bitmap == nil or (it.ImageSize or 0) <= 0 then return; end
        local ptr = ffi.new('IDirect3DTexture8*[1]');
        if ffi.C.D3DXCreateTextureFromFileInMemoryEx(d3d.get_device(), it.Bitmap, it.ImageSize, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
                ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED, ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0xFF000000, nil, nil, ptr) == ffi.C.S_OK then
            local t = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
            ICONS[id] = { tex = t, ptr = tonumber(ffi.cast('uint32_t', t)) };
        end
    end);
    return ICONS[id] or nil;
end

-- Races an item fits: "All Races", or the ones it does
local RACE_NAMES = { [1] = 'Hume M', [2] = 'Hume F', [3] = 'Elvaan M', [4] = 'Elvaan F', [5] = 'Tarutaru M',
                     [6] = 'Tarutaru F', [7] = 'Mithra', [8] = 'Galka' };
local function raceText(mask)
    mask = tonumber(mask);
    if mask == nil or mask == 0 then return nil; end
    local list = {};
    for r = 1, 8 do if bit.band(mask, bit.lshift(1, r)) ~= 0 then list[#list + 1] = RACE_NAMES[r]; end end
    if #list == 8 or #list == 0 then return 'All Races'; end
    return table.concat(list, ', ');
end

-- The loot tooltip, in the game-menu style: a dark card with a pink-to-blue
-- bar down its left edge, the icon, the name in mint, races and level under it,
-- then the stats in white and the jobs in lavender
local MINT = { 0.55, 0.95, 0.62, 1 };
local function itemTooltip(name, meta)
    local info = itemInfo(name, meta);
    local id = (meta and tonumber(meta.id)) or (info and info.id);
    local icon = itemIcon(id);
    local pv, pc = 0, 0;
    local function sv(k, v) if k ~= nil then imgui.PushStyleVar(k, v); pv = pv + 1; end end
    local function sc(k, v) if k ~= nil then imgui.PushStyleColor(k, v); pc = pc + 1; end end
    local ok = pcall(function ()
        sv(ImGuiStyleVar_WindowPadding, { 16, 10 });
        sv(ImGuiStyleVar_WindowRounding, 8);
        sv(ImGuiStyleVar_WindowBorderSize, 1);
        sv(ImGuiStyleVar_ItemSpacing, { 8, 3 });
        sc(ImGuiCol_PopupBg, { 0.075, 0.07, 0.095, 0.97 });
        sc(ImGuiCol_Border, { 0.60, 0.50, 0.90, 0.45 });
        imgui.BeginTooltip();
        local dl = imgui.GetWindowDrawList();
        local wx, wy = imgui.GetWindowPos();
        local _, wh = imgui.GetWindowSize();
        -- the bar down the left edge
        pcall(function ()
            dl:AddRectFilledMultiColor({ wx + 5, wy + 7 }, { wx + 8, wy + math.max(wh, 40) - 7 },
                u32({ NEON2[1], NEON2[2], NEON2[3], 1 }), u32({ NEON2[1], NEON2[2], NEON2[3], 1 }), u32({ C.mp2[1], C.mp2[2], C.mp2[3], 1 }), u32({ C.mp2[1], C.mp2[2], C.mp2[3], 1 }));
        end);
        -- icon, then name and races / level beside it
        local isz = 32;
        local ix, iy = imgui.GetCursorScreenPos();
        imgui.Dummy({ isz, isz });
        dl:AddRectFilled({ ix - 2, iy - 2 }, { ix + isz + 2, iy + isz + 2 }, u32({ 0.14, 0.13, 0.18, 1 }), 6);
        if icon then pcall(function () dl:AddImage(icon.ptr, { ix, iy }, { ix + isz, iy + isz }); end); end
        dl:AddRect({ ix - 2, iy - 2 }, { ix + isz + 2, iy + isz + 2 }, u32({ 1, 1, 1, 0.10 }), 6, C.rall, 1);
        imgui.SameLine(0, 10);
        imgui.BeginGroup();
        imgui.TextColored(MINT, (info and info.name) or name);
        local sub = {};
        local races = info and raceText(info.races);
        if races then sub[#sub + 1] = races; end
        if info and info.level and info.level > 0 then sub[#sub + 1] = 'Lv.' .. info.level; end
        if info and info.ilvl and info.ilvl > 0 then sub[#sub + 1] = '<iLv.' .. info.ilvl .. '>'; end
        if #sub > 0 then imgui.TextColored(C.lav, table.concat(sub, '   ')); end
        imgui.EndGroup();
        imgui.Spacing();
        imgui.PushTextWrapPos(imgui.GetCursorPosX() + 300);
        if info and info.desc and info.desc ~= '' then imgui.TextColored({ 0.94, 0.93, 0.97, 1 }, info.desc); end
        if info and info.jobText then imgui.TextColored(C.lav, info.jobText); end
        if not info then imgui.TextColored(C.muted, 'No item details found in the game data.'); end
        local tags = {};
        if meta and meta.rarity then tags[#tags + 1] = RARITY[meta.rarity] or tostring(meta.rarity):gsub('_', ' '); end
        if #tags > 0 then imgui.TextColored(C.gold, table.concat(tags, '  ·  ')); end
        imgui.PopTextWrapPos();
        imgui.EndTooltip();
    end);
    if pc > 0 then imgui.PopStyleColor(pc); end
    if pv > 0 then imgui.PopStyleVar(pv); end
    if not ok then imgui.SetTooltip(tostring(name)); end
end

-- Little rounded tags in a row (the HVNM's loot)
-- What the game knows about an item, for the loot tooltips (looked up once)
local JOB_ABBR = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM',
                   'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' };
local ITEMS = {};

local function gameText(t)
    if t == nil then return nil; end
    t = tostring(t);
    local ok, u = pcall(function () return vana.encoding.from_shift_jis(t); end);
    if ok and type(u) == 'string' then t = u; end
    t = t:gsub('[%z\1-\9\11-\31]', ''):gsub('\r', '');
    return t;
end

local function itemInfo(name, meta)
    local key = tostring(name or '');
    if ITEMS[key] ~= nil then return ITEMS[key] or nil; end
    ITEMS[key] = false;
    local info = nil;
    pcall(function ()
        local rm = AshitaCore:GetResourceManager();
        local item = nil;
        if meta and tonumber(meta.id) then item = rm:GetItemById(tonumber(meta.id)); end
        if item == nil then
            local nm = key:gsub("Archers", "Archer's"):gsub("Furys", "Fury's");
            item = rm:GetItemByName(nm, 0) or rm:GetItemByName(key, 0);
        end
        if item == nil then return; end
        local function field(f) local ok, v = pcall(function () return item[f]; end); return ok and v or nil; end
        local nameT = field('Name');
        local descT = field('Description');
        info = {
            name  = gameText(type(nameT) == 'table' and (nameT[1] or nameT[0]) or nameT) or key,
            desc  = gameText(type(descT) == 'table' and (descT[1] or descT[0]) or descT),
            level = tonumber(field('Level')),
            ilvl  = tonumber(field('ItemLevel')),
            jobs  = tonumber(field('Jobs')),
        };
    end);
    if info then
        if info.jobs and info.jobs > 0 then
            local list = {};
            for j = 1, #JOB_ABBR do
                if bit.band(info.jobs, bit.lshift(1, j)) ~= 0 then list[#list + 1] = JOB_ABBR[j]; end
            end
            info.jobText = (#list >= 22) and 'All jobs' or table.concat(list, ' ');
        end
        ITEMS[key] = info;
    end
    return info;
end

local RARITY = { very_rare = 'Very rare', rare = 'Rare', uncommon = 'Uncommon', common = 'Common', very_common = 'Very common' };

local function itemTooltip(name, meta)
    local info = itemInfo(name, meta);
    local ok = pcall(function ()
        imgui.BeginTooltip();
        imgui.PushTextWrapPos(imgui.GetFontSize() * 24);
        imgui.TextColored({ 1, 1, 1, 1 }, (info and info.name) or name);
        local tags = {};
        if meta and meta.rarity then tags[#tags + 1] = RARITY[meta.rarity] or tostring(meta.rarity):gsub('_', ' '); end
        if meta and meta.type then tags[#tags + 1] = tostring(meta.type):gsub('^%l', string.upper); end
        if #tags > 0 then imgui.TextColored(C.gold, table.concat(tags, '  ·  ')); end
        if info then
            local lv = {};
            if info.level and info.level > 0 then lv[#lv + 1] = 'Lv. ' .. info.level; end
            if info.ilvl and info.ilvl > 0 then lv[#lv + 1] = '<Item Level: ' .. info.ilvl .. '>'; end
            if #lv > 0 then imgui.TextColored(C.lav, table.concat(lv, '   ')); end
            if info.jobText then imgui.TextColored(C.lav, info.jobText); end
            if info.desc and info.desc ~= '' then
                imgui.Spacing();
                imgui.TextColored(C.text, info.desc);
            end
        else
            imgui.TextColored(C.muted, 'No item details found in the game data.');
        end
        imgui.PopTextWrapPos();
        imgui.EndTooltip();
    end);
    if not ok then imgui.SetTooltip(tostring(name)); end
end

-- Little rounded tags in a row (the HVNM's loot); hover one for the item's details
local function pills(list, metaByName)
    local dl = imgui.GetWindowDrawList();
    for i, t in ipairs(list) do
        local tw, th = imgui.CalcTextSize(t);
        local w, h = tw + 22, th + 8;
        local x, y = imgui.GetCursorScreenPos();
        imgui.InvisibleButton('##vengo_loot' .. i, { w, h });
        local hov = imgui.IsItemHovered();
        dl:AddRectFilled({ x, y }, { x + w, y + h }, u32(hov and { 0.20, 0.14, 0.26, 1 } or { 0.13, 0.11, 0.18, 1 }), h / 2);
        dl:AddRect({ x, y }, { x + w, y + h }, u32({ NEON2[1], NEON2[2], NEON2[3], hov and 0.9 or 0.35 }), h / 2, C.rall, 1);
        dl:AddText({ x + 11, y + 4 }, u32({ 0.93, 0.90, 1, 1 }), t);
        if hov then itemTooltip(t, metaByName and metaByName[t] or nil); end
        if i < #list then imgui.SameLine(0, 6); end
    end
end

-- Ventures reset at JST midnight = 15:00 UTC
local function resetCountdown()
    local left = (15 * 3600 - os.time() % 86400) % 86400;
    if SITE.resetAt and SITE.resetAt > os.time() then left = SITE.resetAt - os.time(); end
    return ('%dh %02dm'):fmt(math.floor(left / 3600), math.floor(left % 3600 / 60));
end

local function commaNum(n)
    local r = tostring(n or 0):reverse():gsub('(%d%d%d)', '%1,'):reverse();
    return (r:gsub('^,', ''));
end

local function isActive(v)
    return ARMED ~= nil and ARMED.v == v;
end

local function goButton(v)
    if isActive(v) then
        if button('CANCEL##' .. v.key, { 80, 0 }, true, true) then ARMED = nil; msg('Cancelled.'); end
    elseif TRF.trailShowing(v) then
        if button('STOP##' .. v.key, { 80, 0 }, true, true) then warpTo(v); end
    elseif button('GO##' .. v.key, { 80, 0 }, false, true) then
        warpTo(v);
    end
end

------------------------------------------------------------------------
-- Panel frame and sidebar
------------------------------------------------------------------------
-- A picture from the addon's images folder, as a texture (loaded once)
local IMAGES = {};
local function imageTex(name)
    if IMAGES[name] ~= nil then return IMAGES[name] or nil; end
    IMAGES[name] = false;
    pcall(function ()
        local f = io.open(addon.path .. 'images\\' .. name, 'rb');
        if f == nil then return; end
        local data = f:read('*a');
        f:close();
        local ffi = require('ffi');
        local d3d = require('d3d8');
        local ptr = ffi.new('IDirect3DTexture8*[1]');
        if ffi.C.D3DXCreateTextureFromFileInMemoryEx(d3d.get_device(), data, #data, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
                ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED, ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0, nil, nil, ptr) == ffi.C.S_OK then
            local t = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
            IMAGES[name] = { tex = t, ptr = tonumber(ffi.cast('uint32_t', t)) };
        end
    end);
    return IMAGES[name] or nil;
end

-- The panel, ChadcoreMenu style: a dark violet-grey card with small rounded
-- corners, a thin lavender edge, and a pink-to-violet line across the top
local function frame(dl, x, y, w, h)
    local r = 10;
    x, y, w, h = x + 4, y + 4, w - 8, h - 8;
    local clear = config.transparent;
    dl:AddRectFilled({ x, y }, { x + w, y + h }, u32({ C.panel[1], C.panel[2], C.panel[3], clear and 0.45 or 0.97 }), r);
    dl:AddRect({ x, y }, { x + w, y + h }, u32({ 0.55, 0.46, 0.85, clear and 0.30 or 0.45 }), r, C.rall, 1);
    pcall(function ()
        dl:AddRectFilledMultiColor({ x + 14, y + 8 }, { x + w - 14, y + 10 },
            u32(C.hp), u32(C.mp2), u32(C.mp2), u32(C.hp));
    end);
    -- a faint line between the menu and the page
    dl:AddLine({ x + SW - 8, y + 70 }, { x + SW - 8, y + h - 16 }, u32({ 1, 1, 1, 0.06 }), 1);
end

-- The header: the page's name in small spaced capitals, "VenGo" under it
local function header(dl, x0, y0)
    local tabName = TABS[ui.tab] or 'VENTURES';
    spaced(dl, x0, y0, tabName, u32(C.label), 2.5);
    local lh = imgui.GetTextLineHeight();
    local pushed = pushFont(fonts.title, 22);
    if not pushed then imgui.SetWindowFontScale(1.3); end
    local t = os.clock();
    local word, px = 'VenGo', x0;
    for i = 1, #word do
        local ch = word:sub(i, i);
        local col = C.text;
        if i > 3 then
            local u = 0.5 + 0.5 * math.sin(t * 1.2 - i * 0.45);
            col = { C.hp[1] + (C.mp2[1] - C.hp[1]) * u, C.hp[2] + (C.mp2[2] - C.hp[2]) * u, C.hp[3] + (C.mp2[3] - C.hp[3]) * u, 1 };
        end
        dl:AddText({ px, y0 + lh + 1 }, u32(col), ch);
        px = px + imgui.CalcTextSize(ch);
    end
    local _, th = imgui.CalcTextSize('VenGo');
    if pushed then imgui.PopFont(); else imgui.SetWindowFontScale(1); end
    -- the version, small and grey, beside the name
    local vs = 'v' .. tostring(addon.version or '');
    local _, vh = imgui.CalcTextSize(vs);
    dl:AddText({ px + 8, y0 + lh + 1 + th - vh - 1 }, u32(C.muted), vs);
end

-- The logo's animation:
--   shine: every few seconds a slanted band of light sweeps across it (only on
--          the logo itself: drawn with a white copy of its shape, in thin strips)
--   wind:  purple petals drift across it, swaying, fading in and out
local logoFx;
local SHINE_EVERY, SHINE_TIME = 6.0, 1.3;
local PETALS = {
    { y = 0.18, speed = 0.11, size = 4.5, sway = 0.05, phase = 0.00 },
    { y = 0.42, speed = 0.08, size = 3.5, sway = 0.07, phase = 0.37 },
    { y = 0.63, speed = 0.13, size = 5.0, sway = 0.04, phase = 0.71 },
    { y = 0.30, speed = 0.06, size = 3.0, sway = 0.06, phase = 0.55 },
    { y = 0.80, speed = 0.10, size = 4.0, sway = 0.05, phase = 0.15 },
};

logoFx = function(dl, lx, ly, size)
    local t = os.clock();
    -- shine
    local mask = imageTex('logo_mask.png');
    local ph = (t % SHINE_EVERY) / SHINE_TIME;
    if mask and ph <= 1 then
        local u = ph * ph * (3 - 2 * ph);                             -- (eases in and out)
        local center = lx - size * 0.35 + u * size * 1.7;
        local slant = 0.45;                                           -- (how far the band leans)
        local strip = math.max(3, math.floor(size / 36));
        local bands = { { size * 0.22, 0.10 }, { size * 0.12, 0.16 }, { size * 0.05, 0.22 } };
        for row = ly, ly + size - 1, strip do
            local off = (row - ly - size / 2) * -slant;
            for _, b in ipairs(bands) do
                local x1, x2 = center + off - b[1] / 2, center + off + b[1] / 2;
                if x2 > lx and x1 < lx + size then
                    dl:PushClipRect({ math.max(lx, x1), row }, { math.min(lx + size, x2), row + strip }, true);
                    dl:AddImage(mask.ptr, { lx, ly }, { lx + size, ly + size }, { 0, 0 }, { 1, 1 }, u32({ 1, 1, 1, b[2] }));
                    dl:PopClipRect();
                end
            end
        end
    end
    -- wind: petals
    for i, p in ipairs(PETALS) do
        local k = (t * p.speed + p.phase) % 1;                         -- 0..1 across
        local px = lx - size * 0.1 + k * size * 1.2;
        local py = ly + size * (p.y + p.sway * math.sin(t * 1.7 + i * 1.3) + 0.12 * k);
        local fade = math.min(1, k * 6, (1 - k) * 6);
        local ang = t * (1.5 + i * 0.3) + i;
        local r1, r2 = p.size * size / 180, p.size * size / 420;
        local ca, sa = math.cos(ang), math.sin(ang);
        local function pt(a, b) return { px + a * ca - b * sa, py + a * sa + b * ca }; end
        dl:AddQuadFilled(pt(-r1, 0), pt(0, -r2), pt(r1, 0), pt(0, r2), u32({ 0.72, 0.52, 1.00, 0.75 * fade }));
        dl:AddQuadFilled(pt(-r1 * 0.5, 0), pt(0, -r2 * 0.5), pt(r1 * 0.5, 0), pt(0, r2 * 0.5), u32({ 0.90, 0.80, 1.00, 0.5 * fade }));
    end
end

-- The menu: dots, the chosen one lit pink fading to the right with a bright
-- left edge and a small arrow beside it
local GROUPS = { [7] = true };          -- (a faint line before SETTINGS)

local function sidebar(dl, x0, y0, sw)
    local y = y0;
    local ih = 28;
    local mx, my = imgui.GetMousePos();
    for k, n in ipairs(TABS) do
        if GROUPS[k] then
            dl:AddLine({ x0 + 8, y + 4 }, { x0 + sw - 6, y + 4 }, u32({ 1, 1, 1, 0.06 }), 1);
            y = y + 10;
        end
        local on = (ui.tab == k);
        local over = mx >= x0 and mx < x0 + sw and my >= y and my < y + ih;
        if on then
            pcall(function ()
                dl:AddRectFilledMultiColor({ x0, y }, { x0 + sw, y + ih },
                    u32({ 0.78, 0.25, 0.52, 0.55 }), u32({ 0.78, 0.25, 0.52, 0 }),
                    u32({ 0.78, 0.25, 0.52, 0 }), u32({ 0.78, 0.25, 0.52, 0.55 }));
            end);
            dl:AddRectFilled({ x0, y + 2 }, { x0 + 3, y + ih - 2 }, u32({ NEON2[1], NEON2[2], NEON2[3], 1 }));
            local ax, ay = x0 - 12, y + ih / 2;
            dl:AddTriangleFilled({ ax, ay - 5 }, { ax + 7, ay }, { ax, ay + 5 }, u32({ 0.85, 0.82, 0.95, 1 }));
        elseif over then
            dl:AddRectFilled({ x0, y }, { x0 + sw, y + ih }, u32({ 1, 1, 1, 0.04 }), 4);
        end
        local _, nh = imgui.CalcTextSize(n);
        local label = n:sub(1, 1) .. n:sub(2):lower();
        if not on then dl:AddCircleFilled({ x0 + 10, y + ih / 2 + 1 }, 1.6, u32(C.muted), 8); end
        dl:AddText({ x0 + (on and 14 or 18), y + (ih - nh) / 2 }, u32(on and { 1, 1, 1, 1 } or (over and { 1, 1, 1, 1 } or C.text)), label);
        imgui.SetCursorScreenPos({ x0, y });
        if imgui.InvisibleButton('##vengo_side' .. k, { sw, ih }) then ui.tab = k; end
        y = y + ih + 2;
    end
    local tabsEnd = y;

    -- what VenGo is doing, and when the board last updated, in a dark box under the menu
    local lines = {};
    local st, sv = statusText();
    lines[#lines + 1] = { st, sv and C.active or C.green };
    if sv then lines[#lines + 1] = { sv.zone_name or '', C.lav }; end
    lines[#lines + 1] = { 'LAST UPDATE', C.label, true };
    lines[#lines + 1] = { 'Game  ' .. (liveAge() or 'not yet'), C.text };
    if config.website then lines[#lines + 1] = { 'Website  ' .. (siteAge() or 'not yet'), C.text }; end
    local lh = imgui.GetTextLineHeight();
    local bh = 30 + #lines * (lh + 3) + 4;
    local sy = tabsEnd + 18;
    local logoTop = tabsEnd + 12;
    if sy + bh < y0 + WIN_H - 34 - 40 then
        logoTop = sy + bh + 14;
        dl:AddRectFilled({ x0 - 4, sy }, { x0 + sw, sy + bh }, u32({ C.well[1], C.well[2], C.well[3], 0.95 }), 8);
        spaced(dl, x0 + 6, sy + 8, 'STATUS', u32(C.label), 2);
        local ly = sy + 28;
        for _, ln in ipairs(lines) do
            if ln[3] then
                ly = ly + 4;
                spaced(dl, x0 + 6, ly, ln[1], u32(ln[2]), 2);
            else
                local text = ln[1];
                while #text > 4 and imgui.CalcTextSize(text) > sw - 12 do text = text:sub(1, -2); end
                dl:AddText({ x0 + 6, ly }, u32(ln[2]), text);
            end
            ly = ly + lh + 3;
        end
    end

    -- the logo, bottom left, as big as the room allows
    local bottom = y0 + WIN_H - 86 - 14;
    local size = math.min(sw + 4, bottom - logoTop);
    if size >= 60 then
        local tex = imageTex('logo.png');
        if tex then
            local lx = x0 - 4 + (sw + 4 - size) / 2;
            pcall(function () dl:AddImage(tex.ptr, { lx, bottom - size }, { lx + size, bottom }); end);
            if config.logo_anim then pcall(logoFx, dl, lx, bottom - size, size); end
        end
    end
end

-- A round icon button at the top right: draws(cx, cy, r, col) draws its mark
local function iconButton(dl, id, bx, by, bs, hoverCol, tipText, draws)
    imgui.SetCursorScreenPos({ bx, by });
    local clicked = imgui.InvisibleButton(id, { bs, bs });
    local hov = imgui.IsItemHovered();
    if hov then
        dl:AddRectFilled({ bx, by }, { bx + bs, by + bs }, u32(hoverCol), bs / 2);
        imgui.SetTooltip(tipText);
    end
    draws(bx + bs / 2, by + bs / 2, bs * 0.22, u32(hov and { 1, 1, 1, 1 } or { 0.80, 0.78, 0.90, 0.9 }));
    return clicked;
end

local function topButtons(dl, wx, wy, ww)
    local bs, by = 22, wy + 16;
    local xClose = wx + ww - 24 - bs;
    local xMin   = xClose - bs - 8;
    local xClear = xMin - bs - 8;
    -- see-through on / off
    if iconButton(dl, '##vengo_clear', xClear, by, bs, { C.acc[1], C.acc[2], C.acc[3], 0.22 },
            config.transparent and 'Solid window' or 'See-through window', function (cx, cy, r, col)
                dl:AddCircle({ cx, cy }, r * 1.25, col, 20, 1.4);
                if not config.transparent then dl:AddCircleFilled({ cx, cy }, r * 0.7, col, 20); end
            end) then
        config.transparent = not config.transparent;
        saveSettings();
    end
    -- minimise
    if iconButton(dl, '##vengo_min', xMin, by, bs, { C.acc[1], C.acc[2], C.acc[3], 0.22 },
            'Minimise (click the VenGo tag to open it again)', function (cx, cy, r, col)
                dl:AddLine({ cx - r, cy + r * 0.6 }, { cx + r, cy + r * 0.6 }, col, 1.8);
            end) then
        config.minimized = true;
        saveSettings();
    end
    -- close
    if iconButton(dl, '##vengo_x', xClose, by, bs, { C.hp[1], C.hp[2], C.hp[3], 0.30 },
            'Close (type /vengo to open it again)', function (cx, cy, r, col)
                dl:AddLine({ cx - r, cy - r }, { cx + r, cy + r }, col, 1.6);
                dl:AddLine({ cx - r, cy + r }, { cx + r, cy - r }, col, 1.6);
            end) then
        ui.open[1] = false;
    end
end

------------------------------------------------------------------------
-- Tabs
------------------------------------------------------------------------
-- A venture row. Every column is measured from what's in it (all rows at once),
-- so long zone names can't run into the NM names.
local GAP = 18;

local function rowTier(v, showPool)
    local t = ('T%s  %s'):fmt(tostring(v.tier or '?'), v.levels or '');
    if showPool and v.pool then t = v.pool .. '  ' .. t; end
    return t;
end

local function measureCols(list, showPool)
    local w = { go = 80, tier = 0, zone = 0, nm = 0, grid = 0, bar = 78, pct = math.max(imgui.CalcTextSize('100%'), imgui.CalcTextSize('10:00')) };
    for _, v in ipairs(list) do
        w.tier = math.max(w.tier, imgui.CalcTextSize(rowTier(v, showPool)));
        w.zone = math.max(w.zone, imgui.CalcTextSize(v.zone_name or ''));
        w.nm   = math.max(w.nm,   imgui.CalcTextSize(v.nm or ''));
        w.grid = math.max(w.grid, imgui.CalcTextSize(v.grid or ''));
    end
    local x, at = 0, {};
    for _, k in ipairs({ 'go', 'tier', 'zone', 'nm', 'grid', 'bar', 'pct', 'drops' }) do
        at[k] = x;
        x = x + (w[k] or 0) + GAP;
    end
    return at;
end

local function vnmTip(v)
    local lines = {};
    if v.notes and v.notes ~= '' then lines[#lines + 1] = v.notes; end
    if v.element and v.element ~= '' then lines[#lines + 1] = 'Element: ' .. v.element; end
    if v.crest and v.crest ~= '' then lines[#lines + 1] = 'Crest: ' .. v.crest; end
    if v.drops and v.drops ~= '' then lines[#lines + 1] = 'Drops: ' .. v.drops; end
    if v.mobs and #v.mobs > 0 then
        lines[#lines + 1] = 'Mobs:';
        for i, m in ipairs(v.mobs) do
            if i > 10 then lines[#lines + 1] = ('  ...and %d more'):fmt(#v.mobs - 10); break; end
            lines[#lines + 1] = '  ' .. m;
        end
    end
    if #lines > 0 then tip(table.concat(lines, '\n')); end
end

local function warpTip(v)
    if not imgui.IsItemHovered() then return; end
    if WARPS == nil then imgui.SetTooltip('Warps with Uberwarp (not found yet)'); return; end
    local o = warpOptions(v);
    local lines = { 'Warp to ' .. (v.zone_name or '?') .. ':' };
    for _, sys in ipairs(SYSTEMS) do
        for k, w in ipairs(o[sys]) do
            if k > 3 then break; end
            lines[#lines + 1] = ('  %s  %s%s'):fmt(SYS_NAME[sys], w.alias,
                w.dist and ('  (%d yalms)'):fmt(math.floor(w.dist + 0.5)) or (w.via and '  (closest way in)' or ''));
        end
    end
    if #lines == 1 then lines[2] = '  No Home Point, Survival Guide or Unity warp goes there'; end
    imgui.SetTooltip(table.concat(lines, '\n'));
end

local function ventureRow(v, z, at, showPool)
    local x0 = imgui.GetCursorPosX();
    do                                                               -- the hover highlight, drawn first
        local sx, sy = imgui.GetCursorScreenPos();
        local rh = imgui.GetFrameHeight();
        local mx, my = imgui.GetMousePos();
        if mx >= sx and mx < sx + ROW_W and my >= sy and my < sy + rh then
            local dl = imgui.GetWindowDrawList();
            pcall(function ()
                dl:AddRectFilledMultiColor({ sx - 6, sy }, { sx + ROW_W, sy + rh },
                    u32({ 0.78, 0.25, 0.52, 0.35 }), u32({ 0.78, 0.25, 0.52, 0 }),
                    u32({ 0.78, 0.25, 0.52, 0 }), u32({ 0.78, 0.25, 0.52, 0.35 }));
            end);
            dl:AddRectFilled({ sx - 6, sy + 2 }, { sx - 3, sy + rh - 2 }, u32({ NEON2[1], NEON2[2], NEON2[3], 1 }));
        end
    end
    goButton(v);
    warpTip(v);
    imgui.SameLine(x0 + at.tier);
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.muted, rowTier(v, showPool));
    imgui.SameLine(x0 + at.zone);
    local zc = isActive(v) and C.active or (v.zone == z and C.here or C.text);
    if ALERT and ALERT.v == v then zc = { NEON2[1], NEON2[2], NEON2[3], 1 }; end
    imgui.TextColored(zc, v.zone_name or '?');
    imgui.SameLine(x0 + at.nm);
    imgui.TextColored(C.acc, v.nm or '?');
    vnmTip(v);
    imgui.SameLine(x0 + at.grid);
    imgui.TextColored(C.lav, v.grid or '');
    imgui.SameLine(x0 + at.bar);
    if (v.progress or 0) >= 100 then popBar(78, v); else trendBar(78, (v.progress or 0) / 100, trendOf(v)); end
    imgui.SameLine(x0 + at.pct);
    local full = (v.progress or 0) >= 100;
    local plab, pcol = progressLabel(v);
    imgui.TextColored(pcol or C.text, plab);
    if v.drops and v.drops ~= '' then
        imgui.SameLine(x0 + at.drops);
        imgui.TextColored(C.seal, v.drops);
        vnmTip(v);
    end
end

-- A row of rounded choice pills; returns the picked value when one is clicked
local function pillChoice(id, opts, cur)
    local picked = nil;
    local dl = imgui.GetWindowDrawList();
    for i, o in ipairs(opts) do
        local label = o[2];
        local tw, th = imgui.CalcTextSize(label);
        local w, h = tw + 28, th + 12;
        local x, y = imgui.GetCursorScreenPos();
        if imgui.InvisibleButton(id .. i, { w, h }) then picked = o[1]; end
        local on, hov = (o[1] == cur), imgui.IsItemHovered();
        if on then
            dl:AddRectFilled({ x, y }, { x + w, y + h }, u32({ NEON2[1] * 0.40, NEON2[2] * 0.31, NEON2[3] * 0.42, 0.85 }), 6);
            dl:AddRect({ x, y }, { x + w, y + h }, u32({ NEON2[1], NEON2[2], NEON2[3], 0.95 }), 6, C.rall, 1.3);
        else
            dl:AddRectFilled({ x, y }, { x + w, y + h }, u32(hov and { 0.16, 0.15, 0.21, 1 } or { 0.12, 0.11, 0.155, 1 }), 6);
            dl:AddRect({ x, y }, { x + w, y + h }, u32({ 1, 1, 1, hov and 0.22 or 0.10 }), 6, C.rall, 1);
        end
        dl:AddText({ x + 14, y + 6 }, u32(on and { 1, 1, 1, 1 } or C.text), label);
        if i < #opts then imgui.SameLine(0, 6); end
    end
    return picked;
end

local function sortedList()
    local list = {};
    for _, v in ipairs(vdata.exp or {}) do
        local pool = v.pool or (((v.key or ''):lower():match('^b')) and 'B' or 'A');
        v.pool = pool;
        if config.pool == 'all' or config.pool == pool then list[#list + 1] = v; end
    end
    table.sort(list, function (a, b)
        if config.sort == 'pct' then
            local pa, pb = a.progress or 0, b.progress or 0;
            if pa ~= pb then return pa > pb; end
        end
        if (a.tier or 0) ~= (b.tier or 0) then return (a.tier or 0) < (b.tier or 0); end
        return (a.pool or '') < (b.pool or '');
    end);
    return list;
end

local function tabVentures(z)
    -- the one-click GO: the 100% venture, or the one in your zone
    local pick = pickCurrent();
    local bigPushed = pushFont(fonts.big, 24);
    if ARMED then
        if button('CANCEL##vengo_big', { 260, 52 }, true) then ARMED = nil; msg('Cancelled.'); end
    elseif pick and TRF.trailShowing(pick) then
        if button('STOP##vengo_big', { 260, 52 }, true) then warpTo(pick); end
    elseif pick then
        if button('GO##vengo_big', { 260, 52 }) then warpTo(pick); end
    else
        button('NO VENTURES##vengo_big', { 260, 52 }, true);
    end
    if bigPushed then imgui.PopFont(); end
    if pick then warpTip(pick); end

    imgui.SameLine(0, 20);
    imgui.BeginGroup();
    if ARMED then
        imgui.TextColored(C.muted, 'Walk up to a warp NPC for');
        imgui.TextColored(C.acc, ARMED.v.nm or '?');
        imgui.TextColored(C.text, ARMED.v.zone_name or '?');
    elseif pick and zone() == pick.zone then
        imgui.TextColored(C.muted, TRF.trailShowing(pick) and 'STOP hides the arrows to' or 'GO shows the arrows to');
        imgui.TextColored(C.acc, pick.nm or '?');
        imgui.TextColored(C.text, ('%s  (%s)  %s'):fmt(pick.zone_name or '?', pick.grid or '?', pctText(pick.progress)));
    elseif pick then
        imgui.TextColored(C.muted, 'GO warps you toward');
        imgui.TextColored(C.acc, pick.nm or '?');
        imgui.TextColored(C.text, ('%s  (%s)  %s'):fmt(pick.zone_name or '?', pick.grid or '?', pctText(pick.progress)));
    end
    imgui.EndGroup();

    if ALERT then
        imgui.TextColored({ NEON2[1], NEON2[2], NEON2[3], 1 }, ('VNM INCOMING:  %s, %s (%s)  -  %s'):fmt(
            ALERT.v.nm, ALERT.v.zone_name, ALERT.v.grid or '?', popWords(ALERT.pop_at - os.time())));
        if dropsOf(ALERT.v) ~= '' then
            imgui.SameLine(0, 14);
            imgui.TextColored(C.seal, 'Drops: ' .. dropsOf(ALERT.v));
        end
    end
    if LASTWARP and os.time() - LASTWARP.at < 90 and LASTWARP.list[LASTWARP.i + 1] then
        if button('NOT UNLOCKED? TRY NEXT CLOSEST##vengo_next', { 0, 0 }, false, true) then warpNext(); end
    end

    if #ventures == 0 then
        section('Ventures');
        hint('No ventures loaded. Check ventures.lua, then RELOAD in Settings.');
        return;
    end

    local h = vdata.hvnm;
    if h then
        section('Higher Venture NM');
        local x0 = imgui.GetCursorPosX();
        goButton(h);
        warpTip(h);
        imgui.SameLine(x0 + 96);
        imgui.AlignTextToFramePadding();
        imgui.TextColored(isActive(h) and C.active or (h.zone == z and C.here or C.acc), h.nm or '?');
        vnmTip(h);
        imgui.SameLine(0, GAP);
        imgui.TextColored(C.text, ('%s  (%s)'):fmt(h.zone_name or '?', h.grid or '?'));
        local facts = {};
        if h.level then facts[#facts + 1] = 'Level ' .. tostring(h.level); end
        if h.hp then facts[#facts + 1] = 'HP ' .. commaNum(h.hp); end
        if h.next_up then facts[#facts + 1] = 'Next up  ' .. h.next_up; end
        if #facts > 0 then imgui.TextColored(C.muted, table.concat(facts, '      ')); end
        if (h.progress or 0) >= 100 then popBar(math.max(200, ROW_W - 80), h, 8);
        else trendBar(math.max(200, ROW_W - 80), (h.progress or 0) / 100, trendOf(h), 8); end
        imgui.SameLine();
        local hlab, hcol = progressLabel(h);
        imgui.TextColored(hcol or C.text, hlab);
        if h.loot and #h.loot > 0 then pills(h.loot, h.lootItems); end
    end

    section('EXP Ventures');
    local p = pillChoice('##vengo_pool', { { 'all', 'ALL POOLS' }, { 'A', 'POOL A' }, { 'B', 'POOL B' } }, config.pool);
    if p then config.pool = p; saveSettings(); end
    imgui.SameLine(0, 24);
    local so = pillChoice('##vengo_sort', { { 'pct', 'SORT  %' }, { 'tier', 'SORT  TIER' } }, config.sort);
    if so then config.sort = so; saveSettings(); end
    imgui.SameLine(0, 24);
    local md = pillChoice('##vengo_mode', { { 'ACE', 'ACE' }, { 'CW', 'CW' } }, config.mode);
    if md then config.mode = md; saveSettings(); applyLive(false); applySite(false); end

    local srcs = {};
    if LIVE then srcs[#srcs + 1] = 'game board ' .. (liveAge() or '?'); end
    if SITE.at then srcs[#srcs + 1] = 'catseyexi.com ' .. (siteAge() or '?'); end
    if #srcs > 0 then
        imgui.TextColored(C.muted, 'Live. Updated: ' .. table.concat(srcs, ',  '));
    else
        imgui.TextColored(C.muted, 'From ventures.lua until the game or the website sends the board.');
    end
    imgui.SameLine(0, 14);
    if button('REFRESH##vengo_refresh', { 0, 0 }, true, true) then
        if config.website then SITE.nextAt = 0; end
        refreshBoard();
    end
    tip('Updates from catseyexi.com now, and asks the game server for the board (the same as typing !ventures)');
    imgui.Spacing();
    local list = sortedList();
    local showPool = (config.pool == 'all');
    local at = measureCols(list, showPool);
    for _, v in ipairs(list) do ventureRow(v, z, at, showPool); end
end

-- Rows of text in columns, each as wide as its widest cell. The last column
-- word-wraps inside the window (and drops under the row when there's no room).
local function infoRows(rows)
    local w = {};
    for _, r in ipairs(rows) do
        for c = 1, #r - 1 do w[c] = math.max(w[c] or 0, imgui.CalcTextSize(tostring(r[c] or ''))); end
    end
    for i, r in ipairs(rows) do
        local x0, x = imgui.GetCursorPosX(), 0;
        local wrapped = false;
        for c, cell in ipairs(r) do
            local last = (c == #r);
            local col = (c == 1) and C.acc or (last and C.muted or C.text);
            if last and c > 1 then
                local room = ROW_W - x;
                if room < 160 then                                   -- (too narrow: put it on its own line, indented)
                    imgui.SetCursorPosX(x0 + 18);
                    room = ROW_W - 18;
                else
                    imgui.SameLine(x0 + x);
                end
                local cx = imgui.GetCursorPosX();
                imgui.PushTextWrapPos(cx + room);
                imgui.TextColored(col, tostring(cell or ''));
                imgui.PopTextWrapPos();
                wrapped = imgui.CalcTextSize(tostring(cell or '')) > room;
            else
                if c > 1 then imgui.SameLine(x0 + x); end
                imgui.TextColored(col, tostring(cell or ''));
                x = x + (w[c] or 0) + GAP;
            end
        end
        if wrapped and i < #rows then imgui.Spacing(); end
    end
end

local function sourceHint(siteRows)
    if siteRows then hint('From catseyexi.com, updated ' .. (siteAge() or '?') .. '.');
    else hint('From ventures.lua (turn on website updates in Settings for the current list).'); end
end

local function tabHelm()
    section('HELM Ventures');
    local rows = vdata.helm_rows;
    if rows == nil then
        rows = {};
        for _, h in ipairs(vdata.helm or {}) do rows[#rows + 1] = { h.kind, h.zones }; end
    end
    sourceHint(vdata.helm_rows ~= nil);
    if #rows == 0 then hint('None listed.'); end
    infoRows(rows);
end

local function tabFishing()
    section('Fishing Ventures');
    local rows = vdata.fishing_rows;
    if rows == nil then
        rows = {};
        for _, f in ipairs(vdata.fishing or {}) do
            rows[#rows + 1] = { ('Tier %d'):fmt(f.tier), f.levels or '', f.fish, 'x' .. tostring(f.count) };
        end
    end
    sourceHint(vdata.fishing_rows ~= nil);
    if #rows == 0 then hint('None listed.'); end
    infoRows(rows);
end

local function tabDynamis()
    section('Dynamis Ventures');
    local rows = vdata.dynamis_rows;
    if rows == nil then
        rows = {};
        for _, d in ipairs(vdata.dynamis or {}) do rows[#rows + 1] = { d.kind, d.zone }; end
    end
    sourceHint(vdata.dynamis_rows ~= nil);
    if #rows == 0 then hint('None listed.'); end
    infoRows(rows);
end

local THANKS = {
    { 'Vekkien', 'the VanaCore project, the client VenGo runs in' },
    { 'Yunas', 'YunaUI: the look of VenGo, and how it starts up in VanaCore' },
    { 'Commandobill, Seekey and Phatty', 'the ventures addon: the live venture board and the VNM list (drops, grid squares, notes)' },
    { 'Thorny', 'Uberwarp: the warps behind GO' },
    { 'GUST', 'the TeX Gyre Adventor font' },
};

local function tabThanks()
    section('Special Thanks');
    hint('VenGo is built on the work of these people. Thank you!');
    imgui.Spacing();
    for _, t in ipairs(THANKS) do
        imgui.TextColored({ NEON2[1], NEON2[2], NEON2[3], 1 }, t[1]);
        imgui.Indent(18);
        imgui.PushTextWrapPos(imgui.GetCursorPosX() + ROW_W - 18);
        imgui.TextColored(C.text, t[2]);
        imgui.PopTextWrapPos();
        imgui.Unindent(18);
        imgui.Spacing();
    end
end

------------------------------------------------------------------------
-- The trail: glowing chevrons crawling along the ground from your feet to the
-- VNM's grid square, and a marker at the end.
-- The game's own camera (its view and projection, asked from the Direct3D
-- device while the world is being drawn) puts the path on the ground.
-- It's a straight line: it doesn't know walls, so in a dungeon it points
-- the way rather than the route.
------------------------------------------------------------------------
local TRAIL, trailTick, drawTrail, trailSettings;
do
local TRAIL_LEN  = 90;         -- yalms of path drawn ahead of you
local TRAIL_NEAR = 5;          -- yalms from the square's middle: the trail is done

TRAIL = { pick = nil, v = nil, cam = 'not read yet', order = nil, up = nil, last = 0 };

local TRAIL_COLORS = {
    { 'pink',   { 1.00, 0.42, 0.72 } }, { 'violet', { 0.70, 0.45, 1.00 } }, { 'blue',  { 0.45, 0.70, 1.00 } },
    { 'cyan',   { 0.40, 0.95, 0.95 } }, { 'green',  { 0.48, 0.92, 0.58 } }, { 'gold',  { 0.96, 0.76, 0.32 } },
    { 'orange', { 1.00, 0.55, 0.30 } }, { 'white',  { 0.95, 0.95, 1.00 } }, { 'neon', { 0.25, 0.65, 1.00 } },
};
local function trailColor()
    for _, c in ipairs(TRAIL_COLORS) do if c[1] == config.trail_color then return c[2]; end end
    return TRAIL_COLORS[1][2];
end

-- The camera, read from the Direct3D device: view (2) and projection (3)
local ffi_ = require('ffi');
pcall(ffi_.cdef, [[
typedef struct { float m[16]; } VG_MAT;
typedef int32_t (__stdcall *VG_GetTransform)(void* self, uint32_t state, VG_MAT* out);
]]);
local CAM = { view = nil, proj = nil, cands = {}, tries = 0, on = false, frame = 0, me = nil };
-- (CAM.on: look at the game's draws this frame at all. It's off unless arrows are wanted, and it switches itself
--  off the moment the world's camera has been seen, so most of the game's draws cost one check.)

-- The device and its GetTransform, found once
function CAM.init()
    local ok = pcall(function ()
        local dev = require('d3d8').get_device();
        if dev == nil then return; end
        local p = ffi_.cast('void*', dev);
        local vt = ffi_.cast('void**', ffi_.cast('void**', p)[0]);
        CAM.dev, CAM.get = p, ffi_.cast('VG_GetTransform', vt[38]);      -- IDirect3DDevice8::GetTransform
        CAM.mv, CAM.mp = ffi_.new('VG_MAT'), ffi_.new('VG_MAT');
    end);
    if not ok or CAM.get == nil then TRAIL.cam = 'no Direct3D device'; CAM.dead = true; end
end

local function toTable(m)
    local out = {};
    for i = 0, 15 do
        local v = m.m[i];
        if v ~= v or v > 1e9 or v < -1e9 then return nil; end  -- (not a number)
        out[i + 1] = v;
    end
    return out;
end

-- Is it a 3D camera (perspective), not the interface's flat one?
local function perspective(pm)
    return pm and math.abs(pm[16]) < 0.001 and math.abs(math.abs(pm[12]) - 1) < 0.01;
end

-- Where a view matrix's camera stands in the world
local function camPos(v)
    local t1, t2, t3 = v[13], v[14], v[15];
    return -(t1 * v[1] + t2 * v[2] + t3 * v[3]), -(t1 * v[5] + t2 * v[6] + t3 * v[7]), -(t1 * v[9] + t2 * v[10] + t3 * v[11]);
end

-- Called for the game's draws: every different 3D camera of the frame is kept (the sky's, the world's, the
-- equipment preview's...); the one standing a few yalms from you is picked when drawing
local function camSampleInner()
    if CAM.get == nil then CAM.init(); if CAM.get == nil then CAM.on = false; return; end end
    local mv = CAM.mv;
    if CAM.get(CAM.dev, 2, mv) ~= 0 then return; end
    local m = mv.m;
    for _, c in ipairs(CAM.cands) do                         -- (the same camera as one already kept: nothing to do)
        local v = c.view;
        if math.abs(v[13] - m[12]) < 0.01 and math.abs(v[14] - m[13]) < 0.01 and math.abs(v[15] - m[14]) < 0.01
            and math.abs(v[1] - m[0]) < 0.001 then return; end
    end
    if CAM.get(CAM.dev, 3, CAM.mp) ~= 0 then return; end
    local pm = toTable(CAM.mp);
    if not perspective(pm) then return; end
    local vm = toTable(mv);
    if vm == nil then return; end
    CAM.cands[#CAM.cands + 1] = { view = vm, proj = pm };
    local me = CAM.me;                                       -- (the world's camera: a few yalms from you, looking at you. Done for this frame.)
    if me then
        local cx, cy, cz = camPos(vm);
        if (cx - me[1]) ^ 2 + (cy - me[2]) ^ 2 + (cz - me[3]) ^ 2 < 3600 then
            local x, y, z = me[1], me[2], me[3];
            local vx = x * vm[1] + y * vm[5] + z * vm[9]  + vm[13];
            local vy = x * vm[2] + y * vm[6] + z * vm[10] + vm[14];
            local vz = x * vm[3] + y * vm[7] + z * vm[11] + vm[15];
            local cxp = vx * pm[1] + vy * pm[5] + vz * pm[9]  + pm[13];
            local cyp = vx * pm[2] + vy * pm[6] + vz * pm[10] + pm[14];
            local cw  = vx * pm[4] + vy * pm[8] + vz * pm[12] + pm[16];
            if cw > 0.05 and math.abs(cxp / cw) < 0.8 and math.abs(cyp / cw) < 0.9 then CAM.on = false; end
        end
    end
    if #CAM.cands >= 8 then CAM.on = false; end
end
local function camSample()
    if not CAM.on then return; end
    CAM.tries = CAM.tries + 1;
    if CAM.tries > CAM.max then CAM.on = false; return; end
    if not pcall(camSampleInner) then TRAIL.cam = 'could not be read'; CAM.on = false; end
end

-- World (x, y, z, D3D order) -> screen x, y and depth (nil if behind the camera)
local function projectWith(v, p, x, y, z)
    local vx = x * v[1] + y * v[5] + z * v[9]  + v[13];
    local vy = x * v[2] + y * v[6] + z * v[10] + v[14];
    local vz = x * v[3] + y * v[7] + z * v[11] + v[15];
    local cx = vx * p[1] + vy * p[5] + vz * p[9]  + p[13];
    local cy = vx * p[2] + vy * p[6] + vz * p[10] + p[14];
    local cw = vx * p[4] + vy * p[8] + vz * p[12] + p[16];
    if cw <= 0.05 then return nil; end
    local ds = imgui.GetIO().DisplaySize;
    local W, H = (ds and ds.x) or 1920, (ds and ds.y) or 1080;
    return (cx / cw * 0.5 + 0.5) * W, (0.5 - cy / cw * 0.5) * H, cw;
end
local function project(x, y, z)
    if CAM.view == nil then return nil; end
    return projectWith(CAM.view, CAM.proj, x, y, z);
end

-- The game keeps your position as (east, north, height); the world is drawn as (east, height, north)
local function toD3D(hx, hy, hz)
    if TRAIL.order == 2 then return hx, hy, hz; end
    return hx, hz, hy;
end

-- Pick the world's camera: the one standing 1-60 yalms from you, looking at you
local function calibrate(px, py, ph)
    local ds = imgui.GetIO().DisplaySize;
    local W, H = (ds and ds.x) or 1920, (ds and ds.y) or 1080;
    local best = nil;
    for _, c in ipairs(CAM.cands) do
        local cx, cy, cz = camPos(c.view);
        for _, ord in ipairs({ 1, 2 }) do
            local x, y, z;
            if ord == 1 then x, y, z = px, ph, py; else x, y, z = px, py, ph; end
            local d = math.sqrt((cx - x) ^ 2 + (cy - y) ^ 2 + (cz - z) ^ 2);
            local sx, sy = projectWith(c.view, c.proj, x, y, z);
            if d > 0.5 and d < 60 and sx and sx > 0 and sx < W and sy > 0 and sy < H then
                local off = math.sqrt((sx - W / 2) ^ 2 + (sy - H / 2) ^ 2) / W + d / 200;
                if best == nil or off < best.off then
                    best = { off = off, c = c, ord = ord, d = d, cam = { cx, cy, cz }, me = { x, y, z } };
                end
            end
        end
    end
    if best == nil then return false; end
    CAM.view, CAM.proj = best.c.view, best.c.proj;
    CAM.me = best.me;
    TRAIL.order = best.ord;
    -- up: the camera is above you
    local vert = (best.ord == 1) and 2 or 3;
    TRAIL.up = (best.cam[vert] > best.me[vert]) and 1 or -1;
    TRAIL.cam = ('found (%d cameras this frame, %.0f yalms behind you)'):format(#CAM.cands, best.d);
    return true;
end

-- The point 'h' yalms above a ground spot
local function above(hx, hy, hz, h)
    local x, y, z = toD3D(hx, hy, hz);
    local u = (TRAIL.up or -1) * h;
    if TRAIL.order == 2 then return x, y, z + u; end
    return x, y + u, z;
end

-- Which venture to guide to: the one you pressed GO for, else the one in this zone
-- The Venture Seal: an NPC the game loads once you're within about 50 yalms. Its spot is remembered per zone
-- (seal_spots.lua), so the trail heads straight for it next time too.
local SL = { spots = nil, at = 0, zone = nil, x = nil };    -- spots[zone] = { x, y, h }; the rest: the last look
function SL.file() return addon.path .. 'seal_spots.lua'; end
function SL.load()
    local SEALS = {};
    SL.spots = SEALS;
    local t_ = loadTable(SL.file());
    if type(t_) == 'table' then for k, s in pairs(t_) do if type(s) == 'table' and s.x then SEALS[tonumber(k)] = s; end end end
end
function SL.save()
    local f = io.open(SL.file(), 'w');
    if f == nil then return; end
    f:write('-- Where VenGo saw each zone\'s Venture Seal (rewritten by VenGo)\nreturn {\n');
    for z, s in pairs(SL.spots) do f:write(('  [%d] = { x = %.2f, y = %.2f, h = %.2f },\n'):format(z, s.x, s.y, s.h or 0)); end
    f:write('}\n');
    f:close();
end
function SL.find(z)
    if SL.spots == nil then SL.load(); end
    local SEALS, SEAL_SCAN = SL.spots, SL;
    local now = os.clock();
    if SEAL_SCAN.zone ~= z then SEAL_SCAN.zone, SEAL_SCAN.x, SEAL_SCAN.idx, SEAL_SCAN.full = z, nil, nil, 0; SEAL_SCAN.at = 0; end
    if now - SEAL_SCAN.at > (tonumber(config.seal_check) or 0.25) then
        SEAL_SCAN.at = now;
        -- (where it was last time: just that slot; otherwise the whole list, every 2 s, or 4 s in Lightweight)
        if SL.idx and SEAL_SCAN.x then
            local ok_ = false;
            pcall(function ()
                local nm = mm():GetEntity():GetName(SL.idx);
                if nm and nm:lower() == 'venture seal' then
                    local ex, ey, eh = entPos(SL.idx);
                    if ex then SEAL_SCAN.x, SEAL_SCAN.y, SEAL_SCAN.h = ex, ey, eh; ok_ = true; end
                end
            end);
            if ok_ then return SEAL_SCAN.x, SEAL_SCAN.y, SEAL_SCAN.h, true; end
        end
        if now - (SEAL_SCAN.full or 0) < (tonumber(config.seal_scan) or 0.5) then
            SEAL_SCAN.x = nil;
            local s0 = SEALS[z];
            if s0 then return s0.x, s0.y, s0.h, false; end
            return nil;
        end
        SEAL_SCAN.full = now;
        SEAL_SCAN.x = nil;
        pcall(function ()
            local ent = mm():GetEntity();
            -- (the Seal is spawned by the server, so it can sit anywhere in the list: e.g. 1832, past the zone's own NPCs;
            --  the last slot it was in is looked at first)
            local function isSeal(i)
                local nm = ent:GetName(i);
                return nm and nm ~= '' and nm:lower() == 'venture seal';
            end
            local order = {};
            if SL.idx then order[1] = SL.idx; end
            for i = 1, MAX_ENTITY_IDX do if i ~= SL.idx then order[#order + 1] = i; end end
            for _, i in ipairs(order) do
                if isSeal(i) then
                    SL.idx = i;
                    local ex, ey, eh = entPos(i);
                    if ex then
                        SEAL_SCAN.x, SEAL_SCAN.y, SEAL_SCAN.h = ex, ey, eh;
                        local old = SEALS[z];
                        if old == nil or dist2d(old.x, old.y, ex, ey) > 1 then
                            SEALS[z] = { x = ex, y = ey, h = eh };
                            SL.save();
                        end
                        break;
                    end
                end
            end
        end);
    end
    if SEAL_SCAN.x then return SEAL_SCAN.x, SEAL_SCAN.y, SEAL_SCAN.h, true; end
    local s = SEALS[z];
    if s then return s.x, s.y, s.h, false; end
    return nil;
end

-- Which venture to guide to: the one you pressed GO for, else the one in this zone.
-- Where: the Venture Seal if it's loaded or remembered, else the middle of the VNM's grid square.
local function trailTarget()
    local z = zone();
    if TRAIL.zone_ ~= z then TRAIL.zone_, TRAIL.stopped, TRAIL.forced = z, nil, nil; end   -- (a new zone: GO / STOP start fresh)
    local v = TRAIL.pick;
    if v and v.zone ~= z then v = nil; end
    if v == nil then
        local best = nil;
        for _, c in ipairs(ventures) do
            if c.zone == z and c.grid and (best == nil or (c.progress or 0) > (best.progress or 0)) then best = c; end
        end
        v = best;
    end
    if v == nil or TRAIL.stopped == v.key then return nil; end
    local gx, gy = gridToWorld(v.zone, v.grid, v.map);
    local sx, sy, sh, live = SL.find(z);
    if sx and (live or gx == nil or dist2d(sx, sy, gx, gy) < 120) then   -- (a remembered seal: only if it's near the VNM's square)
        return v, sx, sy, live and 'seal' or 'seal_mem', sh;
    end
    if gx == nil then return nil; end
    return v, gx, gy, 'grid', nil;
end

TRF.trailPick = function(v) TRAIL.pick = v; end

-- A slider row: name on the left, the slider at the right edge. Saved when you let go.
function TRF.slider(id, text, key, lo, hi, fmt, tipText, int)
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.text, text);
    if tipText and imgui.IsItemHovered() then imgui.SetTooltip(tipText); end
    imgui.SameLine(ROW_W - 300);
    imgui.PushItemWidth(300);
    imgui.PushStyleColor(ImGuiCol_SliderGrab, { NEON2[1], NEON2[2], NEON2[3], 0.90 });
    imgui.PushStyleColor(ImGuiCol_SliderGrabActive, { NEON2[1], NEON2[2], NEON2[3], 1.00 });
    local val = { tonumber(config[key]) or lo };
    local changed;
    if int then changed = imgui.SliderInt(id, val, lo, hi, fmt);
    else changed = imgui.SliderFloat(id, val, lo, hi, fmt); end
    imgui.PopStyleColor(2);
    imgui.PopItemWidth();
    if tipText and imgui.IsItemHovered() then imgui.SetTooltip(tipText); end
    if changed then
        local v = val[1];
        if int then v = math.floor(v + 0.5); end
        config[key] = v;
        TRF.dirty = true;
        if key == 'trail_scale' then config.trail_size = 'custom'; end
    end
    if TRF.dirty and not imgui.IsAnyItemActive() then TRF.dirty = false; saveSettings(); end
end

-- Hunter of the week and Summit of the Stars (from catseyexi.com/events): their own tabs
function TRF.row(label, text, col, sub, lw)
    local dl = imgui.GetWindowDrawList();
    local x0 = imgui.GetCursorPosX();
    local sx, sy = imgui.GetCursorScreenPos();
    spaced(dl, sx, sy + 1, label, u32(C.label), 1.5);
    imgui.SetCursorPosX(x0 + (lw or 120));
    imgui.TextColored(col or C.text, text);
    if sub and sub ~= '' then imgui.SameLine(0, 10); imgui.TextColored(C.muted, sub); end
end
function TRF.dur(s)
    s = math.max(0, math.floor(s));
    if s >= 86400 then return ('%dd %dh %02dm'):fmt(math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)); end
    return ('%dh %02dm %02ds'):fmt(math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60);
end
-- Conquest Tally: when catseyexi.com/events counts down to (Sunday 16:00 UTC)
function TRF.tallyLeft()
    local now = os.time();
    local u = os.date('!*t', now);
    local secs = ((u.wday - 1) * 86400) + u.hour * 3600 + u.min * 60 + u.sec;   -- (since Sunday 00:00 UTC)
    local target = 16 * 3600;                                                   -- (Sunday 16:00 UTC)
    local left = target - secs;
    if left <= 0 then left = left + 7 * 86400; end
    return left;
end
function TRF.noData(what)
    if not config.website then hint('Turn on "Update from catseyexi.com/events" in Settings to see ' .. what .. '.');
    elseif SITE.x.pending then hint('Getting ' .. what .. ' from catseyexi.com...');
    else hint('No ' .. what .. ' from catseyexi.com yet. It\'s fetched in the background; check back in a moment.'); end
end
TRF.hunterTab = function()
    section('Hunter of the week');
    local H = SITE.x.hunter;
    if not config.website or H == nil then TRF.noData('the hunt'); return; end
    local cw = (config.mode == 'CW');
    for _, m in ipairs({ { 'ace', 'ACE', not cw }, { 'cw', 'CRYSTAL WARRIOR', cw } }) do
        local e = H[m[1]];
        if type(e) == 'table' and e.name then
            imgui.Spacing();
            local dl = imgui.GetWindowDrawList();
            local sx, sy = imgui.GetCursorScreenPos();
            spaced(dl, sx, sy, m[2] .. (m[3] and '   (your mode)' or ''), u32(m[3] and C.acc or C.label), 2);
            imgui.Dummy({ ROW_W, imgui.GetTextLineHeight() + 4 });
            local big = pushFont(fonts.big, 24);
            imgui.TextColored(m[3] and C.active or C.text, tostring(e.name));
            if big then imgui.PopFont(); end
            imgui.TextColored(C.muted, tostring(e.zone or '?') .. (e.points and ('   ·   ' .. e.points .. ' points') or ''));
            imgui.Spacing();
        end
    end
    imgui.Spacing();
    TRF.row('RESETS', 'Conquest Tally', C.text, 'in ' .. TRF.dur(TRF.tallyLeft()));
    hint('Weekly NM hunting targets, different for ACE and Crystal Warrior. Defeat yours for points; both change at Conquest Tally.');
    if SITE.x.at then hint('From catseyexi.com/events, updated ' .. (math.floor((os.time() - SITE.x.at) / 60)) .. ' min ago.'); end
end
TRF.summitTab = function()
    section('Summit of the Stars');
    local S = SITE.x.summit;
    if not config.website or S == nil or S.currentObjective == nil then TRF.noData('the Summit'); return; end
    local left = SITE.x.summitEnd and (SITE.x.summitEnd - os.time()) or nil;
    local dl = imgui.GetWindowDrawList();
    local sx, sy = imgui.GetCursorScreenPos();
    spaced(dl, sx, sy, 'CURRENT TARGET', u32(C.label), 2);
    imgui.Dummy({ ROW_W, imgui.GetTextLineHeight() + 4 });
    local big = pushFont(fonts.big, 28);
    imgui.TextColored(C.active, tostring(S.currentObjective.familyName or '?'));
    if big then imgui.PopFont(); end
    if left == nil then imgui.TextColored(C.muted, '');
    elseif left <= 0 then imgui.TextColored(C.muted, 'Changing now...');
    else imgui.TextColored(C.text, TRF.dur(left) .. ' left'); end
    imgui.Spacing(); imgui.Spacing();
    local B = S.currentBuff;
    if type(B) == 'table' and B.name then
        TRF.row('BUFF', tostring(B.name), C.seal, tostring(B.description or ''), 90);
    end
    hint('Defeat monsters of the target family together to earn the server-wide buff. The target changes every few hours; VenGo updates the moment it does.');
    if type(S.allBuffs) == 'table' and #S.allBuffs > 0 then
        section('All Summit buffs');
        for _, b in ipairs(S.allBuffs) do
            local on = type(B) == 'table' and b.id == B.id;
            TRF.row(on and 'NOW' or '', tostring(b.name or '?'), on and C.seal or C.text, tostring(b.description or ''), 60);
        end
    end
end

TRF.sliders = function()
    section('Arrows');
    TRF.slider('##vengo_s_scale', 'Size', 'trail_scale', 0.4, 2.5, '%.2fx', 'How big each arrow is (Small 0.70, Medium 1.00, Large 1.40)');
    TRF.slider('##vengo_s_space', 'Spacing', 'trail_spacing', 0.5, 3.0, '%.2fx', 'Space between arrows (or sets of three)');
    TRF.slider('##vengo_s_speed', 'Speed', 'trail_speed', 0, 15, '%.1f yalms/s', 'How fast the arrows crawl toward the VNM (0: still)');
    TRF.slider('##vengo_s_range', 'Reach', 'trail_range', 20, 150, '%.0f yalms', 'How far ahead of you arrows are drawn');
    section('Performance');
    TRF.slider('##vengo_s_seal', 'Venture Seal: check its spot', 'seal_check', 0.05, 2.0, 'every %.2f s', 'How often the Seal\'s own slot is looked at, once it\'s been found');
    TRF.slider('##vengo_s_scan', 'Venture Seal: search for it', 'seal_scan', 0.1, 5.0, 'every %.2f s', 'How often the whole list is searched while the Seal hasn\'t been found yet (2,300 slots)');
    TRF.slider('##vengo_s_cam', 'Camera: read it', 'cam_every', 1, 5, 'every %d frame(s)', 'Every frame is smoothest; every 2-5 frames costs less (the arrows may lag a fast camera spin a moment)', true);
    TRF.slider('##vengo_s_glow', 'Glow passes', 'glow_q', 1, 2, '%d', '1: one soft pass (lighter)   2: fuller glow', true);
    hint('Lower numbers for the Seal and camera are faster and smoother but cost a little more. Lightweight mode (under Window) sets these in one click.');
end

-- Three preset slots: every setting, saved to vengo_presets.lua and loaded back with one click
local PRESET_KEYS = { 'transparent', 'alerts', 'alert_sound', 'alert90', 'mode', 'pool', 'sort', 'website', 'login_refresh', 'logo_anim',
    'trail', 'trail_glow', 'trail_color', 'trail_style', 'trail_size', 'theme', 'bg', 'lite',
    'seal_check', 'seal_scan', 'cam_every', 'trail_range', 'trail_scale', 'trail_spacing', 'trail_speed', 'glow_q' };
function TRF.presetFile() return addon.path .. 'vengo_presets.lua'; end
function TRF.loadPresets()
    TRF.slots = {};
    local chunk = loadfile(TRF.presetFile());
    if chunk then local ok, t_ = pcall(chunk); if ok and type(t_) == 'table' then TRF.slots = t_; end end
end
function TRF.savePresets()
    local f = io.open(TRF.presetFile(), 'w');
    if f == nil then return; end
    f:write('-- VenGo preset slots (written by VenGo)\nreturn {\n');
    for i = 1, 3 do
        local s = TRF.slots[i];
        if s then
            f:write(('  [%d] = { at = %q, cfg = {\n'):format(i, s.at or ''));
            for _, k in ipairs(PRESET_KEYS) do
                local v = s.cfg[k];
                if v ~= nil then f:write(('    %s = %s,\n'):format(k, type(v) == 'string' and ('%q'):format(v) or tostring(v))); end
            end
            f:write('  } },\n');
        end
    end
    f:write('}\n');
    f:close();
end
TRF.presets = function()
    if TRF.slots == nil then TRF.loadPresets(); end
    section('Presets');
    for i = 1, 3 do
        local s = TRF.slots[i];
        imgui.AlignTextToFramePadding();
        imgui.TextColored(C.text, ('Slot %d'):format(i));
        imgui.SameLine(0, 14);
        imgui.TextColored(C.muted, s and ('saved ' .. (s.at or '')) or 'empty');
        imgui.SameLine(ROW_W - 250);
        if button(('SAVE##vengo_ps%d'):format(i), { 120, 0 }, true, true) then
            local c_ = {};
            for _, k in ipairs(PRESET_KEYS) do c_[k] = config[k]; end
            TRF.slots[i] = { at = os.date('%b %d  %I:%M %p'), cfg = c_ };
            TRF.savePresets();
            msg(('Settings saved to slot %d.'):format(i));
        end
        imgui.SameLine(0, 10);
        if s then
            if button(('LOAD##vengo_pl%d'):format(i), { 120, 0 }, false, true) then
                for _, k in ipairs(PRESET_KEYS) do if s.cfg[k] ~= nil then config[k] = s.cfg[k]; end end
                pcall(C.apply);
                saveSettings();
                msg(('Settings loaded from slot %d.'):format(i));
            end
        else
            button(('LOAD##vengo_pl%d'):format(i), { 120, 0 }, true, true);
        end
    end
    hint('SAVE keeps every setting (colours, arrows, performance, alerts, window) in that slot; LOAD puts them all back.');
end

-- Are the arrows up for this venture right now?
TRF.trailShowing = function(v)
    return v ~= nil and TRAIL.v == v and TRAIL.stopped ~= v.key and zone() == v.zone and (config.trail or TRAIL.forced == v.key);
end

-- GO in the venture's zone: arrows on (even if the setting is off); STOP: arrows off. Forgotten when you leave the zone.
TRF.trailGo = function(v)
    if TRF.trailShowing(v) then
        TRAIL.stopped, TRAIL.forced = v.key, nil;
        msg(('Arrows to %s off. Press GO to show them again.'):fmt(v.nm or 'the VNM'));
    else
        TRAIL.stopped, TRAIL.pick, TRAIL.zone_ = nil, v, zone();
        if not config.trail then TRAIL.forced = v.key; end
        TRAIL.v = v;                                          -- (the button turns to STOP at once)
        msg(('Arrows on: follow them to %s (%s).'):fmt(v.nm or 'the VNM', v.grid or '?'));
    end
    return true;
end

trailTick = function(now)
    -- Look at the game's draws next frame only while arrows are up (Lightweight: one frame in three, the last
    -- camera kept in between). Otherwise VenGo leaves the game's drawing alone.
    CAM.frame = CAM.frame + 1;
    local want = TRAIL.wanted and not CAM.dead;
    local ce = math.max(1, math.floor(tonumber(config.cam_every) or 1));
    if want and ce > 1 and CAM.view and CAM.frame % ce ~= 0 then want = false; end
    if want then CAM.cands, CAM.tries = {}, 0; end
    CAM.max = 800;
    CAM.on = want;
end

local function glowLine(dl, a, b, col, w, glow)
    if glow and (tonumber(config.glow_q) or 2) < 2 then       -- (one soft pass)
        dl:AddLine(a, b, u32({ col[1], col[2], col[3], col[4] * 0.18 }), w * 2.6);
    elseif glow then
        dl:AddLine(a, b, u32({ col[1], col[2], col[3], col[4] * 0.10 }), w * 3.2);
        dl:AddLine(a, b, u32({ col[1], col[2], col[3], col[4] * 0.22 }), w * 1.9);
    end
    dl:AddLine(a, b, u32(col), w);
end

drawTrail = function()
    TRAIL.wanted = false;
    if not config.trail and TRAIL.forced == nil then return; end
    local v, tx, ty, kind, th = trailTarget();
    if v == nil or (not config.trail and TRAIL.forced ~= v.key) then TRAIL.v = nil; return; end
    TRAIL.wanted = true;
    TRAIL.kind = kind;
    local px, py, ph = pos();
    if px == nil then return; end
    local now = os.clock();
    local fresh = (#CAM.cands > 0);
    if not fresh and CAM.view == nil then CAM.on, CAM.max, CAM.tries = true, 1, 0; camSample(); fresh = (#CAM.cands > 0); end   -- (no draws seen: try now)
    if fresh and not calibrate(px, py, ph) then
        if TRAIL.cam == 'not read yet' or TRAIL.cam:find('^found') then
            TRAIL.cam = (#CAM.cands == 0) and 'no 3D camera seen (VanaCore may not pass the game\'s draws to addons)'
                or ('%d cameras seen, none near you'):format(#CAM.cands);
        end
        return;
    end
    if CAM.view == nil or TRAIL.order == nil then return; end
    TRAIL.v = v;
    local dist = dist2d(px, py, tx, ty);
    if dist < ((kind == 'grid') and TRAIL_NEAR or 2.5) then return; end
    local gh = th or ph;                                      -- (the ground at the end: the seal's own height when known)

    local ds = imgui.GetIO().DisplaySize;
    local W, H = (ds and ds.x) or 1920, (ds and ds.y) or 1080;
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoMove,
        ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoInputs or 197120, ImGuiWindowFlags_NoSavedSettings or 256, ImGuiWindowFlags_NoBringToFrontOnFocus or 8192);
    imgui.SetNextWindowPos({ 0, 0 }, ImGuiCond_Always);
    imgui.SetNextWindowSize({ W, H }, ImGuiCond_Always);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    if imgui.Begin('##vengo_trail', { true }, flags) then
        local dl = imgui.GetWindowDrawList();
        local col = trailColor();
        local glow = config.trail_glow ~= false;
        local ux, uy = (tx - px) / dist, (ty - py) / dist;    -- toward the VNM
        local RANGE = tonumber(config.trail_range) or TRAIL_LEN;
        local len = math.min(dist, RANGE);

        -- the chevrons, crawling toward the VNM, in the style and size picked in Settings
        local style = config.trail_style or 'solid';
        local SZ = tonumber(config.trail_scale) or 1.0;
        local SP = tonumber(config.trail_spacing) or 1.0;
        local mix = (config.trail_color == 'neon');
        local NEON_MIX = { { 0.25, 0.65, 1.00 }, { 1.00, 0.55, 0.20 }, { 0.68, 0.42, 1.00 }, { 0.20, 0.92, 0.85 } };
        local SOLID_MIX = { { 1.00, 0.42, 0.18 }, { 0.15, 0.90, 0.85 }, { 0.30, 0.55, 1.00 } };   -- (orange, teal, blue)
        local nx, ny = -uy, ux;                                -- across the path
        local phase = now * (tonumber(config.trail_speed) or 5);

        if style == 'lines' then
            -- the first look: two glowing lines meeting at a point, flat on the screen
            local every = 4 * SP;
            local off = phase % every;
            local first = math.floor(phase / every);
            local k = 0;
            local d = off + 1.5;
            while d < len - 1 do
                local sx, sy, sw = project(toD3D(px + ux * d, py + uy * d, ph));
                local ex, ey = project(toD3D(px + ux * (d + 1), py + uy * (d + 1), ph));
                if sx and ex then
                    local dx, dy = ex - sx, ey - sy;
                    local l = math.sqrt(dx * dx + dy * dy);
                    if l > 0.01 then
                        dx, dy = dx / l, dy / l;
                        local c = mix and NEON_MIX[((k - first) % #NEON_MIX) + 1] or col;
                        local size = math.max(3, math.min(18, 260 / sw)) * SZ;
                        local fade = 1 - (d / RANGE) * 0.6;
                        local l1 = { sx - dx * size * 0.8 - dy * size * 0.6, sy - dy * size * 0.8 + dx * size * 0.6 };
                        local l2 = { sx - dx * size * 0.8 + dy * size * 0.6, sy - dy * size * 0.8 - dx * size * 0.6 };
                        local wpx = math.max(1.5, math.min(5, 60 / sw)) * math.sqrt(SZ);
                        local cc = { c[1], c[2], c[3], 0.95 * fade };
                        glowLine(dl, l1, { sx, sy }, cc, wpx, glow);
                        glowLine(dl, l2, { sx, sy }, cc, wpx, glow);
                        dl:AddCircleFilled({ sx, sy }, wpx * 0.6, u32({ 1, 1, 1, 0.8 * fade }), 8);
                    end
                end
                d = d + every;
                k = k + 1;
            end
        else
            -- 'bands': hollow neon bands; 'solid': filled glowing chevrons in sets of three, nested close together.
            -- Both lean back 35 degrees from the ground, facing you.
            local solid = (style == 'solid');
            local A, Wd, T = 1.1 * SZ, 1.4 * SZ, (solid and 0.8 or 0.6) * SZ;
            local TC, TS = math.cos(math.rad(35)), math.sin(math.rad(35));
            local every = (solid and 9 * SZ or 5 * SZ) * SP;       -- (a set of three, or one)
            local per = solid and 3 or 1;
            local gap = 1.55 * A;                                   -- (within a set)
            local off = phase % every;
            local first = math.floor(phase / every);
            local k = 0;
            local d0 = off + 2.5;
            local spots = {};                                       -- (drawn far to near, so the near ones are on top)
            while d0 < len - 1 do
                for j = 0, per - 1 do
                    if d0 + j * gap < len - 1 then spots[#spots + 1] = { d0 + j * gap, j, k }; end
                end
                d0 = d0 + every;
                k = k + 1;
            end
            for si = #spots, 1, -1 do
                local d, j, k = spots[si][1], spots[si][2], spots[si][3];
                do
                    do
                        local function gp(f, s_)
                            local fo = f * TC;
                            return project(above(px + ux * (d + fo) + nx * s_, py + uy * (d + fo) + ny * s_, ph, (f + A) * TS));
                        end
                        local function shape(a_, w_, t_)               -- tip, right end, (inner) right end, inner tip, (inner) left end, left end
                            local P = {};
                            for i, q in ipairs({ { a_, 0 }, { -a_, w_ }, { -a_ + t_, w_ }, { a_ - t_ * 1.5, 0 }, { -a_ + t_, -w_ }, { -a_, -w_ } }) do
                                local x_, y_, w2 = gp(q[1], q[2]);
                                if not x_ then return nil; end
                                P[i] = { x_, y_ };
                                if i == 1 then P.w = w2; end
                            end
                            return P;
                        end
                        local P = shape(A, Wd, T);
                        if P then
                            local c;
                            if solid then c = mix and SOLID_MIX[j + 1] or col;
                            else c = mix and NEON_MIX[((k - first) % #NEON_MIX) + 1] or col; end
                            local fade = 1 - (d / RANGE) * 0.6;
                            local wpx = math.max(1.2, math.min(3.5, 45 / P.w));
                            local function quads(Q, colr)
                                dl:AddQuadFilled(Q[1], Q[2], Q[3], Q[4], colr);
                                dl:AddQuadFilled(Q[1], Q[4], Q[5], Q[6], colr);
                            end
                            if solid then
                                -- a bright body, a lighter core, a white-hot inner edge, and the neon rim
                                quads(P, u32({ c[1], c[2], c[3], 0.80 * fade }));
                                local Q = shape(A - T * 0.28, Wd - T * 0.22, T * 0.45);
                                if Q then
                                    quads(Q, u32({ 0.55 + c[1] * 0.45, 0.55 + c[2] * 0.45, 0.55 + c[3] * 0.45, 0.55 * fade }));
                                    local hw = u32({ 1, 1, 1, 0.55 * fade });
                                    for i = 1, 6 do dl:AddLine(Q[i], Q[i % 6 + 1], hw, math.max(1, wpx * 0.4)); end
                                end
                                local cc = { 0.6 + c[1] * 0.4, 0.6 + c[2] * 0.4, 0.6 + c[3] * 0.4, 0.95 * fade };
                                for i = 1, 6 do glowLine(dl, P[i], P[i % 6 + 1], cc, wpx * 0.8, false); end
                                if glow then
                                    local lightg = (tonumber(config.glow_q) or 2) < 2;
                                    local g1 = u32({ c[1], c[2], c[3], (lightg and 0.16 or 0.10) * fade });
                                    local g2 = u32({ c[1], c[2], c[3], 0.20 * fade });
                                    for i = 1, 6 do
                                        dl:AddLine(P[i], P[i % 6 + 1], g1, wpx * (lightg and 3.6 or 5));
                                        if not lightg then dl:AddLine(P[i], P[i % 6 + 1], g2, wpx * 2.6); end
                                    end
                                end
                            else
                                quads(P, u32({ c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 0.55 * fade }));
                                if glow then quads(P, u32({ c[1], c[2], c[3], 0.10 * fade })); end
                                local cc = { c[1], c[2], c[3], 0.95 * fade };
                                for i = 1, 6 do glowLine(dl, P[i], P[i % 6 + 1], cc, wpx, glow); end
                                local m1 = { gp(A - T * 0.8, 0) };
                                local m2 = { gp(-A + T * 0.5, Wd - T * 0.5) };
                                local m3 = { gp(-A + T * 0.5, -Wd + T * 0.5) };
                                if m1[1] and m2[1] and m3[1] then
                                    local wc = u32({ 0.5 + c[1] * 0.5, 0.5 + c[2] * 0.5, 0.5 + c[3] * 0.5, 0.55 * fade });
                                    dl:AddLine({ m2[1], m2[2] }, { m1[1], m1[2] }, wc, math.max(1, wpx * 0.45));
                                    dl:AddLine({ m3[1], m3[2] }, { m1[1], m1[2] }, wc, math.max(1, wpx * 0.45));
                                end
                            end
                        end
                    end
                end
            end
        end

        -- the marker: a ring on the ground around the square's middle, a pole, a flag and the name
        local mx, my, mw = project(toD3D(tx, ty, gh));
        if mx and mx > -50 and mx < W + 50 and my > -50 and my < H + 50 then
            local pulse = 0.6 + 0.4 * math.sin(now * 3);
            local ring = {};
            for i = 0, 24 do
                local a = i / 24 * math.pi * 2;
                local rx, ry = project(toD3D(tx + math.cos(a) * 3, ty + math.sin(a) * 3, gh));
                if rx then ring[#ring + 1] = { rx, ry }; end
            end
            for i = 2, #ring do glowLine(dl, ring[i - 1], ring[i], { col[1], col[2], col[3], 0.8 * pulse }, math.max(1.5, math.min(4, 60 / mw)), glow); end
            local fx, fy = project(above(tx, ty, gh, 7));
            if fx then
                glowLine(dl, { mx, my }, { fx, fy }, { C.mp2[1], C.mp2[2], C.mp2[3], 0.9 }, math.max(1.5, math.min(4, 60 / mw)), glow);
                local fs = math.max(6, math.min(26, 400 / mw));
                dl:AddTriangleFilled({ fx, fy }, { fx + fs, fy + fs * 0.35 }, { fx, fy + fs * 0.7 }, u32({ col[1], col[2], col[3], 1 }));
                local label = (kind == 'grid') and ('%s  %s  ·  %d yalms'):fmt(v.nm or 'VNM', v.grid or '', math.floor(dist + 0.5))
                    or ('Venture Seal  ·  %s  ·  %d yalms'):fmt(v.nm or 'VNM', math.floor(dist + 0.5));
                local tw = imgui.CalcTextSize(label);
                local lh = imgui.GetTextLineHeight();
                local bx, by = fx - tw / 2, fy - lh - 22;
                dl:AddRectFilled({ bx - 10, by - 5 }, { bx + tw + 10, by + lh + 5 }, u32({ C.pbg[1], C.pbg[2], C.pbg[3], 0.90 }), 8);
                dl:AddRect({ bx - 10, by - 5 }, { bx + tw + 10, by + lh + 5 }, u32({ C.mp2[1], C.mp2[2], C.mp2[3], 0.55 }), 8, C.rall, 1);
                dl:AddText({ bx, by }, u32(C.text), label);
            end
        end
    end
    imgui.End();
    imgui.PopStyleVar(2);
end

trailSettings = function()
    section('Trail to the VNM');
    if rowSwitch('##vengo_trail', 'Trail on the ground to the VNM', config.trail ~= false,
            'Glowing arrows on the ground from your feet to the VNM\'s grid square, in the venture\'s zone (and after GO)') then
        config.trail = not (config.trail ~= false);
        saveSettings();
    end
    if rowSwitch('##vengo_trail_glow', 'Glow', config.trail_glow ~= false, 'A soft glow around the arrows') then
        config.trail_glow = not (config.trail_glow ~= false);
        saveSettings();
    end
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.text, 'Arrow style');
    imgui.SameLine(ROW_W - 400);
    local stl = pillChoice('##vengo_tstyle', { { 'lines', 'LINES' }, { 'bands', 'NEON BANDS' }, { 'solid', 'SOLID NEON' } }, config.trail_style or 'solid');
    if stl then config.trail_style = stl; saveSettings(); end
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.text, 'Arrow size');
    imgui.SameLine(ROW_W - 400);
    local sc_ = tonumber(config.trail_scale) or 1;
    local szcur = (math.abs(sc_ - 0.7) < 0.01 and 'small') or (math.abs(sc_ - 1) < 0.01 and 'medium') or (math.abs(sc_ - 1.4) < 0.01 and 'large') or '';
    local szc = pillChoice('##vengo_tsize', { { 'small', 'SMALL' }, { 'medium', 'MEDIUM' }, { 'large', 'LARGE' } }, szcur);
    if szc then config.trail_size = szc; config.trail_scale = ({ small = 0.7, medium = 1.0, large = 1.4 })[szc]; saveSettings(); end
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.text, 'Arrow colour');
    imgui.SameLine(ROW_W - #TRAIL_COLORS * 30 + 4);
    local dl = imgui.GetWindowDrawList();
    for i, c in ipairs(TRAIL_COLORS) do
        local x, y = imgui.GetCursorScreenPos();
        local h = imgui.GetFrameHeight();
        if imgui.InvisibleButton('##vengo_tc' .. c[1], { 26, h }) then config.trail_color = c[1]; saveSettings(); end
        local on = (config.trail_color or 'pink') == c[1];
        local cx, cy = x + 13, y + h / 2;
        dl:AddCircleFilled({ cx, cy }, 9, u32({ c[2][1], c[2][2], c[2][3], 0.25 }), 20);
        if c[1] == 'neon' then                                -- (neon mix: blue, orange, violet, teal)
            local q = { { 0.25, 0.65, 1.00 }, { 1.00, 0.55, 0.20 }, { 0.68, 0.42, 1.00 }, { 0.20, 0.92, 0.85 } };
            for j = 0, 3 do
                local a0 = j * math.pi / 2;
                for s_ = 0, 3 do
                    local b0, b1 = a0 + s_ * math.pi / 8, a0 + (s_ + 1) * math.pi / 8;
                    dl:AddTriangleFilled({ cx, cy }, { cx + math.cos(b0) * 6, cy + math.sin(b0) * 6 },
                        { cx + math.cos(b1) * 6, cy + math.sin(b1) * 6 }, u32({ q[j + 1][1], q[j + 1][2], q[j + 1][3], 1 }));
                end
            end
        else
            dl:AddCircleFilled({ cx, cy }, 6, u32({ c[2][1], c[2][2], c[2][3], 1 }), 20);
        end
        if on then dl:AddCircle({ cx, cy }, 10.5, u32({ 1, 1, 1, 0.9 }), 20, 1.5); end
        if imgui.IsItemHovered() then imgui.SetTooltip((c[1] == 'neon') and 'neon mix' or c[1]); end
        if i < #TRAIL_COLORS then imgui.SameLine(0, 4); end
    end
    local st = TRAIL.cam;
    if TRAIL.cam == 'found' and TRAIL.order == nil then st = 'found, but your spot didn\'t line up'; end
    imgui.TextColored(C.muted, 'Camera: ' .. st .. (TRAIL.v and ('   ·   guiding to ' .. (TRAIL.v.nm or '?')
        .. ((TRAIL.kind == 'seal') and ' (the Venture Seal)' or (TRAIL.kind == 'seal_mem') and ' (the Venture Seal, remembered)' or ' (its grid square)')) or ''));
    hint('It heads for the VNM\'s grid square, then straight to the Venture Seal once it\'s loaded (about 50 yalms), and remembers where each zone\'s Seal is for next time. A straight line: it points the way, not the route round walls.');
end

-- the camera is read while the world is being drawn
local hooked = false;
if rawget(_G, 'vana') and type(vana.on) == 'function' then
    hooked = pcall(function ()
        vana.on('d3d_dip', function () camSample(); end);
        vana.on('d3d_dp', function () camSample(); end);
    end);
end
if not hooked then
    pcall(function ()
        ashita.events.register('d3d_dip', 'vengo_cam_dip', function () camSample(); end);
        ashita.events.register('d3d_dp', 'vengo_cam_dp', function () camSample(); end);
    end);
end
end

local function tabSettings()
    section('Window');
    if rowSwitch('##vengo_lite', 'Lightweight mode', config.lite == true,
            'A quick preset for the Performance sliders: camera every 3 frames, arrows to 60 yalms, one glow pass, the Seal checked every 0.5 s. Off puts the normal values back. Move any slider after to fine-tune.') then
        config.lite = not config.lite;
        local P_ = config.lite and { cam_every = 3, trail_range = 60, glow_q = 1, seal_check = 0.5, seal_scan = 1.0 }
            or { cam_every = 1, trail_range = 90, glow_q = 2, seal_check = 0.25, seal_scan = 0.5 };
        for k, v in pairs(P_) do config[k] = v; end
        saveSettings();
    end
    if rowSwitch('##vengo_clear_sw', 'See-through window', config.transparent == true,
            'Lets the game show through the panel') then
        config.transparent = not config.transparent;
        saveSettings();
    end
    if rowSwitch('##vengo_logoanim', 'Animate the logo', config.logo_anim == true,
            'A shine that sweeps across it every few seconds, and petals drifting in the wind') then
        config.logo_anim = not config.logo_anim;
        saveSettings();
    end
    hint('Drag the bottom-right corner to resize. The  -  button at the top right shrinks VenGo to a small tag.');

    section('Colours');
    local function swatches(id, list, cur, draw)
        local dl = imgui.GetWindowDrawList();
        local picked = nil;
        imgui.SameLine(ROW_W - #list * 34 + 6);
        for i, e in ipairs(list) do
            local x, y = imgui.GetCursorScreenPos();
            local h = imgui.GetFrameHeight();
            if imgui.InvisibleButton(id .. e[1], { 30, h }) then picked = e[1]; end
            local cx, cy = x + 15, y + h / 2;
            draw(dl, cx, cy, e);
            if (cur or list[1][1]) == e[1] then dl:AddCircle({ cx, cy }, 12.5, u32({ 1, 1, 1, 0.9 }), 24, 1.5); end
            if imgui.IsItemHovered() then imgui.SetTooltip(e[2]); end
            if i < #list then imgui.SameLine(0, 4); end
        end
        return picked;
    end
    local function half(dl, cx, cy, r, a0, c)                -- half a circle, from angle a0
        for s_ = 0, 7 do
            local b0, b1 = a0 + s_ * math.pi / 8, a0 + (s_ + 1) * math.pi / 8;
            dl:AddTriangleFilled({ cx, cy }, { cx + math.cos(b0) * r, cy + math.sin(b0) * r },
                { cx + math.cos(b1) * r, cy + math.sin(b1) * r }, u32({ c[1], c[2], c[3], 1 }));
        end
    end
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.text, 'Accent');
    local ac = swatches('##vengo_th_', C.accents, config.theme, function (dl, cx, cy, e)
        dl:AddCircleFilled({ cx, cy }, 11, u32({ e[3][1], e[3][2], e[3][3], 0.22 }), 24);
        half(dl, cx, cy, 8, math.pi * 0.75, e[3]);
        half(dl, cx, cy, 8, math.pi * 1.75, e[4]);
    end);
    if ac then config.theme = ac; C.apply(); saveSettings(); end
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.text, 'Background');
    local bgc = swatches('##vengo_bg_', C.bgs, config.bg, function (dl, cx, cy, e)
        dl:AddCircleFilled({ cx, cy }, 9, u32({ e[4][1], e[4][2], e[4][3], 1 }), 24);
        dl:AddCircleFilled({ cx, cy }, 6, u32({ e[3][1], e[3][2], e[3][3], 1 }), 24);
        dl:AddCircle({ cx, cy }, 9, u32({ 1, 1, 1, 0.25 }), 24, 1);
    end);
    if bgc then config.bg = bgc; C.apply(); saveSettings(); end
    hint('Accent: the edges, highlights, switches and bars. Background: the panel itself. See-through mode still works with every colour.');

    section('VNM Alerts');
    if rowSwitch('##vengo_alerts', 'Alert when a VNM is announced', config.alerts == true,
            'Watches chat for Populox announcing a VNM in Unity chat') then
        config.alerts = not config.alerts;
        saveSettings();
    end
    if rowSwitch('##vengo_alert_snd', 'Play a sound', config.alert_sound == true,
            'At the announcement, and again a minute before it pops') then
        config.alert_sound = not config.alert_sound;
        saveSettings();
    end
    if button('TEST ALERT##vengo_test', { 240, 0 }) then
        AshitaCore:GetChatManager():QueueCommand(-1, '/vengo testalert');
    end
    imgui.SameLine(0, 10);
    if ALERT and button('CLEAR ALERT##vengo_clear_alert', { 240, 0 }, true) then ALERT = nil; end
    if LAST_ANNOUNCE then
        hint('Last Populox line: ' .. LAST_ANNOUNCE);
    else
        hint('No Populox line seen yet. Every one is saved to announcements.txt in the vengo folder; send me one so I can match them exactly.');
    end

    section('Warping');
    if WARPS then
        imgui.TextColored(C.text, 'Uberwarp: found');
        hint('Warp list read from ' .. (WARPS_FROM or '?') .. '. GO also needs the Uberwarp plugin loaded in game.');
    else
        imgui.TextColored({ C.hp[1], C.hp[2], C.hp[3], 1 }, 'Uberwarp: not found');
        hint('Install Uberwarp (the plugin, plus its resources folder in the VanaCore folder), or copy its "resources" folder into the vengo folder.');
    end
    if button('FIND UBERWARP##vengo_uwscan', { 320, 0 }) then
        if loadWarps() then msg('Uberwarp\'s warp list found.'); else msg('Uberwarp\'s warp list still not found.'); end
    end
    local near = nearSystem();
    imgui.TextColored(C.muted, 'Standing at: ' .. (near and SYS_NAME[near] or 'no warp NPC'));
    hint('Stand at a Home Point, Survival Guide or Unity NPC and press GO. Pressed anywhere else, GO waits 3 minutes and warps the moment you walk up to one. It picks the warp that lands closest to the VNM.');

    trailSettings();
    TRF.sliders();
    TRF.presets();

    section('Ventures data');
    if rowSwitch('##vengo_cw', 'Crystal Warrior zones (CW)', config.mode == 'CW',
            'Off: ACE zones. The board has a set of zones for each.') then
        config.mode = (config.mode == 'CW') and 'ACE' or 'CW';
        saveSettings();
        applyLive(false);
        applySite(false);
    end
    if LIVE then
        imgui.TextColored(C.text, 'Game board: live, updated ' .. (liveAge() or '?'));
    else
        imgui.TextColored(C.text, 'Game board: not received yet');
    end
    if rowSwitch('##vengo_login', 'Type !ventures when you log in', config.login_refresh == true,
            'Once per log-in, a few seconds after you arrive, so the board is current right away') then
        config.login_refresh = not config.login_refresh;
        saveSettings();
    end
    if rowSwitch('##vengo_site', 'Update from catseyexi.com/events', config.website == true,
            'After every reset (and at least weekly), in the background: HVNM details, mobs, HELM, Fishing, Dynamis and the reset time') then
        config.website = not config.website;
        saveSettings();
        if config.website then SITE.nextAt = 0; end
    end
    if config.website then
        local st = SITE.pending and 'updating...' or (SITE.at and ('updated ' .. siteAge()) or 'not updated yet');
        imgui.TextColored(SITE.err and { C.hp[1], C.hp[2], C.hp[3], 1 } or C.text, 'Website: ' .. st .. (SITE.err and ('  (' .. SITE.err .. ')') or ''));
        if button('UPDATE NOW##vengo_siteupd', { 320, 0 }) then SITE.nextAt = 0; end
    end
    hint('The server sends the board on its own; VenGo reads it as it arrives. Until then the list comes from ventures.lua.');
    if rowSwitch('##vengo_a90', 'Heads-up in chat at 90%', config.alert90 == true) then
        config.alert90 = not config.alert90;
        saveSettings();
    end
    imgui.TextColored(C.text, 'VNM drops and positions: ' .. ((VNMDB and VNMDB_FROM) or 'missing'));
    if button('UPDATE DROP DATA##vengo_upd', { 320, 0 }) then
        AshitaCore:GetChatManager():QueueCommand(-1, '/vengo update');
    end
    hint('Drops, grid squares and notes come from the ventures addon\'s community list (by Commandobill). If the download does not work, copy data\\vnms.lua from that addon into the vengo folder.');
    if button('RELOAD VENTURES FILE##vengo_reload', { 320, 0 }) then
        loadVentures(); applyLive(false);
        msg(('Loaded %d ventures.'):fmt(#ventures));
    end
    hint('ventures.lua is only needed for HELM, Fishing and Dynamis, and as a fallback.');
end

------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------
local drawAlert, drawMini;
do
-- The alert banner: top middle of the screen, over everything, until you
-- dismiss it or press GO. Shows even when the VenGo window is closed or small.
drawAlert = function()
    if ALERT == nil or ALERT.dismissed then return; end
    local v = ALERT.v;
    local nc, nv = pushTheme();
    local pulse = 0.55 + 0.45 * math.sin(os.clock() * 4);
    imgui.PushStyleColor(ImGuiCol_WindowBg, { 0.05, 0.04, 0.07, config.transparent and 0.70 or 0.95 });
    imgui.PushStyleColor(ImGuiCol_Border, { NEON2[1], NEON2[2], NEON2[3], 0.45 + 0.55 * pulse });
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 22, 16 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 2);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 10);
    nc, nv = nc + 2, nv + 3;
    local ds = imgui.GetIO().DisplaySize;
    imgui.SetNextWindowPos({ ((ds and ds.x) or 1920) / 2, 70 }, ImGuiCond_FirstUseEver, { 0.5, 0 });
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoFocusOnAppearing);
    local pushed = pushFont(fonts.panel, 16);
    if imgui.Begin('VenGo alert##vengo_alert', { true }, flags) then
        local dl = imgui.GetWindowDrawList();
        local x0, y0 = imgui.GetCursorScreenPos();
        local lh = imgui.GetTextLineHeight();
        local w = spaced(dl, x0, y0, 'VNM INCOMING', u32({ NEON2[1], NEON2[2], NEON2[3], 0.6 + 0.4 * pulse }), 3);
        imgui.Dummy({ w, lh });

        local tp = pushFont(fonts.big, 26);
        if not tp then imgui.SetWindowFontScale(1.35); end
        imgui.TextColored(C.text, v.nm);
        if tp then imgui.PopFont(); else imgui.SetWindowFontScale(1); end

        imgui.TextColored(C.acc, ('%s  (%s)'):fmt(v.zone_name, v.grid or '?'));
        local d = dropsOf(v);
        if d ~= '' then
            imgui.TextColored(C.muted, 'Drops');
            imgui.SameLine();
            imgui.PushTextWrapPos(imgui.GetCursorPosX() + 360);
            imgui.TextColored(C.seal, d);
            imgui.PopTextWrapPos();
        end
        local left = ALERT.pop_at - os.time();
        imgui.TextColored(left <= 60 and { C.hp[1], C.hp[2], C.hp[3], 1 } or C.active, popWords(left));
        imgui.Spacing();
        if isActive(v) then
            if button('CANCEL##vengo_alert_go', { 160, 38 }, true) then ARMED = nil; msg('Cancelled.'); end
        elseif TRF.trailShowing(v) then
            if button('STOP##vengo_alert_go', { 160, 38 }, true) then warpTo(v); end
        elseif button('GO##vengo_alert_go', { 160, 38 }) then
            warpTo(v);
        end
        warpTip(v);
        imgui.SameLine(0, 10);
        if button('DISMISS##vengo_alert_x', { 140, 38 }, true) then ALERT.dismissed = true; end
    end
    imgui.End();
    if pushed then imgui.PopFont(); end
    imgui.PopStyleVar(nv);
    imgui.PopStyleColor(nc);
end

-- Minimised: a small glowing tag with "VenGo" (Go shimmering). Click it to open the
-- panel again; drag it to move it. A dot pulses while VenGo is running somewhere.
local MINI = { x = nil, y = nil, dragged = false };

-- An arc of a circle drawn as short lines (no ImGui path calls needed)
local function arc(dl, cx, cy, r, a0, a1, col, thick)
    local n = math.max(6, math.floor(math.abs(a1 - a0) * r / 4));
    local px, py = cx + math.cos(a0) * r, cy + math.sin(a0) * r;
    for k = 1, n do
        local a = a0 + (a1 - a0) * k / n;
        local x, y = cx + math.cos(a) * r, cy + math.sin(a) * r;
        dl:AddLine({ px, py }, { x, y }, col, thick);
        px, py = x, y;
    end
end

-- Mix of two colours (u from 0 to 1)
local function mix(c1, c2, u, a)
    return { c1[1] + (c2[1] - c1[1]) * u, c1[2] + (c2[2] - c1[2]) * u, c1[3] + (c2[3] - c1[3]) * u, a or 1 };
end

local ICE = { 0.45, 0.78, 1.00 };      -- the rings' light blue
local LILAC = { 0.70, 0.52, 1.00 };    -- and their violet

-- Minimised: a round glossy orb with a silver rim and two light rings sweeping
-- around it (shifting blue to violet), "VenGo" across the middle with Go
-- shimmering pink to violet.
-- Click it to open the panel; drag it to move it.
drawMini = function()
    local nc, nv = pushTheme();
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse,
        ImGuiWindowFlags_NoMove);
    local R = 34;                                     -- the orb's radius
    local S = (R + 16) * 2;                           -- the window (room for the rings, glow and badge)
    if MINI.x then imgui.SetNextWindowPos({ MINI.x, MINI.y }, ImGuiCond_Always);
    else imgui.SetNextWindowPos({ 240, 160 }, ImGuiCond_FirstUseEver); end
    imgui.SetNextWindowSize({ S, S }, ImGuiCond_Always);
    if imgui.Begin('VenGo##vengo_mini', { true }, flags) then
        local dl = imgui.GetWindowDrawList();
        local wx, wy = imgui.GetWindowPos();
        MINI.x, MINI.y = wx, wy;
        local cx, cy = wx + S / 2, wy + S / 2;
        local t = os.clock();
        local clear = config.transparent;
        local running = ARMED ~= nil;
        local hot = ALERT ~= nil;

        -- soft glow around it (stronger and pinker during an alert)
        local gcol = hot and NEON2 or LILAC;
        local gpulse = hot and (0.6 + 0.4 * math.sin(t * 5)) or 1;
        for k = 1, 5 do
            dl:AddCircle({ cx, cy }, R + 3 + k * 2, u32({ gcol[1], gcol[2], gcol[3], 0.06 * (6 - k) * gpulse }), 48, 2.5);
        end

        -- the two light rings, turning opposite ways, their colour drifting blue <-> violet
        local u = 0.5 + 0.5 * math.sin(t * 0.8);
        local c1 = hot and mix(NEON2, LILAC, u) or mix(ICE, LILAC, u);
        local c2 = hot and mix(LILAC, NEON2, u) or mix(LILAC, ICE, u);
        local spin = running and 2.4 or 1.3;
        local a1 = t * spin;
        arc(dl, cx, cy, R + 7, a1, a1 + 3.6, u32({ c1[1], c1[2], c1[3], 0.95 }), 2.2);
        arc(dl, cx, cy, R + 7, a1 + 3.6, a1 + 3.9, u32({ c1[1], c1[2], c1[3], 0.35 }), 1.6);   -- (its fading tail)
        local a2 = -t * spin * 0.7 + 1.5;
        arc(dl, cx, cy, R + 11, a2, a2 + 2.2, u32({ c2[1], c2[2], c2[3], 0.80 }), 1.6);

        -- the orb: dark glass with a silver rim
        dl:AddCircleFilled({ cx, cy }, R, u32({ 0.045, 0.042, 0.065, clear and 0.55 or 0.97 }), 48);
        dl:AddCircle({ cx, cy }, R, u32({ 0.62, 0.62, 0.70, 0.95 }), 48, 3.2);
        dl:AddCircle({ cx, cy }, R - 2.5, u32({ 0.25, 0.24, 0.32, 0.9 }), 48, 1.2);
        arc(dl, cx, cy, R, math.pi * 1.05, math.pi * 1.55, u32({ 1, 1, 1, 0.85 }), 2.0);       -- (a highlight on the rim)
        -- gloss: a faint light in the upper left
        dl:AddCircleFilled({ cx - R * 0.32, cy - R * 0.38 }, R * 0.42, u32({ 1, 1, 1, 0.05 }), 32);
        dl:AddCircleFilled({ cx - R * 0.38, cy - R * 0.45 }, R * 0.22, u32({ 1, 1, 1, 0.06 }), 24);
        -- a soft pink glow under the word, breathing
        local br = 0.10 + 0.08 * (0.5 + 0.5 * math.sin(t * 2));
        dl:AddCircleFilled({ cx, cy + 2 }, R * 0.62, u32({ NEON[1], NEON[2], NEON[3], br }), 32);

        -- "VenGo", sized to fit, Go shimmering
        local pushed = pushFont(fonts.title, 24);
        local word = 'VenGo';
        local tw, th = imgui.CalcTextSize(word);
        local fit = math.min(1.0, (R * 1.6) / math.max(tw, 1));
        imgui.SetWindowFontScale(fit);
        tw, th = imgui.CalcTextSize(word);
        local x0, y0 = cx - tw / 2, cy - th / 2;
        for i = 1, #word do
            local ch = word:sub(i, i);
            local px = x0 + imgui.CalcTextSize(word:sub(1, i - 1));
            local col = C.text;
            if i > 3 then
                local w = 0.5 + 0.5 * math.sin(t * 1.6 - i * 0.6);
                col = mix(C.hp, C.mp2, w);
            end
            dl:AddText({ px + 1, y0 + 1 }, u32({ 0, 0, 0, 0.7 }), ch);    -- (shadow)
            dl:AddText({ px, y0 }, u32(col), ch);
        end
        imgui.SetWindowFontScale(1);
        if pushed then imgui.PopFont(); end

        local ready = 0;                              -- (how many VNMs are at 100%, for the tooltip)
        for _, v in ipairs(ventures) do if (v.progress or 0) >= 100 then ready = ready + 1; end end

        -- click / drag
        imgui.SetCursorScreenPos({ cx - R - 6, cy - R - 6 });
        imgui.InvisibleButton('##vengo_mini_btn', { (R + 6) * 2, (R + 6) * 2 });
        local hovered, active, released = imgui.IsItemHovered(), imgui.IsItemActive(), imgui.IsItemDeactivated();
        if hovered then
            dl:AddCircle({ cx, cy }, R + 1, u32({ 1, 1, 1, 0.35 }), 48, 1.5);
            local tipText = running and ('VenGo: waiting for a warp NPC for ' .. (ARMED.v.zone_name or '?')) or 'VenGo';
            if ready > 0 then tipText = tipText .. ('\n%d VNM%s at 100%%'):fmt(ready, ready == 1 and '' or 's'); end
            if ALERT then tipText = tipText .. ('\nVNM: %s, %s'):fmt(ALERT.v.nm, popWords(ALERT.pop_at - os.time()):lower()); end
            imgui.SetTooltip(tipText .. '\nClick to open');
        end
        if active and imgui.IsMouseDragging(0, 3) then
            local io = imgui.GetIO();
            local dx, dy = io.MouseDelta.x or 0, io.MouseDelta.y or 0;
            MINI.x, MINI.y = MINI.x + dx, MINI.y + dy;
            MINI.dragged = true;
        end
        if released then
            if not MINI.dragged then
                config.minimized = false;
                saveSettings();
            end
            MINI.dragged = false;
        end
    end
    imgui.End();
    imgui.PopStyleVar(nv);
    imgui.PopStyleColor(nc);
end

end

local function drawUI()
    if not ui.open[1] then return; end
    if config.minimized then drawMini(); return; end
    local nc, nv = pushTheme();
    -- the resize grip in the bottom-right corner, in the panel's violet
    imgui.PushStyleColor(ImGuiCol_ResizeGrip, { NEON2[1], NEON2[2], NEON2[3], 0.25 });
    imgui.PushStyleColor(ImGuiCol_ResizeGripHovered, { NEON2[1], NEON2[2], NEON2[3], 0.60 });
    imgui.PushStyleColor(ImGuiCol_ResizeGripActive, { NEON2[1], NEON2[2], NEON2[3], 0.90 });
    nc = nc + 3;
    imgui.SetNextWindowPos({ 240, 160 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSize({ WIN_W, WIN_H }, ImGuiCond_FirstUseEver);
    pcall(imgui.SetNextWindowSizeConstraints, { MIN_W, MIN_H }, { 4000, 3000 });
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse);
    local pushed = pushFont(fonts.panel, 16);
    if imgui.Begin('VenGo##vengo_main', { true }, flags) then
        local dl = imgui.GetWindowDrawList();
        local wx, wy = imgui.GetWindowPos();
        local ww, wh = imgui.GetWindowSize();
        WIN_W, WIN_H = math.max(MIN_W, ww or WIN_W), math.max(MIN_H, wh or WIN_H);
        ROW_W = math.max(360, WIN_W - SW - 8 - MARGIN - 44);
        local z = zone();
        frame(dl, wx, wy, WIN_W, WIN_H);
        header(dl, wx + 20, wy + 18);
        sidebar(dl, wx + 22, wy + 86, SW - 36);
        topButtons(dl, wx, wy, WIN_W);
        -- the reset timer at the top right, in gold (where ChadcoreMenu shows your gil)
        do
            local rt = 'Reset in ' .. resetCountdown();
            local rw = imgui.CalcTextSize(rt);
            dl:AddText({ wx + WIN_W - 24 - rw, wy + 50 }, u32(C.gold), rt);
        end

        local cx, ctop = wx + SW + 8, wy + 80;
        local ch = WIN_H - 80 - 76;
        imgui.SetCursorScreenPos({ cx, ctop });
        -- narrower than the rows need: the content scrolls sideways
        imgui.BeginChild('##vengo_body', { MARGIN + ROW_W + 14, ch }, false,
            (ROW_W < FULL_ROW) and ImGuiWindowFlags_HorizontalScrollbar or 0);
        imgui.Indent(MARGIN);
        local ok, err = pcall(function ()
            if     ui.tab == 1 then tabVentures(z);
            elseif ui.tab == 2 then tabHelm();
            elseif ui.tab == 3 then tabFishing();
            elseif ui.tab == 4 then tabDynamis();
            elseif ui.tab == 5 then TRF.hunterTab();
            elseif ui.tab == 6 then TRF.summitTab();
            elseif ui.tab == 7 then tabSettings();
            elseif ui.tab == 8 then tabThanks();
            end
        end);
        if not ok then imgui.TextColored({ C.hp[1], C.hp[2], C.hp[3], 1 }, 'Window error: ' .. tostring(err)); end
        imgui.Spacing();
        imgui.Unindent(MARGIN);
        imgui.EndChild();

        -- the bottom: a dark box with what VenGo last did (ChadcoreMenu's description box)
        local by = wy + WIN_H - 66;
        local bx1, bx2 = cx + MARGIN - 6, wx + WIN_W - 20;
        dl:AddRectFilled({ bx1, by }, { bx2, by + 48 }, u32({ C.well[1], C.well[2], C.well[3], 0.95 }), 8);
        spaced(dl, bx1 + 10, by + 6, (TABS[ui.tab] or ''):upper(), u32(C.label), 2);
        local last = ui.last or '';
        local room = bx2 - bx1 - 20;
        if imgui.CalcTextSize(last) > room then
            while #last > 4 and imgui.CalcTextSize(last .. '...') > room do last = last:sub(1, -2); end
            last = last .. '...';
        end
        dl:AddText({ bx1 + 10, by + 24 }, u32(C.text), last);
    end
    imgui.End();
    if pushed then imgui.PopFont(); end
    imgui.PopStyleVar(nv);
    imgui.PopStyleColor(nc);
end

ashita.events.register('d3d_present', 'vengo_present', function ()
    local now = os.clock();
    tickAlert();
    tickArm(now);
    pollBoard(now);
    siteTick(now);
    loginTick();
    drawTrail();
    drawUI();
    drawAlert();
    trailTick(now);
end);

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
ashita.events.register('command', 'vengo_command', function (e)
    local args = e.command:args();
    if #args == 0 or args[1]:lower() ~= '/vengo' then return; end
    e.blocked = true;
    local cmd = (args[2] or ''):lower();
    local rest = table.concat(args, ' ', 3);

    if cmd == '' or cmd == 'show' or cmd == 'ui' then
        if config.minimized and ui.open[1] then
            config.minimized = false;
            saveSettings();
        else
            ui.open[1] = not ui.open[1];
        end
    elseif cmd == 'help' then
        msg('Usage: /vengo (window) | <nm|zone|shorthand> (warp there) | current | next | cancel | ventures | mode ace|cw | update | reload | testalert | where');
    elseif cmd == 'cancel' or cmd == 'stop' then
        ARMED = nil;
        msg('Cancelled.');
    elseif cmd == 'refresh' then
        refreshBoard();
    elseif cmd == 'next' then
        warpNext();
    elseif cmd == 'testalert' then
        local v = (rest ~= '' and resolve(rest)[1]) or pickCurrent() or ventures[1];
        if v == nil then msg('No ventures loaded to test with.'); return; end
        raiseAlert(v, '(test)');
    elseif cmd == 'where' then
        local x, y = pos();
        if x == nil then msg('Can\'t read your position right now.'); return; end
        local near = (WARPS or loadWarps()) and nearSystem() or nil;
        msg(('You are in grid %s  (%.1f, %.1f), zone %d. Warp NPC here: %s.'):fmt(worldToGrid(zone(), x, y) or '?', x, y, zone(),
            near and SYS_NAME[near] or 'none'));
        local tv = TRAIL.v or TRAIL.pick;
        if tv and tv.zone == zone() then
            local tx, ty = gridToWorld(tv.zone, tv.grid, tv.map);
            if tx then
                msg(('Trail: %s at %s -> (%.1f, %.1f), checks as grid %s, %d yalms away. Camera: %s.'):fmt(
                    tv.nm or '?', tv.grid or '?', tx, ty, worldToGrid(zone(), tx, ty) or '?', math.floor(dist2d(x, y, tx, ty) + 0.5),
                    TRAIL.cam));
            end
        end
    elseif cmd == 'ventures' then
        for _, v in ipairs(ventures) do msg(describe(v)); end
    elseif cmd == 'reload' then
        loadVentures();
        applyLive(false);
        applySite(false);
        loadWarps();
        msg(('Loaded %d ventures.'):fmt(#ventures));
    elseif cmd == 'update' then
        if loadVnmDb(true) then
            applyLive(false);
            msg('VNM drop data loaded (' .. VNMDB_FROM .. ').');
        else
            msg('Could not get the VNM drop data. Put vnms.lua from the ventures addon into the vengo folder.');
        end
    elseif cmd == 'mode' then
        local m = (args[3] or ''):upper();
        if m == 'ACE' or m == 'CW' then
            config.mode = m; saveSettings(); applyLive(false); applySite(false);
            msg('Showing ' .. m .. ' venture zones.');
        else
            msg('Use /vengo mode ace or /vengo mode cw');
        end
    elseif cmd == 'current' then
        local v = pickCurrent();
        if v == nil then msg('No ventures loaded.'); return; end
        warpTo(v);
    else
        local query = table.concat(args, ' ', 2);
        if cmd == 'nm' or cmd == 'go' then query = rest; end
        local hits = resolve(query);
        if #hits == 0 then
            msg(('No venture matches "%s". Try /vengo ventures.'):fmt(query));
        elseif #hits > 1 then
            msg(('"%s" matches more than one:'):fmt(query));
            for _, v in ipairs(hits) do msg('  ' .. describe(v)); end
        else
            warpTo(hits[1]);
        end
    end
end);

-- The venture board from the server
ashita.events.register('packet_in', 'vengo_packet', function (e)
    if e == nil or e.id ~= 0x1A3 then return; end
    local ok, err = pcall(onVenturePacket, e.data);
    if not ok then msg('Could not read the venture board: ' .. tostring(err)); end
end);

-- Every chat line: look for Populox announcing a VNM
ashita.events.register('text_in', 'vengo_text', function (e)
    if e == nil or e.message == nil or #e.message > 2048 then return; end
    local mode = bit.band(tonumber(e.mode) or 0, 0xFF);
    pcall(checkAnnouncement, mode, e.message);
    pcall(checkSealText, mode, e.message);
end);

pcall(function ()
    vana.on('logout', function () LOGIN_ASK.done, LOGIN_ASK.at = false, nil; end);
    vana.on('login', function () LOGIN_ASK.done, LOGIN_ASK.at = false, nil; end);
end);

ashita.events.register('load', 'vengo_load', function ()
    loadFonts();
    loadSettings();
    pcall(C.apply);
    loadVentures();
    loadVnmDb(true);
    loadTrends();
    loadPops();
    loadLive();
    applyLive(false);
    siteLoadCache();
    pcall(SITE.xLoadCache);
    if not loadWarps() then
        msg('Uberwarp\'s warp list wasn\'t found, so GO can\'t warp yet. See Settings > Warping.');
    end
    if VNMDB == nil then
        msg('No VNM drop data yet (download failed). See Settings > Ventures data.');
    end
end);

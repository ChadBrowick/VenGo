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
  Uberwarp by Thorny, which is installed separately. VanaCore is Vekien's project.
]]

addon.name    = 'vengo';
addon.author  = 'Chadbrowick';
addon.version = '4.37';
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
    star_zones = '',           -- starred venture zones
    star_items = '',           -- starred VNM armour pieces (item ids)
    star_chat = true,          -- chat warnings for starred VNMs
    star_sound = true,         -- and a sound
    check_updates = true,      -- look for new VenGo versions on GitHub
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

-- VenGo's shared helpers and features (stars, controller, updates, the trail's GO / STOP, the collection tabs):
-- one table, so they don't count against LuaJIT's 200 locals
local TRF = {};

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
                           'seal_check', 'seal_scan', 'cam_every', 'trail_range', 'trail_scale', 'trail_spacing', 'trail_speed', 'glow_q',
                           'star_zones', 'star_items', 'star_chat', 'star_sound', 'check_updates' }) do
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
TRF.playAlertSound = playAlertSound;

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
TRF.jsonDecode = jsonDecode;

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

local TABS = { 'VENTURES', 'HELM', 'FISHING', 'DYNAMIS', 'HUNTER', 'SUMMIT', 'VNM ARMOR', 'ULTIMATES', 'LUMORIA', 'ODIOUS CODEX', 'SETTINGS', 'SPECIAL THANKS' };
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
local GROUPS = { [7] = true, [11] = true };   -- (faint lines before the collections and before SETTINGS)

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
    local w = { go = 80 + 28, tier = 0, zone = 0, nm = 0, grid = 0, bar = 78, pct = math.max(imgui.CalcTextSize('100%'), imgui.CalcTextSize('10:00')) };
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
    TRF.ST.button(v);
    imgui.SameLine(0, 6);
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
    pcall(TRF.UP.notice);
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
    { 'Vekien', 'the VanaCore project, the client VenGo runs in' },
    { 'Yunas', 'YunaUI: the look of VenGo, and how it starts up in VanaCore' },
    { 'Commandobill, Seekey and Phatty', 'the ventures addon: the live venture board and the VNM list (drops, grid squares, notes)' },
    { 'Thorny', 'Uberwarp: the warps behind GO' },
    { 'GUST', 'the TeX Gyre Adventor font' },
    { 'Loxley (Trove)', 'the VNM Armor, Ultimates, Lumoria and Odious Codex data, and how to ask the CatsEyeXI server for currency and Lumoria progress (MIT licence, LICENSE-trove.txt)' },
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

function CAM.toTable(m)
    local out = {};
    for i = 0, 15 do
        local v = m.m[i];
        if v ~= v or v > 1e9 or v < -1e9 then return nil; end  -- (not a number)
        out[i + 1] = v;
    end
    return out;
end

-- Is it a 3D camera (perspective), not the interface's flat one?
function CAM.perspective(pm)
    return pm and math.abs(pm[16]) < 0.001 and math.abs(math.abs(pm[12]) - 1) < 0.01;
end

-- Where a view matrix's camera stands in the world
function CAM.camPos(v)
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
    local pm = CAM.toTable(CAM.mp);
    if not CAM.perspective(pm) then return; end
    local vm = CAM.toTable(mv);
    if vm == nil then return; end
    CAM.cands[#CAM.cands + 1] = { view = vm, proj = pm };
    local me = CAM.me;                                       -- (the world's camera: a few yalms from you, looking at you. Done for this frame.)
    if me then
        local cx, cy, cz = CAM.camPos(vm);
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
        local cx, cy, cz = CAM.camPos(c.view);
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

------------------------------------------------------------------------
-- VNM ARMOR: the five VNM armour sets, each tier and slot, coloured by whether you have it (green), have
-- finished it (blue), and outlined when it drops from today's ventures (pulsing when a VNM is up).
-- Set, tier, drop-zone and Storage Slip 01 data from Trove's VNM Armor plugin by Loxley (MIT licence,
-- LICENSE-trove.txt).
------------------------------------------------------------------------
TRF.AR = { owned = {}, scanAt = -1e9 };
TRF.AR.SETS = {
    { name = 'Ares', crest = 'Mountain', color = { 0.90, 0.55, 0.20, 1 }, jobs = 'WAR DRK PLD DRG RUN',
      final = { head = 16084, body = 14546, hands = 14961, legs = 15625, feet = 15711 },
      tiers = { { prefix = "Enyo's",   head = 16085, body = 14547, hands = 14962, legs = 15626, feet = 15712 },
                { prefix = "Phobos's", head = 16086, body = 14548, hands = 14963, legs = 15627, feet = 15713 },
                { prefix = "Deimos's", head = 16087, body = 14549, hands = 14964, legs = 15628, feet = 15714 } } },
    { name = 'Skadi', crest = 'Forest', color = { 0.20, 0.75, 0.20, 1 }, jobs = 'THF RNG BST COR DNC',
      final = { head = 16088, body = 14550, hands = 14965, legs = 15629, feet = 15715 },
      tiers = { { prefix = "Njord's", head = 16089, body = 14551, hands = 14966, legs = 15630, feet = 15716 },
                { prefix = "Freyr's", head = 16090, body = 14552, hands = 14967, legs = 15631, feet = 15717 },
                { prefix = "Freya's", head = 16091, body = 14553, hands = 14968, legs = 15632, feet = 15718 } } },
    { name = 'Usukane', crest = 'Desert', color = { 0.85, 0.75, 0.30, 1 }, jobs = 'MNK NIN SAM PUP',
      final = { head = 16092, body = 14554, hands = 14969, legs = 15633, feet = 15719 },
      tiers = { { prefix = 'Hoshikazu', head = 16093, body = 14555, hands = 14970, legs = 15634, feet = 15720 },
                { prefix = 'Tsukikazu', head = 16094, body = 14556, hands = 14971, legs = 15635, feet = 15721 },
                { prefix = 'Hikazu',    head = 16095, body = 14557, hands = 14972, legs = 15636, feet = 15722 } } },
    { name = 'Marduk', crest = 'Ocean', color = { 0.30, 0.55, 0.90, 1 }, jobs = 'WHM BRD SMN SCH',
      final = { head = 16096, body = 14558, hands = 14973, legs = 15637, feet = 15723 },
      tiers = { { prefix = "Anu's",   head = 16097, body = 14559, hands = 14974, legs = 15638, feet = 15724 },
                { prefix = "Ea's",    head = 16098, body = 14560, hands = 14975, legs = 15639, feet = 15725 },
                { prefix = "Enlil's", head = 16099, body = 14561, hands = 14976, legs = 15640, feet = 15726 } } },
    { name = 'Morrigan', crest = 'Tundra', color = { 0.65, 0.45, 0.80, 1 }, jobs = 'BLM RDM BLU GEO',
      final = { head = 16100, body = 14562, hands = 14977, legs = 15641, feet = 15727 },
      tiers = { { prefix = "Nemain's", head = 16101, body = 14563, hands = 14978, legs = 15642, feet = 15728 },
                { prefix = "Bodb's",   head = 16102, body = 14564, hands = 14979, legs = 15643, feet = 15729 },
                { prefix = "Macha's",  head = 16103, body = 14565, hands = 14980, legs = 15644, feet = 15730 } } },
};
TRF.AR.SLOTS = { 'head', 'body', 'hands', 'legs', 'feet' };
TRF.AR.SLOT_LABELS = { 'Head', 'Body', 'Hands', 'Legs', 'Feet' };
TRF.AR.HNM = {
    { head = 'Cerberus', body = 'Tiamat',     hands = 'Nidhogg',       legs = 'Medusa',                 feet = 'Escha Suzaku' },
    { head = 'Hydra',    body = 'Jormungand', hands = 'Aspidochelone', legs = 'Gulool Ja Ja',           feet = 'Escha Seiryu' },
    { head = 'Khimaira', body = 'Vrtra',      hands = 'Escha Genbu',   legs = 'Gurfurlur the Menacing', feet = 'Escha Byakko' },
};
TRF.AR.DROPS = {
    { 'Valkurm Dunes', 1, 'head', 'Ocean' }, { 'Buburimu Peninsula', 1, 'body', 'Mountain' },
    { 'Maze of Shakhrami', 1, 'hands', 'Tundra' }, { 'Jugner Forest', 1, 'legs', 'Forest' },
    { 'Pashhow Marshlands', 1, 'feet', 'Ocean' }, { 'Meriphataud Mountains', 1, 'hands', 'Mountain' },
    { 'Korroloka Tunnel', 2, 'body', 'Mountain' }, { 'Batallia Downs', 1, 'legs', 'Desert' },
    { 'Rolanberry Fields', 1, 'feet', 'Ocean' }, { 'Sauromugue Champaign', 1, 'head', 'Desert' },
    { 'Qufim Island', 1, 'legs', 'Tundra' }, { 'Yuhtunga Jungle', 1, 'body', 'Forest' },
    { 'Yhoator Jungle', 2, 'hands', 'Forest' }, { 'Sea Serpent Grotto', 2, 'legs', 'Ocean' },
    { "The Sanctuary of Zi'Tah", 2, 'head', 'Forest' }, { 'Eastern Altepa Desert', 2, 'body', 'Desert' },
    { 'Garlaige Citadel', 2, 'feet', 'Mountain' }, { "Crawler's Nest", 2, 'legs', 'Desert' },
    { 'Western Altepa Desert', 2, 'hands', 'Desert' }, { 'Labyrinth of Onzozo', 2, 'head', 'Tundra' },
    { 'Gustav Tunnel', 3, 'hands', 'Desert' }, { 'Toraimarai Canal', 2, 'body', 'Ocean' },
    { 'Misareaux Coast', 2, 'feet', 'Tundra' }, { 'Bostaunieux Oubliette', 3, 'feet', 'Tundra' },
    { 'Uleguerand Range', 3, 'head', 'Tundra' }, { 'Kuftal Tunnel', 3, 'legs', 'Mountain' },
    { 'The Boyahda Tree', 3, 'head', 'Mountain' }, { 'Cape Teriggan', 3, 'body', 'Desert' },
    { "Ro'Maeve", 3, 'hands', 'Forest' }, { 'Bibiki Bay', 3, 'body', 'Ocean' },
    { 'East Ronfaure [S]', 1, 'head', 'Forest', 'G-9' }, { 'West Sarutabaruta [S]', 1, 'hands', 'Forest' },
    { 'North Gustaberg [S]', 1, 'feet', 'Mountain' }, { 'Wajaom Woodlands', 1, 'body', 'Tundra', 'I-6' },
    { 'Bhaflau Thickets', 1, 'hands', 'Desert', 'H-9' }, { 'Alzadaal Undersea Ruins', 1, 'legs', 'Ocean', 'I-8', 3 },
    { 'Grauberg [S]', 2, 'head', 'Mountain' }, { 'Vunkerl Inlet [S]', 2, 'hands', 'Ocean' },
    { 'Fort Karugo-Narugo [S]', 2, 'feet', 'Forest' }, { 'East Ronfaure [S]', 2, 'body', 'Forest', 'H-9' },
    { 'Garlaige Citadel [S]', 3, 'legs', 'Forest' }, { 'Rolanberry Fields [S]', 3, 'hands', 'Ocean' },
    { 'Bhaflau Thickets', 3, 'feet', 'Desert', 'H-7' }, { 'Wajaom Woodlands', 3, 'body', 'Tundra', 'I-8' },
    { 'Aydeewa Subterrane', 3, 'legs', 'Mountain' }, { 'Caedarva Mire', 3, 'legs', 'Tundra' },
    { 'Mount Zhayolm', 3, 'feet', 'Desert' }, { 'Alzadaal Undersea Ruins', 3, 'head', 'Ocean', 'I-8', 2 },
};
TRF.AR.CREST_IDS = { Mountain = 3047, Forest = 3045, Desert = 3049, Ocean = 3046, Tundra = 3050 };
TRF.AR.SLIP_ID = 29312;
TRF.AR.SLIP_ITEMS = {
    16084, 14546, 14961, 15625, 15711, 16085, 14547, 14962, 15626, 15712, 16086, 14548, 14963, 15627, 15713,
    16087, 14549, 14964, 15628, 15714, 16088, 14550, 14965, 15629, 15715, 16089, 14551, 14966, 15630, 15716,
    16090, 14552, 14967, 15631, 15717, 16091, 14553, 14968, 15632, 15718, 16092, 14554, 14969, 15633, 15719,
    16093, 14555, 14970, 15634, 15720, 16094, 14556, 14971, 15635, 15721, 16095, 14557, 14972, 15636, 15722,
    16096, 14558, 14973, 15637, 15723, 16097, 14559, 14974, 15638, 15724, 16098, 14560, 14975, 15639, 15725,
    16099, 14561, 14976, 15640, 15726, 16100, 14562, 14977, 15641, 15727, 16101, 14563, 14978, 15642, 15728,
    16102, 14564, 14979, 15643, 15729, 16103, 14565, 14980, 15644, 15730,
};
TRF.AR.BAGS = { { 0, 'Inventory' }, { 1, 'Safe' }, { 2, 'Storage' }, { 4, 'Locker' }, { 5, 'Satchel' }, { 6, 'Sack' },
    { 7, 'Case' }, { 8, 'Wardrobe' }, { 9, 'Safe 2' }, { 10, 'Wardrobe 2' }, { 11, 'Wardrobe 3' }, { 12, 'Wardrobe 4' },
    { 13, 'Wardrobe 5' }, { 14, 'Wardrobe 6' }, { 15, 'Wardrobe 7' }, { 16, 'Wardrobe 8' } };

-- the zones each piece drops in (in a function: its loop counters would count against the file's 200 locals)
(function ()
    TRF.AR.itemZones = {};
    for _, d in ipairs(TRF.AR.DROPS) do
        for _, set in ipairs(TRF.AR.SETS) do
            local id = set.tiers[d[2]][d[3]];
            TRF.AR.itemZones[id] = TRF.AR.itemZones[id] or {};
            local label = d[1] .. (d[5] and (' (' .. (d[6] and ('Map ' .. d[6] .. ' ') or '') .. d[5] .. ')') or '');
            table.insert(TRF.AR.itemZones[id], { label = label, zone = d[1], grid = d[5] });
        end
    end
end)();

-- What you have, in every bag and in Storage Slip 01 (every 2 s while the tab is open)
-- Your bags, read a little each frame (about two bags a frame, every 2 s, only while a collection tab is open)
-- and shared by VNM ARMOR, ULTIMATES and ODIOUS CODEX. Reading all 1,300-odd slots at once made a stutter.
TRF.BAG = { ids = { 0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 },
            names = { [0] = 'Inventory', 'Safe', 'Storage', nil, 'Locker', 'Satchel', 'Sack', 'Case', 'Wardrobe', 'Safe 2',
                      'Wardrobe 2', 'Wardrobe 3', 'Wardrobe 4', 'Wardrobe 5', 'Wardrobe 6', 'Wardrobe 7', 'Wardrobe 8' },
            bi = 1, slot = 0, max = nil, cur = nil, ready = nil, gen = 0, wantAt = -1e9, restAt = -1e9,
            EXTRA = { [29312] = true, [30840] = true } };   -- (Storage Slip 01 and the Odious Codex: their bits are read too)
function TRF.BAG.want() TRF.BAG.wantAt = os.clock(); end
function TRF.BAG.bytes(ex, n)                                    -- (an item's extra data as a string, whatever form it comes in)
    if type(ex) == 'string' then return ex:sub(1, n); end
    local out = {};
    for i = 0, n - 1 do
        local ok, v = pcall(function () return ex[i]; end);
        v = (ok and tonumber(v)) or 0;
        if v < 0 then v = v + 256; end
        out[#out + 1] = string.char(v % 256);
    end
    return table.concat(out);
end
function TRF.BAG.step()
    local B = TRF.BAG;
    local now = os.clock();
    if now - B.wantAt > 3 then return; end                      -- (no collection tab open: nothing to do)
    if B.cur == nil then
        if now < B.restAt then return; end
        B.cur, B.bi, B.slot, B.max = { count = {}, where = {}, extra = {} }, 1, 0, nil;
    end
    local budget = 170;                                          -- (slots per frame)
    pcall(function ()
        local inv = mm():GetInventory();
        while budget > 0 and B.bi <= #B.ids do
            local bag = B.ids[B.bi];
            if B.max == nil then B.max = inv:GetContainerCountMax(bag) or 0; end
            local it = (B.slot <= B.max) and inv:GetContainerItem(bag, B.slot) or nil;
            if it == nil then
                B.bi, B.slot, B.max = B.bi + 1, 0, nil;
            else
                local id = it.Id;
                if id ~= 0 and id ~= 65535 then
                    B.cur.count[id] = (B.cur.count[id] or 0) + (tonumber(it.Count) or 1);
                    B.cur.where[id] = B.cur.where[id] or B.names[bag] or 'Bag';
                    if B.EXTRA[id] and B.cur.extra[id] == nil then B.cur.extra[id] = B.bytes(it.Extra, 24); end
                end
                B.slot = B.slot + 1;
                budget = budget - 1;
            end
        end
    end);
    if B.bi > #B.ids then                                        -- (a full pass: publish it, rest 2 s)
        B.ready, B.cur = B.cur, nil;
        B.gen = B.gen + 1;
        B.restAt = now + 2;
    end
end

function TRF.AR.scan()
    local B = TRF.BAG;
    B.want();
    if B.ready == nil or TRF.AR.gen == B.gen then return; end
    TRF.AR.gen = B.gen;
    local found = {};
    local watch = TRF.AR.watch;
    if watch == nil then
        watch = {};
        for _, set in ipairs(TRF.AR.SETS) do
            for t_ = 1, 3 do for _, sl in ipairs(TRF.AR.SLOTS) do watch[set.tiers[t_][sl]] = true; end end
            for _, sl in ipairs(TRF.AR.SLOTS) do watch[set.final[sl]] = true; end
        end
        TRF.AR.watch = watch;
    end
    for id in pairs(watch) do if B.ready.where[id] then found[id] = B.ready.where[id]; end end
    local ex = B.ready.extra[TRF.AR.SLIP_ID];
    if ex then
        for k, sid in ipairs(TRF.AR.SLIP_ITEMS) do
            local b = ex:byte(math.floor((k - 1) / 8) + 1) or 0;
            if bit.band(b, bit.lshift(1, (k - 1) % 8)) ~= 0 then found[sid] = found[sid] or 'Storage Slip 01'; end
        end
    end
    TRF.AR.owned = found;
end

-- Pieces that drop from today's ventures: 1 on the board, 2 at 100% or announced
function TRF.AR.hot()
    local H = TRF.AR.hotCache;
    local sig = #ventures .. (ALERT and tostring(ALERT.v) or '');
    for _, v in ipairs(ventures) do sig = sig .. '|' .. tostring(v.zone) .. (v.grid or '') .. (v.progress or 0); end
    if H and H.sig == sig then return H.hot, H.why; end
    if TRF.AR.dropZK == nil then
        TRF.AR.dropZK = {};
        for i, d in ipairs(TRF.AR.DROPS) do TRF.AR.dropZK[i] = zoneKey(d[1]); end
    end
    local hot, why = {}, {};
    for _, v in ipairs(ventures) do
        if v.key ~= 'hvnm' and v.zone_name then
            local zk = zoneKey(v.zone_name);
            local lvl = ((v.progress or 0) >= 100 or (ALERT and ALERT.v == v)) and 2 or 1;
            local matches = {};
            for i, d in ipairs(TRF.AR.DROPS) do if TRF.AR.dropZK[i] == zk then matches[#matches + 1] = d; end end
            if #matches > 1 and v.grid then                       -- (a zone listed twice: the one at the VNM's square)
                local m2 = {};
                for _, d in ipairs(matches) do if d[5] and d[5]:upper() == tostring(v.grid):upper() then m2[#m2 + 1] = d; end end
                if #m2 > 0 then matches = m2; end
            end
            for _, d in ipairs(matches) do
                for _, set in ipairs(TRF.AR.SETS) do
                    local id = set.tiers[d[2]][d[3]];
                    if lvl > (hot[id] or 0) then hot[id] = lvl; end
                    why[id] = why[id] or {};
                    table.insert(why[id], ('%s  (%s, %d%%)'):fmt(v.nm or '?', v.zone_name, v.progress or 0));
                end
            end
        end
    end
    TRF.AR.hotCache = { sig = sig, hot = hot, why = why };
    return hot, why;
end

TRF.AR.names = {};
function TRF.AR.name(id)
    local c = TRF.AR.names[id];
    if c then return c; end
    local n = nil;
    pcall(function () local r = AshitaCore:GetResourceManager():GetItemById(id); n = r and r.Name[1]; end);
    n = n or ('Item ' .. id);
    TRF.AR.names[id] = n;
    return n;
end

TRF.armorTab = function()
    TRF.AR.scan();
    local hot, why = TRF.AR.hot();
    local owned = TRF.AR.owned;
    local have, total = 0, 0;
    for _, set in ipairs(TRF.AR.SETS) do
        for t_ = 1, 3 do for _, sl in ipairs(TRF.AR.SLOTS) do
            total = total + 1;
            if owned[set.tiers[t_][sl]] or owned[set.final[sl]] then have = have + 1; end
        end end
    end
    section(('VNM Armor  %d / %d'):fmt(have, total));

    local dl = imgui.GetWindowDrawList();
    local x0, y0 = imgui.GetCursorScreenPos();
    -- Each set in its own panel (its colour along the top, its name and T1 T2 T3 inside), with a clear gap between
    -- sets and a small one between tiers. The cells fill the width: a wider window gives bigger icons.
    local lh = imgui.GetTextLineHeight();
    local labelW = 0;                                            -- (as wide as the longest slot name really is, plus room)
    for _, l in ipairs(TRF.AR.SLOT_LABELS) do labelW = math.max(labelW, spacedW(l:upper(), 1)); end
    labelW = labelW + 16;
    local setGap = 12;
    local pad = 7;
    local tg = 4;                                                -- (between tiers)
    local cell = math.floor(math.max(30, math.min(46, (ROW_W - labelW - setGap * 4 - 5 * (pad * 2 + tg * 2)) / 15)));
    local setW = cell * 3 + tg * 2 + pad * 2;
    local headH = lh * 2 + 14;
    local gridH = 5 * cell + 4 * tg;
    local panelH = headH + gridH + pad + 2;
    local now = os.clock();
    local function setX(si) return x0 + labelW + (si - 1) * (setW + setGap); end
    local function cellX(si, t_) return setX(si) + pad + (t_ - 1) * (cell + tg); end
    local gy = y0 + headH;
    local mx_, my_ = imgui.GetMousePos();

    for si, set in ipairs(TRF.AR.SETS) do
        local px = setX(si);
        local c_ = set.color;
        local over = mx_ >= px and mx_ < px + setW and my_ >= y0 and my_ < y0 + panelH;
        dl:AddRectFilled({ px, y0 }, { px + setW, y0 + panelH }, u32({ C.panel[1], C.panel[2], C.panel[3], 0.95 }), 10);
        dl:AddRectFilled({ px + 1, y0 + 1 }, { px + setW - 1, y0 + lh + 12 }, u32({ c_[1], c_[2], c_[3], 0.12 }), 9);
        dl:AddRect({ px, y0 }, { px + setW, y0 + panelH }, u32({ 1, 1, 1, over and 0.12 or 0.06 }), 10, C.rall, 1);
        -- the name (hover: crest, jobs and crest zones), how many of its 15 you have, and T1 T2 T3
        local n_ = 0;
        for t_ = 1, 3 do for _, sl in ipairs(TRF.AR.SLOTS) do if owned[set.tiers[t_][sl]] or owned[set.final[sl]] then n_ = n_ + 1; end end end
        local cnt = ('%d/15'):fmt(n_);
        local tw = imgui.CalcTextSize(set.name);
        dl:AddCircleFilled({ px + pad + 5, y0 + 6 + lh / 2 }, 3.5, u32(c_), 12);
        dl:AddText({ px + pad + 14, y0 + 6 }, u32(C.text), set.name);
        local cntW = imgui.CalcTextSize(cnt);
        if pad + 14 + tw + 10 + cntW <= setW - pad then           -- (only when there's room beside the name)
            dl:AddText({ px + setW - pad - cntW, y0 + 6 }, u32(n_ >= 15 and C.green or C.lav), cnt);
        end
        imgui.SetCursorScreenPos({ px, y0 });
        imgui.InvisibleButton('##vengo_arset' .. si, { setW, lh + 10 });
        if imgui.IsItemHovered() then
            imgui.BeginTooltip();
            local ci = itemIcon(TRF.AR.CREST_IDS[set.crest]);
            if ci then imgui.Image(ci.ptr, { 20, 20 }); imgui.SameLine(0, 6); end
            imgui.TextColored(set.color, set.name .. ' (' .. set.crest .. ' Crest)');
            imgui.TextColored(n_ >= 15 and C.green or C.lav, ('%d of 15 pieces'):fmt(n_));
            imgui.TextColored(C.muted, set.jobs);
            imgui.Separator();
            imgui.TextColored(C.text, 'Crest zones:');
            local seen = {};
            for _, d in ipairs(TRF.AR.DROPS) do
                if d[4] == set.crest and not seen[d[1]] then seen[d[1]] = true; imgui.TextColored(C.muted, '  ' .. d[1]); end
            end
            imgui.EndTooltip();
        end
        for t_ = 1, 3 do
            local tl = 'T' .. t_;
            local tx = cellX(si, t_) + (cell - spacedW(tl, 1)) / 2;
            spaced(dl, tx, y0 + lh + 12, tl, u32(C.label), 1);
        end
    end
    local hoverInfo = nil;
    for r, sl in ipairs(TRF.AR.SLOTS) do
        local ry = gy + (r - 1) * (cell + tg);
        spaced(dl, x0, ry + (cell - lh) / 2, TRF.AR.SLOT_LABELS[r]:upper(), u32(C.label), 1);
        for si, set in ipairs(TRF.AR.SETS) do
            local complete = owned[set.final[sl]] ~= nil;
            for t_ = 1, 3 do
                local id = set.tiers[t_][sl];
                local cx = cellX(si, t_);
                local over = mx_ >= cx and mx_ < cx + cell and my_ >= ry and my_ < ry + cell;
                TRF.card(dl, cx, ry, cell, cell, complete and 'on' or (owned[id] and 'own') or nil, over, 6);
                TRF.icon(dl, id, cx + 3, ry + 3, cell - 6, (complete or owned[id]) and 1 or 0.55);
                local h = hot[id];
                if h == 2 then
                    local pulse = math.abs(math.sin(now * 3));
                    dl:AddRect({ cx - 1, ry - 1 }, { cx + cell + 1, ry + cell + 1 }, u32({ NEON2[1], NEON2[2], NEON2[3], 0.25 * pulse }), 7, C.rall, 5);
                    dl:AddRect({ cx, ry }, { cx + cell, ry + cell }, u32({ NEON2[1], NEON2[2], NEON2[3], 0.6 + 0.4 * pulse }), 6, C.rall, 2);
                elseif h == 1 then
                    dl:AddRect({ cx, ry }, { cx + cell, ry + cell }, u32({ C.gold[1], C.gold[2], C.gold[3], 0.65 }), 6, C.rall, 1.2);
                end
                if TRF.ST.itemStarred(id) then
                    dl:AddCircleFilled({ cx + cell - 8, ry + 8 }, 7, u32({ 0, 0, 0, 0.55 }), 14);
                    TRF.ST.draw(dl, cx + cell - 8, ry + 8, 6, C.gold, true);
                end
                imgui.SetCursorScreenPos({ cx, ry });
                if imgui.InvisibleButton(('##vengo_ar%d'):format(id), { cell, cell }) then TRF.ST.toggleItem(id); end
                if imgui.IsItemHovered() then
                    hoverInfo = { id = id, set = set, tier = t_, slot = sl, complete = complete };
                end
            end
        end
    end
    imgui.SetCursorScreenPos({ x0, y0 + panelH + 10 });
    imgui.Dummy({ ROW_W, 1 });

    if hoverInfo then
        local H_ = hoverInfo;
        imgui.BeginTooltip();
        imgui.TextColored(C.text, TRF.AR.name(H_.id));
        if H_.complete then imgui.TextColored({ 0.45, 0.65, 1, 1 }, '  Completed: ' .. TRF.AR.name(H_.set.final[H_.slot]));
        elseif owned[H_.id] then imgui.TextColored(C.green, '  Owned (' .. tostring(owned[H_.id]) .. ')');
        else imgui.TextColored(C.muted, '  Not owned'); end
        imgui.Separator();
        imgui.TextColored(C.muted, 'Drop zones:');
        for _, z in ipairs(TRF.AR.itemZones[H_.id] or {}) do imgui.TextColored(C.text, '  ' .. z.label); end
        if why[H_.id] then
            imgui.Separator();
            imgui.TextColored({ 1, 0.85, 0.3, 1 }, 'On today\'s board:');
            for _, w in ipairs(why[H_.id]) do imgui.TextColored(C.text, '  ' .. w); end
        end
        local hn = TRF.AR.HNM[H_.tier] and TRF.AR.HNM[H_.tier][H_.slot];
        if hn then imgui.Separator(); imgui.TextColored(C.muted, 'Also drops from:'); imgui.TextColored(C.gold, '  ' .. hn); end
        imgui.Separator();
        imgui.TextColored(TRF.ST.itemStarred(H_.id) and C.gold or C.lav, TRF.ST.itemStarred(H_.id)
            and 'Starred: you\'re warned when a venture that drops it is up. Click to unstar.'
            or 'Click to star: VenGo warns you when a venture that drops it is up.');
        imgui.EndTooltip();
    end

    -- legend
    local lx, ly = imgui.GetCursorScreenPos();
    local function key(x, kind, outline, text)
        TRF.card(dl, x, ly + 2, 14, 14, kind, false, 4);
        if outline then dl:AddRect({ x, ly + 2 }, { x + 14, ly + 16 }, u32(outline), 4, C.rall, 1.5); end
        dl:AddText({ x + 20, ly + 1 }, u32(C.muted), text);
        return x + 20 + imgui.CalcTextSize(text) + 22;
    end
    local kx = key(lx, 'own', nil, 'Owned');
    kx = key(kx, 'on', nil, 'Completed');
    kx = key(kx, nil, { C.gold[1], C.gold[2], C.gold[3], 0.8 }, 'Drops from today\'s ventures');
    key(kx, nil, { NEON2[1], NEON2[2], NEON2[3], 1 }, 'VNM up (pulsing)');
    imgui.Dummy({ ROW_W, 20 });
    hint('Click a piece to star it: VenGo warns you (chat and sound) at 90%, 100% and before the pop whenever a venture that drops it is up. Hover a piece for its drop zones; hover a set name for its crest and jobs.');
end

------------------------------------------------------------------------
-- ULTIMATES, LUMORIA and ODIOUS CODEX: collection tabs. Their data (items, weapons, stages, currencies, bits)
-- comes from Trove's plugins by Loxley (MIT licence, LICENSE-trove.txt). Currency totals and the Lumoria data are
-- asked of the CatsEyeXI server the way Trove asks for them (packet 0x1A4); the rest is read from your bags.
------------------------------------------------------------------------
TRF.LU = TRF.LU or {};
TRF.TV = { cur = {}, curAt = nil, curPending = nil, lum = nil, lumAt = nil, lumPending = nil };
TRF.TV.PACKET = 0x1A4;
-- Ask the server for something (Trove's request: byte 4 = what, byte 6 = which plugin)
function TRF.TV.ask(action, plugin)
    local p = {};
    for i = 1, 64 do p[i] = 0; end
    p[5] = action;
    p[7] = plugin or 0;
    pcall(function () AshitaCore:GetPacketManager():AddOutgoingPacket(TRF.TV.PACKET, p); end);
end
function TRF.TV.askCurrency(force)
    local T = TRF.TV;
    local now = os.clock();
    if T.curPending and now - T.curPending < 5 then return; end
    if not force and T.curAt and now - T.curAt < 60 then return; end
    T.curPending = now;
    T.ask(7);                                                    -- (GET_CURRENCY)
end
function TRF.TV.askLumoria(force)
    local T = TRF.TV;
    local now = os.clock();
    if T.lumPending and now - T.lumPending < 5 then return; end
    if not force and T.lumAt and now - T.lumAt < 60 then return; end
    T.lumPending = now;
    T.ask(17, 0);                                                -- (GET_PLUGIN_DATA, Lumoria)
end
-- The server's answers
function TRF.TV.packet(d)
    local T = TRF.TV;
    local function u8(o) return d:byte(o + 1) or 0; end
    local function u16(o) return u8(o) + u8(o + 1) * 256; end
    local function i32(o)
        local v = u8(o) + u8(o + 1) * 256 + u8(o + 2) * 65536 + u8(o + 3) * 16777216;
        if v >= 0x80000000 then v = v - 0x100000000; end
        return v;
    end
    local function str(o, n)
        local s = d:sub(o + 1, o + n);
        return (s:gsub('%z.*$', ''));
    end
    local action = u8(0x04);
    if action == 6 then                                          -- (a currency line)
        local name = str(0x18, 23);
        if name ~= '' then
            T.cur[name] = { total = i32(0x30), icon = u16(0x06), section = str(0x08, 15), breakdown = str(0x34, 71) };
        end
    elseif action == 2 and T.curPending then                     -- (the end of the list)
        T.curAt, T.curPending = os.clock(), nil;
    elseif action == 17 and u8(0x05) == 0 then                   -- (Lumoria)
        local L = { buffs = u16(0x06), torques = u8(0x08), weapons = u8(0x09),
                    homam = {}, nashira = {}, omega = {}, ultima = {}, organInv = {}, organVis = {} };
        for i = 1, 5 do
            L.homam[i] = u8(0x09 + i); L.nashira[i] = u8(0x0E + i);
            L.omega[i] = u8(0x13 + i); L.ultima[i] = u8(0x18 + i);
        end
        for i = 1, 12 do L.organInv[i] = u8(0x1D + i); L.organVis[i] = u8(0x1D + 12 + i); end
        local lb = 0x1D + 24 + 1;
        L.torqueLoc, L.weaponLoc, L.homamLoc, L.nashiraLoc = u8(lb), u8(lb + 1), u8(lb + 2), u8(lb + 3);
        T.lum, T.lumAt, T.lumPending = L, os.clock(), nil;
    end
end
function TRF.TV.total(name)
    local e = TRF.TV.cur[name];
    return e and e.total or nil;
end

-- Your bags: which of a set of items you have, and how many (every 2 s while a tab is open)
TRF.BAGS = { 0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
function TRF.scanBags(watch, fn)                                 -- (from the shared reading above)
    local B = TRF.BAG;
    B.want();
    local have, count = {}, {};
    if B.ready == nil then return have, count, false; end
    for id, n in pairs(B.ready.count) do
        if watch == nil or watch[id] then have[id] = true; count[id] = n; end
    end
    if fn then for id, ex in pairs(B.ready.extra) do fn(id, { Extra = ex }); end end
    return have, count, true;
end

-- Small drawing pieces shared by the three tabs
function TRF.icon(dl, id, x, y, sz, alpha)
    local ic = itemIcon(id);
    if ic then
        pcall(dl.AddImage, dl, ic.ptr, { x, y }, { x + sz, y + sz }, { 0, 0 }, { 1, 1 }, u32({ 1, 1, 1, alpha or 1 }));
    else
        dl:AddRectFilled({ x, y }, { x + sz, y + sz }, u32({ 1, 1, 1, 0.06 * (alpha or 1) }), 3);
    end
end
function TRF.itemTip(id, lines)
    imgui.BeginTooltip();
    local ic = itemIcon(id);
    if ic then imgui.Image(ic.ptr, { 32, 32 }); imgui.SameLine(0, 8); end
    imgui.TextColored(C.text, TRF.AR.name(id));
    pcall(function ()
        local r = AshitaCore:GetResourceManager():GetItemById(id);
        if r and r.Description and r.Description[1] and r.Description[1] ~= '' then
            imgui.PushTextWrapPos(imgui.GetCursorPosX() + 320);
            imgui.TextColored(C.muted, r.Description[1]);
            imgui.PopTextWrapPos();
        end
    end);
    for _, l in ipairs(lines or {}) do imgui.TextColored(l[2] or C.text, l[1]); end
    imgui.EndTooltip();
end
-- A hover area over a spot just drawn (the tooltip comes from the caller)
function TRF.hot(id, x, y, w, h)
    local cx, cy = imgui.GetCursorScreenPos();
    imgui.SetCursorScreenPos({ x, y });
    local clicked = imgui.InvisibleButton(id, { w, h });
    local hov = imgui.IsItemHovered();
    imgui.SetCursorScreenPos({ cx, cy });
    return hov, clicked;
end
-- A thin rounded bar like the rest of VenGo (pink to violet; green when it's full), the numbers to its right
function TRF.bar(dl, x, y, w, h, have, need, fill)
    local pct = (need > 0) and math.min(have / need, 1) or 0;
    local s = ('%s / %s'):fmt(TRF.num(math.min(have, need)), TRF.num(need));
    local tw = imgui.CalcTextSize(s);
    local lh = imgui.GetTextLineHeight();
    local bw = math.max(20, w - tw - 10);
    local ph = math.min(6, h);
    local cy = y + h / 2;
    dl:AddRectFilled({ x, cy - ph / 2 }, { x + bw, cy + ph / 2 }, u32({ 0.20, 0.19, 0.25, 1 }), ph / 2);
    if pct > 0 then
        if pct >= 1 then
            dl:AddRectFilled({ x, cy - ph / 2 }, { x + bw, cy + ph / 2 }, u32(C.green), ph / 2);
        else
            local ok = pcall(function ()
                dl:AddRectFilledMultiColor({ x, cy - ph / 2 }, { x + bw * pct, cy + ph / 2 }, u32(C.hp), u32(C.mp2), u32(C.mp2), u32(C.hp));
            end);
            if not ok then dl:AddRectFilled({ x, cy - ph / 2 }, { x + bw * pct, cy + ph / 2 }, u32(NEON), ph / 2); end
        end
    end
    dl:AddText({ x + bw + 8, cy - lh / 2 }, u32(pct >= 1 and C.green or C.lav), s);
end
-- A dark rounded panel with a faint edge. kind: 'own' (green), 'done' (gold), 'on' (blue), else plain.
-- Hovered: the pink glow and bright left edge the venture list uses.
TRF.KINDS = { own = { 0.48, 0.92, 0.58 }, done = { 0.96, 0.76, 0.32 }, on = { 0.62, 0.80, 1.00 } };
function TRF.card(dl, x, y, w, h, kind, hov, r)
    r = r or 8;
    dl:AddRectFilled({ x, y }, { x + w, y + h }, u32({ C.well[1], C.well[2], C.well[3], 0.95 }), r);
    local k = TRF.KINDS[kind or ''];
    if k then dl:AddRectFilled({ x, y }, { x + w, y + h }, u32({ k[1], k[2], k[3], 0.10 }), r); end
    if hov then
        pcall(function ()
            dl:AddRectFilledMultiColor({ x, y }, { x + math.min(w, 260), y + h },
                u32({ NEON2[1], NEON2[2], NEON2[3], 0.22 }), u32({ NEON2[1], NEON2[2], NEON2[3], 0 }),
                u32({ NEON2[1], NEON2[2], NEON2[3], 0 }), u32({ NEON2[1], NEON2[2], NEON2[3], 0.22 }));
        end);
        dl:AddRectFilled({ x, y + 3 }, { x + 3, y + h - 3 }, u32({ NEON2[1], NEON2[2], NEON2[3], 1 }), 1);
    end
    dl:AddRect({ x, y }, { x + w, y + h }, u32(k and { k[1], k[2], k[3], 0.45 } or { 1, 1, 1, hov and 0.14 or 0.06 }), r, C.rall, 1);
end
function TRF.num(n)
    local s = tostring(math.floor(n or 0));
    return (s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', ''));
end
function TRF.header(dl, text, col, count)
    imgui.Spacing();
    local x, y = imgui.GetCursorScreenPos();
    local lh = imgui.GetTextLineHeight();
    local dx = x;
    if col then dl:AddCircleFilled({ x + 4, y + lh / 2 + 1 }, 3.5, u32({ col[1], col[2], col[3], 1 }), 12); dx = x + 14; end
    local tw = spaced(dl, dx, y, text:upper(), u32(C.label), 2);
    local cw = 0;
    if count then
        cw = imgui.CalcTextSize(count);
        dl:AddText({ x + ROW_W - cw, y }, u32(C.lav), count);
    end
    dl:AddLine({ dx + tw + 14, y + lh / 2 }, { x + ROW_W - cw - (count and 12 or 0), y + lh / 2 }, u32({ 1, 1, 1, 0.06 }), 1);
    imgui.Dummy({ ROW_W, lh + 8 });
end
function TRF.refreshRow(what, at, pending, onClick)
    local age = at and ('updated ' .. math.floor((os.clock() - at) / 60) .. ' min ago') or (pending and 'asking the server...' or 'not loaded yet');
    imgui.TextColored(C.muted, what .. ': ' .. age);
    imgui.SameLine(0, 14);
    if button('REFRESH##vengo_ref_' .. what, { 0, 0 }, true, true) then onClick(); end
end

------------------------------------------------------------------------
-- ODIOUS CODEX: which Dynamis pop items and zone drops your Odious Codex holds (read from the item itself)
------------------------------------------------------------------------
TRF.CX = { open = {}, at = -1e9, masks = nil, has = false, ID = 30840 };
function TRF.CX.scan()
    local X = TRF.CX;
    TRF.BAG.want();
    if TRF.BAG.ready == nil or X.gen == TRF.BAG.gen then return; end
    X.gen = TRF.BAG.gen;
    X.has, X.masks = false, { A = 0, B = 0, C = 0, D = 0 };
    TRF.scanBags({ [X.ID] = true }, function (id, it)
        if id ~= X.ID or X.has then return; end
        X.has = true;
        local ex = it.Extra;
        local function b(i)
            if type(ex) == 'string' then return ex:byte(i + 1) or 0; end
            local ok, v = pcall(function () return ex[i]; end);
            v = (ok and tonumber(v)) or 0;
            if v < 0 then v = v + 256; end
            return v;
        end
        local function u32_(o) return b(o) + b(o + 1) * 256 + b(o + 2) * 65536 + b(o + 3) * 16777216; end
        X.masks = { A = u32_(0), B = u32_(4), C = u32_(8), D = u32_(12) };
    end);
end
function TRF.CX.got(e)
    local m = TRF.CX.masks and TRF.CX.masks[e.mask] or 0;
    return bit.band(m, bit.lshift(1, e.bit)) ~= 0;                -- (bit numbering as Trove reads it)
end
TRF.cxTab = function()
    local X = TRF.CX;
    X.scan();
    local all, have = 0, 0;
    for _, z in ipairs(X.ZONES) do
        for _, e in ipairs(z.pops) do all = all + 1; if X.got(e) then have = have + 1; end end
        for _, e in ipairs(z.drops or {}) do all = all + 1; if X.got(e) then have = have + 1; end end
    end
    section(('Odious Codex  %d / %d'):fmt(have, all));
    if not X.has then
        hint('No Odious Codex found in your bags or wardrobes. It records the Dynamis pop items and drops you\'ve collected.');
        return;
    end
    local dl = imgui.GetWindowDrawList();
    local lh = imgui.GetTextLineHeight();
    for zi, z in ipairs(X.ZONES) do
        local zh, zt = 0, #z.pops + #(z.drops or {});
        for _, e in ipairs(z.pops) do if X.got(e) then zh = zh + 1; end end
        for _, e in ipairs(z.drops or {}) do if X.got(e) then zh = zh + 1; end end
        local t = z.tint or { 0.14, 0.12, 0.20 };
        local col = { math.min(1, t[1] * 4), math.min(1, t[2] * 4), math.min(1, t[3] * 4) };
        local x, y = imgui.GetCursorScreenPos();
        local h = 34;
        local hov, clicked = TRF.hot('##vengo_cxz' .. zi, x, y, ROW_W, h);
        TRF.card(dl, x, y, ROW_W, h, (zh >= zt and zt > 0) and 'own' or nil, hov or X.open[zi]);
        local ax, ay = x + 16, y + h / 2;                    -- (an arrow: right when closed, down when open)
        if X.open[zi] then dl:AddTriangleFilled({ ax - 4, ay - 2 }, { ax + 4, ay - 2 }, { ax, ay + 3 }, u32(C.lav));
        else dl:AddTriangleFilled({ ax - 2, ay - 4 }, { ax + 3, ay }, { ax - 2, ay + 4 }, u32(C.lav)); end
        dl:AddCircleFilled({ x + 30, ay }, 3.5, u32({ col[1], col[2], col[3], 1 }), 12);
        dl:AddText({ x + 42, ay - lh / 2 }, u32(C.text), z.name);
        TRF.bar(dl, x + ROW_W - 230, y, 216, h, zh, zt);
        if clicked then X.open[zi] = not X.open[zi]; end
        imgui.Dummy({ ROW_W, h + 4 });
        if X.open[zi] then
            local cols = { { 'Pop items', z.pops } };
            if #(z.drops or {}) > 0 then cols[2] = { 'Zone drops', z.drops }; end
            local cw = (#cols == 2) and (ROW_W - 10) / 2 or ROW_W;
            local x0, y0 = imgui.GetCursorScreenPos();
            local maxY = y0;
            for ci, c in ipairs(cols) do
                local cx = x0 + (ci - 1) * (cw + 10);
                local cy = y0;
                local n = 0;
                for _, e in ipairs(c[2]) do if X.got(e) then n = n + 1; end end
                spaced(dl, cx, cy, ('%s  %d/%d'):fmt(c[1]:upper(), n, #c[2]), u32(C.label), 1.5);
                cy = cy + lh + 6;
                for ei, e in ipairs(c[2]) do
                    local got = X.got(e);
                    local rh = 28;
                    local rhov = TRF.hot(('##vengo_cx%d_%d_%d'):format(zi, ci, ei), cx, cy, cw, rh);
                    TRF.card(dl, cx, cy, cw, rh, got and 'own' or nil, rhov, 6);
                    TRF.icon(dl, e.id, cx + 3, cy + 2, 24, got and 1 or 0.45);
                    dl:AddText({ cx + 34, cy + (rh - lh) / 2 }, u32(got and C.text or C.muted), e.name);
                    if e.spawns then
                        local sw_ = imgui.CalcTextSize(e.spawns);
                        if sw_ < cw - 180 then dl:AddText({ cx + cw - sw_ - 8, cy + (rh - lh) / 2 }, u32({ C.muted[1], C.muted[2], C.muted[3], 0.8 }), e.spawns); end
                    end
                    if rhov then TRF.itemTip(e.id, { { got and 'In your Codex' or 'Not in your Codex yet', got and C.green or C.muted }, { 'Spawns: ' .. tostring(e.spawns or '?'), C.gold } }); end
                    cy = cy + rh + 2;
                end
                if cy > maxY then maxY = cy; end
            end
            imgui.SetCursorScreenPos({ x0, maxY + 6 });
            imgui.Dummy({ ROW_W, 1 });
        end
    end
    hint('Click a zone to see its items. Read from the Odious Codex item itself (any bag or wardrobe).');
end

------------------------------------------------------------------------
-- ULTIMATES: relic weapons (Dynamis currency per stage), Mythic and Ergon, and the CW Incursion weapons
------------------------------------------------------------------------
TRF.UL = { view = 'relic', at = -1e9, have = {}, count = {} };
TRF.UL.CUR_NAME = { BYNE = 'Byne Bills', SHELL = 'Whiteshells', BRONZE = 'Bronzepieces' };
TRF.UL.BAR_ICONS = { ['Alexandrite'] = 2488, ['H-P Bayld'] = 8798 };
function TRF.UL.scan()
    local U = TRF.UL;
    TRF.BAG.want();
    if TRF.BAG.ready == nil or U.gen == TRF.BAG.gen then return; end
    U.gen = TRF.BAG.gen;
    if U.watch == nil then
        local w = {};
        for _, r in ipairs(U.RELICS) do w[r.finalId] = true; for _, s in ipairs(r.stages) do w[s.weaponId] = true; end end
        for _, c in ipairs(U.EXTRA_CARDS) do
            for _, m in ipairs(c.materials or {}) do w[m.id] = true; end
            for _, row in ipairs(c.materialRows or {}) do for _, m in ipairs(row.items) do w[m.id] = true; end end
            for _, m in ipairs(c.sideColumn or {}) do w[m.id] = true; end
        end
        for _, z in ipairs(U.INCURSION_ZONES) do
            for _, wp in ipairs(z.weapons) do
                w[wp.id] = true; w[wp.mat] = true;
                for _, ph in ipairs(wp.phases) do w[ph.result] = true; for _, r in ipairs(ph.reqs) do w[r] = true; end end
            end
        end
        U.watch = w;
    end
    U.have, U.count = TRF.scanBags(U.watch);
end
function TRF.UL.cur(kind) return TRF.TV.total(TRF.UL.CUR_NAME[kind]) or 0; end

function TRF.UL.relicCard(dl, r, x, y, w, h)
    local U = TRF.UL;
    local stage = 0;
    if U.have[r.finalId] then stage = #r.stages;
    else for s = #r.stages, 1, -1 do if U.have[r.stages[s].weaponId] then stage = s; break; end end end
    local done = stage >= #r.stages;
    local need = { BYNE = 0, SHELL = 0, BRONZE = 0 };
    for _, s in ipairs(r.stages) do
        need[s.currency] = need[s.currency] + s.amount;
        for _, ex in ipairs(s.extraCurrency or {}) do need[ex[1]] = need[ex[1]] + ex[2]; end
    end
    local tn, th = 0, 0;
    for k, a in pairs(need) do if a > 0 then tn = tn + a; th = th + math.min(U.cur(k), a); end end
    local pct = done and 1 or (tn > 0 and th / tn or 0);
    local mx_, my_ = imgui.GetMousePos();
    TRF.card(dl, x, y, w, h, done and 'done' or (stage > 0 and 'own') or nil, mx_ >= x and mx_ < x + w and my_ >= y and my_ < y + h);
    TRF.icon(dl, r.finalId, x + 8, y + 6, 26);
    dl:AddText({ x + 40, y + 5 }, u32(C.text), r.name);
    dl:AddText({ x + 40 + imgui.CalcTextSize(r.name) + 8, y + 5 }, u32(C.muted), r.job or '');
    local ps = ('%d%%'):fmt(math.floor(pct * 100));
    dl:AddText({ x + w - imgui.CalcTextSize(ps) - 10, y + 5 }, u32(done and C.gold or (pct >= 0.75 and C.green) or C.lav), ps);
    for s = 1, #r.stages do
        local dx, dy = x + 44 + (s - 1) * 14, y + 28;
        if s <= stage then dl:AddCircleFilled({ dx, dy }, 4, u32(done and C.gold or { NEON2[1], NEON2[2], NEON2[3], 1 }), 12);
        else dl:AddCircle({ dx, dy }, 4, u32({ 1, 1, 1, 0.25 }), 12, 1); end
    end
    if done then
        spaced(dl, x + 40, y + 46, 'COMPLETE', u32(C.gold), 2.5);
        dl:AddText({ x + 40, y + 46 + imgui.GetTextLineHeight() + 4 }, u32(C.muted), TRF.AR.name(r.finalId));
    else
        local bars = {};
        for _, k in ipairs({ 'BYNE', 'SHELL', 'BRONZE' }) do if need[k] > 0 then bars[#bars + 1] = { k, need[k] }; end end
        table.sort(bars, function (a, b) return a[2] < b[2]; end);
        local by = y + 40;
        for _, b in ipairs(bars) do
            local cd = U.CURRENCY[b[1]];
            TRF.icon(dl, cd.icon, x + 40, by, 16);
            TRF.bar(dl, x + 60, by, w - 70, 16, U.cur(b[1]), b[2]);
            by = by + 19;
        end
    end
    if TRF.hot('##vengo_relic' .. r.finalId, x, y, w, h) then
        local lines = { { done and 'Complete' or ('Stage %d of %d'):fmt(stage, #r.stages), done and C.gold or C.green } };
        for si, s in ipairs(r.stages) do
            lines[#lines + 1] = { ('  %d. %s  (%s %s)'):fmt(si, TRF.AR.name(s.weaponId), TRF.num(s.amount), U.CUR_NAME[s.currency]),
                                  U.have[s.weaponId] and C.green or C.muted };
        end
        TRF.itemTip(r.finalId, lines);
    end
end

function TRF.UL.extraCard(dl, c, x, y, w, h)
    local U = TRF.UL;
    local have = TRF.TV.total(c.currency) or 0;
    local pct = c.target > 0 and math.min(have / c.target, 1) or 0;
    local rows = c.materialRows or { { items = c.materials or {} } };
    local mx_, my_ = imgui.GetMousePos();
    TRF.card(dl, x, y, w, h, pct >= 1 and 'done' or nil, mx_ >= x and mx_ < x + w and my_ >= y and my_ < y + h);
    TRF.icon(dl, c.icon, x + 8, y + 6, 26);
    dl:AddText({ x + 40, y + 5 }, u32(C.text), c.name);
    local ps = ('%d%%'):fmt(math.floor(pct * 100));
    dl:AddText({ x + w - imgui.CalcTextSize(ps) - 10, y + 5 }, u32(pct >= 1 and C.gold or C.lav), ps);
    TRF.icon(dl, U.BAR_ICONS[c.currency] or c.icon, x + 40, y + 26, 16);
    TRF.bar(dl, x + 60, y + 26, w - 70, 16, have, c.target);
    local my = y + 48;
    local tipLines = nil;
    for ri, row in ipairs(rows) do
        for mi, m in ipairs(row.items) do
            local mx = x + 40 + (mi - 1) * 21;
            local got = U.have[m.id];
            if got then TRF.card(dl, mx - 1, my - 1, 20, 20, 'own', false, 4); end
            TRF.icon(dl, m.id, mx, my, 18, got and 1 or 0.3);
            if TRF.hot(('##vengo_xm%d_%d'):format(m.id, ri), mx, my, 18, 18) then tipLines = { m.id, got }; end
        end
        my = my + 21;
    end
    for si, m in ipairs(c.sideColumn or {}) do
        local mx = x + w - (#c.sideColumn - si + 1) * 21 - 6;
        local got = U.have[m.id];
        if got then TRF.card(dl, mx - 1, y + 47, 20, 20, 'own', false, 4); end
        TRF.icon(dl, m.id, mx, y + 48, 18, got and 1 or 0.3);
        if TRF.hot('##vengo_xs' .. m.id, mx, y + 48, 18, 18) then tipLines = { m.id, got }; end
    end
    if tipLines then TRF.itemTip(tipLines[1], { { tipLines[2] and 'You have it' or 'Not in your bags', tipLines[2] and C.green or C.muted } });
    elseif TRF.hot('##vengo_xc' .. c.name, x, y, w, 46) then
        imgui.SetTooltip(('%s: %s of %s %s'):fmt(c.name, TRF.num(have), TRF.num(c.target), c.currency));
    end
end

function TRF.UL.incursion(dl)
    local U = TRF.UL;
    local lh = imgui.GetTextLineHeight();
    local LABELS = { 'Forge', 'Upgrade', 'Trade' };
    for zi, z in ipairs(U.INCURSION_ZONES) do
        local n = 0;
        for _, wp in ipairs(z.weapons) do if U.have[wp.id] then n = n + 1; end end
        TRF.header(dl, z.name, z.color, ('%d / %d'):fmt(n, #z.weapons));
        for wi, wp in ipairs(z.weapons) do
            local x, y = imgui.GetCursorScreenPos();
            TRF.icon(dl, wp.id, x + 2, y + 1, 20);
            dl:AddText({ x + 30, y + 4 }, u32(U.have[wp.id] and C.gold or C.text), wp.name);
            dl:AddText({ x + 36 + imgui.CalcTextSize(wp.name), y + 4 }, u32(C.muted), wp.job);
            local bw = math.floor((ROW_W - 8) / 3);
            local maxBars = 0;
            for _, ph in ipairs(wp.phases) do if #(ph.bars or {}) > maxBars then maxBars = #ph.bars; end end
            local bh = 58 + maxBars * 16;
            local by = y + 26;
            for pi, ph in ipairs(wp.phases) do
                local px = x + (pi - 1) * (bw + 4);
                local got = U.have[ph.result];
                local mx_, my_ = imgui.GetMousePos();
                TRF.card(dl, px, by, bw, bh, got and 'done' or nil, mx_ >= px and mx_ < px + bw and my_ >= by and my_ < by + bh, 6);
                TRF.icon(dl, ph.result, px + 6, by + 3, 22, got and 1 or 0.35);
                local nm = TRF.AR.name(ph.result);
                if nm:find('^Item %d') and pi == #wp.phases then nm = wp.name; end
                while #nm > 1 and imgui.CalcTextSize(nm) > bw - 70 do nm = nm:sub(1, -2); end
                dl:AddText({ px + 32, by + 6 }, u32(got and C.gold or C.muted), nm);
                local lt = LABELS[pi] or '';
                local ltw = spacedW(lt:upper(), 1);
                spaced(dl, px + bw - ltw - 8, by + 6, lt:upper(), u32(C.label), 1);
                for ri, rid in ipairs(ph.reqs) do
                    local rx, ry = px + 6 + (ri - 1) * 22, by + 30;
                    local own = U.have[rid];
                    if own then TRF.card(dl, rx - 1, ry - 1, 22, 22, 'own', false, 4); end
                    TRF.icon(dl, rid, rx, ry, 20, own and 1 or 0.2);
                    if TRF.hot(('##vengo_inr%d_%d_%d'):format(zi * 100 + wi, pi, ri), rx, ry, 20, 20) then
                        TRF.itemTip(rid, { { own and 'You have it' or 'Not in your bags', own and C.green or C.muted } });
                    end
                end
                local yb = by + 54;
                for _, b in ipairs(ph.bars or {}) do
                    local have = b[3] and (TRF.TV.total(b[3]) or 0) or (U.count[b[2]] or 0);
                    TRF.icon(dl, b[2], px + 6, yb, 13);
                    TRF.bar(dl, px + 22, yb, bw - 30, 13, have, b[4]);
                    yb = yb + 16;
                end
                if TRF.hot(('##vengo_inp%d_%d'):format(zi * 100 + wi, pi), px, by, bw, 28) then
                    TRF.itemTip(ph.result, { { LABELS[pi] .. (got and ': done' or ''), got and C.gold or C.muted } });
                end
            end
            imgui.SetCursorScreenPos({ x, by + bh + 8 });
            imgui.Dummy({ ROW_W, 1 });
        end
        imgui.Spacing();
    end
end

TRF.ulTab = function()
    local U = TRF.UL;
    TRF.TV.askCurrency(false);
    U.scan();
    section('Ultimates');
    local dl = imgui.GetWindowDrawList();
    local loaded = TRF.TV.curAt ~= nil or next(TRF.TV.cur) ~= nil;
    local x, y = imgui.GetCursorScreenPos();
    local cx = x;
    for _, k in ipairs({ 'BYNE', 'SHELL', 'BRONZE' }) do
        local cd = U.CURRENCY[k];
        TRF.icon(dl, cd.icon, cx, y, 18);
        local s = loaded and TRF.num(U.cur(k)) or '?';
        dl:AddText({ cx + 24, y + 1 }, u32(C.lav), s);
        cx = cx + 24 + imgui.CalcTextSize(s) + 26;
    end
    imgui.Dummy({ ROW_W, 22 });
    TRF.refreshRow('Currency', TRF.TV.curAt, TRF.TV.curPending, function () TRF.TV.askCurrency(true); U.at = 0; end);
    imgui.Spacing();
    local v = pillChoice('##vengo_ulv', { { 'relic', 'RELIC' }, { 'incursion', 'CW INCURSION' } }, U.view);
    if v then U.view = v; end
    imgui.Spacing();
    if U.view == 'incursion' then TRF.UL.incursion(dl); return; end
    local gap = 8;
    local cw = math.floor((ROW_W - gap * 2) / 3);
    local ch = 40 + 3 * 19 + 4;
    local items = {};
    for _, r in ipairs(U.RELICS) do items[#items + 1] = { 'r', r }; end
    for _, c in ipairs(U.EXTRA_CARDS) do items[#items + 1] = { 'x', c }; end
    local x0, y0 = imgui.GetCursorScreenPos();
    for i, it in ipairs(items) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3);
        local px, py = x0 + col * (cw + gap), y0 + row * (ch + gap);
        if it[1] == 'r' then U.relicCard(dl, it[2], px, py, cw, ch); else U.extraCard(dl, it[2], px, py, cw, ch); end
    end
    local rows = math.ceil(#items / 3);
    imgui.SetCursorScreenPos({ x0, y0 + rows * (ch + gap) });
    imgui.Dummy({ ROW_W, 1 });
    hint('Currency totals come from the CatsEyeXI server (the same list as Trove\'s Currency tab); weapons and materials from your bags. Hover a card for its stages.');
end

------------------------------------------------------------------------
-- LUMORIA: Storming Sea buffs, Homam / Nashira with augment tiers, Omega / Ultima pieces, torques, Jailer
-- weapons and organs (all from the CatsEyeXI server)
------------------------------------------------------------------------
function TRF.LU.bit(m, pos) return bit.band(m or 0, bit.lshift(1, pos)) ~= 0; end
TRF.luTab = function()
    local LU, T = TRF.LU, TRF.TV;
    T.askLumoria(false);
    section('Lumoria');
    TRF.refreshRow('Lumoria', T.lumAt, T.lumPending, function () T.askLumoria(true); end);
    local D = T.lum;
    if D == nil then
        hint('Asking the CatsEyeXI server for your Sea progress. If nothing comes back, press REFRESH.');
        return;
    end
    local dl = imgui.GetWindowDrawList();
    local lh = imgui.GetTextLineHeight();
    local SEA = { 0.45, 0.62, 1.0 };

    -- Storming Sea buffs, two columns
    local nb = 0;
    for i = 0, 9 do if LU.bit(D.buffs, i) then nb = nb + 1; end end
    TRF.header(dl, 'Storming Sea buffs', SEA, ('%d / 10'):fmt(nb));
    local x0, y0 = imgui.GetCursorScreenPos();
    local half = (ROW_W - 8) / 2;
    for i, b in ipairs(LU.BUFFS) do
        local on = LU.bit(D.buffs, i - 1);
        local bx, by = x0 + ((i - 1) % 2) * (half + 8), y0 + math.floor((i - 1) / 2) * 30;
        local bh_ = TRF.hot('##vengo_lub' .. i, bx, by, half, 28);
        TRF.card(dl, bx, by, half, 28, on and 'on' or nil, bh_, 6);
        TRF.icon(dl, b.chip, bx + 4, by + 3, 22, on and 1 or 0.4);
        dl:AddText({ bx + 34, by + (28 - lh) / 2 }, u32(on and C.text or C.muted), b.name);
        if on then dl:AddCircleFilled({ bx + half - 12, by + 14 }, 3.5, u32(C.seal), 12); end
        if bh_ then
            imgui.BeginTooltip();
            imgui.TextColored(C.seal, b.name .. (on and '   (active)' or ''));
            imgui.TextColored(C.text, b.desc);
            imgui.TextColored(C.muted, ('%s  ·  %s %s'):fmt(b.nm, b.zone, b.pos));
            imgui.TextColored(C.muted, b.chipName .. '  ·  ' .. b.jobs);
            imgui.EndTooltip();
        end
    end
    imgui.SetCursorScreenPos({ x0, y0 + 5 * 30 + 6 });
    imgui.Dummy({ ROW_W, 1 });

    -- Homam and Nashira, side by side
    local function column(cx, cy, cw, name, pieces, tiers, mats, matCounts, locMask)
        local n = 0;
        for i = 1, 5 do if (tiers[i] or 0) > 0 then n = n + 1; end end
        local tw_ = spaced(dl, cx, cy, name:upper(), u32(C.label), 2);
        dl:AddText({ cx + tw_ + 12, cy }, u32(n >= 5 and C.green or C.lav), ('%d / 5'):fmt(n));
        cy = cy + lh + 6;
        for i, p in ipairs(pieces) do
            local tier = tiers[i] or 0;
            local own = tier > 0;
            local rh = 40;
            local mx_, my_ = imgui.GetMousePos();
            TRF.card(dl, cx, cy, cw, rh, own and 'own' or nil, mx_ >= cx and mx_ < cx + cw and my_ >= cy and my_ < cy + rh, 6);
            TRF.icon(dl, p.id, cx + 6, cy + 8, 24, own and 1 or 0.4);
            dl:AddText({ cx + 38, cy + 4 }, u32(own and C.text or C.muted), p.name);
            for d = 1, 3 do
                local dx = cx + 42 + (d - 1) * 12;
                if d <= tier - 1 then dl:AddCircleFilled({ dx, cy + 28 }, 4, u32({ NEON2[1], NEON2[2], NEON2[3], 1 }), 12);
                else dl:AddCircle({ dx, cy + 28 }, 4, u32({ 1, 1, 1, 0.25 }), 12, 1); end
            end
            local mc = matCounts[i] or 0;
            local s = 'x' .. mc;
            local sw_ = imgui.CalcTextSize(s);
            dl:AddText({ cx + cw - sw_ - 10, cy + 12 }, u32(mc > 0 and C.lav or C.muted), s);
            if mats[i] then TRF.icon(dl, mats[i].id, cx + cw - sw_ - 34, cy + 10, 20, mc > 0 and 1 or 0.45); end
            if TRF.hot(('##vengo_lua%s%d'):format(name, i), cx, cy, cw, rh) then
                local lines = {};
                if own then
                    local at = tier - 1;
                    if at >= 1 and p.augs and p.augs[at] then for _, a in ipairs(p.augs[at]) do lines[#lines + 1] = { a, { 1, 0.55, 0.75, 1 } }; end
                    else lines[#lines + 1] = { 'Base (no augments)', C.muted }; end
                    lines[#lines + 1] = { LU.bit(locMask, i - 1) and 'In: Squire' or 'In: Inventory', C.green };
                else lines[#lines + 1] = { 'Not owned', C.muted }; end
                if mats[i] then lines[#lines + 1] = { ('%s: %d'):fmt(mats[i].name, mc), C.text }; end
                TRF.itemTip(p.id, lines);
            end
            cy = cy + rh + 2;
        end
        return cy;
    end
    TRF.header(dl, 'Homam and Nashira', SEA, nil);
    local ax, ay = imgui.GetCursorScreenPos();
    local cw = (ROW_W - 10) / 2;
    local e1 = column(ax, ay, cw, 'Homam', LU.HOMAM, D.homam, LU.OMEGA_PIECES, D.omega, D.homamLoc);
    local e2 = column(ax + cw + 10, ay, cw, 'Nashira', LU.NASHIRA, D.nashira, LU.ULTIMA_PIECES, D.ultima, D.nashiraLoc);
    imgui.SetCursorScreenPos({ ax, math.max(e1, e2) + 6 });
    imgui.Dummy({ ROW_W, 1 });

    -- torques and Jailer weapons
    local function iconRow(label, list, mask, locMask, key)
        local n = 0;
        for i = 0, #list - 1 do if LU.bit(mask, i) then n = n + 1; end end
        TRF.header(dl, label, SEA, ('%d / %d'):fmt(n, #list));
        local rx, ry = imgui.GetCursorScreenPos();
        for i, it in ipairs(list) do
            local own = LU.bit(mask, i - 1);
            local ix = rx + (i - 1) * 42;
            local th_ = TRF.hot(('##vengo_lu%s%d'):format(key, i), ix, ry, 38, 38);
            TRF.card(dl, ix, ry, 38, 38, own and 'own' or nil, th_, 6);
            TRF.icon(dl, it.id, ix + 3, ry + 3, 32, own and 1 or 0.35);
            if th_ then
                TRF.itemTip(it.id, { { own and ('Owned  ·  ' .. (LU.bit(locMask, i - 1) and 'Squire' or 'Inventory')) or 'Not owned', own and C.green or C.muted },
                                     { 'From: ' .. it.nm, C.gold } });
            end
        end
        imgui.SetCursorScreenPos({ rx, ry + 44 });
        imgui.Dummy({ ROW_W, 1 });
    end
    iconRow('Sea Torques', LU.TORQUES, D.torques, D.torqueLoc, 't');
    iconRow('Jailer Weapons', LU.WEAPONS, D.weapons, D.weaponLoc, 'w');

    -- organs: inventory + vision storage
    local tot = 0;
    for i = 1, #LU.ORGANS do tot = tot + (D.organInv[i] or 0) + (D.organVis[i] or 0); end
    TRF.header(dl, 'Organs', SEA, TRF.num(tot));
    local ox, oy = imgui.GetCursorScreenPos();
    local per = 6;
    local ow = (ROW_W - (per - 1) * 6) / per;
    for i, o in ipairs(LU.ORGANS) do
        local inv, vis = D.organInv[i] or 0, D.organVis[i] or 0;
        local t_ = inv + vis;
        local px, py = ox + ((i - 1) % per) * (ow + 6), oy + math.floor((i - 1) / per) * 34;
        local oh_ = TRF.hot('##vengo_luo' .. i, px, py, ow, 30);
        TRF.card(dl, px, py, ow, 30, t_ > 0 and 'own' or nil, oh_, 6);
        TRF.icon(dl, o.id, px + 4, py + 3, 24, t_ > 0 and 1 or 0.35);
        dl:AddText({ px + 34, py + (30 - lh) / 2 }, u32(t_ > 0 and (o.hq and C.gold or C.lav) or C.muted), 'x' .. t_);
        if oh_ then
            TRF.itemTip(o.id, { { ('Inventory: %d'):fmt(inv), C.text }, { ('Vision storage: %d'):fmt(vis), C.text }, { ('Total: %d'):fmt(t_), C.green } });
        end
    end
    imgui.SetCursorScreenPos({ ox, oy + math.ceil(#LU.ORGANS / per) * 34 + 4 });
    imgui.Dummy({ ROW_W, 1 });
    hint('From the CatsEyeXI server (the same data as Trove\'s Lumoria window). Hover anything for details; dots are augment tiers.');
end

-- Trove's data for the three tabs (items, stages, bits): MIT licence, LICENSE-trove.txt
TRF.CX.ZONES = {
    {
        name = "Dynamis-San d'Oria",
        tint = { 0.20, 0.12, 0.12 }, -- red
        pops = {
            { name = "Barbaric Bijou",  id = 3353, mask = 'A', bit = 1,  spawns = "Overlord's Tombstone" },
            { name = "Chapter 1",       id = 3404, mask = 'A', bit = 11, spawns = "Arch Overlord (1/5)" },
            { name = "Chapter 2",       id = 3405, mask = 'A', bit = 12, spawns = "Arch Overlord (2/5)" },
            { name = "Chapter 3",       id = 3406, mask = 'A', bit = 13, spawns = "Arch Overlord (3/5)" },
            { name = "Chapter 4",       id = 3407, mask = 'A', bit = 14, spawns = "Arch Overlord (4/5)" },
            { name = "Chapter 5",       id = 3408, mask = 'A', bit = 15, spawns = "Arch Overlord (5/5)" },
        },
        drops = {
            { name = "Odious Scale",       id = 3380, mask = 'C', bit = 9,  spawns = "Bladeburner Rokgevok" },
            { name = "Odious Leather",     id = 3381, mask = 'C', bit = 10, spawns = "Steelshank Kratzvatz" },
            { name = "Odious Cryptex",     id = 3382, mask = 'C', bit = 11, spawns = "Bloodfist Voshgrosh" },
            { name = "Odious Strongbox",   id = 3383, mask = 'C', bit = 12, spawns = "Spellspear Djokvukk" },
        },
    },
    {
        name = "Dynamis-Bastok",
        tint = { 0.12, 0.14, 0.22 }, -- blue
        pops = {
            { name = "Steelwall Bijou", id = 3354, mask = 'A', bit = 2,  spawns = "Gu'Dha Effigy" },
            { name = "Chapter 6",       id = 3409, mask = 'A', bit = 16, spawns = "Arch Gu'Dha (1/5)" },
            { name = "Chapter 7",       id = 3410, mask = 'A', bit = 17, spawns = "Arch Gu'Dha (2/5)" },
            { name = "Chapter 8",       id = 3411, mask = 'A', bit = 18, spawns = "Arch Gu'Dha (3/5)" },
            { name = "Chapter 9",       id = 3412, mask = 'A', bit = 19, spawns = "Arch Gu'Dha (4/5)" },
            { name = "Chapter 10",      id = 3413, mask = 'A', bit = 20, spawns = "Arch Gu'Dha (5/5)" },
        },
        drops = {
            { name = "Odious Charm",       id = 3384, mask = 'C', bit = 5,  spawns = "Zo'Pha Forgesoul" },
            { name = "Odious Backscale",   id = 3385, mask = 'C', bit = 6,  spawns = "Ra'Gho Darkfount" },
            { name = "Odious Engraving",   id = 3386, mask = 'C', bit = 7,  spawns = "Va'Zhe Pummelsong" },
            { name = "Odious Letterbox",   id = 3387, mask = 'C', bit = 8,  spawns = "Bu'Bho Truesteel" },
        },
    },
    {
        name = "Dynamis-Windurst",
        tint = { 0.12, 0.18, 0.12 }, -- green
        pops = {
            { name = "Divine Bijou",    id = 3355, mask = 'A', bit = 3,  spawns = "Tzee Xicu Idol" },
            { name = "Chapter 11",      id = 3414, mask = 'A', bit = 21, spawns = "Arch Tzee Xicu (1/5)" },
            { name = "Chapter 12",      id = 3415, mask = 'A', bit = 22, spawns = "Arch Tzee Xicu (2/5)" },
            { name = "Chapter 13",      id = 3416, mask = 'A', bit = 23, spawns = "Arch Tzee Xicu (3/5)" },
            { name = "Chapter 14",      id = 3417, mask = 'A', bit = 24, spawns = "Arch Tzee Xicu (4/5)" },
            { name = "Chapter 15",      id = 3418, mask = 'A', bit = 25, spawns = "Arch Tzee Xicu (5/5)" },
        },
        drops = {
            { name = "Odious Necklace",    id = 3388, mask = 'C', bit = 1,  spawns = "Xuu Bhoqa the Enigma" },
            { name = "Odious Feather",     id = 3389, mask = 'C', bit = 2,  spawns = "Fuu Tzapo the Blessed" },
            { name = "Odious Holy Water",  id = 3390, mask = 'C', bit = 3,  spawns = "Naa Yixo the Stillrage" },
            { name = "Odious Quipu",       id = 3391, mask = 'C', bit = 4,  spawns = "Tee Zaksa the Ceaseless" },
        },
    },
    {
        name = "Dynamis-Jeuno",
        tint = { 0.20, 0.18, 0.10 }, -- yellow
        pops = {
            { name = "Roving Bijou",    id = 3356, mask = 'A', bit = 4,  spawns = "Goblin Golem" },
            { name = "Chapter 16",      id = 3419, mask = 'A', bit = 26, spawns = "Arch Goblin Golem (1/5)" },
            { name = "Chapter 17",      id = 3420, mask = 'A', bit = 27, spawns = "Arch Goblin Golem (2/5)" },
            { name = "Chapter 18",      id = 3421, mask = 'A', bit = 28, spawns = "Arch Goblin Golem (3/5)" },
            { name = "Chapter 19",      id = 3422, mask = 'A', bit = 29, spawns = "Arch Goblin Golem (4/5)" },
            { name = "Chapter 20",      id = 3423, mask = 'A', bit = 30, spawns = "Arch Goblin Golem (5/5)" },
        },
        drops = {
            { name = "Odious Cup",         id = 3392, mask = 'C', bit = 23, spawns = "Quicktrix Hexhands" },
            { name = "Odious Die",         id = 3393, mask = 'C', bit = 24, spawns = "Feralox Honeylips" },
            { name = "Odious Mask",        id = 3394, mask = 'C', bit = 25, spawns = "Scourquix Scaleskin" },
            { name = "Odious Grenade",     id = 3395, mask = 'C', bit = 26, spawns = "Wilywox Tenderpalm" },
        },
    },
    {
        name = "Dynamis-Beaucedine",
        tint = { 0.12, 0.16, 0.22 }, -- light blue
        pops = {
            { name = "Leering Bijou",   id = 3357, mask = 'A', bit = 5,  spawns = "Angra Mainyu" },
            { name = "Chapter 21",      id = 3424, mask = 'A', bit = 31, spawns = "Arch Angra Mainyu (1/5)" },
            { name = "Chapter 22",      id = 3425, mask = 'A', bit = 32, spawns = "Arch Angra Mainyu (2/5)" },
            { name = "Chapter 23",      id = 3426, mask = 'B', bit = 1,  spawns = "Arch Angra Mainyu (3/5)" },
            { name = "Chapter 24",      id = 3427, mask = 'B', bit = 2,  spawns = "Arch Angra Mainyu (4/5)" },
            { name = "Chapter 25",      id = 3428, mask = 'B', bit = 3,  spawns = "Arch Angra Mainyu (5/5)" },
        },
        drops = {
            { name = "Odious Talisman",        id = 3396, mask = 'C', bit = 27, spawns = "Taquede" },
            { name = "Odious Bell",            id = 3397, mask = 'C', bit = 28, spawns = "Pignonpausard" },
            { name = "Odious Tree Root",       id = 3398, mask = 'C', bit = 29, spawns = "Hitaume" },
            { name = "Odious Mirror",          id = 3399, mask = 'C', bit = 30, spawns = "Cavanneche" },
            { name = "Despot's Parchment",     id = 3359, mask = 'C', bit = 31, spawns = "Goublefaupe" },
            { name = "Sadist's Parchment",     id = 3360, mask = 'C', bit = 32, spawns = "Quiebitiel" },
            { name = "Villain's Parchment",    id = 3361, mask = 'D', bit = 1,  spawns = "Mildaunegeux" },
            { name = "Deluder's Parchment",    id = 3362, mask = 'D', bit = 2,  spawns = "Velosareon" },
            { name = "Traitor's Parchment",    id = 3363, mask = 'D', bit = 3,  spawns = "Dagourmarche" },
        },
    },
    {
        name = "Dynamis-Xarcabard",
        tint = { 0.09, 0.10, 0.18 }, -- dark blue
        pops = {
            { name = "Shrouded Bijou",  id = 3358, mask = 'A', bit = 6,  spawns = "Dynamis Lord" },
            { name = "Chapter 26",      id = 3429, mask = 'B', bit = 4,  spawns = "Arch Dynamis Lord (1/5)" },
            { name = "Chapter 27",      id = 3430, mask = 'B', bit = 5,  spawns = "Arch Dynamis Lord (2/5)" },
            { name = "Chapter 28",      id = 3431, mask = 'B', bit = 6,  spawns = "Arch Dynamis Lord (3/5)" },
            { name = "Chapter 29",      id = 3432, mask = 'B', bit = 7,  spawns = "Arch Dynamis Lord (4/5)" },
            { name = "Chapter 30",      id = 3433, mask = 'B', bit = 8,  spawns = "Arch Dynamis Lord (5/5)" },
        },
        drops = {
            { name = "Odious Skull",       id = 3400, mask = 'D', bit = 4,  spawns = "Duke Haures" },
            { name = "Odious Horn",        id = 3401, mask = 'D', bit = 5,  spawns = "Marquis Caim" },
            { name = "Odious Blood",       id = 3402, mask = 'D', bit = 6,  spawns = "Baron Avnas" },
            { name = "Odious Pen",         id = 3403, mask = 'D', bit = 7,  spawns = "Count Haagenti" },
            { name = "Mystic Goad",        id = 3364, mask = 'D', bit = 8,  spawns = "Animated Knuckles" },
            { name = "Ornate Goad",        id = 3365, mask = 'D', bit = 9,  spawns = "Animated Dagger" },
            { name = "Holy Goad",          id = 3366, mask = 'D', bit = 10, spawns = "Animated Longsword" },
            { name = "Intricate Goad",     id = 3367, mask = 'D', bit = 11, spawns = "Animated Claymore" },
            { name = "Runaeic Goad",       id = 3368, mask = 'D', bit = 12, spawns = "Animated Tabar" },
            { name = "Seraphic Goad",      id = 3369, mask = 'D', bit = 13, spawns = "Animated Great Axe" },
            { name = "Tenebrous Goad",     id = 3370, mask = 'D', bit = 14, spawns = "Animated Scythe" },
            { name = "Stellar Goad",       id = 3371, mask = 'D', bit = 15, spawns = "Animated Spear" },
            { name = "Demoniac Goad",      id = 3372, mask = 'D', bit = 16, spawns = "Animated Kunai" },
            { name = "Divine Goad",        id = 3373, mask = 'D', bit = 17, spawns = "Animated Tachi" },
            { name = "Heavenly Goad",      id = 3374, mask = 'D', bit = 18, spawns = "Animated Hammer" },
            { name = "Celestial Goad",     id = 3375, mask = 'D', bit = 19, spawns = "Animated Staff" },
            { name = "Snarled Goad",       id = 3376, mask = 'D', bit = 20, spawns = "Animated Longbow" },
            { name = "Ethereal Goad",      id = 3377, mask = 'D', bit = 21, spawns = "Animated Gun" },
            { name = "Mysterial Goad",     id = 3378, mask = 'D', bit = 22, spawns = "Animated Horn" },
            { name = "Supernal Goad",      id = 3379, mask = 'D', bit = 23, spawns = "Animated Shield" },
        },
    },
    {
        name = "Dynamis-Valkurm",
        tint = { 0.16, 0.12, 0.20 }, -- purple
        pops = {
            { name = "Creepers Juju",   id = 3456, mask = 'A', bit = 7,  spawns = "Cirrate Christelle" },
            { name = "Tome II Ch.1",    id = 3470, mask = 'B', bit = 9,  spawns = "Arch Christelle (1/4)" },
            { name = "Tome II Ch.2",    id = 3471, mask = 'B', bit = 10, spawns = "Arch Christelle (2/4)" },
            { name = "Tome II Ch.3",    id = 3472, mask = 'B', bit = 11, spawns = "Arch Christelle (3/4)" },
            { name = "Tome II Ch.4",    id = 3473, mask = 'B', bit = 12, spawns = "Arch Christelle (4/4)" },
        },
        drops = {
            { name = "Nightmare Bud",     id = 3461, mask = 'C', bit = 13, spawns = "Lost Nant'ina" },
            { name = "Nightmare Log",     id = 3460, mask = 'C', bit = 14, spawns = "Lost Fairy Ring" },
            { name = "Nightmare Water",   id = 3462, mask = 'C', bit = 15, spawns = "Lost Stcemqestcint" },
        },
    },
    {
        name = "Dynamis-Buburimu",
        tint = { 0.16, 0.12, 0.20 }, -- purple
        pops = {
            { name = "Revelatory Juju", id = 3457, mask = 'A', bit = 8,  spawns = "Apocalyptic Beast" },
            { name = "Tome II Ch.5",    id = 3474, mask = 'B', bit = 13, spawns = "Arch Apoc. Beast (1/5)" },
            { name = "Tome II Ch.6",    id = 3475, mask = 'B', bit = 14, spawns = "Arch Apoc. Beast (2/5)" },
            { name = "Tome II Ch.7",    id = 3476, mask = 'B', bit = 15, spawns = "Arch Apoc. Beast (3/5)" },
            { name = "Tome II Ch.8",    id = 3477, mask = 'B', bit = 16, spawns = "Arch Apoc. Beast (4/5)" },
            { name = "Tome II Ch.9",    id = 3478, mask = 'B', bit = 17, spawns = "Arch Apoc. Beast (5/5)" },
        },
        drops = {
            { name = "Nightmare Shank",   id = 3463, mask = 'C', bit = 16, spawns = "Lost Stihi" },
            { name = "Nightmare Loin",    id = 3465, mask = 'C', bit = 17, spawns = "Lost Alklha" },
            { name = "Nightmare Roast",   id = 3464, mask = 'C', bit = 18, spawns = "Lost Barong" },
            { name = "Nightmare Chop",    id = 3466, mask = 'C', bit = 19, spawns = "Lost Aitvaras" },
        },
    },
    {
        name = "Dynamis-Qufim",
        tint = { 0.16, 0.12, 0.20 }, -- purple
        pops = {
            { name = "Undying Juju",    id = 3458, mask = 'A', bit = 9,  spawns = "Antaeus" },
            { name = "Tome II Ch.10",   id = 3479, mask = 'B', bit = 18, spawns = "Arch Antaeus (1/4)" },
            { name = "Tome II Ch.11",   id = 3480, mask = 'B', bit = 19, spawns = "Arch Antaeus (2/4)" },
            { name = "Tome II Ch.12",   id = 3481, mask = 'B', bit = 20, spawns = "Arch Antaeus (3/4)" },
            { name = "Tome II Ch.13",   id = 3482, mask = 'B', bit = 21, spawns = "Arch Antaeus (4/4)" },
        },
        drops = {
            { name = "Nightmare Shard",   id = 3469, mask = 'C', bit = 20, spawns = "Lost Suttung" },
            { name = "Nightmare Shell",   id = 3467, mask = 'C', bit = 21, spawns = "Lost Scolopendra" },
            { name = "Nightmare Blood",   id = 3468, mask = 'C', bit = 22, spawns = "Lost Stringes" },
        },
    },
    {
        name = "Dynamis-Tavnazia",
        tint = { 0.20, 0.15, 0.10 }, -- orange
        pops = {
            { name = "Heralds Juju",    id = 3459, mask = 'A', bit = 10, spawns = "Diabolos" },
            { name = "Tome II Ch.14",   id = 3483, mask = 'B', bit = 22, spawns = "Arch Diabolos (1/4)" },
            { name = "Tome II Ch.15",   id = 3484, mask = 'B', bit = 23, spawns = "Arch Diabolos (2/4)" },
            { name = "Tome II Ch.16",   id = 3485, mask = 'B', bit = 24, spawns = "Arch Diabolos (3/4)" },
            { name = "Tome II Ch.17",   id = 3486, mask = 'B', bit = 25, spawns = "Arch Diabolos (4/4)" },
        },
        drops = {},
    },
};

TRF.UL.CURRENCY = {
    -- Byne Bills (base unit = 1 One Byne Bill)
    BYNE = {
        name  = 'Byne Bills',
        icon  = 1455, -- One Byne Bill
        color = { 1.00, 0.78, 0.35, 1.00 }, -- amber
        barFill = { 0.70, 0.55, 0.20, 0.65 }, -- darker fill for readability
    },
    -- Whiteshells (base unit = 1 Tukuku Whiteshell)
    SHELL = {
        name  = 'Whiteshells',
        icon  = 1449, -- Tukuku Whiteshell
        color = { 0.55, 0.85, 1.00, 1.00 }, -- light blue
        barFill = { 0.25, 0.50, 0.65, 0.65 },
    },
    -- Bronzepieces (base unit = 1 Ordelle Bronzepiece)
    BRONZE = {
        name  = 'Bronzepieces',
        icon  = 1452, -- Ordelle Bronzepiece
        color = { 0.85, 0.60, 0.40, 1.00 }, -- bronze
        barFill = { 0.55, 0.35, 0.18, 0.65 },
    },
};

TRF.UL.RELICS = {
    {
        name = 'Spharai', finalId = 18264, job = 'MNK',
        stages = {
            { weaponId = 18261, currency = 'BYNE',   amount = 400 },   -- Militant Knuckles
            { weaponId = 18262, currency = 'BRONZE', amount = 1400 },  -- Dynamis Knuckles
            { weaponId = 18263, currency = 'SHELL',  amount = 6100 },  -- Caestus
            { weaponId = 18264, currency = 'BYNE',   amount = 10000 }, -- Spharai
        },
    },
    {
        name = 'Mandau', finalId = 18270, job = 'THF',
        stages = {
            { weaponId = 18267, currency = 'BYNE',   amount = 400 },   -- Malefic Dagger
            { weaponId = 18268, currency = 'BRONZE', amount = 1400 },  -- Dynamis Dagger
            { weaponId = 18269, currency = 'SHELL',  amount = 6100 },  -- Batardeau
            { weaponId = 18270, currency = 'BYNE',   amount = 10000 }, -- Mandau
        },
    },
    {
        name = 'Excalibur', finalId = 18276, job = 'PLD',
        stages = {
            { weaponId = 18273, currency = 'BRONZE', amount = 400 },   -- Glyptic Sword
            { weaponId = 18274, currency = 'BYNE',   amount = 1400 },  -- Dynamis Sword
            { weaponId = 18275, currency = 'SHELL',  amount = 6100 },  -- Caliburn
            { weaponId = 18276, currency = 'BRONZE', amount = 10000 }, -- Excalibur
        },
    },
    {
        name = 'Ragnarok', finalId = 18282, job = 'DRK',
        stages = {
            { weaponId = 18279, currency = 'BRONZE', amount = 400 },   -- Gilded Blade
            { weaponId = 18280, currency = 'SHELL',  amount = 1600 },  -- Dynamis Blade
            { weaponId = 18281, currency = 'BYNE',   amount = 6100 },  -- Valhalla
            { weaponId = 18282, currency = 'BRONZE', amount = 10000 }, -- Ragnarok
        },
    },
    {
        name = 'Guttler', finalId = 18288, job = 'BST',
        stages = {
            { weaponId = 18285, currency = 'SHELL',  amount = 300 },   -- Leonine Axe
            { weaponId = 18286, currency = 'BRONZE', amount = 1400 },  -- Dynamis Axe
            { weaponId = 18287, currency = 'BYNE',   amount = 6000 },  -- Ogre Killer
            { weaponId = 18288, currency = 'SHELL',  amount = 10000 }, -- Guttler
        },
    },
    {
        name = 'Bravura', finalId = 18294, job = 'WAR',
        stages = {
            { weaponId = 18291, currency = 'BYNE',   amount = 300 },   -- Agonal Bhuj
            { weaponId = 18292, currency = 'SHELL',  amount = 1600 },  -- Dynamis Bhuj
            { weaponId = 18293, currency = 'BRONZE', amount = 6000 },  -- Abaddon Killer
            { weaponId = 18294, currency = 'BYNE',   amount = 10000 }, -- Bravura
        },
    },
    {
        name = 'Gungnir', finalId = 18300, job = 'DRG',
        stages = {
            { weaponId = 18297, currency = 'SHELL',  amount = 400 },   -- Hotspur Lance
            { weaponId = 18298, currency = 'BYNE',   amount = 1600 },  -- Dynamis Lance
            { weaponId = 18299, currency = 'BRONZE', amount = 6100 },  -- Gae Assail
            { weaponId = 18300, currency = 'SHELL',  amount = 10000 }, -- Gungnir
        },
    },
    {
        name = 'Apocalypse', finalId = 18306, job = 'DRK',
        stages = {
            { weaponId = 18303, currency = 'SHELL',  amount = 500 },   -- Memento Scythe
            { weaponId = 18304, currency = 'BRONZE', amount = 1600 },  -- Dynamis Scythe
            { weaponId = 18305, currency = 'BYNE',   amount = 6200 },  -- Bec de Faucon
            { weaponId = 18306, currency = 'SHELL',  amount = 10000 }, -- Apocalypse
        },
    },
    {
        name = 'Kikoku', finalId = 18312, job = 'NIN',
        stages = {
            { weaponId = 18309, currency = 'BYNE',   amount = 400 },   -- Mimizuku
            { weaponId = 18310, currency = 'SHELL',  amount = 1600 },  -- Rogetsu
            { weaponId = 18311, currency = 'BRONZE', amount = 6100 },  -- Yoshimitsu
            { weaponId = 18312, currency = 'BYNE',   amount = 10000 }, -- Kikoku
        },
    },
    {
        name = 'Amanomurakumo', finalId = 18318, job = 'SAM',
        stages = {
            { weaponId = 18315, currency = 'BRONZE', amount = 300 },   -- Hayatemaru
            { weaponId = 18316, currency = 'SHELL',  amount = 1500 },  -- Oboromaru
            { weaponId = 18317, currency = 'BYNE',   amount = 6000 },  -- Totsukanotsurugi
            { weaponId = 18318, currency = 'BRONZE', amount = 10000 }, -- Amanomurakumo
        },
    },
    {
        name = 'Mjollnir', finalId = 18324, job = 'WHM',
        stages = {
            { weaponId = 18321, currency = 'BRONZE', amount = 500 },   -- Battering Maul
            { weaponId = 18322, currency = 'BYNE',   amount = 1600 },  -- Dynamis Maul
            { weaponId = 18323, currency = 'SHELL',  amount = 6200 },  -- Gullintani
            { weaponId = 18324, currency = 'BRONZE', amount = 10000 }, -- Mjollnir
        },
    },
    {
        name = 'Claustrum', finalId = 18330, job = 'BLM',
        stages = {
            { weaponId = 18327, currency = 'SHELL',  amount = 500 },   -- Sages Staff
            { weaponId = 18328, currency = 'BYNE',   amount = 1600 },  -- Dynamis Staff
            { weaponId = 18329, currency = 'BRONZE', amount = 6200 },  -- Thyrus
            { weaponId = 18330, currency = 'SHELL',  amount = 10000 }, -- Claustrum
        },
    },
    {
        name = 'Annihilator', finalId = 18336, job = 'RNG',
        stages = {
            { weaponId = 18333, currency = 'BYNE',   amount = 500 },   -- Marksmans Gun
            { weaponId = 18334, currency = 'SHELL',  amount = 1500 },  -- Dynamis Gun
            { weaponId = 18335, currency = 'BRONZE', amount = 6200 },  -- Ferdinand
            { weaponId = 18336, currency = 'BYNE',   amount = 10000 }, -- Annihilator
        },
    },
    {
        name = 'Gjallarhorn', finalId = 18342, job = 'BRD',
        stages = {
            { weaponId = 18339, currency = 'SHELL',  amount = 300 },   -- Pyrrhic Horn
            { weaponId = 18340, currency = 'BYNE',   amount = 1400 },  -- Dynamis Horn
            { weaponId = 18341, currency = 'BRONZE', amount = 6000 },  -- Millennium Horn
            { weaponId = 18342, currency = 'SHELL',  amount = 10000 }, -- Gjallarhorn
        },
    },
    {
        name = 'Yoichinoyumi', finalId = 18348, job = 'RNG',
        stages = {
            { weaponId = 18345, currency = 'BRONZE', amount = 400 },   -- Wolver Bow
            { weaponId = 18346, currency = 'BRONZE', amount = 1500 },  -- Dynamis Bow
            { weaponId = 18347, currency = 'SHELL',  amount = 6100 },  -- Futatokoroto
            { weaponId = 18348, currency = 'BRONZE', amount = 10000 }, -- Yoichinoyumi
        },
    },
    {
        name = 'Aegis', finalId = 15070, job = 'PLD',
        stages = {
            { weaponId = 15067, currency = 'BYNE',   amount = 100,  extraCurrency = { { 'BRONZE', 100 }, { 'SHELL', 100 } } },   -- Bulwark Shield
            { weaponId = 15068, currency = 'BYNE',   amount = 400,  extraCurrency = { { 'BRONZE', 400 }, { 'SHELL', 400 } } },   -- Dynamis Shield
            { weaponId = 15069, currency = 'BYNE',   amount = 2000, extraCurrency = { { 'BRONZE', 2000 }, { 'SHELL', 2000 } } }, -- Ancile
            { weaponId = 15070, currency = 'BRONZE', amount = 10000 }, -- Aegis
        },
    },
};

TRF.UL.EXTRA_CARDS = {
    {
        name       = 'Mythic',
        icon       = 18993, -- Yagrush
        currency   = 'Alexandrite',
        target     = 30000,
        color      = { 0.70, 0.90, 0.50, 1.00 }, -- lime green
        barFill    = { 0.35, 0.50, 0.20, 0.65 },
        materials  = {
            { id = 3066, name = "Medusa's Brassard" },
            { id = 3067, name = "Gurfurlur's Morion" },
            { id = 3068, name = "Ja Ja's Plastron" },
        },
    },
    {
        name       = 'Ergon',
        icon       = 21685, -- Epeolatry
        currency   = 'H-P Bayld',
        target     = 10000,
        color      = { 0.80, 0.55, 0.90, 1.00 }, -- purple
        barFill    = { 0.40, 0.25, 0.50, 0.65 },
        materialRows = {
            {
                items = {
                    { id = 3980, name = 'Bztavian Stinger' },
                    { id = 3979, name = 'Rockfin Tooth' },
                    { id = 3977, name = 'Gabbrath Horn' },
                    { id = 4015, name = 'Yggdreant Root' },
                    { id = 4013, name = 'Waktza Crest' },
                    { id = 8754, name = 'Cehuetzi Pelt' },
                },
            },
            {
                items = {
                    { id = 3981, name = 'Bztavian Wing' },
                    { id = 3978, name = 'Rockfin Fin' },
                    { id = 6068, name = 'Gabbrath Meat' },
                    { id = 4014, name = 'Yggdreant Bole' },
                    { id = 4012, name = 'Waktza Rostrum' },
                    { id = 8752, name = 'Cehuetzi Claw' },
                },
            },
        },
        -- Extra column: Domain NM materials (displayed right of rows in L-shape)
        sideColumn = {
            { id = 9506, name = 'Amphisbaena Hide' },
            { id = 9510, name = 'Battosai Fang' },
            { id = 9511, name = 'Tortuga Shell' },
        },
    },
};

TRF.UL.INCURSION_ZONES = {
    {
        name  = 'Mamook',
        color = { 0.90, 0.45, 0.40, 1.00 },  -- red (Orcish)
        weapons = {
            { name = 'Ohrmazd', id = 20530, job = 'MNK/PUP', coin = 3951, chain = 3012, hoard = 3063, gem = 8964, mat = 1458, phases = {
                { result = 21510, reqs = { 16437, 16446, 17519, 2984 }, bars = { { 'Orcish Steel', 3951, 'Orcish Steel', 300 } } },
                { result = 20531, reqs = { 17472, 17503, 18350, 21510 }, bars = { { 'Orcish Steel', 3951, 'Orcish Steel', 500 }, { 'Chains', 3012, 'Orcish Chain', 10 } } },
                { result = 20530, reqs = { 20531, 18351, 16426 }, bars = { { 'Hoards', 3063, 'Mamook Steel', 9900 }, { 'Gems', 8964, 'Imperial Citrine', 250 }, { 'Mats', 1458, nil, 12 } } },
            }},
            { name = 'Claidheamh', id = 20718, job = 'PLD/BLU', coin = 3951, chain = 3012, hoard = 3063, gem = 8961, mat = 1409, phases = {
                { result = 22219, reqs = { 16628, 16634, 17692, 2985 }, bars = { { 'Orcish Steel', 3951, 'Orcish Steel', 300 } } },
                { result = 20719, reqs = { 16580, 16533, 17693, 22219 }, bars = { { 'Orcish Steel', 3951, 'Orcish Steel', 500 }, { 'Chains', 3012, 'Orcish Chain', 10 } } },
                { result = 20718, reqs = { 20719, 17695, 17649 }, bars = { { 'Hoards', 3063, 'Mamook Steel', 9900 }, { 'Gems', 8961, 'Imperial Opal', 250 }, { 'Mats', 1409, nil, 12 } } },
            }},
            { name = 'Kumbhakarna', id = 20809, job = 'WAR/BST', coin = 3951, chain = 3012, hoard = 3063, gem = 8962, mat = 1459, phases = {
                { result = 21712, reqs = { 16663, 16664, 16687, 2986 }, bars = { { 'Orcish Steel', 3951, 'Orcish Steel', 300 } } },
                { result = 20810, reqs = { 17969, 16676, 17936, 21712 }, bars = { { 'Orcish Steel', 3951, 'Orcish Steel', 500 }, { 'Chains', 3012, 'Orcish Chain', 10 } } },
                { result = 20809, reqs = { 20810, 17937, 17960 }, bars = { { 'Hoards', 3063, 'Mamook Steel', 9900 }, { 'Gems', 8962, 'Imperial Amethyst', 250 }, { 'Mats', 1459, nil, 12 } } },
            }},
            { name = 'Svarga', id = 20857, job = 'WAR', coin = 3951, chain = 3012, hoard = 3063, gem = 8964, mat = 1467, phases = {
                { result = 21769, reqs = { 16717, 18215, 18209, 2987 }, bars = { { 'Orcish Steel', 3951, 'Orcish Steel', 300 } } },
                { result = 20859, reqs = { 18507, 16727, 18210, 21769 }, bars = { { 'Orcish Steel', 3951, 'Orcish Steel', 500 }, { 'Chains', 3012, 'Orcish Chain', 10 } } },
                { result = 20857, reqs = { 20859, 18211, 18497 }, bars = { { 'Hoards', 3063, 'Mamook Steel', 9900 }, { 'Gems', 8964, 'Imperial Citrine', 250 }, { 'Mats', 1467, nil, 12 } } },
            }},
            { name = 'Olyndicus', id = 20946, job = 'DRG', coin = 3951, chain = 3012, hoard = 3063, gem = 8962, mat = 1462, phases = {
                { result = 21864, reqs = { 16864, 16876, 18085, 2988 }, bars = { { 'Orcish Steel', 3951, 'Orcish Steel', 300 } } },
                { result = 20947, reqs = { 16885, 16882, 18086, 21864 }, bars = { { 'Orcish Steel', 3951, 'Orcish Steel', 500 }, { 'Chains', 3012, 'Orcish Chain', 10 } } },
                { result = 20946, reqs = { 20947, 18088, 18125 }, bars = { { 'Hoards', 3063, 'Mamook Steel', 9900 }, { 'Gems', 8962, 'Imperial Amethyst', 250 }, { 'Mats', 1462, nil, 12 } } },
            }},
            { name = 'Svalinn', id = 27627, job = 'WAR', coin = 3951, chain = 3012, hoard = 3063, gem = 8960, mat = 1468, phases = {
                { result = 26413, reqs = { 12334, 12326, 18171, 2989 }, bars = { { 'Orcish Steel', 3951, 'Orcish Steel', 300 } } },
                { result = 27624, reqs = { 12348, 16187, 12405, 26413 }, bars = { { 'Orcish Steel', 3951, 'Orcish Steel', 500 }, { 'Chains', 3012, 'Orcish Chain', 10 } } },
                { result = 27627, reqs = { 27624, 12361, 12360 }, bars = { { 'Hoards', 3063, 'Mamook Steel', 9900 }, { 'Gems', 8960, 'Imperial Garnet', 250 }, { 'Mats', 1468, nil, 12 } } },
            }},
        },
    },
    {
        name  = 'Halvung',
        color = { 0.45, 0.65, 1.00, 1.00 },  -- blue (Quadav)
        weapons = {
            { name = 'Claritas', id = 18909, job = 'RDM', coin = 3952, chain = 3013, hoard = 3064, gem = 8965, mat = 1468, phases = {
                { result = 21622, reqs = { 16633, 16803, 17692, 2978 }, bars = { { 'Quadav Brass', 3952, 'Quadav Brass', 300 } } },
                { result = 18905, reqs = { 16822, 16821, 17696, 21622 }, bars = { { 'Quadav Brass', 3952, 'Quadav Brass', 500 }, { 'Chains', 3013, 'Quadav Chain', 10 } } },
                { result = 18909, reqs = { 18905, 17694, 17658 }, bars = { { 'Hoards', 3064, 'Halvung Brass', 9900 }, { 'Gems', 8965, 'Imperial Sapphire', 250 }, { 'Mats', 1468, nil, 12 } } },
            }},
            { name = 'Macbain', id = 20759, job = 'DRK/RUN', coin = 3952, chain = 3013, hoard = 3064, gem = 8960, mat = 1459, phases = {
                { result = 21665, reqs = { 16931, 16932, 16959, 2979 }, bars = { { 'Quadav Brass', 3952, 'Quadav Brass', 300 } } },
                { result = 20760, reqs = { 16942, 16945, 16937, 21665 }, bars = { { 'Quadav Brass', 3952, 'Quadav Brass', 500 }, { 'Chains', 3013, 'Quadav Chain', 10 } } },
                { result = 20759, reqs = { 20760, 18385, 19153 }, bars = { { 'Hoards', 3064, 'Halvung Brass', 9900 }, { 'Gems', 8960, 'Imperial Garnet', 250 }, { 'Mats', 1459, nil, 12 } } },
            }},
            { name = 'Inanna', id = 20901, job = 'BLM/DRK', coin = 3952, chain = 3013, hoard = 3064, gem = 8961, mat = 1458, phases = {
                { result = 21822, reqs = { 16779, 16782, 18045, 2980 }, bars = { { 'Quadav Brass', 3952, 'Quadav Brass', 300 } } },
                { result = 20903, reqs = { 16787, 18041, 18046, 21822 }, bars = { { 'Quadav Brass', 3952, 'Quadav Brass', 500 }, { 'Chains', 3013, 'Quadav Chain', 10 } } },
                { result = 20901, reqs = { 20903, 18047, 18948 }, bars = { { 'Hoards', 3064, 'Halvung Brass', 9900 }, { 'Gems', 8961, 'Imperial Opal', 250 }, { 'Mats', 1458, nil, 12 } } },
            }},
            { name = 'Nehushtan', id = 21105, job = 'WHM/GEO', coin = 3952, chain = 3013, hoard = 3064, gem = 8965, mat = 1409, phases = {
                { result = 22006, reqs = { 17115, 17121, 17462, 2981 }, bars = { { 'Quadav Brass', 3952, 'Quadav Brass', 300 } } },
                { result = 21109, reqs = { 17416, 17454, 17463, 22006 }, bars = { { 'Quadav Brass', 3952, 'Quadav Brass', 500 }, { 'Chains', 3013, 'Quadav Chain', 10 } } },
                { result = 21105, reqs = { 21109, 17464, 18857 }, bars = { { 'Hoards', 3064, 'Halvung Brass', 9900 }, { 'Gems', 8965, 'Imperial Sapphire', 250 }, { 'Mats', 1409, nil, 12 } } },
            }},
            { name = 'Providence', id = 18626, job = 'SMN', coin = 3952, chain = 3013, hoard = 3064, gem = 8965, mat = 1462, phases = {
                { result = 22291, reqs = { 17126, 17127, 17571, 2982 }, bars = { { 'Quadav Brass', 3952, 'Quadav Brass', 300 } } },
                { result = 21172, reqs = { 17108, 17563, 17573, 22291 }, bars = { { 'Quadav Brass', 3952, 'Quadav Brass', 500 }, { 'Chains', 3013, 'Quadav Chain', 10 } } },
                { result = 18626, reqs = { 21172, 17576, 17528 }, bars = { { 'Hoards', 3064, 'Halvung Brass', 9900 }, { 'Gems', 8965, 'Imperial Sapphire', 250 }, { 'Mats', 1462, nil, 12 } } },
            }},
            { name = 'Doomsday', id = 21476, job = 'RNG/COR', coin = 3952, chain = 3013, hoard = 3064, gem = 8960, mat = 1467, phases = {
                { result = 22144, reqs = { 17254, 17260, 17271, 2983 }, bars = { { 'Quadav Brass', 3952, 'Quadav Brass', 300 } } },
                { result = 21275, reqs = { 17232, 17244, 17215, 22144 }, bars = { { 'Quadav Brass', 3952, 'Quadav Brass', 500 }, { 'Chains', 3013, 'Quadav Chain', 10 } } },
                { result = 21476, reqs = { 21275, 17245, 18706 }, bars = { { 'Hoards', 3064, 'Halvung Brass', 9900 }, { 'Gems', 8960, 'Imperial Garnet', 250 }, { 'Mats', 1467, nil, 12 } } },
            }},
        },
    },
    {
        name  = 'Arrapago',
        color = { 0.50, 0.88, 0.50, 1.00 },  -- green (Yagudo)
        weapons = {
            { name = 'Ipetam', id = 20616, job = 'THF/DNC', coin = 3953, chain = 3014, hoard = 3065, gem = 8963, mat = 1459, phases = {
                { result = 21566, reqs = { 16742, 16739, 17993, 2990 }, bars = { { 'Yagudo Silver', 3953, 'Yagudo Silver', 300 } } },
                { result = 20617, reqs = { 16767, 19120, 17994, 21566 }, bars = { { 'Yagudo Silver', 3953, 'Yagudo Silver', 500 }, { 'Chains', 3014, 'Yagudo Chain', 10 } } },
                { result = 20616, reqs = { 20617, 17996, 17619 }, bars = { { 'Hoards', 3065, 'Arrapago Silver', 9900 }, { 'Gems', 8963, 'Imperial Peridot', 250 }, { 'Mats', 1459, nil, 12 } } },
            }},
            { name = 'Izuna', id = 20989, job = 'NIN', coin = 3953, chain = 3014, hoard = 3065, gem = 8963, mat = 1468, phases = {
                { result = 21912, reqs = { 16925, 16921, 17786, 2991 }, bars = { { 'Yagudo Silver', 3953, 'Yagudo Silver', 300 } } },
                { result = 20993, reqs = { 19280, 16911, 17787, 21912 }, bars = { { 'Yagudo Silver', 3953, 'Yagudo Silver', 500 }, { 'Chains', 3014, 'Yagudo Chain', 10 } } },
                { result = 20989, reqs = { 20993, 18429, 18430 }, bars = { { 'Hoards', 3065, 'Arrapago Silver', 9900 }, { 'Gems', 8963, 'Imperial Peridot', 250 }, { 'Mats', 1468, nil, 12 } } },
            }},
            { name = 'Nenekirimaru', id = 21037, job = 'SAM', coin = 3953, chain = 3014, hoard = 3065, gem = 8963, mat = 1467, phases = {
                { result = 21976, reqs = { 16983, 16986, 17820, 2992 }, bars = { { 'Yagudo Silver', 3953, 'Yagudo Silver', 300 } } },
                { result = 21038, reqs = { 17813, 16980, 17821, 21976 }, bars = { { 'Yagudo Silver', 3953, 'Yagudo Silver', 500 }, { 'Chains', 3014, 'Yagudo Chain', 10 } } },
                { result = 21037, reqs = { 21038, 17823, 18446 }, bars = { { 'Hoards', 3065, 'Arrapago Silver', 9900 }, { 'Gems', 8963, 'Imperial Peridot', 250 }, { 'Mats', 1467, nil, 12 } } },
            }},
            { name = 'Keraunos', id = 21169, job = 'BLM/SCH', coin = 3953, chain = 3014, hoard = 3065, gem = 8961, mat = 1458, phases = {
                { result = 22088, reqs = { 17124, 17119, 17571, 2993 }, bars = { { 'Yagudo Silver', 3953, 'Yagudo Silver', 300 } } },
                { result = 21171, reqs = { 17586, 17564, 17572, 22088 }, bars = { { 'Yagudo Silver', 3953, 'Yagudo Silver', 500 }, { 'Chains', 3014, 'Yagudo Chain', 10 } } },
                { result = 21169, reqs = { 21171, 17575, 17567 }, bars = { { 'Hoards', 3065, 'Arrapago Silver', 9900 }, { 'Gems', 8961, 'Imperial Opal', 250 }, { 'Mats', 1458, nil, 12 } } },
            }},
            { name = 'Phaosphaelia', id = 21224, job = 'RNG', coin = 3953, chain = 3014, hoard = 3065, gem = 8962, mat = 1462, phases = {
                { result = 22133, reqs = { 17178, 17180, 17202, 2994 }, bars = { { 'Yagudo Silver', 3953, 'Yagudo Silver', 300 } } },
                { result = 21226, reqs = { 17187, 17212, 17203, 22133 }, bars = { { 'Yagudo Silver', 3953, 'Yagudo Silver', 500 }, { 'Chains', 3014, 'Yagudo Chain', 10 } } },
                { result = 21224, reqs = { 21226, 17165, 17199 }, bars = { { 'Hoards', 3065, 'Arrapago Silver', 9900 }, { 'Gems', 8962, 'Imperial Amethyst', 250 }, { 'Mats', 1462, nil, 12 } } },
            }},
            { name = 'Linos', id = 21404, job = 'BRD', coin = 3953, chain = 3014, hoard = 3065, gem = 8964, mat = 1409, phases = {
                { result = 22296, reqs = { 17370, 17375, 18170, 2995 }, bars = { { 'Yagudo Silver', 3953, 'Yagudo Silver', 300 } } },
                { result = 21406, reqs = { 17346, 17982, 17995, 22296 }, bars = { { 'Yagudo Silver', 3953, 'Yagudo Silver', 500 }, { 'Chains', 3014, 'Yagudo Chain', 10 } } },
                { result = 21404, reqs = { 21406, 17838, 17365 }, bars = { { 'Hoards', 3065, 'Arrapago Silver', 9900 }, { 'Gems', 8964, 'Imperial Citrine', 250 }, { 'Mats', 1409, nil, 12 } } },
            }},
        },
    },
};

TRF.LU.TORQUES = {
    { id = 15508, name = 'Justice Torque',     nm = 'Jailer of Justice' },
    { id = 15509, name = 'Hope Torque',        nm = 'Jailer of Hope' },
    { id = 15510, name = 'Prudence Torque',    nm = 'Jailer of Prudence' },
    { id = 15511, name = 'Fortitude Torque',   nm = 'Jailer of Fortitude' },
    { id = 15512, name = 'Faith Torque',       nm = 'Jailer of Faith' },
    { id = 15513, name = 'Temperance Torque',  nm = 'Jailer of Temperance' },
    { id = 15514, name = 'Love Torque',        nm = 'Jailer of Love' },
};

TRF.LU.WEAPONS = {
    { id = 17595, name = 'Hope Staff',       nm = 'Jailer of Hope' },
    { id = 17710, name = 'Justice Sword',    nm = 'Jailer of Justice' },
    { id = 17948, name = 'Temperance Axe',   nm = 'Jailer of Temperance' },
    { id = 18100, name = 'Love Halberd',     nm = 'Jailer of Love' },
    { id = 18222, name = 'Fortitude Axe',    nm = 'Jailer of Fortitude' },
    { id = 18360, name = 'Faith Baghnakhs',  nm = 'Jailer of Faith' },
    { id = 18397, name = 'Prudence Rod',     nm = 'Jailer of Prudence' },
};

TRF.LU.HOMAM = {
    { id = 15240, name = 'Homam Zucchetto', slot = 'Head',
      augs = {
          { 'Dual Wield+1, Mag.Acc.+1, Triple Atk.+1%' },
          { 'Dual Wield+2, Mag.Acc.+2, Triple Atk.+2%' },
          { 'Dual Wield+3, Mag.Acc.+3, Triple Atk.+3%' },
      },
    },
    { id = 14488, name = 'Homam Corazza', slot = 'Body',
      augs = {
          { 'Haste+1%, Great Sword Skill+3, Desperate Blows+2' },
          { 'Haste+2%, Great Sword Skill+4, Desperate Blows+3' },
          { 'Haste+3%, Great Sword Skill+5, Desperate Blows+4' },
      },
    },
    { id = 14905, name = 'Homam Manopolas', slot = 'Hands',
      augs = {
          { 'HP+15, Parrying Skill+3, Phys. Dmg. Taken-1%' },
          { 'HP+20, Parrying Skill+4, Phys. Dmg. Taken-2%' },
          { 'HP+25, Parrying Skill+5, Phys. Dmg. Taken-3%' },
      },
    },
    { id = 15576, name = 'Homam Cosciales', slot = 'Legs',
      augs = {
          { 'Conserve MP+3, Blue Magic Skill+3, Enh. Magic Duration+3' },
          { 'Conserve MP+4, Blue Magic Skill+4, Enh. Magic Duration+4' },
          { 'Conserve MP+5, Blue Magic Skill+5, Enh. Magic Duration+5' },
      },
    },
    { id = 15661, name = 'Homam Gambieras', slot = 'Feet',
      augs = {
          { 'STR+3, Polearm Skill+4, Meditate Duration+1' },
          { 'STR+4, Polearm Skill+5, Meditate Duration+2' },
          { 'STR+5, Polearm Skill+6, Meditate Duration+3' },
      },
    },
};

TRF.LU.NASHIRA = {
    { id = 15241, name = 'Nashira Turban', slot = 'Head',
      augs = {
          { 'MP+10, Fast Cast+1%, Conserve MP+1' },
          { 'MP+15, Fast Cast+2%, Conserve MP+2' },
          { 'MP+20, Fast Cast+3%, Conserve MP+3' },
      },
    },
    { id = 14489, name = 'Nashira Manteel', slot = 'Body',
      augs = {
          { 'Enh. Mag. Skill+3, Conserve MP+1, Enh. Magic Duration+3' },
          { 'Enh. Mag. Skill+4, Conserve MP+2, Enh. Magic Duration+4' },
          { 'Enh. Mag. Skill+5, Conserve MP+3, Enh. Magic Duration+5' },
      },
    },
    { id = 14906, name = 'Nashira Gages', slot = 'Hands',
      augs = {
          { 'MP+8, Blood Boon+3, B.P. Ability Delay-1' },
          { 'MP+10, Blood Boon+4, B.P. Ability Delay-2' },
          { 'MP+12, Blood Boon+5, B.P. Ability Delay-3' },
      },
    },
    { id = 15577, name = 'Nashira Seraweels', slot = 'Legs',
      augs = {
          { 'INT+1, MND+1, Enfeebling Magic Duration+3' },
          { 'INT+2, MND+2, Enfeebling Magic Duration+4' },
          { 'INT+3, MND+3, Enfeebling Magic Duration+5' },
      },
    },
    { id = 15662, name = 'Nashira Crackows', slot = 'Feet',
      augs = {
          { 'MP+8, INT+2, Mag. Atk. Bonus+1' },
          { 'MP+10, INT+3, Mag. Atk. Bonus+2' },
          { 'MP+12, INT+4, Mag. Atk. Bonus+3' },
      },
    },
};

TRF.LU.OMEGA_PIECES = {
    { id = 1925, name = "Omega's Eye" },
    { id = 1926, name = "Omega's Heart" },
    { id = 1927, name = "Omega's Foreleg" },
    { id = 1928, name = "Omega's Hind Leg" },
    { id = 1929, name = "Omega's Tail" },
};

TRF.LU.ULTIMA_PIECES = {
    { id = 1920, name = "Ultima's Cerebrum" },
    { id = 1921, name = "Ultima's Heart" },
    { id = 1922, name = "Ultima's Claw" },
    { id = 1923, name = "Ultima's Leg" },
    { id = 1924, name = "Ultima's Tail" },
};

TRF.LU.ORGANS = {
    { id = 1784, name = 'Phuabo Organ' },
    { id = 1785, name = 'Xzomit Organ' },
    { id = 1786, name = 'Aern Organ' },
    { id = 1787, name = 'Hpemde Organ' },
    { id = 1788, name = 'Yovra Organ' },
    { id = 1818, name = 'Euvhi Organ' },
    { id = 1852, name = 'H.Q. Phuabo Organ', hq = true },
    { id = 1855, name = 'H.Q. Xzomit Organ', hq = true },
    { id = 1900, name = 'H.Q. Aern Organ',   hq = true },
    { id = 1871, name = 'H.Q. Hpemde Organ', hq = true },
    { id = 1899, name = 'H.Q. Euvhi Organ',  hq = true },
    { id = 1819, name = 'Luminion Chip' },
};

TRF.LU.BUFFS = {
    { name = "Sniper's Salvo",        desc = 'Ranged Accuracy+15, Ranged Attack+15',       nm = "Al'Xzomit",       zone = "Al'Taieu",                pos = '(J-13)', chip = 1906, chipName = 'Emerald Chip', jobs = 'RNG, NIN, COR' },
    { name = "Rogue's Retribution",   desc = 'DEX+5, Critical Hit Rate+10%',               nm = "Al'Ghrah",        zone = "Garden of Ru'Hmet",       pos = '(I-8)',  chip = 1905, chipName = 'Scarlet Chip', jobs = 'THF, DRG, BST' },
    { name = "Warlord's Wrath",       desc = 'Enmity+5, Double Attack+10%',                nm = "Al'Euvhi",        zone = "Garden of Ru'Hmet",       pos = '(H-10)', chip = 1905, chipName = 'Scarlet Chip', jobs = 'WAR, SAM' },
    { name = "Scholar's Swiftness",   desc = 'Fast Cast+10%, Movement Speed+10%',          nm = "Al'Hpemde",       zone = "Al'Taieu",                pos = '(D-9)',  chip = 1906, chipName = 'Emerald Chip', jobs = 'RDM, SMN, SCH' },
    { name = "Rambler's Respite",     desc = 'HP/MP Rec. +10, Mag. Def.+15',               nm = "Al'Zdei",         zone = "Grand Palace of Hu'Xzoi", pos = '(L-8)',  chip = 1904, chipName = 'Ivory Chip',   jobs = 'MNK, BRD, PUP' },
    { name = "Cleric's Clarity",      desc = 'MND+5, Cure Potency+10%',                    nm = "Al'Aern",         zone = "Grand Palace of Hu'Xzoi", pos = '(I-7)',  chip = 1904, chipName = 'Ivory Chip',   jobs = 'WHM, PLD, DNC' },
    { name = "Thaumaturge's Tempest", desc = 'INT+5, Mag. Atk. Bonus+10',                  nm = "Al'Phuabo",       zone = "Al'Taieu",                pos = '(M-9)',  chip = 1906, chipName = 'Emerald Chip', jobs = 'BLM, DRK, BLU' },
    { name = "Ronin's Revenge",       desc = 'WS Accuracy+10, Store TP+8',                 nm = 'Justice Warden',  zone = "Al'Taieu",                pos = '(D-11)', chip = 2127, chipName = 'Metal Chip',   jobs = 'All Jobs' },
    { name = "Trickster's Tenacity",  desc = 'AGI+5, Evasion+15, Mag. Dmg. Taken-8%',     nm = 'Prudence Warden', zone = "Al'Taieu",                pos = '(L-9)',  chip = 2127, chipName = 'Metal Chip',   jobs = 'All Jobs' },
    { name = "Braver's Bulwark",      desc = 'DEF+15, Phys. Dmg. Taken-8%',                nm = 'Hope Warden',     zone = "Al'Taieu",                pos = '(E-9)',  chip = 2127, chipName = 'Metal Chip',   jobs = 'All Jobs' },
};

------------------------------------------------------------------------
-- STARS: ventures (by zone) and VNM armour pieces you care about. A starred zone, or a venture that drops a
-- starred piece, gets chat and sound warnings at 90%, at 100%, and a minute before the pop.
------------------------------------------------------------------------
TRF.ST = { seen = {}, ready = false, at = 0 };
TRF.ST.parsed = {};
function TRF.ST.set(key)                                         -- (kept in the settings as "a,b,c"; read again only when it changes)
    local raw = tostring(config[key] or '');
    local P = TRF.ST.parsed[key];
    if P and P.raw == raw then return P.set; end
    local s = {};
    for part in raw:gmatch('[^,]+') do s[part] = true; end
    TRF.ST.parsed[key] = { raw = raw, set = s };
    return s;
end
function TRF.ST.save(key, s)
    TRF.ST.pieces = {};
    local list = {};
    for k in pairs(s) do list[#list + 1] = k; end
    table.sort(list);
    config[key] = table.concat(list, ',');
    saveSettings();
end
function TRF.ST.zk(v)                                          -- (a venture's zone key, worked out once per zone name)
    local c = TRF.ST.zkc or {};
    TRF.ST.zkc = c;
    local n = v.zone_name or '';
    if c[n] == nil then c[n] = zoneKey(n); end
    return c[n];
end
function TRF.ST.zoneStarred(v) return v and v.zone_name and TRF.ST.set('star_zones')[TRF.ST.zk(v)] or false; end
function TRF.ST.toggleZone(v)
    local s = TRF.ST.set('star_zones');
    local k = TRF.ST.zk(v);
    if s[k] then s[k] = nil; msg(('Unstarred %s.'):fmt(v.zone_name)); else s[k] = true; msg(('Starred %s: VenGo will warn you at 90%%, 100%% and before the pop.'):fmt(v.zone_name)); end
    TRF.ST.save('star_zones', s);
end
function TRF.ST.itemStarred(id) return TRF.ST.set('star_items')[tostring(id)] or false; end
function TRF.ST.toggleItem(id)
    local s = TRF.ST.set('star_items');
    local k = tostring(id);
    if s[k] then s[k] = nil; msg(('Unstarred %s.'):fmt(TRF.AR.name(id)));
    else s[k] = true; msg(('Starred %s: VenGo will warn you when a venture that drops it is up.'):fmt(TRF.AR.name(id))); end
    TRF.ST.save('star_items', s);
end
-- The starred pieces a venture drops (the zone's armour drops, matched by grid square where a zone is listed twice)
TRF.ST.pieces = {};
TRF.ST.NONE = {};
function TRF.ST.piecesOf(v)
    local items = TRF.ST.set('star_items');
    if next(items) == nil or v == nil or v.zone_name == nil then return TRF.ST.NONE; end
    local ck = (v.zone_name or '') .. '|' .. tostring(v.grid) .. '|' .. tostring(config.star_items);
    local hit = TRF.ST.pieces[ck];
    if hit then return hit; end
    local out = {};
    TRF.ST.pieces[ck] = out;
    if TRF.AR.dropZK == nil then
        TRF.AR.dropZK = {};
        for i, d in ipairs(TRF.AR.DROPS) do TRF.AR.dropZK[i] = zoneKey(d[1]); end
    end
    local zk = TRF.ST.zk(v);
    local m = {};
    for i, d in ipairs(TRF.AR.DROPS) do if TRF.AR.dropZK[i] == zk then m[#m + 1] = d; end end
    if #m > 1 and v.grid then
        local m2 = {};
        for _, d in ipairs(m) do if d[5] and d[5]:upper() == tostring(v.grid):upper() then m2[#m2 + 1] = d; end end
        if #m2 > 0 then m = m2; end
    end
    for _, d in ipairs(m) do
        for _, set in ipairs(TRF.AR.SETS) do
            local id = set.tiers[d[2]][d[3]];
            if items[tostring(id)] then out[#out + 1] = id; end
        end
    end
    return out;
end
function TRF.ST.watched(v) return TRF.ST.zoneStarred(v) or #TRF.ST.piecesOf(v) > 0; end
function TRF.ST.why(v)
    local p = TRF.ST.piecesOf(v);
    if #p == 0 then return ''; end
    local n = {};
    for i, id in ipairs(p) do if i <= 3 then n[#n + 1] = TRF.AR.name(id); end end
    return ' (drops ' .. table.concat(n, ', ') .. ((#p > 3) and ', ...' or '') .. ')';
end
function TRF.ST.ping(text)
    if config.star_chat ~= false then msg('[Star] ' .. text); end
    if config.star_sound ~= false then
        local was = config.alert_sound;
        config.alert_sound = true;                               -- (its own switch, not the alert one)
        pcall(TRF.playAlertSound);
        config.alert_sound = was;
    end
end
-- Once a second: 90%, 100%, and a minute before the pop, once each per venture and zone
function TRF.ST.tick()
    local ST = TRF.ST;
    local now = os.clock();
    if now - ST.at < 1 then return; end
    ST.at = now;
    for _, v in ipairs(ventures) do
        if v.key and v.zone_name and TRF.ST.watched(v) then
            local id = v.key .. '|' .. tostring(v.zone);
            local s = ST.seen[id];
            local p = v.progress or 0;
            if s == nil then
                s = { p90 = p >= 90, p100 = p >= 100, pop = false };   -- (what's already true when VenGo starts: no ping)
                if not ST.ready then ST.seen[id] = s; else ST.seen[id] = { p90 = false, p100 = false, pop = false }; s = ST.seen[id]; end
            end
            if p < 90 then s.p90, s.p100, s.pop = false, false, false; end
            if p >= 90 and p < 100 and not s.p90 then
                s.p90 = true;
                ST.ping(('%s (%s, %s) is at %d%%%s.'):fmt(v.nm or 'The VNM', v.zone_name, v.grid or '?', p, ST.why(v)));
            end
            if p >= 100 and not s.p100 then
                s.p90, s.p100 = true, true;
                local left = popLeft(v);
                ST.ping(('%s (%s, %s) is at 100%%%s%s.'):fmt(v.nm or 'The VNM', v.zone_name, v.grid or '?',
                    left and left > 0 and (', pops ' .. popWords(left)) or '', ST.why(v)));
            end
            local left = popLeft(v);
            if left and left > 0 and left <= 60 and not s.pop then
                s.pop = true;
                if not (ALERT and ALERT.v == v and ALERT.warned) then
                    ST.ping(('%s pops in about a minute (%s, %s).'):fmt(v.nm or 'The VNM', v.zone_name, v.grid or '?'));
                end
            end
        end
    end
    ST.ready = true;
end
-- A star (5 points), filled or outlined
function TRF.ST.draw(dl, cx, cy, r, col, filled)
    local pts = {};
    for i = 0, 9 do
        local a = -math.pi / 2 + i * math.pi / 5;
        local rr = (i % 2 == 0) and r or r * 0.45;
        pts[#pts + 1] = { cx + math.cos(a) * rr, cy + math.sin(a) * rr };
    end
    if filled then
        for i = 0, 4 do
            dl:AddTriangleFilled({ cx, cy }, pts[i * 2 + 1], pts[(i * 2 + 1) % 10 + 1], u32(col));
            dl:AddTriangleFilled({ cx, cy }, pts[(i * 2 + 1) % 10 + 1], pts[(i * 2 + 2) % 10 + 1], u32(col));
        end
    else
        for i = 1, 10 do dl:AddLine(pts[i], pts[i % 10 + 1], u32(col), 1.3); end
    end
end
-- The star button on a venture row: gold when the zone is starred, violet when it's watched for a starred piece
function TRF.ST.button(v)
    local h = imgui.GetFrameHeight();
    local x, y = imgui.GetCursorScreenPos();
    local clicked = imgui.InvisibleButton('##vengo_star' .. tostring(v.key), { 22, h });
    local hov = imgui.IsItemHovered();
    local dl = imgui.GetWindowDrawList();
    local zs = TRF.ST.zoneStarred(v);
    local pieces = TRF.ST.piecesOf(v);
    local col = zs and C.gold or (#pieces > 0 and C.mp2 or { 1, 1, 1, hov and 0.7 or 0.3 });
    if zs or #pieces > 0 then dl:AddCircleFilled({ x + 11, y + h / 2 }, 10, u32({ col[1], col[2], col[3], 0.15 }), 16); end
    TRF.ST.draw(dl, x + 11, y + h / 2, 7, { col[1], col[2], col[3], 1 }, zs or #pieces > 0);
    if hov then
        local t = zs and ('Starred: you\'ll be warned about %s at 90%%, 100%% and before the pop. Click to unstar.'):fmt(v.zone_name)
            or (#pieces > 0 and ('Watched: it drops a piece you starred%s. Click to star the zone too.'):fmt(TRF.ST.why(v)))
            or ('Star %s: warnings at 90%%, 100%% and a minute before the pop.'):fmt(v.zone_name or 'this venture');
        imgui.SetTooltip(t);
    end
    if clicked then TRF.ST.toggleZone(v); end
end

------------------------------------------------------------------------
-- CONTROLLER: VenGo's window takes the controller (VanaCore hands it over; the d-pad moves between buttons,
-- A presses, the game doesn't see them). /vengo pad or the button in Settings; Back / Select gives it back.
------------------------------------------------------------------------
TRF.PAD = { on = false, focus = false };
function TRF.PAD.set(on)
    if on and not (rawget(_G, 'vana') and vana.gamepad and vana.gamepad.nav) then
        msg('This VanaCore has no controller hand-over (vana.gamepad.nav); the controller can\'t drive VenGo here.');
        return;
    end
    TRF.PAD.on = on;
    if on then
        ui.open[1] = true;
        if config.minimized then config.minimized = false; saveSettings(); end
        TRF.PAD.focus = true;
        msg('VenGo has the controller: d-pad to move, A to press. Back / Select (or /vengo pad) gives it back.');
    else
        pcall(vana.gamepad.nav, false);
        msg('The controller is back with the game.');
    end
end
function TRF.PAD.frame()
    if not TRF.PAD.on then return; end
    if not ui.open[1] or config.minimized then TRF.PAD.set(false); return; end
    pcall(vana.gamepad.nav, true);
end
pcall(function ()
    ashita.events.register('xinput_button', 'vengo_pad_x', function (e)
        if TRF.PAD.on and e.button == 5 and (e.state or 0) ~= 0 then  -- (Back)
            TRF.PAD.set(false);
            e.blocked = true;
            return true;
        end
    end);
    ashita.events.register('dinput_button', 'vengo_pad_d', function (e)
        if TRF.PAD.on and e.button == 56 and (e.state or 0) >= 128 then -- (Share / Select on most pads)
            TRF.PAD.set(false);
            e.blocked = true;
            return true;
        end
    end);
end);

------------------------------------------------------------------------
-- UPDATES: VenGo asks GitHub for ChadBrowick/VenGo's latest release (in the background, with Windows' curl.exe)
-- at load and every 6 hours, and offers it when it's newer. INSTALL downloads that release's zip (only from that
-- repository) and unpacks it over the vengo folder with Windows' tar.exe; your settings aren't in the zip.
------------------------------------------------------------------------
TRF.UP = { REPO = 'ChadBrowick/VenGo', at = nil, nextAt = 0, pending = nil, latest = nil, err = nil, install = nil };
TRF.UP.API = 'https://api.github.com/repos/' .. TRF.UP.REPO .. '/releases/latest';
TRF.UP.PAGE = 'https://github.com/' .. TRF.UP.REPO .. '/releases/latest';
function TRF.UP.file(n) return addon.path .. n; end
function TRF.UP.shell(exe, args)
    local ok, err = pcall(function ()
        local ffi = require('ffi');
        pcall(ffi.cdef, 'void* __stdcall ShellExecuteA(void* hwnd, const char* op, const char* file, const char* params, const char* dir, int show);');
        local r = ffi.load('shell32').ShellExecuteA(nil, 'open', exe, args, nil, (exe:find('^https://')) and 1 or 0);
        if tonumber(ffi.cast('intptr_t', r)) <= 32 then error(exe .. ' could not be started'); end
    end);
    return ok, err;
end
function TRF.UP.newer(a, b)                                      -- (is version a newer than b? "4.32" vs "4.4")
    local function parts(s) local t = {}; for n in tostring(s or ''):gmatch('%d+') do t[#t + 1] = tonumber(n); end return t; end
    local pa, pb = parts(a), parts(b);
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0;
        if x ~= y then return x > y; end
    end
    return false;
end
function TRF.UP.ask()
    local U = TRF.UP;
    if U.pending then return; end
    os.remove(U.file('update_check.tmp'));
    local ok, err = U.shell('curl.exe', ('-s -f -L -m 20 -A "VenGo/%s" -H "Accept: application/vnd.github+json" -o "%s" "%s"')
        :format(addon.version, U.file('update_check.tmp'), U.API));
    if ok then U.pending = os.time(); else U.err = tostring(err); end
end
function TRF.UP.tick()
    local U = TRF.UP;
    if config.check_updates == false then return; end
    local c = os.clock();
    if c - (U.tickAt or -1) < 0.5 then return; end
    U.tickAt = c;
    local now = os.time();
    if U.pending then
        local f = io.open(U.file('update_check.tmp'), 'rb');
        local body = f and f:read('*a');
        if f then f:close(); end
        local data = body and body ~= '' and TRF.jsonDecode(body) or nil;
        if data and data.tag_name then
            U.pending, U.at, U.err = nil, now, nil;
            local zip = nil;
            for _, a in ipairs(data.assets or {}) do
                local u = tostring(a.browser_download_url or '');
                if u:lower():find('%.zip$') and u:find('^https://github%.com/' .. U.REPO:gsub('%p', '%%%0') .. '/releases/download/') then zip = u; end
            end
            U.latest = { tag = tostring(data.tag_name), url = tostring(data.html_url or U.PAGE), zip = zip,
                         notes = tostring(data.body or ''):gsub('\r', '') };
            if TRF.UP.newer(U.latest.tag, addon.version) and U.told ~= U.latest.tag then
                U.told = U.latest.tag;
                msg(('VenGo %s is out (you have %s). See Settings > Updates, or type /vengo upgrade.'):fmt(U.latest.tag, addon.version));
            end
            os.remove(U.file('update_check.tmp'));
        elseif now - U.pending > 25 then
            U.pending, U.err = nil, 'GitHub didn\'t answer';
            os.remove(U.file('update_check.tmp'));
        end
    elseif now >= U.nextAt then
        U.nextAt = now + ((U.at == nil and U.nextAt == 0) and 30 or 6 * 3600);   -- (30 s after loading, then every 6 hours)
        if U.at ~= nil or U.first then U.ask(); end
        U.first = true;
    end
    local I = U.install;                                         -- (an install under way)
    if I then
        if I.step == 'download' then
            local f = io.open(U.file('update.zip'), 'rb');
            local size = f and f:seek('end') or 0;
            if f then f:close(); end
            if size > 1000 and size == I.size then                   -- (it stopped growing: done)
                I.step, I.at = 'unpack', now;
                local parent = addon.path:gsub('[\\/]+$', ''):match('^(.*)[\\/][^\\/]+$');
                local ok = U.shell('tar.exe', ('-xf "%s" -C "%s"'):format(U.file('update.zip'), parent));
                if not ok then msg('Couldn\'t start tar.exe to unpack the update. Unzip update.zip in the vengo folder yourself.'); U.install = nil; end
            elseif now - I.at > 90 then
                msg('The update download didn\'t finish. Try again, or get it from the release page.'); U.install = nil;
            end
            I.size = size;
        elseif I.step == 'unpack' and now - I.at >= 3 then
            local f = io.open(addon.path .. 'vengo.lua', 'rb');
            local head = f and f:read(4096) or '';
            if f then f:close(); end
            local v = head:match("addon%.version%s*=%s*'([^']+)'");
            if v == I.tag or not TRF.UP.newer(I.tag, v) then
                msg(('VenGo %s is installed. Type /addon reload vengo to start it.'):fmt(I.tag));
                os.remove(U.file('update.zip'));
                U.install = nil;
                U.done = I.tag;
            elseif now - I.at > 20 then
                msg('The update didn\'t unpack. update.zip is in the vengo folder: unzip it over the vengo folder yourself.');
                U.install = nil;
            end
        end
    end
end
function TRF.UP.installNow()
    local U = TRF.UP;
    local L = U.latest;
    if L == nil or not L.zip then msg('No zip to install on that release: opening its page.'); U.shell(L and L.url or U.PAGE, ''); return; end
    if U.install then return; end
    os.remove(U.file('update.zip'));
    local ok = U.shell('curl.exe', ('-s -f -L -m 60 -A "VenGo/%s" -o "%s" "%s"'):format(addon.version, U.file('update.zip'), L.zip));
    if ok then
        U.install = { step = 'download', at = os.time(), tag = L.tag, size = -1 };
        msg(('Downloading VenGo %s from github.com/%s...'):fmt(L.tag, U.REPO));
    else
        msg('Couldn\'t start curl.exe to download the update.');
    end
end
-- On the Ventures tab: a slim notice when a newer VenGo is out
function TRF.UP.notice()
    local L = TRF.UP.latest;
    if config.check_updates == false or L == nil or not TRF.UP.newer(L.tag, addon.version) or TRF.UP.done == L.tag then return; end
    local dl = imgui.GetWindowDrawList();
    local x, y = imgui.GetCursorScreenPos();
    local h = 34;
    TRF.card(dl, x, y, ROW_W, h, 'on', false, 8);
    dl:AddText({ x + 14, y + (h - imgui.GetTextLineHeight()) / 2 }, u32(C.text), ('VenGo %s is out (you have %s).'):fmt(L.tag, addon.version));
    imgui.SetCursorScreenPos({ x + ROW_W - 270, y + 5 });
    if button('INSTALL##vengo_up_i', { 120, h - 10 }, false, true) then TRF.UP.installNow(); end
    imgui.SameLine(0, 8);
    if button('WHAT\'S NEW##vengo_up_n', { 130, h - 10 }, true, true) then ui.tab = 11; end
    imgui.SetCursorScreenPos({ x, y + h + 8 });
    imgui.Dummy({ ROW_W, 1 });
end

-- Settings: Starred, Controller, Updates
TRF.extraSettings = function()
    section('Starred');
    if rowSwitch('##vengo_star_chat', 'Chat warnings for starred VNMs', config.star_chat ~= false,
            'At 90%, at 100% and a minute before the pop, for starred zones and ventures that drop a starred armour piece') then
        config.star_chat = not (config.star_chat ~= false); saveSettings();
    end
    if rowSwitch('##vengo_star_snd', 'Sound for starred VNMs', config.star_sound ~= false, 'The alert sound with each warning') then
        config.star_sound = not (config.star_sound ~= false); saveSettings();
    end
    local zs, is_ = TRF.ST.set('star_zones'), TRF.ST.set('star_items');
    local nz, ni = 0, 0;
    for _ in pairs(zs) do nz = nz + 1; end
    for _ in pairs(is_) do ni = ni + 1; end
    imgui.TextColored(C.muted, ('Starred: %d zone(s), %d armour piece(s).'):fmt(nz, ni));
    if (nz + ni) > 0 then
        imgui.SameLine(0, 14);
        if button('CLEAR STARS##vengo_star_clr', { 0, 0 }, true, true) then config.star_zones, config.star_items = '', ''; saveSettings(); msg('Stars cleared.'); end
    end
    hint('Star a venture with the star by its GO button, or click a piece on the VNM ARMOR tab: any venture that drops it is watched.');

    section('Controller');
    if button((TRF.PAD.on and 'GIVE CONTROLLER BACK' or 'USE CONTROLLER') .. '##vengo_pad', { 320, 0 }) then TRF.PAD.set(not TRF.PAD.on); end
    hint('VenGo takes the controller: the d-pad moves between buttons and tabs, A presses. Back / Select gives it back to the game. Put /vengo pad in a macro to switch from the game.');
end

-- Settings: Updates (at the top of the tab)
TRF.updateSettings = function()
    section('Updates');
    if rowSwitch('##vengo_upd', 'Check GitHub for new versions', config.check_updates ~= false,
            'Looks at github.com/' .. TRF.UP.REPO .. ' 30 seconds after loading and every 6 hours') then
        config.check_updates = not (config.check_updates ~= false); saveSettings();
    end
    local U = TRF.UP;
    local L = U.latest;
    local st;
    if U.install then st = (U.install.step == 'download') and 'downloading...' or 'unpacking...';
    elseif U.pending then st = 'checking...';
    elseif L and TRF.UP.newer(L.tag, addon.version) and U.done ~= L.tag then st = ('%s is out (you have %s)'):fmt(L.tag, addon.version);
    elseif U.done then st = U.done .. ' installed: type /addon reload vengo';
    elseif L then st = ('up to date (%s)'):fmt(addon.version);
    else st = U.err or 'not checked yet'; end
    imgui.TextColored(C.text, 'GitHub: ' .. st);
    if button('CHECK NOW##vengo_upc', { 200, 0 }, true, true) then U.ask(); end
    if L and TRF.UP.newer(L.tag, addon.version) and U.done ~= L.tag then
        imgui.SameLine(0, 10);
        if button('INSTALL ' .. L.tag .. '##vengo_upi', { 200, 0 }) then U.installNow(); end
        imgui.SameLine(0, 10);
        if button('OPEN PAGE##vengo_upo', { 160, 0 }, true, true) then U.shell(L.url, ''); end
        if L.notes ~= '' then
            imgui.Spacing();
            imgui.PushTextWrapPos(imgui.GetCursorPosX() + ROW_W);
            imgui.TextColored(C.muted, (L.notes:gsub('%*%*', ''):gsub('%[([^%]]+)%]%([^%)]+%)', '%1')));
            imgui.PopTextWrapPos();
        end
    end
    hint('INSTALL downloads that release\'s zip from github.com/' .. TRF.UP.REPO .. ' only, unpacks it over the vengo folder (your settings, stars and presets aren\'t in it), then you type /addon reload vengo.');
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
TRF.PRESET_KEYS = { 'transparent', 'alerts', 'alert_sound', 'alert90', 'mode', 'pool', 'sort', 'website', 'login_refresh', 'logo_anim',
    'trail', 'trail_glow', 'trail_color', 'trail_style', 'trail_size', 'theme', 'bg', 'lite',
    'seal_check', 'seal_scan', 'cam_every', 'trail_range', 'trail_scale', 'trail_spacing', 'trail_speed', 'glow_q',
    'star_zones', 'star_items', 'star_chat', 'star_sound', 'check_updates' };
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
            for _, k in ipairs(TRF.PRESET_KEYS) do
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
            for _, k in ipairs(TRF.PRESET_KEYS) do c_[k] = config[k]; end
            TRF.slots[i] = { at = os.date('%b %d  %I:%M %p'), cfg = c_ };
            TRF.savePresets();
            msg(('Settings saved to slot %d.'):format(i));
        end
        imgui.SameLine(0, 10);
        if s then
            if button(('LOAD##vengo_pl%d'):format(i), { 120, 0 }, false, true) then
                for _, k in ipairs(TRF.PRESET_KEYS) do if s.cfg[k] ~= nil then config[k] = s.cfg[k]; end end
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
    if CAM.listening['d3d_dip'] and not CAM.listening['d3d_dp'] then                      -- (did the indexed draws show a camera?)
        if #CAM.cands == 0 then CAM.dipEmpty = (CAM.dipEmpty or 0) + 1; else CAM.dipEmpty = 0; end
    end
    if want then CAM.cands, CAM.tries = {}, 0; end
    CAM.max = 800;
    CAM.on = want;
    CAM.setListening(want);
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
    if dist < ((kind == 'grid') and 5 or 2.5) then return; end
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
-- The game's draw calls (thousands a frame) are listened to ONLY on the frames the camera is read, and only while
-- arrows are wanted: just being listened to costs a call into VenGo per draw, which was what cost FPS all the time.
-- Indexed draws first (the world is drawn with them); the other kind too only if those show no camera.
CAM.listening = {};
function CAM.listen(name, on)
    if (CAM.listening[name] or false) == on then return; end
    local key = 'vengo_cam_' .. name;
    local ok = false;
    if rawget(_G, 'vana') and type(vana.on) == 'function' and type(vana.off) == 'function' then
        ok = pcall(function ()
            if on then vana.on(name, function () camSample(); end, key); else vana.off(name, key); end
        end);
    end
    if not ok then
        pcall(function ()
            if on then ashita.events.register(name, key, function () camSample(); end);
            else ashita.events.unregister(name, key); end
        end);
    end
    CAM.listening[name] = on;
end
function CAM.setListening(on)
    CAM.listen('d3d_dip', on);
    CAM.listen('d3d_dp', on and (CAM.dipEmpty or 0) >= 30);   -- (30 frames of indexed draws with no camera: try the others)
end
end

local function tabSettings()
    TRF.updateSettings();

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
    TRF.extraSettings();

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
    local starred = TRF.ST and TRF.ST.watched(v) or false;
    local gc = starred and C.gold or NEON2;                       -- (the glow: gold for a starred VNM)
    local nc, nv = pushTheme();
    local pulse = 0.55 + 0.45 * math.sin(os.clock() * 4);
    imgui.PushStyleColor(ImGuiCol_WindowBg, { 0.05, 0.04, 0.07, config.transparent and 0.70 or 0.95 });
    imgui.PushStyleColor(ImGuiCol_Border, { gc[1], gc[2], gc[3], 0.65 + 0.35 * pulse });
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 22, 16 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 3);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 10);
    nc, nv = nc + 2, nv + 3;
    local ds = imgui.GetIO().DisplaySize;
    imgui.SetNextWindowPos({ ((ds and ds.x) or 1920) / 2, 70 }, ImGuiCond_FirstUseEver, { 0.5, 0 });
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoFocusOnAppearing);
    local pushed = pushFont(fonts.panel, 16);
    if imgui.Begin('VenGo alert##vengo_alert', { true }, flags) then
        local dl = imgui.GetWindowDrawList();
        -- a bright glow all round the banner, behind it, pulsing
        pcall(function ()
            local wx, wy = imgui.GetWindowPos();
            local ww, wh = imgui.GetWindowSize();
            local bg = imgui.GetBackgroundDrawList and imgui.GetBackgroundDrawList() or nil;
            if bg == nil then return; end
            for i = 1, 9 do
                local g = i * 2.4;
                local a = (0.20 - i * 0.02) * (0.55 + 0.45 * pulse) * (starred and 1.3 or 1);
                bg:AddRect({ wx - g, wy - g }, { wx + ww + g, wy + wh + g }, u32({ gc[1], gc[2], gc[3], math.max(0, a) }), 10 + g, C.rall, 3);
            end
        end);
        local x0, y0 = imgui.GetCursorScreenPos();
        local lh = imgui.GetTextLineHeight();
        local sx = x0;
        if starred then                                          -- (a gold star before the title)
            TRF.ST.draw(dl, x0 + 7, y0 + lh / 2, 7, { C.gold[1], C.gold[2], C.gold[3], 0.7 + 0.3 * pulse }, true);
            sx = x0 + 20;
        end
        local w = spaced(dl, sx, y0, starred and 'STARRED VNM INCOMING' or 'VNM INCOMING',
            u32({ gc[1], gc[2], gc[3], 0.7 + 0.3 * pulse }), 3);
        imgui.Dummy({ w + (sx - x0), lh });

        local tp = pushFont(fonts.big, 26);
        if not tp then imgui.SetWindowFontScale(1.35); end
        if starred then
            local nx, ny = imgui.GetCursorScreenPos();
            local nh = imgui.GetTextLineHeight();
            dl:AddCircleFilled({ nx + 11, ny + nh / 2 }, 13, u32({ C.gold[1], C.gold[2], C.gold[3], 0.18 * pulse }), 20);
            TRF.ST.draw(dl, nx + 11, ny + nh / 2, 10, C.gold, true);
            imgui.Dummy({ 26, nh });
            imgui.SameLine(0, 6);
        end
        imgui.TextColored(C.text, v.nm);
        if tp then imgui.PopFont(); else imgui.SetWindowFontScale(1); end
        if starred then
            local why = TRF.ST.zoneStarred(v) and 'You starred this zone' or 'Drops a piece you starred';
            local ps = TRF.ST.piecesOf(v);
            local names = {};
            for i, id in ipairs(ps) do if i <= 3 then names[#names + 1] = TRF.AR.name(id); end end
            if #names > 0 then why = why .. ': ' .. table.concat(names, ', '); end
            imgui.TextColored(C.gold, why);
        end

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
    if TRF.PAD.focus then TRF.PAD.focus = false; pcall(imgui.SetNextWindowFocus); end
    if imgui.Begin('VenGo##vengo_main', { true }, flags) then
        TRF.PAD.frame();
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
            elseif ui.tab == 7 then TRF.armorTab();
            elseif ui.tab == 8 then TRF.ulTab();
            elseif ui.tab == 9 then TRF.luTab();
            elseif ui.tab == 10 then TRF.cxTab();
            elseif ui.tab == 11 then tabSettings();
            elseif ui.tab == 12 then tabThanks();
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
    pcall(TRF.ST.tick);
    pcall(TRF.UP.tick);
    pcall(TRF.BAG.step);
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
        msg('Usage: /vengo (window) | <nm|zone|shorthand> (warp there) | current | next | cancel | ventures | mode ace|cw | update | reload | testalert | where | pad (controller) | upgrade (install a new VenGo)');
    elseif cmd == 'cancel' or cmd == 'stop' then
        ARMED = nil;
        msg('Cancelled.');
    elseif cmd == 'refresh' then
        refreshBoard();
    elseif cmd == 'pad' or cmd == 'controller' then
        TRF.PAD.set(not TRF.PAD.on);
    elseif cmd == 'upgrade' then
        local L = TRF.UP.latest;
        if L and TRF.UP.newer(L.tag, addon.version) then TRF.UP.installNow();
        else msg('Checking GitHub for a new VenGo...'); TRF.UP.ask(); end
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
    if e ~= nil and e.id == 0x1A4 then                           -- (the CatsEyeXI server's answers: currency, Lumoria)
        pcall(TRF.TV.packet, e.data_modified or e.data);
        e.blocked = true;                                         -- (the game itself doesn't know this packet)
        return;
    end
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

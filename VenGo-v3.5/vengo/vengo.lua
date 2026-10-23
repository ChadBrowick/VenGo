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
addon.version = '3.5';
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
    for _, k in ipairs({ 'transparent', 'minimized', 'alerts', 'alert_sound', 'alert90', 'mode', 'pool', 'sort' }) do
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
local function gridToWorld(zid, grid, mapNo)
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
local function worldToGrid(zid, wx, wy)
    local e = mapEntries(zid)[1];
    if e == nil then return nil; end
    local mx, my = worldToMap(e, wx, wy);
    local col = math.floor((mx - GRID_EDGE) / GRID_SIZE);
    local row = math.floor((my - GRID_EDGE) / GRID_SIZE);
    if col < 0 or col > 25 or row < 0 then return '?'; end
    return ('%s-%d'):fmt(string.char(65 + col), row + 1);
end

------------------------------------------------------------------------
-- VNM alerts: Populox announces a spawning VNM in Unity chat, and it pops
-- 10 minutes later. VenGo watches chat for that, alerts you, marks the
-- venture 100% and points GO at it.
------------------------------------------------------------------------
local POP_DELAY = 600;                 -- seconds from the announcement to the pop
local ALERT = nil;                     -- { v, at, pop_at, line, warned }
local LAST_ANNOUNCE = nil;             -- the last Populox line seen (shown in Settings)

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

local function raiseAlert(v, line, source)
    local now = os.time();
    v.progress = 100;
    ALERT = { v = v, at = now, pop_at = now + POP_DELAY, line = line, warned = false, source = source or 'chat' };
    msg(('VNM ALERT: %s in %s (%s) pops in about 10 minutes. Press GO in VenGo.'):fmt(v.nm, v.zone_name, v.grid or '?'));
    playAlertSound();
end

local function logAnnouncement(line)
    pcall(function ()
        local f = io.open(addon.path .. 'announcements.txt', 'a');
        if f then f:write(os.date('%Y-%m-%d %H:%M:%S') .. '  ' .. line .. '\n'); f:close(); end
    end);
end

-- Called for every incoming chat line
local function checkAnnouncement(mode, raw)
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
            ALERT.pop_at = os.time() + POP_DELAY;
            ALERT.warned = false;
        end
        return;
    end
    raiseAlert(v, line, 'chat');
end

-- One minute before the pop: a second sound. 15 minutes after: the alert goes away.
local function tickAlert()
    if ALERT == nil then return; end
    local left = ALERT.pop_at - os.time();
    if left <= 60 and not ALERT.warned then
        ALERT.warned = true;
        msg(('%s pops in about a minute (%s).'):fmt(ALERT.v.nm, ALERT.v.zone_name));
        playAlertSound();
    end
    if left < -900 then ALERT = nil; end
end

------------------------------------------------------------------------
-- Live ventures: the server sends the whole venture board in packet 0x1A3
-- (two pools x six tiers, each with an ACE zone, a CW zone and the progress,
-- plus the HVNM's zone and progress). VenGo reads it the moment it arrives,
-- so the list and the percentages stay current with no editing.
-- Packet layout as documented by the "ventures" addon (Commandobill).
------------------------------------------------------------------------
local TIER_LEVELS = { '10-19', '20-29', '30-39', '40-49', '50-59', '60-69' };
local LIVE = nil;             -- { at = os.time(), exp = { {pool, tier, ace, cw, progress}, ... }, hvnm = { zone, progress } }
local LIVEV = {};             -- key -> the venture table shown (kept, so GO and alerts keep pointing at it)
local VNMDB = nil;            -- drops, positions and notes per zone: { [zone name] = { {name, level_range, position, ...} } }
local VNMDB_FROM = 'none';

local function liveFile() return addon.path .. 'live_ventures.lua'; end

local function u16(d, off) return (d:byte(off + 1) or 0) + (d:byte(off + 2) or 0) * 256; end
local function u8(d, off) return d:byte(off + 1) or 0; end

-- "Crawlers' Nest", "Crawlers Nest", "East Ronfaure [S]", "East Ronfaure S" all match
local function zoneKey(name)
    local r = tostring(name or ''):lower():gsub('%[s%]', 's'):gsub('[^%w]', '');
    return r;
end

local function zoneNameOf(zid)
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

local function loadTable(path)
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

local function loadVnmDb(tryDownload)
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

local function splitList(s)
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
local function fillFromDb(v, levels)
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

local function fileEntry(key)
    if key == 'hvnm' then return vfile.hvnm; end
    for _, v in ipairs(vfile.exp or {}) do if v.key == key then return v; end end
    return nil;
end

local heads = {};   -- key -> highest heads-up already given (90 / 100)

local function crossed(v, before)
    local now = v.progress or 0;
    if before == nil then before = heads[v.key] and 100 or 0; end
    if now >= 100 and before < 100 then
        heads[v.key] = 100;
        if not (ALERT and ALERT.v == v and os.time() - ALERT.at < 900) then raiseAlert(v, '(venture board)', 'board'); end
    elseif now >= 90 and before < 90 and now < 100 and config.alert90 then
        msg(('%s (%s) is at %d%%.'):fmt(v.nm, v.zone_name, now));
    end
end

local function applyLive(alerts)
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
        fillFromDb(v, TIER_LEVELS[r.tier]);
        v.progress = r.progress;
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
        fillFromDb(h, 'HVNM');
        local same = f and f.nm == h.nm;
        h.level, h.hp, h.next_up = same and f.level or nil, same and f.hp or nil, same and f.next_up or nil;
        h.loot = splitList(h.drops ~= '' and h.drops or (same and table.concat(f.loot or {}, ',') or ''));
        h.progress = LIVE.hvnm.progress;
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

local function loadLive()
    local t = loadTable(liveFile());
    if t and type(t.exp) == 'table' then LIVE = t; end
end

local function onVenturePacket(data)
    if data == nil or #data < 0x54 then return; end
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
end

local function liveAge()
    if LIVE == nil then return nil; end
    local s = os.time() - (LIVE.at or os.time());
    if s < 60 then return 'just now'; end
    if s < 3600 then return ('%d min ago'):fmt(math.floor(s / 60)); end
    return ('%dh %02dm ago'):fmt(math.floor(s / 3600), math.floor(s % 3600 / 60));
end

local function pickCurrent()
    if ALERT then return ALERT.v; end
    local best = nil;
    for _, e in ipairs(ventures) do
        if e.key ~= 'hvnm' and (best == nil or (e.progress or 0) > (best.progress or 0)) then best = e; end
    end
    return best;
end

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
local SYSTEMS    = { 'hp', 'sg', 'uc' };
local SYS_NAME   = { hp = 'Home Point', sg = 'Survival Guide', uc = 'Unity warp' };
local SYS_FILES  = { hp = { 'homepoint.xml', 'uwHomePoints.xml' }, sg = { 'survivalguide.xml', 'uwSurvivalGuides.xml' },
                     uc = { 'unitywarp.xml', 'uwUnity.xml' } };

-- Zones where the closest warp is in another zone. Listed per warp kind, in order
-- of preference, by Uberwarp's alias. Unity warps aren't changed.
local WARP_OVERRIDES = {
    [72] = { name = 'Aht Urhgan Whitegate',                           -- Alzadaal Undersea Ruins
             hp = { 'Aht Urhgan Whitegate2' },                        --   Whitegate Home Point #2
             sg = { 'Aht Urhgan Whitegate' } },                       --   Whitegate Survival Guide
};

local WARPS = nil;            -- { hp = { dest = {...}, npc = {...} }, sg = ..., uc = ... }
local WARPS_FROM = nil;       -- the folder they were read from

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

local function loadWarps()
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
local function nearSystem()
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
local function warpOptions(v)
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
        if ov then break; end
        for _, d in ipairs(WARPS[sys].dest) do
            if d.zone == v.zone then
                out[sys][#out[sys] + 1] = { sys = sys, alias = d.alias,
                    dist = (tx and d.x) and dist2d(tx, ty, d.x, d.y) or nil };
            end
        end
        table.sort(out[sys], function (a, b) return (a.dist or 1e9) < (b.dist or 1e9); end);
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
local LASTWARP = nil;         -- { v, sys, list, i, at }

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

local ARMED = nil;            -- { v, until } : GO pressed away from a warp NPC

-- GO: warp toward a venture (or wait for a warp NPC)
local function warpTo(v)
    if v == nil then return; end
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
local function warpNext()
    local L = LASTWARP;
    if L == nil then return; end
    if not doWarp(L.v, L.sys, L.list, L.i + 1) then
        msg(('No other %s goes to %s.'):fmt(SYS_NAME[L.sys], L.v.zone_name));
        LASTWARP = nil;
    end
end

-- Waiting after GO: warp as soon as you're at a warp NPC that goes there
local armCheckAt = 0;
local function tickArm(now)
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
    rall   = ImDrawFlags_RoundCornersAll or ImDrawCornerFlags_All or 15,
};
local NEON  = { 0.86, 0.24, 0.86 };
local NEON2 = { 1.00, 0.42, 0.72 };

local SW, ROW_W, MARGIN = 220, 760, 8;
local FULL_ROW = 760;                                   -- width the venture rows need
local WIN_W = SW + 30 + MARGIN + FULL_ROW + 50;         -- starting size; the window can be resized
local WIN_H = 700;
local MIN_W, MIN_H = 640, 460;

local TABS = { 'VENTURES', 'HELM', 'FISHING', 'DYNAMIS', 'SETTINGS', 'SPECIAL THANKS' };
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
    fonts.panel = add(addon.path .. 'fonts\\texgyreadventor-regular.otf', 18)
        or add(win .. 'GOTHIC.TTF', 18) or add(win .. 'segoeui.ttf', 17);
    fonts.title = add(win .. 'bahnschrift.ttf', 24);
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
    local tw = spaced(dl, x0, y0, text:upper(), u32({ 0.93, 0.90, 1.00, 1 }), 2.5);
    dl:AddLine({ x0 + tw + 18, y0 + lh / 2 }, { x0 + ROW_W, y0 + lh / 2 }, u32({ 1, 1, 1, 0.08 }), 1);
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
    local rr = math.min(h * 0.45, 14);
    local fill = { 0.10, 0.09, 0.13, 1 };
    if hov or act then fill = act and { 0.18, 0.17, 0.23, 1 } or { 0.15, 0.14, 0.19, 1 }; end
    dl:AddRectFilled({ x, y }, { x + w, y + h }, u32(fill), rr);
    local ec = u32(quiet and { 1, 1, 1, hov and 0.25 or 0.14 } or { NEON2[1], NEON2[2], NEON2[3], hov and 1 or 0.8 });
    dl:AddRect({ x, y }, { x + w, y + h }, ec, rr, C.rall, quiet and 1 or 1.6);
    if small then imgui.SetWindowFontScale(0.82); end
    spaced(dl, x + (w - lw) / 2, y + (h - lh) / 2, name, u32({ 0.93, 0.91, 0.98, 1 }), sp);
    if small then imgui.SetWindowFontScale(1); end
    return clicked;
end

-- A thin pink-to-violet bar on a dark track, drawn where the cursor is
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
local function pills(list)
    local dl = imgui.GetWindowDrawList();
    for i, t in ipairs(list) do
        local tw, th = imgui.CalcTextSize(t);
        local w, h = tw + 22, th + 8;
        local x, y = imgui.GetCursorScreenPos();
        imgui.Dummy({ w, h });
        dl:AddRectFilled({ x, y }, { x + w, y + h }, u32({ 0.13, 0.11, 0.18, 1 }), h / 2);
        dl:AddRect({ x, y }, { x + w, y + h }, u32({ NEON2[1], NEON2[2], NEON2[3], 0.35 }), h / 2, C.rall, 1);
        dl:AddText({ x + 11, y + 4 }, u32({ 0.93, 0.90, 1, 1 }), t);
        if i < #list then imgui.SameLine(0, 6); end
    end
end

local function fmtLeft(sec)
    if sec <= 0 then return 'up now'; end
    return ('%d:%02d'):fmt(math.floor(sec / 60), sec % 60);
end

-- Ventures reset at JST midnight = 15:00 UTC
local function resetCountdown()
    local left = (15 * 3600 - os.time() % 86400) % 86400;
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
    elseif button('GO##' .. v.key, { 80, 0 }, false, true) then
        warpTo(v);
    end
end

------------------------------------------------------------------------
-- Panel frame and sidebar
------------------------------------------------------------------------
local function frame(dl, x, y, w, h)
    local r = 30;
    x, y, w, h = x + 5, y + 5, w - 10, h - 10;
    local clear = config.transparent;
    dl:AddRectFilled({ x, y }, { x + w, y + h }, u32({ 0.035, 0.032, 0.050, clear and 0.40 or 0.95 }), r);
    for k = 3, 1, -1 do
        dl:AddRect({ x, y }, { x + w, y + h }, u32({ NEON[1], NEON[2], NEON[3], 0.07 * (4 - k) * (clear and 0.5 or 1) }), r, C.rall, 2 + k * 2.2);
    end
    dl:AddRect({ x, y }, { x + w, y + h }, u32({ NEON2[1], NEON2[2], NEON2[3], clear and 0.55 or 0.85 }), r, C.rall, 1.6);
    -- the sidebar's slanted edge: faint all the way down, bright near the top
    local tx, bx = x + SW + 30, x + SW - 60;
    dl:AddLine({ tx, y + 24 }, { bx, y + h - 24 }, u32({ 1, 1, 1, 0.08 }), 1);
    local k = 0.28;
    local mx2, my2 = tx + (bx - tx) * k, y + 24 + (h - 48) * k;
    dl:AddLine({ tx, y + 24 }, { mx2, my2 }, u32({ NEON[1], NEON[2], NEON[3], 0.25 }), 6);
    dl:AddLine({ tx, y + 24 }, { mx2, my2 }, u32({ NEON2[1], NEON2[2], NEON2[3], 0.9 }), 1.6);
end

-- VEN GO, with GO shimmering pink to violet
local function title(dl, x0, y0)
    local full = 'VEN GO';
    local pushed = pushFont(fonts.title, 24);
    if not pushed then imgui.SetWindowFontScale(1.4); end
    local tw, lh = imgui.CalcTextSize(full);
    local t = os.clock();
    for i = 1, #full do
        local ch = full:sub(i, i);
        if ch ~= ' ' then
            local cx = x0 + imgui.CalcTextSize(full:sub(1, i - 1));
            local col = C.text;
            if i > 4 then
                local u = 0.5 + 0.5 * math.sin(t * 1.2 - i * 0.45);
                col = { C.hp[1] + (C.mp2[1] - C.hp[1]) * u, C.hp[2] + (C.mp2[2] - C.hp[2]) * u, C.hp[3] + (C.mp2[3] - C.hp[3]) * u, 1 };
            end
            dl:AddText({ cx, y0 }, u32(col), ch);
        end
    end
    if pushed then imgui.PopFont(); else imgui.SetWindowFontScale(1); end
    return tw, lh;
end

local function sidebar(dl, x0, y0, sw)
    -- measure the title, then centre it
    local pushed = pushFont(fonts.title, 24);
    if not pushed then imgui.SetWindowFontScale(1.4); end
    local tw, th = imgui.CalcTextSize('VEN GO');
    if pushed then imgui.PopFont(); else imgui.SetWindowFontScale(1); end
    title(dl, x0 + (sw - tw) / 2, y0 + 2);
    local ty = y0 + 2 + th + 2;
    local vs = 'v' .. addon.version;
    local vw, vh = imgui.CalcTextSize(vs);
    dl:AddText({ x0 + (sw - vw) / 2, ty }, u32(C.muted), vs);
    local y = ty + vh + 34;

    local ih = 40;
    local mx, my = imgui.GetMousePos();
    for k, n in ipairs(TABS) do
        local on = (ui.tab == k);
        local over = mx >= x0 and mx < x0 + sw and my >= y and my < y + ih;
        if on then
            pcall(function ()
                dl:AddRectFilledMultiColor({ x0, y }, { x0 + sw, y + ih }, u32({ NEON[1], NEON[2], NEON[3], 0.38 }), u32({ NEON[1], NEON[2], NEON[3], 0 }),
                    u32({ NEON[1], NEON[2], NEON[3], 0 }), u32({ NEON[1], NEON[2], NEON[3], 0.38 }));
                dl:AddRectFilledMultiColor({ x0, y + ih - 2 }, { x0 + sw, y + ih }, u32({ NEON2[1], NEON2[2], NEON2[3], 1 }), u32({ NEON2[1], NEON2[2], NEON2[3], 0 }),
                    u32({ NEON2[1], NEON2[2], NEON2[3], 0 }), u32({ NEON2[1], NEON2[2], NEON2[3], 1 }));
            end);
            dl:AddRectFilled({ x0, y }, { x0 + 3, y + ih }, u32({ 0.92, 0.80, 1, 1 }));
        elseif over then
            dl:AddRectFilled({ x0, y }, { x0 + sw, y + ih }, u32({ 1, 1, 1, 0.04 }));
        end
        local _, nh = imgui.CalcTextSize(n);
        dl:AddText({ x0 + 20, y + (ih - nh) / 2 }, u32(on and { 0.97, 0.94, 1, 1 } or (over and { 1, 1, 1, 1 } or C.text)), n);
        imgui.SetCursorScreenPos({ x0, y });
        if imgui.InvisibleButton('##vengo_side' .. k, { sw, ih }) then ui.tab = k; end
        y = y + ih + 8;
    end

    local tabsEnd = y;

    local sy = y0 + WIN_H - 34 - 26 - 60;

    -- what VenGo is doing, bottom left
    if sy > tabsEnd + 8 then
        dl:AddText({ x0 + 20, sy }, u32(C.muted), 'STATUS');
        local st, sv = statusText();
        dl:AddText({ x0 + 20, sy + 24 }, u32(sv and C.active or C.text), st);
        if sv then dl:AddText({ x0 + 20, sy + 48 }, u32(C.acc), sv.zone_name or ''); end
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
    if iconButton(dl, '##vengo_x', xClose, by, bs, { 1, 0.36, 0.62, 0.30 },
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

local function pctText(p)
    p = tonumber(p) or 0;
    if p == math.floor(p) then return ('%d%%'):fmt(p); end
    return ('%.1f%%'):fmt(p);
end

local function measureCols(list, showPool)
    local w = { go = 80, tier = 0, zone = 0, nm = 0, grid = 0, bar = 78, pct = imgui.CalcTextSize('100%') };
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
    imgui.TextColored(C.muted, v.grid or '');
    imgui.SameLine(x0 + at.bar);
    bar(78, (v.progress or 0) / 100);
    imgui.SameLine(x0 + at.pct);
    local full = (v.progress or 0) >= 100;
    imgui.TextColored(full and { NEON2[1], NEON2[2], NEON2[3], 1 } or C.text, pctText(v.progress));
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
            dl:AddRectFilled({ x, y }, { x + w, y + h }, u32({ NEON[1] * 0.42, NEON[2] * 0.42, NEON[3] * 0.42, 1 }), h / 2);
            dl:AddRect({ x, y }, { x + w, y + h }, u32({ NEON2[1], NEON2[2], NEON2[3], 0.9 }), h / 2, C.rall, 1.4);
        else
            dl:AddRectFilled({ x, y }, { x + w, y + h }, u32(hov and { 0.15, 0.14, 0.19, 1 } or { 0.10, 0.09, 0.13, 1 }), h / 2);
            dl:AddRect({ x, y }, { x + w, y + h }, u32({ 1, 1, 1, hov and 0.25 or 0.12 }), h / 2, C.rall, 1);
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
    elseif pick then
        imgui.TextColored(C.muted, 'GO warps you toward');
        imgui.TextColored(C.acc, pick.nm or '?');
        imgui.TextColored(C.text, ('%s  (%s)  %s'):fmt(pick.zone_name or '?', pick.grid or '?', pctText(pick.progress)));
    end
    imgui.EndGroup();

    if ALERT then
        imgui.TextColored({ NEON2[1], NEON2[2], NEON2[3], 1 }, ('VNM INCOMING:  %s, %s (%s)  -  pops in %s'):fmt(
            ALERT.v.nm, ALERT.v.zone_name, ALERT.v.grid or '?', fmtLeft(ALERT.pop_at - os.time())));
    end
    imgui.PushTextWrapPos(imgui.GetCursorPosX() + ROW_W);
    imgui.TextColored(C.active, ui.last or '');
    imgui.PopTextWrapPos();
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
        bar(math.max(200, ROW_W - 80), (h.progress or 0) / 100, 8);
        imgui.SameLine();
        imgui.TextColored((h.progress or 0) >= 100 and { NEON2[1], NEON2[2], NEON2[3], 1 } or C.text, pctText(h.progress));
        if h.loot and #h.loot > 0 then pills(h.loot); end
    end

    section('EXP Ventures');
    local p = pillChoice('##vengo_pool', { { 'all', 'ALL POOLS' }, { 'A', 'POOL A' }, { 'B', 'POOL B' } }, config.pool);
    if p then config.pool = p; saveSettings(); end
    imgui.SameLine(0, 24);
    local so = pillChoice('##vengo_sort', { { 'pct', 'SORT  %' }, { 'tier', 'SORT  TIER' } }, config.sort);
    if so then config.sort = so; saveSettings(); end
    imgui.SameLine(0, 24);
    local md = pillChoice('##vengo_mode', { { 'ACE', 'ACE' }, { 'CW', 'CW' } }, config.mode);
    if md then config.mode = md; saveSettings(); applyLive(false); end

    if LIVE then
        imgui.TextColored(C.muted, 'Live from the venture board, updated ' .. (liveAge() or '?'));
    else
        imgui.TextColored(C.muted, 'From ventures.lua. Goes live the next time the server sends the venture board.');
    end
    imgui.Spacing();
    local list = sortedList();
    local showPool = (config.pool == 'all');
    local at = measureCols(list, showPool);
    for _, v in ipairs(list) do ventureRow(v, z, at, showPool); end
end

local function infoRows(rows, offsets)
    for _, r in ipairs(rows) do
        local x0 = imgui.GetCursorPosX();
        for c, cell in ipairs(r) do
            if c > 1 then imgui.SameLine(x0 + offsets[c]); end
            imgui.TextColored((c == 1) and C.acc or C.text, cell);
        end
    end
end

local function tabHelm()
    section('HELM Ventures');
    local rows = {};
    for _, h in ipairs(vdata.helm or {}) do rows[#rows + 1] = { h.kind, h.zones }; end
    if #rows == 0 then hint('None listed in ventures.lua.'); end
    infoRows(rows, { 0, 160 });
end

local function tabFishing()
    section('Fishing Ventures');
    local rows = {};
    for _, f in ipairs(vdata.fishing or {}) do
        rows[#rows + 1] = { ('Tier %d'):fmt(f.tier), f.levels or '', f.fish, 'x' .. tostring(f.count) };
    end
    if #rows == 0 then hint('None listed in ventures.lua.'); end
    infoRows(rows, { 0, 110, 230, 520 });
end

local function tabDynamis()
    section('Dynamis Ventures');
    local rows = {};
    for _, d in ipairs(vdata.dynamis or {}) do rows[#rows + 1] = { d.kind, d.zone }; end
    if #rows == 0 then hint('None listed in ventures.lua.'); end
    infoRows(rows, { 0, 160 });
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

local function tabSettings()
    section('Window');
    if rowSwitch('##vengo_clear_sw', 'See-through window', config.transparent == true,
            'Lets the game show through the panel') then
        config.transparent = not config.transparent;
        saveSettings();
    end
    hint('Drag the bottom-right corner to resize. The  -  button at the top right shrinks VenGo to a small tag.');

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

    section('Ventures data');
    if rowSwitch('##vengo_cw', 'Crystal Warrior zones (CW)', config.mode == 'CW',
            'Off: ACE zones. The board has a set of zones for each.') then
        config.mode = (config.mode == 'CW') and 'ACE' or 'CW';
        saveSettings();
        applyLive(false);
    end
    if LIVE then
        imgui.TextColored(C.text, 'Venture board: live, updated ' .. (liveAge() or '?'));
    else
        imgui.TextColored(C.text, 'Venture board: not received yet');
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
-- The alert banner: top middle of the screen, over everything, until you
-- dismiss it or press GO. Shows even when the VenGo window is closed or small.
local function drawAlert()
    if ALERT == nil or ALERT.dismissed then return; end
    local v = ALERT.v;
    local nc, nv = pushTheme();
    local pulse = 0.55 + 0.45 * math.sin(os.clock() * 4);
    imgui.PushStyleColor(ImGuiCol_WindowBg, { 0.05, 0.04, 0.07, config.transparent and 0.70 or 0.95 });
    imgui.PushStyleColor(ImGuiCol_Border, { NEON2[1], NEON2[2], NEON2[3], 0.45 + 0.55 * pulse });
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 22, 16 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 2);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 18);
    nc, nv = nc + 2, nv + 3;
    local ds = imgui.GetIO().DisplaySize;
    imgui.SetNextWindowPos({ ((ds and ds.x) or 1920) / 2, 70 }, ImGuiCond_FirstUseEver, { 0.5, 0 });
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoFocusOnAppearing);
    local pushed = pushFont(fonts.panel, 18);
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
        local left = ALERT.pop_at - os.time();
        imgui.TextColored(left <= 60 and { C.hp[1], C.hp[2], C.hp[3], 1 } or C.active, 'Pops in ' .. fmtLeft(left));
        imgui.Spacing();
        if isActive(v) then
            if button('CANCEL##vengo_alert_go', { 160, 38 }, true) then ARMED = nil; msg('Cancelled.'); end
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

local function drawMini()
    local nc, nv = pushTheme();
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse,
        ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoMove);
    if MINI.x then imgui.SetNextWindowPos({ MINI.x, MINI.y }, ImGuiCond_Always);
    else imgui.SetNextWindowPos({ 240, 160 }, ImGuiCond_FirstUseEver); end
    local pushed = pushFont(fonts.title, 24);
    if imgui.Begin('VenGo##vengo_mini', { true }, flags) then
        if not pushed then imgui.SetWindowFontScale(1.4); end
        local dl = imgui.GetWindowDrawList();
        local wx, wy = imgui.GetWindowPos();
        MINI.x, MINI.y = wx, wy;
        local word = 'VenGo';
        local tw, th = imgui.CalcTextSize(word);
        local running = ARMED ~= nil;
        local padX, padY = 22, 10;
        local w, h = tw + padX * 2 + ((running or ALERT) and 16 or 0), th + padY * 2;
        local x, y = wx + 10, wy + 10;                  -- (room round it for the glow)

        -- the tag: dark, rounded, violet glow, pink edge (same as the panel)
        local clear = config.transparent;
        dl:AddRectFilled({ x, y }, { x + w, y + h }, u32({ 0.035, 0.032, 0.050, clear and 0.45 or 0.95 }), h / 2);
        for k = 3, 1, -1 do
            dl:AddRect({ x, y }, { x + w, y + h }, u32({ NEON[1], NEON[2], NEON[3], 0.07 * (4 - k) }), h / 2, C.rall, 2 + k * 2.2);
        end
        dl:AddRect({ x, y }, { x + w, y + h }, u32({ NEON2[1], NEON2[2], NEON2[3], 0.85 }), h / 2, C.rall, 1.6);

        -- the word, with "Go" shimmering pink to violet
        local t = os.clock();
        for i = 1, #word do
            local ch = word:sub(i, i);
            local cx = x + padX + imgui.CalcTextSize(word:sub(1, i - 1));
            local col = C.text;
            if i > 3 then
                local u = 0.5 + 0.5 * math.sin(t * 1.2 - i * 0.45);
                col = { C.hp[1] + (C.mp2[1] - C.hp[1]) * u, C.hp[2] + (C.mp2[2] - C.hp[2]) * u, C.hp[3] + (C.mp2[3] - C.hp[3]) * u, 1 };
            end
            dl:AddText({ cx, y + padY }, u32(col), ch);
        end
        if ALERT and not running then
            local a = 0.55 + 0.45 * math.sin(t * 6);
            dl:AddCircleFilled({ x + padX + tw + 12, y + h / 2 }, 5, u32({ NEON2[1], NEON2[2], NEON2[3], a }), 16);
        end
        if running then
            local a = 0.55 + 0.45 * math.sin(t * 4);
            dl:AddCircleFilled({ x + padX + tw + 12, y + h / 2 }, 4, u32({ C.active[1], C.active[2], C.active[3], a }), 16);
        end

        imgui.SetCursorScreenPos({ x, y });
        imgui.InvisibleButton('##vengo_mini_btn', { w, h });
        local hovered, active, released = imgui.IsItemHovered(), imgui.IsItemActive(), imgui.IsItemDeactivated();
        imgui.SetCursorScreenPos({ x + w, y + h });
        imgui.Dummy({ 10, 10 });
        if hovered then
            local tipText = running and ('VenGo: waiting for a warp NPC for ' .. (ARMED.v.zone_name or '?')) or 'VenGo';
            if ALERT then tipText = tipText .. ('\nVNM: %s, pops in %s'):fmt(ALERT.v.nm, fmtLeft(ALERT.pop_at - os.time())); end
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
        if not pushed then imgui.SetWindowFontScale(1); end
    end
    imgui.End();
    if pushed then imgui.PopFont(); end
    imgui.PopStyleVar(nv);
    imgui.PopStyleColor(nc);
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
    local pushed = pushFont(fonts.panel, 18);
    if imgui.Begin('VenGo##vengo_main', { true }, flags) then
        local dl = imgui.GetWindowDrawList();
        local wx, wy = imgui.GetWindowPos();
        local ww, wh = imgui.GetWindowSize();
        WIN_W, WIN_H = math.max(MIN_W, ww or WIN_W), math.max(MIN_H, wh or WIN_H);
        ROW_W = math.max(360, WIN_W - SW - 30 - MARGIN - 50);
        local z = zone();
        frame(dl, wx, wy, WIN_W, WIN_H);
        sidebar(dl, wx + 26, wy + 34, SW - 40);
        topButtons(dl, wx, wy, WIN_W);

        local cx, ctop = wx + SW + 30, wy + 54;
        local ch = WIN_H - 54 - 84;
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
            elseif ui.tab == 5 then tabSettings();
            elseif ui.tab == 6 then tabThanks();
            end
        end);
        if not ok then imgui.TextColored({ C.hp[1], C.hp[2], C.hp[3], 1 }, 'Window error: ' .. tostring(err)); end
        imgui.Spacing();
        imgui.Unindent(MARGIN);
        imgui.EndChild();

        -- the bottom: a faint line, the reset timer, CLOSE
        local by = wy + WIN_H - 70;
        dl:AddLine({ cx + MARGIN - 20, by - 10 }, { cx + MARGIN + ROW_W, by - 10 }, u32({ 1, 1, 1, 0.08 }), 1);
        dl:AddText({ cx + MARGIN, by + 10 }, u32(C.muted), 'Next reset in ' .. resetCountdown());
        local cw = math.min(260, ROW_W - 200);
        imgui.SetCursorScreenPos({ cx + MARGIN + ROW_W - cw, by });
        if button('CLOSE##vengo_close', { cw, 40 }, true) then ui.open[1] = false; end
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
    drawUI();
    drawAlert();
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
    elseif cmd == 'ventures' then
        for _, v in ipairs(ventures) do msg(describe(v)); end
    elseif cmd == 'reload' then
        loadVentures();
        applyLive(false);
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
            config.mode = m; saveSettings(); applyLive(false);
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
end);

ashita.events.register('load', 'vengo_load', function ()
    loadFonts();
    loadSettings();
    loadVentures();
    loadVnmDb(true);
    loadLive();
    applyLive(false);
    if not loadWarps() then
        msg('Uberwarp\'s warp list wasn\'t found, so GO can\'t warp yet. See Settings > Warping.');
    end
    if VNMDB == nil then
        msg('No VNM drop data yet (download failed). See Settings > Ventures data.');
    end
end);

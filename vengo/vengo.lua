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
  The DAILIES tab is ported from Goldilox by Dewin (MIT, LICENSE-goldilox.txt).
]]

addon.name    = 'vengo';
addon.author  = 'Chadbrowick';
addon.version = '4.80';
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
    strip = false,             -- shrunk to the venture bar (just the top venture)
    alerts = true,             -- watch chat for VNM announcements
    alert_chat = true,         -- VNM alerts and heads-ups as chat lines
    alert_popup = true,        -- the VNM INCOMING pop-up window
    alert_voice = 'off',       -- a recorded voice that says the VNM: off | scot_f | gb_m | ja_f
    lang = 'en',               -- the window's language: en | jp (the switch at the top)
    alert_sound = true,        -- play a sound with the alert
    alert90 = true,            -- a chat heads-up when a venture reaches 90%
    mode = 'ACE',              -- ACE or CW venture zones
    pool = 'all',              -- all | A | B
    sort = 'pct',              -- pct (100% on top) | tier
    website = true,            -- update from catseyexi.com/events after each reset
    login_refresh = true,      -- type !ventures once when you log in
    logo_anim = true,          -- shine and petals on the logo
    logo_clear = true,         -- nothing behind the shrunk logo (off: a dark cloud)
    logo_style = 'bolt',       -- what VenGo shrinks to: bolt (the lightning logo) | orb (the round orb)
    logo_size = 1,             -- the shrunk lightning logo's size (drag its corner): 0.4 to 3
    trail = true,              -- the glowing path on the ground to the VNM
    trail_glow = true,         -- its glow
    trail_full = true,         -- show it on its own only when the zone's VNM is at 100% (GO in the zone still shows it)
    trail_color = 'pink',      -- the chevrons' colour
    trail_style = 'lines',     -- the GPS style: lines (arrows) | runes | light | aether
    theme = 'pink',            -- the window's accent colours (Settings > Colours)
    lite = false,              -- Lightweight mode: a quick preset for the sliders below
    star_zones = '',           -- starred venture zones
    star_items = '',           -- starred VNM armour pieces (item ids)
    dl_pins = '',              -- pinned dailies, shown in a small tracker while VenGo is minimized
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
    style = 'classic',         -- classic | phantom (red, black and white, slanted) | neon (ChadcoreMenu's Neon)
    ph_accent = 'Red', ph_slab = 'Black', ph_edge = 'White',   -- Phantom's colours
    bg_img = '',               -- your own picture behind the window (a file in images\)
    bg_img_alpha = 0.45,       -- how much of it shows
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
    print(chat.header(addon.name):append(chat.message(TRF.LANG and TRF.LANG.chat(text) or text)));
end
-- A VNM notification: in chat unless chat notifications are off (it still shows in VenGo's status line)
function TRF.note(text)
    if config.alert_chat == false then ui.last = text; return; end
    msg(text);
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
    for _, k in ipairs({ 'transparent', 'minimized', 'strip', 'alerts', 'alert_chat', 'alert_popup', 'alert_voice', 'lang', 'alert_sound', 'alert90', 'mode', 'pool', 'sort', 'website', 'login_refresh', 'logo_anim', 'logo_style', 'logo_size', 'logo_clear', 'trail', 'trail_glow', 'trail_full', 'trail_color', 'trail_style', 'trail_size', 'theme', 'bg', 'style', 'ph_accent', 'ph_slab', 'ph_edge', 'bg_img', 'bg_img_alpha', 'lite',
                           'seal_check', 'seal_scan', 'cam_every', 'trail_range', 'trail_scale', 'trail_spacing', 'trail_speed', 'glow_q',
                           'star_zones', 'star_items', 'dl_pins', 'star_chat', 'star_sound', 'check_updates' }) do
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
    local crest = (v.crest and v.crest ~= '') and v.crest or TRF.crestOf(v.zone_name);
    if crest then d = (d ~= '' and (d .. ', ') or '') .. crest .. ' Crest'; end   -- (the crest too)
    TRF.note(('VNM ALERT: %s in %s (%s) pops in about %s.%s Press GO in VenGo.'):fmt(v.nm, v.zone_name, v.grid or '?',
        fmtLeft(popAt - now), (d ~= '') and (' Drops: ' .. d .. '.') or ''));
    local ok_, spoke = pcall(TRF.VO.say, 'incoming', v);          -- (the voice, else the chime)
    if not (ok_ and spoke) then playAlertSound(); end
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
    if (av.progress or 0) >= 100 then ALERT.saw = true; end
    -- (an alert from Populox's own callout only closes on a drop once the board has shown 100% during it)
    if (av.progress or 0) < 100 and (av.prog_at or 0) > ALERT.at and (ALERT.source ~= 'chat' or ALERT.saw) then
        TRF.note(('%s is no longer at 100%% (killed or reset). Alert closed.'):fmt(av.nm or 'The VNM'));
        TRF.flap = TRF.flap or {};
        TRF.flap[av.key or '?'] = os.time();                      -- (no new board alert for it for 10 minutes)
        ALERT = nil;
        return;
    end
    local pl = popLeft(ALERT.v);
    if pl then ALERT.pop_at = os.time() + pl; end
    local left = ALERT.pop_at - os.time();
    if left <= 60 and not ALERT.warned then
        ALERT.warned = true;
        TRF.note(('%s pops in about a minute (%s).'):fmt(ALERT.v.nm, ALERT.v.zone_name));
        local ok_, spoke = pcall(TRF.VO.say, 'minute', ALERT.v);
        if not (ok_ and spoke) then playAlertSound(); end
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
-- Which crest a venture zone's VNM drops (CatsEyeXI's list, pools A and B), and each crest's colour (its armour set's)
TRF.CRESTC = { Ocean = { 0.40, 0.65, 1.00, 1 }, Forest = { 0.35, 0.85, 0.35, 1 }, Mountain = { 0.95, 0.62, 0.28, 1 }, Tundra = { 0.75, 0.58, 0.92, 1 }, Desert = { 0.92, 0.82, 0.38, 1 } };
TRF.CRESTZ = {};
for crest, zones in pairs({
    Ocean = "valkurm dunes|pashhow marshlands|rolanberry fields|alzadaal undersea ruins|sea serpent grotto|vunkerl inlet [s]|toraimarai canal|rolanberry fields [s]|bibiki bay",
    Forest = "east ronfaure [s]|west sarutabaruta [s]|jugner forest|yuhtunga jungle|yhoator jungle|the sanctuary of zi'tah|fort karugo-narugo [s]|garlaige citadel [s]|ro'maeve",
    Mountain = "buburimu peninsula|north gustaberg [s]|meriphataud mountains|korroloka tunnel|grauberg [s]|garlaige citadel|kuftal tunnel|aydeewa subterrane|the boyahda tree",
    Tundra = "maze of shakhrami|wajaom woodlands|qufim island|labyrinth of onzozo|misareaux coast|bostaunieux oubliette|uleguerand range|caedarva mire",
    Desert = "batallia downs|bhaflau thickets|sauromugue champaign|eastern altepa desert|crawler's nest|western altepa desert|gustav tunnel|cape teriggan|mount zhayolm",
}) do for zn in zones:gmatch('[^|]+') do TRF.CRESTZ[zn] = crest; end end
-- (a zone's crest: the list's, whatever map of the zone or apostrophe the name carries)
function TRF.crestOf(zoneName)
    local z = tostring(zoneName or ''):lower():gsub('%s+map%s*%d+$', ''):gsub('^%s+', ''):gsub('%s+$', '');
    return TRF.CRESTZ[z] or TRF.CRESTZ[(z:gsub('crawlers', 'crawler\'s'))];
end
fillFromDb = function(v, levels)
    local info = vnmInfo(v.zone_name, levels);
    v.nm = (info and info.name and info.name ~= '') and info.name or (v.nm_file or '?');
    v.grid = (info and info.position and info.position ~= '') and info.position or v.grid_file;
    v.notes = info and info.notes or '';
    v.drops = info and info.equipment or '';
    v.element = info and info.element or '';
    v.crest = TRF.crestOf(v.zone_name) or (info and info.crest) or '';
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
        if not (ALERT and ALERT.v == v and os.time() - ALERT.at < 900)
            and not (TRF.flap and TRF.flap[v.key] and os.time() - TRF.flap[v.key] < 600) then raiseAlert(v, '(venture board)', 'board'); end
    elseif now >= 90 and before < 90 and now < 100 and config.alert90 then
        TRF.note(('%s (%s) is at %d%%.'):fmt(v.nm, v.zone_name, now));
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
        v.prog_at, v.prog_zone, v.prog_game = LIVE.at or os.time(), zid, LIVE.at or os.time();
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
        h.prog_at, h.prog_zone, h.prog_game = LIVE.at or os.time(), h.zone, LIVE.at or os.time();
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
                if ((v.prog_at or 0) <= (SITE.at or 0) and (SITE.at or 0) - (v.prog_game or 0) > 900) or v.zone ~= v.prog_zone then   -- (the game's board is the live one: the website's % only when the game hasn't said for 15 minutes)
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
        if ((h.prog_at or 0) <= (SITE.at or 0) and (SITE.at or 0) - (h.prog_game or 0) > 900) or h.zone ~= h.prog_zone then
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
    -- (the website's own clock can be wrong, as after the server restart of 11 Nov 2026, 14 hours ahead: then its
    --  reset time is read against this PC's clock; a reset that comes out already past becomes the next 15:00 UTC,
    --  so VenGo doesn't keep asking the website, whose numbers then run over the game's)
    local nr, now = isoSeconds(V.nextReset), isoSeconds(r.currentTime);
    local at = SITE.at or os.time();
    local pc = os.time(os.date('!*t', at));
    if nr and now and math.abs(now - pc) > 900 then now = pc; end
    if nr and now then SITE.resetAt = at + (nr - now); end
    if SITE.resetAt and SITE.resetAt <= at then SITE.resetAt = at + (15 * 3600 - at % 86400) % 86400; end
    if SITE.resetAt and SITE.resetAt <= at then SITE.resetAt = at + 86400; end

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
    if data and data.ventures and (data.success == false or data.mock) then
        -- (the site sent its placeholder, not the board: keep what we have and ask again in 10 minutes)
        SITE.pending = false;
        SITE.err = 'catseyexi.com sent placeholder data; trying again soon';
        SITE.retryAt = os.time() + 600;
        os.remove(siteTmp());
    elseif data and data.ventures then
        SITE.pending, SITE.retryAt = false, nil;
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
    if data and data.ventures and (data.success == false or data.mock) then
        SITE.at = nil;                                               -- (a placeholder was saved: fetch the real board)
    elseif data and data.ventures then
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
    if SITE.retryAt and now >= SITE.retryAt then return true; end
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
    [173] = { name = 'Zeruhn Mines',                                  -- Korroloka Tunnel
              sg = { 'Zeruhn Mines' } },                              --   Zeruhn Mines Survival Guide
    [91] = { name = "Crawlers' Nest [S]",                             -- Rolanberry Fields [S]
             sg = { "Crawlers' Nest [S]" } },                         --   Crawlers' Nest [S] Survival Guide
    [123] = { name = 'Kazham',                                        -- Yuhtunga Jungle (it has no Home Point)
              hp = { 'Kazham' } },                                    --   Kazham Home Point
    [118] = { name = 'Bibiki Bay', nm = 'puffer pugil',               -- Buburimu Peninsula (only for Puffer Pugil)
              sg = { 'Bibiki Bay' } },                                --   Bibiki Bay Survival Guide
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
    if ov and ov.nm and not tostring(v.nm or ''):lower():find(ov.nm, 1, true) then ov = nil; end   -- (an override for one VNM)
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
        if #opts[sys] > 0 then
            local via = opts[sys][1].via;                         -- (a warp into the zone next door: say which)
            have[#have + 1] = SYS_NAME[sys] .. (via and (' (' .. via .. ')') or ((#opts[sys] > 1) and ('s (' .. #opts[sys] .. ')') or ''));
        end
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
    if ov and ov.nm and not tostring(v.nm or ''):lower():find(ov.nm, 1, true) then ov = nil; end
    local ovZone = nil;
    if ov then
        for _, sys in ipairs({ 'hp', 'sg' }) do
            for _, d in ipairs(WARPS[sys].dest) do if d.alias == (ov[sys] or {})[1] then ovZone = d.zone; end end
        end
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
    { 'sakura',  'Sakura',        { 1.00, 0.66, 0.80 }, { 0.95, 0.80, 0.90 }, { 1.00, 0.86, 0.92 } },
    { 'mint',    'Mint',          { 0.45, 1.00, 0.80 }, { 0.70, 0.95, 0.60 }, { 0.76, 0.98, 0.88 } },
    { 'teal',    'Teal',          { 0.20, 0.85, 0.80 }, { 0.20, 0.55, 0.90 }, { 0.66, 0.90, 0.90 } },
    { 'royal',   'Royal',         { 0.45, 0.50, 1.00 }, { 0.75, 0.40, 1.00 }, { 0.74, 0.76, 1.00 } },
    { 'cyber',   'Cyber',         { 0.15, 0.95, 1.00 }, { 1.00, 0.25, 0.85 }, { 0.70, 0.92, 1.00 } },
    { 'aurora',  'Aurora',        { 0.35, 1.00, 0.55 }, { 0.60, 0.35, 1.00 }, { 0.72, 0.96, 0.82 } },
    { 'ember',   'Ember',         { 1.00, 0.42, 0.18 }, { 0.95, 0.75, 0.20 }, { 1.00, 0.78, 0.62 } },
    { 'amber',   'Amber',         { 1.00, 0.70, 0.10 }, { 0.90, 0.40, 0.10 }, { 1.00, 0.86, 0.56 } },
    { 'lime',    'Lime',          { 0.70, 1.00, 0.20 }, { 0.30, 0.85, 0.40 }, { 0.86, 1.00, 0.66 } },
    { 'lilac',   'Lilac',         { 0.80, 0.62, 1.00 }, { 0.55, 0.62, 1.00 }, { 0.86, 0.80, 1.00 } },
    { 'blood',   'Blood moon',    { 0.85, 0.10, 0.20 }, { 0.45, 0.05, 0.20 }, { 0.90, 0.60, 0.64 } },
    { 'mono',    'Silver',        { 0.92, 0.92, 0.95 }, { 0.60, 0.62, 0.68 }, { 0.86, 0.86, 0.90 } },
};
C.bgs = {
    { 'violet',   'Violet black', { 0.068, 0.066, 0.088 }, { 0.165, 0.158, 0.205 }, { 0.090, 0.084, 0.115 }, { 0.060, 0.056, 0.080 } },
    { 'black',    'Black',        { 0.045, 0.045, 0.048 }, { 0.140, 0.140, 0.150 }, { 0.065, 0.065, 0.070 }, { 0.035, 0.035, 0.040 } },
    { 'navy',     'Navy',         { 0.045, 0.065, 0.105 }, { 0.130, 0.170, 0.240 }, { 0.065, 0.090, 0.140 }, { 0.035, 0.050, 0.085 } },
    { 'charcoal', 'Charcoal',     { 0.105, 0.105, 0.115 }, { 0.210, 0.210, 0.230 }, { 0.130, 0.130, 0.142 }, { 0.080, 0.080, 0.090 } },
    { 'plum',     'Plum',         { 0.090, 0.050, 0.085 }, { 0.215, 0.140, 0.205 }, { 0.120, 0.070, 0.112 }, { 0.070, 0.038, 0.066 } },
    { 'forest',   'Forest',       { 0.045, 0.075, 0.060 }, { 0.130, 0.190, 0.160 }, { 0.065, 0.100, 0.082 }, { 0.035, 0.058, 0.046 } },
    { 'midnight', 'Midnight',     { 0.030, 0.035, 0.075 }, { 0.110, 0.120, 0.230 }, { 0.045, 0.052, 0.105 }, { 0.022, 0.026, 0.060 } },
    { 'wine',     'Wine',         { 0.085, 0.030, 0.045 }, { 0.220, 0.100, 0.130 }, { 0.115, 0.045, 0.062 }, { 0.062, 0.020, 0.032 } },
    { 'slate',    'Slate',        { 0.075, 0.090, 0.105 }, { 0.170, 0.200, 0.230 }, { 0.095, 0.112, 0.130 }, { 0.055, 0.066, 0.078 } },
    { 'ocean',    'Deep sea',     { 0.025, 0.070, 0.085 }, { 0.090, 0.190, 0.220 }, { 0.035, 0.095, 0.115 }, { 0.018, 0.050, 0.062 } },
    { 'cocoa',    'Cocoa',        { 0.085, 0.060, 0.045 }, { 0.210, 0.160, 0.125 }, { 0.112, 0.080, 0.060 }, { 0.060, 0.042, 0.030 } },
    { 'dusk',     'Dusk',         { 0.075, 0.055, 0.100 }, { 0.200, 0.150, 0.250 }, { 0.100, 0.072, 0.132 }, { 0.055, 0.040, 0.075 } },
    { 'steel',    'Steel',        { 0.105, 0.115, 0.130 }, { 0.230, 0.250, 0.280 }, { 0.135, 0.148, 0.165 }, { 0.080, 0.088, 0.100 } },
    { 'void',     'Void',         { 0.010, 0.010, 0.014 }, { 0.090, 0.090, 0.110 }, { 0.022, 0.022, 0.030 }, { 0.006, 0.006, 0.010 } },
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
    if TRF.PH then TRF.PH.apply(); end                               -- (Phantom's colours over these)
end

local SW, ROW_W, MARGIN = 200, 760, 8;
local FULL_ROW = 830;                                   -- width the venture rows need
local WIN_W = SW + 30 + MARGIN + FULL_ROW + 50;         -- starting size; the window can be resized
local WIN_H = 700;
local MIN_W, MIN_H = 640, 460;

local TABS = { 'VENTURES', 'HELM', 'FISHING', 'DYNAMIS', 'HUNTER', 'SUMMIT', 'DAILIES', 'CATSEYEXI', 'VNM ARMOR', 'ULTIMATES', 'LUMORIA', 'ODIOUS CODEX', 'SPARK VENDOR', 'SETTINGS', 'SPECIAL THANKS' };
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
    fonts.ph    = add(addon.path .. 'fonts\\texgyreheroscn-bold.otf', 18);   -- (Phantom: a bold narrow face,
    fonts.phH   = add(addon.path .. 'fonts\\Inter-Black.otf', 34);           --  a heavy one for titles)
    fonts.ne    = add(addon.path .. 'fonts\\texgyretermes-bolditalic.otf', 26);   -- (Neon: titles and menu rows, italic serif)
    fonts.jp    = add(addon.path .. 'fonts\\NotoSansJP-Medium-VenGo.otf', 16);   -- (Japanese: Noto Sans JP, cut down to
    fonts.jpB   = add(addon.path .. 'fonts\\NotoSansJP-Bold-VenGo.otf', 18);     --  the letters VenGo uses)
    fonts.jpH   = add(addon.path .. 'fonts\\NotoSansJP-Black-VenGo.otf', 30);
end
local function newFont(f)
    local ok, ls = pcall(function () return f.LegacySize; end);
    return ok and ls ~= nil;
end
local function pushFont(f, size)
    if TRF.PH and TRF.PH.on() then                                -- (Phantom: its own faces)
        if f == fonts.panel and fonts.ph then f, size = fonts.ph, (size or 16) * 1.12;
        elseif (f == fonts.title or f == fonts.big) and fonts.phH then f = fonts.phH; end
    end
    f, size = TRF.LANG.face(f, size);                             -- (Japanese: its own faces)
    if f == nil then return false; end
    if newFont(f) then return (pcall(imgui.PushFont, f, size)); end
    return (pcall(imgui.PushFont, f));
end

------------------------------------------------------------------------
-- JAPANESE (the EN / JP switch at the top of the window). The words come from lang_jp.lua; they're put in where
-- the text is drawn and measured (Text, tooltips, CalcTextSize, the draw list's AddText, spaced capitals), so the
-- layout measures the Japanese. Lines put together from pieces are matched by their shape ({1}, {2}...); names
-- from the game stay in English. Japanese is drawn in Noto Sans CJK JP (fonts\, cut down to the letters needed).
------------------------------------------------------------------------
TRF.LANG = { cache = {}, n = 0, live = false };
function TRF.LANG.on() return config.lang == 'jp' and TRF.LANG.D ~= nil and fonts.jp ~= nil; end
function TRF.LANG.load()
    local L = TRF.LANG;
    local ok, d = pcall(dofile, addon.path .. 'lang_jp.lua');
    if not ok or type(d) ~= 'table' or type(d.T) ~= 'table' then return false; end
    L.D, L.lc, L.F, L.pre = d, {}, {}, {};
    for en, jp in pairs(d.T) do
        L.lc[en:lower()] = jp;
        if en:find('%%[%-%d%.]*[sdf]') then                       -- (a line with numbers or names put in: its shape)
            local p, i, specs = '^', 1, {};
            while i <= #en do
                local c = en:sub(i, i);
                local spec = (c == '%') and en:match('^%%[%-%d%.]*[sdf]', i) or nil;
                if c == '%' and en:sub(i + 1, i + 1) == '%' then p, i = p .. '%%', i + 2;
                elseif spec then
                    specs[#specs + 1] = spec;
                    local nxt = en:match('^%%[%-%d%.]*[sdf]', i + #spec);    -- (a %s right before another: one word)
                    p, i = p .. ((spec:sub(-1) == 's') and (nxt and '(%S*)' or '(.-)') or '([%-%d%.]+)'), i + #spec;
                else
                    p, i = p .. (c:find('[%^%$%(%)%%%.%[%]%*%+%-%?]') and ('%' .. c) or c), i + 1;
                end
            end
            L.F[#L.F + 1] = { p .. '$', jp, specs, #en };
        elseif #en >= 3 and (en:sub(-1) == ' ' or en:sub(-1) == '(') then
            L.pre[#L.pre + 1] = { en, jp };                       -- (the start of a line, the rest put on after it)
        end
    end
    table.sort(L.F, function (a, b) return a[4] > b[4]; end);
    table.sort(L.pre, function (a, b) return #a[1] > #b[1]; end);
    L.cache, L.n = {}, 0;
    return true;
end
function TRF.LANG.fill(t, caps, depth)
    return (t:gsub('{(%d)}', function (k) return TRF.LANG.look(caps[tonumber(k)] or '', depth + 1); end));
end
function TRF.LANG.look(s, depth)
    if s == '' or not s:find('%a') then return s; end
    local L = TRF.LANG;
    local body, id = s:match('^(.-)(##.*)$');
    if body then return L.look(body, depth) .. id; end
    local t = L.D.T[s] or L.lc[s:lower()];
    if t then return t; end
    if depth > 3 then return s; end
    for _, p in ipairs(L.D.P or {}) do
        local caps = { s:match(p[1]) };
        if caps[1] ~= nil then return L.fill(p[2], caps, depth); end
    end
    for _, f in ipairs(L.F) do
        local caps = { s:match(f[1]) };
        if caps[1] ~= nil then return L.fill(f[2], caps, depth); end
    end
    for _, p in ipairs(L.pre) do
        if s:sub(1, #p[1]) == p[1] then return p[2] .. L.look(s:sub(#p[1] + 1), depth + 1); end
    end
    return s;
end
function TRF.LANG.tr(s)
    local L = TRF.LANG;
    if type(s) ~= 'string' or L.D == nil then return s; end
    local c = L.cache[s];
    if c then return c; end
    local ok, r = pcall(L.look, s, 0);
    if not ok or type(r) ~= 'string' then r = s; end
    if L.n > 4000 then L.cache, L.n = {}, 0; end
    L.cache[s], L.n = r, L.n + 1;
    return r;
end
-- A format for imgui (a slider's): the Japanese with the format's own %d / %.1f back in place
function TRF.LANG.fmt(f)
    local L = TRF.LANG;
    if not L.live or type(f) ~= 'string' or L.D == nil then return f; end
    local jp = L.D.T[f];
    if jp == nil then return f; end
    local specs = {};
    for sp in f:gmatch('%%[%-%d%.]*[sdf]') do specs[#specs + 1] = sp; end
    return (jp:gsub('%%', '%%%%'):gsub('{(%d)}', function (k) return specs[tonumber(k)] or ''; end));
end
-- The face to draw with: in Japanese, Noto Sans JP (bold in Phantom; black for titles)
function TRF.LANG.face(f, size)
    if not TRF.LANG.live then return f, size; end
    if f == fonts.ne then return fonts.jpB or f, (size or 18) * 0.9; end
    if f == fonts.panel or f == fonts.ph then
        return ((TRF.PH and TRF.PH.on()) and fonts.jpB or fonts.jp) or f, (size or 16) * 0.94;
    elseif f == fonts.title or f == fonts.big then return fonts.jpB or f, size;
    elseif f == fonts.phH then return fonts.jpH or f, size; end
    return f, size;
end
-- Put the translation in at the places text is drawn and measured (once; each one only translates in Japanese)
function TRF.LANG.hook()
    local L = TRF.LANG;
    if L.o == nil then
        L.o = {};
        local o, tr = L.o, L.tr;
        for _, k in ipairs({ 'TextColored', 'SetTooltip', 'CalcTextSize', 'Text', 'TextWrapped', 'TextDisabled', 'SliderFloat', 'SliderInt' }) do o[k] = imgui[k]; end
        if o.TextColored then imgui.TextColored = function (c, t, ...) if L.live then t = tr(t); end return o.TextColored(c, t, ...); end end
        if o.SetTooltip then imgui.SetTooltip = function (t, ...) if L.live then t = tr(t); end return o.SetTooltip(t, ...); end end
        if o.CalcTextSize then imgui.CalcTextSize = function (t, ...) if L.live then t = tr(t); end return o.CalcTextSize(t, ...); end end
        if o.Text then imgui.Text = function (t, ...) if L.live then t = tr(t); end return o.Text(t, ...); end end
        if o.TextWrapped then imgui.TextWrapped = function (t, ...) if L.live then t = tr(t); end return o.TextWrapped(t, ...); end end
        if o.TextDisabled then imgui.TextDisabled = function (t, ...) if L.live then t = tr(t); end return o.TextDisabled(t, ...); end end
        if o.SliderFloat then imgui.SliderFloat = function (a, b, c, d, e, ...) return o.SliderFloat(a, b, c, d, L.fmt(e), ...); end end
        if o.SliderInt then imgui.SliderInt = function (a, b, c, d, e, ...) return o.SliderInt(a, b, c, d, L.fmt(e), ...); end end
    end
    if L.dl == nil then                                           -- (the draw lists' AddText, through their metatable)
        L.dl = false;
        pcall(function ()
            local dl = imgui.GetBackgroundDrawList();
            local mt = dl and debug.getmetatable(dl);
            if mt == nil then return; end
            local tr = L.tr;
            local function wrap(orig)
                return function (self, a, b, c, d, e, ...)
                    if L.live then
                        if type(c) == 'string' then c = tr(c); elseif type(e) == 'string' then e = tr(e); end
                    end
                    return orig(self, a, b, c, d, e, ...);
                end
            end
            local ix = mt.__index;
            if type(ix) == 'table' and type(ix.AddText) == 'function' then
                ix.AddText = wrap(ix.AddText);
                L.dl = true;
            elseif type(ix) == 'function' then
                local w;
                mt.__index = function (self, k)
                    if k == 'AddText' then
                        if w == nil then w = wrap(ix(self, k)); end
                        return w;
                    end
                    return ix(self, k);
                end
                L.dl = true;
            end
        end);
    end
end
-- Each frame: Japanese on or off (the hooks look at this, not at the settings)
function TRF.LANG.frame()
    local L = TRF.LANG;
    if config.lang == 'jp' and L.D == nil and not L.tried then L.tried = true; L.load(); end
    L.live = L.on();
    if L.live and (L.o == nil or L.dl == nil) then L.hook(); end
end
-- A chat line in Japanese: translated, and in Shift-JIS for the game
function TRF.LANG.chat(text)
    local L = TRF.LANG;
    if config.lang ~= 'jp' or L.D == nil then return text; end
    local t = L.tr(text);
    local ok, s = pcall(function () return vana.encoding.to_shift_jis(t); end);
    return (ok and type(s) == 'string') and s or text;
end
-- The EN / JP switch (top of the window): two halves, the language on in the accent
function TRF.LANG.toggle(dl, x, y, h)
    local L = TRF.LANG;
    local w = 58;
    imgui.SetCursorScreenPos({ x, y });
    local clicked = imgui.InvisibleButton('##vengo_lang', { w, h });
    local hov = imgui.IsItemHovered();
    local jp = config.lang == 'jp';
    local ph = TRF.PH and TRF.PH.on();
    local acc = ph and C.hp or C.acc;
    local half = w / 2;
    local bg = u32({ 0.08, 0.07, 0.10, 0.9 });
    local on = u32({ acc[1], acc[2], acc[3], 0.95 });
    if ph then
        TRF.PH.q(dl, x, y + 3, x + w, y, x + w - 2, y + h, x + 1, y + h + 1, bg);
        local a = jp and half or 0;
        TRF.PH.q(dl, x + a + 2, y + 4, x + a + half - 1, y + 2, x + a + half - 2, y + h - 1, x + a + 2, y + h - 1, on);
    else
        dl:AddRectFilled({ x, y }, { x + w, y + h }, bg, h / 2);
        dl:AddRectFilled({ x + (jp and half or 0) + 2, y + 2 }, { x + (jp and w or half) - 2, y + h - 2 }, on, (h - 4) / 2);
        dl:AddRect({ x, y }, { x + w, y + h }, u32({ acc[1], acc[2], acc[3], hov and 0.9 or 0.45 }), h / 2, C.rall, 1);
    end
    local was = L.live;
    L.live = false;                                               -- (EN and JP are themselves; JP drawn in the Japanese face)
    local tw = (L.o and L.o.CalcTextSize or imgui.CalcTextSize)('EN');
    local _, th = imgui.CalcTextSize('EN');
    imgui.SetWindowFontScale(0.8);
    tw, th = tw * 0.8, th * 0.8;
    dl:AddText({ x + (half - tw) / 2, y + (h - th) / 2 }, u32(jp and C.muted or (ph and TRF.PH.sel or { 1, 1, 1, 1 })), 'EN');
    dl:AddText({ x + half + (half - tw) / 2, y + (h - th) / 2 }, u32(jp and (ph and TRF.PH.sel or { 1, 1, 1, 1 }) or C.muted), 'JP');
    imgui.SetWindowFontScale(1);
    L.live = was;
    if hov then imgui.SetTooltip(jp and '言語: 日本語 (クリックで英語)' or 'Language: English (click for Japanese)'); end
    if clicked then
        config.lang = jp and 'en' or 'jp';
        if config.lang == 'jp' and L.D == nil then L.load(); end
        if config.lang == 'jp' and (L.D == nil or fonts.jp == nil) then
            config.lang = 'en';
            msg('Japanese needs lang_jp.lua and fonts\\NotoSansJP-*-VenGo.otf in the vengo folder.');
        end
        saveSettings();
    end
end

------------------------------------------------------------------------
-- PHANTOM STYLE (Settings > Colours > Style): red, black and white, slanted, as ChadcoreMenu's Phantom style.
-- The panel is a black slab edged white on a red one; titles are heavy cut-out letters; the menu is dark strips with
-- the page you're on as a white slab and a red slash. Its fonts (TeX Gyre Heros Cn Bold, Inter Black) are in fonts\.
------------------------------------------------------------------------
TRF.PH = {
    ACC  = { { 'Red', { 0.92, 0.04, 0.08 }, { 0.72, 0.02, 0.06 }, { 0.95, 0.12, 0.14 } },
             { 'Crimson', { 0.75, 0.02, 0.18 }, { 0.55, 0.01, 0.12 }, { 0.90, 0.20, 0.32 } },
             { 'Blue', { 0.10, 0.45, 0.98 }, { 0.05, 0.28, 0.75 }, { 0.35, 0.65, 1.00 } },
             { 'Gold', { 0.98, 0.72, 0.08 }, { 0.80, 0.50, 0.04 }, { 1.00, 0.80, 0.30 } },
             { 'Pink', { 1.00, 0.25, 0.60 }, { 0.80, 0.12, 0.45 }, { 1.00, 0.45, 0.72 } },
             { 'Green', { 0.15, 0.85, 0.40 }, { 0.08, 0.60, 0.28 }, { 0.40, 0.95, 0.60 } },
             { 'Purple', { 0.62, 0.30, 1.00 }, { 0.45, 0.18, 0.85 }, { 0.74, 0.55, 1.00 } } },
    SLAB = { { 'Black', { 0.035, 0.030, 0.035 } }, { 'Charcoal', { 0.10, 0.10, 0.11 } }, { 'Navy', { 0.04, 0.06, 0.13 } }, { 'Wine', { 0.12, 0.03, 0.05 } } },
    EDGE = { { 'White', { 0.97, 0.96, 0.94 } }, { 'Cream', { 0.98, 0.92, 0.80 } }, { 'Silver', { 0.78, 0.80, 0.84 } }, { 'Black', { 0.06, 0.06, 0.06 } } },
    edge = { 0.97, 0.96, 0.94 }, sel = { 0.04, 0.04, 0.04, 1 }, orig = nil,
};
function TRF.PH.on() return config.style == 'phantom' or config.style == 'neon'; end   -- (Neon rides on Phantom's plumbing)
function TRF.PH.pick(L, v) for _, t in ipairs(L) do if t[1] == v then return t; end end return L[1]; end
-- The palette: Phantom's over the theme's (text, slab, accent, edge); the theme's back when it's off
function TRF.PH.apply()
    local P = TRF.PH;
    local function set(dst, src) dst[1], dst[2], dst[3] = src[1], src[2], src[3]; end
    if P.orig == nil then P.orig = { text = { unpack(C.text) }, muted = { unpack(C.muted) } }; end
    set(C.text, P.orig.text); set(C.muted, P.orig.muted);
    if not P.on() then return; end
    local ac, sl, ed = P.pick(P.ACC, config.ph_accent), P.pick(P.SLAB, config.ph_slab), P.pick(P.EDGE, config.ph_edge);
    set(C.text, { 0.97, 0.96, 0.94 }); set(C.muted, { 0.76, 0.74, 0.72 });
    set(NEON2, ac[2]); set(C.hp, ac[2]); set(C.mp2, ac[3]); set(NEON, ac[3]);
    set(C.acc, ac[4]); set(C.lav, ac[4]); set(C.label, ed[2]);
    local s = sl[2];
    set(C.pbg, s); set(C.panel, s);
    set(C.pframe, { s[1] + 0.10, s[2] + 0.10, s[3] + 0.11 }); set(C.well, { s[1] * 0.5 + 0.06, s[2] * 0.5 + 0.055, s[3] * 0.5 + 0.06 });
    P.edge = { ed[2][1], ed[2][2], ed[2][3] };
    P.sel = (ed[1] == 'Black') and { 0.97, 0.96, 0.94, 1 } or { 0.04, 0.04, 0.04, 1 };
end
-- Drawing pieces: a four-cornered shape (in one piece, else two triangles), its edge, and drawing past the window
function TRF.PH.q(dl, a, b, c, d, e, f, g, h, col)
    local ok = TRF.PH.qok ~= false and pcall(dl.AddQuadFilled, dl, { a, b }, { c, d }, { e, f }, { g, h }, col);
    if ok then TRF.PH.qok = true; return; end
    TRF.PH.qok = false;
    dl:AddTriangleFilled({ a, b }, { c, d }, { e, f }, col); dl:AddTriangleFilled({ a, b }, { e, f }, { g, h }, col);
end
function TRF.PH.ql(dl, a, b, c, d, e, f, g, h, col, th)
    dl:AddLine({ a, b }, { c, d }, col, th); dl:AddLine({ c, d }, { e, f }, col, th);
    dl:AddLine({ e, f }, { g, h }, col, th); dl:AddLine({ g, h }, { a, b }, col, th);
end
function TRF.PH.clip(dl) pcall(function () dl:PushClipRect({ -10000, -10000 }, { 20000, 20000 }, false); end); end
function TRF.PH.unclip(dl) pcall(function () dl:PopClipRect(); end); end
function TRF.PH.font(f, size)                                    -- (a face at a size: true if it was pushed)
    f, size = TRF.LANG.face(f, size);
    if f == nil then return false; end
    local ok_ = pcall(function () return f.LegacySize; end);
    if ok_ then return (pcall(imgui.PushFont, f, size)); end
    return (pcall(imgui.PushFont, f));
end
-- The panel: a slanted slab edged in white, a red one behind it sticking out down and to the right
function TRF.PH.frame(dl, x, y, w, h)
    if TRF.NE.on() then return TRF.NE.panel(dl, x, y, x + w, y + h, 1); end
    local P = TRF.PH;
    local a = config.transparent and 0.6 or 1;
    local k, q = math.min(12, w * 0.03), 3;
    P.clip(dl);
    P.q(dl, x + 4, y + k + 8, x + w + 12, y + 2, x + w + 10, y + h + 10, x + 8, y + h + k + 12, u32({ C.hp[1], C.hp[2], C.hp[3], a }));
    P.q(dl, x - q, y + k, x + w + q, y - q, x + w + q * 0.4, y + h + q, x - q * 0.4, y + h + k + q, u32({ C.panel[1], C.panel[2], C.panel[3], config.transparent and 0.55 or 0.98 }));
    if TRF.BGI then pcall(TRF.BGI.draw, dl, x, y + k, w, h - k, 0); end
    P.ql(dl, x - q, y + k, x + w + q, y - q, x + w + q * 0.4, y + h + q, x - q * 0.4, y + h + k + q, u32({ P.edge[1], P.edge[2], P.edge[3], a }), 3);
    P.unclip(dl);
end
-- A title as cut-out letters: heavy black ones edged white, the first bigger, one turned white-on-black, on a black
-- slab with red shards behind. base: where the letters stand. Returns how wide it was.
-- A five-pointed star (filled from its middle): cx, cy its centre, r its points, turned by rot
function TRF.PH.star(dl, cx, cy, r, rot, col)
    local pts = {};
    for i = 0, 9 do
        local a = rot - math.pi / 2 + i * math.pi / 5;
        local rr = (i % 2 == 0) and r or r * 0.45;
        pts[#pts + 1] = { cx + math.cos(a) * rr, cy + math.sin(a) * rr };
    end
    for i = 1, 10 do dl:AddTriangleFilled({ cx, cy }, pts[i], pts[(i % 10) + 1], col); end
end
function TRF.PH.badge(dl, x, base, t, s, acc, star)
    t = tostring(t or ''):upper();
    if t == '' then return 0; end
    local seed = 0; for i = 1, #t do seed = (seed * 31 + t:byte(i)) % 9973; end
    local inv, cnt = nil, 0;
    for i = 2, #t do if t:sub(i, i):match('%a') then cnt = cnt + 1; if cnt == ((#t >= 6) and 4 or 2) then inv = i; end end end
    local f = fonts.phH or fonts.title;
    local SZ, ws, total = {}, {}, 0;
    for i = 1, #t do
        local ch = t:sub(i, i);
        local sz = ((i == 1) and 44 or ({ 31, 34, 36, 32, 35 })[((seed + i * 7) % 5) + 1]) * s;
        local pushed = TRF.PH.font(f, sz);
        local w = (ch == ' ') and sz * 0.42 or imgui.CalcTextSize(ch);
        if pushed then imgui.PopFont(); end
        SZ[i], ws[i] = sz, w; total = total + w + 1.2 * s;
    end
    local top, bot = base - 42 * s, base + 6 * s;
    local x0, x1 = x - 9 * s, x + total + 9 * s;
    acc = acc or C.hp;
    local red, wht, blk = u32({ acc[1], acc[2], acc[3], 1 }), u32({ TRF.PH.edge[1], TRF.PH.edge[2], TRF.PH.edge[3], 1 }), u32({ 0.03, 0.03, 0.03, 1 });
    local P = TRF.PH;
    P.clip(dl);
    if star then                                                  -- (a big star behind it, turning slowly; a dark one inside)
        local cx, cy, r = (x0 + x1) / 2, (top + bot) / 2, (bot - top) * 1.15;
        local rot = math.sin(os.clock() * 0.8) * 0.12 - 0.2;
        P.star(dl, cx, cy, r + 5 * s, rot, u32({ 0.03, 0.03, 0.03, 1 }));
        P.star(dl, cx, cy, r, rot, red);
        P.star(dl, cx, cy, r * 0.62, rot, u32({ acc[1] * 0.55, acc[2] * 0.55, acc[3] * 0.55, 1 }));
        P.star(dl, x0 - 4 * s, top + 2 * s, r * 0.42, -rot, red);        -- (two small ones at the ends)
        P.star(dl, x1 + 6 * s, bot - 2 * s, r * 0.36, rot * 1.5, red);
    end
    dl:AddTriangleFilled({ x0 - 18 * s, bot - 2 * s }, { x0 + 40 * s, top + 4 * s }, { x1 + 46 * s, top - 12 * s }, red);
    dl:AddTriangleFilled({ x1 - 30 * s, top + 12 * s }, { x1 + 52 * s, bot + 4 * s }, { x0 + 24 * s, bot + 10 * s }, red);
    dl:AddTriangleFilled({ x0 - 6 * s, top + 8 * s }, { x0 + 46 * s, top - 14 * s }, { x0 + 24 * s, top + 14 * s }, red);
    P.q(dl, x0 - 3 * s, top - 3 * s, x1 + 3 * s, top - 7 * s, x1 + 6 * s, bot + 3 * s, x0 - 1 * s, bot + 6 * s, wht);
    P.q(dl, x0, top, x1, top - 4 * s, x1 + 3 * s, bot, x0 + 2 * s, bot + 3 * s, blk);
    local cx = x;
    for i = 1, #t do
        local ch = t:sub(i, i);
        if ch ~= ' ' then
            local pushed = P.font(f, SZ[i]);
            local lh = imgui.GetTextLineHeight();
            local ly = base - lh * 0.92 + (((seed + i) % 3) - 1) * 1.2 * s;
            if i == inv then
                P.q(dl, cx - 2 * s, ly + lh * 0.16, cx + ws[i] + 2 * s, ly + lh * 0.12, cx + ws[i] + 3 * s, ly + lh * 0.96, cx - 1 * s, ly + lh * 0.98, wht);
                dl:AddText({ cx, ly }, blk, ch);
            else
                local o = 2.4 * s;
                for _, d in ipairs({ { -o, 0 }, { o, 0 }, { 0, -o }, { 0, o }, { -o, -o }, { o, o }, { -o, o }, { o, -o } }) do dl:AddText({ cx + d[1], ly + d[2] }, wht, ch); end
                dl:AddText({ cx, ly }, blk, ch);
            end
            if pushed then imgui.PopFont(); end
        end
        cx = cx + ws[i] + 1.2 * s;
    end
    P.unclip(dl);
    return x1 - x;
end
-- Titles made ahead as pictures (images\ph_*.png): the letters in a white-rimmed black sticker with the Japanese
-- under them, as ChadcoreMenu's. Name, its width and height, the picture's.
TRF.PH.IMG = { ['VENTURES'] = { 'ph_ventures', 248, 90, 256, 128 }, ['HELM'] = { 'ph_helm', 145, 85, 256, 128 }, ['FISHING'] = { 'ph_fishing', 190, 87, 256, 128 }, ['DYNAMIS'] = { 'ph_dynamis', 224, 93, 256, 128 }, ['HUNTER'] = { 'ph_hunter', 196, 87, 256, 128 }, ['SUMMIT'] = { 'ph_summit', 193, 91, 256, 128 }, ['DAILIES'] = { 'ph_dailies', 186, 89, 256, 128 }, ['CATSEYEXI'] = { 'ph_catseyexi', 263, 96, 512, 128 }, ['VNM ARMOR'] = { 'ph_vnm_armor', 291, 95, 512, 128 }, ['ULTIMATES'] = { 'ph_ultimates', 264, 96, 512, 128 }, ['LUMORIA'] = { 'ph_lumoria', 215, 91, 256, 128 }, ['ODIOUS CODEX'] = { 'ph_odious_codex', 339, 99, 512, 128 }, ['SPARK VENDOR'] = { 'ph_spark_vendor', 346, 97, 512, 128 }, ['SETTINGS'] = { 'ph_settings', 230, 91, 256, 128 }, ['SPECIAL THANKS'] = { 'ph_special_thanks', 381, 103, 512, 128 }, ['VNM INCOMING!'] = { 'ph_vnm_incoming', 360, 100, 512, 128 }, ['STARRED VNM!'] = { 'ph_starred_vnm', 339, 98, 512, 128 } };
-- A title, its top at y: the picture with shards (accent, or gold) and a star behind it if asked, or cut-out letters
-- when there's no picture. Returns its width and height.
function TRF.PH.title(dl, x, y, t, s, acc, star)
    local P = TRF.PH;
    if TRF.NE.on() then                                           -- (Neon: its own title, the Japanese under it)
        local key = tostring(t or ''):upper();
        local w = TRF.NE.title(dl, x + 18, y + 54, t, 0.85, acc, TRF.NE.ICON[key], TRF.NE.jp(key));
        return w + 10, 70;
    end
    local im = P.IMG[tostring(t or ''):upper()];
    local tex = im and TRF.imageTex and TRF.imageTex(im[1] .. '.png');
    if tex == nil then
        P.badge(dl, x + 9 * s, y + 46 * s, t, s, acc, star);
        return 0, 56 * s;
    end
    acc = acc or C.hp;
    local w, h = im[2] * s, im[3] * s;
    local x0, x1, top, bot = x, x + w, y, y + h;
    local red = u32({ acc[1], acc[2], acc[3], 1 });
    P.clip(dl);
    if star then                                                  -- (a big star behind, rocking gently; two small ones)
        local cx, cy, r = (x0 + x1) / 2 + 10 * s, (top + bot) / 2, h * 0.86;
        local rot = math.sin(os.clock() * 0.8) * 0.12 - 0.2;
        P.star(dl, cx, cy, r + 5 * s, rot, u32({ 0.03, 0.03, 0.03, 1 }));
        P.star(dl, cx, cy, r, rot, red);
        P.star(dl, cx, cy, r * 0.62, rot, u32({ acc[1] * 0.55, acc[2] * 0.55, acc[3] * 0.55, 1 }));
        P.star(dl, x0 + 4 * s, top + 8 * s, r * 0.36, -rot, red);
        P.star(dl, x1 - 2 * s, bot - 12 * s, r * 0.3, rot * 1.5, red);
    else                                                          -- (the shards, as on ChadcoreMenu's titles)
        dl:AddTriangleFilled({ x0 - 6 * s, bot - 14 * s }, { x0 + 40 * s, top + 22 * s }, { x1 + 30 * s, top + 4 * s }, red);
        dl:AddTriangleFilled({ x1 - 60 * s, top + 26 * s }, { x1 + 34 * s, bot - 6 * s }, { x0 + 30 * s, bot - 2 * s }, red);
        dl:AddTriangleFilled({ x0 + 6 * s, top + 18 * s }, { x0 + 52 * s, top + 2 * s }, { x0 + 30 * s, top + 30 * s }, red);
    end
    pcall(dl.AddImage, dl, tex.ptr, { x0, top }, { x1, bot }, { 0, 0 }, { im[2] / im[4], im[3] / im[5] }, u32({ 1, 1, 1, 1 }));
    P.unclip(dl);
    return w, h;
end
-- The header: the page's name as cut-out letters, "VenGo" and the version beside it
function TRF.PH.header(dl, x0, y0, name)
    if TRF.NE.on() then return TRF.NE.header(dl, x0, y0, name); end
    local w = TRF.PH.title(dl, x0 - 4, y0 - 8, name, 0.78);
    if w == 0 then w = TRF.PH.badge(dl, x0 + 4, y0 + 44, name, 0.82); end
    local x = x0 + w + 30;
    local pushed = TRF.PH.font(fonts.phH or fonts.title, 24);
    local ven = imgui.CalcTextSize('Ven');
    local y = y0 + 16;
    dl:AddText({ x, y }, u32(C.text), 'Ven');
    dl:AddText({ x + ven, y }, u32({ C.hp[1], C.hp[2], C.hp[3], 1 }), 'Go');
    local gw = imgui.CalcTextSize('Go');
    local _, th = imgui.CalcTextSize('VenGo');
    if pushed then imgui.PopFont(); end
    local vs = 'v' .. tostring(addon.version or '');
    local _, vh = imgui.CalcTextSize(vs);
    dl:AddText({ x + ven + gw + 8, y + th - vh - 2 }, u32(C.muted), vs);
end
-- One menu entry: a dark slanted strip (staggered a little, like steps); the page you're on is a white slab with a
-- red slash running past its edge and a pointer bobbing at its left
function TRF.PH.sideItem(dl, k, x0, y, sw, ih, on, over, label)
    if TRF.NE.on() then return TRF.NE.sideItem(dl, k, x0, y, sw, ih, on, over, label); end
    local P = TRF.PH;
    local sx = ((k % 3) - 1) * 3;
    if on then
        P.clip(dl);
        local red = u32({ C.hp[1], C.hp[2], C.hp[3], 0.97 });
        P.q(dl, x0 - 6, y - 2, x0 + sw * 0.6, y - 7, x0 + sw * 0.62, y + ih + 6, x0 - 2, y + ih + 5, red);
        dl:AddTriangleFilled({ x0 + sw * 0.5, y - 7 }, { x0 + sw + 26, y - 4 }, { x0 + sw * 0.6, y + ih * 0.5 }, red);
        dl:AddTriangleFilled({ x0 + sw * 0.55, y + ih * 0.35 }, { x0 + sw + 20, y + ih + 7 }, { x0 + sw * 0.5, y + ih + 6 }, red);
        P.q(dl, x0 + 6, y + 1, x0 + sw - 8, y - 3, x0 + sw - 12, y + ih + 1, x0 + 4, y + ih + 3, u32({ P.edge[1], P.edge[2], P.edge[3], 1 }));
        local bob = math.sin(os.clock() * 5) * 1.5;
        dl:AddTriangleFilled({ x0 - 16 + bob, y + 4 }, { x0 + 2 + bob, y + ih / 2 }, { x0 - 16 + bob, y + ih - 4 }, u32({ 0.03, 0.03, 0.03, 1 }));
        dl:AddTriangleFilled({ x0 - 13 + bob, y + 8 }, { x0 - 2 + bob, y + ih / 2 }, { x0 - 13 + bob, y + ih - 8 }, u32({ P.edge[1], P.edge[2], P.edge[3], 1 }));
        P.unclip(dl);
    else
        local c = over and { 0.24, 0.22, 0.23, 0.98 } or { 0.14, 0.13, 0.14, 0.95 };
        P.q(dl, x0 + 4 + sx, y + 3, x0 + sw - 6 + sx, y, x0 + sw - 9 + sx, y + ih - 1, x0 + 1 + sx, y + ih + 1, u32(c));
    end
    local _, nh = imgui.CalcTextSize(label);
    dl:AddText({ x0 + 16 + (on and 0 or sx), y + (ih - nh) / 2 }, u32(on and P.sel or (over and { 1, 1, 1, 1 } or C.text)), label:upper());
end
-- A button: a slanted slab. The main one white with black letters, a red shard behind it when the mouse is on it;
-- the quiet ones dark with white letters and a red line under them on the mouse. (Returns nothing: the click is the caller's.)
function TRF.PH.button(dl, x, y, w, h, name, lw, lh, sp, quiet, small, hov, act)
    if TRF.NE.on() then return TRF.NE.button(dl, x, y, w, h, name, lw, lh, sp, quiet, small, hov, act); end
    local P = TRF.PH;
    local k = math.min(6, h * 0.18);
    local red = u32({ C.hp[1], C.hp[2], C.hp[3], 1 });
    -- (drawn inside the window's clip: in a scrolling list, a button out of view stays out of view)
    local light = not quiet and not small;                       -- (the big main button: a white slab)
    if light then
        if hov or act then P.q(dl, x + 4, y + k + 4, x + w + 7, y + 2, x + w + 4, y + h + 5, x + 2, y + h + 4, red); end
        P.q(dl, x, y + k, x + w, y, x + w - 2, y + h - 1, x + 1, y + h, u32(act and { 0.80, 0.79, 0.77, 1 } or { P.edge[1], P.edge[2], P.edge[3], 1 }));
    elseif not quiet then                                         -- (a small main button, as on each row: dark, edged in the accent)
        local c = act and { 0.30, 0.28, 0.29, 1 } or (hov and { 0.24, 0.22, 0.23, 1 } or { 0.15, 0.14, 0.15, 1 });
        P.q(dl, x, y + k, x + w, y, x + w - 2, y + h - 1, x + 1, y + h, u32(c));
        P.ql(dl, x, y + k, x + w, y, x + w - 2, y + h - 1, x + 1, y + h, u32({ C.hp[1], C.hp[2], C.hp[3], hov and 1 or 0.75 }), 1.5);
    else
        local c = act and { 0.30, 0.28, 0.29, 1 } or (hov and { 0.22, 0.20, 0.21, 1 } or { 0.13, 0.12, 0.13, 1 });
        P.q(dl, x, y + k, x + w, y, x + w - 2, y + h - 1, x + 1, y + h, u32(c));
        if hov then dl:AddLine({ x + 6, y + h - 1 }, { x + w - 4, y + h - 3 }, red, 2); end
    end
    if small then imgui.SetWindowFontScale(0.82); end
    TRF.spaced(dl, x + (w - lw) / 2, y + (h - lh) / 2 + k * 0.3, name, u32(light and P.sel or C.text), sp);
    if small then imgui.SetWindowFontScale(1); end
end
-- The VNM alert's panel: a black slab edged white on a red (gold for a starred VNM) one that pulses out behind it
function TRF.PH.alertFrame(dl, x, y, w, h, gc, pulse)
    if TRF.NE.on() then return TRF.NE.alertFrame(dl, x, y, w, h, gc, pulse); end
    local P = TRF.PH;
    local k = math.min(12, w * 0.03);
    local o = 9 + 5 * pulse;
    P.clip(dl);
    P.q(dl, x + 6, y + k + o + 6, x + w + o + 10, y + 4, x + w + o + 8, y + h + o + 4, x + 10, y + h + k + o + 6, u32({ gc[1], gc[2], gc[3], 0.25 * pulse }));
    P.q(dl, x + 4, y + k + 9, x + w + 12, y + 3, x + w + 10, y + h + 11, x + 8, y + h + k + 13, u32({ gc[1], gc[2], gc[3], 1 }));
    P.q(dl, x - 3, y + k, x + w + 3, y - 3, x + w + 1, y + h + 3, x - 1, y + h + k + 3, u32({ C.panel[1], C.panel[2], C.panel[3], config.transparent and 0.75 or 0.98 }));
    P.ql(dl, x - 3, y + k, x + w + 3, y - 3, x + w + 1, y + h + 3, x - 1, y + h + k + 3, u32({ P.edge[1], P.edge[2], P.edge[3], 1 }), 3);
    P.unclip(dl);
end
-- A section's name: white capitals on a small black slab edged white, a red shard behind, a thin line after
function TRF.PH.section(dl, x0, y0, text)
    if TRF.NE.on() then return TRF.NE.section(dl, x0, y0, text); end
    local P = TRF.PH;
    local t = text:upper();
    local w, lh = imgui.CalcTextSize(t);
    lh = imgui.GetTextLineHeight();
    local x1, y1 = x0 + w + 28, y0 + lh + 4;
    P.q(dl, x0 + 2, y0 + 4, x1 + 8, y0 + 1, x1 + 6, y1 + 4, x0 + 5, y1 + 6, u32({ C.hp[1], C.hp[2], C.hp[3], 1 }));
    P.q(dl, x0 - 2, y0 - 1, x1, y0 - 3, x1 - 2, y1, x0, y1 + 1, u32({ 0.03, 0.03, 0.03, 1 }));
    P.ql(dl, x0 - 2, y0 - 1, x1, y0 - 3, x1 - 2, y1, x0, y1 + 1, u32({ P.edge[1], P.edge[2], P.edge[3], 1 }), 1.5);
    dl:AddText({ x0 + 9, y0 + 1 }, u32({ P.edge[1], P.edge[2], P.edge[3], 1 }), t);
    dl:AddLine({ x1 + 14, y0 + lh / 2 + 2 }, { x0 + ROW_W, y0 + lh / 2 + 2 }, u32({ C.hp[1], C.hp[2], C.hp[3], 0.35 }), 1.5);
    return lh + 6;
end

------------------------------------------------------------------------
-- NEON (Settings > Colours > Style): ChadcoreMenu 3.57's "Neon" look, from its chadcore_ui bundle, copied into
-- VenGo (nothing of ChadcoreMenu's is needed). Dark slabs in a glowing double line of the accent, italic serif
-- titles with an icon box and the Japanese under them, menu rows that lean, a spark running round the title.
-- It rides on Phantom's plumbing (its fonts, palette and the places it draws); TRF.PH.* hand over to these.
------------------------------------------------------------------------
TRF.NE = { INK = { 0.035, 0.035, 0.042 }, STRIP = { 0.10, 0.10, 0.115 },
    ICON = { VENTURES = 11, HELM = 8, FISHING = 10, DYNAMIS = 4, HUNTER = 13, SUMMIT = 6, DAILIES = 12, CATSEYEXI = 9,
             ['VNM ARMOR'] = 1, ULTIMATES = 0, LUMORIA = 3, ['ODIOUS CODEX'] = 12, ['SPARK VENDOR'] = 7, SETTINGS = 'gear',
             ['SPECIAL THANKS'] = 2, ['VNM INCOMING!'] = 13, ['STARRED VNM!'] = 6 },
    JP = { ['VNM INCOMING!'] = 'VNM出現', ['STARRED VNM!'] = 'スターVNM' } };
function TRF.NE.on() return config.style == 'neon'; end
function TRF.NE.col(a) local c = C.acc; return u32({ c[1], c[2], c[3], a or 1 }); end
-- a convex outline, filled (in one path, else as a fan of triangles)
function TRF.NE.fill(dl, P, col)
    local N = TRF.NE;
    if #P < 3 then return; end
    if N.pok ~= false then
        local ok = pcall(function ()
            dl:PathClear();
            for i = 1, #P do dl:PathLineTo(P[i]); end
            dl:PathFillConvex(col);
        end);
        if ok then N.pok = true; return; end
        N.pok = false; pcall(function () dl:PathClear(); end);
    end
    for i = 2, #P - 1 do dl:AddTriangleFilled(P[1], P[i], P[i + 1], col); end
end
-- the outline pushed out by o all round (in, if negative)
function TRF.NE.grow(P, o)
    local n = #P;
    local cx, cy = 0, 0;
    for _, p in ipairs(P) do cx, cy = cx + p[1] / n, cy + p[2] / n; end
    local function nrm(u, w)
        local ex, ey = w[1] - u[1], w[2] - u[2];
        local l = math.sqrt(ex * ex + ey * ey); if l < 0.001 then l = 0.001; end
        local nx, ny = ey / l, -ex / l;
        if ((u[1] + w[1]) / 2 - cx) * nx + ((u[2] + w[2]) / 2 - cy) * ny < 0 then nx, ny = -nx, -ny; end
        return nx, ny;
    end
    local out = {};
    for i = 1, n do
        local a, p, b = P[(i - 2) % n + 1], P[i], P[i % n + 1];
        local n1x, n1y = nrm(a, p);
        local n2x, n2y = nrm(p, b);
        local mx, my = n1x + n2x, n1y + n2y;
        local ml = math.sqrt(mx * mx + my * my); if ml < 0.001 then mx, my, ml = n1x, n1y, 1; end
        mx, my = mx / ml, my / ml;
        local dd = mx * n1x + my * n1y; if dd < 0.35 then dd = 0.35; end
        out[i] = { p[1] + mx * o / dd, p[2] + my * o / dd };
    end
    return out;
end
function TRF.NE.outline(dl, P, col, th)
    for i = 1, #P do local p, q = P[i], P[i % #P + 1]; dl:AddLine(p, q, col, th); end
end
-- shapes in the neon frame: a soft glow, the bright line, the dark inside, a thin line just inside that
function TRF.NE.frame(dl, shapes, s, c, a)
    local N = TRF.NE;
    c = c or C.acc; a = a or 1;
    for _, P in ipairs(shapes) do N.fill(dl, N.grow(P, 8 * s), u32({ c[1], c[2], c[3], 0.14 * a })); end
    for _, P in ipairs(shapes) do N.fill(dl, N.grow(P, 5 * s), u32({ c[1], c[2], c[3], 0.30 * a })); end
    for _, P in ipairs(shapes) do N.fill(dl, N.grow(P, 2.6 * s), u32({ math.min(1, c[1] + 0.15), math.min(1, c[2] + 0.15), math.min(1, c[3] + 0.15), a })); end
    for _, P in ipairs(shapes) do N.fill(dl, P, u32({ 0.045 + c[1] * 0.04, 0.045 + c[2] * 0.04, 0.055 + c[3] * 0.04, a })); end
    for _, P in ipairs(shapes) do N.outline(dl, N.grow(P, -3.2 * s), u32({ c[1], c[2], c[3], 0.55 * a }), 1.1 * s); end
end
-- a bright spark running round an outline, a fading trail behind it (once round in about 3 s)
function TRF.NE.pulse(dl, E, s, c, a, seed)
    c = c or C.acc; a = a or 1;
    local len, segs = 0, {};
    for i = 1, #E do local p, q = E[i], E[i % #E + 1]; local d = math.sqrt((q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2); segs[i] = d; len = len + d; end
    if len < 1 then return; end
    local function at(t)
        t = t % len;
        for i = 1, #E do
            if t <= segs[i] then local p, q = E[i], E[i % #E + 1]; local u = t / math.max(0.001, segs[i]); return p[1] + (q[1] - p[1]) * u, p[2] + (q[2] - p[2]) * u; end
            t = t - segs[i];
        end
        return E[1][1], E[1][2];
    end
    local head = (os.clock() + (seed or 0)) * (len / 3.0);
    local trail = math.min(len * 0.22, 200 * s);
    for j = 12, 1, -1 do
        local ax, ay = at(head - trail * j / 12); local bx, by = at(head - trail * (j - 1) / 12);
        local u = 1 - (j - 1) / 12;
        if math.abs(ax - bx) + math.abs(ay - by) < trail then
            dl:AddLine({ ax, ay }, { bx, by }, u32({ c[1], c[2], c[3], 0.35 * u * a }), 6 * s * u);
            dl:AddLine({ ax, ay }, { bx, by }, u32({ 1, 1, 1, 0.9 * u * u * a }), 1.8 * s);
        end
    end
    local hx, hy = at(head);
    dl:AddCircleFilled({ hx, hy }, 4.5 * s, u32({ c[1], c[2], c[3], 0.45 * a }), 10);
    dl:AddCircleFilled({ hx, hy }, 2.2 * s, u32({ 1, 1, 1, a }), 8);
end
-- writing with a black edge
function TRF.NE.text(dl, x, y, t, c, a, o)
    c = c or C.text; a = a or 1; o = o or 1;
    local blk = u32({ 0, 0, 0, 0.9 * a });
    for k = 0, 7 do local an = k * math.pi / 4; dl:AddText({ x + math.cos(an) * o, y + math.sin(an) * o }, blk, t); end
    dl:AddText({ x, y }, u32({ c[1], c[2], c[3], a }), t);
end
-- italic serif capitals, the first letter of the title bigger, a metal sheen (the lower half greyer). Returns the width.
-- (English as it stands, in either language: the Japanese goes under it, as on ChadcoreMenu)
function TRF.NE.caps(dl, x, base, t, big, small, s, a, measure)
    local L = TRF.LANG;
    local was = L.live;
    L.live = false;
    a = a or 1;
    local cx, first = x, true;
    for word in tostring(t):upper():gmatch('%S+') do
        for _, p in ipairs({ { word:sub(1, 1), first and big or small * 1.12 }, { word:sub(2), small } }) do
            if p[1] ~= '' then
                local pushed = TRF.PH.font(fonts.ne or fonts.title, p[2]);
                local w = imgui.CalcTextSize(p[1]);
                if not measure then
                    local lh = imgui.GetTextLineHeight();
                    local ty = base - lh * 0.80;
                    for k = 0, 7 do local an = k * math.pi / 4; dl:AddText({ cx + math.cos(an) * 1.6 * s, ty + math.sin(an) * 1.6 * s + 1 * s }, u32({ 0, 0, 0, 0.9 * a }), p[1]); end
                    dl:AddText({ cx, ty }, u32({ 0.97, 0.97, 1, a }), p[1]);
                    pcall(function ()
                        dl:PushClipRect({ cx - 4 * s, ty + lh * 0.50 }, { cx + w + 6 * s, ty + lh * 1.2 }, true);
                        dl:AddText({ cx, ty }, u32({ 0.70, 0.72, 0.78, a }), p[1]);
                        dl:PopClipRect();
                    end);
                end
                if pushed then imgui.PopFont(); end
                cx = cx + w;
            end
        end
        cx = cx + small * 0.30;
        first = false;
    end
    L.live = was;
    return cx - small * 0.30 - x;
end
-- an icon: a number on the sheet (images\ne_icons.png: 14 in a row, 96 px each), or 'gear' / 'list' (drawn)
function TRF.NE.icon(dl, cx, cy, r, kind, s, c, a)
    c = c or C.acc; a = a or 1;
    local wht = u32({ 0.90, 0.92, 0.96, a });
    if type(kind) == 'number' then
        local sh = TRF.imageTex and TRF.imageTex('ne_icons.png');
        local R = r * 1.25;
        if sh and pcall(dl.AddImage, dl, sh.ptr, { cx - R, cy - R }, { cx + R, cy + R }, { kind * 96 / 2048, 0 }, { (kind + 1) * 96 / 2048, 0.75 }, u32({ 1, 1, 1, a })) then return; end
        kind = 'list';
    end
    if kind == 'gear' then
        for k = 0, 7 do
            local an = k * math.pi / 4;
            local ca, sa = math.cos(an), math.sin(an);
            local px, py = -sa, ca;
            local r0, r1, hw = r * 0.6, r * 1.02, r * 0.2;
            TRF.PH.q(dl, cx + ca * r0 + px * hw, cy + sa * r0 + py * hw, cx + ca * r1 + px * hw * 0.8, cy + sa * r1 + py * hw * 0.8,
               cx + ca * r1 - px * hw * 0.8, cy + sa * r1 - py * hw * 0.8, cx + ca * r0 - px * hw, cy + sa * r0 - py * hw, wht);
        end
        dl:AddCircleFilled({ cx, cy }, r * 0.74, wht, 24);
        dl:AddCircleFilled({ cx, cy }, r * 0.40, u32({ 0.05, 0.05, 0.07, a }), 20);
        dl:AddCircle({ cx, cy }, r * 0.30, u32({ c[1], c[2], c[3], a }), 20, 2 * s);
    else
        local w, h = r * 1.25, r * 0.30;
        for i = -1, 1 do dl:AddRectFilled({ cx - w * 0.35, cy + i * r * 0.52 - h / 2 }, { cx + w * 0.9, cy + i * r * 0.52 + h / 2 }, wht); end
        dl:AddTriangleFilled({ cx - w * 0.95, cy - r * 0.30 }, { cx - w * 0.55, cy }, { cx - w * 0.95, cy + r * 0.30 }, u32({ c[1], c[2], c[3], a }));
    end
end
-- The title (ChadcoreMenu's): a dark leaning bar in the neon frame, an icon box at its left, the name in serif
-- capitals, the Japanese under it, two stripes at its end, a spark running round. y: where the bar's foot sits
-- (less 6). Returns its width from x and the bar's top.
function TRF.NE.title(dl, x, y, t, s, c, icon, jp)
    local N = TRF.NE;
    c = c or C.acc;
    t = tostring(t or ''):upper();
    local jh = (jp and fonts.jp) and 9 * s or 0;
    local bh = 40 * s + jh;
    local bot = y + 6 * s;
    local top = bot - bh;
    local K = bh * 0.55;
    local nw = N.caps(dl, 0, 0, t, 32 * s, 24 * s, s, 1, true);
    local iw = 62 * s;
    local ix0 = x - 18 * s;
    local bx0 = ix0 + iw - 6 * s;
    local bx1 = bx0 + nw + 110 * s;
    local e, ek = 7 * s, 7 * s * 0.55;
    local I = { { ix0 + K + ek, top - e }, { ix0 + iw + K + ek, top - e }, { ix0 + iw - ek, bot + e }, { ix0 - ek, bot + e } };
    local B = { { bx0 + K, top }, { bx1 + K, top }, { bx1, bot }, { bx0, bot } };
    TRF.PH.clip(dl);
    N.frame(dl, { B }, s, c);
    N.frame(dl, { I }, s, c);
    for i = 0, 1 do                                              -- (two stripes at the right end)
        local sx = bx1 - 44 * s + i * 20 * s;
        TRF.PH.q(dl, sx + K * 0.86, top + 5 * s, sx + 12 * s + K * 0.86, top + 5 * s, sx + 12 * s + K * 0.14, bot - 5 * s, sx + K * 0.14, bot - 5 * s, u32({ c[1], c[2], c[3], 0.35 + 0.25 * i }));
    end
    dl:AddLine({ (bx0 + bx1) / 2 - 20 * s, bot + 2.6 * s }, { (bx0 + bx1) / 2 + 50 * s, bot + 2.6 * s }, u32({ 1, 1, 1, 0.55 }), 1.5 * s);
    N.icon(dl, ix0 + iw / 2 + K / 2, (top + bot) / 2, 15 * s, icon or 'list', s, c);
    N.caps(dl, bx0 + K + 14 * s, bot - 10 * s - jh, t, 32 * s, 24 * s, s);
    if jh > 0 then                                               -- (the Japanese, small, centred under the name)
        local L = TRF.LANG;
        local was = L.live;
        L.live = false;
        local pushed = TRF.PH.font(fonts.jp, 11 * s);
        local jx = bx0 + K * 0.3 + 14 * s + nw / 2 - imgui.CalcTextSize(jp) / 2;
        local jy = bot - 8 * s - jh;
        dl:AddText({ jx + 1, jy + 1 }, u32({ 0, 0, 0, 1 }), jp);
        dl:AddText({ jx, jy }, u32({ 0.92, 0.92, 0.95, 1 }), jp);
        if pushed then imgui.PopFont(); end
        L.live = was;
    end
    N.pulse(dl, B, s, c, 1, 0);
    N.pulse(dl, I, s, c, 0.8, 1.3);
    TRF.PH.unclip(dl);
    return bx1 + K - x, top - e;
end
-- A tab's Japanese name (from lang_jp.lua, read once even in English: it goes under the title)
function TRF.NE.jp(name)
    local N, L = TRF.NE, TRF.LANG;
    if N.JP[name] then return N.JP[name]; end
    if L.D == nil and not N.triedLang then N.triedLang = true; pcall(L.load); end
    local d = L.D and L.D.T;
    return d and (d[name] or (L.lc and L.lc[name:lower()])) or nil;
end
-- The panel: an upright dark slab in a glowing double line, its bottom-right corner cut
function TRF.NE.panel(dl, x0, y0, x1, y1, s, c, a, glow)
    local N = TRF.NE;
    c = c or C.acc; a = a or 1; glow = glow or 1;
    local n = 12 * s;
    local P = { { x0, y0 }, { x1, y0 }, { x1, y1 - n }, { x1 - n, y1 }, { x0, y1 } };
    TRF.PH.clip(dl);
    N.fill(dl, N.grow(P, 9 * s * glow), u32({ c[1], c[2], c[3], 0.10 * a * glow }));
    N.fill(dl, N.grow(P, 6 * s), u32({ c[1], c[2], c[3], 0.22 * a }));
    N.fill(dl, N.grow(P, 3 * s), u32({ math.min(1, c[1] + 0.1), math.min(1, c[2] + 0.1), math.min(1, c[3] + 0.1), a }));
    N.fill(dl, P, u32({ C.panel[1], C.panel[2], C.panel[3], config.transparent and 0.6 or 1 }));
    if TRF.BGI then pcall(TRF.BGI.draw, dl, x0, y0, x1 - x0, y1 - y0 - n, 0); end
    N.outline(dl, N.grow(P, -5 * s), u32({ c[1], c[2], c[3], 0.6 * a }), 1.2 * s);
    dl:AddLine({ x1 - (x1 - x0) * 0.25, y1 + 3 * s }, { x1 - n - 6 * s, y1 + 3 * s }, u32({ 1, 1, 1, 0.5 * a }), 1.4 * s);
    TRF.PH.unclip(dl);
end
-- The header: the page's title (icon box, Japanese under it), "VenGo" and the version beside it
function TRF.NE.header(dl, x0, y0, name)
    local N = TRF.NE;
    local w = N.title(dl, x0 + 18, y0 + 50, name, 0.92, nil, N.ICON[name], N.jp(name));
    local x = x0 + w + 26;
    local pushed = TRF.PH.font(fonts.ne or fonts.title, 26);
    local ven = imgui.CalcTextSize('Ven');
    local _, th = imgui.CalcTextSize('VenGo');
    local y = y0 + 30;
    N.text(dl, x, y, 'Ven', C.text, 1, 1.4);
    N.text(dl, x + ven, y, 'Go', C.acc, 1, 1.4);
    local gw = imgui.CalcTextSize('Go');
    if pushed then imgui.PopFont(); end
    local vs = 'v' .. tostring(addon.version or '');
    local _, vh = imgui.CalcTextSize(vs);
    dl:AddText({ x + ven + gw + 8, y + th - vh - 3 }, u32(C.muted), vs);
end
-- A menu row: leaning 0.42 of its height, a small tab in the accent before it. Picked: filled in the accent (bright
-- left, deeper right), a honeycomb over its right end, a double chevron, a glow and bright corner brackets.
function TRF.NE.row(dl, x0, y0, x1, y1, s, on, over, label)
    local N = TRF.NE;
    local c = C.acc;
    local h = y1 - y0;
    local K = h * 0.42;
    local cy = (y0 + y1) / 2;
    local w = 7 * s;
    TRF.PH.q(dl, x0 + K, y0, x0 + K + w, y0, x0 + w, y1, x0, y1, u32({ c[1] * 0.85, c[2] * 0.85, c[3] * 0.85, 1 }));
    TRF.PH.q(dl, x0 + K, y0, x0 + K + w, y0, x0 + K * 0.5 + w, cy, x0 + K * 0.5, cy, u32({ 1, 1, 1, 0.18 }));
    x0 = x0 + w + 4 * s;
    if on then
        TRF.PH.clip(dl);
        local P = { { x0 + K, y0 }, { x1 + K, y0 }, { x1, y1 }, { x0, y1 } };
        local pl = 0.8 + 0.2 * math.sin(os.clock() * 4);
        N.fill(dl, N.grow(P, 7 * s), u32({ c[1], c[2], c[3], 0.18 * pl }));
        N.fill(dl, N.grow(P, 4 * s), u32({ c[1], c[2], c[3], 0.38 * pl }));
        N.fill(dl, N.grow(P, 2 * s), u32({ math.min(1, c[1] + 0.25), math.min(1, c[2] + 0.25), math.min(1, c[3] + 0.25), 1 }));
        for j = 0, 9 do
            local u0, u1 = j / 10, (j + 1) / 10;
            local f = 0.82 - 0.42 * (u0 + u1) / 2;
            local xa, xb = x0 + (x1 - x0) * u0, x0 + (x1 - x0) * u1 + 0.6;
            TRF.PH.q(dl, xa + K, y0, xb + K, y0, xb, y1, xa, y1, u32({ c[1] * f + 0.02, c[2] * f + 0.02, c[3] * f + 0.03, 1 }));
        end
        TRF.PH.q(dl, x0 + K, y0, x1 + K, y0, x1 + K * 0.6, y0 + h * 0.4, x0 + K * 0.6, y0 + h * 0.4, u32({ 1, 1, 1, 0.10 }));
        TRF.PH.q(dl, x0 + K * 0.35, y0 + h * 0.65, x1 + K * 0.35, y0 + h * 0.65, x1, y1, x0, y1, u32({ 0, 0, 0, 0.22 }));
        pcall(function ()                                         -- (the honeycomb)
            local hx0 = x0 + (x1 - x0) * 0.55;
            dl:PushClipRect({ hx0, y0 + 1 }, { x1 + K, y1 - 1 }, true);
            local r = h * 0.2;
            local dx, dy = r * 1.732, r * 1.5;
            local rw, yy = 0, y0 - r;
            while yy < y1 + r do
                local xx = hx0 + ((rw % 2 == 1) and dx / 2 or 0);
                while xx < x1 + K + dx do
                    local fade = math.max(0, math.min(1, (xx - hx0) / ((x1 - hx0) * 0.6)));
                    local hc = u32({ 1, 0.85, 0.85, 0.22 * fade });
                    for k = 0, 2 do
                        local a0, a1 = math.rad(30 + k * 60), math.rad(90 + k * 60);
                        dl:AddLine({ xx + math.cos(a0) * r, yy + math.sin(a0) * r }, { xx + math.cos(a1) * r, yy + math.sin(a1) * r }, hc, 1 * s);
                    end
                    xx = xx + dx;
                end
                yy = yy + dy; rw = rw + 1;
            end
            dl:PopClipRect();
        end);
        dl:AddLine({ x0 + K + (x1 - x0) * 0.2, y0 - 2 * s }, { x0 + K + (x1 - x0) * 0.55, y0 - 2 * s }, u32({ 1, 1, 1, 0.65 }), 1.4 * s);
        local bc, B = u32({ 1, 0.9, 0.9, 1 }), 9 * s;
        dl:AddLine({ x1 + K + 5 * s - B, y0 - 5 * s }, { x1 + K + 5 * s, y0 - 5 * s }, bc, 1.6 * s);
        dl:AddLine({ x1 + K + 5 * s, y0 - 5 * s }, { x1 + K + 5 * s, y0 - 5 * s + B }, bc, 1.6 * s);
        dl:AddLine({ x1 + 3 * s - B, y1 + 5 * s }, { x1 + 3 * s, y1 + 5 * s }, bc, 1.6 * s);
        dl:AddLine({ x0 - 3 * s, y1 + 5 * s }, { x0 - 3 * s + B, y1 + 5 * s }, bc, 1.6 * s);
        local bob = math.sin(os.clock() * 5) * 1.5 * s;
        for k = 0, 1 do
            local vx = x1 - 18 * s + k * 7 * s + bob;
            dl:AddLine({ vx - 4 * s, cy - 6 * s }, { vx + 2 * s, cy }, u32({ 1, 1, 1, 1 }), 2.6 * s);
            dl:AddLine({ vx + 2 * s, cy }, { vx - 4 * s, cy + 6 * s }, u32({ 1, 1, 1, 1 }), 2.6 * s);
        end
        TRF.PH.unclip(dl);
    else
        local st = over and { 0.17, 0.17, 0.19 } or N.STRIP;
        TRF.PH.q(dl, x0 + K, y0, x1 + K, y0, x1, y1, x0, y1, u32({ st[1], st[2], st[3], 0.96 }));
        TRF.PH.q(dl, x0 + K, y0, x1 + K, y0, x1 + K * 0.5, cy, x0 + K * 0.5, cy, u32({ 1, 1, 1, 0.045 }));
        TRF.PH.ql(dl, x0 + K, y0, x1 + K, y0, x1, y1, x0, y1, u32({ 0.62, 0.60, 0.62, 0.55 }), 1 * s);
        local vx = x1 - 12 * s;
        dl:AddLine({ vx - 3.5 * s, cy - 5 * s }, { vx + 1.5 * s, cy }, u32({ 0.85, 0.85, 0.9, 0.9 }), 2 * s);
        dl:AddLine({ vx + 1.5 * s, cy }, { vx - 3.5 * s, cy + 5 * s }, u32({ 0.85, 0.85, 0.9, 0.9 }), 2 * s);
    end
    if label then
        local pushed = TRF.PH.font(fonts.ne or fonts.title, 17 * s);
        N.text(dl, x0 + K + 8 * s, cy - imgui.GetTextLineHeight() / 2, label, C.text, 1, 1);
        if pushed then imgui.PopFont(); end
    end
end
function TRF.NE.sideItem(dl, k, x0, y, sw, ih, on, over, label)
    TRF.NE.row(dl, x0 - 4, y + 1, x0 + sw - 18, y + ih - 1, 1, on, over, label);
end
-- A button: the main big one a picked row (filled in the accent, glowing); a small main one dark in the neon line;
-- the quiet ones a dark strip with a pale line
function TRF.NE.button(dl, x, y, w, h, name, lw, lh, sp, quiet, small, hov, act)
    local N = TRF.NE;
    local c = C.acc;
    local K = math.min(h * 0.42, 9);
    local P = { { x + K, y }, { x + w, y }, { x + w - K, y + h }, { x, y + h } };
    if not quiet and not small then
        local pl = (hov or act) and (0.85 + 0.15 * math.sin(os.clock() * 5)) or 0.7;
        N.fill(dl, N.grow(P, 5), u32({ c[1], c[2], c[3], 0.30 * pl }));
        N.fill(dl, N.grow(P, 2), u32({ math.min(1, c[1] + 0.25), math.min(1, c[2] + 0.25), math.min(1, c[3] + 0.25), 1 }));
        local f = act and 0.55 or 0.78;
        N.fill(dl, P, u32({ c[1] * f + 0.02, c[2] * f + 0.02, c[3] * f + 0.03, 1 }));
        TRF.PH.q(dl, x + K, y, x + w, y, x + w - K * 0.6, y + h * 0.42, x + K * 0.4, y + h * 0.42, u32({ 1, 1, 1, 0.12 }));
    elseif not quiet then
        N.fill(dl, N.grow(P, 1.6), u32({ math.min(1, c[1] + 0.15), math.min(1, c[2] + 0.15), math.min(1, c[3] + 0.15), hov and 1 or 0.8 }));
        N.fill(dl, P, u32(act and { 0.16, 0.15, 0.18, 1 } or (hov and { 0.12, 0.11, 0.14, 1 } or { 0.06, 0.06, 0.075, 1 })));
        if hov then N.fill(dl, N.grow(P, 4), u32({ c[1], c[2], c[3], 0.18 })); end
    else
        local st = act and { 0.22, 0.22, 0.25 } or (hov and { 0.16, 0.16, 0.18 } or N.STRIP);
        N.fill(dl, P, u32({ st[1], st[2], st[3], 0.96 }));
        TRF.PH.ql(dl, P[1][1], P[1][2], P[2][1], P[2][2], P[3][1], P[3][2], P[4][1], P[4][2], u32({ 0.62, 0.60, 0.62, hov and 0.9 or 0.55 }), 1);
    end
    if small then imgui.SetWindowFontScale(0.82); end
    TRF.spaced(dl, x + (w - lw) / 2, y + (h - lh) / 2, name, u32(C.text), sp);
    if small then imgui.SetWindowFontScale(1); end
end
-- The VNM alert's panel: the neon slab, its glow pulsing in the alert's colour (gold for a starred VNM)
function TRF.NE.alertFrame(dl, x, y, w, h, gc, pulse)
    TRF.NE.panel(dl, x, y, x + w, y + h, 1, gc, 1, 0.8 + 0.6 * pulse);
end
-- A section's name: a black box with a thin line in the accent, its name in serif, a fading line after it
function TRF.NE.section(dl, x0, y0, text)
    local N = TRF.NE;
    local t = text:upper();
    local pushed = TRF.PH.font(fonts.ne or fonts.title, 17);
    local w = imgui.CalcTextSize(t);
    local lh = imgui.GetTextLineHeight();
    local x1, y1 = x0 + w + 30, y0 + lh + 6;
    dl:AddRectFilled({ x0, y0 }, { x1, y1 }, u32({ 0.02, 0.02, 0.025, 1 }));
    dl:AddRect({ x0, y0 }, { x1, y1 }, N.col(0.55), 0, 0, 1.1);
    dl:AddRectFilled({ x0, y0 }, { x0 + 4, y1 }, N.col(0.9));
    N.text(dl, x0 + 14, y0 + 3, t, C.text, 1, 1);
    if pushed then imgui.PopFont(); end
    pcall(function ()
        dl:AddRectFilledMultiColor({ x1 + 8, y0 + (y1 - y0) / 2 }, { x0 + ROW_W, y0 + (y1 - y0) / 2 + 1.5 },
            N.col(0.55), N.col(0), N.col(0), N.col(0.55));
    end);
    return y1 - y0 + 4;
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
    local L = TRF.LANG;
    local was = L.live;
    if was then                                                    -- (Japanese: the whole line first, closer letters)
        str = L.tr(str);
        if str:find('[\128-\255]') then gap = gap * 0.25; end
        L.live = false;
    end
    local cx = x;
    for ch in str:gmatch('[%z\1-\127\194-\244][\128-\191]*') do   -- (a letter at a time, UTF-8 ones whole)
        dl:AddText({ cx, y }, col, ch);
        cx = cx + imgui.CalcTextSize(ch) + gap;
    end
    L.live = was;
    return cx - x - gap;
end
TRF.spaced = spaced;
local function spacedW(str, gap)
    local L = TRF.LANG;
    local was = L.live;
    if was then
        str = L.tr(str);
        if str:find('[\128-\255]') then gap = gap * 0.25; end
        L.live = false;
    end
    local w = 0;
    for ch in str:gmatch('[%z\1-\127\194-\244][\128-\191]*') do w = w + imgui.CalcTextSize(ch) + gap; end
    L.live = was;
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
    if TRF.PH and TRF.PH.on() then imgui.Dummy({ ROW_W, TRF.PH.section(dl, x0 + 2, y0, text) }); return; end
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
    if TRF.PH and TRF.PH.on() then return TRF.PH.button(dl, x, y, w, h, name, lw, lh, sp, quiet, small, hov, act) or clicked; end
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
TRF.imageTex = imageTex;

-- The panel, ChadcoreMenu style: a dark violet-grey card with small rounded
-- corners, a thin lavender edge, and a pink-to-violet line across the top
local function frame(dl, x, y, w, h)
    local r = 10;
    x, y, w, h = x + 4, y + 4, w - 8, h - 8;
    if TRF.PH.on() then
        TRF.PH.frame(dl, x, y, w, h);
        dl:AddLine({ x + SW - 8, y + 70 }, { x + SW - 8, y + h - 16 }, u32({ 1, 1, 1, 0.08 }), 1);
        return;
    end
    local clear = config.transparent;
    dl:AddRectFilled({ x, y }, { x + w, y + h }, u32({ C.panel[1], C.panel[2], C.panel[3], clear and 0.45 or 0.97 }), r);
    if TRF.BGI then pcall(TRF.BGI.draw, dl, x, y, w, h, r); end      -- (your own picture, if you chose one)
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
    if TRF.PH.on() then return TRF.PH.header(dl, x0, y0, tabName); end
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
local GROUPS = { [9] = true, [14] = true };   -- (faint lines before the collections and before SETTINGS)

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
        if TRF.PH.on() then
            TRF.PH.sideItem(dl, k, x0, y, sw, ih, on, over, (n == 'CATSEYEXI') and 'CatsEyeXI' or n);
        elseif on then
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
        local label = (n == 'CATSEYEXI') and 'CatsEyeXI' or (n:sub(1, 1) .. n:sub(2):lower());
        if not TRF.PH.on() then
            if not on then dl:AddCircleFilled({ x0 + 10, y + ih / 2 + 1 }, 1.6, u32(C.muted), 8); end
            dl:AddText({ x0 + (on and 14 or 18), y + (ih - nh) / 2 }, u32(on and { 1, 1, 1, 1 } or (over and { 1, 1, 1, 1 } or C.text)), label);
        end
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
    pcall(TRF.LANG.toggle, dl, xClear - 58 - 12, by, bs);     -- (EN / JP)
    -- see-through on / off
    if iconButton(dl, '##vengo_clear', xClear, by, bs, { C.acc[1], C.acc[2], C.acc[3], 0.22 },
            config.transparent and 'Solid window' or 'See-through window', function (cx, cy, r, col)
                dl:AddCircle({ cx, cy }, r * 1.25, col, 20, 1.4);
                if not config.transparent then dl:AddCircleFilled({ cx, cy }, r * 0.7, col, 20); end
            end) then
        config.transparent = not config.transparent;
        saveSettings();
    end
    -- the venture bar: just the top venture, in one row
    if iconButton(dl, '##vengo_min', xMin, by, bs, { C.acc[1], C.acc[2], C.acc[3], 0.22 },
            'Venture bar: just the highest venture, in one row (its open button brings VenGo back)', function (cx, cy, r, col)
                dl:AddLine({ cx - r, cy + r * 0.6 }, { cx + r, cy + r * 0.6 }, col, 1.8);
            end) then
        config.strip, config.minimized = true, false;
        saveSettings();
    end
    -- the VenGo orb
    if iconButton(dl, '##vengo_x', xClose, by, bs, { C.hp[1], C.hp[2], C.hp[3], 0.30 },
            'Shrink to the VenGo orb (click it to open VenGo again; /vengo hides everything)', function (cx, cy, r, col)
                dl:AddLine({ cx - r, cy - r }, { cx + r, cy + r }, col, 1.6);
                dl:AddLine({ cx - r, cy + r }, { cx + r, cy - r }, col, 1.6);
            end) then
        config.minimized, config.strip = true, false;
        saveSettings();
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
    local crest = (v.crest and v.crest ~= '') and v.crest or TRF.crestOf(v.zone_name);
    if crest and TRF.CRESTC[crest] then                           -- (the crest it drops, in its armour set's colour)
        if v.drops and v.drops ~= '' then imgui.SameLine(0, 8); else imgui.SameLine(x0 + at.drops); end
        imgui.TextColored(TRF.CRESTC[crest], crest);
        tip(crest .. ' Crest');
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
        imgui.TextColored(C.muted, TRF.trailShowing(pick) and 'STOP hides the GPS to' or 'GO shows the GPS to');
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
        local crest = (ALERT.v.crest and ALERT.v.crest ~= '') and ALERT.v.crest or TRF.crestOf(ALERT.v.zone_name);
        if crest and TRF.CRESTC[crest] then
            imgui.SameLine(0, 10);
            imgui.TextColored(TRF.CRESTC[crest], crest .. ' Crest');
        end
    end
    if LASTWARP and os.time() - LASTWARP.at < 90 and LASTWARP.list[LASTWARP.i + 1] then
        if button('NOT UNLOCKED? TRY NEXT CLOSEST##vengo_next', { 0, 0 }, false, true) then warpNext(); end
    end

    TRF.PT.block('ventures', 'Venture points', 4);

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

-- The venture bar (the _ button): one row, the venture furthest along right now (the one being announced
-- first), with its star and GO button, and a button at the end to open VenGo again. Drag it by its edges.
TRF.drawStrip = function()
    local top = nil;
    for _, v in ipairs(vdata.exp or {}) do
        local p = (ALERT and ALERT.v == v) and 1000 or (v.progress or 0);
        local tp = top and ((ALERT and ALERT.v == top) and 1000 or (top.progress or 0)) or -1;
        if p > tp or (p == tp and (v.tier or 0) > (top.tier or 0)) then top = v; end
    end
    local nc, nv = pushTheme();
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 12, 7 });
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 8, 4 });
    imgui.PushStyleColor(ImGuiCol_WindowBg, { C.pbg[1], C.pbg[2], C.pbg[3], config.transparent and 0.62 or 0.92 });
    imgui.PushStyleColor(ImGuiCol_Border, { 1, 1, 1, 0.08 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 1);
    imgui.SetNextWindowPos({ 240, 120 }, ImGuiCond_FirstUseEver);
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse, ImGuiWindowFlags_NoFocusOnAppearing);
    local pushed = pushFont(fonts.panel, 16);
    if imgui.Begin('VenGo bar##vengo_strip', { true }, flags) then pcall(function ()
        local dl = imgui.GetWindowDrawList();
        local wx, wy = imgui.GetWindowPos();
        local ww = imgui.GetWindowSize();
        pcall(function ()                                         -- (the pink-to-violet line along the top)
            dl:AddRectFilledMultiColor({ wx + 10, wy }, { wx + ww - 10, wy + 2 }, u32({ NEON2[1], NEON2[2], NEON2[3], 0.9 }),
                u32({ C.mp2[1], C.mp2[2], C.mp2[3], 0.9 }), u32({ C.mp2[1], C.mp2[2], C.mp2[3], 0.9 }), u32({ NEON2[1], NEON2[2], NEON2[3], 0.9 }));
        end);
        if top == nil then
            imgui.AlignTextToFramePadding();
            imgui.TextColored(C.muted, 'No ventures yet');
        else
            ventureRow(top, zone(), measureCols({ top }, true), true);
        end
        imgui.SameLine(0, 14);
        local bx, by = imgui.GetCursorScreenPos();
        local bs = imgui.GetFrameHeight();
        if iconButton(dl, '##vengo_strip_open', bx, by, bs, { C.acc[1], C.acc[2], C.acc[3], 0.22 }, 'Open VenGo', function (cx, cy, r, col)
                    dl:AddRect({ cx - r * 1.1, cy - r * 0.9 }, { cx + r * 1.1, cy + r * 0.9 }, col, 2, C.rall, 1.6);
                    dl:AddLine({ cx - r * 1.1, cy - r * 0.35 }, { cx + r * 1.1, cy - r * 0.35 }, col, 1.4);
                end) then
            config.strip = false;
            saveSettings();
        end
    end); end
    imgui.End();
    if pushed then imgui.PopFont(); end
    imgui.PopStyleVar(3);
    imgui.PopStyleColor(2);
    imgui.PopStyleVar(nv);
    imgui.PopStyleColor(nc);
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
    { 'Noto Sans CJK', 'the Japanese (Adobe and Google, SIL Open Font License, fonts\\OFL-NotoSansCJK.txt)' },
    { 'Phantom style', 'the red, black and white slanted look, from ChadcoreMenu; its fonts are Inter Black (Rasmus Andersson, SIL Open Font License, fonts\\OFL-Inter.txt) and TeX Gyre Heros Cn Bold (GUST Font License, fonts\\GUST-texgyreheroscn.txt); the Japanese in its titles is Noto Sans CJK (Google, SIL Open Font License)' },
    { 'The alba, Kokoro and sherpa-onnx voices', 'the spoken VNM alerts: the Scottish (alba, University of Edinburgh, CC BY 4.0), British and Japanese (Kokoro by hexgrad, Apache 2.0) voices (LICENSE-voices.txt)' },
    { 'Dewin (Goldilox)', 'the DAILIES tab: the goblin and Palalumin dailies and how to read them from chat (MIT licence, LICENSE-goldilox.txt)' },
    { 'Loxley (Trove)', 'the VNM Armor, Ultimates, Lumoria and Odious Codex data, and how to ask the CatsEyeXI server for currency, points and Lumoria progress (MIT licence, LICENSE-trove.txt)' },
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
    if TRAIL.zone_ ~= z then TRAIL.zone_, TRAIL.stopped, TRAIL.forced, TRAIL.manual = z, nil, nil, nil; end   -- (a new zone: GO / STOP start fresh)
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
    -- On its own only once the VNM is at 100% (or announced); GO pressed in the zone shows it any time
    if config.trail_full ~= false and (v.progress or 0) < 100 and not (ALERT and ALERT.v == v) and TRAIL.manual ~= v.key then return nil; end
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
    if not config.website or S == nil or S.currentObjective == nil then TRF.noData('the Summit'); TRF.PT.block('summit', 'Summit points', 4); return; end
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
    TRF.PT.block('summit', 'Summit points', 4);
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

-- One piece (style B): faded grey when you don't have it; green tile and check when owned, gold tile and check when
-- completed; a cyan bar under it when it drops from today's ventures, a pulsing pink glow and bar when its VNM is up
TRF.AR.GREEN, TRF.AR.GOLD = { 0.48, 0.92, 0.58 }, { 0.96, 0.76, 0.32 };
TRF.AR.CYAN, TRF.AR.PINK = { 0.31, 0.86, 0.92 }, { 1.00, 0.42, 0.72 };
function TRF.AR.check(dl, x, y, r, col)                          -- (a filled circle with a dark tick)
    dl:AddCircleFilled({ x, y }, r, u32({ col[1], col[2], col[3], 1 }), 16);
    local k = { col[1] * 0.15, col[2] * 0.15, col[3] * 0.15, 1 };
    dl:AddLine({ x - r * 0.45, y + r * 0.02 }, { x - r * 0.1, y + r * 0.38 }, u32(k), math.max(1.5, r * 0.28));
    dl:AddLine({ x - r * 0.1, y + r * 0.38 }, { x + r * 0.5, y - r * 0.35 }, u32(k), math.max(1.5, r * 0.28));
end
function TRF.AR.piece(dl, id, x, y, sz, have, hot, over, now)
    local A = TRF.AR;
    local P_ = A.PINK;
    local pulse = (hot == 2) and (0.55 + 0.45 * math.abs(math.sin(now * 3))) or 0;
    if hot == 2 then                                             -- (the glow, behind the cell)
        for i = 3, 1, -1 do
            local o = i * 3;
            dl:AddRectFilled({ x - o, y - o }, { x + sz + o, y + sz + o }, u32({ P_[1], P_[2], P_[3], (0.30 - i * 0.07) * pulse }), 6 + o);
        end
    end
    TRF.card(dl, x, y, sz, sz, nil, over, 6);
    local c_ = (have == 2) and A.GOLD or A.GREEN;
    if have > 0 then
        dl:AddRectFilled({ x, y }, { x + sz, y + sz }, u32({ c_[1], c_[2], c_[3], have == 2 and 0.16 or 0.10 }), 6);
        dl:AddRect({ x, y }, { x + sz, y + sz }, u32({ c_[1], c_[2], c_[3], have == 2 and 0.85 or 0.55 }), 6, C.rall, have == 2 and 1.5 or 1);
    end
    local ic = itemIcon(id);
    if ic then
        local tint = (have > 0) and { 1, 1, 1, 1 } or { 0.62, 0.62, 0.66, 0.38 };
        pcall(dl.AddImage, dl, ic.ptr, { x + 4, y + 4 }, { x + sz - 4, y + sz - 4 }, { 0, 0 }, { 1, 1 }, u32(tint));
    else
        dl:AddRectFilled({ x + 4, y + 4 }, { x + sz - 4, y + sz - 4 }, u32({ 1, 1, 1, 0.05 }), 3);
    end
    if hot == 2 then dl:AddRect({ x, y }, { x + sz, y + sz }, u32({ P_[1], P_[2], P_[3], 0.7 + 0.3 * pulse }), 6, C.rall, 2); end
    if have > 0 then A.check(dl, x + 8, y + sz - 8, 6, c_); end
    if hot == 1 or hot == 2 then
        local b = (hot == 2) and P_ or A.CYAN;
        dl:AddRectFilled({ x + 6, y + sz + 3 }, { x + sz - 6, y + sz + 6 }, u32({ b[1], b[2], b[3], hot == 2 and (0.7 + 0.3 * pulse) or 0.95 }), 2);
    end
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
    local rg = 10;                                               -- (between rows: room for the bar under a piece)
    local cell = math.floor(math.max(30, math.min(46, (ROW_W - labelW - setGap * 4 - 5 * (pad * 2 + tg * 2)) / 15)));
    local setW = cell * 3 + tg * 2 + pad * 2;
    local headH = lh * 2 + 14;
    local gridH = 5 * cell + 4 * rg + 4;
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
        local ry = gy + (r - 1) * (cell + rg);
        spaced(dl, x0, ry + (cell - lh) / 2, TRF.AR.SLOT_LABELS[r]:upper(), u32(C.label), 1);
        for si, set in ipairs(TRF.AR.SETS) do
            local complete = owned[set.final[sl]] ~= nil;
            for t_ = 1, 3 do
                local id = set.tiers[t_][sl];
                local cx = cellX(si, t_);
                local over = mx_ >= cx and mx_ < cx + cell and my_ >= ry and my_ < ry + cell;
                TRF.AR.piece(dl, id, cx, ry, cell, complete and 2 or (owned[id] and 1 or 0), hot[id], over, now);
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
        if H_.complete then imgui.TextColored(C.gold, '  Completed: ' .. TRF.AR.name(H_.set.final[H_.slot]));
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
    local function key(x, kind, text)
        local A = TRF.AR;
        if kind == 'own' or kind == 'done' then A.check(dl, x + 7, ly + lh / 2 + 1, 6.5, kind == 'own' and A.GREEN or A.GOLD);
        else
            local c_ = kind == 'drop' and A.CYAN or A.PINK;
            dl:AddRectFilled({ x, ly + lh / 2 - 1 }, { x + 16, ly + lh / 2 + 3 }, u32({ c_[1], c_[2], c_[3], 1 }), 2);
        end
        dl:AddText({ x + 22, ly + 1 }, u32(C.muted), text);
        return x + 22 + imgui.CalcTextSize(text) + 22;
    end
    local kx = key(lx, 'own', 'Owned');
    kx = key(kx, 'done', 'Completed');
    kx = key(kx, 'drop', 'Drops from today\'s ventures');
    key(kx, 'up', 'VNM up (glows)');
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
    if TRF.PT and TRF.PT.pending and now - TRF.PT.pending < 5 then return; end
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
    elseif action == 7 and TRF.PT.pending then                  -- (a points line)
        local P = TRF.PT;
        P.buf = P.buf or {};
        local label = str(0x1C, 23);
        if label ~= '' then P.buf[#P.buf + 1] = { group = str(0x08, 19), label = label, value = i32(0x34) }; end
    elseif action == 0 and TRF.PT.pending then                  -- (the server starts the list again)
        TRF.PT.buf = {};
    elseif action == 2 and TRF.PT.pending then                  -- (the end of the points)
        local P = TRF.PT;
        P.list, P.buf, P.at, P.pending = P.buf or {}, nil, os.clock(), nil;
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

-- Points (asked of the server the way Trove's Points tab by Loxley asks, MIT licence): the server sends
-- them grouped (CatsEyeXI, Dailies, Ventures, Summit); each group is shown on its own tab
TRF.PT = { list = nil, buf = nil, at = nil, pending = nil, triedAt = nil,
    COLS = { catseyexi = { 0.55, 0.75, 1.00 }, dailies = { 0.76, 0.62, 1.00 }, ventures = { 0.50, 0.88, 0.50 }, summit = { 1.00, 0.78, 0.35 } } };
function TRF.PT.ask(force)
    local P, T = TRF.PT, TRF.TV;
    local now = os.clock();
    if P.pending and now - P.pending < 5 then return; end
    if T.curPending and now - T.curPending < 5 then return; end  -- (one list at a time: both end the same way)
    if not force and P.at and now - P.at < 60 then return; end
    if not force and P.at == nil and P.triedAt and now - P.triedAt < 15 then return; end
    P.pending, P.triedAt, P.buf = now, now, {};
    T.ask(8);                                                    -- (GET_POINTS)
end
-- One group's points: { { label, value }, ... } (nil until the server has answered)
function TRF.PT.group(name)
    local P = TRF.PT;
    if P.list == nil then return nil; end
    local out = {};
    for _, e in ipairs(P.list) do if e.group:lower() == name then out[#out + 1] = e; end end
    return out;
end
-- The groups that aren't shown on a tab of their own (they go on the CATSEYEXI tab)
function TRF.PT.others()
    local P = TRF.PT;
    local seen, order = {}, {};
    for _, e in ipairs(P.list or {}) do
        local g = e.group:lower();
        if g ~= 'catseyexi' and g ~= 'dailies' and g ~= 'ventures' and g ~= 'summit' and not seen[g] then
            seen[g] = true; order[#order + 1] = e.group;
        end
    end
    return order;
end
-- Cards in a row: the name small and dim, the number big under it
function TRF.PT.cards(list, col, per)
    local dl = imgui.GetWindowDrawList();
    local lh = imgui.GetTextLineHeight();
    local x0, y0 = imgui.GetCursorScreenPos();
    per = math.max(1, math.min(per or 4, #list));
    local gap = 8;
    local cw = (ROW_W - (per - 1) * gap) / per;
    local ch = lh + 46;                                          -- (the name, then the number in the big font)
    local mx, my = imgui.GetMousePos();
    for i, e in ipairs(list) do
        local cx, cy = x0 + ((i - 1) % per) * (cw + gap), y0 + math.floor((i - 1) / per) * (ch + gap);
        local hov = imgui.IsWindowHovered() and mx >= cx and mx < cx + cw and my >= cy and my < cy + ch;
        TRF.card(dl, cx, cy, cw, ch, nil, hov, 8);
        dl:AddRectFilled({ cx + 1, cy + 8 }, { cx + 3, cy + ch - 8 }, u32({ col[1], col[2], col[3], 0.85 }), 1);
        dl:AddText({ cx + 14, cy + 7 }, u32(C.muted), e.label);
        local big = pushFont(fonts.big, 22);
        dl:AddText({ cx + 14, cy + lh + 9 }, u32({ math.min(1, col[1] * 0.6 + 0.4), math.min(1, col[2] * 0.6 + 0.4), math.min(1, col[3] * 0.6 + 0.4), 1 }), TRF.num(e.value));
        if big then imgui.PopFont(); end
    end
    local rows = math.ceil(#list / per);
    imgui.Dummy({ ROW_W, rows * ch + (rows - 1) * gap + 2 });
end
-- A group as a block on its tab: header, then the cards (or a line saying they're on the way)
function TRF.PT.block(name, title, per)
    local P = TRF.PT;
    P.ask(false);
    local list = P.group(name);
    local col = P.COLS[name] or { 0.76, 0.70, 0.98 };
    TRF.header(imgui.GetWindowDrawList(), title, col, list and #list > 0 and TRF.num(#list) or nil);
    if list == nil then
        hint(P.pending and 'Asking the CatsEyeXI server for your points...' or 'Your points haven\'t come back from the server yet.');
    elseif #list == 0 then
        hint('The server sent no ' .. title:lower() .. '.');
    else
        P.cards(list, col, per);
    end
end

------------------------------------------------------------------------
-- SPARK VENDOR: your Sparks of Eminence, what they'd buy in Acheron Shields and what those sell for, and BUY / SELL.
-- BUY: stand by a Sparks NPC (Isakoth, Rolandienne, Fhelm Jobeizat or Eternal Flame). VenGo talks to them, keeps
-- the menu shut, buys one shield at a time (each checked by the sparks the server says are left) and closes the menu.
-- SELL: sends "/sellit Acheron Shield" (the SellIt addon sells them at the next NPC shop you open).
-- (The menu's numbers are the server's own, from CatsEyeXI's source: Equipment Lv.71-98, entry 41, 2,755 sparks.)
------------------------------------------------------------------------
TRF.SV = { ID = 12385, COST = 2755, PRICE = 27550, OPTION = 9 + 41 * 65536,
    NPCS = { ['isakoth'] = 26, ['rolandienne'] = 995, ['fhelm jobeizat'] = 850, ['eternal flame'] = 5081 },
    sparks = nil, sparksAt = nil, left = nil, priceSeen = false, job = nil, status = nil, statusCol = nil, askAt = -1e9,
    inv = { at = -1, have = 0, free = 0, gil = 0, slots = {} } };
function TRF.SV.say(t, bad) TRF.SV.status, TRF.SV.statusCol = t, bad and { 1, 0.45, 0.45, 1 } or nil; msg(t); end
-- A packet to the server: the header (its number and size), then the fields
function TRF.SV.send(id, size, fields)
    local p = {};
    for i = 1, size do p[i] = 0; end
    p[1], p[2] = id % 256, math.floor(size / 4) * 2 + math.floor(id / 256) % 2;
    for _, f in ipairs(fields) do                                 -- { offset, value, bytes }
        local v = f[2] % (2 ^ (8 * f[3]));
        for b = 0, f[3] - 1 do p[f[1] + b + 1] = math.floor(v / (2 ^ (8 * b))) % 256; end
    end
    return pcall(function () AshitaCore:GetPacketManager():AddOutgoingPacket(id, p); end);
end
-- Your bag: Acheron Shields (and their slots), free space, gil
function TRF.SV.scan(force)
    local I = TRF.SV.inv;
    if not force and os.clock() - I.at < 0.5 then return I; end
    I.at = os.clock();
    pcall(function ()
        local inv = mm():GetInventory();
        local max = inv:GetContainerCountMax(0) or 0;
        local used, have, slots = 0, 0, {};
        for i = 1, max do
            local it = inv:GetContainerItem(0, i);
            local id = it and it.Id or 0;
            if id ~= 0 and id ~= 65535 then
                used = used + 1;
                if id == TRF.SV.ID then
                    have = have + 1;
                    if (it.Flags or 0) == 0 then slots[#slots + 1] = i; end   -- (not equipped, not in a bazaar)
                end
            end
        end
        local g = inv:GetContainerItem(0, 0);
        I.have, I.free, I.slots, I.gil = have, math.max(0, max - used), slots, (g and g.Count) or 0;
    end);
    return I;
end
-- How many shields you could buy now: sparks, the week's limit (when the server has said it) and bag space
function TRF.SV.canBuy()
    local S = TRF.SV;
    local n = math.floor((S.sparks or 0) / S.COST);
    if S.left and S.left >= 0 and S.left < 10000000 then n = math.min(n, math.floor(S.left / S.COST)); end
    return math.max(0, n), math.max(0, math.min(n, S.scan().free));
end
-- The Sparks NPC beside you: index, server id, name, distance
function TRF.SV.npc()
    local x, y = pos();
    if x == nil then return nil; end
    local best = nil;
    pcall(function ()
        local ent = mm():GetEntity();
        for i = 1, 1023 do
            local nm = ent:GetName(i);
            if nm and nm ~= '' and TRF.SV.NPCS[nm:lower()] then
                local ex, ey = entPos(i);
                if ex then
                    local d = dist2d(x, y, ex, ey);
                    if best == nil or d < best.d then best = { idx = i, id = ent:GetServerId(i), name = nm, d = d, ev = TRF.SV.NPCS[nm:lower()] }; end
                end
            end
        end
    end);
    return best;
end
-- BUY: talk to the NPC (the menu kept shut), then one shield at a time
function TRF.SV.buy(n)
    local S = TRF.SV;
    if S.job then return; end
    local np = S.npc();
    if np == nil then S.say('No Sparks NPC here: go to Isakoth (Bastok Markets), Rolandienne (Southern San d\'Oria), Fhelm Jobeizat (Windurst Woods) or Eternal Flame (Western Adoulin).', true); return; end
    if np.d > 5.5 then S.say(('Walk up to %s (%.0f yalms away), then press BUY.'):fmt(np.name, np.d), true); return; end
    if n < 1 then S.say('Not enough sparks or bag space for an Acheron Shield.', true); return; end
    S.job = { kind = 'buy', npc = np, want = n, got = 0, stage = 'talk', t = os.clock() };
    S.status, S.statusCol = ('Talking to %s...'):fmt(np.name), nil;
    S.send(0x1A, 0x1C, { { 0x04, np.id, 4 }, { 0x08, np.idx, 2 }, { 0x0A, 0, 2 } });
end
-- SELL: hands it to the SellIt addon ("/sellit Acheron Shield"), which sells them at the next NPC shop you open
function TRF.SV.sell()
    local S = TRF.SV;
    if S.job then return; end
    local I = S.scan(true);
    if #I.slots == 0 then S.say('No Acheron Shields in your bag to sell.', true); return; end
    local ok = pcall(function () AshitaCore:GetChatManager():QueueCommand(1, '/sellit Acheron Shield'); end);
    if ok then S.say('Sent /sellit Acheron Shield: talk to an NPC shop and SellIt sells them.');
    else S.say('Could not send /sellit Acheron Shield: type it yourself.', true); end
end
function TRF.SV.stop(text, bad)
    local S, J = TRF.SV, TRF.SV.job;
    if J and J.kind == 'buy' and J.ev then                        -- (close the menu the server thinks is open)
        S.send(0x5B, 0x14, { { 0x04, J.ev.npc, 4 }, { 0x08, 0x40000000, 4 }, { 0x0C, J.ev.idx, 2 }, { 0x0E, 0, 2 }, { 0x10, J.ev.zone, 2 }, { 0x12, J.ev.event, 2 } });
    end
    S.job = nil;
    S.scan(true);
    if text then S.say(text, bad); end
end
-- Each frame: move the job along (and give up on a step after a few seconds)
function TRF.SV.tick()
    local S, J = TRF.SV, TRF.SV.job;
    if J == nil then return; end
    local now = os.clock();
    if J.kind == 'buy' then
        if J.stage == 'talk' and now - J.t > 4 then
            S.job = nil;
            S.say(('%s didn\'t open the Sparks menu. Talk to them once yourself (they may have something to say first), then press BUY.'):fmt(J.npc.name), true);
        elseif J.stage == 'ready' and now - J.t > 0.25 then
            J.stage, J.t, J.before = 'wait', now, S.sparks;
            S.send(0x5B, 0x14, { { 0x04, J.ev.npc, 4 }, { 0x08, S.OPTION, 4 }, { 0x0C, J.ev.idx, 2 }, { 0x0E, 1, 2 }, { 0x10, J.ev.zone, 2 }, { 0x12, J.ev.event, 2 } });
        elseif J.stage == 'wait' and now - J.t > 4 then
            S.stop(('The server didn\'t answer. Bought %d.'):fmt(J.got), true);
        end
    end
end
-- The server's packets: sparks (0x110 on change, 0x113 when asked), the Sparks menu (0x034, its updates 0x05C),
-- a shop's price (0x03D). Returns true to keep a packet from the game (the menu VenGo opened, its answers).
function TRF.SV.packet(id, d)
    local S, J = TRF.SV, TRF.SV.job;
    local function u8(o) return d:byte(o + 1) or 0; end
    local function u16(o) return u8(o) + u8(o + 1) * 256; end
    local function u32_(o) return u16(o) + u16(o + 2) * 65536; end
    local function i32(o) local v = u32_(o); if v >= 0x80000000 then v = v - 0x100000000; end return v; end
    if id == 0x110 then S.sparks, S.sparksAt = u8(4) + u8(5) * 256 + u8(6) * 65536, os.clock();
    elseif id == 0x113 then S.sparks, S.sparksAt = i32(0x74), os.clock();
    elseif id == 0x034 then
        local ev = u16(0x2C);
        local isShop = false;
        for _, e in pairs(S.NPCS) do if e == ev then isShop = true; end end
        if not isShop then
            if J and J.kind == 'buy' and J.stage == 'talk' and u32_(0x04) == J.npc.id then
                S.job = nil;
                S.say(('%s has something to say first: talk to them yourself, then press BUY.'):fmt(J.npc.name), true);
            end
            return false;
        end
        S.sparks, S.sparksAt = i32(0x0C), os.clock();
        local left = i32(0x1C);
        if left > 0 then S.left = left; end
        if J and J.kind == 'buy' and J.stage == 'talk' and u32_(0x04) == J.npc.id then
            J.ev = { npc = u32_(0x04), idx = u16(0x28), zone = u16(0x2A), event = ev };
            J.stage, J.t = 'ready', os.clock();
            S.status = ('Buying from %s...'):fmt(J.npc.name);
            return true;                                         -- (the menu stays shut)
        end
    elseif id == 0x05C and J and J.kind == 'buy' and J.stage == 'wait' then
        local sp = i32(0x04);
        local left = i32(0x18);
        if left > 0 then S.left = left; end
        if J.before and sp == J.before - S.COST then
            S.sparks, S.sparksAt = sp, os.clock();
            J.got = J.got + 1;
            if J.got >= J.want then S.stop(('Bought %d Acheron Shield%s for %s sparks.'):fmt(J.got, J.got == 1 and '' or 's', TRF.num(J.got * S.COST)));
            else J.stage, J.t = 'ready', os.clock(); end
        else
            S.sparks = sp;
            S.stop(J.got == 0 and 'The server didn\'t sell a shield (not enough sparks, the week\'s limit, or a full bag).'
                or ('Bought %d; the server stopped there (sparks, the week\'s limit or bag space).'):fmt(J.got), J.got == 0);
        end
        return true;
    end
    return false;
end
-- Ask the game server for your currencies (it answers with sparks among them) every 30 s while the tab is open
function TRF.SV.ask(force)
    local S = TRF.SV;
    if not force and os.clock() - S.askAt < (S.sparks == nil and 6 or 30) then return; end   -- (sooner until it has answered)
    S.askAt = os.clock();
    S.send(0x10F, 0x04, {});                                      -- (the Currencies window's request: just its header)
    if S.sparks == nil then pcall(TRF.TV.askCurrency, true); end  -- (and the CatsEyeXI server's own list, in case)
end
TRF.svTab = function()
    local S = TRF.SV;
    S.ask(false);
    local I = S.scan();
    if S.sparks == nil then                                       -- (until the game says: the CatsEyeXI server's currency list)
        for name, e in pairs(TRF.TV.cur or {}) do if name:lower():find('spark') then S.sparks, S.sparksAt = e.total, os.clock(); end end
    end
    local sparkN, room = S.canBuy();
    local dl = imgui.GetWindowDrawList();
    section('Spark vendor');
    -- the shield: its icon, its name, what it costs and sells for
    local x0, y0 = imgui.GetCursorScreenPos();
    local lh = imgui.GetTextLineHeight();
    local ic = itemIcon(S.ID);
    TRF.card(dl, x0, y0, ROW_W, 52, nil, false, 8);
    if ic then pcall(dl.AddImage, dl, ic.ptr, { x0 + 10, y0 + 10 }, { x0 + 42, y0 + 42 }, { 0, 0 }, { 1, 1 }, u32({ 1, 1, 1, 1 })); end
    dl:AddText({ x0 + 54, y0 + 9 }, u32(C.text), 'Acheron Shield');
    dl:AddText({ x0 + 54, y0 + 9 + lh + 2 }, u32(C.muted), ('%s sparks each  ·  sells for %s gil%s'):fmt(TRF.num(S.COST), TRF.num(S.PRICE), ''));
    imgui.Dummy({ ROW_W, 58 });
    -- the numbers
    local cards = {
        { label = 'Sparks', value = S.sparks or 0 },
        { label = 'Worth in gil', value = sparkN * S.PRICE },
        { label = 'Shields you can buy', value = sparkN },
        { label = 'Shields in your bag', value = I.have },
    };
    if S.sparks == nil then cards[1].value = 0; end
    TRF.PT.cards(cards, { 1.00, 0.80, 0.30 }, 4);
    imgui.TextColored(C.muted, (S.sparks == nil and 'Sparks: asking the game server...  ' or '') ..
        ('Bag space: %d free  ·  Gil: %s%s'):fmt(I.free, TRF.num(I.gil),
            (S.left and S.left < 10000000) and ('  ·  This week\'s limit: %s sparks left'):fmt(TRF.num(S.left)) or ''));
    if room < sparkN then imgui.TextColored(C.gold, ('Your bag has room for %d: make space to buy all %d.'):fmt(room, sparkN)); end
    imgui.Spacing();
    -- BUY and SELL
    local busy = S.job ~= nil;
    S.qty = math.max(1, math.min(S.qty or room, math.max(room, 1)));
    if S.qtyFor ~= room then S.qty, S.qtyFor = math.max(room, 1), room; end
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.text, 'How many');
    imgui.SameLine(0, 12);
    if button('-##vengo_sv_m', { 34, 0 }, true, true) and S.qty > 1 then S.qty = S.qty - 1; end
    imgui.SameLine(0, 8);
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.text, tostring(S.qty));
    imgui.SameLine(0, 8);
    if button('+##vengo_sv_p', { 34, 0 }, true, true) and S.qty < math.max(room, 1) then S.qty = S.qty + 1; end
    imgui.SameLine(0, 8);
    if button('MAX##vengo_sv_x', { 0, 0 }, true, true) then S.qty = math.max(room, 1); end
    imgui.Spacing();
    if busy then
        if button('STOP##vengo_sv_s', { 160, 0 }, true) then S.stop('Stopped.'); end
    else
        if button(('BUY %d##vengo_sv_b'):fmt(S.qty), { 160, 0 }) then S.buy(math.min(S.qty, room)); end
        tip(('Buys %d Acheron Shield%s (%s sparks). Stand by a Sparks NPC.'):fmt(S.qty, S.qty == 1 and '' or 's', TRF.num(S.qty * S.COST)));
        imgui.SameLine(0, 14);
        if button(('SELL %d##vengo_sv_l'):fmt(#I.slots), { 160, 0 }) then S.sell(); end
        tip(('Sends /sellit Acheron Shield (the SellIt addon): talk to an NPC shop and it sells the %d in your bag, about %s gil.'):fmt(#I.slots, TRF.num(#I.slots * S.PRICE)));
    end
    if S.status then
        imgui.Spacing();
        imgui.TextColored(S.statusCol or C.lav, S.status);
    end
    imgui.Spacing();
    local np = S.npc();
    if np then imgui.TextColored(np.d <= 5.5 and C.green or C.muted, ('%s is %.0f yalms away%s'):fmt(np.name, np.d, np.d <= 5.5 and ': ready to buy' or ': walk up to them'));
    else hint('Sparks NPCs: Isakoth (Bastok Markets), Rolandienne (Southern San d\'Oria), Fhelm Jobeizat (Windurst Woods), Eternal Flame (Western Adoulin).'); end
    imgui.Spacing();
    hint('BUY: stand by a Sparks NPC and press BUY. VenGo talks to them, buys one shield at a time (checking the sparks the server says are left after each) and closes the menu. SELL: sends /sellit Acheron Shield, so the SellIt addon sells them at the next NPC shop you talk to (SellIt must be loaded).');
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
    if config.star_chat ~= false then TRF.note('[Star] ' .. text); end
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
        if config.minimized or config.strip then config.minimized, config.strip = false, false; saveSettings(); end
        TRF.PAD.focus = true;
        msg('VenGo has the controller: d-pad to move, A to press. Back / Select (or /vengo pad) gives it back.');
    else
        pcall(vana.gamepad.nav, false);
        msg('The controller is back with the game.');
    end
end
-- The VNM alert from the controller: hold LB and press A for GO, B for DISMISS (only while the alert is showing;
-- A and B go to the game as usual otherwise, and LB always does). Returns true when the game shouldn't see the button.
function TRF.PAD.alertKey(btn, down, lb, a, b)
    local P = TRF.PAD;
    P.seen = true;                                                -- (any button: there's a controller)
    if btn == lb then P.lb = down; return false; end
    if btn ~= a and btn ~= b then return false; end
    if not P.lb or ALERT == nil or ALERT.dismissed or config.alert_popup == false then return false; end
    if down then P.alertCmd = (btn == a) and 'go' or 'dismiss'; end
    return true;
end
-- Is a controller plugged in? (any button pressed since load, or VanaCore lists one; asked every 10 s at most)
function TRF.PAD.present()
    local P = TRF.PAD;
    if P.seen then return true; end
    local now = os.clock();
    if P.listAt and now - P.listAt < 10 then return P.listed or false; end
    P.listAt = now;
    P.listed = false;
    pcall(function ()
        if not (rawget(_G, 'vana') and vana.gamepad and vana.gamepad.list) then return; end
        local function any(t) return (type(t) == 'table' and next(t) ~= nil) or (type(t) == 'number' and t > 0) or t == true; end
        local pads, xi = vana.gamepad.list();
        P.listed = any(pads) or any(xi);
    end);
    return P.listed;
end
-- A small controller drawn in lines (body, grips, d-pad, buttons)
function TRF.PAD.icon(dl, x, y, h, col)
    local w = h * 1.6;
    local c = u32(col);
    dl:AddCircleFilled({ x + h * 0.42, y + h * 0.62 }, h * 0.38, c, 14);       -- (left grip)
    dl:AddCircleFilled({ x + w - h * 0.42, y + h * 0.62 }, h * 0.38, c, 14);   -- (right grip)
    dl:AddRectFilled({ x + h * 0.22, y + h * 0.12 }, { x + w - h * 0.22, y + h * 0.72 }, c, h * 0.3);
    local k = u32({ 0.05, 0.04, 0.07, 1 });
    local dx, dy, a = x + h * 0.48, y + h * 0.42, h * 0.17;                      -- (d-pad)
    dl:AddRectFilled({ dx - a, dy - a * 0.35 }, { dx + a, dy + a * 0.35 }, k);
    dl:AddRectFilled({ dx - a * 0.35, dy - a }, { dx + a * 0.35, dy + a }, k);
    local bx, by, r = x + w - h * 0.48, y + h * 0.42, h * 0.075;                 -- (four buttons)
    dl:AddCircleFilled({ bx, by - h * 0.13 }, r, k, 8); dl:AddCircleFilled({ bx, by + h * 0.13 }, r, k, 8);
    dl:AddCircleFilled({ bx - h * 0.13, by }, r, k, 8); dl:AddCircleFilled({ bx + h * 0.13, by }, r, k, 8);
    return w;
end
-- Under the alert's buttons: [controller]  LB + A  GO     LB + B  DISMISS (a little smaller than the rest)
function TRF.PAD.alertHint(goWord)
    imgui.SetWindowFontScale(0.85);
    local dl = imgui.GetWindowDrawList();
    local x, y = imgui.GetCursorScreenPos();
    local lh = imgui.GetTextLineHeight();
    local iw = TRF.PAD.icon(dl, x, y + lh * 0.02, lh, C.muted);
    imgui.Dummy({ iw, lh });
    local parts = { { 'LB + A', C.lav }, { goWord, C.text }, { 'LB + B', C.lav }, { 'DISMISS', C.text } };
    for i, p_ in ipairs(parts) do
        imgui.SameLine(0, (i == 1) and 10 or ((i == 3) and 22 or 8));
        imgui.TextColored(p_[2], p_[1]);
    end
    imgui.SetWindowFontScale(1);
end
function TRF.PAD.frame()
    if not TRF.PAD.on then return; end
    if not ui.open[1] or config.minimized or config.strip then TRF.PAD.set(false); return; end
    pcall(vana.gamepad.nav, true);
end
pcall(function ()
    ashita.events.register('xinput_button', 'vengo_pad_x', function (e)
        if TRF.PAD.on and e.button == 5 and (e.state or 0) ~= 0 then  -- (Back)
            TRF.PAD.set(false);
            e.blocked = true;
            return true;
        end
        if TRF.PAD.alertKey(e.button, (e.state or 0) ~= 0, 8, 12, 13) then e.blocked = true; return true; end   -- (LB, A, B)
    end);
    ashita.events.register('dinput_button', 'vengo_pad_d', function (e)
        if TRF.PAD.on and e.button == 56 and (e.state or 0) >= 128 then -- (Share / Select on most pads)
            TRF.PAD.set(false);
            e.blocked = true;
            return true;
        end
        if TRF.PAD.alertKey(e.button, (e.state or 0) >= 128, 52, 49, 50) then e.blocked = true; return true; end -- (L1, Cross, Circle)
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
    if button('WHAT\'S NEW##vengo_up_n', { 130, h - 10 }, true, true) then ui.tab = 14; end
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

------------------------------------------------------------------------
-- DAILIES: the CatsEyeXI goblin dailies in Lower Jeuno (and Goldilox's dice), plus Palalumin's three Sea dailies.
-- Read from chat as you talk to them and work on them; kept per character until JP midnight.
-- Ported from Goldilox 3.10 by Dewin (Daniel Grace), MIT licence (LICENSE-goldilox.txt). Palalumin's chat formats
-- follow seekey13's Goldilox-UI (MIT).
------------------------------------------------------------------------
TRF.DL = { st = nil, cid = nil, inv = { at = -10, ok = false, names = {}, ids = {}, counts = {} }, tradeAt = nil,
    ORDER = { 'Fishstix', 'Murdox', 'Mistrix', 'Saltlix', 'Beetrix' },
    SEA = { 'Find flux', 'Item request', 'Defeat mobs' },
    SEA_TITLE = { ['Find flux'] = 'Find the Flux', ['Item request'] = 'Item request', ['Defeat mobs'] = 'Defeat mobs' },
    TAG = { new = 'NOT STARTED', active = 'IN PROGRESS', ['return'] = 'TURN IN', done = 'DONE' },
    QUICK = { 'Fishstix', 'Murdox', 'Mistrix', 'Saltlix', 'Beetrix', 'please return to', 'Daily Quest', 'Dice roll',
              'Find flux', 'Item request', 'Defeat mobs', 'Defeat Mobs', 'Quest Completed' },
    -- the diamonds before Palalumin's quest lines (Shift-JIS, and UTF-8 in case chat is re-encoded): open = not done
    DIAMONDS = { { '\129\158', false }, { '\129\159', true }, { '\226\151\135', false }, { '\226\151\134', true } },
};
function TRF.DL.trim(s) return (s:match('^%s*(.-)%s*$')); end
function TRF.DL.deadline()                                        -- (the next midnight in Japan, when dailies reset)
    local J = 9 * 3600;
    return 86400 + math.floor((os.time() + J) / 86400) * 86400 - J;
end
function TRF.DL.file(cid) return addon.path .. 'dailies_' .. tostring(cid) .. '.lua'; end
function TRF.DL.ser(v, ind)
    local t = type(v);
    if t == 'string' then return ('%q'):format(v); end
    if t == 'number' or t == 'boolean' then return tostring(v); end
    if t ~= 'table' then return 'nil'; end
    local out = {};
    for k, x in pairs(v) do
        local key = (type(k) == 'string' and k:match('^[%a_][%w_]*$')) and k or ('[' .. TRF.DL.ser(k) .. ']');
        out[#out + 1] = ind .. '  ' .. key .. ' = ' .. TRF.DL.ser(x, ind .. '  ') .. ',';
    end
    return '{\n' .. table.concat(out, '\n') .. '\n' .. ind .. '}';
end
function TRF.DL.save()
    local D = TRF.DL;
    if D.st == nil or D.cid == nil then return; end
    local f = io.open(D.file(D.cid), 'w');
    if f == nil then return; end
    f:write('-- Today\'s dailies (rewritten by VenGo)\nreturn ' .. D.ser(D.st, '') .. '\n');
    f:close();
end
-- Today's state for the character you're on (loaded when you change character; emptied at JP midnight)
function TRF.DL.status()
    local D = TRF.DL;
    local cid = 0;
    pcall(function () cid = mm():GetParty():GetMemberServerId(0) or 0; end);
    if cid == 0 then return D.st; end
    if D.st == nil or cid ~= D.cid then
        D.cid = cid;
        D.st = loadTable(D.file(cid)) or {};
    end
    local dl_ = D.deadline();
    if D.st.deadline ~= dl_ then
        D.st.deadline, D.st.dailies, D.st.sea = dl_, {}, {};
        if D.st.goldilox ~= dl_ then D.st.goldilox = 0; end
        D.save();
    end
    D.st.dailies = D.st.dailies or {};
    D.st.sea = D.st.sea or {};
    return D.st;
end

-- What each goblin says, read into the day's entry: talk(data, prev); describe(data) -> task, zone, link, items;
-- progress(data) -> killed, total
TRF.DL.GOB = {
    Fishstix = {
        talk = function (d) d.zone = d.message:match('Go to (.-),') or d.message:match('^Find .-chest in (.-)[%.!]?$'); end,
        describe = function (d) if d.zone then return 'Find and open the Secret Treasure Chest', d.zone; end end,
    },
    Murdox = {
        talk = function (d, prev)
            d.zone, d.count, d.target = d.message:match('Go to (.+) and kill (%d+) (.+)!');
            if not d.count then                                    -- (the short form: "Kill 16 Evil Weapons in Xarcabard")
                local n_, t_, z_ = d.message:match('^[Kk]ill (%d+) (.-) in (.-)[%.!]?$');
                if n_ then d.count, d.target, d.zone = n_, t_, z_; end
            end
            if prev and prev.message == d.message then d.remaining, d.mob = prev.remaining, prev.mob; end
        end,
        describe = function (d)
            if d.count and d.target then
                local q = d.mob;                                   -- ("Treants" is "Olden Treant" in the database)
                if not q then
                    q = d.target;
                    if tonumber(d.count) ~= 1 then q = q:gsub('s$', ''); end
                end
                return 'Kill ' .. d.count .. ' ' .. d.target, d.zone, { label = d.target, query = q };
            end
        end,
        progress = function (d)
            local total = tonumber(d.count);
            if not total or total <= 0 then return nil; end
            local left = tonumber(d.remaining) or total;
            return math.max(0, math.min(total, total - left)), total;
        end,
    },
    Mistrix = {
        talk = function (d) d.item = d.message:match('Craft me up %a+ signed (.+) and trade it to me!') or d.message:match('^[Cc]raft a signed (.-)[%.!]?$'); end,
        describe = function (d)
            if d.item then
                local name = d.item:gsub('^[Ss]erving of ', '');
                return 'Craft a signed ' .. name .. ' and trade it to Mistrix', nil, { label = name, query = name }, { { name = name, count = 1 } };
            end
        end,
    },
    Saltlix = {
        talk = function (d)
            d.zone, d.target = d.message:match('Go to (.+) and kill (.+)!');
            if not d.target then local t_, z_ = d.message:match('^[Kk]ill (.-) in (.-)[%.!]?$'); if t_ then d.target, d.zone = t_, z_; end end
        end,
        describe = function (d) if d.target then return 'Kill ' .. d.target, d.zone, { label = d.target, query = d.target }; end end,
        progress = function () return 0, 1; end,
    },
    Beetrix = {
        talk = function (d)
            d.zone, d.item = d.message:match('Go to (.+), get %a+ (.+) and trade it to me!');
            if not d.item then local i_, z_ = d.message:match('^[Cc]ollect (.-) from (.-)[%.!]?$'); if i_ then d.item, d.zone = i_, z_; end end
        end,
        describe = function (d)
            if d.item then return 'Get ' .. d.item .. ' and trade it to Beetrix', d.zone, { label = d.item, query = d.item }, { { name = d.item, count = 1 } }; end
        end,
    },
};

-- A goblin's row: state ('new', 'active', 'return', 'done'), task, zone, link, items, killed / total
function TRF.DL.describe(npc)
    local D = TRF.DL;
    local d = D.st and D.st.dailies[npc];
    if d == nil then return { state = 'new', task = 'Talk to ' .. npc .. ' in Lower Jeuno' }; end
    if d.status == 'complete' then return { state = 'done', task = 'Completed for today' }; end
    if d.status == 'return' then return { state = 'return', task = 'Return to ' .. npc .. ' to claim your reward' }; end
    local h = D.GOB[npc];
    if h.talk and d.message and not d.parsed_ then                -- (a day saved before this version: read its line again)
        d.parsed_ = true;
        pcall(h.talk, d, d);
    end
    local task, where, link, items = h.describe(d);
    local r = { state = 'active', task = task or d.message or '?', where = where, link = link, items = items };
    if h.progress then r.killed, r.total = h.progress(d); end
    return r;
end

-- "Ancient Beastcoin x3, Cosmo-Coin" -> { { name = 'Ancient Beastcoin', count = 3 }, { name = 'Cosmo-Coin', count = 1 } }
function TRF.DL.items(text)
    local out = {};
    for e in text:gmatch('([^,]+)') do
        e = TRF.DL.trim(e);
        local name, n = e:match('^(.-)%s+x(%d+)$');
        if name then out[#out + 1] = { name = name, count = tonumber(n) };
        elseif e ~= '' then out[#out + 1] = { name = e, count = 1 }; end
    end
    return out;
end
function TRF.DL.describeSea(key)
    local D = TRF.DL;
    local q = D.st and D.st.sea[key];
    local title = D.SEA_TITLE[key];
    if q == nil then return { state = 'new', title = title, task = 'Talk to Palalumin in the Grand Palace of Hu\'Xzoi' }; end
    if q.completed then return { state = 'done', title = title, task = 'Completed for today' }; end
    if key == 'Find flux' then return { state = 'active', title = title, task = 'Find the Lumorian Flux', where = q.zone }; end
    if key == 'Item request' then
        if q.items and #q.items > 0 then return { state = 'active', title = title, task = 'Trade these to Palalumin', items = q.items }; end
        return { state = 'active', title = title, task = 'Trade ' .. ((q.message and q.message ~= '') and q.message or 'the requested items') };
    end
    if q.total and q.killed then
        if q.killed >= q.total then return { state = 'return', title = title, task = 'Return to Palalumin to claim your reward' }; end
        return { state = 'active', title = title, where = q.zone, killed = math.max(0, q.killed), total = q.total,
                 task = q.target and ('Kill ' .. q.target) or 'Defeat the mobs',
                 link = q.target and { label = q.target, query = q.target } or nil };
    end
    return { state = 'active', title = title, task = (q.message and q.message ~= '') and q.message or 'Defeat the mobs' };
end

-- How many of each item you carry (main bag only: that's all you can trade from). Once a second, only while the tab is open.
function TRF.DL.scanInv()
    local I = TRF.DL.inv;
    local now = os.clock();
    if now - I.at < 1 then return; end
    I.at = now;
    I.ok = pcall(function ()
        local inv = mm():GetInventory();
        local counts = {};
        for i = 0, inv:GetContainerCountMax(0) or 0 do
            local it = inv:GetContainerItem(0, i);
            local id = it and it.Id;
            if id and id ~= 0 and id ~= 65535 then
                local n = I.names[id];
                if n == nil then
                    n = TRF.AR.name(id);
                    n = (type(n) == 'string' and n ~= '' and not n:find('^Item ')) and n:lower() or false;
                    I.names[id] = n;
                    if n then I.ids[n] = id; end
                end
                if n then counts[n] = (counts[n] or 0) + (tonumber(it.Count) or 1); end
            end
        end
        I.counts = counts;
    end);
end
-- An exact name wins; otherwise one containing the other counts ("serving of goblin stir-fry" finds "Goblin Stir-fry")
function TRF.DL.have(name)
    local I = TRF.DL.inv;
    local key = (name or ''):lower();
    if I.counts[key] then return I.counts[key], I.ids[key]; end
    local sum, id = 0, nil;
    if #key >= 4 then
        for k, v in pairs(I.counts) do
            if #k >= 4 and (k:find(key, 1, true) or key:find(k, 1, true)) then sum = sum + v; id = id or I.ids[k]; end
        end
    end
    return sum, id;
end

-- Chat: every line is checked cheaply first, so combat spam costs almost nothing
function TRF.DL.text(m)
    local D = TRF.DL;
    local hit = false;
    for _, n in ipairs(D.QUICK) do if m:find(n, 1, true) then hit = true; break; end end
    if not hit then return; end
    m = m:gsub('[\30\31\127].', ''):gsub('[\1-\6\8\9\11-\31]', '');
    for line in (m .. '\n'):gmatch('([^\n\7]*)[\n\7]') do
        line = D.trim(line);
        if line ~= '' and not line:find('^%[VenGo%]') then pcall(D.line, line); end
    end
end
function TRF.DL.seaLine(line)                                     -- (one of Palalumin's quest lines? key, finished, objective)
    local low = line:lower();
    for _, key in ipairs(TRF.DL.SEA) do
        local s, e = low:find(key:lower() .. '%s*:');
        if s then
            local before = line:sub(math.max(1, s - 4), s - 1);
            for _, d in ipairs(TRF.DL.DIAMONDS) do
                if before:find(d[1], 1, true) then
                    local obj = TRF.DL.trim(line:sub(e + 1));
                    if obj ~= '' then return key, d[2], obj; end
                end
            end
        end
    end
end
function TRF.DL.line(line)
    local D = TRF.DL;
    local S = D.status();
    if S == nil then return; end
    -- Palalumin
    local key, fin, obj = D.seaLine(line);
    if key then
        local q = { message = obj, completed = fin or nil };
        if key == 'Find flux' then q.zone = obj;
        elseif key == 'Item request' then q.items = D.items(obj);
        elseif not fin then
            local t, z, k, n = obj:match('(.+)%s+%((.+)%)%s+(%d+)/(%d+)');
            if t then q.target, q.zone, q.killed, q.total = t, z, tonumber(k), tonumber(n); end
        end
        S.sea[key] = q;
        return D.save();
    end
    local k, n, mob, z = line:match('Defeat Mobs (%d+)/(%d+) %((.+) in (.+)%)');
    if k then
        local q = S.sea['Defeat mobs'] or { message = '' };
        q.killed, q.total, q.target, q.zone = tonumber(k), tonumber(n), mob, z;
        S.sea['Defeat mobs'] = q;
        return D.save();
    end
    if line:find('Quest Completed', 1, true) then              -- (which one: worked out from who you're facing)
        local t = nil;
        pcall(function ()
            local tg = mm():GetTarget();
            local idx = tg:GetTargetIndex(tg:GetIsSubTargetActive() == 1 and 1 or 0);
            if idx and idx > 0 then t = mm():GetEntity():GetName(idx); end
        end);
        local function finish(key_) local q = S.sea[key_]; if q and not q.completed then q.completed = true; D.save(); end end
        if t == 'Lumorian Flux' then finish('Find flux');
        elseif t == 'Palalumin' then
            local kills = S.sea['Defeat mobs'];
            if D.tradeAt and os.clock() - D.tradeAt < 60 then finish('Item request');
            elseif kills and kills.killed and kills.total and kills.killed >= kills.total then finish('Defeat mobs'); end
        end
        return;
    end
    -- "Fishstix : Go to Yughott Grotto, ..."
    for _, npc in ipairs(D.ORDER) do
        local said = line:match('%f[%a]' .. npc .. '%s*:%s*(.+)$');
        if said then
            said = D.trim(said);
            local d = { message = said };
            if said:find('completed') then d.status = 'complete'; else D.GOB[npc].talk(d, S.dailies[npc]); end
            S.dailies[npc] = d;
            return D.save();
        end
    end
    -- "You've killed enough Olden Treants, please return to Murdox to claim your reward!"
    local who = line:match('please return to (%a+) to claim your reward');
    if who and D.GOB[who] then
        S.dailies[who] = S.dailies[who] or { message = '' };
        S.dailies[who].status = 'return';
        return D.save();
    end
    -- "Daily Quest: 19 kills remain. (Olden Treant in Bhaflau Thickets)"
    local left = line:match('Daily Quest: (%d+) kills? remain');
    if left then
        local M = S.dailies.Murdox;
        if M then
            M.remaining = left;
            local exact = line:match('kills? remain.-%((.-) in ');
            if exact and exact ~= '' then M.mob = exact; end
            D.save();
        end
        return;
    end
    if line:match('Dice roll!.*rolls.*%(.*%)') then S.goldilox = S.deadline; D.save(); end
end

function TRF.DL.open(query)                                       -- (catseyexi.com's database, searched for the name)
    local url = 'https://catseyexi.com/database?q=' .. query:gsub('[^%w%-%._~]', function (c) return ('%%%02X'):format(c:byte()); end);
    if not TRF.UP.shell(url, '') then msg('Could not open your browser. Link: ' .. url); end
end

-- One quest card: state dot, name, zone and pill on top; the task under it (the NM or item is a link); then a bar
-- for kills and one per item you have to bring
TRF.DL.COL = { new = 'muted', active = 'seal', ['return'] = 'gold', done = 'green' };
TRF.DL.KIND = { active = 'on', ['return'] = 'done', done = 'own' };
function TRF.DL.card(dl, id, name, r, pin)
    local D = TRF.DL;
    local lh = imgui.GetTextLineHeight();
    local bars = {};
    if r.total and r.state == 'active' then bars[#bars + 1] = { have = r.killed or 0, need = r.total, label = 'Killed' }; end
    if r.items and r.state == 'active' then
        for _, it in ipairs(r.items) do
            local have, iid = D.have(it.name);
            bars[#bars + 1] = { have = have, need = it.count, label = it.name, id = iid, link = it.name };
        end
    end
    local x, y = imgui.GetCursorScreenPos();
    local w = ROW_W;
    local h = 14 + lh + 6 + lh + 12 + #bars * (lh + 8);
    local mx0, my0 = imgui.GetMousePos();                          -- (no hover button: the links inside take the clicks)
    local hov = imgui.IsWindowHovered() and mx0 >= x and mx0 < x + w and my0 >= y and my0 < y + h;
    TRF.card(dl, x, y, w, h, D.KIND[r.state], hov, 8);
    local col = C[D.COL[r.state]] or C.muted;
    local done = r.state == 'done';

    -- top line
    local ty = y + 10;
    dl:AddCircleFilled({ x + 16, ty + lh / 2 }, 4, u32({ col[1], col[2], col[3], 1 }), 12);
    if r.state == 'active' or r.state == 'return' then
        dl:AddCircle({ x + 16, ty + lh / 2 }, 7, u32({ col[1], col[2], col[3], 0.35 }), 16, 1.5);
    end
    dl:AddText({ x + 30, ty }, u32(done and C.muted or C.text), name);
    local nx = x + 30 + imgui.CalcTextSize(name);
    if r.where and r.where ~= '' and not done then dl:AddText({ nx + 12, ty }, u32(C.lav), r.where); end
    local tag = D.TAG[r.state];
    imgui.SetWindowFontScale(0.82);
    local pw, ph = spacedW(tag, 1.5) + 20, imgui.GetTextLineHeight() + 6;
    local px, py = x + w - pw - 12, ty + (lh - ph) / 2;
    dl:AddRectFilled({ px, py }, { px + pw, py + ph }, u32({ col[1], col[2], col[3], 0.14 }), ph / 2);
    dl:AddRect({ px, py }, { px + pw, py + ph }, u32({ col[1], col[2], col[3], 0.55 }), ph / 2, C.rall, 1);
    spaced(dl, px + 10, py + 3, tag, u32({ col[1], col[2], col[3], 1 }), 1.5);
    imgui.SetWindowFontScale(1);
    if pin then                                                   -- (the pin, left of the pill)
        local on = D.pinned(pin);
        local qx, qy = px - 18, ty + lh / 2;
        local qh, qc = TRF.hot('##vengo_dlp' .. id, qx - 11, qy - 11, 22, 22);
        if qh then dl:AddCircleFilled({ qx, qy }, 11, u32({ 1, 1, 1, 0.07 }), 16); end
        D.pinIcon(dl, qx, qy, 19, on and NEON2 or (qh and C.text or C.muted), on);
        if qh then imgui.SetTooltip(on and 'Pinned: shown on screen while VenGo is minimized. Click to unpin.' or 'Pin: keep this on screen while VenGo is minimized'); end
        if qc then D.togglePin(pin); end
    end

    -- the task, with the NM or item as a link
    local tx, tyy = x + 30, ty + lh + 6;
    local task, L = r.task or '', r.link;
    local s_, e_ = nil, nil;
    if L and not done and r.state ~= 'return' then s_, e_ = task:find(L.label, 1, true); end
    if s_ then
        local pre, mid, post = task:sub(1, s_ - 1), task:sub(s_, e_), task:sub(e_ + 1);
        dl:AddText({ tx, tyy }, u32(C.text), pre);
        local mx_ = tx + imgui.CalcTextSize(pre);
        local mw = imgui.CalcTextSize(mid);
        local lhov, lclick = TRF.hot('##vengo_dll' .. id, mx_, tyy, mw, lh);
        local lc = lhov and { NEON2[1], NEON2[2], NEON2[3], 1 } or C.acc;
        dl:AddText({ mx_, tyy }, u32(lc), mid);
        dl:AddLine({ mx_, tyy + lh }, { mx_ + mw, tyy + lh }, u32({ lc[1], lc[2], lc[3], lhov and 0.9 or 0.4 }), 1);
        dl:AddText({ mx_ + mw, tyy }, u32(C.text), post);
        if lhov then imgui.SetTooltip('Look up ' .. L.query .. ' on catseyexi.com/database'); end
        if lclick then D.open(L.query); end
    else
        dl:AddText({ tx, tyy }, u32(done and C.muted or C.text), task);
    end

    -- bars
    local by = tyy + lh + 10;
    for i, b in ipairs(bars) do
        local bx = tx;
        if b.id then TRF.icon(dl, b.id, bx, by - 1, lh + 2, 1); end
        local lx = bx + (b.id and lh + 8 or 0);
        local label = b.label;
        local lw = math.min(imgui.CalcTextSize(label), 260);
        dl:AddText({ lx, by }, u32(b.have >= b.need and C.green or C.muted), label);
        if b.link then
            local ih, ic = TRF.hot(('##vengo_dli%s%d'):format(id, i), lx, by, lw, lh);
            if ih then imgui.SetTooltip('Look up ' .. b.link .. ' on catseyexi.com/database'); end
            if ic then D.open(b.link); end
        end
        local barX = x + 30 + 280;
        TRF.bar(dl, barX, by, x + w - 16 - barX, lh, b.have, b.need);
        by = by + lh + 8;
    end
    imgui.Dummy({ w, h + 6 });
end

-- Pins: a pinned daily stays on screen in a small tracker while VenGo is minimized or closed
-- (kept in the settings as "g:Murdox,s:Defeat mobs")
function TRF.DL.pinned(key) return TRF.ST.set('dl_pins')[key] or false; end
function TRF.DL.togglePin(key)
    local s = {};
    for k in pairs(TRF.ST.set('dl_pins')) do s[k] = true; end
    s[key] = (not s[key]) or nil;
    TRF.ST.save('dl_pins', s);
end
-- A dagger, point down-left (stuck in, like a pin): pommel, grip, cross-guard, blade. The blade is filled when on.
function TRF.DL.pinIcon(dl, cx, cy, sz, col, on)
    local c = u32({ col[1], col[2], col[3], on and 1 or 0.8 });
    local dx, dy = -0.7071, 0.7071;                               -- (along the dagger, toward the point)
    local nx, ny = 0.7071, 0.7071;                                -- (across it)
    local function at(t, n) return { cx + (dx * t + nx * (n or 0)) * sz, cy + (dy * t + ny * (n or 0)) * sz }; end
    dl:AddCircleFilled(at(-0.47), sz * 0.085, c, 10);                                  -- (pommel)
    dl:AddLine(at(-0.42), at(-0.2), c, math.max(1.5, sz * 0.13));                       -- (grip)
    dl:AddLine(at(-0.18, -0.21), at(-0.18, 0.21), c, math.max(1.5, sz * 0.11));         -- (cross-guard)
    local b1, b2, tip = at(-0.14, -0.085), at(-0.14, 0.085), at(0.52);
    if on then
        dl:AddTriangleFilled(b1, b2, tip, c);
        dl:AddLine(at(-0.12), at(0.36), u32({ 1, 1, 1, 0.45 }), 1);                     -- (a glint down the middle)
    else
        local w = math.max(1, sz * 0.07);
        dl:AddLine(b1, tip, c, w); dl:AddLine(b2, tip, c, w); dl:AddLine(b1, b2, c, w);
    end
end
-- The rows the tracker shows, in tab order
function TRF.DL.pinnedRows()
    local D = TRF.DL;
    local rows = {};
    for _, npc in ipairs(D.ORDER) do
        if D.pinned('g:' .. npc) then local r = D.describe(npc); r.name, r.key = npc, 'g:' .. npc; rows[#rows + 1] = r; end
    end
    for _, k in ipairs(D.SEA) do
        if D.pinned('s:' .. k) then local r = D.describeSea(k); r.name, r.key = r.title, 's:' .. k; rows[#rows + 1] = r; end
    end
    return rows;
end
-- The tracker: only when the full window isn't showing and something is pinned
function TRF.DL.tracker()
    local D = TRF.DL;
    if ui.open[1] and not config.minimized and not config.strip then return; end
    if (config.dl_pins or '') == '' then return; end
    if D.status() == nil then return; end
    local rows = D.pinnedRows();
    if #rows == 0 then return; end
    local needInv = false;
    for _, r in ipairs(rows) do if r.items and r.state == 'active' then needInv = true; end end
    if needInv then D.scanInv(); end

    local nc, nv = pushTheme();
    local pushed = pushFont(fonts.panel, 15);
    local lh = imgui.GetTextLineHeight();
    local W, P = 330, 12;
    local heights, H = {}, P + lh + 10;
    for i, r in ipairs(rows) do
        local nb = 0;
        if r.state == 'active' then nb = (r.total and 1 or 0) + (r.items and #r.items or 0); end
        heights[i] = lh + 3 + lh + nb * (lh + 3) + 10;
        H = H + heights[i];
    end
    H = H + P - 6;
    imgui.SetNextWindowPos({ 60, 300 }, ImGuiCond_FirstUseEver);
    imgui.SetNextWindowSize({ W, H }, ImGuiCond_Always);
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse, ImGuiWindowFlags_NoFocusOnAppearing);
    if imgui.Begin('VenGo dailies##vengo_dl_track', { true }, flags) then pcall(function ()   -- (an error still ends the window)
        local dl = imgui.GetWindowDrawList();
        local wx, wy = imgui.GetWindowPos();
        local a = config.transparent and 0.62 or 0.92;
        dl:AddRectFilled({ wx, wy }, { wx + W, wy + H }, u32({ C.pbg[1], C.pbg[2], C.pbg[3], a }), 10);
        pcall(function ()
            dl:AddRectFilledMultiColor({ wx + 10, wy }, { wx + W - 10, wy + 2 }, u32({ NEON2[1], NEON2[2], NEON2[3], 0.9 }),
                u32({ C.mp2[1], C.mp2[2], C.mp2[3], 0.9 }), u32({ C.mp2[1], C.mp2[2], C.mp2[3], 0.9 }), u32({ NEON2[1], NEON2[2], NEON2[3], 0.9 }));
        end);
        dl:AddRect({ wx, wy }, { wx + W, wy + H }, u32({ 1, 1, 1, 0.08 }), 10, C.rall, 1);
        -- header: DAILIES and the time to the reset
        local x, y = wx + P, wy + P;
        imgui.SetWindowFontScale(0.85);
        spaced(dl, x, y + 1, 'DAILIES', u32(C.label), 2);
        local rt = TRF.dur(D.deadline() - os.time());
        dl:AddText({ wx + W - P - imgui.CalcTextSize(rt), y + 1 }, u32(C.gold), rt);
        imgui.SetWindowFontScale(1);
        y = y + lh + 6;
        dl:AddLine({ x, y }, { wx + W - P, y }, u32({ 1, 1, 1, 0.06 }), 1);
        y = y + 6;
        for i, r in ipairs(rows) do
            local col = C[D.COL[r.state]] or C.muted;
            local done = r.state == 'done';
            dl:AddCircleFilled({ x + 4, y + lh / 2 }, 3.5, u32({ col[1], col[2], col[3], 1 }), 12);
            dl:AddText({ x + 14, y }, u32(done and C.muted or C.text), r.name);
            local tag = (r.state == 'active' and r.where and r.where ~= '') and r.where or D.TAG[r.state];
            local nx = x + 14 + imgui.CalcTextSize(r.name);
            imgui.SetWindowFontScale(0.85);
            local maxW = wx + W - P - 26 - (nx + 10);
            local t_ = tag;
            while #t_ > 3 and imgui.CalcTextSize(t_) > maxW do t_ = t_:sub(1, -5) .. '...'; end
            dl:AddText({ nx + 10, y + 2 }, u32((r.state == 'active') and C.lav or col), t_);
            imgui.SetWindowFontScale(1);
            -- the pin (click: unpin)
            local px_, py_ = wx + W - P - 9, y + lh / 2;
            local ph_, pc_ = TRF.hot('##vengo_dlt_pin' .. i, px_ - 10, py_ - 10, 20, 20);
            D.pinIcon(dl, px_, py_, 18, ph_ and C.text or NEON2, true);
            if ph_ then imgui.SetTooltip('Unpin'); end
            if pc_ then D.togglePin(r.key); end
            y = y + lh + 3;
            -- the objective, smaller
            imgui.SetWindowFontScale(0.88);
            local task = done and 'Done for today' or (r.task or '');
            local tmax = W - P * 2 - 14;
            while #task > 3 and imgui.CalcTextSize(task) > tmax do task = task:sub(1, -5) .. '...'; end
            dl:AddText({ x + 14, y }, u32(done and C.green or C.muted), task);
            y = y + lh + 3;
            if r.state == 'active' then
                local bw = W - P * 2 - 14;
                if r.total then TRF.bar(dl, x + 14, y, bw, lh, r.killed or 0, r.total); y = y + lh + 3; end
                for _, it in ipairs(r.items or {}) do
                    local have = D.have(it.name);
                    local nm = it.name;
                    local lw = 120;
                    while #nm > 3 and imgui.CalcTextSize(nm) > lw do nm = nm:sub(1, -5) .. '...'; end
                    dl:AddText({ x + 14, y }, u32(have >= it.count and C.green or C.muted), nm);
                    TRF.bar(dl, x + 14 + lw + 8, y, bw - lw - 8, lh, have, it.count);
                    y = y + lh + 3;
                end
            end
            imgui.SetWindowFontScale(1);
            y = y + 7;
        end
        imgui.SetWindowFontScale(1);
        imgui.SetCursorScreenPos({ wx, wy });
        imgui.Dummy({ W, H });
    end); end
    imgui.End();
    if pushed then imgui.PopFont(); end
    imgui.PopStyleVar(nv);
    imgui.PopStyleColor(nc);
end

TRF.dlTab = function()
    local D = TRF.DL;
    local S = D.status();
    D.scanInv();
    section('Dailies');
    local left = TRF.DL.deadline() - os.time();
    imgui.TextColored(C.muted, 'Resets at JP midnight, in');
    imgui.SameLine(0, 6);
    imgui.TextColored(C.gold, TRF.dur(left));
    imgui.SameLine(ROW_W - 150);
    if button('CLEAR TODAY##vengo_dlclr', { 150, 0 }, true, true) and S then
        S.dailies, S.sea, S.goldilox = {}, {}, 0;
        D.save();
    end
    if S == nil then hint('Waiting for your character to load...'); return; end
    local dl = imgui.GetWindowDrawList();
    TRF.PT.block('dailies', 'Daily points', 3);

    -- the goblins
    local n = 0;
    for _, npc in ipairs(D.ORDER) do if S.dailies[npc] and S.dailies[npc].status == 'complete' then n = n + 1; end end
    TRF.header(dl, 'Goblins of Lower Jeuno', { 0.96, 0.76, 0.32 }, ('%d / 5 done'):fmt(n));
    for i, npc in ipairs(D.ORDER) do D.card(dl, 'g' .. i, npc, D.describe(npc), 'g:' .. npc); end

    -- Goldilox's dice
    local got = S.goldilox == S.deadline;
    local x, y = imgui.GetCursorScreenPos();
    local lh = imgui.GetTextLineHeight();
    local h = lh + 20;
    TRF.card(dl, x, y, ROW_W, h, got and 'own' or nil, false, 8);
    local gc = got and C.green or (n > 0 and C.gold or C.muted);
    dl:AddCircleFilled({ x + 16, y + h / 2 }, 4, u32({ gc[1], gc[2], gc[3], 1 }), 12);
    dl:AddText({ x + 30, y + 10 }, u32(C.text), 'Goldilox');
    dl:AddText({ x + 30 + imgui.CalcTextSize('Goldilox') + 12, y + 10 }, u32(C.muted),
        got and 'Reward collected today' or (n > 0 and 'Reward waiting: talk to Goldilox and roll the dice' or 'Finish a goblin daily, then roll Goldilox\'s dice'));
    local tag = got and 'COLLECTED' or 'NOT YET';
    imgui.SetWindowFontScale(0.82);
    local pw, ph = spacedW(tag, 1.5) + 20, imgui.GetTextLineHeight() + 6;
    local px, py = x + ROW_W - pw - 12, y + (h - ph) / 2;
    dl:AddRectFilled({ px, py }, { px + pw, py + ph }, u32({ gc[1], gc[2], gc[3], 0.14 }), ph / 2);
    dl:AddRect({ px, py }, { px + pw, py + ph }, u32({ gc[1], gc[2], gc[3], 0.55 }), ph / 2, C.rall, 1);
    spaced(dl, px + 10, py + 3, tag, u32({ gc[1], gc[2], gc[3], 1 }), 1.5);
    imgui.SetWindowFontScale(1);
    imgui.Dummy({ ROW_W, h + 6 });

    -- Palalumin
    local ns = 0;
    for _, key in ipairs(D.SEA) do if S.sea[key] and S.sea[key].completed then ns = ns + 1; end end
    TRF.header(dl, 'Palalumin (Sea)', { 0.45, 0.62, 1.0 }, ('%d / 3 done'):fmt(ns));
    for i, key in ipairs(D.SEA) do local r = D.describeSea(key); D.card(dl, 's' .. i, r.title, r, 's:' .. key); end

    imgui.Spacing();
    hint('Talk to each goblin in Lower Jeuno (and Palalumin in the Grand Palace of Hu\'Xzoi) to pick up today\'s task; VenGo reads it from chat and follows your kills and the items in your inventory. If a finished Sea quest is missed, talk to Palalumin again. Click a name in violet to look it up on catseyexi.com. Pin a daily to keep it on screen while VenGo is minimized.');
end

TRF.ptTab = function()
    local P = TRF.PT;
    section('CatsEyeXI');
    TRF.refreshRow('Points', P.at, P.pending, function () P.ask(true); end);
    P.block('catseyexi', 'Points', 3);
    for _, g in ipairs(P.others()) do P.block(g:lower(), g, 3); end
    imgui.Spacing();
    hint('Your Dailies, Ventures and Summit points are on those tabs. Updated from the CatsEyeXI server every minute while one of these tabs is open.');
end

------------------------------------------------------------------------
-- VOICES: recorded clips in the sounds folder (nothing to install). When a VNM is announced the voice says
-- "V N M incoming!" and its name; a minute before it pops, its name and "One minute to the pop!".
-- The clips were made with free voices: alba (Scottish English, CC BY 4.0) and Kokoro's George and Alpha
-- (Apache 2.0); see LICENSE-voices.txt.
------------------------------------------------------------------------
TRF.VO = { cache = {},
    PRESETS = {
        { 'off',    'OFF' },
        { 'scot_f', 'SCOTTISH F', name = 'Scottish female' },
        { 'gb_m',   'BRITISH M',  name = 'British male' },
        { 'ja_f',   'JAPANESE F', name = 'Japanese female', ja = true },
    },
};
function TRF.VO.preset(key) for _, p in ipairs(TRF.VO.PRESETS) do if p[1] == key then return p; end end return nil; end
function TRF.VO.slug(s) return (tostring(s or ''):lower():gsub('[^%w]', '')); end
-- A clip's sound data (its format bytes and samples), read once
function TRF.VO.clip(voice, key)
    local V = TRF.VO;
    local path = addon.path .. 'sounds\\' .. voice .. '\\' .. key .. '.wav';
    local c = V.cache[path];
    if c ~= nil then return c or nil; end
    local f = io.open(path, 'rb');
    if f == nil then V.cache[path] = false; return nil; end
    local s = f:read('*a'); f:close();
    local fmt, data = nil, nil;
    local function u32(o) local a, b, c_, d = s:byte(o, o + 3); return a + b * 256 + c_ * 65536 + d * 16777216; end
    if s:sub(1, 4) == 'RIFF' and s:sub(9, 12) == 'WAVE' then
        local o = 13;
        while o + 8 <= #s do
            local id, n = s:sub(o, o + 3), u32(o + 4);
            if id == 'fmt ' then fmt = s:sub(o + 8, o + 7 + n); elseif id == 'data' then data = s:sub(o + 8, o + 7 + n); end
            o = o + 8 + n + (n % 2);
        end
    end
    c = (fmt and data) and { fmt = fmt, data = data } or false;
    V.cache[path] = c;
    return c or nil;
end
-- Join clips (with a short pause between) into one file and play it; true if it played
function TRF.VO.play(voice, keys, need)
    local V = TRF.VO;
    if not V.clip(voice, need) then return false; end              -- (no phrase clip: the voice isn't there)
    local parts, fmt = {}, nil;
    for _, k in ipairs(keys) do
        local c = V.clip(voice, k);                                 -- (a VNM without a clip of its name: just the phrase)
        if c then
            fmt = fmt or c.fmt;
            if #parts > 0 then parts[#parts + 1] = string.rep('\0', 5760); end   -- (0.18 s at 16 kHz, 16-bit)
            parts[#parts + 1] = c.data;
        end
    end
    if fmt == nil then return false; end
    local data = table.concat(parts);
    local function le(n) return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256); end
    local file = addon.path .. 'vengo_say.wav';
    local f = io.open(file, 'wb');
    if f == nil then return false; end
    f:write('RIFF', le(4 + 8 + #fmt + 8 + #data), 'WAVE', 'fmt ', le(#fmt), fmt, 'data', le(#data), data);
    f:close();
    local ok = pcall(function () ashita.misc.play_sound(file); end);
    if not ok then
        ok = pcall(function ()
            local ffi = require('ffi');
            pcall(ffi.cdef, 'int __stdcall PlaySoundA(const char* pszSound, void* hmod, uint32_t fdwSound);');
            ffi.load('winmm').PlaySoundA(file, nil, 0x00020001);   -- SND_FILENAME | SND_ASYNC
        end);
    end
    return ok;
end
-- Say it: kind 'incoming' (announced) or 'minute' (about to pop). True if the voice spoke (then no chime).
function TRF.VO.say(kind, v)
    local V = TRF.VO;
    local p = V.preset(config.alert_voice or 'off');
    if p == nil or p[1] == 'off' or v == nil then return false; end
    local name = V.slug(v.nm);
    local phrase = (kind == 'minute') and '_minute' or '_incoming';
    local keys = { phrase, name };                                  -- ("V N M incoming!  Puffer Pugil")
    if kind == 'minute' and not p.ja then keys = { name, phrase }; end   -- ("Puffer Pugil.  One minute to the pop!")
    return V.play(p[1], keys, phrase);
end
-- Settings > VNM Alerts: the voice
function TRF.VO.settings()
    local V = TRF.VO;
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.text, 'Voice');
    tip('Says "V N M incoming!" and the VNM\'s name when it\'s announced, and its name and "One minute to the pop!" a minute before. It plays instead of the alert chime.');
    local pk = pillChoice('##vengo_voice', V.PRESETS, (V.preset(config.alert_voice or 'off') and config.alert_voice) or 'off');
    if pk then config.alert_voice = pk; saveSettings(); end
    local p = V.preset(config.alert_voice or 'off');
    if p and p[1] ~= 'off' then
        if V.clip(p[1], '_incoming') then
            if button('TEST VOICE##vengo_vtest', { 0, 0 }, false, true) then V.say('incoming', { nm = 'Puffer Pugil' }); end
            imgui.SameLine(0, 10);
            imgui.TextColored(C.muted, p.ja and 'Speaks Japanese, then the VNM\'s name' or 'Recorded voice: nothing to install');
        else
            imgui.TextColored(C.gold, 'The voice clips are missing: the "sounds" folder should be in the vengo folder.');
        end
    end
end

------------------------------------------------------------------------
-- YOUR OWN BACKGROUND: a picture you choose (Windows' file picker, through PowerShell) is copied into the
-- images folder and drawn behind the panel, filling it without stretching, under a tint of the background colour.
------------------------------------------------------------------------
TRF.BGI = { pending = nil, dims = {} };
TRF.BGI.PICK = [[
Add-Type -AssemblyName System.Windows.Forms
$out = Join-Path $PSScriptRoot 'vengo_pick.txt'
$d = New-Object System.Windows.Forms.OpenFileDialog
$d.Title = 'VenGo: choose a background picture'
$d.Filter = 'Pictures (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp'
$owner = New-Object System.Windows.Forms.Form
$owner.TopMost = $true
$name = ''
if ($d.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) {
    $ext = [System.IO.Path]::GetExtension($d.FileName).ToLower()
    $name = 'custom_bg_' + [DateTime]::Now.ToString('yyyyMMddHHmmss') + $ext
    Copy-Item -LiteralPath $d.FileName -Destination (Join-Path $PSScriptRoot ('images\' + $name))
}
[System.IO.File]::WriteAllText($out, $name)
]];
-- Start the picker (in the background; VenGo keeps running)
function TRF.BGI.choose()
    local B = TRF.BGI;
    local f = io.open(addon.path .. 'vengo_pick.ps1', 'wb');
    if f == nil then return; end
    f:write(B.PICK); f:close();
    os.remove(addon.path .. 'vengo_pick.txt');
    B.pending = os.clock();
    TRF.UP.shell('powershell.exe', ('-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%s"'):format(addon.path .. 'vengo_pick.ps1'));
end
function TRF.BGI.poll()
    local B = TRF.BGI;
    if not B.pending or os.clock() - (B.lastPoll or 0) < 0.5 then return; end
    B.lastPoll = os.clock();
    if os.clock() - B.pending > 600 then B.pending = nil; return; end
    local f = io.open(addon.path .. 'vengo_pick.txt', 'rb');
    if f == nil then return; end
    local name = (f:read('*a') or ''):gsub('%s+$', ''); f:close();
    os.remove(addon.path .. 'vengo_pick.txt');
    B.pending = nil;
    if name ~= '' and name:match('^custom_bg_[%w_]+%.%w+$') then
        local old = config.bg_img or '';
        if old ~= '' and old ~= name then os.remove(addon.path .. 'images\\' .. old); end
        config.bg_img = name;
        saveSettings();
    end
end
-- A picture's width and height, read from its header (PNG, JPEG, BMP)
function TRF.BGI.size(name)
    local B = TRF.BGI;
    if B.dims[name] ~= nil then return B.dims[name] or nil; end
    B.dims[name] = false;
    local f = io.open(addon.path .. 'images\\' .. name, 'rb');
    if f == nil then return nil; end
    local s = f:read(65536) or ''; f:close();
    local function be16(o) local a, b = s:byte(o, o + 1); return (a or 0) * 256 + (b or 0); end
    local function be32(o) return be16(o) * 65536 + be16(o + 2); end
    local function le32(o) local a, b, c, d = s:byte(o, o + 3); return (a or 0) + (b or 0) * 256 + (c or 0) * 65536 + (d or 0) * 16777216; end
    local w, h = nil, nil;
    if s:sub(1, 8) == '\137PNG\r\n\26\n' then w, h = be32(17), be32(21);
    elseif s:sub(1, 2) == 'BM' then w, h = le32(19), math.abs(le32(23) >= 2147483648 and (le32(23) - 4294967296) or le32(23));
    elseif s:sub(1, 2) == '\255\216' then
        local o = 3;
        while o < #s - 9 do
            if s:byte(o) ~= 255 then o = o + 1;
            else
                local m = s:byte(o + 1);
                if m >= 192 and m <= 207 and m ~= 196 and m ~= 200 and m ~= 204 then h, w = be16(o + 5), be16(o + 7); break; end
                o = o + 2 + be16(o + 2);
            end
        end
    end
    if w and h and w > 0 and h > 0 then B.dims[name] = { w, h }; end
    return B.dims[name] or nil;
end
-- Behind the panel: the picture, cropped to fill it, then the background colour over it (strength: how much shows)
function TRF.BGI.draw(dl, x, y, w, h, r)
    local name = config.bg_img or '';
    if name == '' then return; end
    local tex = TRF.imageTex and TRF.imageTex(name);
    if tex == nil then return; end
    local d = TRF.BGI.size(name) or { w, h };
    local u0, v0, u1, v1 = 0, 0, 1, 1;
    local ia, pa = d[1] / d[2], w / h;
    if ia > pa then local k = pa / ia; u0, u1 = (1 - k) / 2, (1 + k) / 2;      -- (wider: trim the sides)
    else local k = ia / pa; v0, v1 = (1 - k) / 2, (1 + k) / 2; end            -- (taller: trim top and bottom)
    local st = math.max(0.05, math.min(1, tonumber(config.bg_img_alpha) or 0.45));
    local a = config.transparent and st * 0.6 or st;
    local ok = pcall(dl.AddImageRounded, dl, tex.ptr, { x, y }, { x + w, y + h }, { u0, v0 }, { u1, v1 }, u32({ 1, 1, 1, a }), r);
    if not ok then pcall(dl.AddImage, dl, tex.ptr, { x, y }, { x + w, y + h }, { u0, v0 }, { u1, v1 }, u32({ 1, 1, 1, a })); end
end
-- Settings > Colours: the picture
function TRF.BGI.settings()
    local B = TRF.BGI;
    B.poll();
    local x0 = imgui.GetCursorPosX();
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.text, 'Your picture');
    tip('A picture of your own behind the window (PNG, JPG or BMP)');
    imgui.SameLine(x0 + 130);
    if B.pending then
        imgui.TextColored(C.muted, 'Choose a picture in the window that opened...');
        imgui.SameLine(0, 10);
        if button('CANCEL##vengo_bgi_c', { 0, 0 }, true, true) then B.pending = nil; end
    else
        if button('CHOOSE PICTURE##vengo_bgi', { 0, 0 }, false, true) then B.choose(); end
        if (config.bg_img or '') ~= '' then
            imgui.SameLine(0, 10);
            if button('REMOVE##vengo_bgi_x', { 0, 0 }, true, true) then
                os.remove(addon.path .. 'images\\' .. config.bg_img);
                config.bg_img = '';
                saveSettings();
            end
        end
    end
    if (config.bg_img or '') ~= '' then
        if TRF.imageTex(config.bg_img) == nil then
            imgui.TextColored(C.gold, 'That picture couldn\'t be loaded. Try a smaller PNG or JPG (4096 pixels wide or less).');
        end
        TRF.slider('##vengo_bgi_a', 'Picture strength', 'bg_img_alpha', 0.05, 1.0, '%.2f', 'How much of the picture shows through the background colour (lower keeps text easier to read)');
    end
end

TRF.sliders = function()
    section('GPS');
    TRF.slider('##vengo_s_scale', 'Size', 'trail_scale', 0.4, 2.5, '%.2fx', 'How big the GPS shapes are (Small 0.70, Medium 1.00, Large 1.40)');
    TRF.slider('##vengo_s_space', 'Spacing', 'trail_spacing', 0.5, 3.0, '%.2fx', 'Space between the GPS shapes (arrows, runes or motes)');
    TRF.slider('##vengo_s_speed', 'Speed', 'trail_speed', 0, 15, '%.1f yalms/s', 'How fast the GPS moves toward the VNM (0: still, or slow for Runes, Light and Aether)');
    TRF.slider('##vengo_s_range', 'Reach', 'trail_range', 20, 150, '%.0f yalms', 'How far ahead of you the GPS is drawn');
    section('Performance');
    TRF.slider('##vengo_s_seal', 'Venture Seal: check its spot', 'seal_check', 0.05, 2.0, 'every %.2f s', 'How often the Seal\'s own slot is looked at, once it\'s been found');
    TRF.slider('##vengo_s_scan', 'Venture Seal: search for it', 'seal_scan', 0.1, 5.0, 'every %.2f s', 'How often the whole list is searched while the Seal hasn\'t been found yet (2,300 slots)');
    TRF.slider('##vengo_s_cam', 'Camera: read it', 'cam_every', 1, 5, 'every %d frame(s)', 'Every frame is smoothest; every 2-5 frames costs less (the GPS may lag a fast camera spin a moment)', true);
    TRF.slider('##vengo_s_glow', 'Glow passes', 'glow_q', 1, 2, '%d', '1: one soft pass (lighter)   2: fuller glow', true);
    hint('Lower numbers for the Seal and camera are faster and smoother but cost a little more. Lightweight mode (under Window) sets these in one click.');
end

-- Three preset slots: every setting, saved to vengo_presets.lua and loaded back with one click
TRF.PRESET_KEYS = { 'transparent', 'alerts', 'alert_chat', 'alert_popup', 'alert_voice', 'lang', 'alert_sound', 'alert90', 'mode', 'pool', 'sort', 'website', 'login_refresh', 'logo_anim', 'logo_style', 'logo_size', 'logo_clear',
    'trail', 'trail_glow', 'trail_full', 'trail_color', 'trail_style', 'trail_size', 'theme', 'bg', 'style', 'ph_accent', 'ph_slab', 'ph_edge', 'bg_img', 'bg_img_alpha', 'lite',
    'seal_check', 'seal_scan', 'cam_every', 'trail_range', 'trail_scale', 'trail_spacing', 'trail_speed', 'glow_q',
    'star_zones', 'star_items', 'dl_pins', 'star_chat', 'star_sound', 'check_updates' };
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
    hint('SAVE keeps every setting (colours, GPS, performance, alerts, window) in that slot; LOAD puts them all back.');
end

-- Are the arrows up for this venture right now?
TRF.trailShowing = function(v)
    return v ~= nil and TRAIL.v == v and TRAIL.stopped ~= v.key and zone() == v.zone and (config.trail or TRAIL.forced == v.key);
end

-- GO in the venture's zone: arrows on (even if the setting is off); STOP: arrows off. Forgotten when you leave the zone.
TRF.trailGo = function(v)
    if TRF.trailShowing(v) then
        TRAIL.stopped, TRAIL.forced = v.key, nil;
        msg(('GPS to %s off. Press GO to show it again.'):fmt(v.nm or 'the VNM'));
    else
        TRAIL.stopped, TRAIL.pick, TRAIL.zone_ = nil, v, zone();
        TRAIL.manual = v.key;                                     -- (shown even below 100%)
        if not config.trail then TRAIL.forced = v.key; end
        TRAIL.v = v;                                          -- (the button turns to STOP at once)
        msg(('GPS on: follow it to %s (%s).'):fmt(v.nm or 'the VNM', v.grid or '?'));
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

------------------------------------------------------------------------
-- GPS styles drawn on the ground (Settings > Trail to the VNM > GPS style): RUNES (rune circles joined by a line,
-- a brightness running out along them), LIGHT (one bright line from an orb at your feet) and AETHER (wisps, drifting
-- motes and a spirit light running the path). All three end in the same marker: rings on the ground, beams of
-- light rising from them and two chevrons pointing down at the spot. E: the path this frame (see drawTrail).
------------------------------------------------------------------------
TRF.GPS = { STYLES = { runes = true, light = true, aether = true } };
-- a point of the path: d along it, s across it, up above the ground -> screen x, y, depth
function TRF.GPS.pt(E, d, s, up)
    local x, y = E.px + E.ux * d + E.nx * (s or 0), E.py + E.uy * d + E.ny * (s or 0);
    if up and up ~= 0 then return project(above(x, y, E.ph, up)); end
    return project(toD3D(x, y, E.ph));
end
-- a circle lying on the ground, as screen points (nil if any of it is behind the camera)
function TRF.GPS.ring(wx, wy, h, r, segs, rot)
    local P = {};
    for i = 0, segs - 1 do
        local a = (rot or 0) + i / segs * math.pi * 2;
        local x, y = project(toD3D(wx + math.cos(a) * r, wy + math.sin(a) * r, h));
        if not x then return nil; end
        P[i + 1] = { x, y };
    end
    return P;
end
function TRF.GPS.loop(dl, P, col, th) for i = 1, #P do dl:AddLine(P[i], P[i % #P + 1], col, th); end end
function TRF.GPS.fan(dl, c, P, col) for i = 1, #P do dl:AddTriangleFilled(c, P[i], P[i % #P + 1], col); end end
-- a soft ball of light on the screen: its colour fading out, a white heart
function TRF.GPS.orb(dl, x, y, r, c, a)
    dl:AddCircleFilled({ x, y }, r * 2.6, u32({ c[1], c[2], c[3], 0.07 * a }), 20);
    dl:AddCircleFilled({ x, y }, r * 1.7, u32({ c[1], c[2], c[3], 0.16 * a }), 18);
    dl:AddCircleFilled({ x, y }, r, u32({ 0.45 + c[1] * 0.55, 0.45 + c[2] * 0.55, 0.45 + c[3] * 0.55, 0.75 * a }), 16);
    dl:AddCircleFilled({ x, y }, r * 0.5, u32({ 1, 1, 1, 0.95 * a }), 12);
end
-- a colour pushed toward white by b (0..1), with an alpha
function TRF.GPS.hot(c, b, a) return { c[1] + (1 - c[1]) * b, c[2] + (1 - c[2]) * b, c[3] + (1 - c[3]) * b, a }; end

-- RUNES: circles on the ground every few yalms (counted back from the VNM, so they stay put as you walk), each
-- two rings with rune marks between them and a four-point star, joined by a line; a brightness runs out along them
function TRF.GPS.runes(dl, E)
    local G, c = TRF.GPS, E.col;
    local every = 7 * E.SP * math.max(0.75, E.SZ);
    local r = 1.6 * E.SZ;
    local endd = math.min(E.len, E.dist - 3.4);
    local run = (E.now * math.max(3, E.speed) * 1.8) % (endd + 14);
    local base = math.atan2(E.uy, E.ux);
    local k = math.max(1, math.ceil((E.dist - endd) / every));
    while true do                                                -- (far to near, so the near ones are on top)
        local d = E.dist - k * every;
        if d < 2.2 then break; end
        local b = math.exp(-((d - run) / 4.5) ^ 2);              -- (the brightness passing over this one)
        local fade = 1 - (d / E.RANGE) * 0.55;
        local cx, cy, cw = G.pt(E, d);
        -- the line on to the next circle (or to the marker's ring)
        local fa = math.min(endd, d + every - r);
        if fa > d + r then
            local ax, ay = G.pt(E, d + r);
            local bx, by = G.pt(E, fa);
            if ax and bx then
                local th = cw and math.max(1.2, math.min(3, 46 / cw)) or 1.5;
                glowLine(dl, { ax, ay }, { bx, by }, G.hot(c, 0.25, 0.85 * fade), th, E.glow);
                if run > d + r and run < fa then                 -- (the bead of light on its way)
                    local hx, hy, hw = G.pt(E, run);
                    if hx then G.orb(dl, hx, hy, math.max(2, math.min(7, 90 / hw)) * E.SZ, c, fade); end
                end
            end
        end
        if cx then
            local wx, wy = E.px + E.ux * d, E.py + E.uy * d;
            local near = cw < 42;                                -- (close enough for the fine marks)
            local segs = near and 28 or 14;
            local P1 = G.ring(wx, wy, E.ph, r, segs, base);
            if P1 then
                local th = math.max(1.2, math.min(3.2, 52 / cw)) * (1 + b * 0.5);
                if E.glow then
                    G.fan(dl, { cx, cy }, P1, u32({ c[1], c[2], c[3], (0.07 + b * 0.30) * fade }));
                    G.loop(dl, P1, u32({ c[1], c[2], c[3], (0.16 + b * 0.20) * fade }), th * 2.8);
                end
                G.loop(dl, P1, u32(G.hot(c, 0.20 + b * 0.6, 0.95 * fade)), th);
                local P2 = G.ring(wx, wy, E.ph, r * 0.78, segs, base);
                if P2 then G.loop(dl, P2, u32(G.hot(c, 0.10 + b * 0.5, 0.75 * fade)), math.max(1, th * 0.55)); end
                if near then
                    local rot = base + E.now * 0.22 * ((k % 2 == 0) and 1 or -1);   -- (the marks turn slowly, every other one the other way)
                    local mc = u32(G.hot(c, 0.35 + b * 0.5, 0.85 * fade));
                    local mt = math.max(1, th * 0.5);
                    local function gp(a, rr) return project(toD3D(wx + math.cos(a) * rr, wy + math.sin(a) * rr, E.ph)); end
                    for i = 0, 11 do                             -- (twelve rune marks: a stroke, a hook, a fork or a bar)
                        local a = rot + i / 12 * math.pi * 2;
                        local x1, y1 = gp(a, r * 0.82);
                        local x2, y2 = gp(a, r * 0.96);
                        if x1 and x2 then
                            local kind = (i * 7 + k) % 4;
                            if kind ~= 3 then dl:AddLine({ x1, y1 }, { x2, y2 }, mc, mt); end
                            if kind == 1 then
                                local x3, y3 = gp(a + 0.11, r * 0.90);
                                if x3 then dl:AddLine({ x2, y2 }, { x3, y3 }, mc, mt); end
                            elseif kind == 2 then
                                local x3, y3 = gp(a + 0.10, r * 0.96);
                                local x4, y4 = gp(a - 0.10, r * 0.96);
                                if x3 and x4 then dl:AddLine({ x1, y1 }, { x3, y3 }, mc, mt); dl:AddLine({ x1, y1 }, { x4, y4 }, mc, mt); end
                            elseif kind == 3 then
                                local x3, y3 = gp(a - 0.09, r * 0.89);
                                local x4, y4 = gp(a + 0.09, r * 0.89);
                                if x3 and x4 then dl:AddLine({ x3, y3 }, { x4, y4 }, mc, mt); end
                            end
                        end
                    end
                    local P3 = G.ring(wx, wy, E.ph, r * 0.50, 14, base);
                    if P3 then G.loop(dl, P3, u32(G.hot(c, 0.15 + b * 0.5, 0.55 * fade)), math.max(1, th * 0.4)); end
                end
                -- the four-point star in the middle (long points along and across the path)
                local S = {};
                for i = 0, 7 do
                    local a = base + i * math.pi / 4;
                    local rr = (i % 2 == 0) and r * 0.40 or r * 0.12;
                    local x, y = project(toD3D(wx + math.cos(a) * rr, wy + math.sin(a) * rr, E.ph));
                    if not x then S = nil; break; end
                    S[i + 1] = { x, y };
                end
                if S then
                    G.fan(dl, { cx, cy }, S, u32(G.hot(c, 0.55 + b * 0.45, 0.92 * fade)));
                    if b > 0.25 then G.orb(dl, cx, cy, math.max(2, math.min(9, 110 / cw)) * E.SZ * b, c, fade); end
                end
            end
        end
        k = k + 1;
    end
end

-- LIGHT: one bright line along the ground from an orb at your feet, a brighter length of it racing out to the VNM
function TRF.GPS.light(dl, E)
    local G, c = TRF.GPS, E.col;
    local endd = math.min(E.len, E.dist - 3.4);
    local run = (E.now * math.max(3, E.speed) * 2.2) % (endd + 18);
    local lightg = (tonumber(config.glow_q) or 2) < 2;
    local lx, ly, lw, ld;
    local d = 1.6;
    while true do
        if d > endd then d = endd; end
        local x, y, w = G.pt(E, d);
        if x and lx then
            local fade = 1 - (d / E.RANGE) * 0.5;
            local b = math.exp(-((d - run) / 5) ^ 2);
            local th = math.max(2.2, math.min(9, 130 / ((w + lw) / 2))) * math.sqrt(E.SZ);
            local a, q = { lx, ly }, { x, y };
            if E.glow then
                dl:AddLine(a, q, u32({ c[1], c[2], c[3], (0.10 + b * 0.14) * fade }), th * (lightg and 2.6 or 3.4));
                if not lightg then dl:AddLine(a, q, u32({ c[1], c[2], c[3], (0.22 + b * 0.20) * fade }), th * 1.8); end
            end
            dl:AddLine(a, q, u32(G.hot(c, 0.25 + b * 0.5, 0.95 * fade)), th * 0.85);
            dl:AddLine(a, q, u32({ 1, 1, 1, (0.80 + b * 0.2) * fade }), math.max(1, th * 0.30));
        end
        lx, ly, lw, ld = x, y, w, d;
        if d >= endd then break; end
        d = d + 2.5;
    end
    if run < endd then                                           -- (the head of the racing light)
        local hx, hy, hw = G.pt(E, run);
        if hx then G.orb(dl, hx, hy, math.max(2.5, math.min(9, 120 / hw)) * E.SZ, c, 1 - (run / E.RANGE) * 0.5); end
    end
    -- the orb at your feet: two rings on the ground, a ball of light, a four-ray flare
    local sx, sy, sw = G.pt(E, 1.6);
    if sx then
        local wx, wy = E.px + E.ux * 1.6, E.py + E.uy * 1.6;
        local pl = 0.75 + 0.25 * math.sin(E.now * 3.2);
        for i, rr in ipairs({ 1.5, 0.95 }) do
            local P = G.ring(wx, wy, E.ph, rr * E.SZ, 28, 0);
            if P then
                if E.glow then G.loop(dl, P, u32({ c[1], c[2], c[3], 0.18 * pl }), 6 - i); end
                G.loop(dl, P, u32(G.hot(c, 0.3, (i == 1) and 0.9 or 0.6)), (i == 1) and 2.2 or 1.4);
            end
        end
        local r = math.max(4, math.min(13, 170 / sw)) * E.SZ;
        G.orb(dl, sx, sy, r, c, pl);
        local fl = u32({ 1, 1, 1, 0.75 * pl });
        dl:AddLine({ sx - r * 2.4, sy }, { sx + r * 2.4, sy }, fl, 1.4);
        dl:AddLine({ sx, sy - r * 1.6 }, { sx, sy + r * 1.6 }, fl, 1.4);
    end
end

-- AETHER: three faint wisps weaving along the ground, motes of light drifting on toward the VNM, and a spirit
-- light running the path with rings swirling round it
function TRF.GPS.aether(dl, E)
    local G, c = TRF.GPS, E.col;
    local endd = math.min(E.len, E.dist - 3.4);
    local lightg = (tonumber(config.glow_q) or 2) < 2;
    local function side(s, d)                                    -- (how far across wisp s is at d)
        local taper = math.max(0, math.min(1, d / 5, (endd - d) / 5));
        return (0.40 + 0.22 * s) * E.SZ * taper * math.sin(d * (0.11 + 0.035 * s) - E.now * (0.5 + 0.28 * s) + s * 2.1);
    end
    if E.glow then                                               -- (a faint haze down the middle)
        local lx, ly;
        local d = 1.2;
        while true do
            if d > endd then d = endd; end
            local x, y, w = G.pt(E, d);
            if x and lx then dl:AddLine({ lx, ly }, { x, y }, u32({ c[1], c[2], c[3], 0.07 * (1 - (d / E.RANGE) * 0.5) }), math.max(4, math.min(26, 380 / w)) * E.SZ); end
            lx, ly = x, y;
            if d >= endd then break; end
            d = d + 3;
        end
    end
    for s = 1, (lightg and 2 or 3) do
        local lx, ly;
        local d = 1.2;
        while d <= endd do
            local x, y, w = G.pt(E, d, side(s, d));
            if x and lx then
                local fade = 1 - (d / E.RANGE) * 0.5;
                local th = math.max(1.2, math.min(4.5, 70 / w)) * math.sqrt(E.SZ);
                if E.glow then dl:AddLine({ lx, ly }, { x, y }, u32({ c[1], c[2], c[3], 0.08 * fade }), th * 3.0); end
                dl:AddLine({ lx, ly }, { x, y }, u32(G.hot(c, 0.20, (0.42 - s * 0.08) * fade)), th * 0.55);
            end
            lx, ly = x, y;
            d = d + ((d < 30) and 1.3 or 2.4);                   -- (finer close to you, where the bends show)
        end
    end
    -- the motes: one every few yalms, drifting toward the VNM, bobbing and twinkling
    local every = 6 * E.SP;
    local drift = (E.now * math.max(1.5, E.speed) * 0.55) % every;
    local first = math.floor((E.now * math.max(1.5, E.speed) * 0.55) / every);
    local d, i = drift + 2, 0;
    while d < endd do
        local seed = (i - first) * 1.7;
        local x, y, w = G.pt(E, d, side(1, d) * 0.8, 0.35 + 0.22 * math.sin(E.now * 1.6 + seed));
        if x then
            local tw = 0.65 + 0.35 * math.sin(E.now * 3.1 + seed * 2.3);
            G.orb(dl, x, y, math.max(1.6, math.min(6, 80 / w)) * E.SZ, c, tw * (1 - (d / E.RANGE) * 0.5));
        end
        d = d + every;
        i = i + 1;
    end
    -- the spirit light, and the rings swirling on the ground under it
    local run = (E.now * math.max(3, E.speed) * 1.3) % (endd + 10);
    if run > 1 and run < endd then
        local wx, wy = E.px + E.ux * run, E.py + E.uy * run;
        local fade = 1 - (run / E.RANGE) * 0.5;
        for j = 1, 3 do                                          -- (three arcs, each most of a circle, turning at their own speed)
            local rr = (0.7 + 0.55 * j) * E.SZ;
            local a0 = E.now * (1.9 - j * 0.45) * ((j % 2 == 0) and -1 or 1) + j * 2;
            local lx, ly;
            for q = 0, 10 do
                local a = a0 + q / 10 * math.pi * 1.35;
                local x, y = project(toD3D(wx + math.cos(a) * rr, wy + math.sin(a) * rr, E.ph));
                if x and lx then dl:AddLine({ lx, ly }, { x, y }, u32({ c[1], c[2], c[3], (0.55 - j * 0.10) * fade * (q / 10) }), 2.4 - j * 0.4); end
                lx, ly = x, y;
            end
        end
        local x, y, w = G.pt(E, run, 0, 0.5);
        if x then G.orb(dl, x, y, math.max(4, math.min(15, 200 / w)) * E.SZ, c, fade); end
    end
end

-- The marker at the VNM's spot for these three: rings on the ground, beams of light rising from the outer one, and
-- two chevrons, one inside the other, pointing down at it. Returns where the name goes (above the chevrons).
function TRF.GPS.marker(dl, E)
    local G, c = TRF.GPS, E.col;
    local tx, ty, gh = E.tx, E.ty, E.gh;
    local mx, my, mw = project(toD3D(tx, ty, gh));
    if not mx then return nil; end
    local pl = 0.70 + 0.30 * math.sin(E.now * 3);
    local th = math.max(1.5, math.min(4, 60 / mw));
    local P1 = G.ring(tx, ty, gh, 3.2, 28, 0);
    if P1 then
        if E.glow then
            G.fan(dl, { mx, my }, P1, u32({ c[1], c[2], c[3], 0.10 * pl }));
            G.loop(dl, P1, u32({ c[1], c[2], c[3], 0.20 * pl }), th * 3);
        end
        G.loop(dl, P1, u32(G.hot(c, 0.35, 0.95)), th * 1.2);
    end
    local P2 = G.ring(tx, ty, gh, 2.3, 24, 0);
    if P2 then G.loop(dl, P2, u32(G.hot(c, 0.20, 0.75 * pl)), th * 0.7); end
    local P3 = G.ring(tx, ty, gh, 1.2, 16, 0);
    if P3 then
        G.fan(dl, { mx, my }, P3, u32(G.hot(c, 0.45, 0.45 * pl)));
        G.loop(dl, P3, u32(G.hot(c, 0.6, 0.9)), th * 0.8);
    end
    for i = 0, 11 do                                             -- (the beams: brightest at the ground, gone by 5 yalms up)
        local a = i / 12 * math.pi * 2 + 0.26;
        local bx, by = tx + math.cos(a) * 3.2, ty + math.sin(a) * 3.2;
        local fl = 0.55 + 0.45 * math.sin(E.now * 4 + i * 1.9);
        local top = 3.2 + 1.8 * (0.5 + 0.5 * math.sin(E.now * 2.3 + i * 2.7));
        local lx, ly = project(toD3D(bx, by, gh));
        for s, al in ipairs({ 0.55, 0.30, 0.12 }) do
            local x, y = project(above(bx, by, gh, top * s / 3));
            if x and lx then dl:AddLine({ lx, ly }, { x, y }, u32({ c[1], c[2], c[3], al * fl }), th * (1.5 - s * 0.3)); end
            lx, ly = x, y;
        end
    end
    -- the chevrons, facing you, bobbing above the spot (as tall on the screen as 4 yalms are there)
    local bob = 0.5 * math.sin(E.now * 2.4);
    local cx, cy = project(above(tx, ty, gh, 8.2 + bob));
    local _, ty2 = project(above(tx, ty, gh, 12.2 + bob));
    if not cx or not ty2 then return project(above(tx, ty, gh, 7)); end
    local s = math.max(10, math.min(90, math.abs(cy - ty2) * 0.5));
    local function chev(oy, sc, bright)
        local w, a, t = s * sc, s * sc * 0.78, s * sc * 0.36;   -- (half-width, drop from the ends to the point, thickness)
        local y0 = cy + oy;
        local L, B, R = { cx - w, y0 - a * 0.5 }, { cx, y0 + a * 0.5 }, { cx + w, y0 - a * 0.5 };
        local L2, B2, R2 = { L[1], L[2] + t }, { B[1], B[2] + t }, { R[1], R[2] + t };
        if E.glow then
            local g = u32({ c[1], c[2], c[3], 0.16 * pl });
            for _, e in ipairs({ { L, B }, { B, R }, { L2, B2 }, { B2, R2 } }) do dl:AddLine(e[1], e[2], g, math.max(4, s * 0.16)); end
        end
        local body = u32(G.hot(c, bright, 0.88));
        dl:AddQuadFilled(L, B, B2, L2, body);
        dl:AddQuadFilled(R, R2, B2, B, body);
        local core = u32({ 1, 1, 1, 0.55 });
        local m = t * 0.5;
        dl:AddLine({ L[1] + s * 0.04, L[2] + m }, { B[1], B[2] + m }, core, math.max(1, t * 0.22));
        dl:AddLine({ R[1] - s * 0.04, R[2] + m }, { B[1], B[2] + m }, core, math.max(1, t * 0.22));
        local rim = u32(G.hot(c, 0.7, 0.95));
        for _, e in ipairs({ { L, B }, { B, R }, { R, R2 }, { R2, B2 }, { B2, L2 }, { L2, L } }) do dl:AddLine(e[1], e[2], rim, math.max(1, s * 0.03)); end
    end
    chev(0, 1.0, 0.15);
    chev(s * 0.62, 0.60, 0.40);
    return cx, cy - s * 0.55;
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
        local style = config.trail_style or 'lines';
        if not TRF.GPS.STYLES[style] then style = 'lines'; end    -- (the neon bands and solid neon styles are gone: arrows)
        local SZ = tonumber(config.trail_scale) or 1.0;
        local SP = tonumber(config.trail_spacing) or 1.0;
        local mix = (config.trail_color == 'neon');
        local NEON_MIX = { { 0.25, 0.65, 1.00 }, { 1.00, 0.55, 0.20 }, { 0.68, 0.42, 1.00 }, { 0.20, 0.92, 0.85 } };
        local nx, ny = -uy, ux;                                -- across the path
        local phase = now * (tonumber(config.trail_speed) or 5);
        local gps = TRF.GPS.STYLES[style] and {                -- (RUNES, LIGHT, AETHER: the path this frame)
            px = px, py = py, ph = ph, ux = ux, uy = uy, nx = nx, ny = ny, dist = dist, len = len, RANGE = RANGE,
            col = col, glow = glow, SZ = SZ, SP = SP, now = now, speed = tonumber(config.trail_speed) or 5,
            tx = tx, ty = ty, gh = gh } or nil;

        if gps then
            pcall(TRF.GPS[style], dl, gps);
        elseif style == 'lines' then
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
        end

        -- the marker: a ring on the ground around the square's middle, a pole, a flag and the name
        local mx, my, mw = project(toD3D(tx, ty, gh));
        if mx and mx > -50 and mx < W + 50 and my > -50 and my < H + 50 then
            local pulse = 0.6 + 0.4 * math.sin(now * 3);
            local fx, fy;
            if gps then                                           -- (rings, beams and the chevrons pointing down)
                local ok, gx, gy = pcall(TRF.GPS.marker, dl, gps);
                if ok then fx, fy = gx, gy; end
            else
                local ring = {};
                for i = 0, 24 do
                    local a = i / 24 * math.pi * 2;
                    local rx, ry = project(toD3D(tx + math.cos(a) * 3, ty + math.sin(a) * 3, gh));
                    if rx then ring[#ring + 1] = { rx, ry }; end
                end
                for i = 2, #ring do glowLine(dl, ring[i - 1], ring[i], { col[1], col[2], col[3], 0.8 * pulse }, math.max(1.5, math.min(4, 60 / mw)), glow); end
                fx, fy = project(above(tx, ty, gh, 7));
                if fx then
                    glowLine(dl, { mx, my }, { fx, fy }, { C.mp2[1], C.mp2[2], C.mp2[3], 0.9 }, math.max(1.5, math.min(4, 60 / mw)), glow);
                    local fs = math.max(6, math.min(26, 400 / mw));
                    dl:AddTriangleFilled({ fx, fy }, { fx + fs, fy + fs * 0.35 }, { fx, fy + fs * 0.7 }, u32({ col[1], col[2], col[3], 1 }));
                end
            end
            if fx then
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
            'A glowing GPS trail on the ground from your feet to the VNM\'s grid square, in the venture\'s zone (and after GO)') then
        config.trail = not (config.trail ~= false);
        saveSettings();
    end
    if rowSwitch('##vengo_trail_full', 'Only when the VNM is at 100%', config.trail_full ~= false,
            'The GPS comes up on its own only once the zone\'s VNM is at 100% (or announced). Pressing GO in the zone still shows it any time.') then
        config.trail_full = not (config.trail_full ~= false);
        saveSettings();
    end
    if rowSwitch('##vengo_trail_glow', 'Glow', config.trail_glow ~= false, 'A soft glow around the GPS') then
        config.trail_glow = not (config.trail_glow ~= false);
        saveSettings();
    end
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.text, 'GPS style');
    imgui.SameLine(ROW_W - 400);
    local stl = pillChoice('##vengo_tstyle', { { 'lines', 'LINES' }, { 'runes', 'RUNES' }, { 'light', 'LIGHT' }, { 'aether', 'AETHER' } },
        TRF.GPS.STYLES[config.trail_style or ''] and config.trail_style or 'lines');
    if stl then config.trail_style = stl; saveSettings(); end
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.text, 'GPS size');
    imgui.SameLine(ROW_W - 400);
    local sc_ = tonumber(config.trail_scale) or 1;
    local szcur = (math.abs(sc_ - 0.7) < 0.01 and 'small') or (math.abs(sc_ - 1) < 0.01 and 'medium') or (math.abs(sc_ - 1.4) < 0.01 and 'large') or '';
    local szc = pillChoice('##vengo_tsize', { { 'small', 'SMALL' }, { 'medium', 'MEDIUM' }, { 'large', 'LARGE' } }, szcur);
    if szc then config.trail_size = szc; config.trail_scale = ({ small = 0.7, medium = 1.0, large = 1.4 })[szc]; saveSettings(); end
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.text, 'GPS colour');
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
            'A quick preset for the Performance sliders: camera every 3 frames, GPS to 60 yalms, one glow pass, the Seal checked every 0.5 s. Off puts the normal values back. Move any slider after to fine-tune.') then
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
    do                                                            -- (which icon VenGo shrinks to)
        imgui.AlignTextToFramePadding();
        imgui.TextColored(C.text, 'Icon');
        tip('What VenGo shrinks to. Lightning: the new lightning logo. Orb: the round orb from before.');
        imgui.SameLine(0, 12);
        local pick = pillChoice('##vengo_logo_style', { { 'bolt', 'LIGHTNING' }, { 'orb', 'ORB' } }, config.logo_style == 'orb' and 'orb' or 'bolt');
        if pick then config.logo_style = pick; saveSettings(); end
    end
    if rowSwitch('##vengo_logoclear', 'See-through logo', config.logo_clear ~= false,
            'Lightning: nothing behind it (off: a dark cloud behind it). Orb: its glass lets the game show through (off: solid).') then
        config.logo_clear = (config.logo_clear == false);
        saveSettings();
    end
    do                                                            -- (the logo's size, and a look at it without shrinking VenGo)
        local sz = math.max(0.4, math.min(3, tonumber(config.logo_size) or 1));
        local nsz = sz;
        imgui.AlignTextToFramePadding();
        imgui.TextColored(C.text, 'Logo size');
        imgui.SameLine(0, 12);
        if button('-##vengo_logo_m', { 34, 0 }, true, true) then nsz = sz - 0.1; end
        imgui.SameLine(0, 8);
        imgui.AlignTextToFramePadding();
        imgui.TextColored(C.text, ('%d%%'):fmt(math.floor(sz * 100 + 0.5)));
        imgui.SameLine(0, 8);
        if button('+##vengo_logo_p', { 34, 0 }, true, true) then nsz = sz + 0.1; end
        imgui.SameLine(0, 14);
        if button((TRF.logoPreview and 'HIDE PREVIEW' or 'PREVIEW') .. '##vengo_logo_v', { 0, 0 }, true, true) then TRF.logoPreview = not TRF.logoPreview; end
        tip('Shows the logo next to this window so you can see its size and background. Click the logo or this button to hide it.');
        nsz = math.max(0.4, math.min(3, math.floor(nsz * 10 + 0.5) / 10));
        if nsz ~= sz then config.logo_size = nsz; saveSettings(); end
    end
    hint('Drag the bottom-right corner to resize. The  -  button at the top right shrinks VenGo to a small tag.');

    section('Colours');
    local function swatches(id, list, cur, draw)
        local dl = imgui.GetWindowDrawList();
        local picked = nil;
        local fit = math.max(4, math.floor((ROW_W - 130) / 34));    -- (how many fit in a row beside the label)
        local per = math.ceil(#list / math.ceil(#list / fit));      -- (rows of even length)
        local x0 = imgui.GetCursorPosX();
        for i, e in ipairs(list) do
            if (i - 1) % per == 0 then imgui.SameLine(x0 + 130); end
            local x, y = imgui.GetCursorScreenPos();
            local h = imgui.GetFrameHeight();
            if imgui.InvisibleButton(id .. e[1], { 30, h }) then picked = e[1]; end
            local cx, cy = x + 15, y + h / 2;
            draw(dl, cx, cy, e);
            if (cur or list[1][1]) == e[1] then dl:AddCircle({ cx, cy }, 12.5, u32({ 1, 1, 1, 0.9 }), 24, 1.5); end
            if imgui.IsItemHovered() then imgui.SetTooltip(e[2]); end
            if i < #list and i % per ~= 0 then imgui.SameLine(0, 4); end
            if i < #list and i % per == 0 then imgui.Dummy({ 1, 0 }); end   -- (next row)
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
    -- the style: VenGo's own, or Phantom (red, black and white, slanted)
    local sx0 = imgui.GetCursorPosX();
    imgui.AlignTextToFramePadding();
    imgui.TextColored(C.text, 'Style');
    tip('Classic: VenGo\'s own look. Phantom: red, black and white, slanted, with cut-out titles (like ChadcoreMenu\'s Phantom style). Neon: ChadcoreMenu\'s Neon look: dark slabs in a glowing line, serif titles with an icon and the Japanese under them, a spark running round the title.');
    imgui.SameLine(sx0 + 130);
    local stl = pillChoice('##vengo_style', { { 'classic', 'CLASSIC' }, { 'phantom', 'PHANTOM' }, { 'neon', 'NEON' } }, config.style or 'classic');
    if stl then config.style = stl; C.apply(); saveSettings(); end
    if TRF.PH.on() then                                           -- (Phantom's own picks: accent, slab, edge)
        local P = TRF.PH;
        local function L(src) local out = {}; for _, e in ipairs(src) do out[#out + 1] = { e[1], e[1], e[2], e[3], e[4] }; end return out; end
        imgui.AlignTextToFramePadding();
        imgui.TextColored(C.text, 'Accent');
        local pa = swatches('##vengo_pha_', L(P.ACC), config.ph_accent or 'Red', function (dl, cx, cy, e)
            dl:AddCircleFilled({ cx, cy }, 11, u32({ e[3][1], e[3][2], e[3][3], 0.25 }), 24);
            half(dl, cx, cy, 8, math.pi * 0.75, e[3]);
            half(dl, cx, cy, 8, math.pi * 1.75, e[4]);
        end);
        if pa then config.ph_accent = pa; C.apply(); saveSettings(); end
        imgui.AlignTextToFramePadding();
        imgui.TextColored(C.text, 'Slab');
        local ps = swatches('##vengo_phs_', L(P.SLAB), config.ph_slab or 'Black', function (dl, cx, cy, e)
            dl:AddCircleFilled({ cx, cy }, 9, u32({ e[3][1], e[3][2], e[3][3], 1 }), 24);
            dl:AddCircle({ cx, cy }, 9, u32({ 1, 1, 1, 0.35 }), 24, 1);
        end);
        if ps then config.ph_slab = ps; C.apply(); saveSettings(); end
        if not TRF.NE.on() then                                   -- (Neon has no white edge)
        imgui.AlignTextToFramePadding();
        imgui.TextColored(C.text, 'Edge');
        local pe = swatches('##vengo_phe_', L(P.EDGE), config.ph_edge or 'White', function (dl, cx, cy, e)
            dl:AddCircleFilled({ cx, cy }, 9, u32({ e[3][1], e[3][2], e[3][3], 1 }), 24);
            dl:AddCircle({ cx, cy }, 9, u32({ 1, 1, 1, 0.35 }), 24, 1);
        end);
        if pe then config.ph_edge = pe; C.apply(); saveSettings(); end
        end
    else
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
    end
    pcall(TRF.BGI.settings);
    hint('Accent: the edges, highlights, switches and bars. Background: the panel itself. Your picture sits on the panel; the strength slider sets how much of it shows. See-through mode still works with every colour.');

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
    if rowSwitch('##vengo_alert_chat', 'Chat notifications', config.alert_chat ~= false,
            'VNM alerts, the minute-to-pop warning, the 90% heads-up and starred-VNM warnings as chat lines. Off: they only show in VenGo.') then
        config.alert_chat = not (config.alert_chat ~= false);
        saveSettings();
    end
    if rowSwitch('##vengo_alert_pop', 'Pop-up notification', config.alert_popup ~= false,
            'The VNM INCOMING window with GO and DISMISS. Off: no window; the alert still shows in VenGo (and the orb glows).') then
        config.alert_popup = not (config.alert_popup ~= false);
        saveSettings();
    end
    pcall(TRF.VO.settings);
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
    if ALERT == nil or ALERT.dismissed or config.alert_popup == false then return; end
    local v = ALERT.v;
    local starred = TRF.ST and TRF.ST.watched(v) or false;
    local gc = starred and C.gold or NEON2;                       -- (the glow: gold for a starred VNM)
    local nc, nv = pushTheme();
    local pulse = 0.55 + 0.45 * math.sin(os.clock() * 4);
    local ph = TRF.PH.on();
    if ph then gc = starred and C.gold or C.hp; end
    imgui.PushStyleColor(ImGuiCol_WindowBg, { 0.05, 0.04, 0.07, ph and 0 or (config.transparent and 0.70 or 0.95) });
    imgui.PushStyleColor(ImGuiCol_Border, { gc[1], gc[2], gc[3], ph and 0 or (0.65 + 0.35 * pulse) });
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, ph and { 30, 20 } or { 22, 16 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, ph and 0 or 3);
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 10);
    nc, nv = nc + 2, nv + 3;
    local ds = imgui.GetIO().DisplaySize;
    imgui.SetNextWindowPos({ ((ds and ds.x) or 1920) / 2, 70 }, ImGuiCond_FirstUseEver, { 0.5, 0 });
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoFocusOnAppearing);
    local pushed = pushFont(fonts.panel, 16);
    if imgui.Begin('VenGo alert##vengo_alert', { true }, flags) then
        local dl = imgui.GetWindowDrawList();
        if ph then                                                -- (Phantom: the slanted slab, drawn behind what follows)
            local wx, wy = imgui.GetWindowPos();
            local ww, wh = imgui.GetWindowSize();
            TRF.PH.alertFrame(dl, wx + 6, wy + 6, ww - 12, wh - 12, gc, pulse);
        end
        -- a bright glow all round the banner, behind it, pulsing
        if not ph then pcall(function ()
            local wx, wy = imgui.GetWindowPos();
            local ww, wh = imgui.GetWindowSize();
            local bg = imgui.GetBackgroundDrawList and imgui.GetBackgroundDrawList() or nil;
            if bg == nil then return; end
            for i = 1, 9 do
                local g = i * 2.4;
                local a = (0.20 - i * 0.02) * (0.55 + 0.45 * pulse) * (starred and 1.3 or 1);
                bg:AddRect({ wx - g, wy - g }, { wx + ww + g, wy + wh + g }, u32({ gc[1], gc[2], gc[3], math.max(0, a) }), 10 + g, C.rall, 3);
            end
        end); end
        local x0, y0 = imgui.GetCursorScreenPos();
        local lh = imgui.GetTextLineHeight();
        local sx = x0;
        if starred then                                          -- (a gold star before the title)
            TRF.ST.draw(dl, x0 + 7, y0 + lh / 2, 7, { C.gold[1], C.gold[2], C.gold[3], 0.7 + 0.3 * pulse }, true);
            sx = x0 + 20;
        end
        if ph then                                                -- (Phantom: the title in cut-out letters)
            local bw, bh = TRF.PH.title(dl, sx - 4, y0 - 4, starred and 'Starred VNM!' or 'VNM incoming!', 0.8,
                starred and C.gold or nil, starred);              -- (starred: gold, on a star)
            imgui.Dummy({ math.max(bw, 200) + (sx - x0), bh });
        else
            local w = spaced(dl, sx, y0, starred and 'STARRED VNM INCOMING' or 'VNM INCOMING',
                u32({ gc[1], gc[2], gc[3], 0.7 + 0.3 * pulse }), 3);
            imgui.Dummy({ w + (sx - x0), lh });
        end

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

        local porter = tostring(v.notes or ''):match('%f[%a]([NSEW][EW]?)%s+[Pp]orter');   -- (Alzadaal: "SE porter" -> SE)
        imgui.TextColored(C.acc, ('%s  (%s)%s'):fmt(v.zone_name, v.grid or '?', porter and ('  ' .. porter) or ''));
        if porter and imgui.IsItemHovered() then imgui.SetTooltip(('Take the %s porter (%s)'):fmt(porter, v.notes)); end
        local d = dropsOf(v);
        if d ~= '' then
            imgui.TextColored(C.muted, 'Drops');
            imgui.SameLine();
            imgui.PushTextWrapPos(imgui.GetCursorPosX() + 360);
            imgui.TextColored(C.seal, d);
            imgui.PopTextWrapPos();
        end
        local crest = (v.crest and v.crest ~= '') and v.crest or TRF.crestOf(v.zone_name);
        if crest and TRF.CRESTC[crest] then                       -- (the crest it drops, in its armour set's colour)
            if d ~= '' then imgui.SameLine(0, 10); else imgui.TextColored(C.muted, 'Drops'); imgui.SameLine(); end
            imgui.TextColored(TRF.CRESTC[crest], crest .. ' Crest');
        end
        local left = ALERT.pop_at - os.time();
        imgui.TextColored(left <= 60 and { C.hp[1], C.hp[2], C.hp[3], 1 } or C.active, popWords(left));
        imgui.Spacing();
        local padCmd = TRF.PAD.alertCmd;                         -- (LB + A / LB + B on a controller)
        TRF.PAD.alertCmd = nil;
        if padCmd == 'dismiss' then ALERT.dismissed = true;
        elseif padCmd == 'go' then
            if isActive(v) then ARMED = nil; msg('Cancelled.'); else warpTo(v); end
        end
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
        if TRF.PAD.present() then TRF.PAD.alertHint(isActive(v) and 'CANCEL' or (TRF.trailShowing(v) and 'STOP' or 'GO')); end
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
    local sc = math.max(0.4, math.min(3, tonumber(config.logo_size) or 1));   -- (its size: Settings, or drag its corner)
    local R = 34 * sc;                                -- the orb's radius
    local S = math.floor((R + 16 * sc) * 2);          -- the window (room for the rings, glow and badge)
    local lg = (config.logo_style ~= 'orb') and TRF.imageTex('logo_bolt.png') or nil;         -- (the lightning logo: 9 frames, 4 a row, 512 x 340 each)
    local LW, LH = S, S;
    if lg then LW, LH = math.floor(200 * sc), math.floor(132 * sc); end
    if MINI.x then imgui.SetNextWindowPos({ MINI.x, MINI.y }, ImGuiCond_Always);
    else imgui.SetNextWindowPos({ 240, 160 }, ImGuiCond_FirstUseEver); end
    imgui.SetNextWindowSize({ LW, LH }, ImGuiCond_Always);
    if imgui.Begin('VenGo##vengo_mini', { true }, flags) then
        local dl = imgui.GetWindowDrawList();
        local wx, wy = imgui.GetWindowPos();
        MINI.x, MINI.y = wx, wy;
        local cx, cy = wx + LW / 2, wy + LH / 2;
        local t = os.clock();
        local clear = config.transparent;
        local running = ARMED ~= nil;
        local hot = ALERT ~= nil;

        if lg then
            -- THE LIGHTNING LOGO: bolts gather into "VenGo" (9 frames, 0.15 s each), which then holds, breathing,
            -- and strikes again every 9 s (every 3 s while warping or during an alert, with a glow in its colour)
            if MINI.born == nil or t - (MINI.seen or 0) > 0.5 then MINI.born = t; end   -- (just shrunk to it: it strikes)
            MINI.seen = t;
            local period = (hot or running) and 3 or 9;
            local e = (t - MINI.born) % period;
            local fr = config.logo_anim and math.min(8, math.floor(e / 0.15)) or 8;
            if config.logo_clear == false then                    -- (see-through off: a dark cloud behind it)
                for k = 1, 4 do
                    local q = 1 - (k - 1) * 0.2;
                    pcall(function ()
                        dl:AddEllipseFilled({ cx, cy }, { LW * 0.46 * q, LH * 0.36 * q }, u32({ 0.02, 0.02, 0.05, 0.20 }), 0, 40);
                    end);
                end
            end
            if hot then                                           -- (an alert: a pulse of its colour round it)
                local gp = 0.5 + 0.5 * math.sin(t * 5);
                for k = 1, 3 do
                    pcall(function ()
                        dl:AddEllipse({ cx, cy }, { LW * 0.44 + k * 2, LH * 0.34 + k * 2 }, u32({ NEON2[1], NEON2[2], NEON2[3], 0.14 * (4 - k) * gp }), 0, 40, 2.5);
                    end);
                end
            end
            local col, row = fr % 4, math.floor(fr / 4);
            local u0, v0 = (col * 512 + 2) / 2048, (row * 340 + 2) / 1024;
            local u1, v1 = (col * 512 + 510) / 2048, (row * 340 + 338) / 1024;
            local w, h = LW - 8, (LW - 8) * 336 / 508;
            local breathe = (fr == 8 and config.logo_anim) and (0.90 + 0.10 * math.sin(t * 2.2)) or 1;
            pcall(dl.AddImage, dl, lg.ptr, { cx - w / 2, cy - h / 2 }, { cx + w / 2, cy + h / 2 }, { u0, v0 }, { u1, v1 }, u32({ 1, 1, 1, breathe }));
            R = LH / 2 - 12;                                      -- (the place to click)
        else

        -- soft glow around it (stronger and pinker during an alert)
        local gcol = hot and NEON2 or LILAC;
        local gpulse = hot and (0.6 + 0.4 * math.sin(t * 5)) or 1;
        if not config.logo_anim then t = 0.6; end                 -- ("Animate the logo" off: the rings, colours and shimmer hold still; an alert still pulses)
        for k = 1, 5 do
            dl:AddCircle({ cx, cy }, R + (3 + k * 2) * sc, u32({ gcol[1], gcol[2], gcol[3], 0.06 * (6 - k) * gpulse }), 48, 2.5 * sc);
        end

        -- the two light rings, turning opposite ways, their colour drifting blue <-> violet
        local u = 0.5 + 0.5 * math.sin(t * 0.8);
        local c1 = hot and mix(NEON2, LILAC, u) or mix(ICE, LILAC, u);
        local c2 = hot and mix(LILAC, NEON2, u) or mix(LILAC, ICE, u);
        local spin = running and 2.4 or 1.3;
        local a1 = t * spin;
        arc(dl, cx, cy, R + 7 * sc, a1, a1 + 3.6, u32({ c1[1], c1[2], c1[3], 0.95 }), 2.2 * sc);
        arc(dl, cx, cy, R + 7 * sc, a1 + 3.6, a1 + 3.9, u32({ c1[1], c1[2], c1[3], 0.35 }), 1.6 * sc);   -- (its fading tail)
        local a2 = -t * spin * 0.7 + 1.5;
        arc(dl, cx, cy, R + 11 * sc, a2, a2 + 2.2, u32({ c2[1], c2[2], c2[3], 0.80 }), 1.6 * sc);

        -- the orb: dark glass with a silver rim
        dl:AddCircleFilled({ cx, cy }, R, u32({ 0.045, 0.042, 0.065, (config.logo_clear ~= false) and 0.40 or 0.97 }), 48);   -- (See-through logo: the glass lets the game through)
        dl:AddCircle({ cx, cy }, R, u32({ 0.62, 0.62, 0.70, 0.95 }), 48, 3.2 * sc);
        dl:AddCircle({ cx, cy }, R - 2.5 * sc, u32({ 0.25, 0.24, 0.32, 0.9 }), 48, 1.2 * sc);
        arc(dl, cx, cy, R, math.pi * 1.05, math.pi * 1.55, u32({ 1, 1, 1, 0.85 }), 2.0 * sc);       -- (a highlight on the rim)
        -- gloss: a faint light in the upper left
        dl:AddCircleFilled({ cx - R * 0.32, cy - R * 0.38 }, R * 0.42, u32({ 1, 1, 1, 0.05 }), 32);
        dl:AddCircleFilled({ cx - R * 0.38, cy - R * 0.45 }, R * 0.22, u32({ 1, 1, 1, 0.06 }), 24);
        -- a soft pink glow under the word, breathing
        local br = 0.10 + 0.08 * (0.5 + 0.5 * math.sin(t * 2));
        dl:AddCircleFilled({ cx, cy + 2 * sc }, R * 0.62, u32({ NEON[1], NEON[2], NEON[3], br }), 32);

        -- "VenGo", sized to fit, Go shimmering
        local pushed = pushFont(fonts.title, 24 * sc);
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
        end

        local ready = 0;                              -- (how many VNMs are at 100%, for the tooltip)
        for _, v in ipairs(ventures) do if (v.progress or 0) >= 100 then ready = ready + 1; end end

        -- click / drag
        do                                                        -- (its corner: drag to resize, either icon)
            local mx, my = imgui.GetMousePos();
            local over = mx >= wx and mx <= wx + LW and my >= wy and my <= wy + LH;
            imgui.SetCursorScreenPos({ wx + LW - 20, wy + LH - 20 });
            imgui.InvisibleButton('##vengo_mini_grip', { 18, 18 });
            local gact = imgui.IsItemActive();
            if gact and imgui.IsMouseDragging(0, 1) then
                local io = imgui.GetIO();
                config.logo_size = math.max(0.4, math.min(3, sc + ((io.MouseDelta.x or 0) / 200 + (io.MouseDelta.y or 0) / 132) / 2));
                MINI.sized = true;
            end
            if imgui.IsItemDeactivated() and MINI.sized then MINI.sized = false; saveSettings(); end
            if over or gact then
                local gc = u32({ 0.75, 0.80, 1, (gact or imgui.IsItemHovered()) and 0.95 or 0.45 });
                for k = 0, 2 do dl:AddLine({ wx + LW - 5 - k * 5, wy + LH - 3 }, { wx + LW - 3, wy + LH - 5 - k * 5 }, gc, 1.5); end
            end
            if imgui.IsItemHovered() then imgui.SetTooltip('Drag to resize'); end
        end
        local bw = lg and (LW / 2 - 22) or (R + 6 * sc);
        imgui.SetCursorScreenPos({ cx - bw, cy - R - 6 });
        imgui.InvisibleButton('##vengo_mini_btn', { bw * 2, (R + 6) * 2 });
        local hovered, active, released = imgui.IsItemHovered(), imgui.IsItemActive(), imgui.IsItemDeactivated();
        if hovered and lg and not MINI.wasHover then MINI.born = os.clock(); end   -- (pointing at it: it strikes again)
        MINI.wasHover = hovered;
        if hovered then
            if not lg then dl:AddCircle({ cx, cy }, R + 1, u32({ 1, 1, 1, 0.35 }), 48, 1.5 * sc); end
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
                if config.minimized then config.minimized = false; saveSettings();
                else TRF.logoPreview = false; end                 -- (the preview: a click hides it)
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
    if config.strip then TRF.drawStrip(); return; end
    if config.minimized then TRF.logoPreview = false; drawMini(); return; end
    if TRF.logoPreview then pcall(drawMini); end                  -- (Settings > Window > PREVIEW)
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
            elseif ui.tab == 7 then TRF.dlTab();
            elseif ui.tab == 8 then TRF.ptTab();
            elseif ui.tab == 9 then TRF.armorTab();
            elseif ui.tab == 10 then TRF.ulTab();
            elseif ui.tab == 11 then TRF.luTab();
            elseif ui.tab == 12 then TRF.cxTab();
            elseif ui.tab == 13 then TRF.svTab();
            elseif ui.tab == 14 then tabSettings();
            elseif ui.tab == 15 then tabThanks();
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
    pcall(TRF.LANG.frame);
    if TRF.SV.job then pcall(TRF.SV.tick); end
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
    pcall(TRF.DL.tracker);
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
        if (config.minimized or config.strip) and ui.open[1] then
            config.minimized, config.strip = false, false;
            saveSettings();
        else
            ui.open[1] = not ui.open[1];
        end
    elseif cmd == 'help' then
        msg('Usage: /vengo (window) | <nm|zone|shorthand> (warp there) | current | next | cancel | ventures | mode ace|cw | update | reload | testalert | where | dailies | points | sparks | pad (controller) | upgrade (install a new VenGo)');
    elseif cmd == 'dailies' then
        ui.open[1], ui.tab = true, 7;
    elseif cmd == 'points' then
        ui.open[1], ui.tab = true, 8;
    elseif cmd == 'sparks' then
        ui.open[1], ui.tab = true, 13;
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
    if e ~= nil and (e.id == 0x110 or e.id == 0x113 or e.id == 0x034 or e.id == 0x05C) then   -- (SPARK VENDOR)
        local ok, keep = pcall(TRF.SV.packet, e.id, e.data_modified or e.data);
        if ok and keep then e.blocked = true; end
        return;
    end
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
    pcall(TRF.DL.text, e.message);                                  -- (DAILIES)
end);

-- DAILIES: when you last handed something over, to tell Palalumin's item turn-in from his other quests
ashita.events.register('packet_out', 'vengo_dl_out', function (e)
    if e ~= nil and e.id == 0x0036 then TRF.DL.tradeAt = os.clock(); end
end);

pcall(function ()
    vana.on('logout', function () LOGIN_ASK.done, LOGIN_ASK.at = false, nil; end);
    vana.on('login', function () LOGIN_ASK.done, LOGIN_ASK.at = false, nil; end);
end);

ashita.events.register('load', 'vengo_load', function ()
    loadFonts();
    loadSettings();
    if config.lang == 'jp' then pcall(TRF.LANG.load); end
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

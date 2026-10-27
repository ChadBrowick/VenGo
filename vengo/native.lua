--[[
native.lua: YunaUI's start-up as a VanaCore addon (yunaui.lua runs it first, with YunaUI's folder).

YunaUI's code is written with Ashita's addon API names (AshitaCore, ashita.*, require('imgui'/'settings'/'chat'/'d3d8')).
VanaCore turns those names into its own vana.* API for the Ashita addons it runs, with its Lua "Compatibility layer"
inside VanaCore.Core.dll. This runs that same layer for YunaUI (read from the VanaCore.Core.dll installed now: nothing
of it is copied here), points require at VanaCore's copies of Ashita's libraries, and leaves `vana` as it is, so YunaUI
has both.
--]]

local dir = ...;
local SEP = '\\';
local LIBS = vana.paths.addons .. SEP .. 'vanacore' .. SEP .. 'libs';
local MARK = '--[[\r\nCompatibility layer: lets addons written for the Ashita v4';

-- VanaCore's Ashita layer, as it runs it for Ashita addons
do
    local f = assert(io.open(vana.paths.install .. SEP .. 'VanaCore.Core.dll', 'rb'), 'YunaUI: VanaCore.Core.dll not found');
    local data = f:read('*a');
    f:close();
    local s = data:find(MARK, 1, true);
    assert(s ~= nil, 'YunaUI: this VanaCore has no Ashita layer to run');
    local e = data:find('\0', s, true) or (#data + 1);
    local source = data:sub(s, e - 1);
    data = nil;
    assert(loadstring(source, '=VanaCore compat/ashita.lua'))();
end

-- Where Ashita addons find their libraries in VanaCore: their own folder, then Ashita 4.30's libraries (4.16's with
-- [addons] ashita.libs=4.16), then what both share
do
    local v = (vana.ashita and tonumber(vana.ashita.libs)) or 4.30;
    local parts = {};
    for _, d in ipairs({ dir, LIBS .. SEP .. ((v > 4.2) and 'ashita-4.30' or 'ashita-4.16'), LIBS .. SEP .. 'ashita' }) do
        parts[#parts + 1] = d .. SEP .. '?.lua';
        parts[#parts + 1] = d .. SEP .. '?' .. SEP .. 'init.lua';
    end
    package.path = table.concat(parts, ';') .. ';' .. package.path;
end

-- Ashita's 'command' handlers say "handled" with e.blocked = true; VanaCore's own say it by returning true
do
    local register = ashita.events.register;
    ashita.events.register = function(name, key, fn)
        if tostring(name):lower() == 'command' and type(fn) == 'function' then
            local inner = fn;
            fn = function(e)
                inner(e);
                return type(e) == 'table' and e.blocked == true;
            end;
        end
        return register(name, key, fn);
    end;
end

addon.path = dir .. SEP;                  -- YunaUI's folder, with the trailing backslash Ashita's has
YUI_NATIVE = true;

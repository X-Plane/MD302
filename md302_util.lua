-- Copyright (c) 2026 Tiezheng Eric Xu, erix@x-plane.com, Laminar Research - MIT License, see LICENSE
--
-- md302_util.lua: math, paths, config.ini, dataref/command helpers.
-- Loaded by MD302.lua through load_module(); shares the master script's environment.

local U = {}

U.LOG_PREFIX = "[MD302 XLua2] "

function U.log(msg)
    print(U.LOG_PREFIX .. tostring(msg))
end

-----------------------------------------------------------------------------
-- Math
-----------------------------------------------------------------------------

function U.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function U.wrap360(a)
    a = a % 360
    if a < 0 then a = a + 360 end
    return a
end

-- signed a - b in [-180, 180)
function U.angdiff(a, b)
    local d = (a - b + 180) % 360
    if d < 0 then d = d + 360 end
    return d - 180
end

-- move v toward target at rate units/second
function U.approach(v, target, rate, dt)
    local step = rate * dt
    if v < target then
        v = v + step
        if v > target then v = target end
    elseif v > target then
        v = v - step
        if v < target then v = target end
    end
    return v
end

-- CSS-style cubic-bezier easing curve through (0,0), (x1,y1), (x2,y2), (1,1):
-- returns f(t) for t in 0..1 (x solved by bisection, monotonic for x1, x2 in 0..1)
function U.bezier(x1, y1, x2, y2)
    return function(t)
        if t <= 0 then return 0 end
        if t >= 1 then return 1 end
        local lo, hi, s = 0, 1, t
        for _ = 1, 24 do
            s = (lo + hi) / 2
            local u = 1 - s
            if 3 * u * u * s * x1 + 3 * u * s * s * x2 + s * s * s < t then lo = s else hi = s end
        end
        local u = 1 - s
        return 3 * u * u * s * y1 + 3 * u * s * s * y2 + s * s * s
    end
end

-- t in 0..1 with f(t) = v, for a rising curve f
function U.inverse(f, v)
    if v <= 0 then return 0 end
    if v >= 1 then return 1 end
    local lo, hi = 0, 1
    for _ = 1, 24 do
        local m = (lo + hi) / 2
        if f(m) < v then lo = m else hi = m end
    end
    return (lo + hi) / 2
end

-- on/off flashing from a running clock (s): true for the first half of each period
function U.blink(t, period)
    period = period or 1
    return (t % period) < period / 2
end

function U.sign(v)
    if v > 0 then return 1 elseif v < 0 then return -1 end
    return 0
end

function U.round(v)
    return math.floor(v + 0.5)
end

-----------------------------------------------------------------------------
-- Paths
-----------------------------------------------------------------------------

function U.unwrap_string(v)
    if type(v) == "table" then
        return v[1] or v.outPath or v.outFileName or v.outSystemPath or ""
    end
    return v or ""
end

function U.normalize_path(path)
    local p = (path or ""):gsub("\\", "/")
    return p
end

function U.dirname(path)
    path = U.normalize_path(path)
    return path:match("^(.*)/[^/]*$") or ""
end

function U.join(a, b)
    if a == "" then return b end
    if string.sub(a, -1) == "/" then return a .. b end
    return a .. "/" .. b
end

function U.file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

-- Atlas/font paths must be X-Plane-root relative with forward slashes.
function U.xp_relative(path)
    path = U.normalize_path(path)
    local sys = XPLMGetSystemPath()
    local root = U.normalize_path(U.unwrap_string(type(sys) == "table" and sys.outSystemPath or sys))
    if root ~= "" then
        if string.sub(root, -1) ~= "/" then root = root .. "/" end
        if string.lower(string.sub(path, 1, #root)) == string.lower(root) then
            return string.sub(path, #root + 1)
        end
    end
    return path
end

-----------------------------------------------------------------------------
-- config.ini / settings.ini: [section] lines ignored, ';' and '#' comments (at the
-- start of a line or after a space), key = value.
-- Only keys that already exist in `defaults` are accepted, coerced to the
-- default's type.
-----------------------------------------------------------------------------

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- where a comment starts: ';' or '#' at the start of the line or after a
-- space, so a value may hold one (ssec_file = my#table.csv); nil = none
local function comment_pos(line)
    if line:find("^%s*[;#]") then return (line:find("[;#]")) end
    local p = line:find("%s[;#]")
    return p and p + 1
end

-- seen (optional): the keys the file has, set true
function U.read_ini(path, defaults, seen)
    local f = io.open(path, "r")
    if not f then
        U.log(path:match("[^/\\]+$") .. " not found, using defaults: " .. path)
        return false
    end
    for line in f:lines() do
        local cpos = comment_pos(line)
        local s = trim(cpos and line:sub(1, cpos - 1) or line)
        if s ~= "" and string.sub(s, 1, 1) ~= "[" then
            local key, value = s:match("^([^=]+)=(.*)$")
            if key then
                key = string.lower(trim(key))
                value = trim(value)
                local d = defaults[key]
                if seen and d ~= nil then seen[key] = true end
                if d == nil then
                    U.log(path:match("[^/\\]+$") .. ": unknown key '" .. key .. "' ignored")
                elseif type(d) == "number" then
                    local n = tonumber(value)
                    if n == nil then
                        U.log(path:match("[^/\\]+$") .. ": " .. key .. " = '" .. value .. "' is not a number, using "
                            .. tostring(d))
                    end
                    defaults[key] = n or d
                elseif type(d) == "boolean" then
                    local v = string.lower(value)
                    defaults[key] = (v == "1" or v == "true" or v == "yes" or v == "on")
                else
                    defaults[key] = value
                end
            end
        end
    end
    f:close()
    return true
end

-- Write `text` to `path`; true only when every byte reached the file (a full
-- disk shows up at the close).
local function write_file(path, text)
    local f = io.open(path, "wb")
    if not f then return false end
    local written = f:write(text)
    local closed = f:close()
    return written ~= nil and closed ~= nil and closed ~= false
end

-- Replace an ini file with `text` without ever losing it: the text goes to
-- <path>.tmp first, the old file becomes <path>.bak (kept: the version before
-- the last save) and the copy is renamed into place. The original is never
-- deleted before its replacement is in place; U.ini_recover puts the .tmp or
-- .bak back if X-Plane or Windows stopped in between. When the old file
-- cannot be moved (a .bak that cannot be replaced), the text is written in
-- place and the complete .tmp is kept until that write worked. Returns true,
-- or false and the reason.
local function write_safely(path, text)
    local tmp, bak = path .. ".tmp", path .. ".bak"
    if os == nil or os.rename == nil or os.remove == nil then
        if write_file(path, text) then return true end
        return false, "could not write " .. path
    end
    if not write_file(tmp, text) then
        os.remove(tmp)
        return false, "could not write " .. tmp
    end
    -- the old .bak goes only once the file has moved into the .bak's place (a
    -- rename that fails leaves it): moved aside first, as a rename cannot
    -- replace. One that cannot be removed stays as .bak.old
    local old = bak .. ".old"
    os.remove(old)
    local aside = os.rename(bak, old)
    if os.rename(path, bak) then
        if aside then os.remove(old) end
        if os.rename(tmp, path) then return true end
        if os.rename(bak, path) then os.remove(tmp) end     -- put the original back
        return false, "could not rename " .. tmp
    end
    if aside then os.rename(old, bak) end
    if write_file(path, text) then
        os.remove(tmp)
        return true
    end
    return false, "could not write " .. path .. " (the new text is in " .. tmp .. ")"
end

-- Set "key = value" lines in an ini file in one rewrite: list = { {key,
-- value}, ... }. Every line with a listed key (any case, any spacing) is
-- replaced, keeping its indent and its inline comment in its column
-- (U.read_ini takes the last one); every other line and the line endings are
-- kept; a missing key is appended at the end. Returns true, or false and the
-- reason.
function U.ini_set_many(path, list)
    local f = io.open(path, "rb")
    if not f then return false, "could not read " .. path end
    local raw = f:read("*a")
    f:close()
    local nl = raw:find("\r\n", 1, true) and "\r\n" or "\n"
    if raw:sub(-1) ~= "\n" then raw = raw .. "\n" end
    local want, order, done = {}, {}, {}
    for _, kv in ipairs(list) do
        local lk = string.lower(kv[1])
        if want[lk] == nil then order[#order + 1] = lk end
        want[lk] = kv
    end
    local lines = {}
    for l in raw:gmatch("(.-)\r?\n") do
        local line = l
        local k = line:match("^%s*([^;#=%s]+)%s*=")
        local kv = k and want[string.lower(k)]
        if kv then
            local cpos = comment_pos(l)
            line = l:match("^(%s*)") .. kv[1] .. " = " .. kv[2]
            if cpos then
                line = line .. string.rep(" ", math.max(1, cpos - 1 - #line)) .. l:sub(cpos)
            end
            line = line:gsub("%s+$", "")
            done[string.lower(k)] = true
        end
        lines[#lines + 1] = line
    end
    for _, lk in ipairs(order) do
        if not done[lk] then lines[#lines + 1] = (want[lk][1] .. " = " .. want[lk][2]):gsub("%s+$", "") end
    end
    return write_safely(path, table.concat(lines, nl) .. nl)
end

function U.ini_set(path, key, value)
    return U.ini_set_many(path, { { key, value } })
end

-- An ini file that holds what it should: readable, no NUL bytes (Windows
-- can leave a zero-filled file after a crash right after a save), and at
-- least one "key = value", comment or [section] line (one with comments
-- only is the user's: every setting at its default). Empty = not intact.
local function ini_intact(path)
    local f = io.open(path, "rb")
    if not f then return false end
    local s = f:read("*a") or ""
    f:close()
    if s:find("%z") then return false end
    s = "\n" .. s
    return s:find("\n%s*[%w_]+%s*=") ~= nil or s:find("\n%s*[;#%[]") ~= nil
end

U.ini_intact = ini_intact

-- At load: an ini file that is missing or broken after an interrupted save
-- is put back from its .tmp (the complete new text) or .bak (the version
-- before the last save); a broken one is kept as <path>.broken. Returns the
-- file it came from, or nil.
function U.ini_recover(path)
    if os == nil or os.rename == nil or os.remove == nil or ini_intact(path) then return nil end
    for _, src in ipairs({ path .. ".tmp", path .. ".bak" }) do
        if ini_intact(src) then
            if U.file_exists(path) then
                os.remove(path .. ".broken")
                if not os.rename(path, path .. ".broken") then return nil end
            end
            if os.rename(src, path) then return src end
        end
    end
    return nil
end

-- A new ini file from `pairs` ({ {key, value}, ... }) under a one-line header
-- comment, saved like any other save (write_safely). Returns true, or false
-- and the reason.
function U.write_ini(path, pairs, header)
    local t = {}
    if header then t[#t + 1] = "; " .. header end
    for _, kv in ipairs(pairs) do t[#t + 1] = kv[1] .. " = " .. tostring(kv[2]) end
    return write_safely(path, table.concat(t, "\n") .. "\n")
end

-----------------------------------------------------------------------------
-- Datarefs
-----------------------------------------------------------------------------

function U.find(name)
    local h = XPLMFindDataRef(name)
    if h == nil then
        U.log("dataref not found: " .. name)
    end
    return h
end

function U.getf(h, fallback)
    if h == nil then return fallback end
    return XPLMGetDataf(h)
end

function U.geti(h, fallback)
    if h == nil then return fallback end
    return XPLMGetDatai(h)
end

local scratch = {}

function U.getfa(h, index, fallback)
    if h == nil then return fallback end
    local n = XPLMGetDatavf(h, scratch, index, 1)
    if not n or n < 1 or scratch[1] == nil then return fallback end
    return scratch[1]
end

function U.getia(h, index, fallback)
    if h == nil then return fallback end
    local n = XPLMGetDatavi(h, scratch, index, 1)
    if not n or n < 1 or scratch[1] == nil then return fallback end
    return scratch[1]
end

function U.setf(h, v)
    if h ~= nil then XPLMSetDataf(h, v) end
end

function U.seti(h, v)
    if h ~= nil then XPLMSetDatai(h, v) end
end

function U.setfa(h, index, v)
    if h ~= nil then XPLMSetDatavf(h, { v }, index, 1) end
end

-- Read a byte-array string dataref (nav ids). Returns "" on failure.
-- The binding fills a caller table with byte values (same convention as
-- XPLMGetDatavf); tolerate a string result too in case that changes.
local bytes = {}
function U.gets(h, max_len)
    if h == nil then return "" end
    for i = #bytes, 1, -1 do bytes[i] = nil end
    local ok, ret = pcall(XPLMGetDatab, h, bytes, 0, max_len or 16)
    if not ok then return "" end
    if type(ret) == "string" then return (ret:gsub("%z.*$", "")) end
    local chars = {}
    for i = 1, #bytes do
        local b = bytes[i]
        if type(b) ~= "number" or b == 0 then break end
        chars[#chars + 1] = string.char(b)
    end
    return table.concat(chars)
end

-- Custom int/float datarefs and command handlers. xLua keeps (persists)
-- every callback function handed to the SDK, against a budget of 500 that
-- the aircraft's xLua scripts appear to share (X-Plane can crash when it
-- runs out). So all of them go through a few
-- named callbacks; the refcon is the entry id, and the per-dataref /
-- per-command functions stay in Lua tables here. Setter is optional (nil =
-- read-only). Getters and setters keep the SDK argument order: (ref) and
-- (ref, value); command functions get (cmd, phase, ref).
local acc = {}           -- id -> { getter, setter }
local acc_id = {}        -- dataref handle -> id
local cmds = {}          -- id -> handler
local arrs = {}          -- id -> { n, getter, setter } (int arrays)
local next_id = 0

local function dr_get(ref)
    local e = acc[ref]
    if e == nil then return 0 end
    return e[1](ref) or 0
end

local function dr_set(ref, v)
    local e = acc[ref]
    if e and e[2] then e[2](ref, v) end
end

local function cmd_handler(cmd, phase, ref)
    local f = cmds[ref]
    if f == nil then return true end
    return f(cmd, phase, ref) ~= false
end

local function reg(name, int, getter, setter)
    next_id = next_id + 1
    local id = next_id
    acc[id] = { getter, setter }
    local set = setter and dr_set or nil
    local h
    if int then
        h = XPLMRegisterDataAccessor(name, XPLMDataTypeID.xplmType_Int, setter ~= nil,
            dr_get, set, nil, nil,
            nil, nil, nil, nil, nil, nil, nil, nil, id, id)
    else
        h = XPLMRegisterDataAccessor(name, XPLMDataTypeID.xplmType_Float, setter ~= nil,
            nil, nil, dr_get, set,
            nil, nil, nil, nil, nil, nil, nil, nil, id, id)
    end
    if h == nil then
        acc[id] = nil
    else
        acc_id[h] = id
    end
    return h
end

function U.reg_int(name, getter, setter) return reg(name, true, getter, setter) end

-- a read-only string (byte data) dataref: getter() -> string, built only
-- when someone reads it. X-Plane asks with a table to fill (1-based bytes
-- from offset) and gets the count back; no table = the length.
local function dr_get_b(ref, out, offset, max)
    local e = acc[ref]
    local s = e and tostring(e[1]() or "") or ""
    offset = math.max(0, math.floor(tonumber(offset) or 0))
    if out == nil then return #s end
    local m = math.min(math.floor(tonumber(max) or #s), #s - offset)
    for i = 1, m do out[i] = s:byte(offset + i) end
    return math.max(0, m)
end

function U.reg_string(name, getter)
    next_id = next_id + 1
    local id = next_id
    acc[id] = { getter }
    local h = XPLMRegisterDataAccessor(name, XPLMDataTypeID.xplmType_Data, false,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        dr_get_b, nil, id, id)
    if h == nil then
        acc[id] = nil
    else
        acc_id[h] = id
    end
    return h
end
function U.reg_float(name, getter, setter) return reg(name, false, getter, setter) end

function U.unreg_dataref(h)
    if h == nil then return end
    XPLMUnregisterDataAccessor(h)
    local id = acc_id[h]
    if id then
        if id < 0 then arrs[-id] = nil else acc[id] = nil end
        acc_id[h] = nil
    end
end

-- returns the id to pass to U.unreg_cmd
function U.reg_cmd(cmd, fn)
    next_id = next_id + 1
    cmds[next_id] = fn
    XPLMRegisterCommandHandler(cmd, cmd_handler, true, next_id)
    return next_id
end

function U.unreg_cmd(cmd, id)
    if id == nil then return end
    XPLMUnregisterCommandHandler(cmd, cmd_handler, true, id)
    cmds[id] = nil
end

-- Int array dataref (xLua 2 array contract, example_scripts/XplmTest
-- TestGetArrayOfInts): the reader returns the element count when outvalues
-- is nil, otherwise fills outvalues[1..max] from element `offset`. The
-- writer gets (ref, values, offset, count). getter(i) / setter(i, v) use
-- 0-based element numbers.

local function dr_get_vi(ref, out, offset, max)
    local e = arrs[ref]
    if e == nil then return 0 end
    if out == nil then return e[1] end
    local m = math.min(max or e[1], e[1] - (offset or 0))
    for i = 1, m do out[i] = e[2](offset + i - 1) end
    return math.max(0, m)
end

local function dr_set_vi(ref, values, offset, count)
    local e = arrs[ref]
    if e == nil or e[3] == nil or values == nil then return end
    for i = 1, count or 0 do
        local k = (offset or 0) + i - 1
        if k >= 0 and k < e[1] and values[i] ~= nil then e[3](k, values[i]) end
    end
end

function U.reg_int_array(name, n, getter, setter)
    next_id = next_id + 1
    local id = next_id
    arrs[id] = { n, getter, setter }
    local h = XPLMRegisterDataAccessor(name, XPLMDataTypeID.xplmType_IntArray, setter ~= nil,
        nil, nil, nil, nil, nil, nil,
        dr_get_vi, setter and dr_set_vi or nil,
        nil, nil, nil, nil, id, id)
    if h == nil then
        arrs[id] = nil
    else
        acc_id[h] = -id      -- negative: an array entry
    end
    return h
end

-- Output datarefs in xLua's own storage (XLuaCreateDataRef, the engine of
-- XLua 1's create_dataref): read-only, no Lua callback handed to the SDK,
-- so they cost none of the callback budget. The script writes the value
-- (U.native_set) once per frame. nil when xLua does not offer it; the
-- caller then registers a normal accessor instead.
function U.native_ok()
    return XLuaCreateDataRef ~= nil and XLuaSetNumber ~= nil
end

function U.native_number(name)
    if not U.native_ok() then return nil end
    local ok, h = pcall(XLuaCreateDataRef, name, "number", "no", nil)
    if ok and h ~= nil then return h end
    return nil
end

function U.native_set(h, v)
    XLuaSetNumber(h, v)
end

-- writable variant (no notifier: the script polls U.native_get each frame);
-- nil when xLua does not allow it
function U.native_number_w(name)
    if not U.native_ok() or XLuaGetNumber == nil then return nil end
    local ok, h = pcall(XLuaCreateDataRef, name, "number", "yes", nil)
    if ok and h ~= nil then return h end
    return nil
end

function U.native_get(h)
    return XLuaGetNumber(h)
end

-- The last cursor callback X-Plane called on this unit (diagnostics: who
-- sets the cursor where): src = "3d_screen", "3d_knob_ring",
-- "3d_knob_cap", "3d_none" (a pick window, nothing of the unit under it),
-- "popup_bezel", "popup_screen"; part = "push" / "left" / "right" / "-";
-- cur = the XPLMCursorStatus returned; x, y = where (window px); t = the
-- XPLMGetElapsedTime of the call. Published as laminar/md302/cursor_report.
U.cursor = { n = 0, t = -1, src = "none", part = "-", cur = 0, x = 0, y = 0 }
function U.cursor_note(src, part, cur, x, y)
    local c = U.cursor
    c.n = c.n + 1
    c.t = (XPLMGetElapsedTime and tonumber(tostring(XPLMGetElapsedTime()))) or -1
    c.src, c.part, c.cur = src, part or "-", tonumber(cur) or 0
    c.x, c.y = math.floor((tonumber(x) or 0) + 0.5), math.floor((tonumber(y) or 0) + 0.5)
end

-- live entries (tests: nothing may be left after XPluginDisable)
function U.live_callbacks()
    local n = 0
    for _ in pairs(acc) do n = n + 1 end
    for _ in pairs(cmds) do n = n + 1 end
    for _ in pairs(arrs) do n = n + 1 end
    return n
end

-----------------------------------------------------------------------------
-- Commands
-----------------------------------------------------------------------------

function U.find_cmd(name)
    local c = XPLMFindCommand(name)
    if c == nil then
        U.log("command not found: " .. name)
    end
    return c
end

function U.cmd_once(c)
    if c ~= nil then XPLMCommandOnce(c) end
end

return U

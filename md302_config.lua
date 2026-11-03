-- Copyright (c) 2026 Tiezheng Eric Xu, erix@x-plane.com, Laminar Research - MIT License, see LICENSE
--
-- md302_config.lua: Configuration Mode (manual 9017782 rev Q section 4.5,
-- figures 4.27-4.62).
--
-- Entered by holding the knob while aircraft power comes on, on the ground
-- (md302_unit.lua), or with the command laminar/md302/config_mode. Every
-- change is pending until ACCEPT CHANGES, which writes the changed keys into
-- config.ini (the "Configuration Module") and restarts the unit; CANCEL
-- CHANGES restarts it without saving.
--
-- Pages are a stack: lists (CONFIGURE MENU and its sub-menus), choices
-- (ROLL DISPLAY, AIRSPEED UNITS, ...), digit entry (PANEL TILT, PANEL ROLL,
-- RANGE MMO), the RANGE MARKINGS and VNE TABLE tables, the DIMMING CURVE
-- graph, message pages and YES / NO boxes. Drawn on the air-data LCD in the
-- menu style (white on blue title, green cursor); the attitude LCD shows a
-- live preview with the pending values (figure 4.28: K.preview_kind,
-- K.with_pending).
--
-- Not in the simulator, so placeholders that look right and change nothing:
-- CALIBRATE AIRSPEED / ALTITUDE (no pitot / static test set; CALIBRATE HEADING
-- is left out, X-Plane has no MD32 to swing), CLEAR SSEC TABLE
-- (4.5.11; clears config.ini ssec_file, which only names the table on the
-- pre-flight screen), PASS-THROUGH (no ARINC 429 out), UPDATE SOFTWARE
-- (4.5.1; no USB port, so it ends as on a unit with no USB drive in: FAILED
-- UPDATE, OK, back to the menu; grey on the battery).

local K = {}

local U, G, M, cfg, Dsp, Fail
K.hooks = {
    commit = function(changes) end,     -- { {key, text}, ... } -> config.ini, applied
}

local P = nil           -- pending values while in Configuration Mode
local stack = {}        -- page frames, top = current
K.active = false

local ROW0, PITCH = 294.5, 37.5         -- digit pages, as the Options Menu
-- lists and choices (rev Q figures 4.27-4.48): 6 rows 27 LCD px apart from
-- y 66.5 px; grey triangles (13 px, at x 120 px) when there is more above /
-- below
local CROW0, CPITCH = (240 - 66.5) * 374 / 240, 27 * 374 / 240
local VISIBLE = 6
local TRI_UP = { 178.1, 291.4, 198.4, 291.4, 188.3, 311.7 }
local TRI_DN = { 178.1, 26.5, 198.4, 26.5, 188.3, 6.2 }
local TITLE_CAL = "C86000"              -- CALIBRATING ... boxes (figures 4.50, 4.51, 4.58)

-- RANGE MARKINGS (rev Q 4.5.2.4, figure 4.33): TYPE and CLR of a row
local TYPES = { { "F", "FULL" }, { "H", "HALF" }, { "R", "RAD" }, { "OFF", "OFF" } }
local T_OFF, T_RAD = 4, 3
local COLOURS = { { "white", "WHT" }, { "green", "GRN" }, { "yellow", "YEL" }, { "red", "RED" }, { "blue", "BLU" },
    { "bar", "BAR" }, { "magenta", "MAG" }, { "amber", "AMB" } }
local C_BAR, N_COLOURS = 6, 6           -- MAG / AMB: rev B colours of an old config.ini, kept, not offered

local SPEED_FACTOR = { knots = 1, mph = 1.150779, kph = 1.852 }

local function index_of(list, v)
    for i, e in ipairs(list) do
        if e[1] == v then return i end
    end
    return 1
end

-----------------------------------------------------------------------------
-- Menu tree (rev Q figures 4.27, 4.29, 4.35, 4.37, 4.41, 4.49)
-----------------------------------------------------------------------------

-- DISPLAY ORIENTATION: the pictures follow how MD302.obj sits in the aircraft
-- (MD302.lua), so only what fits that mounting can be picked
local function orientation_grey(v)
    local q = M.mount_q()
    if q == nil then return false end
    if q == 0 then return v ~= "horizontal" and v ~= "horizontal_swap" end
    if q < 0 then return v ~= "vertical_right" end
    return v ~= "vertical_left"
end

local function orientation_now()
    local v = P.display_orientation
    if v ~= "auto" then return v end
    local q = M.mount_q()
    if q == -90 then return "vertical_right" end
    if q == 90 then return "vertical_left" end
    return "horizontal"
end

local CHOICES = {
    roll_display = { title = "ROLL DISPLAY", opts = {
        { "fixed_pointer", "FIXED POINTER" }, { "fixed_scale", "FIXED SCALE" } } },
    airspeed_units = { title = "AIRSPEED UNITS", opts = {
        { "knots", "KNOTS" }, { "mph", "MPH" }, { "kph", "KPH" } } },
    airspeed_minimum = { title = "AIRSPEED MINIMUM", opts = {
        { 20, "20 KNOTS" }, { 30, "30 KNOTS" }, { 40, "40 KNOTS" } } },
    display_orientation = { title = "DISPLAY ORIENTATION", opts = {
        { "horizontal", "HORIZONTAL" }, { "vertical_right", "VERTICAL RIGHT" },
        { "vertical_left", "VERTICAL LEFT" }, { "horizontal_swap", "HORIZONTAL (SWAP)" } },
        grey = orientation_grey, now = orientation_now,
        note = { "SET BY THE AIRCRAFT (.ACF):", "GREY DOES NOT FIT ITS PANEL" } },
    horizon_display = { title = "HORIZON DISPLAY", opts = { { "flat", "FLAT" }, { "shaded", "SHADED" } } },
    heading_display = { title = "CONFIGURE HEADING", opts = { { "on", "DISPLAY ON" }, { "off", "DISPLAY OFF" } } },
    auto_off = { title = "CONFIGURE AUTO-OFF", opts = { { "on", "ON" }, { "off", "OFF" } } },
    baro_sync = { title = "CONFIGURE BARO SYNC", opts = { { "on", "ON" }, { "off", "OFF" } } },
    arinc_pass_through = { title = "PASS-THROUGH", opts = { { "off", "OFF" }, { "on", "ON" } } },
    arinc_speed = { title = "TRANSMIT SPEED", opts = { { "low", "LOW SPEED" }, { "high", "HIGH SPEED" } } },
    dimming_control = { title = "DIMMING CONTROL", opts = {
        { "internal", "INTERNAL" }, { "ext_5v", "EXT 5V" }, { "ext_14v", "EXT 14V" }, { "ext_28v", "EXT 28V" } } },
}

-- digit pages: PANEL TILT 00.0 and a sign (-90..+90), PANEL ROLL 0.0 by 0.5
-- and a sign (-5..+5), MMO 0.000 (figures 4.30-4.32)
local DIGITS = {
    panel_tilt = { title = "PANEL TILT", unit = "DEGREES", fmt = "tilt", lim = 90 },
    panel_roll = { title = "PANEL ROLL", unit = "DEGREES", fmt = "roll", lim = 5 },
    range_mmo = { title = "MMO", unit = "MACH", fmt = "mmo" },
}

local LISTS = {
    root = { title = "CONFIGURE MENU", items = {
        { label = "CONFIGURE AIRCRAFT", list = "aircraft" },
        { label = "CONFIGURE ARINC", list = "arinc" },
        { label = "CONFIGURE BARO SYNC", choice = "baro_sync" },
        { label = "CONFIGURE DIMMING", list = "dimming" },
        { label = "CONFIGURE DISPLAY", list = "display" },
        { label = "CONFIGURE HEADING", choice = "heading_display" },
        { label = "CONFIGURE AUTO-OFF", choice = "auto_off" },
        { label = "CALIBRATE", list = "calibrate" },
        { label = "UPDATE SOFTWARE", action = "update" },
        { label = "CLEAR SSEC TABLE", action = "ssec" },
        { label = "BATTERY STORAGE MODE", action = "storage" },
        { label = "ACCEPT CHANGES", action = "accept" },
        { label = "CANCEL CHANGES", action = "cancel" },
    } },
    aircraft = { title = "> CONFIGURE AIRCRAFT", items = {
        { label = "PANEL TILT", digits = "panel_tilt" },
        { label = "PANEL ROLL", digits = "panel_roll" },
        { label = "RANGE MMO", digits = "range_mmo" },
        { label = "RANGE MARKINGS", table = true },
        { label = "VNE TABLE", vne = true },
        { label = "EXIT", action = "back" },
    } },
    arinc = { title = "> CONFIGURE ARINC", items = {
        { label = "PASS-THROUGH", choice = "arinc_pass_through" },
        { label = "TRANSMIT SPEED", choice = "arinc_speed" },
        { label = "EXIT", action = "back" },
    } },
    dimming = { title = "> CONFIGURE DIMMING", items = {
        { label = "DIMMING CONTROL", choice = "dimming_control" },
        { label = "DIMMING CURVE", curve = true },
        { label = "EXIT", action = "back" },
    } },
    display = { title = "> CONFIGURE DISPLAY", items = {
        { label = "ROLL DISPLAY", choice = "roll_display" },
        { label = "AIRSPEED UNITS", choice = "airspeed_units" },
        { label = "AIRSPEED MINIMUM", choice = "airspeed_minimum" },
        { label = "DISPLAY ORIENTATION", choice = "display_orientation" },
        { label = "HORIZON DISPLAY", choice = "horizon_display" },
        { label = "EXIT", action = "back" },
    } },
    calibrate = { title = "> CALIBRATE", items = {
        { label = "CALIBRATE AIRSPEED", action = "cal_ias" },
        { label = "CALIBRATE ALTITUDE", action = "cal_alt" },
        -- rev Q figures 4.49 / 4.51: on the menu, grey (not modelled: the
        -- heading is X-Plane's own)
        { label = "CALIBRATE HEADING", disabled = true },
        { label = "EXIT", action = "back" },
    } },
}

-----------------------------------------------------------------------------
-- Pending values
-----------------------------------------------------------------------------

local function copy(t)
    local c = {}
    for i, v in ipairs(t) do c[i] = v end
    return c
end

local function curve_text(c)
    local t = {}
    for i, v in ipairs(c) do t[i] = string.format("%d", math.floor(v * 100 + 0.5)) end
    return table.concat(t, " ")
end

-- bands: the markings in use now as the 8 rows, in `units`. Rows taken from
-- the aircraft's V-speeds (acf) keep their exact values and follow AIRSPEED
-- UNITS until the installer edits them; edited rows are typed numbers, which
-- mean whatever units are selected (4.4.3c)
local function seed_rows(bands, units, acf)
    local rows, free = {}, 1
    for _, b in ipairs(bands) do
        -- a row from config.ini keeps its place; the aircraft's fill from the top
        local i = b.row
        if i == nil or rows[i] then
            while rows[free] do free = free + 1 end
            i = free
        end
        if i <= 8 then
            rows[i] = { t = index_of(TYPES, b.width), c = index_of(COLOURS, b.color),
                lo = U.clamp(math.floor(b.lo + 0.5), 0, 999), hi = U.clamp(math.floor(b.hi + 0.5), 0, 999),
                acf = acf, lo0 = b.lo, hi0 = b.hi, units0 = units }
        end
    end
    for i = 1, 8 do rows[i] = rows[i] or { t = T_OFF, c = 1, lo = 0, hi = 0 } end
    return rows
end

-- units: the pending AIRSPEED UNITS unless given (the preview of one the
-- cursor is on)
local function convert_rows(units)
    units = units or P.airspeed_units
    for _, r in ipairs(P.rows) do
        if r.acf then
            local k = (SPEED_FACTOR[units] or 1) / (SPEED_FACTOR[r.units0] or 1)
            r.lo = U.clamp(math.floor(r.lo0 * k + 0.5), 0, 999)
            r.hi = (r.hi0 >= 999) and 999 or U.clamp(math.floor(r.hi0 * k + 0.5), 0, 999)
        end
    end
end

-- config.ini rangeN: "<TYPE> <CLR> <V1> <V2|MAX>"; OFF or 000 / 000 = no bar;
-- a radial's V2 is its V1 (4b)
local function rows_text(rows)
    local out = {}
    for i, r in ipairs(rows) do
        local hi = (r.t == T_RAD) and r.lo or r.hi
        out[i] = (r.t == T_OFF or (r.lo == 0 and hi == 0)) and "" or
            string.format("%s %s %d %s", TYPES[r.t][2], COLOURS[r.c][2], r.lo, (hi >= 999) and "MAX" or tostring(hi))
    end
    return out
end

-- the pending rows as bands for the preview (md302_display.lua range markings)
local function rows_bands(rows)
    local b = {}
    for _, r in ipairs(rows) do
        if r.t ~= T_OFF and (r.lo > 0 or r.hi > 0) then
            b[#b + 1] = { width = TYPES[r.t][1], color = COLOURS[r.c][1], lo = r.lo, hi = (r.t == T_RAD) and r.lo or r.hi }
        end
    end
    return b
end

-- VNE TABLE rows: { alt, v } x up to 7; row 1 is always 0 ft; v = 0 on row 1
-- = no table
local function vne_rows(points)
    local rows = {}
    for i, p in ipairs(points or {}) do rows[i] = { p[1], p[2] } end
    if #rows == 0 then rows[1] = { 0, 0 } end
    return rows
end

local function vne_text(rows)
    if rows[1][2] == 0 then return "" end       -- 0 ft at 000: no table
    local t = {}
    for _, r in ipairs(rows) do
        t[#t + 1] = string.format("%d %d", r[1], r[2])
    end
    return table.concat(t, " ")
end

-- leaving the VNE TABLE: rows in altitude order, a row with speed 000 (but the
-- first) and exact repeats dropped. Two rows at one altitude are a step (rev Q
-- figure 4.34 case 1: 18000 250, 18000 230), kept in the order they were typed
local function vne_tidy()
    local rows = { P.vne[1] }
    local rest = {}
    for i = 2, #P.vne do
        if P.vne[i][2] > 0 and P.vne[i][1] > 0 then rest[#rest + 1] = { P.vne[i], i } end
    end
    table.sort(rest, function(a, b) return a[1][1] < b[1][1] or (a[1][1] == b[1][1] and a[2] < b[2]) end)
    for _, e in ipairs(rest) do
        local r, last = e[1], rows[#rows]
        if r[1] ~= last[1] or r[2] ~= last[2] then rows[#rows + 1] = r end
    end
    P.vne = rows
end

function K.init(util, gfx, unit, config, display, fail)
    U, G, M, cfg, Dsp, Fail = util, gfx, unit, config, display, fail
end

function K.start(bands)
    local tilt, roll = M.panel_angles()
    P = {
        roll_display = cfg.roll_display, airspeed_units = cfg.airspeed_units,
        airspeed_minimum = cfg.airspeed_minimum, display_orientation = cfg.display_orientation,
        horizon_display = cfg.horizon_display, heading_display = cfg.heading_display, auto_off = cfg.auto_off,
        baro_sync = cfg.baro_sync, arinc_pass_through = cfg.arinc_pass_through, arinc_speed = cfg.arinc_speed,
        dimming_control = cfg.dimming_control,
        panel_tilt = tilt, panel_roll = roll, tilt0 = tilt, roll0 = roll, range_mmo = cfg.range_mmo,
        curve_internal = copy(cfg.curve_internal), curve_external = copy(cfg.curve_external),
        low_input = cfg.dimming_low_input / 100,
        rows = seed_rows(bands, cfg.airspeed_units, cfg.range_markings == "auto"),
        rows_touched = false,
        vne = vne_rows(cfg.vne_points), vne_touched = false,
        ssec_file = cfg.ssec_file,
    }
    stack = { { kind = "list", id = "root", sel = 1, top = 1 } }
    K.active = true
    U.log("configuration mode")
end

function K.stop()
    K.active = false
    P = nil
    stack = {}
end

-- dimming used for the screen: the pending curve while it is being set up
function K.dim_params()
    if not K.active then return nil end
    -- DIMMING CONTROL: the option under the cursor, before it is pushed
    local f, control = stack[#stack], P.dimming_control
    if f ~= nil and f.kind == "choice" and f.key == "dimming_control" then control = CHOICES.dimming_control.opts[f.sel][1] end
    return control, P.curve_internal, P.curve_external, P.low_input
end

-- dry: only whether there are any (convert_rows below changes the pending rows)
local function changes(dry)
    local out = {}
    local function put(key, cur, new)
        if cur ~= new then out[#out + 1] = { key, new } end
    end
    for _, k in ipairs({ "roll_display", "airspeed_units", "display_orientation", "horizon_display",
        "heading_display", "auto_off", "baro_sync", "arinc_pass_through", "arinc_speed", "dimming_control" }) do
        put(k, cfg[k], P[k])
    end
    -- the baro input with it, so a source read from an old 'baro_sync = copilot' stays
    if cfg.baro_sync ~= P.baro_sync then out[#out + 1] = { "baro_sync_source", cfg.baro_sync_source } end
    put("airspeed_minimum", tostring(cfg.airspeed_minimum), tostring(P.airspeed_minimum))
    put("dimming_curve_internal", curve_text(cfg.curve_internal), curve_text(P.curve_internal))
    put("dimming_curve_external", curve_text(cfg.curve_external), curve_text(P.curve_external))
    put("dimming_low_input", string.format("%d", math.floor(cfg.dimming_low_input + 0.5)),
        string.format("%d", math.floor(P.low_input * 100 + 0.5)))
    -- PANEL TILT / ROLL stay auto (what the mounting needs) unless a value was
    -- typed; then both are written (a config.ini without panel_roll is one from
    -- before rev Q, whose panel_tilt is read as auto)
    local t0, t1 = string.format("%.1f", P.tilt0), string.format("%.1f", P.panel_tilt)
    local r0, r1 = string.format("%.1f", P.roll0), string.format("%.1f", P.panel_roll)
    if t0 ~= t1 or r0 ~= r1 then
        out[#out + 1] = { "panel_tilt", t1 }
        out[#out + 1] = { "panel_roll", r1 }
    end
    put("range_mmo", string.format("%.3f", cfg.range_mmo), string.format("%.3f", P.range_mmo))
    if P.rows_touched then
        out[#out + 1] = { "range_markings", "manual" }
        if not dry then
            convert_rows()
            local rows = rows_text(P.rows)
            for i = 1, 8 do out[#out + 1] = { "range" .. i, rows[i] } end
        end
    end
    if P.vne_touched then put("vne_table", cfg.vne_table, vne_text(P.vne)) end
    put("ssec_file", cfg.ssec_file, P.ssec_file)
    return out
end

-----------------------------------------------------------------------------
-- Knob
-----------------------------------------------------------------------------

local function top() return stack[#stack] end

local function push(f) stack[#stack + 1] = f end

local function pop()
    if #stack > 1 then stack[#stack] = nil end
end

local function list_items(f) return LISTS[f.id].items end

local function item_ok(it)
    if it.disabled then return false end
    if it.action == "ssec" then return P.ssec_file ~= "" end        -- no SSEC table loaded: grey
    if it.action == "update" then return M.st.ext_power end         -- 4.5.1: not on the battery
    -- BATTERY STORAGE MODE (SB MD302-05) switches the battery off: grey with changes waiting to be saved
    -- (rev Q's menu pictures: grey with ACCEPT / CANCEL CHANGES pending, white without), when already in it,
    -- and without a battery
    if it.action == "storage" then return not M.st.storage and M.has_battery() and #changes(true) == 0 end
    return true
end

-- the cursor stops at the ends and skips grey items; the 6-row window follows
local function turn_list(f, dir)
    local items = list_items(f)
    local i = f.sel + dir
    while i >= 1 and i <= #items do
        if item_ok(items[i]) then
            f.sel = i
            break
        end
        i = i + dir
    end
    -- rev Q CONFIGURE MENU dumps (PDF pages 41, 55, 60-62): the list scrolls
    -- under the cursor on the third row, until its end shows
    f.top = math.max(1, math.min(f.sel - 2, #items - VISIBLE + 1))
end

local function choice_grey(C, o)
    return o[3] or (C.grey ~= nil and C.grey(o[1]))
end

-- digit pages: the fields in the order the push walks them
local function digit_fields(spec)
    if spec.fmt == "tilt" then return 4 end     -- tens, ones, tenths, sign
    if spec.fmt == "roll" then return 3 end     -- ones, half, sign
    return 3                                    -- 0.xxx
end

local function digits_of(spec, v)
    if spec.fmt == "mmo" then
        local n = U.clamp(math.floor(v * 1000 + 0.5), 0, 999)
        return { math.floor(n / 100) % 10, math.floor(n / 10) % 10, n % 10 }, false
    end
    local a = math.abs(v)
    if spec.fmt == "roll" then
        local h = U.clamp(math.floor(a * 2 + 0.5), 0, 10)
        return { math.floor(h / 2), (h % 2) * 5 }, v < 0
    end
    local n = U.clamp(math.floor(a * 10 + 0.5), 0, 900)
    return { math.floor(n / 100), math.floor(n / 10) % 10, n % 10 }, v < 0
end

local function value_of(spec, d, neg)
    if spec.fmt == "mmo" then return (d[1] * 100 + d[2] * 10 + d[3]) / 1000 end
    local v
    if spec.fmt == "roll" then v = d[1] + d[2] / 10 else v = d[1] * 10 + d[2] + d[3] / 10 end
    v = math.min(v, spec.lim)
    if neg and v > 0 then v = -v end
    return v
end

-- RANGE MARKINGS: row by row TYPE, CLR, the three digits of V1 and of V2,
-- then EXIT; an OFF row has its TYPE only, a radial no V2 (= V1, 4b)
local function table_fields()
    local fl = {}
    for r = 1, 8 do
        local t = P.rows[r].t
        fl[#fl + 1] = { r, "t" }
        if t ~= T_OFF then
            fl[#fl + 1] = { r, "c" }
            for k = 1, 3 do fl[#fl + 1] = { r, "lo", k } end
            if t ~= T_RAD then
                for k = 1, 3 do fl[#fl + 1] = { r, "hi", k } end
            end
        end
    end
    return fl
end

local function table_field(i)
    local fd = table_fields()[i]
    if fd == nil then return nil end
    return fd[1], fd[2], fd[3]
end

-- 4.5.2.4 4d: a row made FULL BAR runs to MAX, set as the cursor leaves its
-- CLR (V2 can still be typed after); a radial's V2 follows its V1 where the
-- row is used (4b), so turning TYPE through RAD keeps V2
local function leave_field(f)
    local row, what = table_field(f.field)
    local r = row and P.rows[row]
    if r and what == "c" and r.c_set and r.t == 1 and r.c == C_BAR then r.hi = 999 end
    if r then r.c_set = nil end
end

-- VNE TABLE: row 1 speed (3 digits), then each used row's altitude (5) and
-- speed (3), then the first unused row (one "UNUSED" field), then EXIT
local function vne_fields()
    local fl = {}
    for k = 1, 3 do fl[#fl + 1] = { 1, "v", k } end
    for r = 2, #P.vne do
        for k = 1, 5 do fl[#fl + 1] = { r, "alt", k } end
        for k = 1, 3 do fl[#fl + 1] = { r, "v", k } end
    end
    if #P.vne < 7 then fl[#fl + 1] = { #P.vne + 1, "new" } end
    return fl
end

local function bump_digit(n, place, dir)
    local p = ({ 100, 10, 1 })[place]
    local d = math.floor(n / p) % 10
    return n - d * p + ((d + dir) % 10) * p
end

local function bump_digit5(n, place, dir)
    local p = ({ 10000, 1000, 100, 10, 1 })[place]
    local d = math.floor(n / p) % 10
    return n - d * p + ((d + dir) % 10) * p
end

local CURVE_STEP = 0.02

-- YES / NO boxes (figures 4.50, 4.51, 4.56): { title, colour, lines, centre,
-- cursor, yes = fn, no = fn }; the text one line under the title, the lit NO
-- wide (md302_fail.lua "yesno_cal"); a line { text, x } starts at x; yes =
-- nil: an OK box, the push goes back
local function box(title, lines, centre, cursor, yes, no)
    push({ kind = "dialog", title = title, colour = TITLE_CAL, lines = lines, centre = centre,
        cursor = cursor, yes = yes, no = no, ok = yes == nil })
end
local function lx(px) return px * 1.5625 end

function K.turn(dir)
    local f = top()
    if f.kind == "list" then
        turn_list(f, dir)
    elseif f.kind == "choice" then
        local C = CHOICES[f.key]
        local i = f.sel
        for _ = 1, #C.opts do
            i = (i - 1 + dir) % #C.opts + 1
            if not choice_grey(C, C.opts[i]) then break end
        end
        f.sel = i
    elseif f.kind == "digits" then
        local spec = DIGITS[f.key]
        if f.pos > #f.d then
            f.neg = not f.neg
        elseif spec.fmt == "roll" and f.pos == 1 then
            f.d[1] = (f.d[1] + dir) % 6
        elseif spec.fmt == "roll" then
            f.d[2] = 5 - f.d[2]
        else
            f.d[f.pos] = (f.d[f.pos] + dir) % 10
        end
    elseif f.kind == "table" then
        local row, what, place = table_field(f.field)
        if row then
            P.rows_touched = true
            local r = P.rows[row]
            r.acf = false                   -- now a typed row
            if what == "t" then
                r.t = (r.t - 1 + dir) % #TYPES + 1
            elseif what == "c" then
                -- the rev Q colours; an old MAG / AMB row joins them when turned
                if r.c > N_COLOURS then r.c = (dir > 0) and 1 or N_COLOURS
                else r.c = (r.c - 1 + dir) % N_COLOURS + 1 end
                r.c_set = true
            else
                r[what] = bump_digit(r[what], place, dir)
            end
        end
    elseif f.kind == "vne" then
        local fd = vne_fields()[f.field]
        if fd then
            P.vne_touched = true
            local r = P.vne[fd[1]]
            if fd[2] == "new" then
                local prev = P.vne[#P.vne]
                P.vne[#P.vne + 1] = { math.min(prev[1] + 1000, 99999), prev[2] }
            elseif fd[2] == "alt" then
                r[1] = bump_digit5(r[1], fd[3], dir)
            else
                r[2] = bump_digit(r[2], fd[3], dir)
            end
        end
    elseif f.kind == "curve" then
        local c = (P.dimming_control == "internal") and P.curve_internal or P.curve_external
        if f.phase == "points" then
            c[f.pt] = U.clamp(c[f.pt] + dir * CURVE_STEP, cfg.backlight_min, 1)
        else
            P.low_input = U.clamp(P.low_input + dir * CURVE_STEP, 0, 1)
        end
    elseif f.kind == "dialog" and not f.ok then
        f.cursor = (dir < 0) and 1 or 2
    end
end

local function open_item(f, it)
    if it.list then
        push({ kind = "list", id = it.list, sel = 1, top = 1 })
    elseif it.choice then
        local C = CHOICES[it.choice]
        local now = C.now and C.now() or P[it.choice]
        local sel = 1
        for i, o in ipairs(C.opts) do if o[1] == now then sel = i end end
        push({ kind = "choice", key = it.choice, sel = sel })
    elseif it.digits then
        local spec = DIGITS[it.digits]
        local d, neg = digits_of(spec, P[it.digits])
        push({ kind = "digits", key = it.digits, d = d, neg = neg, pos = 1 })
    elseif it.table then
        convert_rows()                  -- aircraft rows in the pending units
        push({ kind = "table", field = 1 })
    elseif it.vne then
        push({ kind = "vne", field = 1 })
    elseif it.curve then
        push({ kind = "curve", phase = "points", pt = 1 })
    elseif it.action == "back" then
        pop()
    elseif it.action == "cal_ias" then
        box("CALIBRATING AIRSPEED", { "", { "APPLY PITOT PRESSURE", lx(56) }, { "OF 120 KNOTS", lx(81) } }, false, 2,
            function()
                pop()
                U.log("calibrate airspeed: placeholder, nothing changed")
            end)
    elseif it.action == "cal_alt" then
        box("CALIBRATING ALTITUDE", { "", { "APPLY STATIC PRESSURE", lx(56) }, { "OF 5000 FEET", lx(81) } }, false, 2,
            function()
                pop()
                U.log("calibrate altitude: placeholder, nothing changed")
            end)
    elseif it.action == "update" then
        -- rev Q 4.5.1 / 5.1.2 step 9: no USB device (or no valid file) found
        box("UPDATE SOFTWARE", { "", "", "FAILED UPDATE" }, true, 2)
        U.log("update software: no USB port, FAILED UPDATE")
    elseif it.action == "ssec" then
        box("CLEAR SSEC TABLE", { "SSEC FILE " .. string.upper(P.ssec_file), "IS CLEARED ON", "ACCEPT CHANGES.", "", "PROCEED?" },
            false, 2, function()
                pop()
                P.ssec_file = ""
            end)
    elseif it.action == "storage" then
        -- SB MD302-05: the battery is off until the unit starts on aircraft power again
        box("BATTERY STORAGE", { "BATTERY OFF UNTIL", "AIRCRAFT POWER IS", "APPLIED AGAIN.", "", "PROCEED?" },
            false, 2, function()
                pop()
                M.st.storage = true
                U.log("battery storage mode: the battery is off until aircraft power is applied again")
            end)
    elseif it.action == "accept" then
        local ch = changes()
        local ok, err = pcall(K.hooks.commit, ch)
        if ok then
            U.log(string.format("configuration: ACCEPT CHANGES, %d key(s) saved", #ch))
        else
            U.log("ERROR configuration: ACCEPT CHANGES failed: " .. tostring(err))
        end
        K.stop()
        M.restart("configuration accepted")
    elseif it.action == "cancel" then
        U.log("configuration: CANCEL CHANGES")
        K.stop()
        M.restart("configuration cancelled")
    end
end

-- a short push (release of the knob)
function K.press()
    local f = top()
    if f.kind == "list" then
        local it = list_items(f)[f.sel]
        if item_ok(it) then open_item(f, it) end
    elseif f.kind == "choice" then
        local C = CHOICES[f.key]
        local o = C.opts[f.sel]
        -- picking what auto already found keeps auto (it follows the .acf)
        local keep_auto = f.key == "display_orientation" and P.display_orientation == "auto"
            and o[1] == orientation_now()
        if not choice_grey(C, o) and not keep_auto then P[f.key] = o[1] end
        pop()
    elseif f.kind == "digits" then
        local spec = DIGITS[f.key]
        if f.pos < digit_fields(spec) then
            f.pos = f.pos + 1
        else
            P[f.key] = value_of(spec, f.d, f.neg)
            pop()
            if f.after then f.after() end
        end
    elseif f.kind == "table" then
        if table_field(f.field) then
            leave_field(f)
            f.field = f.field + 1
        else
            pop()
        end
    elseif f.kind == "vne" then
        if vne_fields()[f.field] == nil then
            vne_tidy()                  -- EXIT
            pop()
        else
            f.field = f.field + 1       -- an UNUSED row pushed past: on to EXIT
        end
    elseif f.kind == "curve" then
        if f.phase == "points" then
            if f.pt < 6 then
                f.pt = f.pt + 1
            elseif P.dimming_control ~= "internal" then
                f.phase = "low_x"           -- rev Q 4.5.5.2 step 6: the low-input threshold
            else
                pop()
            end
        else
            pop()
        end
    elseif f.kind == "message" then
        pop()
    elseif f.kind == "dialog" then
        if f.cursor == 1 then f.yes() elseif f.no then f.no() else pop() end
    end
end

-----------------------------------------------------------------------------
-- Preview (rev Q 4.5, figure 4.28): the attitude LCD shows the pending values
-----------------------------------------------------------------------------

local AIR_PAGES = { airspeed_units = true, airspeed_minimum = true, range_mmo = true }

-- "air": the page sets something on the airspeed tape, so the preview is the
-- air-data picture; "att" otherwise
function K.preview_kind()
    local f = stack[#stack]
    if f == nil then return "att" end
    if f.kind == "table" or f.kind == "vne" then return "air" end
    if (f.kind == "choice" or f.kind == "digits") and AIR_PAGES[f.key] then return "air" end
    return "att"
end

local PREVIEW_KEYS = { "roll_display", "airspeed_units", "airspeed_minimum", "horizon_display", "heading_display",
    "range_mmo" }
local saved = {}

-- fn(...) with the pending values in config (and in D: the pending range
-- markings; on the VNE TABLE the altitude of the row being set and a speed
-- just above its Vne, as figure 4.34; on RANGE MMO the Mmo pole at sea
-- level, Vmo = Mmo x 661 kt, so the pole shows on the ground), then all put
-- back. On a choice page the option under the cursor is previewed before it
-- is pushed (nothing is set until then)
function K.with_pending(D, fn, ...)
    if not K.active or P == nil then return fn(...) end
    local f = stack[#stack]
    local hover = nil
    if f ~= nil and f.kind == "choice" then
        local o = CHOICES[f.key].opts[f.sel]
        if o and not choice_grey(CHOICES[f.key], o) then hover = o[1] end
    end
    for _, k in ipairs(PREVIEW_KEYS) do
        saved[k] = cfg[k]
        cfg[k] = P[k]
        if hover ~= nil and k == f.key then cfg[k] = hover end
    end
    saved.speed_factor, saved.vne_points, saved.bands = cfg.speed_factor, cfg.vne_points, D.bands
    saved.ias, saved.alt, saved.vmo, saved.vne = D.ias_kt, D.alt_ft, D.vmo_kt, D.vne
    local units = cfg.airspeed_units
    cfg.speed_factor = SPEED_FACTOR[units] or 1
    local on_vne = f ~= nil and f.kind == "vne"
    if P.vne_touched or on_vne then
        local pts = (P.vne[1][2] == 0) and {} or P.vne
        cfg.vne_points = pts
        if on_vne and #pts > 0 then
            local fd = vne_fields()[f.field]
            local r = math.min(fd and fd[1] or #P.vne, #P.vne)
            local row = P.vne[r]
            -- the second row of a step (two rows at one altitude): just above it
            D.alt_ft = row[1] + ((r > 1 and P.vne[r - 1][1] == row[1]) and 1 or 0)
            D.ias_kt = (M.vne_at(pts, D.alt_ft) + 10) / cfg.speed_factor
        end
        D.vne = M.vne_at(pts, D.alt_ft)
    end
    if f ~= nil and f.kind == "digits" and f.key == "range_mmo" then
        local mmo = value_of(DIGITS.range_mmo, f.d)
        cfg.range_mmo = mmo
        D.vmo_kt = mmo * 661.47
        if mmo > 0 then D.ias_kt = D.vmo_kt + 10 / cfg.speed_factor end
    end
    -- the markings in the units shown: the aircraft's (range_markings =
    -- auto) follow AIRSPEED UNITS before ACCEPT too, typed ones keep their numbers
    if P.rows_touched or units ~= saved.airspeed_units then
        convert_rows(units)
        D.bands = rows_bands(P.rows)
        if units ~= P.airspeed_units then convert_rows() end
    end
    local ok, err = pcall(fn, ...)
    for _, k in ipairs(PREVIEW_KEYS) do cfg[k] = saved[k] end
    cfg.speed_factor, cfg.vne_points, D.bands = saved.speed_factor, saved.vne_points, saved.bands
    D.ias_kt, D.alt_ft, D.vmo_kt, D.vne = saved.ias, saved.alt, saved.vmo, saved.vne
    if not ok then error(err, 0) end
end

-----------------------------------------------------------------------------
-- Drawing (air-data LCD)
-----------------------------------------------------------------------------

local function fs20() return G.font("text", 20) end

local function hug_cursor(x, yc, w)
    G.rect(x - 5, yc - 17, x + w + 7, yc + 17, G.C.cursor)
    G.box(x - 5, yc - 17, x + w + 7, yc + 17, G.C.white, 2)
end

-- the rev Q list cursor: 28 LCD px high round the text
local function list_cursor(x, yc, w)
    G.rect(x - 5, yc - 21, x + w + 7, yc + 21, G.C.cursor)
    G.box(x - 5, yc - 21, x + w + 7, yc + 21, G.C.white, 2)
end

local tri_col = nil
local function triangles(more_up, more_down)
    tri_col = tri_col or G.hex("7C7C7C")
    if more_up then G.poly(tri_col, TRI_UP) end
    if more_down then G.poly(tri_col, TRI_DN) end
end

local function draw_list(f)
    local fs = fs20()
    local L = LISTS[f.id]
    Dsp.title_bar(L.title)
    local n = #L.items
    for k = 0, VISIBLE - 1 do
        local i = f.top + k
        local it = L.items[i]
        if it then
            local yc = CROW0 - CPITCH * k
            if i == f.sel then list_cursor(12, yc, G.text_w(fs, it.label)) end
            G.textc(fs, it.label, 12, yc, item_ok(it) and G.C.white or G.C.grey_text)
        end
    end
    triangles(f.top > 1, f.top + VISIBLE - 1 < n)
end

local function draw_choice(f)
    local fs = fs20()
    local C = CHOICES[f.key]
    Dsp.title_bar("> " .. C.title)
    for i, o in ipairs(C.opts) do
        local yc = CROW0 - CPITCH * (i - 1)
        if i == f.sel then list_cursor(12, yc, G.text_w(fs, o[2])) end
        G.textc(fs, o[2], 12, yc, choice_grey(C, o) and G.C.grey_text or G.C.white)
    end
    -- DISPLAY ORIENTATION: why some are grey (never selectable, the reason
    -- under them)
    if C.note then
        for k, l in ipairs(C.note) do G.textc(fs, l, 12, CROW0 - CPITCH * (4 + k), G.C.grey_text) end
    end
end

local grid_col = nil

-- digit pages (rev Q figures 4.30-4.32, 4.53): the digits at fixed columns
-- with the point between, the cursor box 24 x 27 LCD px round the digit
-- being set, the unit from x 122 px (139 px on INCLINATION); a sign shows
-- when negative or while it is the field being set (no dump has one: left of
-- the first digit)
local DIGIT_COLS = {
    tilt = { sign = 24, 44.5, 65, ".", 95.5 },
    roll = { sign = 44.5, 65, ".", 95.5 },
    mmo = { "0", ".", 50.5, 75.5, 99.5 },
}
local DIGIT_DOT = { tilt = 79.5, roll = 79.5, mmo = 38.5 }
local DIGIT_ZERO = 25                   -- MMO's leading 0
local DIGIT_ROW = (240 - 53.5) * 374 / 240

local function digit_box(cx)
    local x0, x1 = (cx - 12) * 1.5625, (cx + 12) * 1.5625
    local y0, y1 = (240 - 69) * 374 / 240, (240 - 41) * 374 / 240
    G.rect(x0, y0, x1, y1, G.C.cursor)
    G.box(x0, y0, x1, y1, G.C.white, 1.56)
end

local function draw_digits(f)
    local fs = fs20()
    local spec = DIGITS[f.key]
    Dsp.title_bar("> " .. spec.title)
    local cols = DIGIT_COLS[spec.fmt]
    local yc = DIGIT_ROW
    local k = 0
    for _, c in ipairs(cols) do
        if c == "." then
            G.textc(fs, ".", DIGIT_DOT[spec.fmt] * 1.5625, yc, G.C.white, G.JC)
        elseif c == "0" then
            G.textc(fs, "0", DIGIT_ZERO * 1.5625, yc, G.C.white, G.JC)
        else
            k = k + 1
            if f.pos == k then digit_box(c) end
            G.textc(fs, tostring(f.d[k]), c * 1.5625, yc, G.C.white, G.JC)
        end
    end
    if cols.sign then
        local on_sign = f.pos == #f.d + 1
        if on_sign then digit_box(cols.sign) end
        if f.neg or on_sign then G.textc(fs, f.neg and "-" or "+", cols.sign * 1.5625, yc, G.C.white, G.JC) end
    end
    G.textc(fs, spec.unit, 122 * 1.5625, yc, G.C.white)
end

-- RANGE MARKINGS (rev Q figure 4.33): # TYPE CLR V1 V2 over 8 rows in a grey
-- grid, the header on dark blue, then EXIT. No screen dump: the figure's
-- columns at the 320 px screen, x 38 59 119 171 223 276; rows 20 px from y 10
local RX = { 38, 59, 119, 171, 223, 276 }
local function rpx(x) return x * 1.5625 end
local function rpy(y) return (240 - y) * 374 / 240 end

local function draw_table(f)
    local fs = fs20()
    grid_col = grid_col or G.hex("7A7A7C")
    local frow, fwhat, fplace = table_field(f.field)
    G.rect(rpx(RX[1]), rpy(30), rpx(RX[6]), rpy(10), G.C.menu_blue)
    for k = 0, 9 do G.rect(rpx(RX[1]), rpy(10 + 20 * k) - 0.8, rpx(RX[6]), rpy(10 + 20 * k) + 0.8, grid_col) end
    for _, x in ipairs(RX) do G.rect(rpx(x) - 0.8, rpy(190), rpx(x) + 0.8, rpy(10), grid_col) end
    local function mid(c) return (rpx(RX[c]) + rpx(RX[c + 1])) / 2 end
    local yh = rpy(20)
    for c, h in ipairs({ "#", "TYPE", "CLR", "V1", "V2" }) do G.textc(fs, h, mid(c), yh, G.C.white, G.JC) end
    for i = 1, 8 do
        local yc = rpy(20 + 20 * i)
        local r = P.rows[i]
        G.textc(fs, tostring(i), mid(1), yc, G.C.white, G.JC)
        local words = { { "t", TYPES[r.t][2], 2 }, { "c", COLOURS[r.c][2], 3 } }
        for _, w in ipairs(words) do
            local tw = G.text_w(fs, w[2])
            if frow == i and fwhat == w[1] then hug_cursor(mid(w[3]) - tw / 2 - 1, yc, tw) end
            G.textc(fs, w[2], mid(w[3]), yc, G.C.white, G.JC)
        end
        for c, part in ipairs({ "lo", "hi" }) do
            local x = mid(3 + c)
            local editing = frow == i and fwhat == part
            if part == "hi" and r.hi >= 999 and not editing then
                G.textc(fs, "MAX", x, yc, G.C.white, G.JC)
            else
                local v = (part == "hi" and r.t == T_RAD) and r.lo or r[part]
                local d = string.format("%03d", v)
                -- digits 16 px apart (the 20 px face's digit is 15 px wide); the
                -- cursor box first, so it is under all three digits
                if editing then hug_cursor(x + (fplace - 2) * 16 - 8.5, yc, 15) end
                for k = 1, 3 do
                    G.textc(fs, string.sub(d, k, k), x + (k - 2) * 16, yc, G.C.white, G.JC)
                end
            end
        end
    end
    local ye, xe = rpy(206), rpx(171)
    local we = G.text_w(fs, "EXIT")
    if frow == nil then hug_cursor(xe - we / 2 - 1, ye, we) end
    G.textc(fs, "EXIT", xe, ye, G.C.white, G.JC)
end

-- VNE TABLE (figures 4.33 / 4.34): # | ALT (FT) | KTS, 7 rows 20 LCD px
-- high from y 52 px (the header) in a grey grid, x 93 / 115 / 193 / 248 px,
-- then EXIT. Row 1's altitude is 00000 in grey; the first unused row reads
-- UNUSED in white, the rest in grey.
local VX = { 93 * 1.5625, 115 * 1.5625, 193 * 1.5625, 248 * 1.5625 }
local function vy(px) return (240 - px) * 374 / 240 end
local function draw_vne(f)
    local fs = fs20()
    Dsp.title_bar("> VNE TABLE")
    grid_col = grid_col or G.hex("7A7A7C")
    local fd = vne_fields()[f.field]
    -- the header row on dark blue (figure 4.34, p47 dumps)
    G.rect(VX[1], vy(62), VX[4], vy(42), G.C.menu_blue)
    for k = 0, 8 do G.rect(VX[1], vy(42 + 20 * k) - 0.8, VX[4], vy(42 + 20 * k) + 0.8, grid_col) end
    for _, x in ipairs(VX) do G.rect(x - 0.8, vy(202), x + 0.8, vy(42), grid_col) end
    local units = ({ knots = "KTS", mph = "MPH", kph = "KPH" })[P.airspeed_units] or "KTS"
    local yh = vy(52)
    G.textc(fs, "#", (VX[1] + VX[2]) / 2, yh, G.C.white, G.JC)
    G.textc(fs, "ALT(FT)", (VX[2] + VX[3]) / 2, yh, G.C.white, G.JC)
    G.textc(fs, units, (VX[3] + VX[4]) / 2, yh, G.C.white, G.JC)
    for i = 1, 7 do
        local yc = vy(52 + 20 * i)
        G.textc(fs, tostring(i), (VX[1] + VX[2]) / 2, yc, G.C.white, G.JC)
        local r = P.vne[i]
        local altx, vx = VX[2] + 14, VX[3] + 14
        if r then
            local s = string.format("%05d", r[1])
            for k = 1, 5 do
                local x = altx + (k - 1) * 18
                if fd and fd[1] == i and fd[2] == "alt" and fd[3] == k then hug_cursor(x - 2, yc, 13) end
                G.textc(fs, string.sub(s, k, k), x + 6, yc, (i == 1) and G.C.grey_text or G.C.white, G.JC)
            end
            local v = string.format("%03d", r[2])
            for k = 1, 3 do
                local x = vx + (k - 1) * 18
                if fd and fd[1] == i and fd[2] == "v" and fd[3] == k then hug_cursor(x - 2, yc, 13) end
                G.textc(fs, string.sub(v, k, k), x + 6, yc, G.C.white, G.JC)
            end
        else
            local first = (i == #P.vne + 1)
            local col = first and G.C.white or G.C.grey_text
            if fd and fd[1] == i and fd[2] == "new" then hug_cursor(altx - 2, yc, G.text_w(fs, "UNUSED")) end
            G.textc(fs, "UNUSED", altx, yc, col)
            G.textc(fs, "000", vx + 18 + 6, yc, col, G.JC)
        end
    end
    local ye = vy(222)
    if fd == nil then hug_cursor(170 * 1.5625 - 22, ye, 44) end
    G.textc(fs, "EXIT", 170 * 1.5625, ye, G.C.white, G.JC)
end

-- DIMMING CURVE (rev Q figures 4.39 / 4.40, p51 dumps): the graph from x 60
-- to 260 LCD px, 0 % on row 180, 100 % on row 20, a dotted grid every 20 %;
-- the input (vertical) and the level (horizontal) in blue, the curve grey,
-- its points 6 px white, the one being set yellow. External: the low-input
-- threshold (PT 7) a grey line upright with its dot, moved left / right
-- only (step 6).
local GX0, GX1, GY0, GY1 = 60 * 1.5625, 260 * 1.5625, (240 - 180) * 374 / 240, (240 - 20) * 374 / 240
local function gx(x) return GX0 + (GX1 - GX0) * x end
local function gy(y) return GY0 + (GY1 - GY0) * y end
local THRESHOLD_DOT = 0.625             -- the dot's height on figure 4.40
local curve_cols = nil

local function dot(x, y, col)
    G.rect(x - 4.7, y - 4.7, x + 4.7, y + 4.7, col)
end

local function draw_curve(f, input, output)
    local fs = fs20()
    local internal = P.dimming_control == "internal"
    local c = internal and P.curve_internal or P.curve_external
    curve_cols = curve_cols or { grid = G.hex("5A5A5A"), axis = G.hex("8C8C8C"), blue = G.hex("1414F0"),
        line = G.hex("9A9A9A"), sel = G.hex("F0F000") }
    local K_ = curve_cols
    -- dotted grid: a dot every 3 LCD px
    for k = 1, 5 do
        local x = gx(k / 5)
        for y = GY0, GY1, 3 * 1.558 do G.rect(x - 0.6, y, x + 0.6, y + 1.2, K_.grid) end
        local yy = gy(k / 5)
        for x2 = GX0, GX1, 3 * 1.5625 do G.rect(x2, yy - 0.6, x2 + 1.2, yy + 0.6, K_.grid) end
    end
    G.rect(GX0 - 0.8, GY0, GX0 + 0.8, GY1, K_.axis)
    G.rect(GX0, GY0 - 0.8, GX1, GY0 + 0.8, K_.axis)
    if not internal then
        local x = gx(P.low_input)
        G.rect(x - 1.8, GY0, x + 1.8, GY1, K_.axis)
    end
    G.rect(gx(input) - 1, GY0, gx(input) + 1, GY1, K_.blue)
    G.rect(GX0, gy(output) - 1, GX1, gy(output) + 1, K_.blue)
    for k = 1, 5 do
        G.line(gx((k - 1) / 5), gy(c[k]), gx(k / 5), gy(c[k + 1]), K_.line, 2)
    end
    for k = 1, 6 do
        dot(gx((k - 1) / 5), gy(c[k]), (f.phase == "points" and f.pt == k) and K_.sel or G.C.white)
    end
    if not internal then
        dot(gx(P.low_input), gy(THRESHOLD_DOT), (f.phase ~= "points") and K_.sel or G.C.white)
    end
    G.textc(fs, "HI", 33 * 1.5625, (240 - 26.5) * 374 / 240, G.C.white)
    G.textc(fs, "LO", 34 * 1.5625, (240 - 174) * 374 / 240, G.C.white)
    local yl = (240 - 196.5) * 374 / 240
    if internal then
        G.textc(fs, "MIN", GX0, yl, G.C.white)
        G.textc(fs, "AMBIENT", 160 * 1.5625, yl, G.C.white, G.JC)
        G.textc(fs, "MAX", 262 * 1.5625, yl, G.C.white, G.JR)
    else
        local v = ({ ext_5v = "5", ext_14v = "14", ext_28v = "28" })[P.dimming_control] or "28"
        G.textc(fs, "0", GX0, yl, G.C.white)
        G.textc(fs, "(VOLTS)", 160 * 1.5625, yl, G.C.white, G.JC)
        G.textc(fs, v, 262 * 1.5625, yl, G.C.white, G.JR)
    end
end

local function draw_message(f)
    local fs = fs20()
    Dsp.title_bar(f.title)
    for i, l in ipairs(f.lines) do
        G.textc(fs, l, 20, ROW0 - PITCH * (i - 1), G.C.white)
    end
end

-- input: where the dimming input is now (0..1), output: the curve's level
function K.draw(input, output)
    G.rect(0, 0, 500, 374, G.C.black)
    local f = top()
    if f == nil then return end
    if f.kind == "list" then draw_list(f)
    elseif f.kind == "choice" then draw_choice(f)
    elseif f.kind == "digits" then draw_digits(f)
    elseif f.kind == "table" then draw_table(f)
    elseif f.kind == "vne" then draw_vne(f)
    elseif f.kind == "curve" then draw_curve(f, input, output)
    elseif f.kind == "message" then draw_message(f)
    elseif f.kind == "dialog" then Fail.MD302_Box_Draw(f.title, f.colour, f.lines, f.ok and "ok" or "yesno_cal", f.cursor, f.centre) end
end

-- rev Q 4.5.1: "CONTINUE HOLDING TO ENTER CONFIG MODE" (rev B: INSTALLER MODE)
function K.draw_hold_message()
    local fs = fs20()
    G.rect(0, 0, 500, 374, G.C.black)
    G.textc(fs, "CONTINUE HOLDING", 250, 222, G.C.white, G.JC)
    G.textc(fs, "TO ENTER", 250, 187, G.C.white, G.JC)
    G.textc(fs, "CONFIG MODE", 250, 152, G.C.white, G.JC)
end

-- for tests: the current page
function K.page()
    local f = top()
    if f == nil then return "" end
    return f.kind .. ":" .. tostring(f.id or f.key or f.phase or f.title or "")
end

return K

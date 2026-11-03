--[[ XLua 2.0 ]]
--[[
*****************************************************************************************
* Program Script Name : Mid-Continent MD302 Standby Attitude Module (2026, XPLM 4 Panel Graphics)
*
* Author Name         : Tiezheng Eric Xu, erix@x-plane.com, Laminar Research
*
* Drawn directly into an ATTR_cockpit_device screen ("laminar_md302") with the
* XPLMPanelGraphics API. Replaces the 2024 xLua 1 MD302.System and its Plane
* Maker generic-instrument layers.
*
* Files (same folder):
*   MD302.lua           this master script: lifecycle, device, datarefs, commands
*   md302_util.lua      helpers (config.ini, datarefs, commands)
*   md302_gfx.lua       drawing layer        md302_unit.lua    behaviour (manual sec. 3)
*   md302_display.lua   the two LCDs         md302_pick.lua    3D knob clicks
*   md302_config.lua    Configuration Mode (installer menu, manual section 4)
*   md302_fail.lua      failure X, message boxes, battery check (manual 5.1.3 / 5.1.4)
*   md302_lcd.lua       the cheap-TFT look of the two LCDs
*   md302_font_data.lua fontbook metrics (generated; glyphs in Textures/Font)
*   md302_bezel.lua     the popup bezel's geometry (generated with popup_bezel.png)
*   Textures/           sprites cut 1:1 from the 2024 art, the LCD look (lcd_*),
*                       anti-aliased lines (aa_*), the popup bezel (a render of 3D/MD302.obj)
*   3D/MD302.obj        the unit, with the screen device and click regions
*   config.ini          the unit's memory: [Options] (pilot), the installer's
*                       Configuration Mode sections (ACCEPT CHANGES) and [State]
*****************************************************************************************
*        Copyright (c) 2026 Tiezheng Eric Xu, erix@x-plane.com, Laminar Research - MIT License, see LICENSE
*****************************************************************************************
--]]

require("XPLMDefs")
require("XPLMDataAccess")
require("XPLMDisplay")
require("XPLMPanelGraphics")
require("XPLMPlanes")
require("XPLMProcessing")
require("XPLMUtilities")

local LCD_W, LCD_H = 500, 374
local DEVICE_ID = "laminar_md302"
local PREFIX = "laminar/md302/"
local SCRIPT_NAME = "MD302"

-----------------------------------------------------------------------------
-- Configuration defaults (overridden by config.ini, see the comments there)
-----------------------------------------------------------------------------

local config = {
    -- [Options] (written back by the unit)
    alt_units = "feet",
    baro_units = "inhg",
    symbol = "delta",
    att_mask = "off",
    alt_trend = "on",
    -- [State] (written by the unit)
    battery_pct = 100,
    run_time_h = 0,
    -- [Power]
    power_bus = 0,
    power_min_volts = 10,
    -- rev Q table 3.2: 1 = lithium-ion (-1 -4), 2 = nickel metal hydride (-7 -8),
    -- none = the versions without a battery (-2 -3 -5 -6)
    battery_type = "1",
    battery_minutes = 120,
    battery_charge_minutes = 180,
    battery_low_pct = 20,
    preflight_s = 5,
    power_down_countdown_s = 60,
    ground_speed_kt = 5,
    ground_ias_kt = 20,
    -- the Configuration Mode sections (manual rev Q 4.5): [Configure Display],
    -- [Configure Heading], [Configure Auto-Off], [Configure Baro Sync],
    -- [Configure ARINC], [Configure Dimming], [Configure Aircraft]
    roll_display = "fixed_scale",
    airspeed_units = "knots",
    airspeed_minimum = 30,
    -- auto: from how MD302.obj is placed in Plane Maker (the .acf)
    display_orientation = "auto",
    horizon_display = "flat",
    heading_display = "on",
    auto_off = "on",
    baro_sync = "off",
    arinc_pass_through = "off",
    dimming_control = "internal",
    dimming_rheostat = 0,
    -- DIMMING CURVE: brightness % at 0, 20, ... 100 % of the dimming input;
    -- the manual's default line (rev Q figures 4.19, 4.39, 4.40). The low-input
    -- threshold (PT 7) in % of the bus range: at or below it the photocell
    -- (rev Q 4.5.5.2 step 6; an older config.ini has a fixed dimming_low_level)
    dimming_curve_internal = "10 28 46 64 82 100",
    dimming_curve_external = "10 28 46 64 82 100",
    dimming_low_input = 0,
    -- no longer used: only read to recognise an older config.ini (check_config)
    dimming_low_level = "",
    -- PANEL TILT / PANEL ROLL: auto = what the .acf mounting needs (the
    -- installer measured it right), or degrees
    panel_tilt = "auto",
    panel_roll = "auto",
    range_mmo = 0,
    range_markings = "auto",
    range1 = "", range2 = "", range3 = "", range4 = "",
    range5 = "", range6 = "", range7 = "", range8 = "",
    vne_table = "",
    ssec_file = "",
    arinc_speed = "high",
    -- [Sources]
    air_data = "stby",
    attitude = "own",
    baro_sync_source = "pilot",
    heading = "pretend",
    -- [Display]
    screen_fb = 2048,
    left_lcd_x = 1400,
    left_lcd_y = 814,
    right_lcd_x = 1400,
    right_lcd_y = 394,
    enable_popup = 1,
    popup_initial = 0,
    lcd_effects = 1,
    lcd_band = 1,
    lcd_bleed = 0.15,
    lcd_grain = 0.1,
    -- [Clicks]
    pick_mode = 1,
    pick_pass_misses = 0,
    pick_debug = 0,

    -- not in config.ini: behaviour constants
    menu_hold_s = 2,              -- 3.3.2: push and hold about 2 s for the Options Menu
    battery_check_min = 60,       -- rev Q 5.1.3: capacity check at power-up, warning below this many minutes
    cfg_msg_s = 6,                -- 4.1: "CONTINUE HOLDING ..." after about 6 s held at power-up
    cfg_intro_s = 9,              -- 4.1: then the introduction screen; let go for the CONFIGURE MENU
    cfg_start_msg_s = 0.5,        -- pushed on the start-up screen: "CONTINUE HOLDING ..." after this long
    cfg_start_enter_s = 3.5,      -- ... and the CONFIGURE MENU by itself after this long held
    menu_timeout_s = 10,          -- 3.3.2: back to the attitude after 10 s without activity
    bright_bar_s = 4,             -- brightness bar stays this long after the last turn
    bright_step = 0.025,          -- brightness bar: dimming level per detent (1/8 doubling)
    baro_highlight_s = 3,         -- baro window stays enlarged / green after the last turn
    trend_s = 6,                  -- 3.3.1.2: altitude trend look-ahead
    trend_tau_s = 1.0,
    slip_tau_s = 0.3,
    -- brightness model (the Garmin G5 plugin's values)
    backlight_neutral = 0.78,
    backlight_doubling = 0.2,
    backlight_min = 0.05,
    ambient_min = 0.002,
    speed_factor = 1,
}

-- the [Options] keys and their valid values
local OPTION_VALUES = {
    alt_units = { feet = true, meters = true },
    baro_units = { inhg = true, hpa = true },
    symbol = { delta = true, split_delta = true, traditional = true },
    att_mask = { off = true, on = true },
    alt_trend = { on = true, off = true },
}
local ENUMS = {
    roll_display = { "fixed_scale", "fixed_pointer" },
    airspeed_units = { "knots", "mph", "kph" },
    display_orientation = { "auto", "horizontal", "vertical_right", "vertical_left", "horizontal_swap" },
    horizon_display = { "flat", "shaded" },
    heading_display = { "on", "off" },
    auto_off = { "on", "off" },
    baro_sync = { "off", "on" },
    arinc_pass_through = { "off", "on" },
    dimming_control = { "internal", "ext_5v", "ext_14v", "ext_28v" },
    range_markings = { "auto", "manual" },
    arinc_speed = { "high", "low" },
    air_data = { "stby", "pilot", "copilot" },
    attitude = { "own", "ahrs", "electric", "vacuum" },
    baro_sync_source = { "pilot", "copilot" },
    heading = { "pretend", "none", "md32", "arinc" },
    battery_type = { "1", "2", "none" },
}
local SPEED_FACTOR = { knots = 1, mph = 1.150779, kph = 1.852 }

-----------------------------------------------------------------------------
-- Module loading: helpers are loaded with loadfile() from this folder and run
-- in this script's environment; `require` is the fallback
-----------------------------------------------------------------------------

local script_dir = ""

local function normalize(p) return (p or ""):gsub("\\", "/") end

local function discover_script_dir()
    local info = debug and debug.getinfo and debug.getinfo(1, "S")
    local src = info and info.source or ""
    if string.sub(src, 1, 1) == "@" then
        local d = normalize(string.sub(src, 2)):match("^(.*)/[^/]*$")
        if d and d ~= "" then return d end
    end
    local model = XPLMGetNthAircraftModel(0)
    local acf = ""
    if type(model) == "table" then acf = normalize(model.outPath or model[2] or "") end
    local aircraft_dir = acf:match("^(.*)/[^/]*$") or "."
    for _, sub in ipairs({ "plugins/xlua/scripts/" .. SCRIPT_NAME, "plugins/xlua2/scripts/" .. SCRIPT_NAME }) do
        local d = aircraft_dir .. "/" .. sub
        local f = io.open(d .. "/" .. SCRIPT_NAME .. ".lua", "r")
        if f then
            f:close()
            return d
        end
    end
    return aircraft_dir .. "/plugins/xlua/scripts/" .. SCRIPT_NAME
end

local function load_module(name)
    local path = script_dir .. "/" .. name .. ".lua"
    if loadfile then
        local chunk, err = loadfile(path)
        if chunk then
            if setfenv and getfenv then setfenv(chunk, getfenv(1)) end
            return chunk()
        end
        print("[MD302 XLua2] loadfile failed: " .. tostring(err))
    end
    if package and package.path and not string.find(package.path, script_dir, 1, true) then
        package.path = script_dir .. "/?.lua;" .. package.path
    end
    return require(name)
end

script_dir = discover_script_dir()

local U = load_module("md302_util")
local G = load_module("md302_gfx")
local M = load_module("md302_unit")
local Dsp = load_module("md302_display")
local Pick = load_module("md302_pick")
local Cfgm = load_module("md302_config")
local FONT = load_module("md302_font_data")
local LCD = load_module("md302_lcd")
local Fail = load_module("md302_fail")
-- the popup bezel's geometry (generated with Textures/popup_bezel.png); the
-- same numbers if the file is missing
local BZ_DEFAULT = { bezel_w = 1400, bezel_h = 608, screen_x = 129, screen_y = 118, gap = 142,
    knob_x = 700.0, knob_y = 94.7, knob_r = 76.4, knob_sprite = 168, shadow_sprite = 200 }
local okb, BZ = pcall(load_module, "md302_bezel")
if okb and type(BZ) == "table" then
    for k in pairs(BZ_DEFAULT) do
        if type(BZ[k]) ~= "number" then okb = false end
    end
end
if not okb or type(BZ) ~= "table" then BZ = BZ_DEFAULT end
local POPUP_GAP = BZ.gap              -- between the two LCDs in the popup (as on the unit)

local log = U.log
local st = M.st

local IMAGES = {
    "att_roll_arc", "att_slip_box", "att_roll_pointer", "att_chevron",
    "sym_delta", "sym_traditional", "slip_ball", "batt_icon", "att_mask",
    "windows_spd", "windows_alt", "windows_fill_spd", "windows_fill_alt", "preflight_logo", "mmo_tape",
    "lcd_band", "lcd_bleed", "lcd_grain", "aa_horizon", "aa_bar10", "aa_bar5",
    "popup_bezel", "popup_knob", "popup_knob_shadow",
}

-----------------------------------------------------------------------------
-- Runtime handles
-----------------------------------------------------------------------------

local avionic, popup = nil, nil
local popup_visible = false
local flight_loop = nil
local commands, cmd_ids = {}, {}
local drs = {}
local out = {}
local heartbeat = 0
local last_error, error_count = {}, 0      -- last message per place: two failing places do not flood the log

local function report_error(where, err)
    error_count = error_count + 1
    local msg = where .. ": " .. tostring(err)
    if msg ~= last_error[where] or error_count % 600 == 0 then
        log("ERROR " .. msg)
        last_error[where] = msg
    end
end

-----------------------------------------------------------------------------
-- config.ini: read once, [Options] / [State] lines rewritten in place
-----------------------------------------------------------------------------

local function config_path() return script_dir .. "/config.ini" end

-- values check_config had to replace (load: an ERROR box, 5.1.4)
local config_fixes = 0

-- "auto" or degrees within +-lim, on a step (PANEL TILT 0.1, PANEL ROLL 0.5)
local function angle_or_auto(key, lim, step)
    local s = string.lower(tostring(config[key]))
    if s == "auto" then
        config[key] = "auto"
        return nil
    end
    local v = tonumber(s)
    if v == nil or v ~= v or v < -lim or v > lim then
        log(string.format("config.ini: %s = '%s' is not auto or -%g..%g, using auto", key, s, lim, lim))
        config_fixes = config_fixes + 1
        config[key] = "auto"
        return nil
    end
    return math.floor(v / step + 0.5) * step
end

-- VNE TABLE (rev Q 4.5.2.5): "alt kts alt kts ..." (up to 7 points, altitude
-- in feet from 0 up, airspeed in AIRSPEED UNITS) -> { {alt, v}, ... }, or {}
local function parse_vne(s)
    local n = {}
    for w in tostring(s):gmatch("%S+") do n[#n + 1] = tonumber(w) or -1 end
    if #n == 0 then return {} end
    local pts, ok = {}, (#n % 2 == 0) and #n <= 14
    for i = 1, #n - 1, 2 do
        local a, v = n[i], n[i + 1]
        local prev = pts[#pts]
        ok = ok and a <= 99999 and v >= 0 and v <= 999
        -- the first point at 0 ft; two at one altitude = a step (rev Q figure 4.34 case 1)
        if prev then ok = ok and a >= prev[1] else ok = ok and a == 0 end
        if not ok then break end
        pts[#pts + 1] = { a, v }
    end
    if ok and pts[1][2] == 0 then return {} end     -- 0 ft at 000: no table (figure 4.33)
    if not ok then
        log("config.ini: vne_table = '" .. tostring(s) .. "' is not up to 7 pairs 'feet speed' from 0 ft up, ignored")
        config_fixes = config_fixes + 1
        config.vne_table = ""
        return {}
    end
    return pts
end

-- the keys config.ini has (U.read_ini): a file from before rev Q has no panel_roll
local config_seen = {}

local function check_config()
    -- before rev Q this package's PANEL TILT changed nothing (its README said so),
    -- so the value an old config.ini holds is only decoration: read as auto
    if config_seen.panel_tilt and not config_seen.panel_roll and string.lower(tostring(config.panel_tilt)) ~= "auto" then
        log("config.ini: panel_tilt = " .. tostring(config.panel_tilt)
            .. " is from before rev Q (it changed nothing then): read as auto")
        config.panel_tilt = "auto"
    end
    -- an older config.ini: [Sources] baro_sync = pilot | copilot (rev B: on with that
    -- side's input); now CONFIGURE BARO SYNC on | off and baro_sync_source
    -- an older config.ini (it has a dimming_low_level value):
    -- its photocell curve meant the level itself (default 83 .. 100, tuned to
    -- X-Plane's ambient); now a level counts from the manual's default line
    -- (md302_unit.lua screen_brightness), so each point moves by default - old
    -- default and the screen looks as it did. The bus curve's old default
    -- (5 .. 100) becomes the manual's 10 .. 100. Written back once.
    config.curve_migrated = nil
    if config_seen.dimming_low_level and tostring(config.dimming_low_level) ~= "" then
        local shift = { -73, -56, -41, -26, -12, 0 }
        local c, k, ok = {}, 0, true
        for n in tostring(config.dimming_curve_internal):gmatch("%S+") do
            k = k + 1
            local v = tonumber(n)
            ok = ok and v ~= nil and shift[k] ~= nil
            c[k] = string.format("%d", U.clamp(math.floor((v or 0) + (shift[k] or 0) + 0.5), 5, 100))
        end
        if ok and k == 6 then
            local new = table.concat(c, " ")
            log("older config.ini: dimming_curve_internal = " .. tostring(config.dimming_curve_internal)
                .. " read as " .. new .. " (the same look)")
            config.dimming_curve_internal = new
        end
        if tostring(config.dimming_curve_external):gsub("%s+", " "):match("^%s*(.-)%s*$") == "5 24 43 62 81 100" then
            config.dimming_curve_external = "10 28 46 64 82 100"
        end
        config.curve_migrated = true
        config.dimming_low_level = ""           -- once: a later check (ACCEPT) does not move it again
    end
    local bs = string.lower(tostring(config.baro_sync))
    if bs == "pilot" or bs == "copilot" then
        log("config.ini: baro_sync = " .. bs .. " (before rev Q) read as baro_sync = on, baro_sync_source = " .. bs)
        config.baro_sync, config.baro_sync_source = "on", bs
    end
    for key, list in pairs(ENUMS) do
        local v = string.lower(tostring(config[key]))
        local ok = false
        for _, o in ipairs(list) do ok = ok or (o == v) end
        if not ok then
            log("config.ini: " .. key .. " = '" .. v .. "' is not valid (" .. table.concat(list, " | ")
                .. "), using " .. list[1])
            v = list[1]
            config_fixes = config_fixes + 1
        end
        config[key] = v
    end
    for key, valid in pairs(OPTION_VALUES) do
        local v = string.lower(tostring(config[key]))
        if not valid[v] then
            local default = ({ alt_units = "feet", baro_units = "inhg", symbol = "delta", att_mask = "off",
                alt_trend = "on" })[key]
            log("config.ini: " .. key .. " = '" .. v .. "' is not valid, using " .. default)
            v = default
            config_fixes = config_fixes + 1
        end
        M.opt[key] = v
    end
    config.speed_factor = SPEED_FACTOR[config.airspeed_units]
    -- AIRSPEED MINIMUM (rev Q 4.5.6.2): 20 | 30 | 40 knots
    local amin = tonumber(config.airspeed_minimum)
    if amin ~= 20 and amin ~= 30 and amin ~= 40 then
        log("config.ini: airspeed_minimum = '" .. tostring(config.airspeed_minimum) .. "' is not 20 | 30 | 40, using 30")
        config_fixes = config_fixes + 1
        amin = 30
    end
    config.airspeed_minimum = amin
    config.panel_tilt_set = angle_or_auto("panel_tilt", 90, 0.1)
    config.panel_roll_set = angle_or_auto("panel_roll", 5, 0.5)
    config.vne_points = parse_vne(config.vne_table)
    config.ssec_file = tostring(config.ssec_file or ""):gsub("%s+", "")
    -- numbers that would break the model (division by zero, negative times)
    local LIMITS = {
        battery_minutes = { 1, 10000 }, battery_charge_minutes = { 1, 10000 },
        battery_low_pct = { 0, 100 }, preflight_s = { 0, 60 }, power_down_countdown_s = { 1, 3600 },
        ground_speed_kt = { 0, 100 }, ground_ias_kt = { 0, 200 }, power_min_volts = { 0, 100 },
        battery_pct = { 0, 100 }, run_time_h = { 0, 1e6 }, range_mmo = { 0, 0.999 }, screen_fb = { 512, 8192 },
        dimming_low_input = { 0, 100 },
        dimming_rheostat = { 0, 31 }, power_bus = { 0, 5 },
        lcd_effects = { 0, 1 }, lcd_band = { 0, 1 }, lcd_bleed = { 0, 1 }, lcd_grain = { 0, 1 },
        -- the installer mode times (not in config.ini, but read like any key):
        -- 0 would open the CONFIGURE MENU on any push of the start-up screen
        cfg_msg_s = { 0, 60 }, cfg_intro_s = { 1, 60 }, cfg_start_msg_s = { 0, 60 }, cfg_start_enter_s = { 1, 60 },
    }
    for key, lim in pairs(LIMITS) do
        local v = config[key]
        if v ~= v or v < lim[1] or v > lim[2] then
            local fixed = (v ~= v) and lim[1] or U.clamp(v, lim[1], lim[2])
            log(string.format("config.ini: %s = %s is out of range (%g..%g), using %g", key, tostring(v), lim[1], lim[2], fixed))
            config[key] = fixed
            config_fixes = config_fixes + 1
        end
    end
    -- an index or a pixel size: a whole number (a dataref index of 1.5 is an
    -- error under Lua 5.3+)
    for _, key in ipairs({ "power_bus", "dimming_rheostat", "screen_fb" }) do
        local v = config[key]
        if v ~= math.floor(v) then
            log(string.format("config.ini: %s = %s is not a whole number, using %d", key, tostring(v), math.floor(v + 0.5)))
            config[key] = math.floor(v + 0.5)
            config_fixes = config_fixes + 1
        end
    end
    -- the two dimming curves: six whole percentages each
    for _, kind in ipairs({ "internal", "external" }) do
        local key = "dimming_curve_" .. kind
        local c = {}
        local ok = true
        for n in tostring(config[key]):gmatch("%S+") do
            local v = tonumber(n)
            ok = ok and v ~= nil and v >= 5 and v <= 100
            c[#c + 1] = v or 0
        end
        ok = ok and #c == 6
        if not ok then
            local default = "10 28 46 64 82 100"
            log("config.ini: " .. key .. " = '" .. tostring(config[key]) .. "' is not six values 5..100, using " .. default)
            config[key] = default
            config_fixes = config_fixes + 1
            c = {}
            for n in default:gmatch("%S+") do c[#c + 1] = tonumber(n) end
        end
        for i = 1, 6 do c[i] = c[i] / 100 end
        config["curve_" .. kind] = c
    end
end

-- config.ini lines in one rewrite; false (logged) when they could not be saved
local function save_lines(list, what)
    -- rev Q 3.6: SETTINGS COULD NOT BE FOUND is for one power-up; a config.ini
    -- deleted since is written again, with the lines saved now (defaults for the rest);
    -- so is one that is there but unreadable (kept as config.ini.broken)
    local path = config_path()
    local present = U.file_exists(path)
    if not present or not U.ini_intact(path) then
        if present and os and os.rename and os.remove then
            os.remove(path .. ".broken")
            os.rename(path, path .. ".broken")
        end
        if U.write_ini(path, list, "Mid-Continent MD302 (xLua 2.0): config.ini was missing or unreadable and was "
            .. "written again by the unit; settings not listed use their defaults (README.md)") then
            log("config.ini was " .. (present and "unreadable (kept as config.ini.broken)" or "missing")
                .. ": written again with " .. what)
            return true
        end
    end
    local ok, saved, why = pcall(U.ini_set_many, config_path(), list)
    if ok and saved then return true end
    log("ERROR config.ini: could not save " .. what .. " (" .. tostring(ok and why or saved) .. ")")
    return false
end

local function save_option(key, value)
    config[key] = value
    save_lines({ { key, value } }, key .. " = " .. value)
end

local function save_state()
    save_lines({ { "battery_pct", string.format("%.1f", st.batt_pct) },
                 { "run_time_h", string.format("%.2f", st.run_time_s / 3600) } }, "battery charge and run time")
end

-----------------------------------------------------------------------------
-- Sim snapshot
-----------------------------------------------------------------------------

local D = {
    pitch = 0, roll = 0, slip_deg = 0,
    ias_kt = 0, alt_ft = 0, baro_inhg = 29.92,
    groundspeed_kt = 0, bus_volts = 0, dim_input = 1,
    p_dps = 0, q_dps = 0,
    vmo_kt = 0, bands = {}, vne = nil,
    heading = nil, oat_c = 15,
    run_time = 0, paused = 0, replay = 0,
}
local dr = {}

-- How MD302.obj sits in the aircraft (md302_pick.lua reads the .acf at
-- enable): q = the quarter the pictures turn by (Plane Maker roll -90 = knob
-- on the right, +90 = knob on the left), tilt = panel tilt (top leaning back
-- +), roll = what is left of the roll beyond the quarter. nil: no .acf slot
-- (the pictures follow display_orientation).
local mount = nil

local function set_mount(m)
    mount = nil
    if m == nil then return end
    local phi = (m.phi + 180) % 360 - 180
    local q = 0
    if phi <= -45 and phi > -135 then q = -90 elseif phi >= 45 and phi < 135 then q = 90 end
    if math.abs(phi) >= 135 then
        log(string.format("MD302.obj is upside down in the .acf (roll %.1f): not an installation the unit allows; drawn horizontal", m.phi))
    end
    mount = { q = q, tilt = -m.the, roll = (math.abs(phi) >= 135) and 0 or (phi - q) }
    -- rev Q 2.1 (figure 2.1): the unit must be installed facing the direction
    -- of flight; there is no setting for a turned unit (a degree or two of
    -- modelling slack is let through)
    local psi = (m.psi + 180) % 360 - 180
    if math.abs(psi) > 2 then
        log(string.format("MD302.obj is turned %.1f deg in heading in the .acf: the unit must face the direction of flight", psi))
    end
    if math.abs(mount.roll) > 5 then
        log(string.format("MD302.obj is rolled %.1f deg off the quarter: PANEL ROLL corrects 5 at most", mount.roll))
    end
    log(string.format("mounting from the .acf: %s, panel tilt %.1f, roll %.1f",
        ({ [0] = "horizontal", [-90] = "vertical right (knob right)", [90] = "vertical left (knob left)" })[q],
        mount.tilt, mount.roll))
end

-- PANEL TILT / PANEL ROLL (rev Q 4.5.2.1-2): the unit's sensor turns with it;
-- the configured angles take the mounting out again. auto = configured right.
-- Returns what the unit then adds to pitch and roll (0 when right).
local function mount_errors()
    local t = mount and mount.tilt or 0
    local r = mount and mount.roll or 0
    local ct = config.panel_tilt_set
    if ct == nil then ct = U.clamp(t, -90, 90) end
    local cr = config.panel_roll_set
    if cr == nil then cr = U.clamp(r, -5, 5) end
    return ct - t, r - cr
end

-- PANEL TILT / ROLL as the unit holds them (auto: what the mounting needs)
function M.panel_angles()
    local t = mount and mount.tilt or 0
    local r = mount and mount.roll or 0
    local ct = config.panel_tilt_set
    if ct == nil then ct = math.floor(U.clamp(t, -90, 90) * 10 + 0.5) / 10 end
    local cr = config.panel_roll_set
    if cr == nil then cr = math.floor(U.clamp(r, -5, 5) * 2 + 0.5) / 2 end
    return ct, cr
end

-- the quarter the .acf mounting asks for (nil: not known)
function M.mount_q() return mount and mount.q end

local AIR = {
    stby = { "sim/cockpit2/gauges/indicators/airspeed_kts_stby", "sim/cockpit2/gauges/indicators/altitude_ft_stby",
        "sim/cockpit2/gauges/actuators/barometer_setting_in_hg_stby" },
    pilot = { "sim/cockpit2/gauges/indicators/airspeed_kts_pilot", "sim/cockpit2/gauges/indicators/altitude_ft_pilot",
        "sim/cockpit2/gauges/actuators/barometer_setting_in_hg_pilot" },
    copilot = { "sim/cockpit2/gauges/indicators/airspeed_kts_copilot", "sim/cockpit2/gauges/indicators/altitude_ft_copilot",
        "sim/cockpit2/gauges/actuators/barometer_setting_in_hg_copilot" },
}
local ATT = {
    own = { "sim/flightmodel/position/theta", "sim/flightmodel/position/phi" },
    ahrs = { "sim/cockpit2/gauges/indicators/pitch_AHARS_deg_pilot", "sim/cockpit2/gauges/indicators/roll_AHARS_deg_pilot" },
    electric = { "sim/cockpit2/gauges/indicators/pitch_electric_deg_pilot", "sim/cockpit2/gauges/indicators/roll_electric_deg_pilot" },
    vacuum = { "sim/cockpit2/gauges/indicators/pitch_vacuum_deg_pilot", "sim/cockpit2/gauges/indicators/roll_vacuum_deg_pilot" },
}

local function find_datarefs()
    local a, t = AIR[config.air_data], ATT[config.attitude]
    dr.ias, dr.alt, dr.baro = U.find(a[1]), U.find(a[2]), U.find(a[3])
    dr.pitch, dr.roll = U.find(t[1]), U.find(t[2])
    -- X-Plane's own failures (Flight > Failures) of the instruments the unit
    -- reads give the same red X as laminar/md302/fail_* (6 = inoperative). The
    -- standby air data and the unit's own AHRS have no instrument failure in
    -- X-Plane; a blocked pitot or static port is no failure the unit can see:
    -- it shows what X-Plane then reports, as the real unit would
    local xf = ({ pilot = { "rel_ss_asi", "rel_ss_alt" }, copilot = { "rel_cop_asi", "rel_cop_alt" } })[config.air_data]
    local xa = ({ ahrs = "rel_g_arthorz", electric = "rel_elec_gyr", vacuum = "rel_ss_ahz" })[config.attitude]
    dr.xfail_ias = xf and U.find("sim/operation/failures/" .. xf[1]) or nil
    dr.xfail_alt = xf and U.find("sim/operation/failures/" .. xf[2]) or nil
    dr.xfail_att = xa and U.find("sim/operation/failures/" .. xa) or nil
    -- ARINC 429 inputs are X-Plane's: the baro setting of that side's altimeter,
    -- heading from X-Plane's magnetic heading (MD32) or the pilot's AHRS (ARINC);
    -- pretend (no real MD302 setting, a plug-and-use default): X-Plane's
    -- magnetic heading, never lost, drawn with the ARINC arrows
    dr.sync = U.find(AIR[config.baro_sync_source][3])
    local mag_psi = "sim/flightmodel/position/mag_psi"
    dr.hdg = ({ md32 = U.find(mag_psi), pretend = U.find(mag_psi),
        arinc = U.find("sim/cockpit2/gauges/indicators/heading_AHARS_deg_mag_pilot") })[config.heading]
    -- the ARINC heading's AHRS failing in X-Plane (Flight > Failures, AHRS)
    dr.xfail_hdg = (config.heading == "arinc") and U.find("sim/operation/failures/rel_g_arthorz") or nil
    dr.oat = U.find("sim/cockpit2/temperature/outside_air_temp_degc")
    dr.slip = U.find("sim/cockpit2/gauges/indicators/slip_deg")
    dr.gs = U.find("sim/flightmodel/position/groundspeed")
    dr.P = U.find("sim/flightmodel/position/P")
    dr.Q = U.find("sim/flightmodel/position/Q")
    dr.bus = U.find("sim/cockpit2/electrical/bus_volts")
    -- the external dimming input, the lighting bus: the panel-light rheostat on
    -- the powered bus (X-Plane 12 _manual, 1:1 with the knob; the plain
    -- instrument_brightness_ratio has X-Plane's own night dimming in it, about
    -- 1 % at night)
    dr.dim = U.find("sim/cockpit2/electrical/instrument_brightness_ratio_manual")
        or U.find("sim/cockpit2/electrical/instrument_brightness_ratio")
    dr.mach = U.find("sim/flightmodel/misc/machno")
    dr.run_time = U.find("sim/time/total_running_time_sec")
    dr.paused = U.find("sim/time/paused")
    dr.replay = U.find("sim/time/is_in_replay")
    for _, k in ipairs({ "Vso", "Vs", "Vfe", "Vno", "Vne" }) do
        dr["acf_" .. k] = U.find("sim/aircraft/view/acf_" .. k)
    end
end

-- VNE TABLE: the speed at this altitude, the points joined by lines, the last
-- line on beyond the last point, below 0 ft the 0 ft speed (rev Q 4.5.2.5)
local function vne_at(pts, alt)
    if #pts == 0 then return nil end
    if #pts == 1 or alt <= 0 then return pts[1][2] end
    local i = 1
    while i < #pts - 1 and alt > pts[i + 1][1] do i = i + 1 end
    local a, b = pts[i], pts[i + 1]
    -- two points at one altitude: a step (rev Q figure 4.34 case 1), the later
    -- one above it (also the last segment, carried on flat); while being typed
    -- the rows can be out of order: the same rule, no division by zero
    if b[1] <= a[1] then return (alt > b[1]) and b[2] or a[2] end
    return a[2] + (b[2] - a[2]) * (alt - a[1]) / (b[1] - a[1])
end

-- a dataref's number, or d when it is not a finite one (NaN or +-inf, which
-- only an instructor override writes: a pitch of inf never ends the ladder loop)
local function fin(v, d)
    if v ~= v or v == math.huge or v == -math.huge then return d end
    return v
end

local function read_sim()
    local tilt_err, roll_err = mount_errors()
    D.pitch = fin(U.getf(dr.pitch, 0), 0) + tilt_err
    D.roll = fin(U.getf(dr.roll, 0), 0) + roll_err
    D.hdg_raw = dr.hdg and (fin(U.getf(dr.hdg, 0), 0) % 360) or nil
    D.oat_c = fin(U.getf(dr.oat, 15), 15)
    D.slip_deg = fin(U.getf(dr.slip, 0), 0)
    D.ias_kt = math.max(0, fin(U.getf(dr.ias, 0), 0))
    D.alt_ft = fin(U.getf(dr.alt, 0), 0)
    D.baro_inhg = fin(U.getf(dr.baro, 29.92), 29.92)
    D.groundspeed_kt = fin(U.getf(dr.gs, 0), 0) * 1.943844
    D.p_dps = fin(U.getf(dr.P, 0), 0)
    D.q_dps = fin(U.getf(dr.Q, 0), 0)
    D.xfail_ias = U.geti(dr.xfail_ias, 0) == 6
    D.xfail_alt = U.geti(dr.xfail_alt, 0) == 6
    D.xfail_att = U.geti(dr.xfail_att, 0) == 6
    D.bus_volts = fin(U.getfa(dr.bus, config.power_bus, 0), 0)
    -- no aircraft power: no lighting bus either (rev Q step 6: "turned off or
    -- fails open" hands the screen to the photocell)
    D.dim_input = (D.bus_volts >= config.power_min_volts) and fin(U.getfa(dr.dim, config.dimming_rheostat, 1), 1) or 0
    D.run_time = fin(U.getf(dr.run_time, 0), 0)
    D.paused = U.geti(dr.paused, 0)
    D.replay = U.geti(dr.replay, 0)
    if config.range_mmo > 0 then
        local mach = fin(U.getf(dr.mach, 0), 0)
        D.vmo_kt = (mach > 0.05) and D.ias_kt * config.range_mmo / mach or 0
    end
    D.vne = vne_at(config.vne_points, D.alt_ft)
end
M.vne_at = vne_at

-- Heading source lost (rev Q 4.3.1.2): the window runs on the unit's own gyro
-- for 10 s, without the source arrows (figure 4.6, gyroscopic heading), then
-- shows "---"; back at once with the source. ARINC (the pilot's AHRS) is
-- lost with the aircraft's power or X-Plane's AHRS failure: X-Plane's AHRS
-- heading itself carries on unpowered (12.4, master switch off), so it
-- cannot tell. MD32 runs on the MD302's own power and never fails; nor does
-- pretend, which has nothing to lose.
-- dt: simulator time (the gyro's 10 s stand while paused)
local HDG_GYRO_S = 10
local hdg_lost_t = 0
local function update_heading(dt)
    local lost = config.heading == "arinc"
        and (D.bus_volts < config.power_min_volts or U.geti(dr.xfail_hdg, 0) == 6)
    if lost then
        if hdg_lost_t == 0 then log("heading: ARINC source lost, gyro for " .. HDG_GYRO_S .. " s") end
        hdg_lost_t = hdg_lost_t + math.max(dt, 1e-6)
    elseif hdg_lost_t > 0 then
        hdg_lost_t = 0
        log("heading: ARINC source back")
    end
    D.hdg_gyro = lost
    D.heading = (not lost or hdg_lost_t < HDG_GYRO_S) and D.hdg_raw or nil
end

-- airspeed range markings (rev Q 4.5.2.4, figure 4.33), in the display unit:
-- rangeN = <FULL|HALF|RAD|OFF> <WHT|GRN|YEL|RED|BLU|BAR> <V1> <V2|MAX> (V2 999 =
-- MAX); the words of an older config.ini are read too: F / H, white green
-- ..., magenta and amber (rev B colours, kept as they were), lower = upper
-- for a radial, an upper above 999 as MAX
local BAND_WIDTH = { full = "F", f = "F", half = "H", h = "H", rad = "R", off = "OFF" }
local BAND_COLOUR = { wht = "white", white = "white", grn = "green", green = "green", yel = "yellow",
    yellow = "yellow", red = "red", blu = "blue", blue = "blue", bar = "bar",
    mag = "magenta", magenta = "magenta", amb = "amber", amber = "amber" }

local function parse_band(s)
    local w, col, lo, hi = s:match("^%s*(%a+)%s+(%a+)%s+(%d+%.?%d*)%s+(%w+%.?%d*)%s*$")
    w, col = BAND_WIDTH[w or ""], BAND_COLOUR[col or ""]
    lo = tonumber(lo)
    hi = (hi == "max") and 999 or tonumber(hi)
    if not (w and col and lo and hi and lo <= 999) then return nil end
    hi = math.min(hi, 999)
    if (w == "F" or w == "H") and lo == hi and lo > 0 then w = "R" end
    if w == "R" then hi = lo end                -- a radial: V2 = V1 (4.5.2.4 4b)
    return { width = w, color = col, lo = lo, hi = hi }
end

local function build_bands()
    local b = {}
    if config.range_markings == "manual" then
        for i = 1, 8 do
            local s = string.lower(config["range" .. i] or "")
            if s ~= "" then
                local band = parse_band(s)
                if band == nil then
                    log("config.ini: range" .. i .. " = '" .. s .. "' is not '<FULL|HALF|RAD|OFF> "
                        .. "<WHT|GRN|YEL|RED|BLU|BAR> <V1> <V2|MAX>', ignored")
                elseif band.width ~= "OFF" and (band.lo > 0 or band.hi > 0) then
                    band.row = i                        -- its row in the table (Configuration Mode)
                    b[#b + 1] = band                    -- 000 / 000 or OFF: no bar (4.5.2.4 5a)
                end
            end
        end
    else
        local f = config.speed_factor
        local v = {}
        for _, k in ipairs({ "Vso", "Vs", "Vfe", "Vno", "Vne" }) do v[k] = U.getf(dr["acf_" .. k], 0) * f end
        -- as rev Q figure 4.33 example 1: white full width Vso - Vs, half width
        -- Vso - Vfe over the green, no red below Vso (rev B's note asking for
        -- red 0 - Vso is gone from rev Q). A band whose V-speed is missing (0 in
        -- the .acf) is left out; drawn in this order, the half-width white last
        local function add(w, col, lo, hi)
            if lo > 0 and hi > lo then b[#b + 1] = { width = w, color = col, lo = lo, hi = hi } end
        end
        add("F", "white", v.Vso, v.Vs)
        add("F", "green", (v.Vs > 0) and v.Vs or v.Vso, v.Vno)
        add("F", "yellow", v.Vno, v.Vne)
        add("F", "red", v.Vne, 999)
        add("H", "white", v.Vso, v.Vfe)
        log(string.format("range markings from the aircraft: Vso %.0f, Vs %.0f, Vfe %.0f, Vno %.0f, Vne %.0f (%s)",
            v.Vso, v.Vs, v.Vfe, v.Vno, v.Vne, config.airspeed_units))
    end
    D.bands = b
    M.bands = b
    M.n_bands = #b
end

-- ACCEPT CHANGES (4.5.3): the changed Configuration Mode keys into config.ini
-- (only those lines), applied at once; the unit restarts after it
local rebuild_popup             -- set below (devices)

local function commit_config(changes)
    if #changes == 0 then return end
    local orient0 = config.display_orientation
    -- one rewrite for all of them, so the file never holds half a change
    if not save_lines(changes, "the configuration") then
        log("the configuration applies until the aircraft is reloaded")
    end
    for _, kv in ipairs(changes) do
        local key, text = kv[1], kv[2]
        config_seen[key] = true
        config[key] = (type(config[key]) == "number") and (tonumber(text) or config[key]) or text
        log("configuration: " .. key .. " = " .. text)
    end
    check_config()
    build_bands()
    if config.display_orientation ~= orient0 and rebuild_popup then rebuild_popup() end
end

-----------------------------------------------------------------------------
-- Drawing
-----------------------------------------------------------------------------

local bright_level = 1

-- DISPLAY ORIENTATION (rev Q 4.5.6.3): the quarter the pictures are turned by
-- in the panel. VERTICAL RIGHT (knob on the right) = the unit turned a quarter
-- counter-clockwise, so the pictures are turned clockwise (-90) and the
-- right LCD of the horizontal unit is now the upper one; VERTICAL LEFT the
-- other way round. The attitude is always on the upper LCD (4.3.1.1).
-- The pictures follow how MD302.obj is placed in Plane Maker (the .acf);
-- display_orientation only when the .acf has no MD302.obj slot.
local function orientation()
    local q = M.mount_q()
    if q ~= nil then return q end
    local o = config.display_orientation
    if o == "vertical_right" then return -90 end
    if o == "vertical_left" then return 90 end
    return 0
end

-- HORIZONTAL (SWAP): a horizontal unit with the attitude on the right LCD
local function swapped()
    return orientation() == 0 and config.display_orientation == "horizontal_swap"
end

-- what the unit is set to, as REVIEW CONFIG names it
function M.orientation_name()
    local q = orientation()
    if q < 0 then return "VERTICAL RIGHT" end
    if q > 0 then return "VERTICAL LEFT" end
    return swapped() and "HORIZONTAL (SWAP)" or "HORIZONTAL"
end

-- a page laid out for the horizontal LCD (menus, dialogs, Configuration
-- Mode, start-up) on an upright one: shrunk to its width, centred
local function page(L, fn, ...)
    if L.W == LCD_W then return fn(...) end
    local s = L.W / LCD_W
    G.push()
    G.translate(0, (L.H - LCD_H * s) / 2)
    G.scale(s)
    fn(...)
    G.pop()
end

-- one LCD's picture, L = its layout (Dsp.LAY.h / .v); role "att" = the
-- attitude side (menus, dialogs, Configuration Mode), "air" = air data
local function draw_lcd(role, L)
    G.rect(0, 0, L.W, L.H, G.C.black)
    if st.mode == M.OFF then return end
    local att = (role == "att")
    if st.mode == M.CFG_ENTRY then
        -- 4.1: dark, then "CONTINUE HOLDING ...", then the introduction screen;
        -- begun on the start-up screen: that screen stays, the message after
        -- half a second on the attitude LCD
        if st.cfg_from_start then
            if att and st.cfg_t >= config.cfg_start_msg_s then
                page(L, Cfgm.draw_hold_message)
            else
                Dsp.preflight(st, L)
            end
        elseif st.cfg_t >= config.cfg_intro_s then
            Dsp.preflight(st, L)
        elseif st.cfg_t >= config.cfg_msg_s and att then
            page(L, Cfgm.draw_hold_message)
        end
    elseif st.mode == M.CONFIG then
        -- rev Q 4.5 (figure 4.28): the menu on the air-data LCD, a live
        -- preview of the setting on the attitude one (attitude or air data,
        -- with the pending values)
        if not att then
            -- a configuration mode message (rev Q 5.14 - 5.16) over the menu
            if Fail.Msg then page(L, Fail.MD302_Msg_Draw) else page(L, Cfgm.draw, st.dim_x, st.dim_level) end
        elseif Cfgm.preview_kind() == "air" then
            Cfgm.with_pending(D, Dsp.air_data, D, st, L)
        else
            Cfgm.with_pending(D, Dsp.attitude, D, st, bright_level, L)
        end
    elseif st.mode == M.PREFLIGHT then
        Dsp.preflight(st, L)
    elseif att then
        -- the power-down countdown (rev Q 4.4.2) is a box over the attitude
        if Fail.Msg and not st.pd then
            page(L, Fail.MD302_Msg_Draw)
        elseif st.menu then
            page(L, Dsp.menu, st)
        else
            Dsp.attitude(D, st, bright_level, L)
        end
    else
        Dsp.air_data(D, st, L)
    end
end

-- one LCD at (x, y), fw x fh as it is shown there; q: the quarter its picture
-- is turned by (3D, vertical), look_q: the quarter of the panel's own look
-- (popup, vertical). An error on one LCD is reported and that LCD's stacks
-- unwound; the other LCD still draws.
-- the LCD look's strength for each device ("3d" / "popup"): each has its own
-- brightness callback, which may get its own ambient
local look_k = { ["3d"] = 1, popup = 1 }
local drawing = "3d"

local function draw_at(role, x, y, fw, fh, q, look_q)
    local L = (orientation() == 0) and Dsp.LAY.h or Dsp.LAY.v
    local mark = G.mark()
    G.push()
    G.translate(x, y)
    G.clip(0, 0, fw, fh)
    if q ~= 0 then G.quarter_begin(q, L.W, L.H) end
    local ok, err = pcall(draw_lcd, role, L)
    G.quarter_end()
    G.unwind_to(mark)
    if not ok then report_error("draw " .. role, err) end
    -- the cheap TFT itself: only while its backlight is on
    if st.mode ~= M.OFF then
        G.push()
        G.translate(x, y)
        G.clip(0, 0, fw, fh)
        if look_q ~= 0 then G.quarter_begin(look_q, LCD_W, LCD_H) end
        ok, err = pcall(LCD.MD302_LCD_Look, LCD_W, LCD_H, look_k[drawing])
        G.quarter_end()
        G.unwind_to(mark)
        if not ok then report_error("lcd look", err) end
    end
end

-- The popup is the unit's face (Textures/popup_bezel.png, md302_bezel.lua)
-- with the two LCDs in it. A vertical unit's popup is that face turned as
-- the unit is in the panel (vertical right = a quarter counter-clockwise,
-- the knob on the right), the LCDs upright, the attitude on top.

-- the whole window (the bezel)
local function popup_size()
    if orientation() == 0 then return BZ.bezel_w, BZ.bezel_h end
    return BZ.bezel_h, BZ.bezel_w
end

-- the screen: both LCDs and the gap between them
local function popup_screen_size()
    if orientation() == 0 then return 2 * LCD_W + POPUP_GAP, LCD_H end
    return LCD_H, 2 * LCD_W + POPUP_GAP
end

-- a point of the horizontal bezel where it is in this popup
local function bezel_point(x, y)
    local q = orientation()
    if q == 0 then return x, y end
    if q > 0 then return y, BZ.bezel_w - x end      -- turned clockwise: the knob on the left
    return BZ.bezel_h - y, x                        -- counter-clockwise: on the right
end

-- the screen's bottom-left in the popup
local function popup_screen_offset()
    local q = orientation()
    if q == 0 then return BZ.screen_x, BZ.screen_y end
    if q > 0 then return bezel_point(BZ.screen_x + 2 * LCD_W + POPUP_GAP, BZ.screen_y) end
    return bezel_point(BZ.screen_x, BZ.screen_y + LCD_H)
end

local function draw_screen(ref)
    G.reset_frame()
    drawing = ref
    local q = orientation()
    if ref == "3d" then
        G.rect(0, 0, config.screen_fb, config.screen_fb, G.C.black)
        local left_role, right_role = "att", "air"
        if q < 0 or swapped() then left_role, right_role = "air", "att" end
        draw_at(left_role, config.left_lcd_x, config.left_lcd_y, LCD_W, LCD_H, q, 0)
        draw_at(right_role, config.right_lcd_x, config.right_lcd_y, LCD_W, LCD_H, q, 0)
    elseif q == 0 then
        -- the popup: the LCDs only; the gap between them is left empty, the
        -- bezel (the knob's top) shows through it
        local left_role, right_role = "att", "air"
        if swapped() then left_role, right_role = "air", "att" end
        G.rect(0, 0, LCD_W, LCD_H, G.C.black)
        G.rect(LCD_W + POPUP_GAP, 0, 2 * LCD_W + POPUP_GAP, LCD_H, G.C.black)
        draw_at(left_role, 0, 0, LCD_W, LCD_H, 0, 0)
        draw_at(right_role, LCD_W + POPUP_GAP, 0, LCD_W, LCD_H, 0, 0)
    else
        -- a vertical unit's popup: both LCDs upright, the attitude on top
        G.rect(0, 0, LCD_H, LCD_W, G.C.black)
        G.rect(0, LCD_W + POPUP_GAP, LCD_H, 2 * LCD_W + POPUP_GAP, G.C.black)
        draw_at("att", 0, LCD_W + POPUP_GAP, LCD_H, LCD_W, 0, -q)
        draw_at("air", 0, 0, LCD_H, LCD_W, 0, -q)
    end
end

-- refcon: { "3d" | "popup" }
local function screen_draw_cb(ref)
    local ok, err = pcall(draw_screen, ref[1])
    if not ok then
        report_error("draw", err)
        pcall(G.unwind)
    end
end

-- X-Plane lays the screen over the bezel layer additively (black lets the
-- bezel show through), so the bezel has to be opaque: black, and in the
-- popup the unit's face (its LCD areas black)
-- the knob without its images: a grey disc
local function vector_knob()
    local pts = {}
    for i = 0, 31 do
        local a = i * math.pi / 16
        pts[#pts + 1] = BZ.knob_x + BZ.knob_r * math.cos(a)
        pts[#pts + 1] = BZ.knob_y + BZ.knob_r * math.sin(a)
    end
    G.poly(G.C.grey or G.rgba(0.35, 0.35, 0.35, 1), pts)
end

-- the knob as the 3D one is: turned by knob_val_for_setting (the OBJ's key 0
-- is -45 deg, one turn per 1, clockwise as it grows) and pushed in by
-- knob_push_anim, which deepens its shadow. The shadow falls down-left in the
-- window, whichever way the unit is turned (the light is the cockpit's).
local function draw_knob(q)
    local kx, ky = bezel_point(BZ.knob_x, BZ.knob_y)
    local p = U.clamp(tonumber(st.knob_push) or 0, 0, 1)
    local s = BZ.shadow_sprite * (1 + 0.06 * p) / 2
    local dx, dy = -(1 + p), -(4 + 3 * p)
    G.image("popup_knob_shadow", kx + dx - s, ky + dy - s, kx + dx + s, ky + dy + s, G.rgba(1, 1, 1, 0.55 + 0.4 * p))
    if q ~= 0 then G.quarter_begin(-q, BZ.bezel_w, BZ.bezel_h) end
    local h, k = BZ.knob_sprite / 2, 1 - 0.12 * p
    if not G.pic_pivot("popup_knob", BZ.knob_x, BZ.knob_y, h, h, 45 + 360 * (tonumber(st.knob_val) or 0),
            G.rgba(k, k, k, 1)) then
        vector_knob()
    end
    G.quarter_end()
end

local function draw_bezel(ref)
    if ref == "popup" then
        -- the unit's face, see-through outside its rounded edge (its LCD
        -- areas opaque black); without the image an opaque black box
        G.reset_frame()
        local q = orientation()
        if G.img["popup_bezel"] == nil then
            local pw, ph = popup_size()
            G.rect(0, 0, pw, ph, G.C.black)
        end
        if q ~= 0 then G.quarter_begin(-q, BZ.bezel_w, BZ.bezel_h) end
        G.image("popup_bezel", 0, 0, BZ.bezel_w, BZ.bezel_h)
        G.quarter_end()
        draw_knob(q)
    else
        G.rect(0, 0, config.screen_fb, config.screen_fb, G.C.black)
    end
end

local function bezel_draw_cb(r, g, b, ref)
    local ok, err = pcall(draw_bezel, ref[1])
    if not ok then
        report_error("bezel", err)
        pcall(G.unwind)
    end
end

local function brightness_cb(rheo, ambient, bus, ref)
    local ok, v, level = pcall(M.screen_brightness, ambient, D)
    if not ok then return 1 end
    bright_level = level or bright_level
    look_k[ref[1]] = st.look_k
    return v
end

-----------------------------------------------------------------------------
-- Popup window
-----------------------------------------------------------------------------

-- X-Plane's screen (global desktop, y up): left, top, right, bottom, or nil
local function screen_bounds()
    local ok, b = pcall(XPLMGetScreenBoundsGlobal)
    if not ok or type(b) ~= "table" then return nil end
    local function num(x) return tonumber(tostring(x)) or 0 end
    local l, t, r, bo = num(b.outLeft or b[1]), num(b.outTop or b[2]), num(b.outRight or b[3]), num(b.outBottom or b[4])
    if r <= l or t <= bo then return nil end
    return l, t, r, bo
end

-- the popup keeps the bezel's aspect, and stays on the screen: an upright one
-- (a vertical unit, 608 x 1400 at 1x) is taller than most screens, and
-- X-Plane puts it half off the screen, so it is
-- held to 85 % of the screen and moved onto it. fresh = not yet sized in this
-- session: an upright one then comes up at 85 % of the screen's height, its
-- LCDs about as large as before the bezel (two thirds of the screen for the
-- LCDs alone); X-Plane gave it the 608 px of a remembered horizontal one, or
-- its full 1400 px
local function lock_popup_aspect(fresh)
    if not popup then return end
    local ok, geom = pcall(XPLMGetAvionicsGeometry, popup)
    if not ok or type(geom) ~= "table" then return end
    local left = tonumber(tostring(geom.outLeft)) or 100
    local top = tonumber(tostring(geom.outTop)) or 600
    local bottom = tonumber(tostring(geom.outBottom)) or (top - 187)
    local h = math.abs(top - bottom)
    local pw, ph = popup_size()
    if h < 100 then h = ph / 2 end              -- no size yet: half size (an upright one is tall)
    local sl, stop, sr, sbot = screen_bounds()
    if fresh and sl and orientation() ~= 0 then h = 0.85 * (stop - sbot) end
    local w = h * pw / ph
    if sl then
        local fit = math.min(1, 0.85 * (stop - sbot) / h, 0.85 * (sr - sl) / w)
        w, h = w * fit, h * fit
        left = U.clamp(left, sl, sr - w)
        top = U.clamp(top, sbot + h, stop)
    end
    XPLMSetAvionicsGeometry(popup, math.floor(left), math.floor(top), math.floor(left + w), math.floor(top - h))
end

-- The popup device lives only while its window is open (closing the popup
-- destroys the window, it is not hidden). It is created on
-- opening (popup_toggle / popup_show / a click on the 3D screens) and
-- destroyed on the toggle command, on the window's own close button (also
-- when popped out to an OS window) and at disable. xLua builds before
-- 2.0.0-b5 cap a script at 500 callbacks, which many openings can use up.
-- It opens again where it was last.
local popup_seen, popup_grace, popup_geom = false, 0, nil
local popup_out = false     -- popped out to an OS window (cursor_report only)

-- The popup's knob: the same commands as the 3D knob's click regions. A
-- click on its middle pushes it (held: the Options Menu after 2 s), on its
-- left / right half turns it, the wheel over it turns it. Anywhere else the
-- click is X-Plane's (it drags the window). The knob's top reaches into the
-- gap between the LCDs, which is the screen's: the screen's mouse
-- callbacks pass there too, in popup px.
local KNOB_CMD = { push = "press_knob", left = "knob_left", right = "knob_right" }
local knob_held = nil       -- the command a popup click holds down

-- a point of this popup on the horizontal bezel (bezel_point undone)
local function bezel_unturn(x, y)
    local q = orientation()
    if q == 0 then return x, y end
    if q > 0 then return BZ.bezel_w - y, x end
    return y, BZ.bezel_h - x
end

-- popup px -> "push" | "left" | "right" | nil; the halves as seen in the
-- window; never on an LCD (the knob's rim reaches their corners)
local function knob_at(x, y)
    local hx, hy = bezel_unturn(x, y)
    local lx = hx - BZ.screen_x
    if hy >= BZ.screen_y and hy <= BZ.screen_y + LCD_H
            and ((lx >= 0 and lx <= LCD_W) or (lx >= LCD_W + POPUP_GAP and lx <= 2 * LCD_W + POPUP_GAP)) then
        return nil
    end
    local kx, ky = bezel_point(BZ.knob_x, BZ.knob_y)
    local dx, dy = x - kx, y - ky
    local d = math.sqrt(dx * dx + dy * dy)
    if d > BZ.knob_r + 4 then return nil end
    if d <= 0.45 * BZ.knob_r then return "push" end
    return (dx < 0) and "left" or "right"
end

local function knob_release()
    if knob_held then
        XPLMCommandEnd(knob_held)
        knob_held = nil
    end
end

local function knob_click(x, y, mouse)
    if mouse == XPLMMouseStatus.xplm_MouseDown then
        knob_release()
        local what = knob_at(x, y)
        local c = what and commands[KNOB_CMD[what]]
        if not c then return false end
        XPLMCommandBegin(c)
        knob_held = c
        return true
    end
    local held = knob_held ~= nil
    if mouse == XPLMMouseStatus.xplm_MouseUp then knob_release() end
    return held
end

local function knob_wheel(x, y, wheel, clicks)
    if wheel ~= 0 or clicks == 0 or not knob_at(x, y) then return false end
    local c = commands[(clicks > 0) and "knob_right" or "knob_left"]
    if c then
        for _ = 1, math.min(math.abs(clicks), 10) do XPLMCommandOnce(c) end
    end
    return true
end

local CURSOR = { push = "xplm_CursorHandle", left = "xplm_CursorRotateMediumLeft", right = "xplm_CursorRotateMediumRight" }
local function knob_cursor(x, y, src)
    local what = knob_at(x, y)
    local key = CURSOR[what or ""] or "xplm_CursorDefault"
    local cur = (XPLMCursorStatus and XPLMCursorStatus[key]) or 0
    U.cursor_note(src, what, cur, x, y)
    return cur
end

-- an error is reported; a click then is not taken (the window still drags)
local function guarded(what, fn, fail, ...)
    local ok, ret = pcall(fn, ...)
    if ok then return ret end
    report_error("popup " .. what, ret)
    return fail
end

local function screen_px(x, y)
    local ox, oy = popup_screen_offset()
    return x + ox, y + oy
end

local function bezel_click_cb(x, y, mouse, ref) return guarded("click", knob_click, false, x, y, mouse) end
local function bezel_scroll_cb(x, y, wheel, clicks, ref) return guarded("wheel", knob_wheel, false, x, y, wheel, clicks) end
local function bezel_cursor_cb(x, y, ref) return guarded("cursor", knob_cursor, 0, x, y, "popup_bezel") end
local function screen_touch_cb(x, y, mouse, ref)
    local px, py = screen_px(x, y)
    return guarded("click", knob_click, false, px, py, mouse)
end
local function screen_scroll_cb(x, y, wheel, clicks, ref)
    local px, py = screen_px(x, y)
    return guarded("wheel", knob_wheel, false, px, py, wheel, clicks)
end
local function screen_cursor_cb(x, y, ref)
    local px, py = screen_px(x, y)
    return guarded("cursor", knob_cursor, 0, px, py, "popup_screen")
end

local function make_popup()
    local pw, ph = popup_size()
    local sw, sh = popup_screen_size()
    local ox, oy = popup_screen_offset()
    return XPLMCreateAvionicsEx({
        screenWidth = sw,
        screenHeight = sh,
        bezelWidth = pw,
        bezelHeight = ph,
        screenOffsetX = ox,
        screenOffsetY = oy,
        bezelDrawCallback = bezel_draw_cb,
        drawCallback = screen_draw_cb,
        brightnessCallback = brightness_cb,
        bezelClickCallback = bezel_click_cb,
        bezelScrollCallback = bezel_scroll_cb,
        bezelCursorCallback = bezel_cursor_cb,
        screenTouchCallback = screen_touch_cb,
        screenScrollCallback = screen_scroll_cb,
        screenCursorCallback = screen_cursor_cb,
        deviceID = DEVICE_ID .. "_popup",
        deviceName = "MD302 Popup",
        refcon = { "popup" },
        contentType = XPLMWindowContentType.xplm_WindowContentTypePanelGraphics,
    })
end

local function destroy_popup(why)
    if popup == nil then return end
    pcall(knob_release)                 -- a push held while the window goes
    XPLMDestroyAvionics(popup)
    popup = nil
    popup_visible, popup_seen, popup_grace = false, false, 0
    log("popup closed (" .. why .. "): window destroyed")
end

local function open_popup()
    if popup ~= nil or config.enable_popup == 0 then return end
    local ok, dev = pcall(make_popup)
    if not ok or dev == nil then
        log("ERROR popup could not be created: " .. tostring(dev))
        return
    end
    popup = dev
    XPLMSetAvionicsBrightnessRheo(popup, 1.0)
    XPLMSetAvionicsPopupVisible(popup, true)
    if popup_geom then
        XPLMSetAvionicsGeometry(popup, popup_geom[1], popup_geom[2], popup_geom[3], popup_geom[4])
    end
    -- a rebuild for a new orientation keeps only the top-left corner (1 px)
    lock_popup_aspect(popup_geom == nil or popup_geom[3] - popup_geom[1] <= 1)
    popup_visible, popup_seen, popup_grace = true, false, 30
end

-- every frame: a window closed with its own button is destroyed; while it is
-- up, its place is kept for the next opening (not while popped out: then the
-- geometry is the OS window's)
local function update_popup()
    if popup == nil then return end
    local ok, vis = pcall(XPLMIsAvionicsPopupVisible, popup)
    if ok and vis then
        popup_seen = true
        local okp, out = pcall(XPLMIsAvionicsPoppedOut, popup)
        popup_out = (okp and out) and true or false
        if not (okp and out) then
            local okg, g = pcall(XPLMGetAvionicsGeometry, popup)
            if okg and type(g) == "table" then
                local function num(x) return math.floor(tonumber(tostring(x)) or 0) end
                local l, t, r, b = num(g.outLeft), num(g.outTop), num(g.outRight), num(g.outBottom)
                if r > l and t > b then popup_geom = { l, t, r, b } end
            end
        end
        return
    end
    if popup_seen then
        destroy_popup("window closed")
        return
    end
    popup_grace = popup_grace - 1
    if popup_grace <= 0 then destroy_popup("never shown") end
end

local function set_popup_visible(v)
    if v then open_popup() else destroy_popup("command") end
end

-----------------------------------------------------------------------------
-- Commands (the old MD302.System names, so old manipulators keep working)
-----------------------------------------------------------------------------

local BEGIN = XPLMCommandPhase.xplm_CommandBegin
local CONTINUE = XPLMCommandPhase.xplm_CommandContinue

local COMMAND_LIST = {
    { "knob_left", "MD302 knob turn left", function(p) if p == BEGIN then M.knob_turn(-1, D) end end },
    { "knob_right", "MD302 knob turn right", function(p) if p == BEGIN then M.knob_turn(1, D) end end },
    { "press_knob", "MD302 knob push (hold 2 s: Options Menu)", function(p)
        if p == BEGIN then M.knob_press(0, D) elseif p ~= CONTINUE then M.knob_press(2, D) end
    end },
    { "popup_toggle", "MD302 toggle popup window", function(p) if p == BEGIN then set_popup_visible(popup == nil) end end },
    -- a click on the 3D screens (MD302.obj): opens it, never closes it
    { "popup_show", "MD302 show popup window", function(p) if p == BEGIN then open_popup() end end },
    -- Configuration Mode without holding the knob through a power-up (on the ground)
    { "config_mode", "MD302 restart in Configuration Mode (on the ground)", function(p)
        if p == BEGIN then M.enter_config() end
    end },
    -- 2024 MD302.System commands: the Options Menu at once; stay on the
    -- battery (the power-down box answered ON)
    { "goes_into_setting", "MD302 open the Options Menu", function(p) if p == BEGIN then M.open_menu() end end },
    { "power_down_off", "MD302 power-down: remain on (ON)", function(p) if p == BEGIN then M.remain_on() end end },
}

local function create_commands()
    for _, c in ipairs(COMMAND_LIST) do
        commands[c[1]] = XPLMCreateCommand(PREFIX .. c[1], c[2])
    end
end

local function register_handlers()
    for _, c in ipairs(COMMAND_LIST) do
        local fn = c[3]
        cmd_ids[c[1]] = U.reg_cmd(commands[c[1]], function(cmd, phase, ref)
            local ok, err = pcall(fn, phase)
            if not ok then report_error("command " .. c[1], err) end
            return true
        end)
    end
end

local function unregister_handlers()
    for name, id in pairs(cmd_ids) do
        U.unreg_cmd(commands[name], id)
        cmd_ids[name] = nil
    end
end

-----------------------------------------------------------------------------
-- Datarefs: read-only outputs (xLua storage when offered, else accessors)
-----------------------------------------------------------------------------

local OUT = {
    -- knob animation of MD302.obj: 1 = one turn, 16 detents
    { "knob_val_for_setting", "f", function() return st.knob_val end },
    { "knob_pressed", "i", function() return st.knob_down and 1 or 0 end },
    -- the knob's push animation of MD302.obj: 0 out .. 1 pushed in, 0.08 s travel
    { "knob_push_anim", "f", function() return st.knob_push end },
    { "unit_on", "i", function() return (st.mode ~= M.OFF) and 1 or 0 end },
    -- the 2024 MD302.System values: -1 off, 0 pre-flight, 1 flight, 3 Options
    -- Menu or Configuration Mode
    { "ops_mode_now", "i", function()
        if st.mode == M.OFF then return -1 end
        if st.mode == M.PREFLIGHT or st.mode == M.CFG_ENTRY then return 0 end
        if st.mode == M.CONFIG then return 3 end
        return st.menu and 3 or 1
    end },
    { "on_battery", "i", function() return M.on_battery() and 1 or 0 end },
    -- the valid signal (pin 2, manual 1.2: grounded = valid, open = invalid):
    -- 1 in flight mode with nothing failed, 0 off, starting, in a menu of the
    -- installer or with a red X up
    { "valid", "i", function()
        if st.mode ~= M.FLIGHT then return 0 end
        return (Fail.ATT or Fail.IAS or Fail.ALT) and 0 or 1
    end },
    { "battery_pct", "f", function() return st.batt_pct end },
    { "menu_open", "i", function() return st.menu and 1 or 0 end },
    { "config_mode", "i", function() return (st.mode == M.CONFIG) and 1 or 0 end },
    { "power_down_timer_remain", "f", function() return st.pd and st.pd.t or 0 end },
    { "alt_trend_fpm", "f", function() return st.vs_fpm end },
    { "popup_visible", "i", function() return popup_visible and 1 or 0 end },
    { "xlua_heartbeat", "i", function() return heartbeat end },
    -- the 2024 MD302.System names, so panels made for it keep working: the
    -- Options Menu settings (0 / 1 as 2024; SYMBOL 2 = SPLIT DELTA, new in
    -- rev Q), on the ground (no motion, no airspeed), the BARO value shown
    { "options_alt_units_now", "i", function() return (M.opt.alt_units == "meters") and 1 or 0 end },
    { "options_baro_units_now", "i", function() return (M.opt.baro_units == "hpa") and 0 or 1 end },
    { "options_symbol_now", "i", function()
        return ({ delta = 0, traditional = 1, split_delta = 2 })[M.opt.symbol] or 0
    end },
    { "options_att_mask_now", "i", function() return (M.opt.att_mask == "on") and 1 or 0 end },
    { "options_alt_trend_now", "i", function() return (M.opt.alt_trend == "on") and 1 or 0 end },
    { "on_ground", "i", function() return st.on_ground and 1 or 0 end },
    { "pressure_display_val", "f", function()
        return (M.opt.baro_units == "hpa") and math.floor(D.baro_inhg * 33.8639 + 0.5) or D.baro_inhg
    end },
}

-- writable inputs for an instructor or a scenario (5.1.4): 1 = failed;
-- fail_message = 1..12 puts up that box (md302_fail.lua) and reads back 0;
-- 12, BATTERY OVER TEMPERATURE, also fails the battery (on it: off at once)
local function fail_message(n)
    if n <= 0 then return end
    if n == Fail.MSG_BATTERY_TEMP and not M.has_battery() then
        log("fail_message 12 (battery over temperature) ignored: battery_type = none")
        return
    end
    if n == Fail.MSG_BATTERY_TEMP then
        M.battery_overtemp()
        if st.mode == M.OFF then return end
    end
    Fail.MD302_Msg_Queue(n)
    if st.mode == M.FLIGHT then Fail.MD302_Msg_Show_Next() end
    if st.mode == M.CONFIG then M.show_config_messages() end
end
local IN = {
    { "fail_attitude", function(v) Fail.Fail_ATT_Req = v end, function() return Fail.Fail_ATT_Req end },
    { "fail_airspeed", function(v) Fail.Fail_IAS_Req = v end, function() return Fail.Fail_IAS_Req end },
    { "fail_altimeter", function(v) Fail.Fail_ALT_Req = v end, function() return Fail.Fail_ALT_Req end },
    { "fail_message", fail_message, function() return 0 end },
}
local inp = {}

-- laminar/md302/cursor_report (diagnostics): one line of key=value for a
-- cursor-reporter script, built when it is read: the last cursor callback
-- X-Plane called on this unit (U.cursor_note: n counts the calls, t =
-- XPLMGetElapsedTime then, src / part / cur / x / y), and the popup: open /
-- closed / out (popped out), geom = its window (global boxels: left, top,
-- right, bottom), bezel = its size in popup px, screen = the screen's x, y,
-- w, h in it (both LCDs and the gap), knob = x, y, r.
local function cursor_report()
    local c = U.cursor
    local state = (popup == nil or not popup_visible) and "closed" or (popup_out and "out" or "open")
    local geom = (state == "open" and popup_geom) and table.concat(popup_geom, ",") or "-"
    local pw, ph = popup_size()
    local sw, sh = popup_screen_size()
    local ox, oy = popup_screen_offset()
    local kx, ky = bezel_point(BZ.knob_x, BZ.knob_y)
    return string.format(
        "n=%d t=%.3f src=%s part=%s cur=%d x=%d y=%d popup=%s geom=%s bezel=%d,%d screen=%d,%d,%d,%d knob=%.0f,%.0f,%.0f",
        c.n, c.t, c.src, c.part, c.cur, c.x, c.y, state, geom, pw, ph, ox, oy, sw, sh, kx, ky, BZ.knob_r)
end

local function create_outputs()
    for _, d in ipairs(OUT) do out[d[1]] = U.native_number(PREFIX .. d[1]) end
    for _, d in ipairs(IN) do inp[d[1]] = U.native_number_w(PREFIX .. d[1]) end
end

local function poll_inputs()
    for _, d in ipairs(IN) do
        local h = inp[d[1]]
        if h then
            local v = math.floor((U.native_get(h) or 0) + 0.5)
            d[2](v)
            if d[1] == "fail_message" and v ~= 0 then U.native_set(h, 0) end
        end
    end
end

local function push_outputs()
    for _, d in ipairs(OUT) do
        local h = out[d[1]]
        if h then U.native_set(h, d[3]()) end
    end
end

local function register_datarefs()
    for _, d in ipairs(IN) do
        if not inp[d[1]] then
            local set, get = d[2], d[3]
            drs[#drs + 1] = U.reg_int(PREFIX .. d[1], function() return get() end,
                function(_, v) set(math.floor((tonumber(v) or 0) + 0.5)) end)
        end
    end
    for _, d in ipairs(OUT) do
        if not out[d[1]] then
            local fn = d[3]
            if d[2] == "i" then
                drs[#drs + 1] = U.reg_int(PREFIX .. d[1], function() return fn() end)
            else
                drs[#drs + 1] = U.reg_float(PREFIX .. d[1], function() return fn() end)
            end
        end
    end
    -- diagnostics only: a build without byte-data datarefs goes on without it
    if XPLMDataTypeID.xplmType_Data then
        local ok, h = pcall(U.reg_string, PREFIX .. "cursor_report", function()
            local okr, s = pcall(cursor_report)
            return okr and s or ""
        end)
        if ok and h ~= nil then drs[#drs + 1] = h end
    end
end

local function unregister_datarefs()
    for i = #drs, 1, -1 do
        U.unreg_dataref(drs[i])
        drs[i] = nil
    end
end

-----------------------------------------------------------------------------
-- Flight loop
-----------------------------------------------------------------------------

-- simulator time step: frozen while paused or in replay; a jump counts as one frame
local last_run_time = nil
local function sim_step(real_dt)
    local t = D.run_time or 0
    local d = 0
    if last_run_time ~= nil and t > last_run_time then d = t - last_run_time end
    last_run_time = t
    if D.paused ~= 0 or D.replay ~= 0 then return 0 end
    if d > 5 then d = real_dt end
    return d
end

local save_t = 0

	--ARINC 429 baro input (1.1): the primary system's baro setting keeps the
	--MD302's in step; the knob still sets it until the primary's changes again.
	--In step: the arrows by BARO (rev Q figure 4.8); a change from the primary
	--lights the window green like the knob (figure 4.10). Held to the unit's
	--28.00 - 31.00 inHg (1.2)
	local Sync_Last = nil
	local function MD302_Baro_Sync_Reset()		--new flight: in step again at once
		Sync_Last = nil
	end
	local function MD302_Baro_Sync()
		if config.baro_sync == "off" or dr.sync == nil then
			Sync_Last = nil						--in step at once when it is turned on
			st.baro_synced = false
			return
		end
		if st.mode == M.OFF then
			Sync_Last = nil						--in step again at the next power-up
			st.baro_synced = false
			return
		end
		local v = U.getf(dr.sync, 29.92)
		if v ~= v or v == math.huge or v == -math.huge then return end	--not a number: nothing to follow
		if Sync_Last == nil or math.abs(v - Sync_Last) > 0.0005 then
			Sync_Last = v
			local held = U.clamp(v, 28.00, 31.00)
			st.baro_synced = held == v			--held at a limit: not the primary's setting
			v = held
			if math.abs(v - D.baro_inhg) > 0.0005 then
				U.setf(dr.baro, v)
				D.baro_inhg = v
				st.baro_t = config.baro_highlight_s
			end
		end
	end

-- each step on its own pcall: one that throws (logged) does not stop the ones
-- after it (the popup lifecycle, the outputs, the 5-minute save)
local function try(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then report_error(where, err) end
end

local function tick(dt)
    try("read_sim", read_sim)
    try("inputs", poll_inputs)
    local ok, sdt = pcall(sim_step, dt)
    if not ok then
        report_error("sim_step", sdt)
        sdt = 0
    end
    try("heading", update_heading, sdt)
    try("failures", Fail.MD302_Fail_Update, D, sdt)
    try("unit", M.update, sdt, dt, D)
    try("baro_sync", MD302_Baro_Sync)
    try("pick", Pick.update, dt)
    try("popup", update_popup)
    try("outputs", push_outputs)
    save_t = save_t + sdt
    if save_t >= 300 then
        save_t = 0
        try("save_state", save_state)
    end
end

local function flight_loop_cb(since_call, since_loop, counter, refcon)
    heartbeat = heartbeat + 1
    local dt = U.clamp(since_call or 0, 0.0, 0.1)
    try("update", tick, dt)
    return -1
end

-----------------------------------------------------------------------------
-- Lifecycle
-----------------------------------------------------------------------------

local function start()
    local restored = U.ini_recover(config_path())
    if restored then log("config.ini was missing or broken after an interrupted save: restored from " .. restored) end
    local found = U.read_ini(config_path(), config, config_seen)
    -- an empty or zero-filled config.ini with nothing to put it back from
    -- counts as no config.ini: defaults
    if found and not U.ini_intact(config_path()) then found = false end
    config_fixes = 0
    check_config()
    if config.curve_migrated then
        save_lines({ { "dimming_curve_internal", config.dimming_curve_internal },
            { "dimming_curve_external", config.dimming_curve_external }, { "dimming_low_level", "" } },
            "the dimming curves of an older config.ini")
    end
    Fail.init(U, G)
    -- 5.1.4: what the load found shows at the first flight mode: config.ini
    -- damaged (back from its .bak) = the external settings were invalid, no
    -- config.ini = defaults, values replaced = settings missing or invalid
    if restored and string.sub(restored, -4) == ".bak" then
        Fail.MD302_Msg_Queue(Fail.MSG_EXTERNAL_INVALID)
    elseif not found then
        Fail.MD302_Msg_Queue(Fail.MSG_NOT_FOUND)
    end
    if config_fixes > 0 then Fail.MD302_Msg_Queue(Fail.MSG_SETTINGS_INVALID) end
    st.batt_pct = U.clamp(config.battery_pct, 0, 100)
    st.run_time_s = math.max(0, config.run_time_h) * 3600
    M.init(U, config, Cfgm, Fail)
    Cfgm.init(U, G, M, config, Dsp, Fail)
    Cfgm.hooks.commit = commit_config
    M.save_option = save_option
    M.save_state = save_state
    -- the knob's setting; when the MD302's air data is the sync source's
    -- altimeter (air_data = baro_sync_source) it lands on that same setting:
    -- taken as already seen, not as a change from the primary
    M.set_baro = function(inhg)
        U.setf(dr.baro, inhg)
        if Sync_Last ~= nil and config.air_data == config.baro_sync_source then Sync_Last = U.getf(dr.sync, inhg) end
    end
    M.SW_VERSION = Dsp.SW_VERSION
    Dsp.init(U, G, M, config, Fail)
    Pick.init(U, config)
    G.init_colors()
    LCD.init(G, config, log)
    G.load_images(U.xp_relative(script_dir), IMAGES, FONT, log)
    find_datarefs()
    create_commands()
    create_outputs()
    log(string.format("options: alt %s, baro %s, symbol %s, att mask %s, alt trend %s; battery %.0f %%",
        M.opt.alt_units, M.opt.baro_units, M.opt.symbol, M.opt.att_mask, M.opt.alt_trend, st.batt_pct))
end

function XPluginStart()
    log("XPluginStart, script dir: " .. script_dir)
    local ok, err = pcall(start)
    if not ok then
        log("ERROR XPluginStart failed: " .. tostring(err))
        return false
    end
    return true
end

local function create_devices()
    local fb = config.screen_fb
    avionic = XPLMCreateAvionicsEx({
        screenWidth = fb,
        screenHeight = fb,
        bezelWidth = fb,
        bezelHeight = fb,
        screenOffsetX = 0,
        screenOffsetY = 0,
        bezelDrawCallback = bezel_draw_cb,
        drawCallback = screen_draw_cb,
        brightnessCallback = brightness_cb,
        deviceID = DEVICE_ID,
        deviceName = "MD302",
        refcon = { "3d" },
        contentType = XPLMWindowContentType.xplm_WindowContentTypePanelGraphics,
    })
    XPLMSetAvionicsBrightnessRheo(avionic, 1.0)
    XPLMSetAvionicsPopupVisible(avionic, false)
    -- the popup is a separate device (one device shares one framebuffer),
    -- created when it opens (open_popup)
    if config.popup_initial ~= 0 then open_popup() end
end

-- a new DISPLAY ORIENTATION (ACCEPT CHANGES): an open popup comes back in the
-- new shape, at its old top-left corner; a closed one opens so next time (its
-- old size is the other shape's)
rebuild_popup = function()
    if popup_geom then popup_geom = { popup_geom[1], popup_geom[2], popup_geom[1] + 1, popup_geom[2] - 1 } end
    if popup == nil then return end
    destroy_popup("new orientation")
    open_popup()
    log("popup rebuilt for " .. config.display_orientation)
end

-- each step on its own pcall (try): one that throws does not leave the
-- others registered
local function teardown()
    if flight_loop then
        try("disable: flight loop", XPLMDestroyFlightLoop, flight_loop)
        flight_loop = nil
    end
    try("disable: pick", Pick.disable)
    try("disable: popup", destroy_popup, "disable")
    popup = nil
    if avionic then
        try("disable: device", XPLMDestroyAvionics, avionic)
        avionic = nil
    end
    try("disable: commands", unregister_handlers)
    try("disable: datarefs", unregister_datarefs)
end

local function enable()
    register_datarefs()
    register_handlers()
    local model = XPLMGetNthAircraftModel(0)
    local acf = type(model) == "table" and U.unwrap_string(model.outPath or model[2]) or tostring(model or "")
    acf = U.normalize_path(acf)
    -- the mounting first: the popup takes its shape from it
    local okm, m = pcall(Pick.mount, script_dir .. "/3D/MD302.obj", acf)
    if not okm then report_error("mounting", m) end
    set_mount(okm and m or nil)
    if mount == nil then log("no MD302.obj slot in the .acf: display_orientation = " .. config.display_orientation) end
    create_devices()
    build_bands()
    local ok, err = pcall(Pick.load, script_dir .. "/3D/MD302.obj", acf)
    if ok then ok, err = pcall(Pick.enable) end
    if not ok then report_error("pick", err) end
    flight_loop = XPLMCreateFlightLoop({
        phase = XPLMFlightLoopPhaseType.xplm_FlightLoop_Phase_AfterFlightModel,
        callbackFunc = flight_loop_cb,
        refcon = nil,
    })
    XPLMScheduleFlightLoop(flight_loop, -1, true)
end

-- a failure half-way must not leave datarefs or handlers registered: undo
-- everything and report the plugin as not enabled
function XPluginEnable()
    log("XPluginEnable")
    local ok, err = pcall(enable)
    if not ok then
        log("ERROR XPluginEnable failed, everything unregistered: " .. tostring(err))
        pcall(teardown)
        return false
    end
    return true
end

function XPluginDisable()
    log("XPluginDisable")
    pcall(save_state)        -- a failing save must not skip the teardown
    teardown()               -- each step on its own pcall
end

function XPluginStop()
    log("XPluginStop")
    G.destroy_images()
end

local MSG_PLANE_LOADED = XPLM_MSG_PLANE_LOADED or 102
local MSG_AIRPORT_LOADED = XPLM_MSG_AIRPORT_LOADED or 103

-- X-Plane sends other messages too (115 about every minute): only a new
-- flight resets the unit
function XPluginReceiveMessage(from, msg, param)
    if from ~= (XPLM_PLUGIN_XPLANE or 0) then return end
    if msg == MSG_AIRPORT_LOADED or (msg == MSG_PLANE_LOADED and (param == 0 or param == nil)) then
        pcall(save_state)
        M.reset()
        MD302_Baro_Sync_Reset()
        last_run_time = nil
        pcall(build_bands)
    end
end

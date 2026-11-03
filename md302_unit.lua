-- Copyright (c) 2026 Tiezheng Eric Xu, erix@x-plane.com, Laminar Research - MIT License, see LICENSE
--
-- md302_unit.lua: what the MD302 does (Mid-Continent Installation Manual and
-- Operating Instructions 9017782 rev Q, section 4.2-4.4): power and the modes, the internal battery, the
-- single push-and-turn knob, the Options Menu and its INFO pages, the
-- brightness bar and the baro setting. MD302.lua feeds it a sim snapshot D
-- every frame; md302_display.lua draws what is in M.st.

local M = {}

local U, cfg, Cfgm, Fail

-- CFG_ENTRY: powered up with the knob held (4.1) or the knob pushed on the
-- start-up screen, CONFIG: Configuration Mode
M.OFF, M.PREFLIGHT, M.FLIGHT, M.CONFIG, M.CFG_ENTRY = 0, 1, 2, 3, 4

local st = {
    mode = 0,
    ext_power = false,
    batt_pct = 100,
    run_time_s = 0,
    preflight_t = 0,
    cfg_t = 0,              -- time the knob has been held in CFG_ENTRY
    cfg_from_start = false, -- CFG_ENTRY begun by a push on the start-up screen
    on_ground = true,
    dim_x = 1,              -- dimming input now, 0..1 (ambient^0.25 or the lighting bus)
    dim_level = 1,          -- the dimming curve's level for it
    -- knob
    knob_down = false,
    knob_t = 0,
    knob_long = false,
    knob_val = 0,           -- OBJ knob animation, 1 = one turn (16 detents)
    knob_push = 0,          -- OBJ knob push animation, 0 out .. 1 pushed in (follows knob_down)
    bar_before = false,
    -- overlays
    -- page: "root" | "info" | "review" | "software" | "battery"
    menu = nil,             -- { page, sel, entered, opt, idle, top, isel }
    bright_t = 0,           -- brightness bar time left (s)
    bright_offset = 0,      -- manual brightness change, reset at power off (3.3.3)
    baro_t = 0,             -- baro window enlarged / green while > 0
    baro_synced = false,    -- BARO SYNC: in step with the primary's baro setting (arrows by BARO)
    batt_failed = false,    -- BATTERY OVER TEMPERATURE (rev Q figure 5.17)
    pd = nil,               -- power-down box: { t = seconds left, sel = 1 ON / 2 OFF }
    pd_ack = false,         -- "remain on" acknowledged
    storage = false,        -- BATTERY STORAGE MODE: no battery until aircraft power is back
    oat_c = 15,             -- for BATTERY INFO
    -- filtered sensors
    slip = 0,
    vs_fpm = 0,
    last_alt = nil,
    -- the last brightness callback: the dimming curve's level, the lowest
    -- level the pilot may set (the curve's lowest point) and the highest
    bright_base = 1,
    bright_floor = 0,
    bright_top = 1,
    look_k = 1,             -- the LCD look's strength against the brightness (screen_brightness)
}
M.st = st

-- Options Menu (rev Q 4.3.2, figures 4.12-4.23): the settings saved in
-- memory; M.opt holds the current value of each key
M.ITEMS = {
    { key = "alt_units", label = "ALT UNITS", opts = { { "feet", "FEET" }, { "meters", "METERS" } } },
    { key = "baro_units", label = "BARO UNITS", opts = { { "inhg", "IN HG" }, { "hpa", "MBAR" } } },
    { key = "symbol", label = "SYMBOL", opts = { { "delta", "DELTA" }, { "split_delta", "SPLIT DELTA" },
        { "traditional", "TRADITIONAL" } } },
    { key = "att_mask", label = "ATT MASK", opts = { { "off", "OFF" }, { "on", "ON" } } },
    { key = "alt_trend", label = "ALT TREND", opts = { { "off", "OFF" }, { "on", "ON" } } },
    { action = "info", label = "INFO >" },
    { action = "exit", label = "EXIT MENU" },
    { action = "power_off", label = "POWER OFF" },
}
-- INFO > (figure 4.18)
M.INFO_ITEMS = { "REVIEW CONFIG", "SOFTWARE INFO", "BATTERY INFO", "EXIT INFO" }
M.INFO_BATTERY = 3
M.LINES = 8                 -- text lines on a REVIEW CONFIG / INFO page (figures 4.19-4.21)
M.opt = {}

-- hooks set by MD302.lua
M.save_option = function(key, value) end
M.save_state = function() end
M.set_baro = function(inhg) end

local BARO_MIN, BARO_MAX = 28.00, 31.00     -- inHg (rev Q 1.2)
local HPA = 33.8639
local FT_PER_INHG = 925                     -- indicated altitude change per inHg of baro (sea level)

function M.init(util, config, config_mode, fail)
    U, cfg, Cfgm, Fail = util, config, config_mode, fail
end

-- a message box (md302_fail.lua, 5.1.4) is up and takes the knob; in
-- Configuration Mode too (rev Q 5.14 - 5.16 are configuration mode messages)
local function msg_up()
    return Fail ~= nil and Fail.Msg ~= nil and (st.mode == M.FLIGHT or st.mode == M.CONFIG) and st.pd == nil
end

-- the boxes that come up in Configuration Mode (rev Q figures 5.14 - 5.16);
-- the others wait for flight mode (one up as it starts goes back in the queue)
function M.show_config_messages()
    if Fail == nil then return end
    if Fail.Msg and not Fail.CONFIG_MESSAGES[Fail.Msg.n] then Fail.MD302_Msg_Drop() end
    Fail.MD302_Msg_Show_Next(Fail.CONFIG_MESSAGES)
end

function M.opt_label(item, value)
    for _, o in ipairs(item.opts) do
        if o[1] == value then return o[2] end
    end
    return ""
end

-----------------------------------------------------------------------------
-- Power (1.2, 3.2, 3.4)
-----------------------------------------------------------------------------

local function power_off(why)
    if st.mode ~= M.OFF then U.log("power off: " .. why) end
    if Cfgm.active then Cfgm.stop() end     -- 4.1: unsaved configuration changes are lost
    st.mode = M.OFF
    st.menu, st.pd, st.pd_ack = nil, nil, false
    st.bright_t, st.baro_t, st.bright_offset = 0, 0, 0
    st.knob_long, st.cfg_from_start = false, false
    if Fail then Fail.MD302_Msg_Drop() end
    M.save_state()
end
M.power_off = power_off

local function power_on()
    -- rev Q 5.1.3: battery capacity check at every power-up; less than 60
    -- minutes of operation left: the warning (figure 5.5) when flight mode starts
    if Fail and M.has_battery() and st.batt_pct / 100 * cfg.battery_minutes < cfg.battery_check_min then
        Fail.MD302_Msg_Queue(Fail.MSG_BATTERY)
    end
    st.mode = M.PREFLIGHT
    st.preflight_t = cfg.preflight_s
    st.menu, st.pd, st.pd_ack = nil, nil, false
    st.bright_t, st.baro_t, st.bright_offset = 0, 0, 0
    st.cfg_t, st.cfg_from_start = 0, false
    -- 4.1: knob held while power is applied, on the ground: installer mode
    if st.knob_down and st.on_ground then
        st.mode = M.CFG_ENTRY
        U.log("power on with the knob held: installer mode entry")
        return
    end
    -- held through a power-up in the air: that hold is used up (no Options
    -- Menu the moment flight mode starts)
    if st.knob_down then st.knob_long = true end
    U.log("power on: pre-flight")
end

-- laminar/md302/power_down_off (2024): the power-down box answered ON
-- (remain on the battery), or it will not come up for this power loss
function M.remain_on()
    if st.mode == M.OFF or st.ext_power then return false end
    st.pd, st.pd_ack = nil, true
    U.log("power-down: remain on (command)")
    return true
end

-- ACCEPT / CANCEL CHANGES (4.5.3 / 4.5.4): the unit resets to pre-flight
function M.restart(why)
    U.log("restart: " .. why)
    st.knob_long = true                 -- the push that chose it is used up
    power_on()
end

-- laminar/md302/config_mode: the same as holding the knob through a power-up
-- or on the start-up screen, on the ground with aircraft power only (section
-- 4: safeguards keep the configuration mode out of reach in flight)
function M.enter_config()
    if st.mode == M.OFF or st.mode == M.CFG_ENTRY or not st.on_ground or not st.ext_power or Cfgm.active then
        U.log("configuration mode: needs the unit on, on the ground, on aircraft power, not already entering it")
        return false
    end
    -- a push held now does not count as a press in the menu when let go
    if st.knob_down then st.knob_long = true end
    st.menu, st.pd = nil, nil
    st.bright_t, st.baro_t = 0, 0
    st.mode = M.CONFIG
    Cfgm.start(M.bands)
    M.show_config_messages()
    return true
end
M.bands = {}

-- POWER OFF in the Options Menu (rev Q 4.3.2.12, SB MD302-09): whenever the
-- unit runs on its internal battery, in the air too (rev B 3.3.2.7: on the
-- ground only); grey on aircraft power
function M.can_power_off()
    return st.mode ~= M.OFF and not st.ext_power
end

-- the unit versions without a battery (rev Q table 3.2: -2, -3, -5, -6),
-- config.ini battery_type = none
function M.has_battery()
    return cfg.battery_type ~= "none"
end

-- the green battery icon (3.4.1): on the internal battery; low below 20 %
function M.on_battery()
    return st.mode ~= M.OFF and not st.ext_power and M.has_battery()
end

-- BATTERY OVER TEMPERATURE (rev Q figure 5.17, fail_message 12): on the
-- battery the unit shuts off at once; on aircraft power the box, then it runs
-- on with the black battery icon with a red X, and no battery to fall back on.
-- Lasts until the aircraft is reloaded.
function M.battery_failed()
    return st.batt_failed and st.mode ~= M.OFF and M.has_battery()
end

function M.battery_overtemp()
    st.batt_failed = true
    U.log("battery over temperature")
    if st.mode ~= M.OFF and not st.ext_power then power_off("battery over temperature") end
end

function M.battery_low()
    return st.batt_pct < cfg.battery_low_pct
end

local function update_power(dt, real_dt, D)
    st.ext_power = D.bus_volts >= cfg.power_min_volts
    st.on_ground = D.groundspeed_kt < cfg.ground_speed_kt and D.ias_kt < cfg.ground_ias_kt
    -- AUTO-OFF (rev Q 4.4.2) "will recognize a lack of airspeed and determine
    -- that the aircraft is on the ground" (a hovering rotorcraft too); taxiing
    -- does not stop it. on_ground (no motion either) guards Configuration Mode
    st.no_airspeed = D.ias_kt < cfg.ground_ias_kt

    if st.mode == M.OFF then
        -- applying aircraft power turns the unit on; it also ends BATTERY
        -- STORAGE MODE (SB MD302-05: "until the unit is restarted by external
        -- power"; the restart after ACCEPT / CANCEL CHANGES does not)
        if st.ext_power then
            if st.storage then
                st.storage = false
                U.log("battery storage mode ended: aircraft power applied")
            end
            power_on()
        end
    else
        st.run_time_s = st.run_time_s + dt
        if st.ext_power then
            -- recharge, and any power-down dialog / acknowledgement ends
            st.batt_pct = math.min(100, st.batt_pct + 100 * dt / (cfg.battery_charge_minutes * 60))
            st.pd, st.pd_ack = nil, false
        else
            if not M.has_battery() then
                power_off("aircraft power lost (battery_type = none: no battery)")
                return
            end
            if st.storage then
                power_off("battery storage mode: no battery")
                return
            end
            if st.batt_failed then
                power_off("aircraft power lost, the battery failed (over temperature)")
                return
            end
            st.batt_pct = math.max(0, st.batt_pct - 100 * dt / (cfg.battery_minutes * 60))
            if st.batt_pct <= 0 then
                power_off("battery empty")
                return
            end
            -- on the ground with AUTO-OFF on (rev Q 4.4.2): POWER DOWN IN .. SEC
            -- over the attitude, ON / OFF, then off; AUTO-OFF off: it stays on
            -- the battery until POWER OFF
            if cfg.auto_off == "on" and st.mode == M.FLIGHT and st.no_airspeed and not st.pd_ack and st.pd == nil then
                st.pd = { t = cfg.power_down_countdown_s, sel = 2 }
                st.menu = nil
                U.log("aircraft power lost on the ground: powering down in " .. cfg.power_down_countdown_s .. " s")
            end
            -- airspeed again (a take-off roll): no longer on the ground
            if st.pd and not st.no_airspeed then
                st.pd = nil
                U.log("power-down cancelled: airspeed")
            end
            if st.pd then
                st.pd.t = st.pd.t - dt
                if st.pd.t <= 0 then
                    power_off("power-down countdown")
                    return
                end
            end
        end
    end

    if st.mode == M.PREFLIGHT then
        st.preflight_t = st.preflight_t - real_dt
        if st.preflight_t <= 0 then
            st.mode = M.FLIGHT
            -- a push held through the start-up screen (one that did not
            -- start the installer mode: on the battery, in motion) is used
            -- up: no Options Menu the moment flight mode starts
            if st.knob_down then st.knob_long = true end
            U.log("flight mode")
            if Fail then Fail.MD302_Msg_Show_Next() end
        end
    elseif st.mode == M.CFG_ENTRY then
        -- aircraft power gone or moving while held: no installer mode (section
        -- 4 safeguards, as the config_mode command); the hold is used up and
        -- the start-up screen goes on
        if not st.ext_power or not st.on_ground then
            st.mode = M.PREFLIGHT
            st.preflight_t = st.cfg_from_start and math.max(0, st.preflight_t - st.cfg_t) or cfg.preflight_s
            st.cfg_from_start, st.knob_long = false, true
            U.log("installer mode entry given up: " .. (st.ext_power and "moving" or "aircraft power lost"))
            return
        end
        st.cfg_t = st.cfg_t + real_dt
        -- begun on the start-up screen: the menu comes by itself once held
        -- long enough; the release is used up (no menu press)
        if st.cfg_from_start and st.cfg_t >= cfg.cfg_start_enter_s then
            st.knob_long = true
            st.mode = M.CONFIG
            st.cfg_from_start = false
            Cfgm.start(M.bands)
            M.show_config_messages()
            U.log("held on the start-up screen: configuration mode")
        end
    end
end

-----------------------------------------------------------------------------
-- Knob (3.1): 16 detents per turn, push, push and hold
-----------------------------------------------------------------------------

local function menu_close()
    st.menu = nil
end

local function selectable(i)
    local it = M.ITEMS[i]
    if it.action == "power_off" then return M.can_power_off() end
    return true
end
M.selectable = selectable

local function menu_open()
    st.menu = { page = "root", sel = 1, entered = nil, opt = 1, idle = 0, top = 1, isel = 1 }
    st.bright_t = 0
    U.log("options menu")
end

-- laminar/md302/goes_into_setting (the 2024 command): the Options Menu, as
-- holding the knob, in flight mode with nothing else up
function M.open_menu()
    if st.mode ~= M.FLIGHT or st.menu or st.pd or msg_up() then return false end
    menu_open()
    return true
end

-- REVIEW CONFIG / SOFTWARE INFO / BATTERY INFO pages (rev Q figures
-- 4.19-4.21): lines { text, grey, cols }; a white heading, its value grey
-- below it; cols = { {text, x, just}, ... } for the table rows, in the
-- columns of the rev Q dumps (p35: x 19, 75, 135, 191 LCD px, left aligned)
local function head(t) return { t, false } end
local function val(t) return { t, true } end
local function cols(c) return { "", true, c } end
local COL = { 19 * 1.5625, 75 * 1.5625, 135 * 1.5625, 191 * 1.5625 }

M.BAND_WIDTH_NAME = { F = "FULL", H = "HALF", R = "RAD" }
M.BAND_COLOUR_NAME = { white = "WHT", green = "GRN", yellow = "YEL", red = "RED", blue = "BLU", bar = "BAR",
    magenta = "MAG", amber = "AMB" }
local onoff = function(v) return (v == "on") and "ON" or "OFF" end

function M.review_lines()
    local out = {}
    local function add(t, v)
        out[#out + 1] = head(t)
        out[#out + 1] = val(v)
    end
    local ias = ({ knots = "KNOTS", mph = "MPH", kph = "KPH" })[cfg.airspeed_units] or "KNOTS"
    local dim = ({ internal = "INTERNAL", ext_5v = "EXT 5V", ext_14v = "EXT 14V", ext_28v = "EXT 28V" })[cfg.dimming_control]
        or "INTERNAL"
    add("AIRSPEED MINIMUM", string.format("%d KNOTS", cfg.airspeed_minimum))
    add("AIRSPEED UNITS", ias)
    add("PASS-THROUGH", onoff(cfg.arinc_pass_through))
    add("TRANSMIT SPEED", (cfg.arinc_speed == "low") and "LOW SPEED" or "HIGH SPEED")
    add("CONFIGURE BARO SYNC", onoff(cfg.baro_sync))
    add("DIMMING CONTROL", dim)
    add("DISPLAY ORIENTATION", M.orientation_name and M.orientation_name() or "HORIZONTAL")
    add("CONFIGURE HEADING", (cfg.heading_display == "on") and "DISPLAY ON" or "DISPLAY OFF")
    add("ROLL DISPLAY", (cfg.roll_display == "fixed_pointer") and "FIXED POINTER" or "FIXED SCALE")
    add("CONFIGURE AUTO-OFF", onoff(cfg.auto_off))
    -- the curve in use, then PT 7: the low-input threshold (listed with the
    -- photocell too, figure 4.19)
    out[#out + 1] = head("DIMMING CURVE")
    local ext = cfg.dimming_control ~= "internal"
    local c = ext and cfg.curve_external or cfg.curve_internal
    for i = 1, 6 do
        out[#out + 1] = cols({ { "PT " .. i .. ":", COL[1], 0 }, { tostring(math.floor(c[i] * 100 + 0.5)), COL[3], 0 } })
    end
    out[#out + 1] = cols({ { "PT 7:", COL[1], 0 }, { tostring(math.floor(cfg.dimming_low_input + 0.5)), COL[3], 0 } })
    add("HORIZON DISPLAY", string.upper(cfg.horizon_display))
    local tilt, roll = 0, 0
    if M.panel_angles then tilt, roll = M.panel_angles() end
    add("PANEL ROLL", string.format("%.1f", roll))
    add("PANEL TILT", string.format("%.1f", tilt))
    add("RANGE MMO", string.format("%.3f", cfg.range_mmo))
    out[#out + 1] = head("RANGE MARKINGS")
    local by_row = {}                           -- config.ini bands keep their table row (range3 = row 3)
    for k, b in ipairs(M.bands or {}) do by_row[b.row or k] = b end
    for i = 1, 8 do
        local b = by_row[i]
        local w, col, lo, hi = "OFF", "OFF", "0", "0"
        if b then
            w, col = M.BAND_WIDTH_NAME[b.width] or "FULL", M.BAND_COLOUR_NAME[b.color] or "WHT"
            lo = tostring(math.floor(b.lo + 0.5))
            hi = (b.hi >= 999) and "MAX" or tostring(math.floor(b.hi + 0.5))
        end
        out[#out + 1] = cols({ { w, COL[1], 0 }, { col, COL[2], 0 }, { lo, COL[3], 0 }, { hi, COL[4], 0 } })
    end
    out[#out + 1] = head("VNE TABLE")
    local pts = cfg.vne_points or {}
    for i = 1, 7 do
        local p = pts[i]
        if p then
            out[#out + 1] = cols({ { "PT " .. i .. ":", COL[1], 0 }, { tostring(p[1]), COL[2], 0 },
                { tostring(p[2]), COL[4], 0 } })
        elseif i == 1 then
            out[#out + 1] = cols({ { "PT 1:", COL[1], 0 }, { "0", COL[2], 0 }, { "0", COL[4], 0 } })
        else
            out[#out + 1] = cols({ { "PT " .. i .. ":", COL[1], 0 }, { "UNUSED", COL[2], 0 } })
        end
    end
    -- rev Q 4.5.11: a loaded SSEC table is named on REVIEW CFG as on the
    -- start-up screen (only then: the figures, from units without one, have
    -- no such line; its place on the page is ours)
    if cfg.ssec_file ~= "" then add("SSEC", "FILE " .. string.upper(cfg.ssec_file)) end
    return out
end

function M.software_lines()
    local v = M.SW_VERSION or ""
    local out = { head("MD302 SW VERSION"), val(v) }
    -- an MD32 magnetometer reports its own version (figure 4.20)
    if cfg.heading == "md32" then
        out[#out + 1] = head("MD32 SW VERSION")
        out[#out + 1] = val(v)
    end
    return out
end

-- figure 4.21: run time left, temperature, charge, capacity, type. The battery
-- sits in the panel with a heater (4.4.1): X-Plane's outside air, kept 5..40 C.
-- Capacity: 966 mAh for 120 minutes (Type 1, lithium-ion 1.0 Ah), twice that
-- per minute of the default for Type 2 (nickel metal hydride 2.0 Ah, 12 Wh
-- against 9.9 Wh: 145 minutes when new; rev Q 1.2)
function M.battery_lines()
    local mins = math.floor(st.batt_pct / 100 * cfg.battery_minutes)
    local t2 = cfg.battery_type == "2"
    local mah = t2 and 1932 * cfg.battery_minutes / 145 or 966 * cfg.battery_minutes / 120
    return {
        head("EST RUN TIME (MINS)"), val(tostring(mins)),
        head("TEMPERATURE (C)"), val(tostring(math.floor(U.clamp(st.oat_c, 5, 40) + 0.5))),
        head("CHARGE (%)"), val(tostring(math.floor(st.batt_pct + 0.5))),
        head("CAPACITY (MAH)"), val(tostring(math.floor(mah + 0.5))),
        head("TYPE"), val(t2 and "TYPE 2" or "TYPE 1"),
    }
end

function M.page_lines(page)
    if page == "review" then return M.review_lines() end
    if page == "software" then return M.software_lines() end
    return M.battery_lines()
end
M.bands = M.bands or {}
M.n_bands = 0

local function menu_turn(dir)
    local m = st.menu
    m.idle = 0
    if m.page == "review" or m.page == "software" or m.page == "battery" then
        local n = #M.page_lines(m.page)
        m.top = U.clamp(m.top + dir, 1, math.max(1, n - M.LINES + 1))
    elseif m.page == "info" then
        local i = U.clamp(m.isel + dir, 1, #M.INFO_ITEMS)
        if not M.info_ok(i) then i = U.clamp(i + dir, 1, #M.INFO_ITEMS) end
        if M.info_ok(i) then m.isel = i end
    elseif m.entered then
        local n = #M.ITEMS[m.entered].opts
        m.opt = (m.opt - 1 + dir) % n + 1
    else
        -- the cursor skips unavailable (grey) items and stops at the ends (rev Q
        -- lists do not wrap; it also keeps POWER OFF, the last item, a full
        -- turn of the list away from ALT UNITS)
        local i = m.sel + dir
        while i >= 1 and i <= #M.ITEMS do
            if selectable(i) then
                m.sel = i
                break
            end
            i = i + dir
        end
    end
end

-- INFO > items: BATTERY INFO is grey on a unit without a battery
function M.info_ok(i)
    return i ~= M.INFO_BATTERY or M.has_battery()
end

local function menu_press()
    local m = st.menu
    m.idle = 0
    if m.page == "review" or m.page == "software" or m.page == "battery" then
        m.page = "info"                 -- push: back to the INFO sub-menu
        return
    end
    if m.page == "info" then
        if m.isel == 4 then
            m.page = "root"             -- EXIT INFO
        else
            m.page = ({ "review", "software", "battery" })[m.isel]
            m.top = 1
        end
        return
    end
    if m.entered then
        -- 3.3.2.1: the selected option becomes active and is saved in memory
        local it = M.ITEMS[m.entered]
        local v = it.opts[m.opt][1]
        if M.opt[it.key] ~= v then
            M.opt[it.key] = v
            M.save_option(it.key, v)
            U.log(string.format("option %s = %s", it.key, v))
        end
        m.entered = nil
        return
    end
    local it = M.ITEMS[m.sel]
    if it.opts then
        m.entered = m.sel
        m.opt = 1
        for k, o in ipairs(it.opts) do
            if o[1] == M.opt[it.key] then m.opt = k end
        end
    elseif it.action == "power_off" then
        if M.can_power_off() then power_off("POWER OFF (options menu)") end
    elseif it.action == "info" then
        m.page = "info"
        m.isel = 1
    elseif it.action == "exit" then
        menu_close()
    end
end

local function baro_step(dir, D)
    local inhg = D.baro_inhg
    if M.opt.baro_units == "hpa" then
        local hpa = math.floor(inhg * HPA + 0.5) + dir
        inhg = hpa / HPA
    else
        inhg = (math.floor(inhg * 100 + 0.5) + dir) / 100
    end
    inhg = U.clamp(inhg, BARO_MIN, BARO_MAX)
    M.set_baro(inhg)
    D.baro_inhg = inhg
    st.baro_t = cfg.baro_highlight_s
    st.baro_synced = false              -- set here now: out of step with the primary (rev Q figure 4.9)
end

function M.knob_turn(dir, D)
    st.knob_val = (st.knob_val + dir / 16) % 1
    if st.mode == M.CONFIG then
        if msg_up() then Fail.MD302_Msg_Turn(dir) else Cfgm.turn(dir) end
        return
    end
    if st.mode ~= M.FLIGHT then return end
    if st.pd then
        st.pd.sel = (dir < 0) and 1 or 2       -- ON (left) / OFF (right), figure 4.26
        return
    end
    if msg_up() then
        Fail.MD302_Msg_Turn(dir)
    elseif st.menu then
        menu_turn(dir)
    elseif st.bright_t > 0 then
        -- 4.3.3: turning while the brightness bar is up changes the level,
        -- never below the dimming curve's lowest point (rev Q: "cannot be
        -- reduced below minimum level set in Configuration Mode") nor past
        -- full; the change stops at either end, so turning back acts at once
        st.bright_offset = U.clamp(st.bright_offset + dir * cfg.bright_step,
            st.bright_floor - st.bright_base, st.bright_top - st.bright_base)
        st.bright_t = cfg.bright_bar_s
    else
        -- 3.3.1.2: turning the knob in Flight Mode sets the barometric pressure
        baro_step(dir, D)
    end
end

-- phase: 0 begin, 1 continue, 2 end (XPLMCommandPhase)
function M.knob_press(phase, D)
    if phase == 0 then
        st.knob_down = true
        st.knob_t = 0
        st.knob_long = false
        st.bar_before = st.bright_t > 0
        -- the knob pushed on the start-up screen, on the ground on aircraft
        -- power: the installer mode entry too, with "CONTINUE HOLDING" after
        -- half a second and the CONFIGURE MENU by itself once held
        -- cfg_start_enter_s. 4.1 wants the knob held before power is applied,
        -- which takes two hands; in the simulator one mouse flips the master
        -- switch and then has to reach the knob
        if st.mode == M.PREFLIGHT and st.on_ground and st.ext_power then
            st.mode = M.CFG_ENTRY
            st.cfg_t, st.cfg_from_start = 0, true
            U.log("knob pushed on the start-up screen: installer mode entry")
            return
        end
        if st.mode == M.CONFIG and msg_up() then
            -- a configuration mode box: answered on the push, the release is used up
            Fail.MD302_Msg_Press(Fail.CONFIG_MESSAGES)
            st.knob_long = true
            return
        end
        if st.mode ~= M.FLIGHT then return end
        if st.pd then
            -- rev Q 4.4.2: ON = remain on (on the battery), OFF = off now
            st.knob_long = true         -- this push is used up
            if st.pd.sel == 1 then
                st.pd, st.pd_ack = nil, true
                U.log("power-down: ON (remain on)")
            else
                power_off("power-down: OFF")
            end
            return
        end
        if msg_up() then
            -- the box's OK / YES / NO, on the push like the power-down OK
            Fail.MD302_Msg_Press()
            st.knob_long = true
            return
        end
        if st.menu == nil then
            -- the brightness bar shows at once; held for 2 s the menu follows (3.3.2)
            st.bright_t = cfg.bright_bar_s
        end
    elseif phase == 2 then
        st.knob_down = false
        if st.mode == M.CFG_ENTRY then
            -- 4.1: let go once the introduction screen shows: CONFIGURE MENU;
            -- earlier: an ordinary start. (Begun on the start-up screen there
            -- is no race with the 3.5 s: cfg_t only grows in update_power,
            -- which enters the menu in that same step, so a let-go sees
            -- either CFG_ENTRY under 3.5 s or CONFIG)
            if st.cfg_t >= cfg.cfg_intro_s then
                st.mode = M.CONFIG
                st.cfg_from_start = false
                Cfgm.start(M.bands)
                M.show_config_messages()
            else
                -- begun on the start-up screen: its countdown goes on as if
                -- not pushed (it stood while held); after a power-up held: in full
                st.mode = M.PREFLIGHT
                st.preflight_t = st.cfg_from_start and math.max(0, st.preflight_t - st.cfg_t) or cfg.preflight_s
                st.cfg_from_start = false
                U.log("knob let go early: pre-flight")
            end
            return
        end
        if st.mode == M.CONFIG then
            if not st.knob_long then Cfgm.press() end
            st.knob_long = false
            return
        end
        if st.mode ~= M.FLIGHT or st.knob_long then return end
        if st.menu then
            menu_press()
        elseif st.bar_before then
            st.bright_t = 0             -- a second short push puts the bar away
        end
    end
end

-- seconds the knob takes to go in or come back out in the model
local KNOB_PUSH_S = 0.08

local function update_knob(real_dt)
    local step = real_dt / KNOB_PUSH_S
    if st.knob_down then
        st.knob_push = math.min(1, st.knob_push + step)
    else
        st.knob_push = math.max(0, st.knob_push - step)
    end
    if not st.knob_down then return end
    st.knob_t = st.knob_t + real_dt
    if st.mode == M.FLIGHT and not st.knob_long and st.menu == nil and st.pd == nil and not msg_up()
        and st.knob_t >= cfg.menu_hold_s then
        st.knob_long = true
        menu_open()
    end
end

-----------------------------------------------------------------------------
-- Sensors
-----------------------------------------------------------------------------

local function update_sensors(dt, D)
    -- slip ball: electronic damping (3.3.1.4)
    if dt > 0 then
        local k = 1 - math.exp(-dt / cfg.slip_tau_s)
        st.slip = st.slip + (D.slip_deg - st.slip) * k
        -- altitude trend (3.3.1.2): vertical speed from the indicated altitude,
        -- less what a baro change adds to it (a 0.01 inHg detent is ~9 ft)
        local alt = D.alt_ft - (D.baro_inhg - 29.92) * FT_PER_INHG
        if st.last_alt then
            local raw = (alt - st.last_alt) / dt * 60
            if math.abs(raw) < 30000 then
                local kv = 1 - math.exp(-dt / cfg.trend_tau_s)
                st.vs_fpm = st.vs_fpm + (raw - st.vs_fpm) * kv
            end
        end
        st.last_alt = alt
    end
    -- a NaN once in (an instructor writing one) would stay in the filters for good
    if st.slip ~= st.slip then st.slip = 0 end
    if st.vs_fpm ~= st.vs_fpm then st.vs_fpm, st.last_alt = 0, nil end
end

-----------------------------------------------------------------------------
-- Frame
-----------------------------------------------------------------------------

-- dt: simulator time (0 while paused); real_dt: wall-clock time
function M.update(dt, real_dt, D)
    update_power(dt, real_dt, D)
    update_knob(real_dt)
    update_sensors(dt, D)
    st.oat_c = D.oat_c or st.oat_c
    if st.menu then
        st.menu.idle = st.menu.idle + real_dt
        -- 3.3.2: back to the attitude display after 10 s without activity
        if st.menu.idle >= cfg.menu_timeout_s and not st.knob_down then
            menu_close()
        elseif st.menu.page == "root" and not st.menu.entered and not selectable(st.menu.sel) then
            st.menu.sel = 1
        end
    end
    if st.bright_t > 0 and not st.knob_down then st.bright_t = math.max(0, st.bright_t - real_dt) end
    if st.baro_t > 0 then st.baro_t = math.max(0, st.baro_t - real_dt) end
end

-- new flight / aircraft reload
function M.reset()
    if Cfgm.active then Cfgm.stop() end
    st.mode = M.OFF
    st.menu, st.pd, st.pd_ack = nil, nil, false
    st.bright_t, st.baro_t, st.bright_offset = 0, 0, 0
    st.knob_down, st.knob_long = false, false
    st.cfg_t, st.cfg_from_start = 0, false
    st.slip, st.vs_fpm, st.last_alt = 0, 0, nil
    st.baro_synced = false
    -- the battery is back to new: its over-temperature box goes too
    st.batt_failed = false
    if Fail then Fail.MD302_Msg_Remove(Fail.MSG_BATTERY_TEMP) end
end

-- 0..1 screen level for the device brightness callback, and the brightness
-- bar's fill (0 = the lowest level allowed, 1 = the highest).
-- The dimming curve (rev Q 4.5.5.2) gives the backlight level for the dimming
-- input: the photocell (X-Plane's ambient on a log scale, ambient_min .. 1 =
-- MIN .. MAX) or the lighting bus; at or below the bus's low-input threshold
-- (PT 7; 0 = the bus off) the photocell and its curve take over (step 6).
-- X-Plane's ambient is the base (the Garmin G5 plugin's model): a level l shows
-- amb x 2^((l - neutral) / doubling). The photocell's own work is already in
-- X-Plane's ambient, so on the photocell a level counts from the manual's
-- default curve (10 .. 100 %) at that input, which looks as LOOK does (a
-- curve tuned in X-Plane); a point set higher or lower is
-- that much brighter or darker. The pilot's change from the brightness bar
-- (4.3.3) moves the level on top, between the curve's lowest point and full.
local LOOK = { 0.83, 0.84, 0.87, 0.90, 0.94, 1.00 }
local DEFAULT_CURVE = { 0.10, 0.28, 0.46, 0.64, 0.82, 1.00 }

local function curve_at(c, x)
    x = U.clamp(x, 0, 1) * 5
    local i = math.min(4, math.floor(x))
    return c[i + 1] + (c[i + 2] - c[i + 1]) * (x - i)
end
M.curve_at = curve_at

local function lowest(c)
    local m = c[1]
    for i = 2, #c do m = math.min(m, c[i]) end
    return m
end

function M.screen_brightness(ambient, D)
    if st.mode == M.OFF then return 0, 0 end
    local amb = math.max(U.clamp(ambient or 1, 0, 1), cfg.ambient_min)
    -- the pending curves while they are set up in Configuration Mode
    local control, ci, ce, low_in = Cfgm.dim_params()
    if control == nil then
        control, ci, ce = cfg.dimming_control, cfg.curve_internal, cfg.curve_external
        low_in = cfg.dimming_low_input / 100
    end
    local photo = math.log(amb / cfg.ambient_min) / math.log(1 / cfg.ambient_min)
    local c, x, shift = ci, photo, 0
    if control ~= "internal" then
        x = U.clamp(D.dim_input, 0, 1)
        if x > low_in then c = ce end
    end
    local level
    if c == ci then
        level = curve_at(ci, photo)
        shift = curve_at(LOOK, photo) - curve_at(DEFAULT_CURVE, photo)
    else
        level = curve_at(ce, x)
    end
    st.dim_x, st.dim_level = x, level
    local dbl, neutral = cfg.backlight_doubling, cfg.backlight_neutral
    local floor = math.max(lowest(c), cfg.backlight_min)
    -- the level that fills the screen at this ambient; the pilot's top
    local full = neutral - shift + dbl * math.log(1 / amb) / math.log(2)
    local top = math.max(floor, math.min(1, full))
    -- a level above top shows as top: the pilot's change counts from there,
    -- so the first detent down already dims
    local base = math.min(level, top)
    st.bright_base, st.bright_floor, st.bright_top = base, floor, top
    local lv = U.clamp(base + st.bright_offset, floor, top)
    local s = U.clamp(amb * 2 ^ ((lv + shift - neutral) / dbl), 0, 1)
    -- the LCD look (md302_lcd.lua) no brighter than at the default brightness:
    -- X-Plane scales the whole picture by s, so above the default the look is
    -- drawn s_default / s as strong (the stains would brighten with the
    -- brightness bar); below it, it dims with the picture
    local s_def = U.clamp(amb * 2 ^ ((curve_at(LOOK, photo) - neutral) / dbl), 0, 1)
    st.look_k = math.min(1, s_def / math.max(s, 1e-6))
    local bar = (top > floor) and (lv - floor) / (top - floor) or 0
    return s, U.clamp(bar, 0, 1)
end

return M

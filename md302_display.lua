-- Copyright (c) 2026 Tiezheng Eric Xu, erix@x-plane.com, Laminar Research - MIT License, see LICENSE
--
-- md302_display.lua: the two MD302 LCDs, 500 x 374 each (display units =
-- the 2024 Plane Maker art, 1:1; origin bottom-left, y up).
--   left  = attitude (3.3.1.1), or the Options Menu / power-down dialog
--   right = airspeed (left half, 3.3.1.3) and altitude (right half, 3.3.1.2)
-- Positions are the 2024 panel's (its Plane Maker panel),
-- converted to each LCD: x - 1 / x - 525, y - 393.

local Dsp = {}

local U, G, M, cfg, C, Fail

function Dsp.init(util, gfx, unit, config, fail)
    U, G, M, cfg, Fail = util, gfx, unit, config, fail
    C = G.C
end

local W, H = 500, 374
local font = function(face, px) return G.font(face, px) end

-- Layouts. "h": the LCD as in the 2024 art (500 x 374). "v": a vertical
-- installation (4.2.3), the LCD turned upright (374 x 500), laid out like
-- rev Q figure 2.1 and five photos of vertical units: the airspeed and the
-- altitude windows side by side at mid height, 3/4 of their horizontal size
-- (win_s, scaled about their pointers), BARO 3/4 at the top between the
-- tapes, the airspeed tape about 77 kt high (spd_ppu; the altitude tape
-- already shows the photos' 610 ft).
-- x_*: the failure X boxes (5.1.4 screen dumps x 1.5625). slip_q / slip_x:
-- the LCD row and column the slip box starts on with the heading displayed
-- (rev Q figure 4.7; upright: centred above the heading window, as photos).
Dsp.LAY = {
    h = { W = 500, H = 374, piv_x = 250, piv_y = 186, lad_bottom = 62.3,
        batt = { 483, 349 }, bar = { 110, 390, 70, 104 }, mask_turn = false, slip_q = 22, slip_x = 11,
        spd_cy = 187, alt_cy = 187, alt_dx = 0, baro_dx = 0, baro_dy = 0, win_s = 1, baro_s = 1, spd_ppu = 7,
        x_att = { 103, 37, 400, 334 }, x_ias = { 56, 45, 166, 326 }, x_alt = { 353, 45, 463, 326 } },
    v = { W = 374, H = 500, piv_x = 187, piv_y = 250, lad_bottom = 85,
        batt = { 357, 475 }, bar = { 47, 327, 70, 104 }, mask_turn = true, slip_q = 29, slip_x = 71,
        spd_cy = 250, alt_cy = 250, alt_dx = -126, baro_dx = -113, baro_dy = 134, win_s = 0.75, baro_s = 0.75,
        spd_ppu = 6.5,
        x_att = { 38, 101, 336, 399 }, x_ias = { 30, 120, 160, 380 }, x_alt = { 190, 120, 330, 380 } },
}
local X_ATT_W, X_SIDE_W = 23, 17        -- stroke widths of the failure X

-----------------------------------------------------------------------------
-- Attitude (left LCD)
-----------------------------------------------------------------------------

-- horizon pivot (Tones / Grids POS) and the ladder window (Grids.png CLIP
-- size, 230 x 260) are per layout (Dsp.LAY)
local PPD = 485 / 90                   -- px per degree of pitch (DEFLECT_PIX 485)
-- sky / ground: flat beyond 130 px, lighter toward the horizon (Tones art)
-- the black-bezel unit draws both flat (photos of the real unit, calibrated
-- on its own white): an azure sky, a crimson ground.
-- The 2024 art had gradients 516BDF..3251D9 / 8F463A..7B2618 (the grey-bezel
-- unit's look); the manual's dumps are 5C5CF8 / 6C1400. The ground is drawn
-- with its blue taken out (photo 832C2D -> 7C1606): in the 3D cockpit the
-- navy black level and X-Plane's tone mapping add blue, and 7C1606 lands on
-- the photo's crimson there (measured); the 2D popup shows it a little orange.
local SKY = { { 0, "027CE9" }, { 65, "027CE9" }, { 130, "027CE9" } }
local GND = { { 0, "7C1606" }, { 65, "7C1606" }, { 130, "7C1606" } }
-- HORIZON DISPLAY SHADED (rev Q 4.5.6.4, figure 4.46): lighter at the horizon,
-- darker toward the edges, over 100 LCD px (156 here). Measured on the rev Q
-- dumps (flat 5C5CF8 / 6C1400; shaded sky 8888F6 at the horizon .. 4040FA,
-- ground AE3E3F .. 641C1F) and carried over to this palette: sky mixed 27 %
-- toward white at the horizon, red / green x0.7 at the edges; ground x1.6 at
-- the horizon, x0.9 at the edges, its blue still kept out (see above).
local SKY_SHADED = { { 0, "46A0EF" }, { 78, "247CEC" }, { 156, "0157E9" } }
local GND_SHADED = { { 0, "C62E10" }, { 78, "9B210A" }, { 156, "701405" } }
local tones = {}

local function tone_bands(shaded)
    local key = shaded and "shaded" or "flat"
    if tones[key] then return tones[key] end
    local t = { sky = {}, gnd = {} }
    for i, s in ipairs(shaded and SKY_SHADED or SKY) do t.sky[i] = { s[1], G.hex(s[2]) } end
    for i, s in ipairs(shaded and GND_SHADED or GND) do t.gnd[i] = { s[1], G.hex(s[2]) } end
    tones[key] = t
    return t
end

-- sky above y = 0, ground below, in the rotated horizon frame (the horizon
-- line over their edge: aa_horizon)
local function sky_ground()
    local t = tone_bands(cfg.horizon_display == "shaded")
    local sky_c, gnd_c = t.sky, t.gnd
    local X = 700
    local far = 2000
    for i = 1, #sky_c - 1 do
        local a, b = sky_c[i], sky_c[i + 1]
        G.polyc({ -X, a[1], a[2], -X, b[1], b[2], X, b[1], b[2], X, a[1], a[2] })
        a, b = gnd_c[i], gnd_c[i + 1]
        G.polyc({ -X, -a[1], a[2], X, -a[1], a[2], X, -b[1], b[2], -X, -b[1], b[2] })
    end
    G.rect(-X, sky_c[#sky_c][1], X, far, sky_c[#sky_c][2])
    G.rect(-X, -far, X, -gnd_c[#gnd_c][1], gnd_c[#gnd_c][2])
end

-- The horizon line and the ladder lines are anti-aliased white bars
-- (Textures/aa_*.png) drawn turned: X-Plane samples
-- them bilinearly, so a slight bank gives a smooth edge, as the rev Q dumps
-- show (p53: the horizon blends into the sky and the ground). Panel Graphics
-- polygons are not anti-aliased, and lines rasterized on the 320 x 240 grid
-- step by whole pixels, away from the sky / ground edge at small banks.
-- The ladder (lines, numbers, chevrons) is masked to an arch round the pivot,
-- measured on the rev Q dumps (p24 / p39 / p53) and a photo: toward the
-- roll scale a circle of 85 LCD px, pixel by pixel (level, the 20 deg numbers
-- are cut through: "_0", "2("); away from it straight down at the same width
-- (a 30 is whole 83 px left of centre, p24); nothing below LCD row 200 (p24,
-- with and without the heading). The circle's side turns with the scale in
-- FIXED POINTER; the bottom stays.
-- mask: page px; centre, radius, the scale's "up", bottom, set in Dsp.attitude
local mask = { cx = 0, cy = 0, r = 133, ux = 0, uy = 1, bottom = 0, x1 = 0, top = 0 }
local INF = math.huge

-- the turned frame of Dsp.attitude: page = pivot + rot(roll) (x, y + dy)
local tf = { co = 1, si = 0, x0 = 0, y0 = 0, dy = 0, roll = 0 }
local function to_page(x, y)
    local yy = y + tf.dy
    return tf.x0 + tf.co * x - tf.si * yy, tf.y0 + tf.si * x + tf.co * yy
end

-- lo .. hi narrowed to where k * x + m <= h
local function half(k, m, h, lo, hi)
    if math.abs(k) < 1e-9 then
        if m <= h then return lo, hi end
        return INF, -INF
    end
    local b = (h - m) / k
    if k > 0 then return lo, math.min(hi, b) end
    return math.max(lo, b), hi
end

-- the mask on the row y = yc: lo, hi, or nil. The arch is convex, so the
-- circle's chord and the straight part's span join into one span.
local function mask_span(yc)
    if yc < mask.bottom or yc > mask.top then return nil end
    local dy = yc - mask.cy
    local ux, uy, r = mask.ux, mask.uy, mask.r
    local c0, c1 = INF, -INF
    local d = r * r - dy * dy
    if d >= 0 then
        d = math.sqrt(d)
        c0, c1 = mask.cx - d, mask.cx + d
    end
    -- away from the scale (along the "up" <= 0), within r across it
    local s0, s1 = half(ux, dy * uy - mask.cx * ux, 0, -INF, INF)
    s0, s1 = half(uy, -mask.cx * uy - dy * ux, r, s0, s1)
    s0, s1 = half(-uy, mask.cx * uy + dy * ux, r, s0, s1)
    local lo, hi = c0, c1
    if s0 <= s1 then lo, hi = math.min(s0, c0), math.max(s1, c1) end
    lo, hi = math.max(lo, 0), math.min(hi, mask.x1)
    if lo > hi then return nil end
    return lo, hi
end

local function in_mask(x, y)
    local lo, hi = mask_span(y)
    return lo ~= nil and x >= lo and x <= hi
end

-- the LCD grid of a layout: pixel size in display units, columns, rows
local function grid(L)
    local nx = (L.W > L.H) and 320 or 240
    local ny = (L.W > L.H) and 240 or 320
    return L.W / nx, L.H / ny, nx, ny
end

-- an atlas cell w x h turned with the horizon (and deg_cw more), its point
-- (px, py) on the turned-frame point (x, y): whole when it is inside the
-- mask, else LCD row by row, each row clipped to the mask's whole pixels
local cx_, cy_ = {}, {}
local function masked_cell(idx, x, y, px, py, w, h, deg_cw, col, L)
    local X, Y = to_page(x, y)
    local a = math.rad(tf.roll - deg_cw)
    local co, si = math.cos(a), math.sin(a)
    local inside = true
    for k, c in ipairs({ { -px, -py }, { w - px, -py }, { w - px, h - py }, { -px, h - py } }) do
        cx_[k], cy_[k] = X + co * c[1] - si * c[2], Y + si * c[1] + co * c[2]
        if inside and not in_mask(cx_[k], cy_[k]) then inside = false end
    end
    if inside then
        G.atlas_turned(idx, X, Y, px, py, deg_cw - tf.roll, col)
        return
    end
    local sx, sy, _, ny = grid(L)
    local bx0, bx1 = math.min(cx_[1], cx_[2], cx_[3], cx_[4]), math.max(cx_[1], cx_[2], cx_[3], cx_[4])
    local by0, by1 = math.min(cy_[1], cy_[2], cy_[3], cy_[4]), math.max(cy_[1], cy_[2], cy_[3], cy_[4])
    for j = math.max(math.floor(by0 / sy), 0), math.min(math.floor(by1 / sy), ny - 1) do
        local m0, m1 = mask_span((j + 0.5) * sy)
        if m0 then
            local i0 = math.ceil(math.max(m0, bx0 - sx) / sx - 0.5)
            local i1 = math.floor(math.min(m1, bx1 + sx) / sx - 0.5)
            if i1 >= i0 then
                G.clip(i0 * sx, j * sy, (i1 + 1) * sx, (j + 1) * sy)
                G.atlas_turned(idx, X, Y, px, py, deg_cw - tf.roll, col)
                G.unclip()
            end
        end
    end
end

-- a ladder number centred on the turned-frame point (x, y)
local function label(fs, s, x, y, L)
    G.text_cells(fs, s, x, y - fs.size / 2, G.JC, function(idx, l, b)
        masked_cell(idx, l, b, 0, 0, fs.cw, fs.ch, 0, C.white, L)
    end)
end

-- pitch ladder: 5 deg ticks, 10 deg lines numbered on both sides, red
-- chevrons toward the horizon in unusual pitch (3.3.1.1, figure 3.4). Past
-- +-90 it goes on over the top, numbered back down (80, 70 ..), as the
-- 2024 Grids art, with a fourth chevron each side (2024: 4).
local CHEVRONS = { 51.3, 71.3, 91.3, 111.3 }
local function ladder(pitch, L)
    local fs = font("text", 20)
    local lo = math.floor((pitch - 35) / 5) * 5
    for p = lo, lo + 70, 5 do
        local a = math.abs(p)
        if p ~= 0 and a < 180 then
            local y = p * PPD
            local key = (p % 10 == 0) and "aa_bar10" or "aa_bar5"
            local bi, bs = G.img[key], G.size[key]
            if bi then masked_cell(bi, 0, y, bs[1] / 2, bs[2] / 2, bs[1], bs[2], 0, C.white, L) end
            if p % 10 == 0 and fs then
                local s = tostring((a <= 90) and a or 180 - a)
                label(fs, s, -88, y, L)
                label(fs, s, 88, y, L)
            end
        end
    end
    local i, sz = G.img["att_chevron"], G.size["att_chevron"]
    if i == nil then return end
    for _, p in ipairs(CHEVRONS) do
        for _, sgn in ipairs({ 1, -1 }) do
            local y = sgn * p * PPD
            if math.abs(y - pitch * PPD) < 260 then
                -- sky side points down at the horizon, ground side up
                masked_cell(i, 0, y, 62, 30, sz[1], sz[2], (sgn > 0) and 0 or 180, nil, L)
            end
        end
    end
end

-- LCD pixel scale of a layout: px -> display units, the LCD's width and
-- height in px (320 x 240, upright 240 x 320)
local function lcd_px(L)
    local up = L.W < L.H
    local pw, ph = up and 240 or 320, up and 320 or 240
    return L.W / pw, L.H / ph, pw, ph
end

-- the battery icon (rev Q 4.4.1, figure 4.25), 13 x 23 LCD px round (x, y):
-- a 1 px white outline round the body and the terminal (7 x 4 px); green on
-- the battery, black with a thin red X corner to corner when low (or the
-- battery failed, figure 5.17). The 2024 batt_icon art is this shape with a
-- thinner outline.
local function batt_icon(x, y, low, L)
    local sx, sy = lcd_px(L)
    local function px(c0, r0, c1, r1, col)        -- LCD columns / rows from the icon's top left
        G.rect(x + (c0 - 6.5) * sx, y + (11.5 - r1 - 1) * sy, x + (c1 + 1 - 6.5) * sx, y + (11.5 - r0) * sy, col)
    end
    local fill = low and C.black or C.batt_green
    px(3, 0, 9, 3, C.white)                       -- terminal
    px(0, 3, 12, 22, C.white)                     -- body
    px(4, 1, 8, 3, fill)
    px(1, 4, 11, 21, fill)
    if low then
        local x0, y0 = x - 6 * sx, y + 8 * sy           -- centres of the corner pixels
        local x1, y1 = x + 6 * sx, y - 11 * sy
        G.line(x0, y0, x1, y1, C.red_x, sx)
        G.line(x0, y1, x1, y0, C.red_x, sx)
    end
end

-- CONFIGURE HEADING (manual rev Q, 2024: 4.3.1.2, 4.3.1.3, 4.5.7; not in
-- rev B): DISPLAY ON puts the heading window at the bottom centre and the slip
-- indicator above and to the left of it (rev Q figures 4.5, 4.7). The heading
-- comes from an MD32 magnetometer or ARINC 429 (labels 014 / 320); X-Plane has
-- neither, so the window shows "---", as the real unit with no heading source
-- (figure 4.7). Drawn in LCD pixels (320 x 240), measured on figure 4.7.
-- The slip box: 98 x 14 px, corners rounded 3.5 px, one translucent polygon
-- (rows drawn one by one would show seams where they meet)
local slip_poly = {}
local function slip_box(x0, y0, sx, sy)
    local x1, y1, r = x0 + 98, y0 + 14, 3.5
    local corners = { { x1 - r, y0 + r, -90 }, { x1 - r, y1 - r, 0 }, { x0 + r, y1 - r, 90 }, { x0 + r, y0 + r, 180 } }
    local n = 0
    for _, c in ipairs(corners) do
        for a = c[3], c[3] + 90, 30 do
            slip_poly[n + 1] = (c[1] + r * math.cos(math.rad(a))) * sx
            slip_poly[n + 2] = (c[2] + r * math.sin(math.rad(a))) * sy
            n = n + 2
        end
    end
    G.poly(G.black_alpha(0.5), slip_poly)
end

-- With a heading source (config.ini [Sources] heading = md32 | arinc | pretend:
-- X-Plane's magnetic heading / the pilot's AHRS heading / X-Plane's magnetic
-- heading again): the three digits, the source arrows (figure 4.6: MD32
-- pointing out, ARINC and pretend pointing in) and the tape along
-- the bottom (figure 4.5: 70 px per 30 deg, a 4 x 10 px mark every 10 deg,
-- every 30 deg a number without its last 0, N E S W).
local HDG_PPD = 70 / 30
local CARDINAL = { [0] = "N", [9] = "E", [18] = "S", [27] = "W" }
local ARROW = nil

local function heading_tape(hdg, sx, sy, cx, pw)
    local fs = font("text", 20)
    local a = math.floor((hdg - (cx + 12) / HDG_PPD) / 10) * 10
    while a <= hdg + (pw - cx + 12) / HDG_PPD do
        local x = (cx + (a - hdg) * HDG_PPD) * sx
        local t = math.floor(a / 10 + 0.5) % 36
        if t % 3 == 0 then
            G.textc(fs, CARDINAL[t] or tostring(t), x, 10 * sy, C.white, G.JC)
        else
            G.rect(x - 2 * sx, 0, x + 2 * sx, 10 * sy, C.white)
        end
        a = a + 10
    end
end

local function source_arrow(x, yc, dir, sx, sy)
    -- 4 x 7 px grey triangle, its point toward dir (-1 left, +1 right)
    G.poly(ARROW, { x + dir * 2 * sx, yc, x - dir * 2 * sx, yc + 3.5 * sy, x - dir * 2 * sx, yc - 3.5 * sy })
end

local function heading_slip(st, L, D)
    local sx, sy, pw = lcd_px(L)
    local up = L.W < L.H
    local cx = pw / 2                                   -- LCD centre column
    local hdg = (cfg.heading ~= "none") and D and D.heading or nil
    if hdg then heading_tape(hdg, sx, sy, cx, pw) end
    -- heading window: 52 x 26 px on the bottom edge, 1 px outline; no
    -- heading: three 11 px dashes on row 13
    local x0, x1, y1 = (cx - 26) * sx, (cx + 26) * sx, 26 * sy
    G.rect(x0, 0, x1, y1, C.black)
    G.box(x0, 0, x1, y1, C.grey_line, sx)
    if hdg then
        local h = math.floor(hdg + 0.5) % 360
        if h == 0 then h = 360 end
        G.textc(font("digits", 28), string.format("%03d", h), cx * sx, 13 * sy, C.white, G.JC)
        -- on the gyro after the source was lost: no arrows (figure 4.6)
        if not D.hdg_gyro then
            ARROW = ARROW or G.hex("7C7C7C")
            local d = (cfg.heading == "md32") and 1 or -1
            source_arrow((cx - 22) * sx, 13 * sy, -d, sx, sy)
            source_arrow((cx + 22) * sx, 13 * sy, d, sx, sy)
        end
    else
        for _, d in ipairs({ -21, -5, 11 }) do
            G.rect((cx + d) * sx, 13 * sy, (cx + d + 11) * sx, 14 * sy, C.white)
        end
    end
    -- slip box from column 11, row L.slip_q; the lines and the ball 1 px in
    local bx, by = L.slip_x, L.slip_q
    slip_box(bx, by, sx, sy)
    for _, c in ipairs({ 39, 58 }) do
        G.rect((bx + c) * sx, (by + 1) * sy, (bx + c + 1) * sx, (by + 13) * sy, C.white)
    end
    -- +-7 deg end to end: the 12 px ball moves 42 px each way, by whole pixels
    local off = math.floor(U.clamp(-st.slip / 7, -1, 1) * 42 + 0.5)
    local bcx, bcy = (bx + 49 + off) * sx, (by + 7) * sy
    G.image("slip_ball", bcx - 6 * sx, bcy - 6 * sy, bcx + 6 * sx, bcy + 6 * sy, C.white)
end

-- brightness bar (rev Q 4.3.3, figure 4.24): a vertical bar along the left
-- edge of the attitude display, a sun over it, filled green from the bottom
-- (rev B has no figure of it)
local BAR_GREEN = nil
local sun_poly = {}
local function brightness_bar(level, L)
    local sx, sy, _, ph = lcd_px(L)
    BAR_GREEN = BAR_GREEN or G.hex("00F004")
    G.rect(5 * sx, 8 * sy, 25 * sx, (ph - 3) * sy, G.black_alpha(0.45))
    local y0, y1 = 11 * sy, (ph - 34) * sy
    G.box(7 * sx, y0, 24 * sx, y1, C.white, sx)
    -- the fill 3 px in from the 1 px outline on both sides (inside 8..23,
    -- fill 11..20, centred under the sun)
    local f = U.clamp(level, 0, 1)
    if f > 0 then G.rect(11 * sx, y0 + 4 * sy, 20 * sx, y0 + 4 * sy + (y1 - y0 - 8 * sy) * f, BAR_GREEN) end
    -- the sun: a disc of 3.5 px and eight rays to 8 px
    local cx, cy = 15.5 * sx, (ph - 20) * sy
    for k = 0, 11 do
        local a = math.rad(k * 30)
        sun_poly[2 * k + 1], sun_poly[2 * k + 2] = cx + 3.5 * sx * math.cos(a), cy + 3.5 * sy * math.sin(a)
    end
    G.poly(C.white, sun_poly)
    for k = 0, 7 do
        local a = math.rad(k * 45)
        G.line(cx + 5 * sx * math.cos(a), cy + 5 * sy * math.sin(a), cx + 8 * sx * math.cos(a),
            cy + 8 * sy * math.sin(a), C.white, 1.5)
    end
end

-- POWER DOWN IN nn SEC (rev Q 4.4.2, figure 4.26): a box over the attitude,
-- 233 x 51 px, ON / OFF, the lit one in the green cursor (OFF first)
local function power_down_box(st, L)
    local sx, sy, pw = lcd_px(L)
    local cx = pw / 2 + 0.5
    local x0, x1, y0, y1 = (cx - 116.5) * sx, (cx + 116.5) * sx, 39 * sy, 90 * sy
    local fs = font("text", 20)
    G.rect(x0, y0, x1, y1, C.black)
    G.box(x0, y0, x1, y1, C.white, sx)
    G.textc(fs, string.format("POWER DOWN IN %d SEC", math.max(1, math.ceil(st.pd.t))), cx * sx, 78 * sy,
        C.white, G.JC)
    for i, b in ipairs({ { "ON", cx - 33.5 }, { "OFF", cx + 34 } }) do
        local bx = b[2] * sx
        if st.pd.sel == i then
            G.rect(bx - 22.5 * sx, 43 * sy, bx + 22.5 * sx, 68 * sy, C.cursor)
            G.box(bx - 22.5 * sx, 43 * sy, bx + 22.5 * sx, 68 * sy, C.white, sx)
        end
        G.textc(fs, b[1], bx, 55.5 * sy, C.white, G.JC)
    end
end

-- SPLIT DELTA (rev Q 4.3.2.4, figure 4.15): the delta's two wings with the
-- middle cut out, two-tone like the delta (sym_delta.png F3ED2A / DABD33);
-- LCD px from the apex, y down; the yellow side bars as with the delta
local SPLIT = {
    { "F3ED2A", { -3, 0, -66, 18, -50, 18 } },
    { "DABD33", { -3, 0, -50, 18, -38, 18 } },
}
local split_cols = nil
local split_flat = {}
local function split_delta(L, x, y)
    split_cols = split_cols or { G.hex(SPLIT[1][1]), G.hex(SPLIT[2][1]) }
    for k, s in ipairs(SPLIT) do
        for _, side in ipairs({ 1, -1 }) do
            local p = s[2]
            for i = 1, #p, 2 do
                split_flat[i] = x + side * p[i] * 1.5625
                split_flat[i + 1] = y - p[i + 1] * 1.5583
            end
            G.poly(split_cols[k], split_flat)
        end
    end
    -- the side bars: sym_delta.png down to its row 9 (the delta starts on row 10)
    G.clip(0, y + 0.5, L.W, L.H)
    G.pic("sym_delta", x, y - 9.5)
    G.unclip()
end

function Dsp.attitude(D, st, bright_level, L)
    L = L or Dsp.LAY.h
    local PIV_X, PIV_Y = L.piv_x, L.piv_y
    -- 5.1.4: attitude failed, a red X on black
    if Fail and Fail.ATT then
        Fail.MD302_Fail_Draw_X(L.x_att, X_ATT_W)
        return
    end
    -- PANEL TILT / PANEL ROLL (4.4.1) are already in D.pitch / D.roll: the
    -- difference between the set angles and the object's mounting in the .acf
    -- (MD302.lua mount_errors; auto = the mounting, so nothing is added)
    local pitch = D.pitch
    local roll = D.roll
    tf.co, tf.si = math.cos(math.rad(roll)), math.sin(math.rad(roll))
    tf.x0, tf.y0, tf.dy, tf.roll = PIV_X, PIV_Y, -pitch * PPD, roll
    -- the ladder mask; its circle side turns with the roll scale (FIXED
    -- POINTER: with the horizon)
    mask.cx, mask.cy, mask.bottom, mask.x1, mask.top = PIV_X, PIV_Y + 1, L.lad_bottom, L.W, L.H
    if cfg.roll_display == "fixed_pointer" then
        mask.ux, mask.uy = -tf.si, tf.co
    else
        mask.ux, mask.uy = 0, 1
    end
    -- sky / ground and horizon (whole LCD), then the ladder in its mask
    G.push()
    G.translate(PIV_X, PIV_Y)
    G.rotate(0, 0, roll)
    G.translate(0, -pitch * PPD)
    sky_ground()
    G.pop()
    -- the horizon line, 6 du (aa_horizon: 1400 du long, so it crosses the LCD at any bank)
    local hi, hs = G.img["aa_horizon"], G.size["aa_horizon"]
    if hi then
        local X, Y = to_page(0, 0)
        G.atlas_turned(hi, X, Y, hs[1] / 2, hs[2] / 2, -roll, C.white)
    end
    ladder(pitch, L)

    -- roll scale and pointer (4.2.1): fixed scale = the pointer turns with the
    -- horizon (sky pointer); fixed pointer = the scale turns, the pointer stays up
    if cfg.roll_display == "fixed_pointer" then
        G.pic_pivot("att_roll_arc", PIV_X, PIV_Y + 1, 163, 111 - 184, -roll)
        G.pic_pivot("att_roll_pointer", PIV_X, PIV_Y + 1, 11, 14.5 - 140.5, 0)
    else
        G.pic("att_roll_arc", PIV_X, PIV_Y + 129.5)
        G.pic_pivot("att_roll_pointer", PIV_X, PIV_Y + 1, 11, 14.5 - 140.5, -roll)
    end

    -- slip indicator (3.3.1.4): +-7 deg end to end, ball moves 100 px; with
    -- the heading displayed it is left of the heading window (heading_slip).
    -- The ball is white as in rev Q 3.3.1.4 and on the real unit (rev B and
    -- the 2024 art: yellow)
    if cfg.heading_display ~= "on" then
        G.pic("att_slip_box", PIV_X, 20.5)
        local sx = U.clamp(-st.slip / 7, -1, 1) * 100
        G.pic("slip_ball", PIV_X + sx, 20, C.white)
    end

    -- symbolic airplane (rev Q 4.3.2.4: DELTA, SPLIT DELTA, TRADITIONAL)
    if M.opt.symbol == "traditional" then
        G.pic("sym_traditional", PIV_X, PIV_Y - 7)
    elseif M.opt.symbol == "split_delta" then
        split_delta(L, PIV_X, PIV_Y - 4.5)
    else
        G.pic("sym_delta", PIV_X, PIV_Y - 14)
    end

    if M.opt.att_mask == "on" then
        if L.mask_turn then
            G.pic_pivot("att_mask", L.W / 2, L.H / 2, 250, 187, 90)
        else
            G.pic("att_mask", 250, 187)
        end
    end
    -- over the mask (it dims the corners, 3.3.2.5), so the slip box stays readable
    if cfg.heading_display == "on" then heading_slip(st, L, D) end
    -- on the battery; a failed battery (figure 5.17) shows on aircraft power too
    if M.on_battery() or M.battery_failed() then
        batt_icon(L.batt[1], L.batt[2], M.battery_low() or M.battery_failed(), L)
    end
    if st.bright_t > 0 then brightness_bar(bright_level, L) end
    if st.pd then power_down_box(st, L) end
end

-----------------------------------------------------------------------------
-- Airspeed and altitude (right LCD)
-----------------------------------------------------------------------------

-- airspeed range markings (rev Q 4.5.2.4, figure 4.33): { width, colour, lo,
-- hi }; width "F" full, "H" half (the right half, drawn over the full ones),
-- "R" radial (a line 2.3 LCD px thick at lo across the bars and into the
-- ticks); colour "bar" = barber pole stripes. A BAR to MAX is not drawn on
-- its own: with the MMO and the VNE TABLE it is the one barber pole, from
-- the lowest of the three (4.5.2.5).
local BAND_COL = {}
local function band_color(name)
    if BAND_COL[name] == nil then
        BAND_COL[name] = ({ red = C.red, yellow = C.band_yellow, green = C.green, white = C.white,
            blue = G.hex("3A8EE6"), magenta = C.magenta, amber = G.hex("F0A000") })[name] or C.white
    end
    return BAND_COL[name]
end

local RADIAL_W, RADIAL_HW = 34, 1.8

-- barber pole stripes (mmo_tape, 18 x 374) in x0..x1, y0..y1, the pattern
-- starting at ys
local function stripes(x0, y0, x1, y1, ys, H)
    if y1 < 0 or y0 > H or y1 <= y0 then return end
    local top = math.min(y1, H)
    G.clip(x0, math.max(y0, 0), x1, top)
    for cx = 9, x1 + 9, 18 do
        local k = math.max(0, math.floor((math.max(y0, 0) - ys) / 374))
        while ys + k * 374 < top do
            G.pic("mmo_tape", cx, ys + 187 + k * 374)
            k = k + 1
        end
    end
    G.unclip()
end

local BAND_ORDER = { "F", "H", "R" }
local function range_bands(bands, spd, ppu, cy, H)
    local pole = nil
    for _, w in ipairs(BAND_ORDER) do
        for _, b in ipairs(bands) do
            if b.width == w then
                local y0 = cy + (b.lo - spd) * ppu
                local y1 = cy + (b.hi - spd) * ppu
                local bar = b.color == "bar"
                if w == "R" then
                    if bar then
                        stripes(0, y0 - RADIAL_HW, RADIAL_W, y0 + RADIAL_HW, y0 - RADIAL_HW, H)
                    elseif y0 > -2 and y0 < H + 2 then
                        G.rect(0, y0 - RADIAL_HW, RADIAL_W, y0 + RADIAL_HW, band_color(b.color))
                    end
                elseif bar and w == "F" and b.hi >= 999 then
                    if pole == nil or b.lo < pole then pole = b.lo end
                elseif bar then
                    stripes((w == "H") and 9 or 0, y0, 18, y1, y0, H)
                elseif y1 > 0 and y0 < H then
                    G.rect((w == "H") and 9 or 0, math.max(y0, -2), 18, math.min(y1, H + 2), band_color(b.color))
                end
            end
        end
    end
    return pole
end

local TICK_HW = 2.75                    -- half the tape ticks' thickness (3.5 LCD px)

local function speed_tape(D, spd, ppu, major, minor, bands, L)
    local SPD_CY, H = L.spd_cy, L.H
    local fs = font("digits", 20)
    local top = (H - SPD_CY) / ppu
    local bottom = SPD_CY / ppu
    -- range markings at the left margin; the barber pole from the lowest of a
    -- BAR to MAX, the Mmo speed and the VNE TABLE speed at this altitude
    local pole = range_bands(bands, spd, ppu, SPD_CY, H)
    if cfg.range_mmo > 0 and D.vmo_kt > 0 then
        local v = D.vmo_kt * cfg.speed_factor
        if pole == nil or v < pole then pole = v end
    end
    if D.vne and (pole == nil or D.vne < pole) then pole = D.vne end
    if pole then
        local y0 = SPD_CY + (pole - spd) * ppu
        stripes(0, y0, 18, H, y0, H)
    end
    -- ticks and numbers (rev Q dumps, p27 / p45: 12 and 6 LCD px long from
    -- x 16, 3.5 px thick; the 2024 art had 13 / 8 px, 4.5 px)
    G.subpixel(false, true)
    local v0 = math.floor((spd - bottom) / minor) * minor
    for v = math.max(0, v0), spd + top + minor, minor do
        local y = SPD_CY + (v - spd) * ppu
        if v % major == 0 then
            G.rect(25, y - TICK_HW, 43.75, y + TICK_HW, C.white)
            if v > 0 then G.led(fs, tostring(v), 90, y, C.white) end
        else
            G.rect(25, y - TICK_HW, 34.4, y + TICK_HW, C.white)
        end
    end
    G.subpixel(false, false)
end

local function alt_label(v)
    local a = math.abs(v)
    local th = math.floor(a / 1000)
    local hu = a % 1000
    local hs = (th > 0) and string.format("%03d", hu) or tostring(hu)
    local ts = (th > 0) and tostring(th) or ""
    if v < 0 then ts = "-" .. ts end
    return ts, hs
end

-- ticks every 25 units in three lengths (rev Q 4.3.1.4, dumps p27 / p45: 19,
-- 13 and 8 LCD px for 100 / 50 / 25, ending at x 308), numbered every 100,
-- the thousands only a little taller than the hundreds (16 px to 13 px; the
-- 2024 art had them 40 % taller)
local ALT_TICK = { [0] = 451.6, [50] = 460.9 }
local function alt_tape(alt, L)
    local ppu = 20.5 / 25                       -- ALT_Marker_Tape: 0.82 px per unit
    local fs_th, fs_hu = font("digits", 25), font("digits", 20)
    local cy, dx = L.alt_cy, L.alt_dx
    local top, bottom = (L.H - cy) / ppu, cy / ppu
    local v0 = math.floor((alt - bottom) / 25) * 25
    G.subpixel(false, true)
    for v = v0, alt + top + 25, 25 do
        local y = cy + (v - alt) * ppu
        local x0 = ALT_TICK[v % 100] or 468.75
        G.rect(x0 + dx, y - TICK_HW, 481.25 + dx, y + TICK_HW, C.white)
        if v % 100 == 0 then
            local ts, hs = alt_label(v)
            -- 2024 layout had the thousands slot end at 386, 6 px into the
            -- hundreds slot, so the digits touched; 380 leaves a gap
            if ts ~= "" then G.led(fs_th, ts, 380 + dx, y + 1, C.white) end
            G.led(fs_hu, hs, 432 + dx, y, C.white)
        end
    end
    G.subpixel(false, false)
end

-- the altitude window (rev Q 4.3.1.4, figures 4.8-4.10): thousands (large) and
-- hundreds on the pointer line, the tens on a drum "every 20 units"; in the
-- last 20 units of a hundred the hundreds roll with the drum (figure 4.8:
-- 1287 shows the 2 and the top of the 3), and the thousands with them at x980.
-- Drum pitch: the dumps' 32 of the drum window's 75 px, on ours (104 px);
-- the thousands (46 px digits) roll the same fraction over a longer pitch
local DRUM_P, THOUS_P = 44, 54
local function alt_window(alt, L)
    local dx, dy = L.alt_dx, L.alt_cy - 187
    local a = math.abs(alt)
    local th = math.floor(a / 1000)
    local hu = math.floor(a % 1000 / 100)
    local tens = a % 100
    local frac = math.max(0, tens - 80) / 20
    local roll = frac * DRUM_P
    local troll = (hu == 9) and frac * THOUS_P or 0
    local function th_str(n)
        local s = (n > 0) and tostring(n) or ""
        if alt < 0 then s = "-" .. s end
        return s
    end
    -- the wide part of the window (2024 windows_alt: 64 px high)
    G.clip(263 + dx, 157 + dy, 381 + dx, 221 + dy)
    G.subpixel(false, true)
    local ft = font("digits", 46)
    G.led(ft, th_str(th), 344 + dx, 191 + dy - troll, C.white)
    if troll > 0 then G.led(ft, th_str(th + 1), 344 + dx, 191 + dy - troll + THOUS_P, C.white) end
    local fh = font("digits", 35)
    if fh then
        local x = 363 + dx + fh.g[48][2] / 2       -- old cell centre x 363
        G.led(fh, tostring(hu), x, 188 + dy - roll, C.white)
        if roll > 0 then G.led(fh, tostring((hu + 1) % 10), x, 188 + dy - roll + DRUM_P, C.white) end
    end
    G.unclip()
    -- tens drum: "40" / "20" / "00" ... every 20 units
    local fs = font("digits", 24)
    G.clip(386 + dx, 136 + dy, 435 + dx, 240 + dy)
    local k0 = math.floor(tens / 20)
    for k = k0 - 2, k0 + 3 do
        local y = 188 + dy + (k * 20 - tens) / 20 * DRUM_P
        G.led(fs, string.format("%02d", (k * 20) % 100), 435 + dx - 4, y, C.white)
    end
    G.subpixel(false, false)
    G.unclip()
end

-- the airspeed window: hundreds + tens, rolling ones (3.3.1.3)
local function spd_window(spd, L)
    local dy = L.spd_cy - 187
    local s = math.max(0, spd)
    local ht = math.floor(s / 10)
    G.led(font("digits", 43), (ht > 0) and tostring(ht) or "", 133.6, 192 + dy, C.white)
    G.clip(141, 126 + dy, 181, 248 + dy)
    G.subpixel(false, true)
    -- below 10 the drum has nothing under 0
    G.roll(font("digits", 42), 161, L.spd_cy - 21, s % 10, 54.8, C.white, (ht == 0) and -1 or nil)
    G.subpixel(false, false)
    G.unclip()
end

-- fn(...) drawn s times its size about (x, y)
local function scaled(s, x, y, fn, ...)
    if s == 1 then return fn(...) end
    G.push()
    G.translate(x, y)
    G.scale(s)
    G.translate(-x, -y)
    fn(...)
    G.pop()
end

local SYNC_L = { 210.6, 350.7, 210.6, 364.7, 218.4, 357.7 }     -- figure 4.8: 5 x 9 px, grey
local SYNC_R = { 326.2, 350.7, 326.2, 364.7, 318.4, 357.7 }
-- the BARO window, LCD rows 23..47 on the rev Q dumps (p27 / p28), its frame
-- as heavy as the airspeed / altitude windows' (2 px)
local BARO_Y0, BARO_Y1, BARO_LINE = 299.5, 339.5, 3
local sync_col = nil

local function baro_box(D, st, L)
    local bx, by = L.baro_dx, L.baro_dy
    local inhg = D.baro_inhg
    local txt
    if M.opt.baro_units == "hpa" then
        txt = string.format("%d", math.floor(inhg * 33.8639 + 0.5))
    else
        txt = string.format("%.2f", inhg)
    end
    G.textc(font("text", 20), "BARO", 266 + bx, 357.7 + by, C.white, G.JC)
    -- rev Q figures 4.8 / 4.10: in step with the primary's baro setting (BARO
    -- SYNC), an arrow each side of BARO pointing in; gone once the knob sets it
    if st.baro_synced then
        sync_col = sync_col or G.hex("808080")
        G.push()
        G.translate(bx, by)
        G.poly(sync_col, SYNC_L)
        G.poly(sync_col, SYNC_R)
        G.pop()
    end
    -- rev Q 4.3.1.4, figures 4.9 / 4.10: set by the knob or by the sync, the
    -- window grows 2 px and it and the digits turn green (3 px line); the
    -- digits keep their size
    local adj = st.baro_t > 0
    local g = adj and 3 or 0
    local y0, y1 = BARO_Y0 + by - g, BARO_Y1 + by + g
    -- the dump's window is x 212..316; 2 px wider each side so the 25 px
    -- digits (100 px for "29.92") keep clear of the line
    G.rect(210 + bx - g, y0, 318 + bx + g, y1, C.black)
    G.box(210 + bx - g, y0, 318 + bx + g, y1, adj and C.baro_green or C.grey_line, adj and 4.5 or BARO_LINE)
    local fs = font("digits", 25)
    if fs == nil then return end
    local w = 0
    for k = 1, #txt do
        local b = string.byte(txt, k)
        w = w + ((b == 46) and fs.g[46][2] or fs.g[48][2])
    end
    G.led(fs, txt, 264 + bx + w / 2, (BARO_Y0 + BARO_Y1) / 2 + by, adj and C.baro_green or C.white)
end

function Dsp.air_data(D, st, L)
    L = L or Dsp.LAY.h
    local spd = D.ias_kt * cfg.speed_factor
    -- AIRSPEED MINIMUM (rev Q 4.5.6.2): below it (in knots, whatever the
    -- units) the airspeed reads 0
    if D.ias_kt < cfg.airspeed_minimum then spd = 0 end
    local alt = D.alt_ft
    if M.opt.alt_units == "meters" then alt = alt * 0.3048 end
    local ppu, major, minor = L.spd_ppu, 10, 5
    if cfg.airspeed_units == "kph" then ppu, major, minor = L.spd_ppu / 2, 20, 10 end
    -- 5.1.4: a failed instrument is a red X, the other one and BARO stay
    local ias_ok = not (Fail and Fail.IAS)
    local alt_ok = not (Fail and Fail.ALT)

    if ias_ok then speed_tape(D, spd, ppu, major, minor, D.bands, L) end
    if alt_ok then
        alt_tape(alt, L)
        if M.opt.alt_trend == "on" then
            -- rev Q figures 4.8-4.10: a column at the right edge (11 px), the
            -- magenta bar from the pointer to where the altitude will be in
            -- 6 s (level: 2 px, the white line on the upper one), grey marks
            -- at +-100 / +-200 units and a white line at the pointer (1 px)
            local trend = st.vs_fpm / 60 * cfg.trend_s
            if M.opt.alt_units == "meters" then trend = trend * 0.3048 end
            local cy, ppu, px = L.alt_cy, 20.5 / 25, 1.56
            local x0, x1 = 482.8 + L.alt_dx, 500 + L.alt_dx
            local h = U.clamp(trend * ppu, -cy, L.H - cy)
            G.rect(x0, math.min(cy, cy + h) - px * 1.5, x1, math.max(cy, cy + h) + px / 2, C.magenta)
            for _, u in ipairs({ -200, -100, 100, 200 }) do
                local y = cy + u * ppu
                G.rect(x0 + px, y - px / 2, x1 - px, y + px / 2, C.trend_grey)
            end
            G.rect(x0 + px, cy - px / 2, x1 - px, cy + px / 2, C.white)
        end
    end
    -- windows: black inside, then the readouts, then the 2024 outlines, the
    -- units under them; on an upright LCD smaller, about each window's pointer
    local sy, ay, ax = 187.5 + L.spd_cy - 187, 187.5 + L.alt_cy - 187, 360.5 + L.alt_dx
    if ias_ok then
        scaled(L.win_s, 42, L.spd_cy, function()
            G.pic("windows_fill_spd", 117, sy)
            spd_window(spd, L)
            G.pic("windows_spd", 117, sy)
            local units = ({ knots = "KTS", mph = "MPH", kph = "KPH" })[cfg.airspeed_units] or "KTS"
            G.textc(font("text", 20), units, 165, 110 + L.spd_cy - 187, C.white, G.JC)
        end)
    else
        Fail.MD302_Fail_Draw_X(L.x_ias, X_SIDE_W)
    end
    if alt_ok then
        scaled(L.win_s, 458 + L.alt_dx, L.alt_cy, function()
            G.pic("windows_fill_alt", ax, ay)
            alt_window(alt, L)
            G.pic("windows_alt", ax, ay)
            G.textc(font("text", 20), (M.opt.alt_units == "meters") and "METERS" or "FEET", 318 + L.alt_dx,
                135 + L.alt_cy - 187, C.white, G.JC)
        end)
    else
        Fail.MD302_Fail_Draw_X(L.x_alt, X_SIDE_W)
    end
    scaled(L.baro_s, 264 + L.baro_dx, (BARO_Y0 + BARO_Y1) / 2 + L.baro_dy, baro_box, D, st, L)
end

-----------------------------------------------------------------------------
-- Menus (3.3.2), in place of the attitude display
-----------------------------------------------------------------------------

local ROW0, PITCH = 294.5, 37.5         -- cap centre of the first item, row pitch

-- the title from x 5 LCD px; a sub-menu's ">" with the title 5 px after it,
-- closer than a space (rev Q dumps)
local TITLE_X, ARROW_GAP = 5 * 1.5625, 5 * 1.5625
local function title_bar(text)
    G.rect(0, 322, W, H, C.menu_blue)
    G.rect(0, 321, W, 322, G.hex("180C63"))
    G.rect(0, 320, W, 321, G.hex("716A9E"))
    G.rect(0, 319, W, 320, C.menu_line)
    G.rect(0, 318, W, 319, G.hex("323233"))
    local fs = font("text", 20)
    if string.sub(text, 1, 2) == "> " then
        G.text(fs, ">", TITLE_X, 338, C.white)
        G.text(fs, string.sub(text, 3), TITLE_X + G.text_w(fs, ">") + ARROW_GAP, 338, C.white)
    else
        G.text(fs, text, TITLE_X, 338, C.white)
    end
end
Dsp.title_bar = title_bar

local function cursor(x0, x1, yc)
    G.rect(x0, yc - 21.5, x1, yc + 21.5, C.cursor)
    G.box(x0, yc - 21.5, x1, yc + 21.5, C.white, 2)
end

-- rev Q figures 4.12-4.17: the values and the choices in a column from 122
-- LCD px, the cursor round the text it is on (as INFO MENU)
local OPT_X = 190
local function options_menu(m)
    local fs = font("text", 20)
    title_bar("OPTIONS MENU")
    if m.entered then
        local it = M.ITEMS[m.entered]
        cursor(OPT_X - 7, OPT_X + G.text_w(fs, it.opts[m.opt][2]) + 7, ROW0 - PITCH * (m.entered - 1 + m.opt - 1))
    else
        cursor(5, 12 + G.text_w(fs, M.ITEMS[m.sel].label) + 7, ROW0 - PITCH * (m.sel - 1))
    end
    for i, it in ipairs(M.ITEMS) do
        local yc = ROW0 - PITCH * (i - 1)
        local col = C.white
        if m.entered then
            if i ~= m.entered then col = C.grey_text end
        elseif not M.selectable(i) then
            col = C.grey_text
        end
        G.textc(fs, it.label, 12, yc, col)
        if it.opts and not m.entered then
            G.textc(fs, M.opt_label(it, M.opt[it.key]), OPT_X, yc, C.grey_text)
        end
    end
    if m.entered then
        local it = M.ITEMS[m.entered]
        for j, o in ipairs(it.opts) do
            G.textc(fs, o[2], OPT_X, ROW0 - PITCH * (m.entered - 1 + j - 1), C.white)
        end
    end
end

-- INFO MENU (rev Q 4.3.2.7, figure 4.18): its four items, the cursor round the text
local function info_menu(m)
    local fs = font("text", 20)
    title_bar("> INFO MENU")
    for i, label in ipairs(M.INFO_ITEMS) do
        local yc = ROW0 - PITCH * (i - 1)
        if i == m.isel then cursor(5, 12 + G.text_w(fs, label) + 7, yc) end
        G.textc(fs, label, 12, yc, M.info_ok(i) and C.white or C.grey_text)
    end
end

-- REVIEW CONFIG / SOFTWARE INFO / BATTERY INFO (figures 4.19-4.21): lines
-- 20 LCD px apart from y 67.5 px, headings at x 5 px, values at 19 px in grey,
-- table columns where the line has them; grey triangles (13 px, x 120 px)
-- when there is more above / below
local LINE0, LINE_P = (240 - 67.5) * 374 / 240, 20 * 374 / 240
local TRI_UP = { 178.1, 291.4, 198.4, 291.4, 188.3, 311.7 }
local TRI_DN = { 178.1, 26.5, 198.4, 26.5, 188.3, 6.2 }
local tri_col = nil

local function lines_page(title, lines, top)
    local fs = font("text", 20)
    title_bar(title)
    for k = 0, M.LINES - 1 do
        local l = lines[top + k]
        if l then
            local yc = LINE0 - LINE_P * k
            if l[3] then
                for _, c in ipairs(l[3]) do G.textc(fs, c[1], c[2], yc, C.grey_text, c[3]) end
            else
                -- a long SSEC file name is cut 10 px before the right edge
                local x = l[2] and 19 * 1.5625 or 5 * 1.5625
                G.textc(fs, G.text_fit(fs, l[1], W - 10 - x), x, yc, l[2] and C.grey_text or C.white)
            end
        end
    end
    tri_col = tri_col or G.hex("7C7C7C")
    if top > 1 then G.poly(tri_col, TRI_UP) end
    if top + M.LINES - 1 < #lines then G.poly(tri_col, TRI_DN) end
end

local PAGE_TITLE = { review = "REVIEW CONFIG", software = "SOFTWARE INFO", battery = "BATTERY INFO" }

function Dsp.menu(st)
    G.rect(0, 0, W, H, C.black)
    local m = st.menu
    if PAGE_TITLE[m.page] then
        lines_page(PAGE_TITLE[m.page], M.page_lines(m.page), m.top)
    elseif m.page == "info" then
        info_menu(m)
    else
        options_menu(m)
    end
end

-----------------------------------------------------------------------------
-- Pre-flight (rev Q 4.2, figure 4.1)
-----------------------------------------------------------------------------

-- the logo, then SSEC (when an SSEC table is loaded), S/W VERSION and RUN
-- TIME; label at x 48 px, the value 19 px after it (28 on the dumps: our
-- "X-PLANE 2.0.0" is longer than "1.1.0")
-- upright (vertical installation, as photos of the unit): the logo, SAM and
-- MD302 stacked with a line between, the lines at the bottom from x 10 px;
-- the parts are cut from the horizontal page's logo (420 x 200, y down)
local LOGO_PARTS = {
    { 40, 0, 380, 75, 429 },            -- x0, y0, x1, y1 in the image, centre y on the LCD
    { 0, 95, 230, 185, 298 },           -- SAM (without the divider after it)
    { 255, 95, 420, 185, 182 },         -- MD302
}
local function preflight_v(st, L)
    local fs = font("text", 16)         -- our "X-PLANE 2.0.0" is longer than the unit's "1.1.0":
                                        -- at 18 px the S/W VERSION row ran past the 374 px LCD
    G.rect(0, 0, L.W, L.H, C.black)
    local cx = L.W / 2
    for _, p in ipairs(LOGO_PARTS) do
        local w, h = p[3] - p[1], p[4] - p[2]
        G.clip(cx - w / 2, p[5] - h / 2, cx + w / 2, p[5] + h / 2)
        G.pic("preflight_logo", cx - ((p[1] + p[3]) / 2 - 210), p[5] + ((p[2] + p[4]) / 2 - 100))
        G.unclip()
    end
    G.rect(45, 229.5, 322, 232.5, C.white)
    local rows = { { "S/W VERSION:", Dsp.SW_VERSION, 83 }, { "RUN TIME (HRS):", tostring(math.floor(st.run_time_s / 3600)), 44 } }
    if cfg.ssec_file ~= "" then table.insert(rows, 1, { "SSEC:", "FILE " .. string.upper(cfg.ssec_file), 122 }) end
    for _, r in ipairs(rows) do
        local x = 15.6 + G.text_w(fs, r[1]) + 12      -- the value cut 10 px before the edge
        G.textc(fs, r[1], 15.6, r[3], C.white)
        G.textc(fs, G.text_fit(fs, r[2], L.W - 10 - x), x, r[3], C.white)
    end
end

function Dsp.preflight(st, L)
    if L and L.W < L.H then return preflight_v(st, L) end
    local fs = font("text", 20)
    G.rect(0, 0, W, H, C.black)
    G.pic("preflight_logo", 250, 234)
    local rows = {
        { "S/W VERSION:", Dsp.SW_VERSION, 77.1 },
        { "RUN TIME (HRS):", tostring(math.floor(st.run_time_s / 3600)), 39.0 },
    }
    if cfg.ssec_file ~= "" then table.insert(rows, 1, { "SSEC:", "FILE " .. string.upper(cfg.ssec_file), 116.1 }) end
    for _, r in ipairs(rows) do
        local x = 75 + G.text_w(fs, r[1]) + 30        -- the value cut 10 px before the edge
        G.textc(fs, r[1], 75, r[3], C.white)
        G.textc(fs, G.text_fit(fs, r[2], W - 10 - x), x, r[3], C.white)
    end
end

Dsp.SW_VERSION = "X-PLANE 2.0.0"

return Dsp

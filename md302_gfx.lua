-- Copyright (c) 2026 Tiezheng Eric Xu, erix@x-plane.com, Laminar Research - MIT License, see LICENSE
--
-- md302_gfx.lua: thin layer over XPLMPanelGraphics.
--
-- Callers work in display units: one MD302 LCD is 500 x 374, origin
-- bottom-left, y up (the 2024 Plane Maker art is 1:1 at this size). The
-- device framebuffer holds both LCDs at 1:1, so there is no scaling here;
-- MD302.lua translates to each LCD's origin before drawing it.
-- Scissor rectangles are only set outside a rotation (XPLMPanelGraphics.h:
-- a scissor while XPLMTransformRotate is in effect is an error, whatever the
-- angle). A whole page turned by a quarter (vertical installation) is
-- therefore turned here, in software: G.quarter_begin maps every point,
-- rectangle and clip, and turns glyphs and images with the atlas' own
-- rotation; G.rotate inside it is handed to X-Plane conjugated.

local G = {}

G.W = 500
G.H = 374

-----------------------------------------------------------------------------
-- Colours (packed once at start; XPLMMakeColor is a C call)
-----------------------------------------------------------------------------

G.C = {}

local function hex(h, a)
    local r = tonumber(string.sub(h, 1, 2), 16) / 255
    local g = tonumber(string.sub(h, 3, 4), 16) / 255
    local b = tonumber(string.sub(h, 5, 6), 16) / 255
    return XPLMMakeColor(r, g, b, a or 1)
end
G.hex = hex

function G.rgba(r, g, b, a)
    return XPLMMakeColor(r, g, b, a or 1)
end

-- Palette sampled from the 2024 MD302 panel art; white, outlines, yellow, sky
-- and ground moved to what photos of the real (black-bezel) unit show,
-- calibrated on its white. 2024 values in the comments.
function G.init_colors()
    local C = G.C
    C.black      = hex("000000")
    C.white      = hex("EEF0F8")    -- every text and the white symbols: a cool backlight (2024 F2F2F4)
    C.grey_line  = hex("EEF0F8")    -- window / BARO outlines: the text white, as on the real unit
                                    -- (2024 grey D6D6D5, dumps 60609C)
    C.grey_text  = hex("7A7A7C")    -- unavailable / current-value text (manual 3.3.2.1)
    C.yellow     = hex("E5E230")    -- delta symbol (2024 F3ED2A; the 2024 slip ball was yellow too,
                                    -- it is C.white as rev Q and the real unit)
    C.green      = hex("3BBF1A")    -- airspeed band (SPD_Bar_Green)
    C.band_yellow = hex("EEE000")   -- airspeed band (SPD_Bar_Yellow)
    C.red        = hex("EB2214")    -- band, chevrons, dialog title
    C.magenta    = hex("B915BE")    -- altitude trend bar (VS_Bar)
    C.trend_grey = hex("606060")    -- the trend column's +-100 / +-200 marks (rev Q dumps)
    C.baro_green = hex("00FC00")    -- BARO window and digits while set (rev Q figures 4.9 / 4.10)
    C.batt_green = hex("4EF625")    -- battery icon (2024 batt_icon art)
    C.menu_blue  = hex("0C005B")    -- menu title bar
    C.menu_line  = hex("C9C6D8")    -- the light line under the title bar
    C.cursor     = hex("175B07")    -- menu cursor / OK button fill
    C.slip_bg    = hex("000000", 0.5)
    C.sky        = hex("027CE9")    -- 2024 3251D9
    C.ground     = hex("7C1606")    -- photo 832C2D less blue for the 3D cockpit (2024 7B2618)
    C.red_x      = hex("F80000")    -- failure X (5.1.4 screen dumps)
    C.fade = {}
    for i = 0, 20 do C.fade[i] = XPLMMakeColor(0, 0, 0, i / 20) end
end

-- alpha-scaled black, cached in 1/20 steps
function G.black_alpha(a)
    local i = math.floor(a * 20 + 0.5)
    if i < 0 then i = 0 elseif i > 20 then i = 20 end
    return G.C.fade[i]
end

local JL, JC, JR = 0, 1, 2
G.JL, G.JC, G.JR = JL, JC, JR

-----------------------------------------------------------------------------
-- Quarter turn (vertical installation): a page Wc x Hc drawn turned by q =
-- +90 (counter-clockwise) or -90 degrees into an Hc x Wc frame.
-----------------------------------------------------------------------------

local qt = nil          -- nil, or { q, Wc, Hc }
local function qmap(x, y)
    if qt == nil then return x, y end
    if qt[1] > 0 then return qt[3] - y, x end
    return y, qt[2] - x
end
local function qvec(dx, dy)
    if qt == nil then return dx, dy end
    if qt[1] > 0 then return -dy, dx end
    return dy, -dx
end

function G.quarter_begin(q, wc, hc)
    qt = { (q > 0) and 90 or -90, wc, hc }
end

function G.quarter_end()
    qt = nil
end

-----------------------------------------------------------------------------
-- Raster fonts (md302_font_data.lua, baked from the STXihei glyphs of the
-- 2024 art). Faces: "text" (letters, size =
-- cap height) and "digits" (LED digits, size = digit height, tabular).
-- Glyph cells are drawn 1:1 at whole pixels unless G.subpixel is on.
-- The text face is set 1 LCD px a letter tighter than the 2024 art (TRACK x
-- size): the unit's lettering is that much closer on the rev Q dumps
-- ("CONFIGURE" 92 px there, 100 px with the art's spacing); the glyphs are
-- the art's.
-----------------------------------------------------------------------------

local TRACK = { text = -1.5 / 20 }
G.rf = nil        -- face -> size -> {base, cw, ch, ox, oy, g, size}
local rf_sizes = {} -- face -> sorted sizes
local rf_warned = {}

local function rf_pick(face, px)
    local sizes = rf_sizes[face]
    if sizes == nil then return nil end
    local want = math.floor(px + 0.5)
    local best, bd = nil, math.huge
    for _, sz in ipairs(sizes) do
        local d = math.abs(sz - want)
        if d < bd then best, bd = sz, d end
    end
    if bd > 0 and not rf_warned[face .. want] then
        rf_warned[face .. want] = true
        print(string.format("[MD302 XLua2] raster font %s %d px not baked, using %d px", face, want, best))
    end
    return G.rf[face][best]
end

-- face at a pixel size (nil without raster fonts)
function G.font(face, px)
    return G.rf and rf_pick(face, px)
end

local cps = {}
local function codepoints(str)
    local n, i, len = 0, 1, #str
    while i <= len do
        local c = string.byte(str, i)
        if c >= 0xE0 and i + 2 <= len then
            c = (c - 0xE0) * 4096 + (string.byte(str, i + 1) - 0x80) * 64 + (string.byte(str, i + 2) - 0x80)
            i = i + 3
        elseif c >= 0xC0 and i + 1 <= len then
            c = (c - 0xC0) * 64 + (string.byte(str, i + 1) - 0x80)
            i = i + 2
        else
            i = i + 1
        end
        n = n + 1
        cps[n] = c
    end
    return n
end

-- Text that slides with a tape or drum keeps its fractional position along
-- the motion (G.subpixel(false, true)); switch it back off afterwards.
local free_x, free_y = false, false
function G.subpixel(x, y)
    free_x, free_y = x and true or false, y and true or false
end

local function rf_glyph(fs, gl, px, base, col)
    if not free_x then px = math.floor(px + 0.5) end
    if not free_y then base = math.floor(base + 0.5) end
    local l = px - fs.ox
    local b = base - fs.oy
    if qt then
        local x, y = qmap(l, b)
        XPLMTextureAtlasDrawScaled(G.atlas, fs.base + gl[1], col, x, y, 0, 0, 1, 1, -qt[1])
        return
    end
    XPLMTextureAtlasDrawIn(G.atlas, fs.base + gl[1], col, l, b + fs.ch, l + fs.cw, b)
end

-- a glyph's advance with the face's tracking; a space gives the tracking of
-- the letter before it back, so words stay as far apart as in the art. A
-- tracked face advances whole pixels (advance and tracking rounded apart, so
-- the space gives back exactly what the letter took): with fractional pens
-- each letter rounded its own way and the gaps came out a pixel wider or
-- narrower by turns
local function adv(fs, cp, gl)
    if fs.track == 0 then return gl[2] end
    local tr = math.floor(fs.track + 0.5)
    return math.floor(gl[2] + 0.5) + ((cp == 32) and -tr or tr)
end

local function rf_width(fs, n)
    local w = 0
    for k = 1, n do
        local gl = fs.g[cps[k]]
        if gl then w = w + adv(fs, cps[k], gl) end
    end
    return w
end

-- ink width: first glyph's left edge .. last glyph's right edge
local function ink_width(fs, n)
    local first, last, lcp
    for k = 1, n do
        local gl = fs.g[cps[k]]
        if gl then
            first = first or gl
            last, lcp = gl, cps[k]
        end
    end
    if first == nil then return 0, 0 end
    return rf_width(fs, n) - adv(fs, lcp, last) + last[4] - first[3], first[3]
end

-- string, y = baseline; just: G.JL / G.JC / G.JR on the ink
function G.text(fs, str, x, y, col, just)
    if fs == nil then return end
    local n = codepoints(str)
    local pen = x
    if just == JC or just == JR then
        local w, l0 = ink_width(fs, n)
        pen = (just == JC) and (x - w / 2 - l0) or (x - w - l0)
    end
    for k = 1, n do
        local gl = fs.g[cps[k]]
        if gl then
            rf_glyph(fs, gl, pen, y, col)
            local a = adv(fs, cps[k], gl)
            -- "__": the next one starts past this one's ink; a copy ending
            -- where the next one's ink starts closes the gap, so a run is one line
            if cps[k] == 95 and k < n and cps[k + 1] == 95 then rf_glyph(fs, gl, pen + a + gl[3] - gl[4], y, col) end
            pen = pen + a
        end
    end
end

-- string with its capitals centred vertically on cy
function G.textc(fs, str, x, cy, col, just)
    if fs == nil then return end
    G.text(fs, str, x, cy - fs.size / 2, col, just)
end

function G.text_w(fs, str)
    if fs == nil then return 0 end
    return (ink_width(fs, codepoints(str)))
end

-- str cut to w px with "..." (a long SSEC file name ran off the LCD); never
-- inside a UTF-8 character
-- Kept per face (the same few lines every frame); emptied when it grows
local fit_cache, fit_n = {}, 0
function G.text_fit(fs, str, w)
    if fs == nil then return str end
    local c = fit_cache[fs]
    if c == nil then
        c = {}
        fit_cache[fs] = c
    end
    local key = w .. "|" .. str
    local hit = c[key]
    if hit then return hit end
    local out = str
    if G.text_w(fs, str) > w then
        local n = #str
        while n > 0 do
            local nxt = string.byte(str, n + 1) or 0          -- a continuation byte: inside a character
            if (nxt < 0x80 or nxt >= 0xC0) and G.text_w(fs, string.sub(str, 1, n) .. "...") <= w then break end
            n = n - 1
        end
        out = string.sub(str, 1, n) .. "..."
    end
    fit_n = fit_n + 1
    if fit_n > 512 then
        fit_cache, fit_n = { [fs] = {} }, 1
        c = fit_cache[fs]
    end
    c[key] = out
    return out
end

-- one character with its ink centred on cx, y = baseline
function G.glyph_c(fs, ch, cx, y, col)
    if fs == nil then return end
    local gl = fs.g[string.byte(ch)]
    if gl then rf_glyph(fs, gl, cx - (gl[4] - gl[3]) / 2 - gl[3], y, col) end
end

-- LED readout like Plane Maker's gen_LED: `str` in slots of the face's digit
-- advance, every glyph centred in its slot, right edge at x_right, digits
-- centred vertically on cy. ' ' = blank slot; '.' takes the period's advance.
function G.led(fs, str, x_right, cy, col)
    if fs == nil then return end
    local slot = fs.g[48][2]
    local n = 0
    for k = 1, #str do
        local b = string.byte(str, k)
        n = n + ((b == 46) and fs.g[46][2] or slot)
    end
    local x = x_right - n
    local base = cy - fs.size / 2
    for k = 1, #str do
        local b = string.byte(str, k)
        local adv = (b == 46) and fs.g[46][2] or slot
        local gl = (b ~= 32) and fs.g[b]
        if gl then rf_glyph(fs, gl, x + (adv - (gl[4] - gl[3])) / 2 - gl[3], base, col) end
        x = x + adv
    end
end

-- rolling digit drum: digit d has its baseline at base0 + (d - v) * pitch,
-- so the drum moves down as v grows; v wraps every 10. Positions below
-- `floor` (nil = none) stay empty. Clip before calling.
local DIGIT = { [0] = "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" }
function G.roll(fs, cx, base0, v, pitch, col, floor)
    local k0 = math.floor(v)
    for k = k0 - 2, k0 + 2 do
        if floor == nil or k > floor then
            G.glyph_c(fs, DIGIT[k % 10], cx, base0 + (k - v) * pitch, col)
        end
    end
end

-----------------------------------------------------------------------------
-- Primitives. Point lists are flat {x1, y1, x2, y2, ...}.
-----------------------------------------------------------------------------

local vbuf = {}
local function verts(flat)
    local n = #flat / 2
    for i = 1, n do
        local v = vbuf[i]
        if v == nil then
            v = {}
            vbuf[i] = v
        end
        v.x, v.y = qmap(flat[2 * i - 1], flat[2 * i])
    end
    for i = n + 1, #vbuf do vbuf[i] = nil end
    return vbuf, n
end

function G.rect(x0, y0, x1, y1, col)
    if qt then
        local ax, ay = qmap(x0, y0)
        local bx, by = qmap(x1, y1)
        x0, y0, x1, y1 = math.min(ax, bx), math.min(ay, by), math.max(ax, bx), math.max(ay, by)
    end
    local v = vbuf
    for i = 5, #v do v[i] = nil end
    for i = 1, 4 do if v[i] == nil then v[i] = {} end end
    v[1].x, v[1].y = x0, y0
    v[2].x, v[2].y = x0, y1
    v[3].x, v[3].y = x1, y1
    v[4].x, v[4].y = x1, y0
    XPLMPolygon(col, v, 4)
end

-- outline drawn inside the rectangle, w px thick
function G.box(x0, y0, x1, y1, col, w)
    w = w or 1
    G.rect(x0, y0, x1, y0 + w, col)
    G.rect(x0, y1 - w, x1, y1, col)
    G.rect(x0, y0 + w, x0 + w, y1 - w, col)
    G.rect(x1 - w, y0 + w, x1, y1 - w, col)
end

-- convex polygon only
function G.poly(col, flat)
    local v, n = verts(flat)
    XPLMPolygon(col, v, n)
end

-- {x, y, color, x, y, color, ...}
local cbuf = {}
function G.polyc(list)
    local n = #list / 3
    for i = 1, n do
        local v = cbuf[i]
        if v == nil then
            v = {}
            cbuf[i] = v
        end
        v.x, v.y = qmap(list[3 * i - 2], list[3 * i - 1])
        v.color = list[3 * i]
    end
    for i = n + 1, #cbuf do cbuf[i] = nil end
    XPLMPolygonc(cbuf, n)
end

function G.line(x0, y0, x1, y1, col, w)
    local v, n = verts({ x0, y0, x1, y1 })
    XPLMLinesWithWidth(col, w or 1, v, n)
end

function G.loop(col, w, flat)
    local v, n = verts(flat)
    XPLMLineLoopWithWidth(col, w or 1, v, n)
end

-----------------------------------------------------------------------------
-- Transforms / clipping
-----------------------------------------------------------------------------

-- X-Plane applies the transform to scissor rectangles too; the translation is
-- tracked so nested clips can be intersected in device px.
-- tx, ty: the translation in force, device px; ts: the (uniform) scale
local tstack, tx, ty, ts = {}, 0, 0, 1
local rot_depth = 0
function G.push()
    tstack[#tstack + 1] = { tx, ty, rot_depth, ts }
    XPLMTransformPush()
end
function G.pop()
    local t = tstack[#tstack]
    if t then tx, ty, rot_depth, ts = t[1], t[2], t[3], t[4] tstack[#tstack] = nil end
    XPLMTransformPop()
end

function G.translate(dx, dy)
    dx, dy = qvec(dx, dy)
    tx, ty = tx + dx * ts, ty + dy * ts
    XPLMTransformTranslate(dx, dy)
end

-- uniform scale about the current origin (a page drawn smaller). Inside a
-- quarter turn that origin sits at qmap(0, 0) in X-Plane's frame, so the
-- scale is taken about that point (X-Plane scales about its own origin)
function G.scale(s)
    if qt then
        local ox, oy = qmap(0, 0)
        tx, ty = tx + ts * (1 - s) * ox, ty + ts * (1 - s) * oy
        ts = ts * s
        XPLMTransformTranslate(ox, oy)
        XPLMTransformScale(s, s)
        XPLMTransformTranslate(-ox, -oy)
        return
    end
    ts = ts * s
    XPLMTransformScale(s, s)
end

-- degrees, positive counter-clockwise (XPLM convention). No clip may be set
-- until the matching G.pop.
function G.rotate(cx, cy, deg)
    rot_depth = rot_depth + 1
    cx, cy = qmap(cx, cy)
    XPLMTransformRotate(cx, cy, deg)
end

local clip_stack = {}
function G.clip(x0, y0, x1, y1)
    if qt then
        local ax, ay = qmap(x0, y0)
        local bx, by = qmap(x1, y1)
        x0, y0, x1, y1 = math.min(ax, bx), math.min(ay, by), math.max(ax, bx), math.max(ay, by)
    end
    local l, b, r, t = x0 * ts + tx, y0 * ts + ty, x1 * ts + tx, y1 * ts + ty
    local top = clip_stack[#clip_stack]
    if top then
        l, b = math.max(l, top[1]), math.max(b, top[2])
        r, t = math.min(r, top[3]), math.min(t, top[4])
        if r < l then r = l end
        if t < b then t = b end
    end
    clip_stack[#clip_stack + 1] = { l, b, r, t }
    XPLMScissorPush()
    -- X-Plane puts the rectangle through the transform in force: hand it local px
    XPLMScissorSet(math.floor((l - tx) / ts), math.floor((t - ty) / ts),
        math.floor((r - tx) / ts), math.floor((b - ty) / ts))
end

function G.unclip()
    clip_stack[#clip_stack] = nil
    XPLMScissorPop()
end

-- stack depths now, for G.unwind_to
function G.mark()
    return { #tstack, #clip_stack }
end

-- pop scissors and transforms back to a G.mark()
function G.unwind_to(m)
    for i = #clip_stack, m[2] + 1, -1 do
        clip_stack[i] = nil
        XPLMScissorPop()
    end
    for i = #tstack, m[1] + 1, -1 do
        local t = tstack[i]
        tx, ty, rot_depth, ts = t[1], t[2], t[3], t[4]
        tstack[i] = nil
        XPLMTransformPop()
    end
end

-- after a draw error: pop what the failed frame left on the XPLM stacks
function G.unwind()
    for i = #clip_stack, 1, -1 do
        clip_stack[i] = nil
        XPLMScissorPop()
    end
    for i = #tstack, 1, -1 do
        tstack[i] = nil
        XPLMTransformPop()
    end
    tx, ty, rot_depth, ts = 0, 0, 0, 1
    qt = nil
end

function G.reset_frame()
    for i = #clip_stack, 1, -1 do clip_stack[i] = nil end
    for i = #tstack, 1, -1 do tstack[i] = nil end
    tx, ty, rot_depth, ts = 0, 0, 0, 1
    free_x, free_y = false, false
    qt = nil
end

-----------------------------------------------------------------------------
-- Images (texture atlas), drawn 1:1
-----------------------------------------------------------------------------

G.atlas = nil
G.img = {}      -- key -> atlas index
G.size = {}     -- key -> {w, h}

-- images: list of Textures/<key>.png; rfont: md302_font_data
function G.load_images(asset_rel_dir, images, rfont, log)
    G.atlas = XPLMCreateTextureAtlas()
    local function add(rel, cx, cy)
        local path = asset_rel_dir .. "/Textures/" .. rel .. ".png"
        local ok, idx
        if cx then
            ok, idx = pcall(XPLMTextureAtlasAddImageFileSet, G.atlas, path, cx, cy)
        else
            ok, idx = pcall(XPLMTextureAtlasAddImageFile, G.atlas, path)
        end
        if ok and idx ~= nil and idx >= 0 then return idx end
        log("image failed to load: " .. path)
        return nil
    end
    for _, key in ipairs(images) do
        local idx = add(key)
        if idx then G.img[key] = idx end
    end
    local rf = {}
    for face, sizes in pairs(rfont.faces) do
        rf[face] = {}
        rf_sizes[face] = {}
        for size, d in pairs(sizes) do
            local idx = add(d.file, d.cols, d.rows)
            if idx then
                rf[face][size] = { base = idx, cw = d.cw, ch = d.ch, ox = d.ox, oy = d.oy, g = d.g, size = size,
                    track = (TRACK[face] or 0) * size }
                table.insert(rf_sizes[face], size)
            end
        end
        table.sort(rf_sizes[face])
        if #rf_sizes[face] == 0 then rf[face], rf_sizes[face] = nil, nil end
    end
    if next(rf) then G.rf = rf end
    XPLMTextureAtlasBake(G.atlas)
    for key, idx in pairs(G.img) do
        G.size[key] = { XPLMTextureAtlasGetImageWidth(G.atlas, idx), XPLMTextureAtlasGetImageHeight(G.atlas, idx) }
    end
end

function G.destroy_images()
    if G.atlas then XPLMDestroyTextureAtlas(G.atlas) end
    G.atlas = nil
    G.img, G.size = {}, {}
    G.rf, rf_sizes = nil, {}
end

local WHITE
local function white()
    if WHITE == nil then WHITE = XPLMMakeColor(1, 1, 1, 1) end
    return WHITE
end

-- stretched into a box (x0,y0 bottom-left .. x1,y1 top-right)
function G.image(key, x0, y0, x1, y1, tint)
    local i = G.img[key]
    if i == nil then return false end
    if qt then
        local s = G.size[key]
        local x, y = qmap(x0, y0)
        XPLMTextureAtlasDrawScaled(G.atlas, i, tint or white(), x, y, 0, 0,
            (x1 - x0) / s[1], (y1 - y0) / s[2], -qt[1])
        return true
    end
    XPLMTextureAtlasDrawIn(G.atlas, i, tint or white(), x0, y1, x1, y0)
    return true
end

-- native size, centred on (cx, cy)
function G.pic(key, cx, cy, tint)
    local s = G.size[key]
    if s == nil then return false end
    local w, h = s[1] / 2, s[2] / 2
    return G.image(key, cx - w, cy - h, cx + w, cy + h, tint)
end

-- atlas cell idx at native size, rotated clockwise by deg about its point
-- (px, py) (px from the cell's bottom-left), which lands on (x, y). No
-- XPLM rotation, so it can be drawn under a scissor.
function G.atlas_turned(idx, x, y, px, py, deg_cw, tint)
    if qt then
        x, y = qmap(x, y)
        deg_cw = deg_cw - qt[1]
    end
    XPLMTextureAtlasDrawScaled(G.atlas, idx, tint or white(), x, y, px, py, 1, 1, deg_cw)
end

function G.pic_pivot(key, x, y, px, py, deg_cw, tint)
    local i = G.img[key]
    if i == nil then return false end
    G.atlas_turned(i, x, y, px, py, deg_cw, tint)
    return true
end

-- the glyph cells of str laid out as G.text does: fn(idx, l, b) for each,
-- (l, b) the cell's bottom-left; the cells are fs.cw x fs.ch
function G.text_cells(fs, str, x, y, just, fn)
    if fs == nil then return end
    local n = codepoints(str)
    local pen = x
    if just == JC or just == JR then
        local w, l0 = ink_width(fs, n)
        pen = (just == JC) and (x - w / 2 - l0) or (x - w - l0)
    end
    for k = 1, n do
        local gl = fs.g[cps[k]]
        if gl then
            local px, base = pen, y
            if not free_x then px = math.floor(px + 0.5) end
            if not free_y then base = math.floor(base + 0.5) end
            fn(fs.base + gl[1], px - fs.ox, base - fs.oy)
            pen = pen + adv(fs, cps[k], gl)
        end
    end
end

return G

-- Copyright (c) 2026 Tiezheng Eric Xu, erix@x-plane.com, Laminar Research - MIT License, see LICENSE
--
-- md302_bezel.lua: generated with the popup images (Textures/popup_*.png), do not edit.
-- The popup bezel (Textures/popup_bezel.png, an orthographic render of
-- 3D/MD302.obj), horizontal unit, 1x px, origin bottom-left, y up.
return {
    bezel_w = 1400, bezel_h = 608,
    -- the two LCDs, side by side, gap px apart
    screen_x = 129, screen_y = 118, gap = 142,
    -- their rounded corners' radius (the 3D screens' mesh), px
    lcd_r = 13.8,
    -- the knob: centre, radius; its sprites (popup_knob / _shadow.png), px square
    knob_x = 700.0, knob_y = 94.7, knob_r = 76.4, knob_sprite = 168, shadow_sprite = 200,
}

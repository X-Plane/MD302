--[[
*****************************************************************************************
* Program Script Name	:	MidContinent MD-302 LCD Look
*
* Author Name			:	Tiezheng Eric Xu, erix@x-plane.com, Laminar Research
*
*	The MD302 LCDs are cheap TN TFTs, 320 x 240 each (2.4" diagonal, the
*	manual's screen figures are 320 x 240 screen dumps). Drawn over what the
*	LCD shows, in the panel's own frame:
*		- black is never black: the backlight leaks through as a band, the way
*		  a TN panel looks a little off-axis (photos of the real unit: nearly
*		  black at the top, a neutral grey, a green-teal cast at the bottom)
*		- the edges glow whiter, patchy (backlight bleed)
*		- every pixel a little different (grain at the 320 x 240 pitch)
*	It goes into the screen image and is gone when the unit is off. X-Plane
*	scales that image by the brightness, so above the default brightness the
*	look is drawn k times as strong (k = default / now, below 1): it stays as
*	at the default when the pilot turns the brightness up or the curve sets
*	it higher, a stain does not light up with the picture;
*	below the default it dims with the picture (k = 1).
*	Dirt and scratches are not here: they are on the surface
*	(3D/MD302_ALB / NRM). Tuning: config.ini [Display] lcd_*.
*****************************************************************************************
*        Copyright (c) 2026 Tiezheng Eric Xu, erix@x-plane.com, Laminar Research - MIT License, see LICENSE
*****************************************************************************************
--]]

local LCD = {}

local G, cfg

	function LCD.init(gfx, config, log)
		G, cfg = gfx, config
	end

	--over one whole LCD, after everything on it; W x H = the LCD as it sits in
	--the panel (500 x 374), whatever way the picture on it is turned; k: the
	--strength against the brightness (md302_unit.lua screen_brightness)
	function LCD.MD302_LCD_Look(W, H, k)
		if cfg.lcd_effects == 0 then return end
		k = k or 1
		local function col(a) return G.rgba(1, 1, 1, math.min(1, a * k)) end
		if cfg.lcd_band > 0 then G.image("lcd_band", 0, 0, W, H, col(cfg.lcd_band)) end		--black is never black
		if cfg.lcd_grain > 0 then G.image("lcd_grain", 0, 0, W, H, col(cfg.lcd_grain)) end
		if cfg.lcd_bleed > 0 then G.image("lcd_bleed", 0, 0, W, H, col(cfg.lcd_bleed)) end
	end

return LCD

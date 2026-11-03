--[[
*****************************************************************************************
* Program Script Name	:	MidContinent MD-302 Failures and Messages
*
* Author Name			:	Tiezheng Eric Xu, erix@x-plane.com, Laminar Research
*
*	Manual 9017782 rev Q (2024), 5.1.4 TROUBLESHOOTING and 5.1.3 BATTERY:
*		- red X over the attitude / airspeed / altimeter that failed
*		- the message boxes (WARNING, ERROR, ...) in place of the attitude,
*		  OK, YES / NO or EXT / INT, the knob answers them
*		- battery capacity check at every power-up: less than 60 minutes
*		  of operation left, a warning
*	A failure comes from the instructor datarefs laminar/md302/fail_attitude,
*	fail_airspeed, fail_altimeter (1 = failed), from X-Plane's own failure of
*	the instrument read (Flight > Failures, D.xfail_*) or from leaving the
*	sensor range (Table 1.2: 300 deg/s, -1500..55000 ft, 500 kt), and
*	self-corrects.
*	laminar/md302/fail_message = 1..12 puts up one box (FAIL.MESSAGES), the
*	config.ini checks at load queue theirs for the first flight mode.
*	Geometry: the manual's 320 x 240 screen dumps x 1.5625 (500 x 374 LCD).
*****************************************************************************************
*        Copyright (c) 2026 Tiezheng Eric Xu, erix@x-plane.com, Laminar Research - MIT License, see LICENSE
*****************************************************************************************
--]]

local FAIL = {}

local U, G

	FAIL.ATT			= false		--red X on the attitude now
	FAIL.IAS			= false		--red X on the airspeed now
	FAIL.ALT			= false		--red X on the altimeter now
	FAIL.Msg			= nil		--the box up now: { n = message, cursor = 1 YES / 2 NO or OK }

	FAIL.Fail_ATT_Req	= 0			--the instructor datarefs, polled every frame
	FAIL.Fail_IAS_Req	= 0
	FAIL.Fail_ALT_Req	= 0

	local Msg_Queue			= {}
	local ATT_Exceed_Sec	= 0
	local ATT_RECOVER_SEC	= 3			--rates back in range this long: attitude back
	local RATE_LIMIT		= 300		--deg/s, pitch / roll rate (Table 1.2)
	local ALT_MIN			= -1500		--ft (Table 1.2)
	local ALT_MAX			= 55000
	local IAS_MAX			= 500		--kt

	--title bars of the screen dumps
	local TITLE_WARNING		= "A45000"
	local TITLE_ORANGE		= "C86000"		--rev Q figures 5.11 - 5.13, 5.16
	local TITLE_ERROR		= "BC0000"
	local TITLE_RED			= "F80000"

	--{ title, title colour, lines, buttons }, word for word from the rev Q
	--figures 5.5 - 5.17; a line { text } is centred (5.5 ACKNOWLEDGE?).
	--5.13 (settings different, flight mode): its figure is a copy of 5.11's,
	--so the rev B words stay, under SETTINGS DISPARITY as in 5.16
	FAIL.MESSAGES = {
		{ "WARNING", TITLE_WARNING, { "INTERNAL BATTERY MAY", "PROVIDE LESS THAN 60", "MINUTES OF OPERATION", "", { "ACKNOWLEDGE?" } }, "yesno" },
		{ "WARNING", TITLE_WARNING, { "EXTERNAL SETTINGS", "MODULE MISSING", "", "SEEK SERVICE IF", "WARNING CONTINUES" }, "ok" },
		{ "ERROR", TITLE_ERROR, { "SETTINGS MISSING", "OR INVALID", "", "SERVICE THIS UNIT", "IMMEDIATELY" }, "ok" },
		{ "ERROR", TITLE_ERROR, { "UNCALIBRATED UNIT", "CALIBRATION DATA", "NOT FOUND", "", "SEEK SERVICE", "IMMEDIATELY" }, "ok" },
		{ "ERROR", TITLE_ERROR, { "DETECTED STARTUP", "FAILURE", "", "SERVICE THIS UNIT", "IMMEDIATELY" }, "ok" },
		{ "WARNING", TITLE_ORANGE, { "INTERNAL SETTINGS", "INVALID. EXTERNAL", "SETTINGS USED", "", "SEEK SERVICE IF", "ERROR CONTINUES" }, "ok" },
		{ "WARNING", TITLE_ORANGE, { "EXTERNAL SETTINGS", "INVALID. INTERNAL", "SETTINGS USED", "", "SEEK SERVICE IF", "ERROR CONTINUES" }, "ok" },
		{ "WARNING", TITLE_ORANGE, { "SETTINGS DISPARITY", "THE EXTERNAL MODULE", "TAKES PRECEDENCE", "AND WILL OVERWRITE", "THE INTERNAL MODULE" }, "ok" },
		{ "WARNING", TITLE_ORANGE, { "SETTINGS DISPARITY", " EXT = USE EXTERNAL", " INT = USE INTERNAL", "", "CONFLICTING MODULE", "IS OVERWRITTEN" }, "extint" },
		{ "WARNING", TITLE_WARNING, { "FAILED TO SET CONFIG", "SETTINGS TO DEFAULT", "", "SEEK SERVICE IF", "ERROR CONTINUES" }, "ok" },
		{ "WARNING", TITLE_WARNING, { "SETTINGS COULD NOT", "BE FOUND. DEFAULT", "VALUES WILL BE USED", "", "SEEK SERVICE IF", "WARNING CONTINUES" }, "ok" },
		{ "WARNING", TITLE_RED, { "", " BATTERY", " OVER TEMPERATURE" }, "ok" },
	}
	FAIL.MSG_BATTERY			= 1		--5.1.3: less than 60 minutes of battery at power-up
	FAIL.MSG_SETTINGS_INVALID	= 3		--config.ini values out of range / unknown
	FAIL.MSG_EXTERNAL_INVALID	= 7		--config.ini damaged, put back from its .bak
	FAIL.MSG_NOT_FOUND			= 11	--no config.ini at all: defaults
	FAIL.MSG_BATTERY_TEMP		= 12	--rev Q 5.17: battery over temperature
	--rev Q figures 5.14 - 5.16 come up in Configuration Mode as well
	FAIL.CONFIG_MESSAGES		= { [9] = true, [10] = true, [11] = true }

	function FAIL.init(util, gfx)
		U, G = util, gfx
	end

-----------------------------------------------------------------------------
-- Failures
-----------------------------------------------------------------------------

	--D: the sim snapshot (MD302.lua), dt: sim time
	function FAIL.MD302_Fail_Update(D, dt)
		--attitude: the rate sensors went past their range; it comes back by itself
		if math.abs(D.p_dps) > RATE_LIMIT or math.abs(D.q_dps) > RATE_LIMIT then
			ATT_Exceed_Sec = ATT_RECOVER_SEC
		elseif ATT_Exceed_Sec > 0 then
			ATT_Exceed_Sec = math.max(0, ATT_Exceed_Sec - dt)
		end
		--D.xfail_*: X-Plane's own failure of the instrument read (MD302.lua)
		FAIL.ATT = FAIL.Fail_ATT_Req ~= 0 or D.xfail_att or ATT_Exceed_Sec > 0
		--pressure sensors out of their range: pressure altitude, not what the
		--baro setting makes of it (925 ft per inHg, as the trend uses)
		local press_alt = D.alt_ft - (D.baro_inhg - 29.92) * 925
		FAIL.ALT = FAIL.Fail_ALT_Req ~= 0 or D.xfail_alt or press_alt < ALT_MIN or press_alt > ALT_MAX
		FAIL.IAS = FAIL.Fail_IAS_Req ~= 0 or D.xfail_ias or D.ias_kt > IAS_MAX
	end

	--red X in a box (x0, y0)-(x1, y1), strokes w px wide
	function FAIL.MD302_Fail_Draw_X(box, w)
		local x0, y0, x1, y1 = box[1], box[2], box[3], box[4]
		local h = w / 2
		--each stroke a quad, w wide across its own direction
		local dx, dy = x1 - x0, y1 - y0
		local len = math.sqrt(dx * dx + dy * dy)
		local ox, oy = -dy / len * h, dx / len * h		--across (x0, y0) -> (x1, y1)
		local px, py = dy / len * h, dx / len * h		--across (x0, y1) -> (x1, y0)
		local col = G.C.red_x
		G.poly(col, { x0 + ox, y0 + oy, x0 - ox, y0 - oy, x1 - ox, y1 - oy, x1 + ox, y1 + oy })
		G.poly(col, { x0 + px, y1 + py, x0 - px, y1 - py, x1 - px, y0 - py, x1 + px, y0 + py })
	end

-----------------------------------------------------------------------------
-- Messages
-----------------------------------------------------------------------------

	function FAIL.MD302_Msg_Queue(n)
		if FAIL.MESSAGES[n] == nil then return end
		for _, q in ipairs(Msg_Queue) do
			if q == n then return end
		end
		if FAIL.Msg and FAIL.Msg.n == n then return end
		Msg_Queue[#Msg_Queue + 1] = n
	end

	--the next waiting box goes up (flight mode, or the last one answered);
	--only = a set of the messages that may come up now (Configuration Mode)
	function FAIL.MD302_Msg_Show_Next(only)
		if FAIL.Msg ~= nil then return end
		for k, n in ipairs(Msg_Queue) do
			if only == nil or only[n] then
				table.remove(Msg_Queue, k)
				FAIL.Msg = { n = n, cursor = 2 }	--NO is lit first (dumps), OK the only one
				U.log("message: " .. FAIL.MESSAGES[n][1] .. " / " .. FAIL.MESSAGES[n][3][1])
				return
			end
		end
	end

	--a box no longer true (BATTERY OVER TEMPERATURE after a new flight): out of
	--the queue, and down if it is up; the next one waits for flight mode
	function FAIL.MD302_Msg_Remove(n)
		for k = #Msg_Queue, 1, -1 do
			if Msg_Queue[k] == n then table.remove(Msg_Queue, k) end
		end
		if FAIL.Msg and FAIL.Msg.n == n then FAIL.Msg = nil end
	end

	--power off: the box up now is gone, what waits stays for the next power-up
	function FAIL.MD302_Msg_Drop()
		if FAIL.Msg then table.insert(Msg_Queue, 1, FAIL.Msg.n) end
		FAIL.Msg = nil
	end

	function FAIL.MD302_Msg_Turn(dir)
		local m = FAIL.Msg
		if m == nil or FAIL.MESSAGES[m.n][4] == "ok" then return end
		if dir > 0 then m.cursor = 2 else m.cursor = 1 end
	end

	function FAIL.MD302_Msg_Press(only)
		local m = FAIL.Msg
		if m == nil then return end
		local def = FAIL.MESSAGES[m.n]
		if def[4] == "yesno" then
			U.log("message answered: " .. ((m.cursor == 1) and "YES" or "NO"))
		elseif def[4] == "extint" then
			U.log("message answered: " .. ((m.cursor == 1) and "EXT" or "INT"))
		else
			U.log("message: OK")
		end
		FAIL.Msg = nil
		FAIL.MD302_Msg_Show_Next(only)
	end

	--x0 / x1: the lit box when it is not the usual 64 wide round the label
	local function MD302_Button(label, cx, lit, fs, x0, x1)
		if lit then
			x0, x1 = x0 or cx - 32, x1 or cx + 32
			G.rect(x0 + 2, 42, x1 - 2, 78, G.C.cursor)
			G.box(x0, 40, x1, 80, G.C.white, 2)
		end
		G.textc(fs, label, cx, 60, G.C.white, G.JC)
	end

	--a box on a black LCD, 500 x 374 (box 50..270 x 20..220 on the dumps):
	--title on its colour (hex), lines (centred when centre, or a line given as
	--{ text } centred, { text, x } at x), buttons "yesno" / "extint" / "ok",
	--cursor 1 YES/EXT / 2 NO/INT. Also the CALIBRATE boxes (md302_config.lua,
	--buttons "yesno_cal": figures 4.50, 4.51, 4.56 light YES 106..147 and NO
	--171..233 LCD px, the title at x 55 px)
	local Box_Cols = {}
	function FAIL.MD302_Box_Draw(title, colour, lines, buttons, cursor, centre)
		local fs = G.font("text", 20)
		Box_Cols[colour] = Box_Cols[colour] or G.hex(colour)
		G.rect(0, 0, 500, 374, G.C.black)
		G.box(77, 29, 423, 341, G.C.white, 2)
		G.rect(79, 299, 421, 339, Box_Cols[colour])
		G.rect(79, 298, 421, 299, G.C.white)
		G.text(fs, title, (buttons == "yesno_cal") and 86 or 94, 309, G.C.white)
		for k, line in ipairs(lines) do
			local c, lx = centre, nil
			if type(line) == "table" then line, c, lx = line[1], line[2] == nil, line[2] end
			if line ~= "" then
				--our face is wider than the unit's: a line that would reach the
				--frame (as the dumps' 9 px margin) is set a size or two smaller
				local lf, px = fs, 20
				while px > 17 and G.text_w(lf, line) > 319 do
					px = px - 1
					lf = G.font("text", px) or lf
				end
				line = G.text_fit(lf, line, 319)		--still too wide (a long SSEC file name): cut
				if c then
					G.text(lf, line, 250, 264 - 31 * (k - 1), G.C.white, G.JC)
				else
					G.text(lf, line, lx or 94, 264 - 31 * (k - 1), G.C.white)
				end
			end
		end
		if buttons == "yesno" then
			MD302_Button("YES", 195, cursor == 1, fs)
			MD302_Button("NO", 299, cursor == 2, fs)
		elseif buttons == "yesno_cal" then
			MD302_Button("YES", 194, cursor == 1, fs, 164, 231)
			MD302_Button("NO", 301, cursor == 2, fs, 266, 366)
		elseif buttons == "extint" then
			MD302_Button("EXT", 195, cursor == 1, fs)
			MD302_Button("INT", 299, cursor == 2, fs)
		else
			MD302_Button("OK", 250, true, fs)
		end
	end

	function FAIL.MD302_Msg_Draw()
		local m = FAIL.Msg
		if m == nil then return end
		local def = FAIL.MESSAGES[m.n]
		FAIL.MD302_Box_Draw(def[1], def[2], def[3], def[4], m.cursor)
	end

return FAIL

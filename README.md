# Mid-Continent MD302 Standby Attitude Module for X-Plane 12

A Mid-Continent MD302 SAM: attitude, airspeed, altitude, slip and heading on two LCDs, with the Options
Menu and its INFO pages, the internal battery, the installer's Configuration Mode, the failure and warning
screens of the real unit, and horizontal or vertical installation (taken from how the unit is placed in Plane
Maker). It is drawn live with the XPLM 4 Panel Graphics API through xLua 2.0 onto an `ATTR_cockpit_device`
screen, with the look of the unit's cheap 320 x 240 TFTs.

Behaviour follows Mid-Continent's *Installation Manual and Operating Instructions*, manual number 9017782
rev Q (March 2024, software 1.1.x): sections 4.2-4.4 (operation) and 4.5 (Configuration Mode), with the
service bulletins SB MD302-05 to -10; section 5.1.3 / 5.1.4 screens (battery check, troubleshooting) as in
rev B (2012). The screen art is the 2024 MD302 art, drawn 1:1;
what rev Q added is drawn from its screen dumps.

Version: 2026-11-03 (manual 9017782 rev Q; the S/W VERSION the unit shows is "X-PLANE 2.0.0").

## Manual

Start here: **[MD302_Manual.pdf](MD302_Manual.pdf)** (64 pages).

Just like the real unit, the MD302 is a standby instrument with two small screens and a single push/turn knob.

Inside:

- The pop-up, the knob and both displays
- Baro, units and brightness
- The Options Menu
- Battery operation, failures and messages
- Configuration Mode, installation and settings (for aircraft authors)
- Tutorial: losing aircraft power, and real failures
- Appendix A: where it differs from the real unit

The rest of this README is the short technical reference.

## Requirements

- X-Plane 12.4.4 with Panel Graphics (developed and tested on 12.4.4-b5, Windows only so far: Mac and Linux
  are untested).
- The xLua 2.0 runtime (tested with 2.0.0-b5; earlier builds that capped a script at 500 callbacks can run
  out after many popup openings, as each one makes a new window with nine callbacks) in the aircraft at `plugins/xlua/`: `win_x64/`, `mac_x64/`,
  `lin_x64/` each holding `xlua.xpl`, plus the stock `init.lua` and `include/`. xLua 2 also runs the
  aircraft's existing xLua 1 scripts.

## Install

1. Copy this folder to `<aircraft>/plugins/xlua/scripts/MD302/`. The folder must be named `MD302` (the main
   script is `MD302.lua`).
2. In Plane Maker, attach `../plugins/xlua/scripts/MD302/3D/MD302.obj` as a misc object (an ordinary object,
   **not** the cockpit object). The OBJ origin is the centre of the bezel's back face: put it on the panel
   surface. The front faces +Z (the pilot), so a vertical panel needs no rotation.
3. Set the unit's power source in `config.ini` `[Power]`: `power_bus` = the
   `sim/cockpit2/electrical/bus_volts` index that feeds it.
4. Check the air data source, `config.ini` `[Sources] air_data`: the default `stby` is X-Plane's standby
   pitot / static system, as the real unit's own ports. An aircraft plugin that takes over the indicated
   airspeed (`sim/operation/override/override_ias`) may write the pilot's alone, as `c172_IAS.lua` of the
   Cessna 172 that comes with X-Plane does: the standby airspeed then stays at 0, and the unit reads
   X-Plane's calibrated airspeed of the same side instead. If the standby airspeed still reads 0 in flight,
   set `pilot` or `copilot`.
5. Vertical installation: turn the object a quarter in Plane Maker (roll -90: knob on the right, +90: knob
   on the left). The unit reads that from the `.acf` and turns its pictures to match; a small tilt or roll of
   the object is what PANEL TILT / PANEL ROLL take out (`auto` in `config.ini`).
6. Heading: as shipped (`config.ini` `[Sources] heading = pretend`) the heading window at the bottom of the
   attitude display shows X-Plane's heading straight away, whenever the unit is on. That is a convenience for
   the simulator, not a real MD302 setting. For the real unit's behaviour set it to `none` (no heading source
   wired: "---"), `md32` (an MD32 magnetometer: X-Plane's magnetic heading) or `arinc` (the aircraft's AHRS
   heading, lost with the aircraft's power); see Heading below.

The script finds the slot in the `.acf` by the OBJ's file name, so the clicks and the orientation work wherever
it is placed.

## Using it

| Control | Does |
|---|---|
| Turn the knob (16 detents per turn) | sets the baro (0.01 inHg / 1 hPa); in a menu: moves the cursor |
| Push | brightness bar (turn to change); in a menu: select |
| Push and hold 2 s | Options Menu (in place of the attitude display) |
| Push and hold the knob 3.5 s on the start-up screen (or hold it while aircraft power comes on), on the ground on aircraft power | Configuration Mode (see below) |

- **Popup**: a click on either screen of the 3D unit (or `laminar/md302/popup_toggle`) opens a 2D window
  showing the whole front of the unit (a render of its 3D model) with both LCDs and the knob. The knob works
  with the mouse as the 3D one does: click its left or right half to turn it a detent (or use the wheel over
  it), click its middle to push it (hold the button 2 s for the Options Menu). The window's controls are
  X-Plane's own, as on any instrument popup: the red dot at the top left closes it, the icon at the top right
  pops it out into a separate window, a drag anywhere off the knob moves it and its edges resize it.
- **Options Menu** (rev Q 4.3.2): ALT UNITS, BARO UNITS, SYMBOL (DELTA, SPLIT DELTA, TRADITIONAL), ATT MASK,
  ALT TREND, INFO >, EXIT MENU, POWER OFF. A value picked there is saved at once in `config.ini [Options]` and
  is back after a reload. INFO > holds REVIEW CONFIG (every installer setting), SOFTWARE INFO and BATTERY INFO
  (run time left, temperature, charge, capacity, type). The menu closes after 10 s without activity.
- **Battery** (4.4): with aircraft power lost in flight the unit runs on its battery (green icon; black with a
  red X below 20 %). `config.ini battery_type` = 1 (lithium-ion, the default), 2 (nickel metal hydride) or
  none (the versions without a battery: off as soon as aircraft power goes, no battery icon or check, BATTERY
  INFO and BATTERY STORAGE MODE grey). POWER OFF in the Options Menu turns it off whenever it is on the battery, in the air too
  (SB MD302-09; grey on aircraft power). With no airspeed (below `ground_ias_kt`, taxiing too: rev Q looks at
  the airspeed only) and CONFIGURE AUTO-OFF on, "POWER DOWN IN 60 SEC" shows over the attitude: ON keeps it
  on the battery, OFF (lit first) turns it off, else it turns off at 0; airspeed again stops the countdown.
  With AUTO-OFF off it stays on the battery until POWER OFF.
- **Brightness** (4.3.3): push the knob: a green bar with a sun along the left edge; turn to change. As rev Q
  says, it cannot go below the lowest point of the DIMMING CURVE. At night the photocell has turned the
  backlight part of the way down (in a test at 21:00 local time, about 42 % with the default curve), so
  fewer steps are left to dim, but the bar can still dim it further or turn it up; only in full darkness is
  it at the lowest point already. In daylight it can dim a long way. The screen follows X-Plane's ambient
  light; the manual's default curve (10 .. 100 %) gives the look tuned for X-Plane.
- **Airspeed** below AIRSPEED MINIMUM (20 / 30 / 40 kt, default 30) reads 0, as on the real unit.
- **Configuration Mode** (4.5): hold the knob while aircraft power is applied (4.1). After about 6 s
  "CONTINUE HOLDING TO ENTER CONFIG MODE" appears, after about 9 s the introduction screen; let go for the
  CONFIGURE MENU. The real unit wants the knob held before the power comes, which takes two hands; one
  mouse cannot, so a push while the start-up screen shows (about 5 s, `preflight_s`; on the ground, on
  aircraft power) counts too: "CONTINUE
  HOLDING" after half a second, and after 3.5 s held the CONFIGURE MENU comes by itself (nothing to let go
  of; let go earlier and it starts as usual; aircraft power lost or the aircraft moving while it is held: no
  Configuration Mode either, it starts as usual). A push held through the start-up screen otherwise (on the
  battery, in motion) is used up: no Options Menu as flight mode starts. Or use the command
  `laminar/md302/config_mode` (on the ground, unit on aircraft power). The
  menu is on the air-data LCD; the attitude LCD shows a live preview of the setting being changed (the
  attitude, or the airspeed tape for the airspeed settings). ROLL DISPLAY, AIRSPEED UNITS, AIRSPEED MINIMUM,
  HORIZON DISPLAY, CONFIGURE HEADING and DIMMING CONTROL preview the choice under the cursor before it is
  pushed (range markings from the aircraft follow the airspeed units there too); DISPLAY ORIENTATION and the
  settings the picture does not show (BARO SYNC, AUTO-OFF, ARINC) change nothing until pushed. Once in
  Configuration Mode the unit stays in it on the battery if aircraft power goes (rev Q 4.5.10: it runs
  there on the battery), with no power-down countdown. CONFIGURE AIRCRAFT (panel tilt, panel roll, Mmo,
  range markings, VNE table), CONFIGURE ARINC (pass-through, transmit speed), CONFIGURE BARO SYNC, CONFIGURE
  DIMMING (control, curve), CONFIGURE DISPLAY (roll display, airspeed units, airspeed minimum, orientation,
  horizon flat / shaded), CONFIGURE HEADING, CONFIGURE AUTO-OFF, CALIBRATE, UPDATE SOFTWARE, CLEAR SSEC TABLE,
  BATTERY STORAGE MODE. Nothing is saved until ACCEPT
  CHANGES, which writes the changed lines into `config.ini` and restarts the unit; CANCEL CHANGES restarts it
  without saving. RANGE MARKINGS is the table of rev Q figure 4.33 (TYPE FULL / HALF / RAD / OFF, CLR WHT /
  GRN / YEL / RED / BLU / BAR, V1, V2 with 999 = MAX). External dimming (EXT 5V / 14V / 28V) follows the
  aircraft's panel-light knob (`dimming_rheostat`); at or below the curve's PT 7 threshold the photocell takes
  over (rev Q step 6). DISPLAY ORIENTATION follows how the unit sits in Plane Maker: the choices that do not
  fit are grey and cannot be picked, and the page says why. The boxes of rev Q figures 5.14 - 5.16 come up in
  Configuration Mode too (`fail_message` 9 / 10 / 11).
- **Heading** (4.3.1.2, CONFIGURE HEADING): DISPLAY ON (the default) puts a heading window at the bottom of the
  attitude display and the slip indicator above and to the left of it; DISPLAY OFF: the slip indicator at the
  bottom centre. The heading comes from `[Sources] heading`: pretend (the default) = X-Plane's magnetic
  heading with the ARINC arrows, whenever the unit is on and never lost: a plug-and-use convenience, not a
  real MD302 configuration; none = "---", as a real unit with no source wired; md32 = an MD32
  magnetometer (X-Plane's magnetic heading, arrows pointing out); arinc = ARINC 429 heading (the pilot's AHRS
  heading in X-Plane, arrows pointing in); with any source the heading tape runs along the bottom. A lost
  source (4.3.1.2): the heading runs on the unit's gyro for 10 s, without the arrows, then shows "---", and
  comes back with the source. The ARINC heading counts as lost while the aircraft has no power (`power_bus`
  below `power_min_volts`) or X-Plane's AHRS is failed (Flight > Failures, AHRS): X-Plane keeps its AHRS
  heading going without power, so the unit cannot see the loss there. The MD32 runs on the MD302's own power
  and is never lost.
- **Vertical installation** (4.5.6.3): the unit turned a quarter in Plane Maker turns both pictures to the
  upright LCDs, the attitude on the upper one; HORIZONTAL (SWAP) puts the attitude on the right LCD of a
  horizontal unit. Attitude and air data are laid out for the upright LCD as rev Q figure 2.1 and photos of
  vertical units: the airspeed and altitude windows side by side at mid height, smaller than on a horizontal
  unit, BARO at the top, the slip box centred over the heading window, the start-up screen stacked (logo, SAM,
  MD302). Menus, dialogs and the Configuration Mode pages are the horizontal pages shrunk to the LCD's width.
  The popup shows the unit turned the same way (the knob at the side), sized to fit the screen.
- **Pitch ladder**: masked as on the unit (a circle under the roll scale, cutting the numbers pixel by pixel;
  straight down below; clear of the bottom 40 px), and it goes on past 90 deg (80, 70 .. over the top) with
  four red chevrons each side. Its lines and the horizon line are anti-aliased, as on the manual's screen
  dumps.
- **Failures** (5.1.4): a red X over the attitude, the airspeed or the altimeter that failed, the rest keeps
  working. They come from the datarefs below or from leaving the sensor range (pitch / roll rate above
  300 deg/s: attitude, back 3 s after the rates are in range again; below -1,500 or above 55,000 ft:
  altimeter; above 500 kt: airspeed). X-Plane's own failures (Flight > Failures) of the instruments the
  unit reads give the same red X: with `air_data = pilot` or `copilot` that side's airspeed indicator and
  altimeter, with `attitude = ahrs` / `electric` / `vacuum` the AHRS, the electric gyro or the pilot's
  artificial horizon. The standby air data (`stby`, the default) and the unit's own AHRS (`own`) have no
  instrument failure in X-Plane: use the datarefs below. A blocked pitot or static port is not a failure
  the unit can see; it shows what X-Plane then reports, as the real unit would.
- **Warnings and errors** (5.1.3 / 5.1.4): the manual's message boxes, in place of the attitude, answered with
  the knob (push = OK; YES / NO, EXT / INT: turn, push), in rev Q's words and colours. At every power-up a
  battery with less than 60 minutes left (`battery_minutes`) gives "INTERNAL BATTERY MAY PROVIDE LESS THAN 60
  MINUTES OF OPERATION". `config.ini` itself is checked at load: missing = "SETTINGS COULD NOT BE FOUND"
  (the next save writes a new `config.ini` with only the values it saved, no comments; to start again from
  the factory settings take a fresh `config.ini` from this repository and delete `config.ini.bak`: an existing
  `.bak` is put back instead), damaged and put back from its `.bak` =
  "EXTERNAL SETTINGS INVALID", values out of range (the value is clamped to the nearest allowed one, see Log.txt) = "SETTINGS MISSING OR INVALID" (shown at the first flight
  mode). Any box can be called up with `laminar/md302/fail_message`. BATTERY OVER TEMPERATURE (rev Q figure
  5.17, `fail_message` 12): on the battery the unit turns off at once; on aircraft power OK, then it runs on
  with the black battery icon with a red X and turns off if aircraft power goes (until the aircraft is
  reloaded).

## config.ini

`config.ini` is the unit's memory and is documented line by line. The unit rewrites single lines in it and
keeps everything else (comments included):

| Section | Written by |
|---|---|
| `[Options]` | the Options Menu |
| `[Configure Display]`, `[Configure Heading]`, `[Configure Auto-Off]`, `[Configure Baro Sync]`, `[Configure ARINC]`, `[Configure Dimming]`, `[Configure Aircraft]` (all but `dimming_rheostat`) | Configuration Mode, on ACCEPT CHANGES |
| `[State]` | the unit: battery charge and run time |
| `[Power]`, `[Sources]`, `[Display]` (including the LCD look), `[Clicks]`, `dimming_rheostat` | nobody: the aircraft author's settings (ACCEPT CHANGES writes `baro_sync_source` back, unchanged, only when CONFIGURE BARO SYNC was changed) |

A save goes to `config.ini.tmp` first and is swapped in; `config.ini.bak` keeps the version before the last
save. If X-Plane stops half-way, or config.ini is found empty or damaged, the next load puts it back from the
`.tmp` or `.bak` (a damaged file is kept as `config.ini.broken`).

`[Sources]`: by default the air data comes from X-Plane's standby pitot / static system (`*_stby`, including
its own baro setting and standby pitot / static failures) and the attitude from the aircraft's attitude (the
MD302's own AHRS). The ARINC 429 inputs are X-Plane's: CONFIGURE BARO SYNC follows `baro_sync_source`'s
altimeter setting (pilot / copilot) whenever it changes (held to 28.00 - 31.00 inHg; in step: an arrow each
side of BARO, rev Q figure 4.8; a change lights the window green), `heading` = pretend / md32 / arinc as
above. An older `config.ini` with `baro_sync = pilot` / `copilot` is read as BARO SYNC on with that source.

## The screen

The two LCDs are 2.4" (diagonal) TFTs of 320 x 240 pixels: the manual's screen figures are 320 x 240 screen
dumps, and 2.4" at 4:3 is 48.8 x 36.6 mm, a 0.153 mm pixel pitch (the model's LCDs are 50 x 37.4 mm).
`md302_lcd.lua` draws their look into the picture, so it is gone when the unit is off (`config.ini
[Display]`). Turning the brightness up makes the picture brighter, not the look (it stays as at the default
brightness); turned down, the look dims with the picture:

- black is never black: the backlight leaks through as a band, the way a TN panel looks a little off-axis:
  nearly black at the top, a neutral grey, a green-teal cast at the bottom (`lcd_band`,
  `Textures/lcd_band.png`, from photos of the real unit);
- the edges glow whiter, patchy, strongest along the long edges and in the corners (`lcd_bleed`,
  `Textures/lcd_bleed.png`);
- every pixel is a little different, at the 320 x 240 pitch (`lcd_grain`, `Textures/lcd_grain.png`).

Colours: the black-bezel unit (the one the model is) draws a flat azure sky and a flat crimson ground,
a slightly cool white, also for the window outlines and the slip ball (rev Q and the real unit; rev B and the
2024 art have a yellow ball), taken from photos of the real unit, each calibrated on
the screen's own white (the photos alone all disagree; the manual's figures show the older grey-bezel unit's
palette).

The picture is 500 x 374 framebuffer pixels per LCD (1.56 per LCD pixel), so a sharp pixel grid cannot be drawn
without moire; the grain stands for it. The defaults are set for the 3D cockpit: X-Plane boosts panel light in
daylight (about 12x), so the band's small values read there like photos of the unit; the 2D popup is not
boosted and looks nearly black. The surface (the screen islands of `3D/MD302_ALB.png` / `MD302_NRM.png`) is
glass, as glossy as the screen of X-Plane's Garmin G5, with faint smudges on it, kept light so the
screen's own character reads before the smudges.

## Commands and datarefs

Commands: `laminar/md302/press_knob` (hold), `knob_left`, `knob_right`, `config_mode`, `popup_toggle` (2D
window: the unit's front with its knob), `popup_show` (opens it; a click on either 3D screen runs it). The popup window exists
only while it is open: closing it (the toggle, or the window's own close button, popped out or not) destroys
it, and it opens again where it was last in this X-Plane session (the position is not saved). From the 2024 version: `goes_into_setting` (the Options Menu at once),
`power_down_off` (the power-down box answered ON: stay on the battery).

Datarefs (writable, for an instructor or a scenario): `laminar/md302/fail_attitude`, `fail_airspeed`,
`fail_altimeter` (1 = failed, 0 = working), `fail_message` (1-12 puts up a message box, then reads 0 again:
1 battery test, 2 settings module missing, 3 settings missing or invalid, 4 uncalibrated unit, 5 startup
failure, 6 internal settings invalid, 7 external settings invalid, 8 / 9 settings disparity, 10 failed to set
defaults, 11 settings not found, 12 battery over temperature).

Datarefs (read only): `laminar/md302/knob_val_for_setting` (knob animation, 1 = one turn),
`knob_push_anim` (the knob's push animation, 0 out .. 1 in), `knob_pressed`, `unit_on`, `ops_mode_now` (-1 off, 0 pre-flight, 1 flight, 3 menu / configuration),
`config_mode`, `on_battery`, `battery_pct`, `menu_open`, `power_down_timer_remain`, `alt_trend_fpm`,
`popup_visible`, `xlua_heartbeat`, `valid` (the unit's valid output, pin 2: 1 in flight mode with no red X,
0 otherwise; for a warning light). From the 2024 version, so panels made for it keep working:
`options_alt_units_now` (0 feet, 1 meters), `options_baro_units_now` (0 hPa, 1 inHg), `options_symbol_now`
(0 delta, 1 traditional, 2 split delta), `options_att_mask_now`, `options_alt_trend_now` (1 = on), `on_ground`,
`pressure_display_val` (the BARO value shown, hPa or inHg).

Dataref for diagnostics (read only, a string): `laminar/md302/cursor_report`, one line of `key=value` built
when it is read, for a cursor-reporter script. It names the last cursor callback X-Plane called on the unit
(`src=none` and `t=-1` before the first one): `src` = `3d_screen`, `3d_knob_ring`, `3d_knob_cap`, `3d_none` (a
click window, nothing of the unit under the mouse), `popup_bezel` or `popup_screen`; `part` = `push`, `left`,
`right` or `-`; `cur` = the XPLMCursorStatus it returned (0 = X-Plane's own cursor, 8 / 9 = turn left / right,
20 = hand); `x`, `y` = where (popup pixels on the popup, global boxels on the 3D click windows); `t` =
XPLMGetElapsedTime of that call; `n` counts the calls. Then where the popup is: `popup` = `open`, `closed` or
`out` (popped out), `geom` = its window in global boxels (left, top, right, bottom; `-` when not open), and
`bezel`, `screen` (x, y, w, h) and `knob` (x, y, radius) in popup pixels. Not there when X-Plane offers no
byte-data datarefs.

## Clicks

X-Plane only clicks manipulators in the aircraft's one cockpit object. `MD302.obj` is an ordinary object, so
`md302_pick.lua` does the picking itself in the 3D cockpit view: small invisible windows over the knob, a ray
test against the OBJ's draw-disabled click regions. The mouse wheel turns the knob. `[Clicks] pick_mode`:
0 = off, 1 = auto (off when X-Plane can already click the unit), 2 = always. Not in VR and not in outside
views. Each MD302 in the aircraft gets its own windows. The knob's window is no wider than half the view, so
with the head right up to the knob it does not take the clicks around it; the screens' window may fill the
view (a click on a screen only opens the popup; a click elsewhere inside its box goes to it too unless
`pick_pass_misses = 1`). When X-Plane's screen and its 3D window are not the same
shape (more than 2 % apart: some multi-monitor, windowed or high-DPI layouts), where the mouse ray would
miss, the 3D clicks are off and Log.txt says so once; the popup and the commands still work.

## Limitations

What this version does not do, or does only in part:

- CALIBRATE (4.5.9) shows the airspeed / altitude boxes ("APPLY PITOT PRESSURE OF 120 KNOTS", YES / NO) but
  calibrates and saves nothing. CALIBRATE HEADING is on the menu but grey (not modelled), as the heading is
  X-Plane's own magnetic heading and a calibration could only make the unit disagree with the simulator.
- PASS-THROUGH and TRANSMIT SPEED are stored and shown only: the unit puts out no ARINC 429, and X-Plane reads
  none.
- SSEC (4.5.11): `ssec_file` only names a table for the pre-flight screen and REVIEW CONFIG ("SSEC: FILE
  ..."), CLEAR SSEC TABLE (grey without one) empties it, and no correction is applied.
- UPDATE SOFTWARE (4.5.1): there is no USB port, so it always ends as on a unit with no USB drive in, with
  "FAILED UPDATE" (OK: back to the CONFIGURE MENU); grey on the battery.
- The attitude is X-Plane's: the real unit's AHRS (its drift, its erection after a hard manoeuvre, the airspeed
  aiding) and the MD32's errors are not modelled. With `attitude = own` (the default) and PANEL TILT / PANEL
  ROLL on `auto` the horizon is exactly the aircraft's; `ahrs` / `electric` / `vacuum` show that X-Plane
  instrument, its errors and failures included, and a PANEL TILT / ROLL that does not match how the unit
  sits tilts the horizon by the difference.
- The battery has no temperature, heating or ageing: BATTERY INFO shows the outside air temperature held to
  5 .. 40 C and a capacity that never falls, and BATTERY OVER TEMPERATURE comes only from `fail_message` 12.
- Low temperature (rev Q 2.2: below -30 C the screen takes up to 5 minutes to be fully readable, and the
  altitude is less accurate) is not modelled.
- Heading: the MD32 never fails; the ARINC heading is lost only with the aircraft's power or X-Plane's AHRS
  failure (see Heading). The shipped `heading = pretend` has no real counterpart: it never loses its heading,
  so a real unit's "---" (no source wired) or loss of source is seen only with `none` / `arinc`.
- The power-up self-test never fails on its own: apart from the `config.ini` and battery checks (Warnings and
  errors), the boxes of rev Q 5.1.4 come up only through `fail_message`.
- Each LCD is a 500 x 374 picture, not 320 x 240 pixels: the pixel grid and the TFT's off-axis glow are
  approximated (The screen), not reproduced.
- The knob is clicked by the script's own ray test, not by X-Plane's manipulators (Clicks), and only on the
  unit attached as Install says: it works in the 3D cockpit view only, not in VR and not from outside views,
  and in a window or on a second screen it can be less dependable than a native click. The knob commands
  (`press_knob`, `knob_left`, `knob_right`) can be bound to joystick or VR controller buttons instead.
- BATTERY STORAGE MODE (SB MD302-05): the battery is off until aircraft power is applied to the unit again;
  its confirmation box is ours (the manual has no figure of it), and so are the CLEAR SSEC TABLE box and the
  brightness bar's exact sizes away from figure 4.24.
- The rev Q manual has no screen dump of the RANGE MARKINGS page (figure 4.33 is a drawing): its layout and
  the radial line's thickness are taken from that drawing.
- Where the ladder mask goes in FIXED POINTER (turning with the scale) and the vertical installation's ladder
  bottom are ours; the manual's dumps are all FIXED SCALE, horizontal.
- Tested on Windows only: Mac and Linux are untested (Requirements).

## Files

```
MD302.lua             master script: lifecycle, config.ini, datarefs, commands, device, flight loop
md302_unit.lua        behaviour: power, battery, knob, Options Menu, brightness, baro
md302_config.lua      Configuration Mode
md302_fail.lua        failure X, message boxes, battery check
md302_lcd.lua         the LCD look
md302_display.lua     the two LCDs
md302_gfx.lua         drawing layer and raster fonts
md302_util.lua        config.ini, dataref and command helpers
md302_pick.lua        3D knob clicks
md302_font_data.lua   fontbook metrics (generated)
md302_bezel.lua       the popup's bezel: LCD and knob positions (generated with Textures/popup_bezel.png)
config.ini            the unit's memory (see above)
LICENSE               MIT
3D/                   MD302.obj (unit, screen device laminar_md302, click regions) and its textures
Textures/             sprites cut from the 2024 art; lcd_band / lcd_bleed / lcd_grain (the LCD look); aa_* (anti-aliased
                      lines); popup_bezel = the popup's face (a render of 3D/MD302.obj); Font/ = the fontbook sheets
docs (folder)         perf: measurements taken in X-Plane (the popup window opened and closed 300 times)
```

## Credits

MD302 for X-Plane by Tiezheng Eric Xu for Laminar Research. The text is drawn from PNG glyph atlases
(`Textures/Font/`, no font files are shipped) cut from the 2024 MD302 art; characters that art did not contain
(Z J Q - _ : , + < > ° = % ? #) were drawn to match. The lettering is set about one LCD pixel a letter tighter than
that art, as the unit's. Behaviour per Mid-Continent's manual 9017782 rev Q (and rev B); the manuals are not
included.

Mid-Continent and MD302 are trademarks of Mid-Continent Instruments and Avionics. This project is not affiliated
with or endorsed by Mid-Continent.

## License

Copyright (c) 2026 Tiezheng Eric Xu, erix@x-plane.com, Laminar Research. MIT; see [LICENSE](LICENSE).

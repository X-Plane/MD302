# MD302 popup: destroyed on close, measured in X-Plane

The MD302 popup window is created when it opens and destroyed when it closes (not hidden). These measurements check
that opening and closing it many times costs nothing.

**Setup:** X-Plane 12.4.4 (Windows 11), xLua 2.0.0a1, a Cessna 172 on the ground at KLAF runway 10, sim
running. The popup was opened and closed with the `laminar/md302/popup_toggle` command through X-Plane's Web API,
0.35 s apart. Recorded 2026-10-30.

## Opening and closing it 300 times

| | before | before, 60 s later | after 300 cycles | after, 60 s later |
|---|---|---|---|---|
| frame time, popup closed (mean / median, ms) | 10.51 / 10.43 | 10.29 / 9.98 | 10.91 / 10.91 | 10.12 / 9.84 |
| frame time, popup open (mean / median, ms) | 11.08 / 10.82 | 10.32 / 10.13 | 10.81 / 10.66 | 10.59 / 10.44 |
| X-Plane private memory (MB) | 11768.8 | 11761.6 | 11847.7 | 11894.6 |
| X-Plane working set (MB) | 7916.0 | 7917.5 | 7991.4 | 8038.1 |

- Frame time: the change is within the spread between the two "before" readings.
- Log.txt: 300 "window destroyed" lines (one per close), no errors. xLua's "callbacks are now persisted" message never appeared.
- Memory: it rose during the cycles, but it also kept rising afterwards with no popup activity, so a control run followed.

## Control: is the memory rise the popup?

Private memory was sampled every 10 s across three equal spans of 112 s.

| span | private memory change |
|---|---|
| idle, no popup activity | +30.2 MB / min |
| 150 open / close cycles | +16.5 MB / min |
| idle again | -0.9 MB / min |

X-Plane's memory grew on its own while idle and then levelled off. The popup cycles added nothing measurable.

## Also checked

- `popup_show` and `popup_toggle` open and close it. A second `popup_show` leaves the one window open.
- With the sim paused, and in an outside view, the popup stays open.
- Brightness bar: with the popup open, the 3D unit and the popup show the same level by day (about 86 %) and at night
  (about 30 %), with no flicker across three screenshots (`br_compare.png`, popup left / 3D unit right in each pair).

## Not covered

- Closing the window with its own close button, or after popping it out to an OS window: needs a real mouse.
- Graphics memory: only a whole-card reading (nvidia-smi) was taken, which moved by 250 MB either way.
- Mac and Linux.

## Files

`stress.json`, `stress.log`: the 300-cycle run. `memtrend.json`, `memtrend.log`: the control run, every sample.
`basic.json`: the open / close checks. `bright.json`, `br_compare.png`: the brightness bar check.

# VenGo

One-click runs to the Venture Seal for any of today's CatsEyeXI ventures, with the
full ventures list, in YunaUI's style. It never fights.

## Install

1. Unzip so you have `VanaCore\addons\vanacore\vengo\vengo.lua`
2. In game: `/addon load vengo vanacore` (add that line to your startup script to load it every time)
3. `/vengo` opens or closes the window

## Use

- **GO** warps you toward a venture's VNM. It needs the **Uberwarp** plugin
  (installed separately, with its `resources` folder in the VanaCore folder).
- Stand at a Home Point, Survival Guide or Unity NPC and press GO: VenGo picks the
  warp of that kind that lands closest to the VNM's grid square and sends `/uw` for you.
- Pressed anywhere else, GO waits 3 minutes and warps the moment you walk up to one.
- If the closest one isn't unlocked, press **NOT UNLOCKED? TRY NEXT CLOSEST**.
- Hover a GO button to see every warp that goes to that zone.
- The big GO picks the venture at 100% (or the highest %).
- VenGo never moves your character.

## The trail

In the venture's zone (or after GO), a glowing path runs along the ground from your
feet to the VNM's grid square, with chevrons crawling toward it and a flag at the end
showing the name and distance. It uses the game's own camera, so it sits on the ground
as you turn. It's a straight line: it shows the way, not the route round walls, and ends
5 yalms from the square's middle. Settings: on/off, glow, and the chevrons' colour.

## Live data

The server sends the venture board (packet 0x1A3) on its own. VenGo reads it as it
arrives, so the zones and percentages stay current: no editing needed. Pick ACE or CW
zones with the pills above the list. A venture reaching 100% raises the VNM alert.

Drops, grid squares and notes come from the community VNM list kept by the
[ventures](https://github.com/commandobill/ventures) addon (Commandobill, Seekey, Phatty).
VenGo downloads it on load. If that fails, copy `data\vnms.lua` from that addon into
the vengo folder.

When you log in, VenGo types `!ventures` once so the game sends the current board.

VenGo also updates from **catseyexi.com/events** after every daily reset, and at least
once a week (its data feed, `https://catseyexi.com/api/ventures`), in the background
with Windows' own `curl.exe`.
That adds the HVNM's level, HP, next HVNM and loot, the mobs in each venture area,
HELM, Fishing and Dynamis ventures, and the exact reset time. Turn it off in Settings.

`ventures.lua` is only a fallback until the game or the website sends the board.

## Special thanks

- **Vekkien** for the VanaCore project
- **Yunas** for YunaUI: VenGo's look and its VanaCore start-up come from it
- **Commandobill, Seekey and Phatty** for the ventures addon: the venture board and the VNM list
- **Thorny** for Uberwarp, which does the warps behind GO
- **GUST** for the TeX Gyre Adventor font

## Credits and licence

VenGo is free software under the GNU GPL v3 (`LICENSE`).
`native.lua` and the window's look come from YunaUI by Yunas (GPL v3).
The font is TeX Gyre Adventor by GUST (`fonts/GUST-texgyreadventor.txt`).

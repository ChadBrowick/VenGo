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

## Live data

The server sends the venture board (packet 0x1A3) on its own. VenGo reads it as it
arrives, so the zones and percentages stay current: no editing needed. Pick ACE or CW
zones with the pills above the list. A venture reaching 100% raises the VNM alert.

Drops, grid squares and notes come from the community VNM list kept by the
[ventures](https://github.com/commandobill/ventures) addon (Commandobill, Seekey, Phatty).
VenGo downloads it on load. If that fails, copy `data\vnms.lua` from that addon into
the vengo folder.

`ventures.lua` is still used for HELM, Fishing and Dynamis, and as a fallback until the
first board arrives.

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

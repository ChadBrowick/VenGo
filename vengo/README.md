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
- The window's top-right buttons: **_** shrinks VenGo to the **venture bar**, one row with the venture furthest along
  right now (its star, GO, zone, VNM, grid, %, drops) and a button to open VenGo again. **X** shrinks it to the VenGo
  orb; click the orb to open it. `/vengo` shows or hides everything.

## The trail

In the venture's zone (or after GO), a glowing path runs along the ground from your
feet to the VNM's grid square, with chevrons crawling toward it and a flag at the end
showing the name and distance. It uses the game's own camera, so it sits on the ground
as you turn. It's a straight line: it shows the way, not the route round walls, and ends
5 yalms from the square's middle. Settings: on/off, glow, and the chevrons' colour.

By default the arrows come up on their own only once the zone's VNM is at 100% (or announced). Press GO in
the zone to show them any time; turn off "Only when the VNM is at 100%" in Settings to have them whenever you're in
a venture zone.

## Stars, controller and updates

- **Stars:** the star beside a venture's GO button watches that zone; clicking a piece on the VNM ARMOR tab watches
  every venture that drops it. Watched VNMs get a chat line and a sound at 90%, at 100% and a minute before the pop.
- **Controller:** `/vengo pad` (or Settings > Controller) gives VenGo the controller: d-pad to move, A to press.
  Back / Select gives it back to the game.
- **VNM alert from the controller:** while the VNM INCOMING alert is up, hold LB and press A for GO (or STOP / cancel)
  and LB + B to dismiss it. A and B work as usual in the game otherwise.
- **Updates:** VenGo checks github.com/ChadBrowick/VenGo for new releases. Settings > Updates (or `/vengo upgrade`)
  downloads the new zip from that repository only and unpacks it over the vengo folder; then `/addon reload vengo`.

## Dailies

The DAILIES tab (under SUMMIT, or `/vengo dailies`) tracks the CatsEyeXI goblin dailies in Lower Jeuno
(Fishstix, Murdox, Mistrix, Saltlix, Beetrix), Goldilox's dice reward, and Palalumin's three Sea dailies. Talk to each
NPC to pick up the day's task; VenGo reads it from chat and shows its state (not started, in progress, turn in, done),
the zone, kills, and how many of the wanted items you carry. Click a name in violet to look it up on the catseyexi.com
database. Everything resets at JP midnight and is kept per character (`dailies_<id>.lua`).

Click the pin on a daily to keep it on screen: while VenGo is minimized (or closed), a small DAILIES tracker shows each
pinned daily with its objective, zone, kill and item bars, and the time to the reset. Drag it where you like; click its
pin to unpin. It hides while the full window is open.

## Points

VenGo asks the CatsEyeXI server for your points the way Trove's Points tab does, and shows each group where it belongs:
Venture points (EXP, Battle) on VENTURES, Summit points on SUMMIT, Daily points on DAILIES, and the CatsEyeXI group
(Domain Shards, Dynamis RP, DKP, Gob Scraps, Muiridian Favor and so on) on its own **CATSEYEXI** tab
(`/vengo points`). They update every minute while one of those tabs is open; REFRESH asks again straight away.

## Colours and your own background

**Style** (Settings > Colours): **Classic** is VenGo's own look; **Phantom** is red, black and white and slanted, like
ChadcoreMenu's Phantom style: the panel a black slab edged white on a red one, the page's name in cut-out letters, the
menu as dark strips with the page you're on a white slab and a red slash, and a bold narrow font. Phantom has its own
colour picks: accent, slab and edge. Its fonts are in `fonts` (Inter Black, SIL Open Font License; TeX Gyre Heros Cn
Bold, GUST Font License).

Settings > Colours has 19 accent colours and 14 backgrounds. **CHOOSE PICTURE** (under them) opens Windows' file picker:
pick a PNG, JPG or BMP and it's copied into the `images` folder and shown behind the window, filling it without
stretching. **Picture strength** sets how much of it shows through the background colour; REMOVE takes it away.

## Voices

Settings > VNM Alerts > **Voice** speaks the alert instead of the chime: **Scottish female**, **British male** or
**Japanese female**. When a VNM is announced it says "V N M incoming!" and the VNM's name; a minute before it pops,
its name and "One minute to the pop!" (the Japanese voice says it in Japanese). The voices are recorded clips in the
`sounds` folder, so there's nothing to install. TEST VOICE tries it. Voice credits: `LICENSE-voices.txt`.

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

- **Vekien** for the VanaCore project
- **Yunas** for YunaUI: VenGo's look and its VanaCore start-up come from it
- **Commandobill, Seekey and Phatty** for the ventures addon: the venture board and the VNM list
- **Thorny** for Uberwarp, which does the warps behind GO
- **GUST** for the TeX Gyre Adventor font
- **Dewin** for Goldilox: the DAILIES tab (MIT licence, `LICENSE-goldilox.txt`)
- **Inter** (Rasmus Andersson) and **TeX Gyre Heros** (GUST) for the Phantom style's fonts
- **alba** (University of Edinburgh, CC BY 4.0) and **Kokoro** (hexgrad, Apache 2.0) for the voices, made with **sherpa-onnx** (`LICENSE-voices.txt`)
- **Loxley** for Trove: the VNM Armor, Ultimates, Lumoria and Odious Codex data, and how to ask for points (MIT licence, `LICENSE-trove.txt`)

## Credits and licence

VenGo is free software under the GNU GPL v3 (`LICENSE`).
`native.lua` and the window's look come from YunaUI by Yunas (GPL v3).
The font is TeX Gyre Adventor by GUST (`fonts/GUST-texgyreadventor.txt`).

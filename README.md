# Meio Stats

For WoW Forever. How fast are you really levelling? XP per hour, time to the next level, how lucky your quest drops were and what you earned, in one window.

![Before: an hour of levelling is XP lines in chat and /played; with Meio Stats, the Levelling
tab with XP per hour, time to the next level and where the XP came
from](docs/before-after.png)

## What it does

Type `/stats`, or click its button in the minimap's addon menu, for a window with eight
tabs. It records from the moment you install it.

- Levelling: XP and gold per hour, time to the next level, XP from kills, rested, quests
  and exploring, and a row per level with its time, kills, quests, deaths and gold
- Zones: each dungeon run with its time, XP per hour, kills and gold, and XP per hour in
  each zone, so you can see whether dungeons or questing level you faster
- Journey: your trail on the world map with where you levelled, died and went into
  dungeons, grind spots in faint red, and a replay bar; the tab adds how far you went on
  foot, mounted, by flight and as a ghost
- Farming: `/stats farm` starts a session with a small tracker of gold and item worth per
  hour; past farms side by side so you can pick the best spot
- Wealth: your account's value day by day, and where your gold came from and went
- History: trades, auction sales and buys, mail, vendor visits, quests and good loot, for
  all your characters
- Loot luck: kills and loot per mob, and quest drops against their real drop rate ("very
  lucky, top 2%"), with Questie installed
- Money: what you sold and bought per item, with profit, and the last 30 days, from
  TradeSkillMaster's ledger
- A chat line at each level-up: how long it took, faster or slower than the level before
- Time spent AFK is left out of XP per hour
- Questie, TradeSkillMaster and [Meionomics](https://www.curseforge.com/wow/addons/meionomics) (profit
  on crafted items, item worth in Wealth) are optional: without them the rest still works

Settings: Esc > Options > AddOns > MeioStats, or `/stats settings`.

- `/stats`: open or close the window (`/meiostats` too)
- `/stats level`, `/stats zones`, `/stats journey`, `/stats farming`, `/stats wealth`,
  `/stats history`, `/stats loot`, `/stats money`: open on that tab
- `/stats farm start|stop`: a farming session
- `/stats replay [level]`: replay your trail on the world map
- `/stats trail on|off`, `/stats heat on|off`: the trail and grind spots on the map
- `/stats ding on|off`: the level-up chat line
- `/stats reset`: put the window and the farming tracker back where they start
- `/stats help`: all of these in chat

## Coming soon

- Hand these in and you level: the XP waiting in your quest log, drawn on the XP bar

![Coming soon: XP bar tooltip: Quests ready: 5,790 XP (Level 23 when handed
in)](docs/soon.png)

## Install

Use your addon manager (CurseForge, Wago), or unzip a GitHub release into
`World of Warcraft\_forever_\Interface\AddOns` and restart WoW fully.

## Feedback

Bugs, ideas or just a thumbs up: leave a comment on the CurseForge or Wago page you got it from. [GitHub issues](https://github.com/MeioNeiz/MeioStats/issues) are welcome too.

## More Meio addons

[Meio Trainer Compare](https://www.curseforge.com/wow/addons/trainercompare) | [Meio Next Stop](https://www.curseforge.com/wow/addons/leavebutton) | [Meio Auto Rank](https://www.curseforge.com/wow/addons/meio-autorank) | [Meio Meter Hover](https://www.curseforge.com/wow/addons/meterhover) | [Meio Map](https://addons.wago.io/addons/meiomap) | [Meio Alts](https://addons.wago.io/addons/meioalts) | [Meio DPS](https://addons.wago.io/addons/meiodps) | [Meio Nameplates](https://addons.wago.io/addons/meioplates) | [Meio Hub](https://addons.wago.io/addons/meiohub) | [Meio Pets](https://addons.wago.io/addons/meiopets) | [Meio Bags](https://addons.wago.io/addons/meiobags) | [Meio Fixes](https://addons.wago.io/addons/meiofixes) | [Meio Flight Times](https://addons.wago.io/addons/meioflighttimes) | [Meio Tooltips](https://addons.wago.io/addons/meiotooltipfold) | [Meio Autorun](https://addons.wago.io/addons/meioautorunturn) | [Meio Mail](https://addons.wago.io/addons/meiomail) | [Meio QoL](https://addons.wago.io/addons/meioqol) | [Meio TSM Browse](https://addons.wago.io/addons/tsmbrowse) | [Meio Shards](https://addons.wago.io/addons/meioshards) | [Meionomics](https://www.curseforge.com/wow/addons/meionomics) | [Meio Spike Check](https://addons.wago.io/addons/meiospikecheck) | [Meio BiS Extras](https://addons.wago.io/addons/meiobisextras) | [Meio Buff Thanks](https://addons.wago.io/addons/meiobuffthanks) | [Meio Flare Fixes](https://addons.wago.io/addons/meioflarefixes) | [Meio Flare Questie](https://addons.wago.io/addons/meioflarequestie)

## Licence

[MIT](LICENSE)

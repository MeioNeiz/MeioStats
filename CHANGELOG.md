# Meio Stats

## 1.2.0

- Your journey on the world map: a dotted trail where you've been, with where you levelled,
  died and went into dungeons, and faint red squares where you killed the most. The bar at
  the map's bottom left replays it (`/stats replay [level]`); `/stats trail` and
  `/stats heat` turn each part on or off
- Journey tab: how far you went on foot, mounted, by flight and as a ghost, the zones you
  passed through and where you were at each level-up; click a level to replay from there
- Farming: `/stats farm` starts a session with a small tracker of gold and item worth per
  hour (AFK left out); the Farming tab compares past farms so you can pick the best spot
- Wealth tab: your account's value day by day, and where your gold came from and went
  (loot, quests, vendors, repairs, auction house, mail, trades, flights, training)
- History tab: trades with who and what changed hands, auction sales and buys, mail,
  vendor visits, quests and good loot, for all your characters

## 1.1.3

- Back to the name Meio Stats: the AddOns list, Settings, chat and the window title say
  MeioStats again. /stats and everything it has recorded are unchanged

## 1.1.2

- Loot luck reads which items your quests need from QuestieDB only: ready for Questie's next
  big update, which shuts other addons out of its insides
- Drop rates still come from Questie while it shares them; when it doesn't, the Loot tab says
  so instead of asking you to install Questie, and quest items are still counted

## 1.1.1

- Now called Meio XP Meter: the AddOns list, Settings and chat say MeioXPMeter. /stats and
  everything it has recorded stay as they were

## 1.1.0

- Zones tab: each dungeon run (time, XP per hour, kills, deaths, gold) and XP per hour in
  each zone at your level, against your rate outside dungeons. A run carries on through a
  death or a logout; 20 minutes outside ends it. `/stats zones`
- Each level: kills, quests, deaths and gold for each level, and hover a row for its XP
  sources, kills per hour and gold per hour
- Gold per hour tile; gold from mail, trade, the auction house and guild bank isn't counted
- A chat line at each level-up: how long it took, faster or slower than the level before,
  with kills, quests, deaths and gold
  (`/stats ding off` turns it off)
- Time spent AFK is left out of XP per hour

## 1.0.1

- Fixed: `/reload` no longer starts a new levelling session or resets this session's gold
- Fixed: without Questie, quest items you were collecting were missing from the loot list
- Money's daily bars use your local date (a sale just after midnight counted on the day
  before)

## 1.0.0

- First release: `/stats` window with Levelling (XP per hour, time to the next level, where
  the XP came from, played time per level), Loot luck (kills and loot per mob, quest drops
  against Questie's drop rates) and Money (sales, purchases and profit per item from
  TradeSkillMaster's ledger, the last 30 days, this session's gold)
- Window position saved; Settings panel under Esc > Options > AddOns, also from the addon
  compartment

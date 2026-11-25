# Meio Stats

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

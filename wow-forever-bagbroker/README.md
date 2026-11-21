# BagBroker for WoW Forever

BagBroker is an addon for World of Warcraft: Forever (interface 16001, Mainline UI engine). It combines price information, vendor automation, auction posting, loot analytics and a farming advisor in a single package. We designed every feature around the restrictions of the Mainline addon API: posting an auction and destroying an item each require one hardware event (a click or key press), and no API exposes creature loot tables. Where a requirement collides with such a restriction, the addon implements the closest behaviour the client permits, as described below.

## Installation

1. Copy the `BagBroker` folder (the one that contains `BagBroker.toc`) into `World of Warcraft\_forever_\Interface\AddOns\`.
2. Restart the game or type `/reload`.
3. If the character screen lists the addon as out of date, a newer client build has changed the interface number. In that case, either tick "Load out of date AddOns" or edit the first line of `BagBroker.toc` to the current number.

## Features

### 1 and 2. Vendor and auction prices on item tooltips

Every auction value BagBroker displays or compares is net: the price minus the 5% auction cut minus the deposit for the item's default duration. Outside the auction house the deposit is estimated (15%, 30% and 60% of the vendor price for 12 h, 24 h and 48 h); each auction house visit measures the real rates with the game's deposit functions and the estimate converges to them.

Prices form an aligned block: labels on the left and money right-aligned, with every lower denomination present (zero-padded and dimmed), so gold, silver and copper line up vertically and values can be compared at a glance. When the game adds its own `Sell Price:` line, BagBroker restyles that line into the block instead of adding a duplicate.

```
Sell Price                 2s 60c
Auction (net)             17s 04c      lowest buyout, net of cut and deposit
  25%                     19s 31c      quartiles of the unit price, net
  50%                     21s 59c
  75%                     25s 82c
```

Prices refer to the hovered stack, consistent with the default line. Percentiles are weighted by units rather than auctions, so a stack of 200 counts as 200 offers. The statistics originate from two sources. First, a full scan (`C_AuctionHouse.ReplicateItems`) runs automatically when the auction house opens, subject to the server limit of one scan per 15 min. Second, every live price search performed by the selling panel refreshes the statistics of the searched item. Soulbound bag items show no auction rows.

### 3. Automatic vendor selling

When a merchant window opens, BagBroker sells every item whose vendor price is greater than or equal to its auction value, with the following rules:

| Item | Decision |
|---|---|
| Unbound bind-on-equip (default) | Never sold |
| Poor quality (grey) | Sold, unless the auction net exceeds the vendor price |
| Tradeable item with auction data | Sold when vendor price ≥ auction net (median − 5% cut − deposit) |
| Unbound bind-on-equip, with "Include bind-on-equip" on (`/bb sellboe on`) | Sold when vendor price ≥ auction net |
| Tradeable item without auction data | Kept |
| Soulbound gear, uncommon or lower, item level not above the equipped item in that slot | Sold |
| Other soulbound items, quest items, refundable purchases, items without vendor value | Kept |
| Keep list (`/bb keep`) / junk list (`/bb junk`) | Always kept / always sold |

A small panel docks next to the merchant window with three options (automatic selling, include bind-on-equip items, include soulbound gear below your item level), the number and value of stacks that sell better to the vendor, and a **Sell now** button that works even when automatic selling is off. Holding Shift while opening a merchant skips automatic selling for that visit, and `/bb preview` lists the decision and its reason for every bag item. The comparison statistic can be changed with `/bb compare min|p25|p50|p75`.

### 4. Selling panel at the auction house

A panel docks to the right of the default auction house window. It lists every auctionable bag item with a tick box, a unit price and a duration. Unit prices sit in three fixed columns (gold, silver, copper), so prices of different magnitude line up coin by coin. Items whose auction proceeds exceed the vendor price are ticked in advance, which constitutes the proposal to sell at good prices. Each click on **Post next** posts the next ticked item from the top of the list, because the game allows one post per click.

Prices derive from the current listings of each item, obtained through throttled live searches, while the addon's own auctions are excluded. Rather than always undercutting the cheapest auction, the algorithm treats a thin layer of cheap listings as stock that buyers will clear first:

1. Listings are grouped by unit price, cheapest first.
2. Price levels are skipped while the cumulative quantity skipped stays at or below 10% of the total supply (adjustable with `/bb wall <percent>`). A level priced below half of the weighted median is also skipped when it holds at most 34% of supply, which removes isolated mispriced items such as a single sword listed at one tenth of its value.
3. The suggested price undercuts the first remaining level by 1c (by 1s on servers that refuse copper values).
4. Without competing listings, the upper quartile of the price history is used. Before the live search returns, the panel shows the historical median in grey.

Default durations follow item categories, and each category button at the top of the panel cycles its duration with a left or right click:

| Category | Default |
|---|---|
| Consumables, reagents | 12 h |
| Trade goods, gems | 12 h |
| Bind-on-equip gear (common, uncommon) | 24 h |
| Rare or better gear, recipes | 48 h |
| Other | 24 h |

Selecting a row opens an editor in which the unit price can be typed (`1g 20s`, `35s`, `80c` or `1.5` for gold) and the duration of that item changed. **Auto** restores the suggested price. When the server requests confirmation for an unusual price, the button changes to **Confirm post** and the next click confirms.

### 5. Full bags and better loot

When the bags are full and a loot slot cannot be stacked anywhere, BagBroker compares its value with the cheapest unprotected bag item. Values are the maximum of vendor price and auction net, multiplied by quantity; quest loot always qualifies. If the loot is worth more, a small prompt appears next to the loot window:

```
Destroy [Broken Fang] (50c) to loot [Shiny Loot] (5g)?   [Replace]
```

Because the Mainline client blocks item destruction without a hardware event (since patch 9.0.2), the swap runs from the **Replace** button, from the key binding "Bags full: replace cheapest item with offered loot", or from a macro containing `/click BagBrokerReplaceButton`. After each swap, the prompt re-evaluates the remaining loot. Protected items include quest items, containers, equipment set items, the keep list, items without any value (such as the Hearthstone), soulbound or bind-on-equip gear of uncommon quality or better, and every epic item.

### 6. Account-wide data

All data reside in one account-wide SavedVariables table (`BagBrokerDB`). Auction statistics are keyed by realm and faction, so a gathering character and a selling character on the same realm read and write the same prices; `/bb share on` merges both factions of a realm. Mob loot data and heatmaps are shared by all characters on all realms. The client writes SavedVariables to disk only on logout or `/reload`, so the scanning character must log out (or reload) before another character can see its newest data.

### 7. Loot tables on mob tooltips: vanilla database, Everloot and your kills

No game API exposes creature loot tables, so BagBroker combines three sources, each weighted by the number of observations it holds:

| Layer | Source | Weight |
|---|---|---|
| Vanilla database | CMaNGOS Classic-DB loot tables (per kill, but vanilla 1.12) | 25 kills by default (`/bb prior <kills>`) |
| Everloot | Crowd-sourced WoW Forever loot windows (everloot.app) | One observation per loot window |
| You | Your own kills, shared by all characters on the account | One observation per kill |

    value = (25 × vanilla + windows × Everloot + kills × yours) / (25 + windows + kills)

Five personal kills therefore weigh 5/30 against the vanilla prior, while 279 Everloot windows outweigh it by 279 to 25, so Forever's real drop rates take over wherever players have recorded them, and creatures with few observations fall back to the vanilla tables. Everloot counts opened loot windows, and corpses without loot cannot be opened; each Everloot share is therefore multiplied by the vanilla probability that a corpse has any loot (100% for creatures that drop money, about 79% for a typical boar) to obtain a per-kill chance. Money per kill uses the vanilla and personal layers, because Everloot does not report it. Creatures absent from both databases, including much new Forever content, use your kills alone. Mob tooltips show the sources, the expected value per kill and, for each drop, its chance and one vendor and one auction (net) unit price in aligned columns:

```
Loot per kill (vanilla + Everloot 279 + you 12)          12s 40c
  Drops                       Chance    Vendor      AH net
  Cracked Basilisk Scale         58%    1s 05c           -
  Basilisk Heart                 21%       45c      2s 50c
  Scorpashi Gloves              0.9%   21s 40c  3g 51s 25c
  Random world drops                                  2.4%
  Skinning (you can skin it)                        4s 10c
```

The columns are true fixed-width columns: every cell is measured with the tooltip font and padded with a transparent spacer (`spacer.tga`) to its column width. Kill counting is unchanged: each looted corpse counts once per GUID (area loot aware), empty corpses of targeted, tapped creatures also count, and pick pocketing and fishing are excluded. Values use current auction prices (net) when available and vendor prices otherwise; skinning is added when your Skinning skill reaches the creature's requirement (level 1 to 10: 1; 11 to 20: (level − 10) × 10; above 20: level × 5).

#### Keeping the Everloot data current

The game cannot download anything, so `EverlootData.lua` is refreshed outside it by `tools/update_everloot.py` (Python 3, no extra packages). It downloads Everloot's drop rollups and rewrites only that 10 KB file, and only when the data changed:

```
python3 tools/update_everloot.py --out "C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/BagBroker/EverlootData.lua"
```

To refresh automatically on Windows, schedule it once (for example daily at 18:00) in a terminal:

```
schtasks /create /tn "BagBroker Everloot" /sc daily /st 18:00 /tr "py \"C:\path\to\tools\update_everloot.py\" --out \"C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\BagBroker\EverlootData.lua\""
```

The new data loads at the next login or `/reload`. `/bb status` and the farming window show the age of the installed data.

#### Contributing your own data to Everloot

Addons cannot send data over the network, so contributions go through Everloot's own pipeline: install the Everloot addon next to BagBroker, then either upload `WTF/Account/<account>/SavedVariables/Everloot.lua` at everloot.app/upload (with a preview before sending) or let the Everloot Desktop App upload after every logout. Both addons run independently; your uploads then return to BagBroker through the next Everloot refresh. BagBroker does not imitate Everloot's upload format, so that their validation, consent and deduplication remain intact.

### 8. Farming heatmap

The heatmap window draws the zone on a 60 × 40 grid and colours each cell from blue (low) to red (high), while opacity increases with the number of kills or spawns. The **Source** button cycles three views:

| Source | Cell colour | Opacity |
|---|---|---|
| My kills | Loot value per kill of the creatures you killed there | Your kills |
| Database | Loot value per kill of normal creatures spawning there within your level window, including skinning if you can skin them | Spawns |
| Gathering | Value per node of the herbs and ores you can gather | Node spawn points |

Hovering a cell lists its creatures or nodes with their values. The `<` and `>` buttons browse all zones with data, **Current zone** returns to the player's position, and **Best spots** opens the farming advisor.

We implemented the heatmap as a separate, movable window rather than an overlay on the world map. Carbonite replaces the default world map, so an overlay would either be hidden or conflict with it, and a permanent overlay would obstruct the map during normal play. The window is toggled by:

- a left click on the minimap button (Carbonite may collect the button into its own button bar);
- the key binding "Toggle loot heatmap";
- `/bb map`, which can also be placed in a macro;
- the Escape key, which closes it.

### 9. Farming advisor (best spots for your level and professions)

`/bb farm`, a Ctrl click on the minimap button, the **Best spots** button of the heatmap or the key binding "Toggle farming spots" opens a window that reads your level and your gathering professions (Herbalism, Mining, Skinning) and ranks:

- **Kill spots:** areas of 5 × 5 heatmap cells (roughly 8% of a zone in each direction) around local maxima of value density, ranked by the value of one clear of the area. Only normal (non-elite) creatures between 6 levels below and 1 level above your level are considered (`/bb levels <below> <above>`); creatures whose recorded level range is wider than 6 levels are judged by their top level. Each row shows the zone and coordinates, the main creatures, the number of spawns, the value per kill and the value per clear.
- **Gathering zones:** for Mining and Herbalism, zones ranked by the total value of all node spawn points you can gather at your current skill, with node types coloured by skill-up colour (orange, yellow, green, grey). Spawn points are possible positions, not nodes that are up simultaneously, so the totals compare zones rather than predict one route's income.

Clicking a row opens the heatmap on that zone with the matching source and, for kill spots, a gold frame around the area.

### 10. Mail panel: send auction goods to a mule

When the mailbox opens, a panel docks to its right. It lists every bag item worth selling at the auction house (bind-on-equip items, and items whose auction net beats the vendor price) with its auction net value, all ticked by default, and remembers your mule's name per realm (`/bb mule <name>` or the panel's field). **Attach** fills the Send Mail tab in one click: the recipient, the subject "AH items" and up to 12 stacks, the game's attachment limit. You then press the default Send button; the panel immediately offers the remaining stacks for the next mail.

## Commands

| Command | Effect |
|---|---|
| `/bb map` | Toggle the heatmap window |
| `/bb farm` | Toggle the farming advisor |
| `/bb prior <kills>` | Weight of the public loot database in kills (default 25) |
| `/bb levels <below> <above>` | Level window of creatures for kill spots (default 6 1) |
| `/bb panel` | Toggle the selling panel (at the auction house) |
| `/bb scan` | Start a full auction scan (once per 15 min) |
| `/bb sell on\|off` | Automatic vendor selling |
| `/bb sellboe on\|off` | Also sell bind-on-equip items when the vendor pays more than the auction net |
| `/bb mule <name>` | Mule for the mail panel (saved per realm) |
| `/bb mail` | Toggle the mail panel |
| `/bb preview` | List vendor decisions with reasons |
| `/bb keep <item link>` | Never sell or destroy an item |
| `/bb junk <item link>` | Always sell an item |
| `/bb forget <item link>` | Remove an item from both lists |
| `/bb compare min\|p25\|p50\|p75` | Auction statistic compared with the vendor price |
| `/bb soulbound on\|off` | Sell soulbound gear below the equipped item level |
| `/bb replace on\|off` | Offer swaps when bags are full |
| `/bb wall <percent>` | Thin-layer threshold of the pricing algorithm (default 10) |
| `/bb mobs on\|off` | Loot lines on mob tooltips |
| `/bb minimap on\|off` | Minimap button |
| `/bb share on\|off` | Share auction data between factions |
| `/bb status` | Data summary |
| `/bb reset heat\|mobs\|prices` | Delete recorded data |

`/bagbroker` is an alias of `/bb`. Key bindings are listed under Options, Keybindings, AddOns, BagBroker.

## Data sources and rebuilding the database

`BagBroker/FarmData.lua` (about 2.3 MB) is generated by `tools/build_farm_data.py` from:

- **CMaNGOS Classic-DB** (GPLv3): creature loot templates resolved with the emulator's group-roll semantics (independent entries roll separately; within a group, explicit chances apply first and equal-chance entries share the remainder), reference (world drop) templates, money drops, skinning loot, gathering node loot with the number of uses per node, and item vendor prices and qualities.
- **QuestieDB, Forever flavour** (GPLv3): creature names, level ranges, ranks and hostility, creature and node spawn coordinates on Forever maps (13,691 coordinates converted from Classic Era by the QuestieDB maintainers), the Forever area-to-map table and the dungeon list. Its correction layers are applied in QuestieDB's own order: raw data, the generated delta-base derived from Wowhead's Forever snapshot, aggregated player traces (about 1.8 million Forever sessions) and authored fixes.

The build parses the SQL dump and the Lua data files as text and never executes downloaded code. The current file holds 6,166 creatures (3,445 with open-world spawns, 1,134 Forever-only creatures without loot data), 500 world-drop tables, 774 skinning tables and 46 gathering node types. To refresh it:

```
python3 tools/build_farm_data.py
```

`BagBroker/EverlootData.lua` holds Everloot's drop observations (CC BY-SA 4.0, attribution in `BagBroker/licenses/Everloot-DATA.md`; Creative Commons declares CC BY-SA 4.0 one-way compatible with GPLv3). CMaNGOS Classic-DB and QuestieDB are GPLv3, and their licence texts are included in `BagBroker/licenses/`. The addon remains free for personal use; if you redistribute it, distribute it under GPLv3 with those licence files.

## Testing

The repository includes a mock of the game API and 43 behavioural tests, which load the addon files in TOC order under Lua 5.1, the language version embedded in the client:

```
lua5.1 tests/run_tests.lua
```

The tests cover the pricing algorithm, the vendor rules, a merchant visit, the aligned tooltip block (including the restyled default line), the aligned money columns, a full scan, cross-character data access, posting from the panel (including server confirmation), loot learning, empty-corpse detection, the weighting of the vanilla, Everloot and personal layers (including the empty-corpse correction), the deposit-aware auction net, the vendor panel and its bind-on-equip option, the mail panel (12 stacks per mail), skinning requirements, kill spot and gathering zone ranking (on a synthetic database for exact values and on the real database as a smoke test), the advisor window, the heatmap sources, full-bag replacement and the slash commands. The API signatures were taken from Blizzard's generated API documentation of the current Mainline client. The addon has not yet been run inside the Forever client, so the first session in game constitutes its validation; `/bb debug on` prints suppressed tooltip errors to the chat window.

## Known limitations

- Auction posting and item destruction require one click or key press per action, which is a client restriction that no addon can bypass.
- The full scan is limited by the server to one run per 15 min.
- Kills of creatures that were not targeted and left an empty corpse are not counted, so values per kill are slightly optimistic for area farming.
- Statistics for gear are keyed by item ID; random suffix variants share one entry on tooltips, whereas the selling panel prices each variant separately.
- The vanilla layer reflects 1.12 loot tables; Everloot and your kills move each estimate toward Forever's real rates as observations accumulate. Everloot currently covers about 170 creatures and grows as players upload.
- Deposits outside the auction house are estimates until the first auction house visit calibrates them.

# BagBroker for WoW Forever

BagBroker is an addon for World of Warcraft: Forever (interface 16001, Mainline UI engine). It combines price information, vendor automation, auction posting and loot analytics in a single package. We designed every feature around the restrictions of the Mainline addon API: posting an auction and destroying an item each require one hardware event (a click or key press), and no API exposes creature loot tables. Where a requirement collides with such a restriction, the addon implements the closest behaviour the client permits, as described below.

## Installation

1. Copy the `BagBroker` folder (the one that contains `BagBroker.toc`) into `World of Warcraft\_forever_\Interface\AddOns\`.
2. Restart the game or type `/reload`.
3. If the character screen lists the addon as out of date, a newer client build has changed the interface number. In that case, either tick "Load out of date AddOns" or edit the first line of `BagBroker.toc` to the current number.

## Features

### 1. Vendor price on item tooltips

Tooltips receive a `Sell Price:` line written with the same function, colour and coin icons as the default game line. The line is added only when the game did not already add one. Prices refer to the hovered stack, consistent with the default line.

### 2. Auction price with quartiles

A second line reports the lowest buyout followed by the 25th, 50th and 75th percentiles of the unit price in parentheses:

```
Sell Price: 12s 50c
Auction: 1g 10s (1g 15s / 1g 30s / 1g 60s)
```

Percentiles are weighted by units rather than auctions, so a stack of 200 counts as 200 offers. The statistics originate from two sources. First, a full scan (`C_AuctionHouse.ReplicateItems`) runs automatically when the auction house opens, subject to the server limit of one scan per 15 min. Second, every live price search performed by the selling panel refreshes the statistics of the searched item. Soulbound bag items show no auction line.

### 3. Automatic vendor selling

When a merchant window opens, BagBroker sells every item whose vendor price is greater than or equal to its auction value, with the following rules:

| Item | Decision |
|---|---|
| Unbound bind-on-equip | Never sold |
| Poor quality (grey) | Sold, unless the auction net exceeds the vendor price |
| Tradeable item with auction data | Sold when vendor price ≥ median × 0.95 (the 5% auction cut is deducted) |
| Tradeable item without auction data | Kept |
| Soulbound gear, uncommon or lower, item level not above the equipped item in that slot | Sold |
| Other soulbound items, quest items, refundable purchases, items without vendor value | Kept |
| Keep list (`/bb keep`) / junk list (`/bb junk`) | Always kept / always sold |

Holding Shift while opening a merchant skips selling for that visit, and `/bb preview` lists the decision and its reason for every bag item. The comparison statistic can be changed with `/bb compare min|p25|p50|p75`.

### 4. Selling panel at the auction house

A panel docks to the right of the default auction house window. It lists every auctionable bag item with a tick box, a unit price and a duration. Items whose auction proceeds exceed the vendor price are ticked in advance, which constitutes the proposal to sell at good prices. Each click on **Post next** posts the next ticked item from the top of the list, because the game allows one post per click.

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

### 7. Learned loot tables on mob tooltips

No API exposes creature loot tables, and Forever adds zones and creatures that no vanilla database covers. BagBroker therefore learns loot tables from the kills of all characters on the account. Each looted corpse counts as one kill of its NPC; area loot is attributed per corpse and duplicates are removed by GUID. Targeted, tapped creatures that die with an empty corpse also count as kills, which prevents the average from being inflated by observing only corpses with loot. Pick pocketing and fishing are excluded. Mob tooltips then show:

```
Loot per kill: 35s 20c (48 kills)
  Linen Cloth          45%
  Broken Fang          21%
  Money                8s 12c
```

The value per kill uses current vendor and auction prices. Estimates become reliable only after several dozen kills of a given creature. The right click on the minimap button, `/bb mobs on|off` and a key binding toggle these lines.

### 8. Farming heatmap

Every recorded kill is placed on a 60 × 40 grid of the zone map. The heatmap window draws the zone and colours each cell by the average loot value per kill of the creatures killed there, from blue (low) to red (high), while opacity increases with the number of kills. Hovering a cell lists its creatures, kill counts and values. The `<` and `>` buttons browse all zones with data, and **Current zone** returns to the player's position.

We implemented the heatmap as a separate, movable window rather than an overlay on the world map. Carbonite replaces the default world map, so an overlay would either be hidden or conflict with it, and a permanent overlay would obstruct the map during normal play. The window is toggled by:

- a left click on the minimap button (Carbonite may collect the button into its own button bar);
- the key binding "Toggle loot heatmap";
- `/bb map`, which can also be placed in a macro;
- the Escape key, which closes it.

## Commands

| Command | Effect |
|---|---|
| `/bb map` | Toggle the heatmap window |
| `/bb panel` | Toggle the selling panel (at the auction house) |
| `/bb scan` | Start a full auction scan (once per 15 min) |
| `/bb sell on\|off` | Automatic vendor selling |
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

## Testing

The repository includes a mock of the game API and 28 behavioural tests, which load the addon files in TOC order under Lua 5.1, the language version embedded in the client:

```
lua5.1 tests/run_tests.lua
```

The tests cover the pricing algorithm, the vendor rules, a merchant visit, the tooltip lines, a full scan, cross-character data access, posting from the panel (including server confirmation), loot learning, empty-corpse detection, the heatmap, full-bag replacement and the slash commands. The API signatures were taken from Blizzard's generated API documentation of the current Mainline client. The addon has not yet been run inside the Forever client, so the first session in game constitutes its validation; `/bb debug on` prints suppressed tooltip errors to the chat window.

## Known limitations

- Auction posting and item destruction require one click or key press per action, which is a client restriction that no addon can bypass.
- The full scan is limited by the server to one run per 15 min.
- Kills of creatures that were not targeted and left an empty corpse are not counted, so values per kill are slightly optimistic for area farming.
- Statistics for gear are keyed by item ID; random suffix variants share one entry on tooltips, whereas the selling panel prices each variant separately.

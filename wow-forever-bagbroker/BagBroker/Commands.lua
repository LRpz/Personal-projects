-- BagBroker: slash commands (/bb or /bagbroker). Every command also works inside a macro.
local _, ns = ...

BINDING_HEADER_BAGBROKER = "BagBroker"
BINDING_NAME_BAGBROKER_TOGGLE_HEATMAP = "Toggle loot heatmap"
BINDING_NAME_BAGBROKER_TOGGLE_PANEL = "Toggle auction selling panel"
BINDING_NAME_BAGBROKER_TOGGLE_MOBTIPS = "Toggle mob loot tooltips"
BINDING_NAME_BAGBROKER_TOGGLE_FARMSPOTS = "Toggle farming spots"
BINDING_NAME_BAGBROKER_REPLACE_LOOT = "Bags full: replace cheapest item with offered loot"

function BagBroker_ToggleMobTooltips()
	ns.settings.mobTooltips = not ns.settings.mobTooltips
	ns:Print("Mob loot tooltips " .. (ns.settings.mobTooltips and "on" or "off") .. ".")
end

local HELP = {
	"/bb map - toggle the loot heatmap window",
	"/bb farm - best farming and gathering spots for your level and professions",
	"/bb prior <kills> - weight of the public loot database in kills (default 25)",
	"/bb levels <below> <above> - level range of creatures for farming spots (default 6 1)",
	"/bb panel - toggle the auction selling panel (at the auction house)",
	"/bb scan - start a full auction scan (once per 15 min, at the auction house)",
	"/bb sell on|off - automatic vendor selling (hold Shift at a merchant to skip once)",
	"/bb sellboe on|off - also sell bind-on-equip items when the vendor pays more than the auction net",
	"/bb mule <name> - mule character for the mail panel (saved per realm); /bb mail toggles the panel",
	"/bb preview - list what the vendor would buy right now, and why other items are kept",
	"/bb keep <item link> - never sell or destroy this item",
	"/bb junk <item link> - always sell this item to vendors",
	"/bb forget <item link> - remove an item from the keep and junk lists",
	"/bb compare min|p25|p50|p75 - auction statistic compared with the vendor price",
	"/bb soulbound on|off - sell soulbound gear (uncommon or lower) below your equipped item level",
	"/bb replace on|off - when bags are full, offer to swap the cheapest bag item for better loot",
	"/bb wall <percent> - share of supply treated as a thin layer when pricing (default 10)",
	"/bb mobs on|off - learned loot lines on mob tooltips",
	"/bb minimap on|off - minimap button",
	"/bb share on|off - share auction data between factions of a realm",
	"/bb status - data summary",
	"/bb reset heat|mobs|prices - delete recorded data",
}

local function OnOff(value, current)
	if value == "on" then return true end
	if value == "off" then return false end
	return not current
end

local function ItemIDFromText(text)
	return tonumber((text or ""):match("item:(%d+)")) or tonumber(text or "")
end

local function CountKeys(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

local commands = {}

commands.map = function() BagBroker_ToggleHeatmap() end
commands.farm = function() BagBroker_ToggleFarmSpots() end

commands.prior = function(arg)
	local kills = tonumber(arg)
	if kills and kills >= 0 and kills <= 1000 then
		ns.settings.priorKills = kills
		ns.Farm:Invalidate()
	end
	ns:Print(("The public loot database counts as %d kills; your own kills add to that."):format(ns.settings.priorKills))
end

commands.levels = function(arg)
	local below, above = (arg or ""):match("^(%d+)%s+(%d+)$")
	if below then
		ns.settings.farmBelow, ns.settings.farmAbove = tonumber(below), tonumber(above)
	end
	ns:Print(("Farming spots use creatures from %d levels below to %d above your level."):format(ns.settings.farmBelow, ns.settings.farmAbove))
end
commands.panel = function() BagBroker_ToggleAuctionPanel() end
commands.scan = function() ns.Scanner:StartFullScan(true) end

commands.sell = function(arg)
	ns.settings.autoSell = OnOff(arg, ns.settings.autoSell)
	ns:Print("Automatic vendor selling " .. (ns.settings.autoSell and "on" or "off") .. ".")
end

commands.sellboe = function(arg)
	ns.settings.sellBoE = OnOff(arg, ns.settings.sellBoE)
	ns:Print("Selling bind-on-equip items when the vendor pays more " .. (ns.settings.sellBoE and "on" or "off") .. ".")
end

commands.mule = function(_, raw)
	local name = (raw or ""):match("^%s*(%S+)")
	if name then ns.Mail:SetMule(name) end
	ns:Print("Mule for " .. ns:GetRealmKey() .. ": " .. (ns.Mail:Mule() ~= "" and ns.Mail:Mule() or "not set"))
end

commands.mail = function() BagBroker_ToggleMailPanel() end

commands.preview = function()
	local sell, keep = ns.Vendor:Preview()
	ns:Print(("Would sell %d stack(s):"):format(#sell))
	for _, line in ipairs(sell) do ns:Print("  " .. line) end
	ns:Print(("Kept %d stack(s):"):format(#keep))
	for _, line in ipairs(keep) do ns:Print("  |cff999999" .. line .. "|r") end
end

local function ListCommand(listName, label)
	return function(arg, raw)
		local itemID = ItemIDFromText(raw)
		if not itemID then
			ns:Print("Shift-click an item into the chat line after the command.")
			return
		end
		ns.db.keep[itemID], ns.db.junk[itemID] = nil, nil
		if listName then ns.db[listName][itemID] = true end
		ns:Print(("%s %s."):format(ns:GetItemDisplayName(itemID), label))
	end
end
commands.keep = ListCommand("keep", "will never be sold or destroyed")
commands.junk = ListCommand("junk", "will always be sold to vendors")
commands.forget = ListCommand(nil, "removed from the keep and junk lists")

commands.compare = function(arg)
	if ns.STAT[arg or ""] and arg ~= "qty" and arg ~= "time" then
		ns.settings.compare = arg
	end
	ns:Print("Vendor price is compared with the auction " .. ns.settings.compare .. " (after the 5% cut).")
end

commands.soulbound = function(arg)
	ns.settings.sellSoulboundGear = OnOff(arg, ns.settings.sellSoulboundGear)
	ns:Print("Selling soulbound non-upgrade gear " .. (ns.settings.sellSoulboundGear and "on" or "off") .. ".")
end

commands.replace = function(arg)
	ns.settings.replaceLoot = OnOff(arg, ns.settings.replaceLoot)
	ns:Print("Full-bag loot replacement offers " .. (ns.settings.replaceLoot and "on" or "off") .. ".")
end

commands.wall = function(arg)
	local pct = tonumber(arg)
	if pct and pct >= 0 and pct <= 50 then ns.settings.wallFraction = pct / 100 end
	ns:Print(("Thin-wall threshold: %d%% of supply."):format(math.floor(ns.settings.wallFraction * 100 + 0.5)))
end

commands.mobs = function(arg)
	ns.settings.mobTooltips = OnOff(arg, ns.settings.mobTooltips)
	ns:Print("Mob loot tooltips " .. (ns.settings.mobTooltips and "on" or "off") .. ".")
end

commands.minimap = function(arg)
	ns.Minimap:SetShown(OnOff(arg, ns.settings.showMinimap))
end

commands.share = function(arg)
	ns.settings.shareFactions = OnOff(arg, ns.settings.shareFactions)
	ns.realmData = nil
	ns:Print("Auction data key: " .. ns:GetRealmKey())
end

commands.status = function()
	local realm = ns:GetRealmData()
	local done = realm.lastScanDone or 0
	ns:Print(("Auction data %s: %d items, last full scan %s."):format(ns:GetRealmKey(), CountKeys(realm.items),
		done > 0 and date("%Y-%m-%d %H:%M", done) or "never"))
	ns:Print(("Loot data: %d mobs, %d maps."):format(CountKeys(ns.db.mobs), CountKeys(ns.db.heat)))
	local age = ns.Farm and ns.Farm:EverlootAgeDays()
	if age then
		ns:Print(("Everloot data: %d creatures, as of %s (%d day(s) old). Run tools/update_everloot.py to refresh."):format(
			CountKeys(ns.EverlootDB.npcs), ns.EverlootDB.asOf:sub(1, 10), age))
	else
		ns:Print("Everloot data: not installed.")
	end
	ns:Print(("Selling: auto %s, compare %s, soulbound gear %s, replacement %s."):format(
		ns.settings.autoSell and "on" or "off", ns.settings.compare,
		ns.settings.sellSoulboundGear and "on" or "off", ns.settings.replaceLoot and "on" or "off"))
end

commands.reset = function(arg)
	if arg == "heat" then
		wipe(ns.db.heat)
	elseif arg == "mobs" then
		wipe(ns.db.mobs)
		wipe(ns.db.heat)
	elseif arg == "prices" then
		ns:GetRealmData().items = {}
	else
		ns:Print("Usage: /bb reset heat|mobs|prices")
		return
	end
	ns:Print("Deleted " .. arg .. " data.")
end

commands.debug = function(arg)
	ns.settings.debug = OnOff(arg, ns.settings.debug)
	ns:Print("Debug " .. (ns.settings.debug and "on" or "off") .. ".")
end

SLASH_BAGBROKER1 = "/bagbroker"
SLASH_BAGBROKER2 = "/bb"
SlashCmdList.BAGBROKER = function(msg)
	msg = msg or ""
	local command, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	command = (command or ""):lower()
	local handler = commands[command]
	if handler then
		handler((rest or ""):lower(), rest)
		return
	end
	ns:Print("Commands:")
	for _, line in ipairs(HELP) do ns:Print("  " .. line) end
end

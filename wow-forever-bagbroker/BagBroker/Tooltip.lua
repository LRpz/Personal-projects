-- BagBroker: tooltip lines, written exactly like the default "Sell Price:" line
-- (a white line with inline coin icons, no extra frames or sub-menus).
--   Sell Price: 12s 50c                       (only added when the game did not add it)
--   Auction: 1g 10s (1g 15s / 1g 30s / 1g 60s) (lowest buyout, then 25th / 50th / 75th percentile)
--   Loot per kill: 35s 20c (48 kills)          (mob tooltips, learned from your own kills)
local _, ns = ...

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local SELL_LINE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice
local MAX_DROP_LINES = 6

local function HasSellPriceLine(data)
	if not SELL_LINE or not data or type(data.lines) ~= "table" then return false end
	for _, line in ipairs(data.lines) do
		if line.type == SELL_LINE then return true end
	end
	return false
end

-- Stack size and location of the hovered item when it sits in a bag.
local function GetHoveredStack(tooltip, data, itemID)
	if data and type(data.guid) == "string" and C_Item.GetItemLocation then
		local ok, loc = pcall(C_Item.GetItemLocation, data.guid)
		if ok and loc and loc.IsValid and loc:IsValid() then
			return C_Item.GetStackCount(loc) or 1, loc
		end
	end
	local owner = tooltip.GetOwner and tooltip:GetOwner()
	if owner and owner.GetBagID and owner.GetID then
		local okBag, bag = pcall(owner.GetBagID, owner)
		local slot = owner:GetID()
		if okBag and bag and slot then
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == itemID then
				return info.stackCount or 1, ItemLocation:CreateFromBagAndSlot(bag, slot)
			end
		end
	end
	return 1, nil
end

local function OnItemTooltip(tooltip, data)
	if not ns.db or not tooltip or tooltip.isShopping or not tooltip.AddLine then return end
	local itemID = data and data.id
	local link = data and data.hyperlink
	if (not link) and tooltip.GetItem then
		local _, l = tooltip:GetItem()
		link = l
	end
	if ns.IsSecret(itemID) or ns.IsSecret(link) then return end
	if not itemID and link then itemID = C_Item.GetItemInfoInstant(link) end
	if type(itemID) ~= "number" then return end

	local count, loc = GetHoveredStack(tooltip, data, itemID)
	local format = ns.FormatMoney

	local sellPrice = select(11, GetItemInfo(link or itemID))
	if sellPrice and sellPrice > 0 and not HasSellPriceLine(data) then
		ns.AddTooltipLine(tooltip, ("%s: %s"):format(SELL_PRICE or "Sell Price", format(sellPrice * count)))
	end

	local bound = loc and C_Item.IsBound and C_Item.IsBound(loc)
	if bound then return end
	local stats = ns:GetStats(itemID)
	if stats then
		ns.AddTooltipLine(tooltip, ("Auction: %s (%s / %s / %s)"):format(
			format(stats[1] * count), format(stats[2] * count), format(stats[3] * count), format(stats[4] * count)))
	end
end

local function OnUnitTooltip(tooltip, data)
	if not ns.db or not ns.settings.mobTooltips or not tooltip or not tooltip.AddLine then return end
	local guid = data and data.guid
	local unit
	if tooltip.GetUnit then
		local _, u = tooltip:GetUnit()
		unit = u
	end
	if not guid and unit and not ns.IsSecret(unit) then guid = UnitGUID(unit) end
	local npcID = ns.NpcIDFromGUID(guid)
	if not npcID then return end
	local mob = ns.db.mobs[npcID]
	if not mob or (mob.k or 0) < 1 then return end
	if not mob.n and unit and not ns.IsSecret(unit) then
		local name = UnitName(unit)
		if name and not ns.IsSecret(name) then mob.n = name end
	end

	ns.AddTooltipLine(tooltip, ("Loot per kill: %s (%d kills)"):format(ns.FormatMoney(ns:GetMobValue(mob)), mob.k))

	local drops = {}
	for itemID, entry in pairs(mob.i or {}) do
		drops[#drops + 1] = { id = itemID, rate = (entry[1] or 0) / mob.k }
	end
	table.sort(drops, function(a, b) return a.rate > b.rate end)
	for i = 1, math.min(#drops, MAX_DROP_LINES) do
		local d = drops[i]
		local pct = d.rate * 100
		local pctText = pct >= 10 and ("%d%%"):format(math.floor(pct + 0.5)) or ("%.1f%%"):format(pct)
		tooltip:AddDoubleLine("  " .. ns:GetItemDisplayName(d.id), pctText, 1, 1, 1, 1, 1, 1)
	end
	if (mob.m or 0) > 0 then
		tooltip:AddDoubleLine("  " .. (MONEY or "Money"), ns.FormatMoney(mob.m / mob.k), 1, 1, 1, 1, 1, 1)
	end
end

local function Guarded(fn)
	return function(tooltip, data)
		local ok, err = pcall(fn, tooltip, data)
		if not ok then ns:Debug("tooltip: " .. tostring(err)) end
	end
end

ns:On("DB_READY", function()
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then
		ns:Print("Tooltip API not found; price lines are disabled.")
		return
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Guarded(OnItemTooltip))
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, Guarded(OnUnitTooltip))
end)

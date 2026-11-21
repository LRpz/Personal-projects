-- BagBroker: tooltip lines as an aligned block (labels left, money right-aligned so gold, silver
-- and copper line up vertically). The game's own "Sell Price:" line is restyled into the block.
--   Sell Price                 2s 60c
--   Auction                   18s 00c      lowest buyout
--     25%                     20s 40c      quartiles of the unit price (weighted by quantity)
--     50%                     23s 00c
--     75%                     27s 60c
-- Mob tooltips show the loot per kill and, per drop, its chance plus one vendor and one auction
-- unit price in aligned columns (public database weighted with your own kills, see Farm.lua):
--   Loot per kill (database + 12 kills)            12s 40c
--     Drops                       Chance   Vendor       AH
--     Cracked Basilisk Scale         58%   1s 05c        -
--     Basilisk Heart                 21%     45c   3s 10c
local _, ns = ...

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local SELL_LINE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice
local MAX_DROP_LINES = 6
local COL_CHANCE, COL_VENDOR, COL_AH = 44, 84, 88 -- pixel widths of the drop columns
local NONE = "|cff7f7f7f-|r"

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

local function MoneyRow(tooltip, label, copper, shade)
	shade = shade or 1
	tooltip:AddDoubleLine(label, ns.CoinString(copper), shade, shade, shade, 1, 1, 1)
end

-- Turns the default "Sell Price: 2s 60c" line into an aligned "Sell Price ... 2s 60c" row.
local function RestyleSellLine(tooltip, copper)
	local name = tooltip.GetName and tooltip:GetName()
	if not name or not tooltip.NumLines then return false end
	local label = SELL_PRICE or "Sell Price"
	local prefix = label .. ":"
	for i = tooltip:NumLines(), 1, -1 do
		local left = _G[name .. "TextLeft" .. i]
		local right = _G[name .. "TextRight" .. i]
		local text = left and left:GetText()
		if right and type(text) == "string" and not ns.IsSecret(text)
			and text:sub(1, #prefix) == prefix and #text > #prefix + 1 then
			left:SetText(label)
			right:SetText(ns.CoinString(copper))
			right:SetTextColor(1, 1, 1)
			right:Show()
			return true
		end
	end
	return false
end

local function OnItemTooltip(tooltip, data)
	if not ns.db or not tooltip or tooltip.isShopping or not tooltip.AddDoubleLine then return end
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
	local changed = false

	local sellPrice = select(11, GetItemInfo(link or itemID))
	if sellPrice and sellPrice > 0 then
		if HasSellPriceLine(data) then
			changed = RestyleSellLine(tooltip, sellPrice * count) or changed
		else
			MoneyRow(tooltip, SELL_PRICE or "Sell Price", sellPrice * count)
			changed = true
		end
	end

	local bound = loc and C_Item.IsBound and C_Item.IsBound(loc)
	local stats = (not bound) and ns:GetStats(itemID)
	if stats then
		MoneyRow(tooltip, "Auction", stats[1] * count)
		MoneyRow(tooltip, "  25%", stats[2] * count, 0.8)
		MoneyRow(tooltip, "  50%", stats[3] * count, 0.8)
		MoneyRow(tooltip, "  75%", stats[4] * count, 0.8)
		changed = true
	end
	if changed and tooltip.Show then tooltip:Show() end
end

local function KillsLabel(kills, source)
	if source == "database" then return "database" end
	if source == "both" then return ("database + %d kills"):format(kills) end
	return ("%d kills"):format(kills)
end

local function Percent(p)
	local pct = p * 100
	return pct >= 10 and ("%d%%"):format(math.floor(pct + 0.5)) or ("%.1f%%"):format(pct)
end

local function OnUnitTooltip(tooltip, data)
	if not ns.db or not ns.settings.mobTooltips or not tooltip or not tooltip.AddDoubleLine or not ns.Farm then return end
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
	if mob and not mob.n and unit and not ns.IsSecret(unit) then
		local name = UnitName(unit)
		if name and not ns.IsSecret(name) then mob.n = name end
	end

	local drops, money, world, kills, source = ns.Farm:DropTable(npcID)
	if not drops then return end
	local value = ns.Farm:MobValue(npcID) or 0
	MoneyRow(tooltip, ("Loot per kill (%s)"):format(KillsLabel(kills, source)), value)
	if #drops > 0 then
		-- One vendor and one auction unit price per item, in aligned columns.
		local header = ns.AlignColumns({ { "Chance", COL_CHANCE }, { "Vendor", COL_VENDOR }, { "AH", COL_AH } })
		tooltip:AddDoubleLine("  Drops", header, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
	end
	for i = 1, math.min(#drops, MAX_DROP_LINES) do
		local d = drops[i]
		local entry = ns.FarmDB and ns.FarmDB.items[d.id]
		local vendor = entry and entry[1] or ns:GetSellPrice(d.id)
		local ah = ns:GetAHPrice(d.id)
		local cells = ns.AlignColumns({
			{ Percent(d.chance), COL_CHANCE },
			{ vendor > 0 and ns.CoinString(vendor) or NONE, COL_VENDOR },
			{ ah and ns.CoinString(ah) or NONE, COL_AH },
		})
		tooltip:AddDoubleLine("  " .. ns.Farm:ItemName(d.id), cells, 1, 1, 1, 1, 1, 1)
	end
	if world > 0.0005 then
		tooltip:AddDoubleLine("  Random world drops", Percent(world), 1, 1, 1, 1, 1, 1)
	end
	if money > 0 then MoneyRow(tooltip, "  " .. (MONEY or "Money"), money) end
	local skinning = ns.Farm:GetProfessions().skinning
	local skin = ns.Farm:SkinValue(npcID, skinning)
	if skin > 0 then MoneyRow(tooltip, "  Skinning (you can skin it)", skin) end
	if tooltip.Show then tooltip:Show() end
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

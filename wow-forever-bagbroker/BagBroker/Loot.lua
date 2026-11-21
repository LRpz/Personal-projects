-- BagBroker: loot learning and full-bag replacement.
--
-- Loot learning: there is no API that exposes loot tables, and Forever adds content that no
-- vanilla database covers, so drop rates are learned from your own kills (shared account-wide).
--   * Every looted corpse counts as one kill of its NPC (deduplicated by GUID, AoE loot aware).
--   * Targeted, tapped mobs that die with an empty corpse also count as a kill, so the average
--     value per kill is not inflated by only seeing corpses that had loot.
--   * The kill position feeds the farming heatmap (cells of a 60 x 40 grid per map).
--
-- Replacement: when the bags are full and a loot slot cannot be stacked anywhere, the cheapest
-- unprotected bag item is chosen if the loot is worth more. Destroying items requires a click or
-- key press on Mainline clients, so a small prompt offers the swap; one click (or the key
-- binding, or "/click BagBrokerReplaceButton" in a macro) destroys that item and takes the loot.
local _, ns = ...

local Loot = { seen = {}, pendingDeath = {} }
ns.Loot = Loot

local HEAT_W, HEAT_H = 60, 40
ns.HEAT_W, ns.HEAT_H = HEAT_W, HEAT_H

local SLOT_ITEM = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or 1
local SLOT_MONEY = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or 2
local SEEN_TTL = 900

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function ItemIDFromLink(link)
	if type(link) ~= "string" then return nil end
	return tonumber(link:match("item:(%d+)"))
end

local function PlayerMapPosition()
	if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return nil end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return nil end
	local x, y = pos:GetXY()
	if not x or ns.IsSecret(x) or x <= 0 or y <= 0 or x >= 1 or y >= 1 then return nil end
	return mapID, x, y
end

-- Parses the localized coin text of a money loot slot ("1 Gold 2 Silver 3 Copper").
local function ParseCoinText(text)
	if type(text) ~= "string" then return 0 end
	local function amount(fmt, multiplier)
		if not fmt then return 0 end
		local pattern = fmt:gsub("%%d", "(%%d+)")
		local n = text:match(pattern)
		return (tonumber(n) or 0) * multiplier
	end
	return amount(GOLD_AMOUNT, 10000) + amount(SILVER_AMOUNT, 100) + amount(COPPER_AMOUNT, 1)
end
Loot.ParseCoinText = ParseCoinText

function Loot:PruneSeen()
	local now = GetTime()
	for guid, t in pairs(self.seen) do
		if now - t > SEEN_TTL then self.seen[guid] = nil end
	end
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
function Loot:AddHeat(mapID, x, y, npcID)
	local map = ns.db.heat[mapID]
	if not map then
		map = {}
		ns.db.heat[mapID] = map
	end
	local cx = math.min(HEAT_W - 1, math.floor(x * HEAT_W))
	local cy = math.min(HEAT_H - 1, math.floor(y * HEAT_H))
	local cellIndex = cy * HEAT_W + cx
	local cell = map[cellIndex]
	if not cell then
		cell = {}
		map[cellIndex] = cell
	end
	cell[npcID] = (cell[npcID] or 0) + 1
end

-- rec = { money = copper, items = { [itemID] = quantity } }
function Loot:RecordKill(guid, npcID, rec, mapID, x, y, name)
	self.seen[guid] = GetTime()
	local mob = ns.db.mobs[npcID]
	if not mob then
		mob = { k = 0, m = 0, i = {} }
		ns.db.mobs[npcID] = mob
	end
	mob.k = mob.k + 1
	mob.m = (mob.m or 0) + (rec.money or 0)
	if name and not mob.n then mob.n = name end
	for itemID, qty in pairs(rec.items or {}) do
		local entry = mob.i[itemID]
		if not entry then
			entry = { 0, 0 }
			mob.i[itemID] = entry
		end
		entry[1] = entry[1] + 1
		entry[2] = entry[2] + qty
	end
	if mapID then self:AddHeat(mapID, x, y, npcID) end
	ns:Fire("KILL_RECORDED", mapID, npcID)
end

function Loot:RecordLootWindow()
	if IsFishingLoot and IsFishingLoot() then return end
	if IsStealthed and IsStealthed() then return end -- pick pocketing: the mob is still alive
	local numSlots = GetNumLootItems() or 0
	if numSlots == 0 then return end
	self:PruneSeen()

	local perSource, order = {}, {}
	for slot = 1, numSlots do
		local slotType = GetLootSlotType(slot)
		local link = (slotType == SLOT_ITEM) and GetLootSlotLink(slot) or nil
		local _, slotText = GetLootSlotInfo(slot)
		local sources = { GetLootSourceInfo(slot) }
		local moneySources, moneyTotal = 0, 0
		for j = 1, #sources, 2 do
			local guid, qty = sources[j], sources[j + 1]
			local npcID = ns.NpcIDFromGUID(guid)
			if npcID and not self.seen[guid] then
				local rec = perSource[guid]
				if not rec then
					rec = { npcID = npcID, money = 0, items = {} }
					perSource[guid] = rec
					order[#order + 1] = guid
				end
				if slotType == SLOT_MONEY then
					rec.money = rec.money + (tonumber(qty) or 0)
					moneySources = moneySources + 1
					moneyTotal = moneyTotal + (tonumber(qty) or 0)
					rec.moneyShare = true
				elseif slotType == SLOT_ITEM then
					local itemID = ItemIDFromLink(link)
					if itemID then
						rec.items[itemID] = (rec.items[itemID] or 0) + (tonumber(qty) or 1)
						local name, _, quality = GetItemInfo(link)
						if name then ns.db.names[itemID] = ns.QualityColor(quality) .. name .. "|r" end
					end
				end
			end
		end
		-- Some clients report a zero quantity for coin slots: split the coin text evenly instead.
		if slotType == SLOT_MONEY and moneySources > 0 and moneyTotal == 0 then
			local share = math.floor(ParseCoinText(slotText) / moneySources)
			for j = 1, #sources, 2 do
				local rec = perSource[sources[j]]
				if rec and rec.moneyShare then rec.money = rec.money + share end
			end
		end
		for _, rec in pairs(perSource) do rec.moneyShare = nil end
	end

	if #order == 0 then return end
	local mapID, x, y = PlayerMapPosition()
	local targetGUID = UnitGUID("target")
	local targetName = UnitName("target")
	if ns.IsSecret(targetGUID) or ns.IsSecret(targetName) then targetGUID, targetName = nil, nil end
	for _, guid in ipairs(order) do
		local rec = perSource[guid]
		local name = (targetGUID == guid) and targetName or nil
		self:RecordKill(guid, rec.npcID, rec, mapID, x, y, name)
	end
end

-- Empty corpses: a tapped target dies and has nothing to loot.
function Loot:OnTargetHealth()
	local unit = "target"
	if not UnitExists(unit) then return end
	local dead = UnitIsDead(unit)
	if ns.IsSecret(dead) or not dead then return end
	local guid = UnitGUID(unit)
	local npcID = ns.NpcIDFromGUID(guid)
	if not npcID or self.seen[guid] or self.pendingDeath[guid] then return end
	local tapDenied = UnitIsTapDenied(unit)
	if ns.IsSecret(tapDenied) or tapDenied or UnitIsPlayer(unit) or not UnitCanAttack("player", unit) then return end
	local name = UnitName(unit)
	if ns.IsSecret(name) then name = nil end
	local mapID, x, y = PlayerMapPosition()
	self.pendingDeath[guid] = true
	C_Timer.After(2, function()
		self.pendingDeath[guid] = nil
		if self.seen[guid] or not CanLootUnit then return end
		local ok, hasLoot = pcall(CanLootUnit, guid)
		if ok and hasLoot == false then
			self:RecordKill(guid, npcID, { money = 0, items = {} }, mapID, x, y, name)
		end
	end)
end

---------------------------------------------------------------------------
-- Full-bag replacement
---------------------------------------------------------------------------
function Loot:CanStack(itemID, quantity)
	local maxStack = (C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID)) or 1
	if maxStack <= 1 then return false end
	local fits = false
	ns:ForEachBagSlot(function(bag, slot)
		local c = C_Container.GetContainerItemInfo(bag, slot)
		if c and c.itemID == itemID and (c.stackCount or 0) + quantity <= maxStack then
			fits = true
			return false
		end
	end)
	return fits
end

-- Items that are never destroyed to make room.
function Loot:IsProtected(info)
	if not info.loaded or info.isLocked then return true end
	if ns.db.keep[info.itemID] then return true end
	if info.isQuest or info.classID == 1 then return true end           -- quest items, containers
	if info.inEquipmentSet then return true end
	if info.hasNoValue and not ns:GetStats(info.itemID) then return true end -- hearthstone, keys, ...
	if info.isEquipment and (info.quality or 0) >= 2 and (info.isBound or info.isBoE) then return true end
	if (info.quality or 0) >= 4 then return true end
	return false
end

function Loot:SlotValue(info)
	return ns:GetUnitValue(info.itemID, info.sellPrice, info.tradeable) * (info.count or 1)
end

function Loot:FindCheapestSlot()
	local best
	ns:ForEachBagSlot(function(bag, slot)
		local info = ns:GetSlotInfo(bag, slot)
		if info and not self:IsProtected(info) then
			info.value = self:SlotValue(info)
			if not best or info.value < best.value then best = info end
		end
	end)
	return best
end

function Loot:BestBlockedLoot()
	local best
	for slot = 1, GetNumLootItems() or 0 do
		if GetLootSlotType(slot) == SLOT_ITEM then
			local _, _, quantity, currencyID, _, locked, isQuestItem = GetLootSlotInfo(slot)
			local link = GetLootSlotLink(slot)
			local itemID = ItemIDFromLink(link)
			if itemID and not locked and not currencyID then
				quantity = (quantity and quantity > 0) and quantity or 1
				if not self:CanStack(itemID, quantity) then
					local value = isQuestItem and math.huge or ns:GetUnitValue(itemID, nil, true) * quantity
					if not best or value > best.value then
						best = { slot = slot, link = link, itemID = itemID, value = value }
					end
				end
			end
		end
	end
	return best
end

local function LootValueText(loot)
	return loot.value == math.huge and "quest item" or ns.FormatMoney(loot.value)
end

-- Finds the best swap (most valuable blocked loot against the cheapest bag item) and offers it.
-- Destroying an item needs a hardware event on Mainline clients (one item per click or key
-- press), so the swap itself runs from the prompt button, its key binding or a /click macro.
function Loot:Evaluate()
	self.offer = nil
	if ns.settings.replaceLoot and self.lootOpen and ns:FreeBagSlots() == 0 then
		local loot = self:BestBlockedLoot()
		local victim = loot and self:FindCheapestSlot()
		if victim and victim.value < loot.value then
			self.offer = { loot = loot, victim = victim }
		end
	end
	self:UpdatePrompt()
end

-- Runs from a click or key press.
function Loot:DoReplace()
	local offer = self.offer
	if not offer or not self.lootOpen or CursorHasItem() then return end
	local victim, loot = offer.victim, offer.loot
	local current = C_Container.GetContainerItemInfo(victim.bag, victim.slot)
	if not current or current.itemID ~= victim.itemID or GetLootSlotLink(loot.slot) ~= loot.link then
		self:Evaluate()
		return
	end
	C_Container.PickupContainerItem(victim.bag, victim.slot)
	if not CursorHasItem() then return end
	DeleteCursorItem()
	if CursorHasItem() then
		ClearCursor()
		ns:Print("The game blocked destroying the item. Use the Replace button or its key binding.")
		return
	end
	ns:Print(("Bags full: destroyed %s (%s) to loot %s (%s)."):format(
		victim.link or "?", ns.FormatMoney(victim.value), loot.link or "?", LootValueText(loot)))
	self.offer = nil
	self:UpdatePrompt()
	C_Timer.After(0.3, function()
		if not self.lootOpen then return end
		LootSlot(loot.slot)
		C_Timer.After(0.5, function() self:Evaluate() end)
	end)
end

function BagBroker_ReplaceLoot()
	Loot:DoReplace()
end

function Loot:CreatePrompt()
	if self.prompt then return self.prompt end
	local f = ns:CreateWindow("BagBrokerReplacePrompt", UIParent, "Bags full")
	f:SetSize(360, 96)
	f:SetFrameStrata("DIALOG")
	f:SetPoint("TOP", UIParent, "TOP", 0, -140)
	f:Hide()
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.text:SetPoint("TOPLEFT", 14, -30)
	f.text:SetPoint("TOPRIGHT", -14, -30)
	f.text:SetJustifyH("LEFT")
	f.text:SetHeight(32)
	-- Named so that a macro can use "/click BagBrokerReplaceButton".
	local b = CreateFrame("Button", "BagBrokerReplaceButton", f, "UIPanelButtonTemplate")
	b:SetSize(110, 22)
	b:SetPoint("BOTTOM", 0, 10)
	b:SetText("Replace")
	b:SetScript("OnClick", function() Loot:DoReplace() end)
	f.button = b
	self.prompt = f
	return f
end

function Loot:UpdatePrompt()
	local offer = self.offer
	if not offer then
		if self.prompt then self.prompt:Hide() end
		return
	end
	local f = self:CreatePrompt()
	f.text:SetText(("Destroy %s (%s) to loot %s (%s)?"):format(
		offer.victim.link or "?", ns.FormatMoney(offer.victim.value), offer.loot.link or "?", LootValueText(offer.loot)))
	if LootFrame and LootFrame.IsShown and LootFrame:IsShown() then
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", LootFrame, "TOPRIGHT", 8, 0)
	end
	f:Show()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- LOOT_READY arrives before auto loot empties the window; GUID deduplication makes the
-- second call from LOOT_OPENED harmless.
ns:RegisterEvent("LOOT_READY", function()
	Loot:RecordLootWindow()
end)

ns:RegisterEvent("LOOT_OPENED", function()
	Loot.lootOpen = true
	Loot:RecordLootWindow()
	-- Give auto loot a moment to take everything that fits before looking at leftovers.
	C_Timer.After(0.4, function() Loot:Evaluate() end)
end)

ns:RegisterEvent("LOOT_SLOT_CLEARED", function()
	if Loot.lootOpen then C_Timer.After(0.2, function() Loot:Evaluate() end) end
end)

ns:RegisterEvent("LOOT_CLOSED", function()
	Loot.lootOpen = false
	Loot.offer = nil
	Loot:UpdatePrompt()
end)

ns:RegisterEvent("UNIT_HEALTH", function(_, unit)
	if unit == "target" then Loot:OnTargetHealth() end
end)

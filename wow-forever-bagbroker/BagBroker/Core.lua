-- BagBroker: namespace, saved variables, event dispatch and item helpers.
local ADDON_NAME, ns = ...

ns.VERSION = "1.0.0"
ns.AH_CUT = 0.05                 -- auction house cut taken from a successful sale
ns.SCAN_COOLDOWN = 15 * 60       -- server throttle on full auction house scans
ns.STAT = { min = 1, p25 = 2, p50 = 3, p75 = 4, qty = 5, time = 6 }

local BIND_ON_EQUIP = (Enum and Enum.ItemBind and Enum.ItemBind.OnEquip) or 2
local BIND_QUEST = (Enum and Enum.ItemBind and Enum.ItemBind.Quest) or 4
local CLASS_QUEST = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local issecret = issecretvalue or function() return false end

-- Midnight-era clients can hand out "secret" values in restricted contexts;
-- any value for which this returns true must not be compared or stored.
function ns.IsSecret(value)
	return value ~= nil and issecret(value) and true or false
end

ns.defaults = {
	autoSell = true,            -- sell to the vendor automatically when vendor >= auction value
	compare = "p50",            -- auction statistic used for vendor-versus-auction decisions
	sellSoulboundGear = true,   -- sell soulbound gear that is not an upgrade (quality <= soulboundMaxQuality)
	soulboundMaxQuality = 2,
	replaceLoot = true,         -- free a bag slot for more valuable loot when bags are full
	autoScan = true,            -- start a full auction scan when the auction house opens (if allowed)
	panelAutoShow = true,       -- open the selling panel next to the auction house window
	wallFraction = 0.10,        -- cheaper listings below this share of supply are treated as a thin layer
	shareFactions = false,      -- share auction data between factions of the same realm
	mobTooltips = true,         -- learned loot table lines on mob tooltips
	showMinimap = true,
	minimapAngle = 215,
	durations = { consumable = 1, trade = 1, gear = 2, rare = 3, other = 2 }, -- 1 = 12h, 2 = 24h, 3 = 48h
	priorKills = 25,            -- weight of the public database, in kills, against personal kills
	farmBelow = 6,              -- farming spots: creatures down to this many levels below yours
	farmAbove = 1,              -- ... and up to this many levels above yours
	debug = false,
}

---------------------------------------------------------------------------
-- Events and internal callbacks
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers, callbacks = {}, {}
local safecall = securecallfunction or function(fn, ...) return fn(...) end

function ns:RegisterEvent(event, fn)
	local list = handlers[event]
	if not list then
		local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
		if not ok then
			ns:Debug("event not available: " .. event)
			return
		end
		list = {}
		handlers[event] = list
	end
	list[#list + 1] = fn
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		safecall(list[i], event, ...)
	end
end)

function ns:On(message, fn)
	callbacks[message] = callbacks[message] or {}
	table.insert(callbacks[message], fn)
end

function ns:Fire(message, ...)
	local list = callbacks[message]
	if not list then return end
	for i = 1, #list do
		safecall(list[i], ...)
	end
end

---------------------------------------------------------------------------
-- Saved variables (account-wide: every character reads and writes the same tables)
---------------------------------------------------------------------------
local function CopyDefaults(src, dst)
	for key, value in pairs(src) do
		if type(value) == "table" then
			if type(dst[key]) ~= "table" then dst[key] = {} end
			CopyDefaults(value, dst[key])
		elseif dst[key] == nil then
			dst[key] = value
		end
	end
	return dst
end

function ns:InitDB()
	BagBrokerDB = BagBrokerDB or {}
	local db = BagBrokerDB
	db.version = 1
	db.settings = CopyDefaults(ns.defaults, db.settings or {})
	db.realms = db.realms or {}   -- [realmKey] = { items = { [itemID] = {min,p25,p50,p75,qty,time} }, lastScan, lastScanDone }
	db.keep = db.keep or {}       -- [itemID] = true: never vendor, never delete
	db.junk = db.junk or {}       -- [itemID] = true: always vendor
	db.mobs = db.mobs or {}       -- [npcID] = { k = kills, m = copper, n = name, i = { [itemID] = {drops, quantity} } }
	db.heat = db.heat or {}       -- [mapID] = { [cell] = { [npcID] = kills } }
	db.names = db.names or {}     -- [itemID] = colored item name, cached at loot time
	ns.db = db
	ns.settings = db.settings
	ns.realmData = nil
end

ns:RegisterEvent("ADDON_LOADED", function(_, name)
	if name ~= ADDON_NAME then return end
	ns:InitDB()
	ns:Fire("DB_READY")
end)

ns:RegisterEvent("AUCTION_HOUSE_SHOW", function() ns.ahOpen = true end)
ns:RegisterEvent("AUCTION_HOUSE_CLOSED", function() ns.ahOpen = false end)
ns:RegisterEvent("MERCHANT_SHOW", function() ns.merchantOpen = true end)
ns:RegisterEvent("MERCHANT_CLOSED", function() ns.merchantOpen = false end)

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------
function ns:Print(msg)
	local frame = DEFAULT_CHAT_FRAME
	if frame then frame:AddMessage("|cff33ff99BagBroker|r: " .. tostring(msg)) end
end

function ns:Debug(msg)
	if ns.settings and ns.settings.debug then ns:Print("|cff999999" .. tostring(msg) .. "|r") end
end

-- Money text identical to the default "Sell Price:" tooltip line.
function ns.FormatMoney(copper)
	copper = math.floor((copper or 0) + 0.5)
	if MoneyFormatterUtil and MoneyFormatterUtil.FormatMoney and GameTooltipMoneyFormat then
		local ok, text = pcall(MoneyFormatterUtil.FormatMoney, copper, GameTooltipMoneyFormat)
		if ok and type(text) == "string" and text ~= "" then return text end
	end
	if GetMoneyString then return GetMoneyString(copper, true) end
	return ns.Pricing.FormatMoneyText(copper)
end

-- Money for aligned columns: lower denominations are always present (zero-padded and dimmed),
-- so right-aligned values line up gold under gold, silver under silver, copper under copper.
local COIN = {
	g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
ns.COIN = COIN
local DIM = "|cff7f7f7f"

local function Pad(n)
	if n == 0 then return DIM .. "00|r" end
	return ("%02d"):format(n)
end

function ns.SplitMoney(copper)
	copper = math.floor((copper or 0) + 0.5)
	return math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
end

function ns.CoinString(copper)
	local g, s, c = ns.SplitMoney(copper)
	if g > 0 then
		local gold = BreakUpLargeNumbers and BreakUpLargeNumbers(g) or tostring(g)
		return gold .. COIN.g .. " " .. Pad(s) .. COIN.s .. " " .. Pad(c) .. COIN.c
	end
	if s > 0 then return s .. COIN.s .. " " .. Pad(c) .. COIN.c end
	return c .. COIN.c
end

-- Fixed-width columns inside one tooltip text: each cell is right-aligned within its width by
-- measuring it with the tooltip font and padding it with a transparent spacer of the missing width.
local SPACER = "Interface\\AddOns\\BagBroker\\spacer"
local measure
local function TextWidth(text)
	if not measure then
		measure = UIParent:CreateFontString(nil, "OVERLAY", "GameTooltipText")
		measure:Hide()
	end
	measure:SetText(text)
	return measure:GetStringWidth() or 0
end

function ns.AlignColumns(cells)
	local out = {}
	for _, cell in ipairs(cells) do
		local pad = math.floor(cell[2] - TextWidth(cell[1]) + 0.5)
		if pad > 0 then out[#out + 1] = ("|T%s:1:%d|t"):format(SPACER, pad) end
		out[#out + 1] = cell[1]
	end
	return table.concat(out)
end

-- Three right-aligned columns (gold, silver, copper) for lists such as the selling panel.
function ns.CreateMoneyColumns(parent, width)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, 14)
	local copperW, silverW = 28, 28
	local function Column(w, anchor, offset)
		local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetWidth(w)
		fs:SetJustifyH("RIGHT")
		fs:SetPoint("RIGHT", anchor or f, anchor and "LEFT" or "RIGHT", offset or 0, 0)
		return fs
	end
	f.c = Column(copperW)
	f.s = Column(silverW, f.c, 0)
	f.g = Column(width - copperW - silverW, f.s, 0)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.text:SetPoint("RIGHT")
	f.text:SetJustifyH("RIGHT")
	-- color: optional "|cffrrggbb" prefix for the digits (coin icons keep their own colours).
	function f:SetAmount(copper, color)
		local g, s, c = ns.SplitMoney(copper)
		local function Digits(n, padded)
			if padded and n == 0 then return DIM .. "00|r" end
			local text = padded and ("%02d"):format(n) or tostring(n)
			return color and (color .. text .. "|r") or text
		end
		local gold = g > 0 and (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or tostring(g)) or nil
		self.g:SetText(gold and ((color and (color .. gold .. "|r") or gold) .. COIN.g) or "")
		self.s:SetText((g > 0 or s > 0) and (Digits(s, g > 0) .. COIN.s) or "")
		self.c:SetText(Digits(c, g > 0 or s > 0) .. COIN.c)
		self.text:Hide()
		self.g:Show()
		self.s:Show()
		self.c:Show()
	end
	function f:SetLabel(text)
		self.g:Hide(); self.s:Hide(); self.c:Hide()
		self.text:SetText(text)
		self.text:Show()
	end
	return f
end

-- Adds a white line exactly like GameTooltip_OnTooltipAddMoney does for the sell price.
function ns.AddTooltipLine(tooltip, text)
	if GameTooltip_AddHighlightLine then
		GameTooltip_AddHighlightLine(tooltip, text)
	else
		tooltip:AddLine(text, 1, 1, 1)
	end
end

function ns.QualityColor(quality)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
	if c and c.hex then return c.hex end
	return "|cffffffff"
end

-- Shared window constructor with a native look; falls back to a plain backdrop.
function ns:CreateWindow(name, parent, title)
	local ok, frame = pcall(CreateFrame, "Frame", name, parent, "BasicFrameTemplateWithInset")
	if not ok or not frame then
		frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
		if frame.SetBackdrop then
			frame:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 8, right = 8, top = 8, bottom = 8 },
			})
		end
	end
	if not frame.CloseButton then
		local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 2, 2)
		frame.CloseButton = close
	end
	if not frame.TitleText then
		local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		text:SetPoint("TOP", 0, -6)
		frame.TitleText = text
	end
	frame.TitleText:SetText(title)
	return frame
end

---------------------------------------------------------------------------
-- Auction statistics (per realm, shared by all characters on the account)
---------------------------------------------------------------------------
function ns:GetRealmKey()
	local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "Unknown"
	if self.settings.shareFactions then return realm end
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	return realm .. "-" .. (faction or "Neutral")
end

function ns:GetRealmData()
	if self.realmData then return self.realmData end
	local key = self:GetRealmKey()
	local data = self.db.realms[key]
	if not data then
		data = { items = {}, lastScan = 0, lastScanDone = 0 }
		self.db.realms[key] = data
	end
	self.realmData = data
	return data
end

function ns:GetStats(itemID)
	if not itemID or not self.db then return nil end
	return self:GetRealmData().items[itemID]
end

function ns:SetStats(itemID, minPrice, p25, p50, p75, quantity, when)
	local function r(v) return math.floor(v + 0.5) end
	self:GetRealmData().items[itemID] = { r(minPrice), r(p25), r(p50), r(p75), quantity, when or time() }
end

-- Unit auction price for the configured statistic (default: median).
function ns:GetAHPrice(itemID, statName)
	local stats = self:GetStats(itemID)
	if not stats then return nil end
	return stats[ns.STAT[statName or self.settings.compare] or ns.STAT.p50]
end

-- What a sale at the reference price would actually pay after the auction house cut.
function ns:GetAHNet(itemID)
	local price = self:GetAHPrice(itemID)
	if not price then return nil end
	return math.floor(price * (1 - ns.AH_CUT))
end

function ns:GetSellPrice(itemID)
	local sellPrice = select(11, GetItemInfo(itemID))
	if sellPrice == nil and C_Item and C_Item.RequestLoadItemDataByID then
		C_Item.RequestLoadItemDataByID(itemID)
	end
	return sellPrice or 0
end

-- Best realistic unit value of an item: vendor price or auction net, whichever is higher.
function ns:GetUnitValue(itemID, sellPrice, tradeable)
	local value = sellPrice or self:GetSellPrice(itemID)
	if tradeable ~= false then
		local net = self:GetAHNet(itemID)
		if net and net > value then value = net end
	end
	return value
end

---------------------------------------------------------------------------
-- Bags and item classification
---------------------------------------------------------------------------
function ns:ForEachBagSlot(fn)
	local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
	for bag = 0, last do
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, slots do
			if fn(bag, slot) == false then return end
		end
	end
end

function ns:FreeBagSlots()
	if C_Container.CalculateTotalNumberOfFreeBagSlots then
		return C_Container.CalculateTotalNumberOfFreeBagSlots()
	end
	local free = 0
	local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
	for bag = 0, last do
		free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
	end
	return free
end

local NON_GEAR_SLOTS = {
	[""] = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_NON_EQUIP = true, INVTYPE_BAG = true,
	INVTYPE_QUIVER = true, INVTYPE_AMMO = true, INVTYPE_BODY = true, INVTYPE_TABARD = true,
}

-- Collects everything the selling and replacement logic needs about one bag slot.
function ns:GetSlotInfo(bag, slot)
	local c = C_Container.GetContainerItemInfo(bag, slot)
	if not c or not c.itemID then return nil end
	local info = {
		bag = bag, slot = slot, itemID = c.itemID, link = c.hyperlink, count = c.stackCount or 1,
		quality = c.quality, isBound = c.isBound and true or false, hasNoValue = c.hasNoValue and true or false,
		isLocked = c.isLocked, icon = c.iconFileID, name = c.itemName,
	}
	local name, _, quality, itemLevel, _, _, _, maxStack, equipLoc, _, sellPrice, classID, subclassID, bindType =
		GetItemInfo(c.hyperlink or c.itemID)
	if not name then
		if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(c.itemID) end
		info.loaded = false
		return info
	end
	info.loaded = true
	info.name = name
	info.quality = info.quality or quality or 1
	info.sellPrice = sellPrice or 0
	info.classID, info.subclassID, info.bindType = classID, subclassID, bindType
	info.equipLoc = equipLoc or ""
	info.maxStack = maxStack or 1
	info.ilvl = (C_Item.GetDetailedItemLevelInfo and c.hyperlink and C_Item.GetDetailedItemLevelInfo(c.hyperlink)) or itemLevel or 0

	local questInfo = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
	info.isQuest = (classID == CLASS_QUEST) or (bindType == BIND_QUEST)
		or (questInfo ~= nil and (questInfo.isQuestItem or questInfo.questID ~= nil)) or false

	info.isEquipment = (classID == 2 or classID == 4) and not NON_GEAR_SLOTS[info.equipLoc]
	if C_Container.GetContainerItemEquipmentSetInfo then
		info.inEquipmentSet = C_Container.GetContainerItemEquipmentSetInfo(bag, slot) and true or false
	end
	if C_Container.GetContainerItemPurchaseInfo then
		local purchase = C_Container.GetContainerItemPurchaseInfo(bag, slot, false)
		info.isRefundable = purchase ~= nil and (purchase.refundSeconds or 0) > 0
	end
	info.isBoE = (not info.isBound) and bindType == BIND_ON_EQUIP
	info.tradeable = (not info.isBound) and not info.isQuest
	if ItemLocation and ItemLocation.CreateFromBagAndSlot then
		info.loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
	end
	return info
end

-- Duration category used by the auction panel.
function ns:GetCategory(classID, quality)
	if classID == 0 or classID == 5 or classID == 6 or classID == 8 then return "consumable" end
	if classID == 7 or classID == 3 then return "trade" end
	if classID == 2 or classID == 4 then
		return (quality or 0) >= 3 and "rare" or "gear"
	end
	if classID == 9 then return "rare" end
	return "other"
end

local EQUIP_SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18, 16 }, INVTYPE_RANGEDRIGHT = { 18, 16 }, INVTYPE_THROWN = { 18, 16 }, INVTYPE_RELIC = { 18 },
}

-- True when the item could still be worth equipping (unknown slot, empty slot, or higher item level).
function ns:IsPotentialUpgrade(info)
	local slots = EQUIP_SLOTS[info.equipLoc or ""]
	if not slots then return true end
	local lowest
	for _, slotID in ipairs(slots) do
		local link = GetInventoryItemLink("player", slotID)
		if not link then return true end
		local equipped = (C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)) or 0
		if not lowest or equipped < lowest then lowest = equipped end
	end
	return (info.ilvl or 0) > (lowest or 0)
end

-- Vendor decision for one bag slot. Returns shouldSell, reason.
function ns:ShouldVendor(info)
	if not info or not info.loaded then return false, "item data not cached" end
	if info.hasNoValue or (info.sellPrice or 0) <= 0 then return false, "no vendor value" end
	local id = info.itemID
	if self.db.keep[id] then return false, "on keep list" end
	if self.db.junk[id] then return true, "on junk list" end
	if info.isQuest then return false, "quest item" end
	if info.isRefundable then return false, "refundable purchase" end
	if info.isBoE then return false, "bind on equip" end

	local ahNet = (not info.isBound) and self:GetAHNet(id) or nil
	if info.quality == 0 then
		if ahNet and ahNet > info.sellPrice then return false, "auction pays more" end
		return true, "poor quality"
	end
	if info.isBound then
		if self.settings.sellSoulboundGear and info.isEquipment
			and (info.quality or 0) <= self.settings.soulboundMaxQuality
			and not info.inEquipmentSet and not self:IsPotentialUpgrade(info) then
			return true, "soulbound gear below equipped item level"
		end
		return false, "soulbound"
	end
	if not ahNet then return false, "no auction data" end
	if info.sellPrice >= ahNet then return true, "vendor price >= auction net" end
	return false, "auction pays more"
end

---------------------------------------------------------------------------
-- Mobs
---------------------------------------------------------------------------
function ns.NpcIDFromGUID(guid)
	if type(guid) ~= "string" or ns.IsSecret(guid) then return nil end
	local unitType, _, _, _, _, npcID = strsplit("-", guid)
	if unitType == "Creature" or unitType == "Vehicle" then return tonumber(npcID) end
	return nil
end

-- Expected copper per kill from your own drops, valued at max(vendor, auction net).
function ns:GetMobValue(mob)
	if not mob or (mob.k or 0) <= 0 then return 0 end
	if ns.Farm then return ns.Farm:PersonalValue(mob) or 0 end
	local total = mob.m or 0
	for itemID, entry in pairs(mob.i or {}) do
		total = total + (entry[2] or 0) * self:GetUnitValue(itemID, nil, true)
	end
	return total / mob.k
end

function ns:GetItemDisplayName(itemID)
	local name, _, quality = GetItemInfo(itemID)
	if name then return ns.QualityColor(quality) .. name .. "|r" end
	return self.db.names[itemID] or ("item:" .. itemID)
end

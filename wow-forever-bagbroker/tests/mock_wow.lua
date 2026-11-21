-- Minimal World of Warcraft API mock used to load and exercise BagBroker under plain Lua 5.1.
-- Only the behaviour the addon depends on is modelled; widgets accept any method call.
local M = { frames = {}, timers = {}, now = 1000, printed = {}, calls = {} }
_G.MOCK = M

local function noop() end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local Widget = {}
local function NewWidget(kind, name, parent)
	local w = setmetatable({ kind = kind, shown = true, scripts = {}, events = {}, text = "", checked = false,
		width = 140, height = 140, children = {}, parent = parent }, Widget)
	if name then _G[name] = w end
	return w
end
-- Plain data fields that real widgets do not have unless a template or the addon sets them.
local PROPERTIES = { isShopping = true, TitleText = true, CloseButton = true, lines = true, owner = true }
Widget.__index = function(self, key)
	local method = rawget(Widget, key)
	if method then return method end
	if PROPERTIES[key] then return nil end
	return noop
end
function Widget:CreateTexture() return NewWidget("Texture", nil, self) end
function Widget:CreateFontString() return NewWidget("FontString", nil, self) end
function Widget:SetScript(name, fn) self.scripts[name] = fn end
function Widget:GetScript(name) return self.scripts[name] end
function Widget:HookScript(name, fn) self.scripts[name] = fn end
function Widget:RegisterEvent(event)
	if event == "UNKNOWN_EVENT_FOR_TEST" then error("unknown event") end
	self.events[event] = true
end
function Widget:UnregisterEvent(event) self.events[event] = nil end
function Widget:Show()
	local was = self.shown
	self.shown = true
	if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Widget:Hide()
	local was = self.shown
	self.shown = false
	if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self.shown end
function Widget:IsVisible() return self.shown end
function Widget:SetText(t) self.text = t end
function Widget:GetText() return self.text end
function Widget:SetChecked(v) self.checked = v and true or false end
function Widget:GetChecked() return self.checked end
function Widget:GetWidth() return self.width end
function Widget:GetHeight() return self.height end
function Widget:SetWidth(w) self.width = w end
function Widget:SetHeight(h) self.height = h end
function Widget:SetSize(w, h) self.width, self.height = w, h end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetLeft() return 0 end
function Widget:GetTop() return 400 end
function Widget:GetCenter() return 0, 0 end
function Widget:HasFocus() return false end
function Widget:IsMouseOver() return false end
function Widget:GetFontString() return self.fontString or NewWidget("FontString", nil, self) end
function Widget:GetName() return self.name end
function Widget:SetEnabled(v) self.enabled = v end
function Widget:AddLine(text) table.insert(self.lines, text) end
function Widget:AddDoubleLine(l, r) table.insert(self.lines, l .. " || " .. r) end
function Widget:GetOwner() return self.owner end

function CreateFrame(kind, name, parent, template)
	if template == "BasicFrameTemplateWithInset" and M.noBasicTemplate then error("unknown template") end
	local w = NewWidget(kind, name, parent)
	w.name = name
	w.template = template
	table.insert(M.frames, w)
	return w
end

UIParent = NewWidget("Frame", "UIParent")
Minimap = NewWidget("Frame", "Minimap")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
GameTooltip.lines = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(M.printed, msg) end }
UISpecialFrames = {}
SlashCmdList = {}
GameFontHighlightSmall = {}

-- Fires an event on every mock frame that registered it.
function M.Fire(event, ...)
	for _, f in ipairs(M.frames) do
		if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end

---------------------------------------------------------------------------
-- Time and timers
---------------------------------------------------------------------------
function GetTime() return M.now end
local clock = 1700000000
function time() return clock end
function M.AdvanceClock(seconds) clock = clock + seconds end

C_Timer = {}
function C_Timer.After(delay, fn)
	table.insert(M.timers, { due = M.now + delay, fn = fn })
end
function C_Timer.NewTicker(interval, fn)
	local ticker = { cancelled = false }
	function ticker:Cancel() self.cancelled = true end
	local function tick()
		if ticker.cancelled then return end
		fn()
		if not ticker.cancelled then C_Timer.After(interval, tick) end
	end
	C_Timer.After(interval, tick)
	return ticker
end
-- Runs timers whose due time is reached while advancing the clock.
function M.Advance(seconds)
	local target = M.now + seconds
	for _ = 1, 100000 do
		table.sort(M.timers, function(a, b) return a.due < b.due end)
		local t = M.timers[1]
		if not t or t.due > target then break end
		table.remove(M.timers, 1)
		M.now = math.max(M.now, t.due)
		t.fn()
	end
	M.now = target
end

---------------------------------------------------------------------------
-- Lua/WoW helpers
---------------------------------------------------------------------------
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
function strsplit(sep, str)
	local out = {}
	for piece in (str .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
	return unpack(out)
end
function securecallfunction(fn, ...) return fn(...) end
function date(fmt, t) return os.date(fmt, t) end
function GetCursorPosition() return 0, 0 end
function IsShiftKeyDown() return M.shift or false end
function IsStealthed() return M.stealthed or false end
function IsFishingLoot() return false end
function GetMoney() return M.money or 10000000 end
function GetNormalizedRealmName() return "TestRealm" end
function GetRealmName() return "Test Realm" end
function UnitFactionGroup() return M.faction or "Alliance" end
function GetPlayerFacing() return 0 end
function IsControlKeyDown() return M.ctrl or false end
function UnitLevel() return M.level or 20 end
-- Professions: M.profs = { {name, rank, skillLine}, ... }
function GetProfessions()
	local p = M.profs or {}
	return p[1] and 1 or nil, p[2] and 2 or nil, nil, nil, nil
end
function GetProfessionInfo(index)
	local p = M.profs[index]
	return p[1], 1, p[2], 300, 0, 0, p[3]
end

SELL_PRICE = "Sell Price"
MONEY = "Money"
GOLD_AMOUNT = "%d Gold"
SILVER_AMOUNT = "%d Silver"
COPPER_AMOUNT = "%d Copper"
NUM_BAG_SLOTS = 4
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
ITEM_QUALITY_COLORS = {}
for q = 0, 7 do ITEM_QUALITY_COLORS[q] = { hex = "|cffq" .. q } end

-- Money formatter stand-in: the real one inserts coin textures.
MoneyFormatterUtil = { FormatMoney = function(copper) return "<" .. copper .. ">" end }
GameTooltipMoneyFormat = {}
function GameTooltip_AddHighlightLine(tooltip, text) tooltip:AddLine(text) end

Enum = {
	ItemBind = { None = 0, OnAcquire = 1, OnEquip = 2, OnUse = 3, Quest = 4 },
	ItemClass = { Questitem = 12 },
	ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 },
	AuctionHouseSortOrder = { Price = 0 },
	LootSlotType = { None = 0, Item = 1, Money = 2, Currency = 3 },
	TooltipDataType = { Item = 0, Unit = 2 },
	TooltipDataLineType = { SellPrice = 11 },
}

---------------------------------------------------------------------------
-- Items and bags
---------------------------------------------------------------------------
M.items = {}   -- [itemID] = { name, quality, ilvl, sellPrice, classID, bindType, equipLoc, maxStack }
M.bags = {}    -- [bag][slot] = { itemID, count, bound }
M.equipped = {} -- [slotID] = ilvl
M.cursor = nil

function M.Link(itemID) return "|Hitem:" .. itemID .. "::|h[" .. (M.items[itemID] and M.items[itemID].name or "?") .. "]|h" end
local function IDFrom(x)
	if type(x) == "number" then return x end
	return tonumber(tostring(x):match("item:(%d+)"))
end

C_Item = {}
function C_Item.GetItemInfo(x)
	local id = IDFrom(x)
	local it = id and M.items[id]
	if not it then return nil end
	return it.name, M.Link(id), it.quality, it.ilvl or 1, 1, "", "", it.maxStack or 1, it.equipLoc or "", 1,
		it.sellPrice or 0, it.classID or 15, 0, it.bindType or 0
end
function C_Item.GetItemInfoInstant(x) return IDFrom(x) end
function C_Item.GetDetailedItemLevelInfo(x)
	if type(x) == "string" and x:match("^equipped:") then return tonumber(x:match("equipped:(%d+)")) end
	local it = M.items[IDFrom(x)]
	return it and it.ilvl or 1
end
function C_Item.GetItemMaxStackSizeByID(id) return M.items[id] and M.items[id].maxStack or 1 end
function C_Item.RequestLoadItemDataByID() end
function C_Item.IsBound(loc)
	local s = M.bags[loc.bag] and M.bags[loc.bag][loc.slot]
	return s and s.bound or false
end
function C_Item.GetStackCount(loc)
	local s = M.bags[loc.bag] and M.bags[loc.bag][loc.slot]
	return s and s.count or 1
end
function GetItemInfo(x) return C_Item.GetItemInfo(x) end
function GetInventoryItemLink(_, slotID)
	local ilvl = M.equipped[slotID]
	return ilvl and ("equipped:" .. ilvl) or nil
end

ItemLocation = {}
function ItemLocation:CreateFromBagAndSlot(bag, slot)
	return { bag = bag, slot = slot, IsValid = function() return true end }
end

C_Container = {}
function C_Container.GetContainerNumSlots(bag) return M.bags[bag] and M.bags[bag].size or 0 end
function C_Container.GetContainerItemInfo(bag, slot)
	local s = M.bags[bag] and M.bags[bag][slot]
	if not s then return nil end
	local it = M.items[s.itemID] or {}
	return { itemID = s.itemID, stackCount = s.count or 1, hyperlink = M.Link(s.itemID), quality = it.quality,
		isBound = s.bound or false, hasNoValue = (it.sellPrice or 0) == 0, isLocked = s.locked or false,
		iconFileID = 1, itemName = it.name }
end
function C_Container.GetContainerItemQuestInfo(bag, slot)
	local s = M.bags[bag][slot]
	return { isQuestItem = s and s.quest or false }
end
function C_Container.GetContainerItemEquipmentSetInfo() return false, "" end
function C_Container.GetContainerItemPurchaseInfo() return nil end
function C_Container.CalculateTotalNumberOfFreeBagSlots()
	local free = 0
	for _, bag in pairs(M.bags) do
		for slot = 1, bag.size do if not bag[slot] then free = free + 1 end end
	end
	return free
end
function C_Container.UseContainerItem(bag, slot)
	table.insert(M.calls, { "UseContainerItem", bag, slot, M.bags[bag][slot] and M.bags[bag][slot].itemID })
	M.bags[bag][slot] = nil
end
function C_Container.PickupContainerItem(bag, slot)
	M.cursor = { bag = bag, slot = slot }
	table.insert(M.calls, { "PickupContainerItem", bag, slot })
end
function CursorHasItem() return M.cursor ~= nil end
function ClearCursor() M.cursor = nil end
function DeleteCursorItem()
	if M.deleteFails then return end
	table.insert(M.calls, { "DeleteCursorItem", M.cursor.bag, M.cursor.slot })
	M.bags[M.cursor.bag][M.cursor.slot] = nil
	M.cursor = nil
end

-- Bag helper: M.SetBags({ [0] = { size = 4, [1] = {itemID=..}, ... } })
function M.SetBags(bags)
	M.bags = bags
	for bag = 0, 5 do
		if not M.bags[bag] then M.bags[bag] = { size = 0 } end
	end
end

---------------------------------------------------------------------------
-- Units, loot, map
---------------------------------------------------------------------------
M.units = {}
function UnitGUID(unit) return M.units[unit] and M.units[unit].guid end
function UnitName(unit) return M.units[unit] and M.units[unit].name end
function UnitExists(unit) return M.units[unit] ~= nil end
function UnitIsDead(unit) return M.units[unit] and M.units[unit].dead or false end
function UnitIsTapDenied(unit) return M.units[unit] and M.units[unit].tapDenied or false end
function UnitIsPlayer() return false end
function UnitCanAttack() return true end
function CanLootUnit(guid) return M.lootable and M.lootable[guid] or false, true end

M.loot = {}
function GetNumLootItems() return #M.loot end
function GetLootSlotType(i) return M.loot[i].type end
function GetLootSlotLink(i) return M.loot[i].link end
function GetLootSlotInfo(i)
	local l = M.loot[i]
	return 1, l.text or (l.link and "item") or "", l.qty or 1, nil, 1, l.locked or false, l.quest or false
end
function GetLootSourceInfo(i) return unpack(M.loot[i].sources) end
function LootSlot(i)
	table.insert(M.calls, { "LootSlot", i })
end

C_Map = {}
M.position = { mapID = 1429, x = 0.505, y = 0.252 }
function C_Map.GetBestMapForUnit() return M.position.mapID end
function C_Map.GetPlayerMapPosition()
	return { GetXY = function() return M.position.x, M.position.y end }
end
function C_Map.GetMapInfo(mapID) return { name = "Zone" .. mapID } end
function C_Map.GetMapArtLayers() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end
function C_Map.GetMapArtLayerTextures() local t = {} for i = 1, 12 do t[i] = i end return t end

---------------------------------------------------------------------------
-- Auction house
---------------------------------------------------------------------------
M.replicate = {}      -- array (0-based use) of { itemID, count, buyout }
M.commodity = {}      -- [itemID] = array of CommoditySearchResultInfo
M.itemResults = {}    -- [itemID] = array of ItemSearchResultInfo
M.commodities = {}    -- [itemID] = true when the item is a commodity
M.throttleReady = true

C_AuctionHouse = {}
function C_AuctionHouse.ReplicateItems() table.insert(M.calls, { "ReplicateItems" }) end
function C_AuctionHouse.GetNumReplicateItems() return #M.replicate end
function C_AuctionHouse.GetReplicateItemInfo(index)
	local r = M.replicate[index + 1]
	if not r then return nil end
	return "n", 1, r.count, 1, true, 1, "", 0, 0, r.buyout, 0, nil, nil, "o", "o", 0, r.itemID, true
end
function C_AuctionHouse.IsThrottledMessageSystemReady() return M.throttleReady end
function C_AuctionHouse.SendSearchQuery(itemKey, sorts, separate)
	table.insert(M.calls, { "SendSearchQuery", itemKey.itemID, sorts[1].sortOrder, separate })
end
function C_AuctionHouse.GetNumCommoditySearchResults(id) return #(M.commodity[id] or {}) end
function C_AuctionHouse.GetCommoditySearchResultInfo(id, i) return M.commodity[id][i] end
function C_AuctionHouse.GetNumItemSearchResults(key) return #(M.itemResults[key.itemID] or {}) end
function C_AuctionHouse.GetItemSearchResultInfo(key, i) return M.itemResults[key.itemID][i] end
function C_AuctionHouse.IsSellItemValid() return true end
function C_AuctionHouse.GetItemCommodityStatus(loc)
	local s = M.bags[loc.bag][loc.slot]
	return M.commodities[s.itemID] and 2 or 1
end
function C_AuctionHouse.GetItemKeyFromItem(loc)
	local s = M.bags[loc.bag][loc.slot]
	return { itemID = s.itemID, itemLevel = M.items[s.itemID].ilvl or 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end
function C_AuctionHouse.GetAvailablePostCount(loc)
	local id = M.bags[loc.bag][loc.slot].itemID
	local n = 0
	for _, bag in pairs(M.bags) do
		for slot = 1, bag.size do if bag[slot] and bag[slot].itemID == id then n = n + (bag[slot].count or 1) end end
	end
	return n
end
function C_AuctionHouse.SupportsCopperValues() return not M.silverOnly end
function C_AuctionHouse.CalculateCommodityDeposit() return 100 end
function C_AuctionHouse.CalculateItemDeposit() return 100 end
function C_AuctionHouse.PostCommodity(loc, duration, quantity, unitPrice)
	table.insert(M.calls, { "PostCommodity", loc.bag, loc.slot, duration, quantity, unitPrice })
	return M.needsConfirmation or false
end
function C_AuctionHouse.PostItem(loc, duration, quantity, bid, buyout)
	table.insert(M.calls, { "PostItem", loc.bag, loc.slot, duration, quantity, bid, buyout })
	return M.needsConfirmation or false
end
function C_AuctionHouse.ConfirmPostCommodity(loc, duration, quantity, unitPrice)
	table.insert(M.calls, { "ConfirmPostCommodity", loc.bag, loc.slot, duration, quantity, unitPrice })
end
function C_AuctionHouse.ConfirmPostItem(loc, duration, quantity, bid, buyout)
	table.insert(M.calls, { "ConfirmPostItem", loc.bag, loc.slot, duration, quantity, bid, buyout })
end
function StaticPopup_Hide(which) table.insert(M.calls, { "StaticPopup_Hide", which }) end

AuctionHouseFrame = NewWidget("Frame", "AuctionHouseFrame")

-- Tooltip data processor: records post-calls so tests can invoke them.
M.tooltipPostCalls = {}
TooltipDataProcessor = {
	AddTooltipPostCall = function(kind, fn) M.tooltipPostCalls[kind] = fn end,
}

function M.FindCall(name)
	for _, c in ipairs(M.calls) do if c[1] == name then return c end end
end
function M.CountCalls(name)
	local n = 0
	for _, c in ipairs(M.calls) do if c[1] == name then n = n + 1 end end
	return n
end
function M.ResetCalls() wipe(M.calls) end

return M

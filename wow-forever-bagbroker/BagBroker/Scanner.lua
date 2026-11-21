-- BagBroker: auction house data collection.
--  * Full scan (C_AuctionHouse.ReplicateItems, server-throttled to once per 15 minutes) builds the
--    per-item quartiles shown on tooltips and used for vendor decisions.
--  * Live searches (one item at a time, throttled by the server message queue) give the current
--    listings the selling panel prices against.
local _, ns = ...

local Scanner = { queue = {} }
ns.Scanner = Scanner

local CHUNK = 1500          -- replicate entries processed per frame
local FULL_TIMEOUT = 120    -- seconds to wait for the replicate list
local SEARCH_TIMEOUT = 5    -- seconds to wait for one live search

local COMMODITY = (Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity) or 2
Scanner.COMMODITY = COMMODITY

local function PriceSorts()
	local order = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0
	return { { sortOrder = order, reverseSort = false } }
end

---------------------------------------------------------------------------
-- Full scan
---------------------------------------------------------------------------
function Scanner:FullScanCooldown()
	local realm = ns:GetRealmData()
	return math.max(0, (realm.lastScan or 0) + ns.SCAN_COOLDOWN - time())
end

function Scanner:IsFullScanRunning()
	return self.full ~= nil
end

function Scanner:StartFullScan(manual)
	if not ns.ahOpen then
		if manual then ns:Print("Open the auction house first.") end
		return false
	end
	if self.full then
		if manual then ns:Print("A full scan is already running.") end
		return false
	end
	local wait = self:FullScanCooldown()
	if wait > 0 then
		if manual then ns:Print(("Full scan available in %d min %d s (server limit)."):format(math.floor(wait / 60), wait % 60)) end
		return false
	end
	self.full = { state = "waiting", started = GetTime() }
	ns:GetRealmData().lastScan = time()
	C_AuctionHouse.ReplicateItems()
	ns:Print("Full auction scan started.")
	ns:Fire("SCAN_STATE")
	local job = self.full
	C_Timer.After(FULL_TIMEOUT, function()
		if self.full == job and job.state == "waiting" then
			self.full = nil
			ns:Print("Full scan timed out (the server did not answer). Try again later.")
			ns:Fire("SCAN_STATE")
		end
	end)
	return true
end

function Scanner:OnReplicateReady()
	local job = self.full
	if not job or job.state ~= "waiting" then return end
	job.state = "processing"
	job.total = C_AuctionHouse.GetNumReplicateItems() or 0
	job.index = 0          -- replicate indices are 0-based
	job.buckets = {}
	job.gear = {}          -- cheapest single-item auction per equipment item and suffix (for gear advisors)
	job.auctions = 0
	self:ProcessChunk()
end

function Scanner:ProcessChunk()
	local job = self.full
	if not job then return end
	if not ns.ahOpen then
		self.full = nil
		ns:Print("Full scan aborted: the auction house was closed.")
		ns:Fire("SCAN_STATE")
		return
	end
	local last = math.min(job.index + CHUNK, job.total) - 1
	for i = job.index, last do
		local _, _, count, quality, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
		if itemID and buyout and buyout > 0 and count and count > 0 then
			local bucket = job.buckets[itemID]
			if not bucket then
				bucket = {}
				job.buckets[itemID] = bucket
			end
			bucket[#bucket + 1] = { price = buyout / count, qty = count }
			job.auctions = job.auctions + 1
			if count == 1 and (quality or 0) >= 2 then self:RecordGear(job, i, itemID, buyout) end
		end
	end
	job.index = last + 1
	ns:Fire("SCAN_STATE")
	if job.index >= job.total then
		self:FinishFullScan()
	else
		C_Timer.After(0, function() self:ProcessChunk() end)
	end
end

-- Equipment auctions keep their link (random suffixes change the stats); one entry per variant.
function Scanner:RecordGear(job, index, itemID, buyout)
	local classID = select(6, C_Item.GetItemInfoInstant(itemID))
	if classID ~= 2 and classID ~= 4 then return end
	local link = C_AuctionHouse.GetReplicateItemLink and C_AuctionHouse.GetReplicateItemLink(index)
	if type(link) ~= "string" then return end
	local suffix = link:match("item:%d+:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:([^:]*)") or ""
	local key = itemID .. ":" .. suffix
	local old = job.gear[key]
	if not old or buyout < old[2] then job.gear[key] = { link, buyout } end
end

function Scanner:FinishFullScan()
	local job = self.full
	self.full = nil
	local now, items = time(), 0
	for itemID, entries in pairs(job.buckets) do
		local minPrice, p25, p50, p75, qty = ns.Pricing.WeightedQuantiles(entries)
		if minPrice then
			ns:SetStats(itemID, minPrice, p25, p50, p75, qty, now)
			items = items + 1
		end
	end
	ns:GetRealmData().lastScanDone = now
	local gear, n = {}, 0
	for _, entry in pairs(job.gear or {}) do
		n = n + 1
		gear[n] = entry
	end
	ns:GetRealmData().gear = gear
	ns:GetRealmData().gearTime = now
	ns:Print(("Full scan complete: %d auctions, %d items."):format(job.auctions, items))
	ns:Fire("SCAN_STATE")
	ns:Fire("SCAN_COMPLETE")
end

function Scanner:GetProgressText()
	local job = self.full
	if not job then return nil end
	if job.state == "waiting" then return "Full scan: waiting for server..." end
	return ("Full scan: %d / %d"):format(job.index or 0, job.total or 0)
end

---------------------------------------------------------------------------
-- Live searches
---------------------------------------------------------------------------
-- job = { key, itemID, itemKey, isCommodity }, callback(listings or nil)
function Scanner:QueueSearch(job, callback)
	for _, queued in ipairs(self.queue) do
		if queued.key == job.key then return end
	end
	if self.current and self.current.key == job.key then return end
	job.callback = callback
	self.queue[#self.queue + 1] = job
	self:Pump()
end

function Scanner:ClearSearches()
	wipe(self.queue)
	self.current = nil
end

function Scanner:PendingSearches()
	return #self.queue + (self.current and 1 or 0)
end

function Scanner:Pump()
	if self.current or not ns.ahOpen or #self.queue == 0 then return end
	if not C_AuctionHouse.IsThrottledMessageSystemReady() then
		-- Normally resumed by AUCTION_HOUSE_THROTTLED_SYSTEM_READY; the timer is a safety net.
		C_Timer.After(1, function() self:Pump() end)
		return
	end
	local job = table.remove(self.queue, 1)
	self.current = job
	C_AuctionHouse.SendSearchQuery(job.itemKey, PriceSorts(), true)
	C_Timer.After(SEARCH_TIMEOUT, function()
		if self.current == job then self:FinishSearch(job, self:CollectListings(job)) end
	end)
end

function Scanner:CollectListings(job)
	local listings = {}
	if job.isCommodity then
		local n = C_AuctionHouse.GetNumCommoditySearchResults(job.itemID) or 0
		for i = 1, n do
			local r = C_AuctionHouse.GetCommoditySearchResultInfo(job.itemID, i)
			if r and r.unitPrice then
				local qty = (r.quantity or 0) - (r.numOwnerItems or 0)
				if qty > 0 then listings[#listings + 1] = { price = r.unitPrice, qty = qty } end
			end
		end
	else
		local n = C_AuctionHouse.GetNumItemSearchResults(job.itemKey) or 0
		for i = 1, n do
			local r = C_AuctionHouse.GetItemSearchResultInfo(job.itemKey, i)
			if r and r.buyoutAmount and not r.containsOwnerItem then
				listings[#listings + 1] = { price = r.buyoutAmount, qty = math.max(1, r.quantity or 1) }
			end
		end
	end
	return listings
end

function Scanner:FinishSearch(job, listings)
	if self.current ~= job then return end
	self.current = nil
	if listings and #listings > 0 then
		-- Fresh listings are the best estimate available: refresh the shared statistics too.
		local copy = {}
		for i, l in ipairs(listings) do copy[i] = { price = l.price, qty = l.qty } end
		local minPrice, p25, p50, p75, qty = ns.Pricing.WeightedQuantiles(copy)
		if minPrice then ns:SetStats(job.itemID, minPrice, p25, p50, p75, qty) end
	end
	if job.callback then job.callback(listings) end
	C_Timer.After(0.1, function() self:Pump() end)
end

local function SameItemKey(a, b)
	return a and b and a.itemID == b.itemID and (a.itemLevel or 0) == (b.itemLevel or 0)
		and (a.itemSuffix or 0) == (b.itemSuffix or 0)
end

local function OnCommodityResults(_, itemID)
	local job = Scanner.current
	if job and job.isCommodity and job.itemID == itemID then
		Scanner:FinishSearch(job, Scanner:CollectListings(job))
	end
end

local function OnItemResults(_, itemKey)
	local job = Scanner.current
	if job and not job.isCommodity and SameItemKey(job.itemKey, itemKey) then
		Scanner:FinishSearch(job, Scanner:CollectListings(job))
	end
end

ns:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", OnCommodityResults)
ns:RegisterEvent("COMMODITY_SEARCH_RESULTS_ADDED", OnCommodityResults)
ns:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", OnItemResults)
ns:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED", OnItemResults)
ns:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function() Scanner:Pump() end)
ns:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE", function() Scanner:OnReplicateReady() end)

ns:RegisterEvent("AUCTION_HOUSE_SHOW", function()
	C_Timer.After(1, function()
		if ns.ahOpen and ns.settings.autoScan then Scanner:StartFullScan(false) end
	end)
end)

ns:RegisterEvent("AUCTION_HOUSE_CLOSED", function()
	Scanner:ClearSearches()
end)

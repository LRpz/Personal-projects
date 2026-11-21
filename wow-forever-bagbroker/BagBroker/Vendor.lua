-- BagBroker: automatic vendor selling.
-- Every item except unbound bind-on-equip items is sold when its vendor price is at least what
-- an auction would pay after the cut (see ns:ShouldVendor for the full rule set).
-- Hold Shift while opening a merchant to skip selling for that visit.
local _, ns = ...

local Vendor = {}
ns.Vendor = Vendor

local SELL_INTERVAL = 0.15

function Vendor:BuildList()
	local list = {}
	ns:ForEachBagSlot(function(bag, slot)
		local info = ns:GetSlotInfo(bag, slot)
		if info and not info.isLocked then
			local sell = ns:ShouldVendor(info)
			if sell then list[#list + 1] = info end
		end
	end)
	return list
end

function Vendor:Start()
	if self.ticker then return end
	local list = self:BuildList()
	if #list == 0 then return end
	self.list, self.index, self.total, self.sold = list, 0, 0, {}
	self.ticker = C_Timer.NewTicker(SELL_INTERVAL, function() self:Step() end)
end

function Vendor:Stop()
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
end

function Vendor:Step()
	if not ns.merchantOpen then
		self:Finish()
		return
	end
	self.index = self.index + 1
	local item = self.list[self.index]
	if not item then
		self:Finish()
		return
	end
	-- Re-check the slot: the player may have moved or used the item since the list was built.
	local current = C_Container.GetContainerItemInfo(item.bag, item.slot)
	if current and current.itemID == item.itemID and not current.isLocked then
		C_Container.UseContainerItem(item.bag, item.slot)
		self.total = self.total + item.sellPrice * (current.stackCount or 1)
		self.sold[#self.sold + 1] = current.hyperlink or item.link
	end
end

function Vendor:Finish()
	self:Stop()
	local sold = self.sold or {}
	if #sold > 0 then
		local detail = #sold <= 8 and (": " .. table.concat(sold, ", ")) or ""
		ns:Print(("Sold %d item(s) for %s%s"):format(#sold, ns.FormatMoney(self.total), detail))
	end
	self.list, self.sold = nil, nil
end

-- Preview used by "/bb preview": what would be sold right now, with reasons for kept items.
function Vendor:Preview()
	local sell, keep = {}, {}
	ns:ForEachBagSlot(function(bag, slot)
		local info = ns:GetSlotInfo(bag, slot)
		if info then
			local ok, reason = ns:ShouldVendor(info)
			local line = ("%s (%s)"):format(info.link or ("item:" .. info.itemID), reason)
			if ok then sell[#sell + 1] = line else keep[#keep + 1] = line end
		end
	end)
	return sell, keep
end

ns:RegisterEvent("MERCHANT_SHOW", function()
	if not ns.settings.autoSell or IsShiftKeyDown() then return end
	C_Timer.After(0.3, function()
		if ns.merchantOpen then Vendor:Start() end
	end)
end)

ns:RegisterEvent("MERCHANT_CLOSED", function()
	if Vendor.ticker then Vendor:Finish() end
end)

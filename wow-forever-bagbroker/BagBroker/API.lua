-- BagBroker: public interface for companion addons (for example a gear advisor tab).
--   BagBrokerAPI.RegisterAuctionTab{ key, label, title, build = function(page) end, onShow = function(page) end }
--     adds a tab to the auction house side panel; build runs once, the first time the tab opens.
--   BagBrokerAPI.GetGearCandidates() -> { {itemLink, buyoutCopper}, ... }, scanTime
--     cheapest auction per equipment item and suffix from the last full scan (uncommon quality and up).
local _, ns = ...

BagBrokerAPI = {
	version = 1,
	RegisterAuctionTab = function(tab) ns.Panel:AddTab(tab) end,
	GetGearCandidates = function()
		local realm = ns:GetRealmData()
		return realm.gear or {}, realm.gearTime
	end,
	GetStats = function(itemID) return ns:GetStats(itemID) end,
	GetAHNet = function(itemID, sellPrice) return ns:GetAHNet(itemID, sellPrice) end,
	IsAuctionHouseOpen = function() return ns.ahOpen and true or false end,
	StartFullScan = function() return ns.Scanner:StartFullScan(true) end,
	ScanCooldown = function() return ns.Scanner:FullScanCooldown() end,
	FormatMoney = function(copper) return ns.FormatMoney(copper) end,
	CoinString = function(copper) return ns.CoinString(copper) end,
	ParseMoney = function(text) return ns.Pricing.ParseMoney(text) end,
	CreateMoneyColumns = function(parent, width) return ns.CreateMoneyColumns(parent, width) end,
	CreateWindow = function(name, parent, title) return ns:CreateWindow(name, parent, title) end,
	QualityColor = function(quality) return ns.QualityColor(quality) end,
	On = function(message, fn) ns:On(message, fn) end, -- messages: SCAN_COMPLETE, SCAN_STATE, DB_READY
}

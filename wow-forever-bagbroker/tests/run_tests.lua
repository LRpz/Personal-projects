-- Test runner: loads BagBroker in TOC order inside the mock client and checks its behaviour.
-- Usage (from the repository folder): lua5.1 tests/run_tests.lua
package.path = "tests/?.lua;" .. package.path
local M = require("mock_wow")

local ADDON_DIR = "BagBroker/"
local ns = {}

local function LoadAddon()
	local files = {}
	for line in io.lines(ADDON_DIR .. "BagBroker.toc") do
		if line:match("%.lua%s*$") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
	end
	for _, file in ipairs(files) do
		local chunk = assert(loadfile(ADDON_DIR .. file))
		chunk("BagBroker", ns)
	end
	return files
end

---------------------------------------------------------------------------
-- Tiny test framework
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print("PASS  " .. name)
	else
		failed = failed + 1
		print("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end
local function eq(actual, expected, msg)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(msg or "value", tostring(expected), tostring(actual)), 2)
	end
end
local function truthy(v, msg) if not v then error((msg or "expected true") , 2) end end
local function contains(list, pattern, msg)
	for _, s in ipairs(list) do if tostring(s):find(pattern, 1, true) then return end end
	error((msg or "missing line") .. ": " .. pattern .. "\n      in: " .. table.concat(list, " | "), 2)
end

---------------------------------------------------------------------------
-- Fixtures
---------------------------------------------------------------------------
M.items = {
	[2589] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7, maxStack = 20 },
	[2592] = { name = "Wool Cloth", quality = 1, sellPrice = 33, classID = 7, maxStack = 20 },
	[1000] = { name = "Broken Fang", quality = 0, sellPrice = 50, classID = 15, maxStack = 5 },
	[1001] = { name = "Collectible Grey", quality = 0, sellPrice = 10, classID = 15 },
	[2000] = { name = "BoE Sword", quality = 2, sellPrice = 500, classID = 2, bindType = 2, equipLoc = "INVTYPE_WEAPON", ilvl = 20 },
	[2001] = { name = "Old Chest", quality = 2, sellPrice = 200, classID = 4, bindType = 1, equipLoc = "INVTYPE_CHEST", ilvl = 10 },
	[2002] = { name = "Better Chest", quality = 2, sellPrice = 300, classID = 4, bindType = 1, equipLoc = "INVTYPE_CHEST", ilvl = 20 },
	[3000] = { name = "Quest Thing", quality = 1, sellPrice = 0, classID = 12 },
	[6948] = { name = "Hearthstone", quality = 1, sellPrice = 0, classID = 15 },
	[4000] = { name = "Cheap Goods", quality = 1, sellPrice = 100, classID = 7, maxStack = 20 },
	[4001] = { name = "Pricey Goods", quality = 1, sellPrice = 100, classID = 7, maxStack = 20 },
	[4002] = { name = "Unknown Goods", quality = 1, sellPrice = 100, classID = 7, maxStack = 20 },
	[5000] = { name = "Epic Blade", quality = 4, sellPrice = 9000, classID = 2, bindType = 2, equipLoc = "INVTYPE_WEAPON", ilvl = 40 },
	[7000] = { name = "Shiny Loot", quality = 2, sellPrice = 5000, classID = 15, maxStack = 1 },
}
M.commodities = { [2589] = true, [2592] = true, [4000] = true, [4001] = true, [4002] = true }
M.equipped = { [5] = 15, [16] = 25, [17] = 25 }

local files = LoadAddon()
M.Fire("ADDON_LOADED", "BagBroker")
M.Fire("PLAYER_LOGIN")

local function ItemSlot(itemID, count, extra)
	local s = { itemID = itemID, count = count or 1 }
	for k, v in pairs(extra or {}) do s[k] = v end
	return s
end

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------
test("addon loads every TOC file and initialises account-wide saved variables", function()
	eq(#files, 15, "file count")
	truthy(BagBrokerDB and BagBrokerDB.settings, "saved variables")
	eq(ns.settings.autoSell, true, "default autoSell")
	eq(ns:GetRealmKey(), "TestRealm-Alliance", "realm key")
	truthy(M.tooltipPostCalls[Enum.TooltipDataType.Item], "item tooltip hook")
	truthy(M.tooltipPostCalls[Enum.TooltipDataType.Unit], "unit tooltip hook")
	truthy(SlashCmdList.BAGBROKER, "slash command")
	truthy(_G.BagBrokerMinimapButton, "minimap button")
end)

---------------------------------------------------------------------------
-- Pricing
---------------------------------------------------------------------------
local P = ns.Pricing

test("money text formatting and parsing round-trip", function()
	eq(P.FormatMoneyText(12345), "1g 23s 45c")
	eq(P.FormatMoneyText(0), "0c")
	eq(P.FormatMoneyText(500), "5s")
	eq(P.ParseMoney("1g 23s 45c"), 12345)
	eq(P.ParseMoney("1g23s"), 12300)
	eq(P.ParseMoney("35s"), 3500)
	eq(P.ParseMoney("80c"), 80)
	eq(P.ParseMoney("1.5"), 15000)
	eq(P.ParseMoney("1,25g"), 12500)
	eq(P.ParseMoney("abc"), nil)
	eq(P.ParseMoney("1x"), nil)
	eq(P.ParseMoney(""), nil)
end)

test("weighted quantiles count units, not auctions", function()
	local minP, p25, p50, p75, qty = P.WeightedQuantiles({
		{ price = 100, qty = 1 }, { price = 200, qty = 1 }, { price = 300, qty = 98 },
	})
	eq(minP, 100, "min")
	eq(p25, 300, "p25 dominated by the large stack")
	eq(p50, 300, "p50")
	eq(p75, 300, "p75")
	eq(qty, 100, "quantity")
	local _, a, b, c = P.WeightedQuantiles({ { price = 10, qty = 1 }, { price = 20, qty = 1 }, { price = 30, qty = 1 }, { price = 40, qty = 1 } })
	eq(a, 10, "p25 even")
	eq(b, 20, "p50 even")
	eq(c, 30, "p75 even")
end)

test("price skips a thin layer of cheap units and undercuts the real wall", function()
	local price, reason, d = P.SuggestPrice({ { price = 10000, qty = 2 }, { price = 15000, qty = 50 }, { price = 16000, qty = 100 } }, {})
	eq(price, 14999, "price under the 1.5g wall")
	eq(reason, "wall")
	eq(d.skipped, 2, "skipped units")
end)

test("price undercuts the lowest listing when it is a real wall", function()
	local price, reason = P.SuggestPrice({ { price = 5000, qty = 30 }, { price = 10000, qty = 70 } }, {})
	eq(price, 4999)
	eq(reason, "undercut")
end)

test("price ignores a lone outlier far below the market (gear)", function()
	local price = P.SuggestPrice({ { price = 10000, qty = 1 }, { price = 100000, qty = 1 }, { price = 120000, qty = 1 } }, {})
	eq(price, 99999, "outlier at 1g ignored, undercut 10g")
end)

test("price without competition uses the upper quartile; without live data the median", function()
	local stats = { 100, 200, 300, 400 }
	eq(select(1, P.SuggestPrice({}, { stats = stats })), 400, "no competition")
	eq(select(2, P.SuggestPrice({}, { stats = stats })), "nocompetition")
	eq(select(1, P.SuggestPrice(nil, { stats = stats })), 300, "estimate")
	eq(select(1, P.SuggestPrice(nil, {})), nil, "no data")
end)

test("silver-only servers get prices rounded down to silver", function()
	eq(select(1, P.SuggestPrice({ { price = 12345, qty = 10 } }, { silverOnly = true })), 12200)
end)

---------------------------------------------------------------------------
-- Vendor decisions
---------------------------------------------------------------------------
local function Decide(itemID, slotExtra)
	M.SetBags({ [0] = { size = 1, [1] = ItemSlot(itemID, 1, slotExtra) } })
	local info = ns:GetSlotInfo(0, 1)
	return ns:ShouldVendor(info)
end

ns:SetStats(1001, 80, 90, 100, 120, 5)    -- grey that sells better on the auction house
ns:SetStats(4000, 90, 95, 100, 110, 50)   -- net 95 < vendor 100
ns:SetStats(4001, 150, 180, 200, 260, 50) -- net 190 > vendor 100

test("vendor rules: junk, BoE, soulbound, auction comparison, lists", function()
	eq(Decide(1000), true, "grey without auction data is sold")
	eq(Decide(1001), false, "grey worth more at auction is kept")
	eq(Decide(2000), false, "unbound bind-on-equip is never sold")
	eq(Decide(2001, { bound = true }), true, "soulbound green below equipped item level is sold")
	eq(Decide(2002, { bound = true }), false, "soulbound upgrade is kept")
	eq(Decide(3000), false, "quest item kept")
	eq(Decide(6948), false, "no vendor value kept")
	eq(Decide(4000), true, "vendor 100 >= auction net 95")
	eq(Decide(4001), false, "auction net 190 > vendor 100")
	eq(Decide(4002), false, "no auction data: kept")
	ns.db.junk[4001] = true
	eq(Decide(4001), true, "junk list overrides")
	ns.db.junk[4001] = nil
	ns.db.keep[1000] = true
	eq(Decide(1000), false, "keep list overrides")
	ns.db.keep[1000] = nil
	ns.settings.sellSoulboundGear = false
	eq(Decide(2001, { bound = true }), false, "soulbound selling can be turned off")
	ns.settings.sellSoulboundGear = true
end)

test("merchant visit sells exactly the qualifying slots and reports the total", function()
	M.SetBags({ [0] = { size = 6,
		[1] = ItemSlot(1000, 3), [2] = ItemSlot(2000), [3] = ItemSlot(4000, 10),
		[4] = ItemSlot(4001, 10), [5] = ItemSlot(2001, 1, { bound = true }), [6] = ItemSlot(6948) } })
	M.ResetCalls()
	M.Fire("MERCHANT_SHOW")
	M.Advance(5)
	local sold = {}
	for _, c in ipairs(M.calls) do if c[1] == "UseContainerItem" then sold[#sold + 1] = c[4] end end
	table.sort(sold)
	eq(table.concat(sold, ","), "1000,2001,4000", "sold item IDs")
	contains(M.printed, "Sold 3 item(s) for <1350>", "summary (3x50 + 200 + 10x100)")
	M.Fire("MERCHANT_CLOSED")
end)

test("holding Shift at a merchant skips selling", function()
	M.SetBags({ [0] = { size = 1, [1] = ItemSlot(1000, 1) } })
	M.ResetCalls()
	M.shift = true
	M.Fire("MERCHANT_SHOW")
	M.Advance(5)
	M.shift = false
	eq(M.CountCalls("UseContainerItem"), 0)
	M.Fire("MERCHANT_CLOSED")
end)

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
-- Money strings contain coin textures and colour codes; reduce them to "1g 02s 03c".
local function Plain(text)
	text = tostring(text or "")
	text = text:gsub("|TInterface\\MoneyFrame\\UI%-GoldIcon[^|]*|t", "g")
	text = text:gsub("|TInterface\\MoneyFrame\\UI%-SilverIcon[^|]*|t", "s")
	text = text:gsub("|TInterface\\MoneyFrame\\UI%-CopperIcon[^|]*|t", "c")
	text = text:gsub("|TInterface\\AddOns\\BagBroker\\spacer[^|]*|t", " ")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return text
end
local function PlainLines(lines)
	local out = {}
	for i, l in ipairs(lines) do out[i] = Plain(l) end
	return out
end

local function ItemTooltip(itemID, data, owner, tt)
	tt = tt or CreateFrame("GameTooltip")
	tt.lines = {}
	tt.owner = owner
	data = data or {}
	data.id = itemID
	M.tooltipPostCalls[Enum.TooltipDataType.Item](tt, data)
	return PlainLines(tt.lines)
end

test("item tooltip: aligned block with sell price, lowest auction and quartiles", function()
	local lines = ItemTooltip(4001, { lines = {} })
	-- Net = price - 5% cut - deposit (15% of the 1s vendor price for the short trade-goods default = 15c).
	eq(table.concat(lines, " | "), "Sell Price || 1s 00c | Auction (net) || 1s 27c |   25% || 1s 56c |   50% || 1s 75c |   75% || 2s 32c")
end)

test("item tooltip: the game's own Sell Price line is restyled into the aligned block", function()
	local tt = CreateFrame("GameTooltip", "TestTip")
	local left = CreateFrame("FontString", "TestTipTextLeft1")
	local right = CreateFrame("FontString", "TestTipTextRight1")
	left.text = "Sell Price: 1s"
	right.shown = false
	tt.GetName = function() return "TestTip" end
	tt.NumLines = function() return 1 end
	local lines = ItemTooltip(4001, { lines = { { type = Enum.TooltipDataLineType.SellPrice } } }, nil, tt)
	eq(left.text, "Sell Price", "label without the colon")
	eq(Plain(right.text), "1s 00c", "money moved to the right column")
	eq(right.shown, true, "right column shown")
	eq(lines[1], "Auction (net) || 1s 27c", "no duplicate sell row")
end)

test("item tooltip multiplies by the hovered bag stack like the default line", function()
	M.SetBags({ [0] = { size = 1, [1] = ItemSlot(4001, 10) } })
	local owner = { GetBagID = function() return 0 end, GetID = function() return 1 end }
	local lines = ItemTooltip(4001, { lines = {} }, owner)
	eq(table.concat(lines, " | "), "Sell Price || 10s 00c | Auction (net) || 12s 70c |   25% || 15s 60c |   50% || 17s 50c |   75% || 23s 20c")
end)

test("item tooltip hides auction rows for soulbound bag items", function()
	M.SetBags({ [0] = { size = 1, [1] = ItemSlot(4001, 1, { bound = true }) } })
	local owner = { GetBagID = function() return 0 end, GetID = function() return 1 end }
	local lines = ItemTooltip(4001, { lines = {} }, owner)
	eq(#lines, 1, "sell price only")
end)

test("aligned money keeps every lower denomination so columns line up", function()
	eq(Plain(ns.CoinString(5)), "5c")
	eq(Plain(ns.CoinString(260)), "2s 60c")
	eq(Plain(ns.CoinString(1800)), "18s 00c")
	eq(Plain(ns.CoinString(48499)), "4g 84s 99c")
	eq(Plain(ns.CoinString(125000)), "12g 50s 00c")
	local cols = ns.CreateMoneyColumns(UIParent, 112)
	cols:SetAmount(125000)
	eq(Plain(cols.g.text) .. "|" .. Plain(cols.s.text) .. "|" .. Plain(cols.c.text), "12g|50s|00c", "three columns")
	cols:SetAmount(95, "|cffff8040")
	eq(Plain(cols.g.text) .. "|" .. Plain(cols.s.text) .. "|" .. Plain(cols.c.text), "||95c", "empty higher columns")
end)


test("auction net deducts the cut and a deposit that is calibrated at the auction house", function()
	eq(ns:DepositPerUnit(4001, 100), 15, "15% of 1s for a short (2h) trade good")
	eq(ns:NetFromPrice(4001, 200, 100), 175, "190 after the cut, minus 15 deposit")
	eq(ns:DepositPerUnit(2000, 500), 150, "BoE gear defaults to medium (8h): 30%")
	local saved = ns.db.depositRates[1]
	ns.db.depositRates[1] = nil
	ns:RecordDepositRate(1, 20, 100)
	eq(ns:DepositPerUnit(4001, 100), 20, "the first measurement replaces the default estimate")
	ns:RecordDepositRate(1, 10, 100)
	eq(ns:DepositPerUnit(4001, 100), 17, "later measurements blend in (70/30)")
	ns.db.depositRates[1] = saved
end)

test("vendor option: bind-on-equip items are sold only when enabled and the vendor pays more", function()
	ns:SetStats(2000, 400, 450, 500, 600, 3)  -- net 475 - 150 deposit = 325 < 500 vendor
	eq(Decide(2000), false, "kept by default")
	ns.settings.sellBoE = true
	eq(Decide(2000), true, "sold with the option on")
	ns:SetStats(2000, 4000, 4500, 5000, 6000, 3)
	eq(Decide(2000), false, "kept when the auction pays more")
	ns.settings.sellBoE = false
	ns:GetRealmData().items[2000] = nil
end)

test("merchant panel shows the options and sells on demand", function()
	ns.settings.autoSell = false
	M.SetBags({ [0] = { size = 2, [1] = ItemSlot(1000, 2), [2] = ItemSlot(4000, 5) } })
	M.ResetCalls()
	M.Fire("MERCHANT_SHOW")
	M.Advance(0.5)
	local panel = ns.Vendor.panel
	truthy(panel and panel:IsShown(), "panel shown")
	eq(M.CountCalls("UseContainerItem"), 0, "nothing sold automatically when auto-sell is off")
	truthy(panel.summary.text:find("2 stack(s) sell better", 1, true), "summary: " .. tostring(panel.summary.text))
	eq(panel.sell.text, "Sell now (2)")
	panel.checks.sellBoE:SetChecked(true)
	panel.checks.sellBoE.scripts.OnClick(panel.checks.sellBoE)
	eq(ns.settings.sellBoE, true, "checkbox toggles the option")
	ns.settings.sellBoE = false
	panel.sell.scripts.OnClick(panel.sell)
	M.Advance(2)
	eq(M.CountCalls("UseContainerItem"), 2, "sold on demand")
	M.Fire("MERCHANT_CLOSED")
	ns.settings.autoSell = true
end)

test("mail panel packs auction items for the mule, 12 stacks per mail", function()
	local bag = { size = 16 }
	for i = 1, 14 do bag[i] = ItemSlot(4001, 20) end   -- auction net 175 > vendor 100
	bag[15] = ItemSlot(2000)                             -- bind-on-equip: auction goods
	bag[16] = ItemSlot(4000, 5)                          -- vendor pays more: stays
	M.SetBags({ [0] = bag })
	M.mailItems = {}
	SendMailNameEditBox.text, SendMailSubjectEditBox.text = "", ""
	SlashCmdList.BAGBROKER("mule Muley")
	eq(ns.Mail:Mule(), "Muley", "mule saved per realm")
	M.Fire("MAIL_SHOW")
	M.Advance(0.2)
	local mail = ns.Mail
	truthy(mail.frame and mail.frame:IsShown(), "panel shown")
	eq(#mail.rows, 2, "two auction items; the vendor item is left out")
	truthy(mail.summary.text:find("15 stack(s)", 1, true) and mail.summary.text:find("2 mail(s)", 1, true), mail.summary.text)
	eq(mail.attachButton.text, "Attach 12 of 15 stacks")
	mail.attachButton.scripts.OnClick(mail.attachButton)
	local attached = 0
	for i = 1, 12 do if M.mailItems[i] then attached = attached + 1 end end
	eq(attached, 12, "mail filled")
	eq(SendMailNameEditBox.text, "Muley", "recipient filled")
	eq(SendMailSubjectEditBox.text, "AH items", "subject filled")
	M.mailItems = {}
	M.Fire("MAIL_SEND_SUCCESS")
	M.Advance(1)
	eq(mail.attachButton.text, "Attach 3 of 3 stacks", "next mail")
	mail.frame:Hide()
end)

---------------------------------------------------------------------------
-- Auction house: full scan and live search
---------------------------------------------------------------------------
test("full scan builds weighted per-unit statistics from replicate data", function()
	M.replicate = {
		{ itemID = 2592, count = 20, buyout = 2000 },  -- 100 each
		{ itemID = 2592, count = 10, buyout = 1500 },  -- 150 each
		{ itemID = 2592, count = 10, buyout = 3000 },  -- 300 each
		{ itemID = 2589, count = 1, buyout = 0 },      -- bid only: ignored
	}
	M.ResetCalls()
	M.Fire("AUCTION_HOUSE_SHOW")
	M.Advance(1.5)
	truthy(M.FindCall("ReplicateItems"), "replicate requested")
	M.Fire("REPLICATE_ITEM_LIST_UPDATE")
	M.Advance(1)
	local s = ns:GetStats(2592)
	truthy(s, "stats stored")
	eq(s[1], 100, "min")
	eq(s[2], 100, "p25")
	eq(s[3], 100, "p50 (20 of 40 units at 100)")
	eq(s[4], 150, "p75")
	eq(s[5], 40, "quantity")
	contains(M.printed, "Full scan complete: 3 auctions, 1 items.")
	eq(ns.Scanner:StartFullScan(false), false, "second scan blocked by the 15 minute limit")
	M.Fire("AUCTION_HOUSE_CLOSED")
end)

test("auction data written by one character is read by another on the same realm", function()
	M.faction = "Alliance"
	ns.realmData = nil
	truthy(ns:GetStats(2592), "same faction sees the data")
	M.faction = "Horde"
	ns.realmData = nil
	eq(ns:GetStats(2592), nil, "other faction has its own auction data by default")
	ns.settings.shareFactions = true
	ns.realmData = nil
	eq(ns:GetRealmKey(), "TestRealm", "shared key")
	ns.settings.shareFactions = false
	M.faction = "Alliance"
	ns.realmData = nil
end)

---------------------------------------------------------------------------
-- Auction panel
---------------------------------------------------------------------------
test("selling panel lists auctionable items, prices them from live listings and posts one per click", function()
	M.SetBags({ [0] = { size = 6,
		[1] = ItemSlot(2592, 20), [2] = ItemSlot(2592, 5), [3] = ItemSlot(2000),
		[4] = ItemSlot(2001, 1, { bound = true }), [5] = ItemSlot(3000), [6] = ItemSlot(4000, 4) } })
	M.commodity[2592] = {
		{ unitPrice = 90, quantity = 3, numOwnerItems = 0 },     -- thin cheap layer
		{ unitPrice = 140, quantity = 100, numOwnerItems = 0 },  -- real wall
		{ unitPrice = 120, quantity = 10, numOwnerItems = 10 },  -- our own auction: ignored
	}
	M.commodity[4000] = { { unitPrice = 96, quantity = 50, numOwnerItems = 0 } }
	M.itemResults[2000] = { { buyoutAmount = 20000, quantity = 1, containsOwnerItem = false } }
	M.ResetCalls()
	M.Fire("AUCTION_HOUSE_SHOW")
	M.Advance(0.2)
	local panel = ns.Panel
	truthy(panel.frame and panel.frame:IsShown(), "panel shown")
	eq(#panel.rows, 3, "rows: wool (aggregated), BoE sword, cheap goods; soulbound and quest excluded")
	local wool = panel.byKey["c2592"]
	eq(wool.count, 25, "stacks aggregated")
	eq(wool.duration, 1, "trade goods default to short (2h)")
	eq(panel.byKey["i2000:20:0"].duration, 2, "BoE gear defaults to medium (8h)")

	-- Live search results arrive one by one.
	for _ = 1, 3 do
		local job = ns.Scanner.current
		truthy(job, "a search is running")
		if job.isCommodity then M.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", job.itemID)
		else M.Fire("ITEM_SEARCH_RESULTS_UPDATED", job.itemKey) end
		M.Advance(0.2)
	end
	eq(wool.price, 139, "skips 3 cheap units, ignores own auction, undercuts 140")
	eq(wool.checked, true, "wool proposed")
	local goods = panel.byKey["c4000"]
	eq(goods.price, 95, "cheap goods priced at 95")
	eq(goods.vendorBetter, true, "vendor 100 beats auction net 90")
	eq(goods.checked, false, "not proposed when the vendor pays more")
	eq(panel.byKey["i2000:20:0"].price, 19999, "sword undercuts 2g")
	local top = panel.rowFrames[1].price
	eq(Plain(top.g.text) .. "|" .. Plain(top.s.text) .. "|" .. Plain(top.c.text), "1g|99s|99c", "price in aligned columns")

	M.ResetCalls()
	panel:PostNext()
	local post = M.FindCall("PostItem") or M.FindCall("PostCommodity")
	truthy(post, "one post issued")
	eq(M.CountCalls("PostItem") + M.CountCalls("PostCommodity"), 1, "exactly one post per click")
	eq(post[1], "PostItem", "most valuable row first (sword 19999 > wool 25x139)")
	eq(post[4], 2, "medium (8h) duration")
	eq(post[7], 19999, "buyout")
	M.Fire("AUCTION_HOUSE_AUCTION_CREATED", 1)
	eq(panel.postedCount, 1, "posted counter")

	M.ResetCalls()
	panel:PostNext()
	local c = M.FindCall("PostCommodity")
	truthy(c, "commodity posted on the next click")
	eq(c[5], 25, "whole quantity across stacks")
	eq(c[6], 139, "unit price")
	eq(c[4], 1, "short (2h)")
end)

test("server confirmation request turns the button into Confirm post", function()
	local panel = ns.Panel
	local goods = panel.byKey["c4000"]
	panel:SetChecked(goods, true)
	M.needsConfirmation = true
	M.ResetCalls()
	panel:PostNext()
	M.needsConfirmation = false
	truthy(panel.pending, "pending post kept")
	eq(panel.postButton.text, "Confirm post")
	M.Advance(0.1)
	truthy(M.FindCall("StaticPopup_Hide"), "default dialog hidden")
	panel:PostNext()
	truthy(M.FindCall("ConfirmPostCommodity"), "confirmed on the next click")
	eq(panel.pending, nil)
end)

test("manual price edits and duration changes stick", function()
	local panel = ns.Panel
	panel:Select("c2592")
	panel:ApplyPriceText("1g 5s")
	local wool = panel.byKey["c2592"]
	eq(wool.price, 10500, "manual price")
	eq(wool.source, "manual")
	panel:CycleRowDuration(1)
	eq(wool.duration, 2, "row duration cycled")
	panel:CycleCategory("trade", 1)
	eq(ns.settings.durations.trade, 2, "category default cycled")
	eq(panel.byKey["c4000"].duration, 2, "category change applies to rows without manual duration")
	panel:ResetPrice()
	eq(wool.price, 139, "auto price restored")
	ns.settings.durations.trade = 1
	M.Fire("AUCTION_HOUSE_CLOSED")
end)

---------------------------------------------------------------------------
-- Farming advisor: real database smoke test, then a small synthetic database for exact checks
---------------------------------------------------------------------------
test("public database loads and ranks real farming and gathering spots", function()
	local db = ns.FarmDB
	truthy(db and db.mobs and db.nodes, "FarmDB present")
	local count = 0
	for _ in pairs(db.mobs) do count = count + 1 end
	truthy(count > 5000, "mobs: " .. count)
	truthy((ns.Farm:DbValue(448) or 0) > 0, "Hogger has a database value")
	local t0 = os.clock()
	local spots = ns.Farm:KillSpots(30, {}, 5)
	eq(#spots, 5, "five kill spots for level 30")
	truthy(spots[1].total >= spots[5].total and spots[5].total > 0, "sorted by value")
	local zones = ns.Farm:GatherZones({ mining = 175 }, "mining", 3)
	eq(#zones, 3, "three mining zones")
	truthy(os.clock() - t0 < 3, "fast enough: " .. (os.clock() - t0) .. " s")
end)

local REAL_DB = ns.FarmDB
ns.FarmDB = {
	items = { [2589] = { 13, 1, "Linen Cloth" }, [7001] = { 100, 1, "Fang" }, [7002] = { 1000, 2, "Green Blade" },
		[2770] = { 5, 1, "Copper Ore" }, [4304] = { 50, 1, "Thick Leather" } },
	refs = { [900] = { 7002, 0.5 } },
	skins = { [800] = { 4304, 1 } },
	nodes = {
		{ "Copper Vein", "mining", 1, { 2770, 3 }, { [1429] = { 100, 4, 101, 2 } } },
		{ "Mithril Deposit", "mining", 175, { 2770, 10 }, { [1429] = { 500, 1 } } },
	},
	mobs = {
		[500] = { "Wolf", 20, 21, 0, 0, 800, { 7001, 0.5, 1 }, {}, { [1429] = { 1210, 5, 1211, 3 } }, 0, true },
		[501] = { "Bandit", 21, 22, 0, 100, 0, { 2589, 0.4, 2 }, { 900, 0.02 }, { [1429] = { 2000, 6 }, [1436] = { 300, 2 } }, 4, true },
		[502] = { "Elite Ogre", 21, 21, 1, 1000, 0, {}, {}, { [1429] = { 1212, 10 } }, 0, true },
		[503] = { "Old Boar", 5, 6, 0, 0, 0, { 7001, 1, 1 }, {}, { [1429] = { 1500, 9 } }, 0, true },
		[504] = { "New Forever Mob", 21, 21, 0, 0, 0, {}, {}, { [1429] = { 1700, 4 } }, 0, false },
	},
}
ns.EverlootDB = { asOf = "2026-11-20T12:00:00", npcs = {} }
ns.Farm:Invalidate()

local function near(a, b, msg) if math.abs(a - b) > 0.01 then error(("%s: expected %s, got %s"):format(msg or "value", b, a), 2) end end

test("database value per kill: money, drops, world drops and small drops", function()
	near(ns.Farm:DbValue(500), 50, "wolf: 50% x 100c")
	near(ns.Farm:DbValue(501), 124.4, "bandit: 100 + 0.4x2x13 + 0.02x0.5x1000 + 4")
	eq(ns.Farm:DbValue(504), nil, "Forever-only creature has no database loot")
end)

test("personal kills are weighted against the database by kill count", function()
	ns.db.mobs[500] = { k = 5, m = 0, i = { [7001] = { 5, 10 } } }  -- personal: 200c per kill
	ns.Farm:Invalidate()
	local v, n, source = ns.Farm:MobValue(500)
	near(v, 75, "5 kills: (25x50 + 5x200) / 30")
	eq(n, 5); eq(source, "vanilla + you 5")
	local drops = ns.Farm:DropTable(500)
	near(drops[1].chance, (25 * 0.5 + 5) / 30, "drop chance weighted the same way")
	ns.db.mobs[500] = { k = 100, m = 0, i = { [7001] = { 100, 200 } } }
	ns.Farm:Invalidate()
	near(ns.Farm:MobValue(500), 170, "100 kills: (25x50 + 100x200) / 125")
	ns.db.mobs[504] = { k = 4, m = 400, i = {} }
	ns.Farm:Invalidate()
	local v2, _, source2 = ns.Farm:MobValue(504)
	near(v2, 100, "Forever-only: personal data alone")
	eq(source2, "you 4")
	ns.settings.priorKills = 0
	ns.Farm:Invalidate()
	near(ns.Farm:MobValue(500), 200, "prior 0: personal only")
	ns.settings.priorKills = 25
	ns.db.mobs[500], ns.db.mobs[504] = nil, nil
	ns.Farm:Invalidate()
end)


test("Everloot windows join the weighting, corrected for corpses without loot", function()
	ns.EverlootDB.npcs[500] = { 100, 6, 7001, 80 }   -- 100 loot windows, 80 with a fang
	ns.Farm:Invalidate()
	local drops, _, _, _, label = ns.Farm:DropTable(500)
	near(drops[1].chance, (25 * 0.5 + 80) / 125, "chance weighted by windows")
	eq(label, "vanilla + Everloot 100")
	near(ns.Farm:MobValue(500), (25 * 50 + 80 * 100) / 125, "value weighted the same way")
	ns.FarmDB.mobs[500][12] = 0.5                     -- only half the corpses can be looted
	ns.Farm:Invalidate()
	drops = ns.Farm:DropTable(500)
	near(drops[1].chance, (25 * 0.5 + 80 * 0.5) / 125, "window share converted to a per-kill chance")
	ns.FarmDB.mobs[500][12] = nil
	ns.EverlootDB.npcs[504] = { 10, 3, 7001, 5 }      -- Forever-only creature
	ns.Farm:Invalidate()
	local v, _, label2 = ns.Farm:MobValue(504)
	near(v, 50, "Everloot alone: 5 of 10 windows x 1s")
	eq(label2, "Everloot 10")
	eq(ns.Farm:EverlootAgeDays() ~= nil, true, "data age known")
	ns.EverlootDB.npcs = {}
	ns.Farm:Invalidate()
end)

test("skinning adds value only when the character's skill is high enough", function()
	eq(ns.Farm.SkinningRequired(5), 1)
	eq(ns.Farm.SkinningRequired(15), 50)
	eq(ns.Farm.SkinningRequired(21), 105)
	eq(ns.Farm:SkinValue(500, 104), 0, "skill 104 cannot skin a level 21 wolf")
	near(ns.Farm:SkinValue(500, 110), 50, "skill 110 can")
	eq(ns.Farm:SkinValue(500, nil), 0, "no skinning")
end)

test("kill spots: level window, normal creatures only, ranked by value per clear", function()
	local spots = ns.Farm:KillSpots(20, {}, 5)
	eq(spots[1].ui, 1429, "best map")
	eq(spots[1].cx .. "," .. spots[1].cy, "20,33", "bandit camp (cell 2000)")
	near(spots[1].total, 6 * 124.4, "6 bandits")
	near(spots[2].total, 8 * 50, "8 wolves; the elite ogre next to them is excluded")
	for _, spot in ipairs(spots) do
		truthy(not spot.ids[503], "level 5 boars are outside the window")
		truthy(not spot.ids[502], "elite excluded")
	end
	local skinned = ns.Farm:KillSpots(20, { skinning = 110 }, 5)
	near(skinned[1].total, 8 * 100, "with skinning the wolves pay more than the bandits")
end)

test("gathering zones only count nodes the character can gather", function()
	local zones = ns.Farm:GatherZones({ mining = 100 }, "mining", 5)
	near(zones[1].total, 6 * 3 * 5, "copper only")
	zones = ns.Farm:GatherZones({ mining = 200 }, "mining", 5)
	near(zones[1].total, 6 * 3 * 5 + 10 * 5, "copper and mithril")
	eq(ns.Farm.SkillColor(120, 1), "|cff808080", "copper is grey at 120")
	eq(ns.Farm.SkillColor(180, 175), "|cffff8040", "mithril is orange at 180")
end)

test("farming spots window lists spots and opens them on the heatmap", function()
	M.level = 20
	M.profs = { { "Mining", 120, 186 }, { "Skinning", 110, 393 } }
	SlashCmdList.BAGBROKER("farm")
	local f = ns.Farm.frame
	truthy(f and f:IsShown(), "window shown")
	truthy(f.summary.text:find("Level 20", 1, true) and f.summary.text:find("Skinning 110", 1, true), "level and professions")
	local rows = {}
	for _, rf in ipairs(ns.Farm.rowFrames) do if rf.shown and rf.row then rows[#rows + 1] = rf.row end end
	truthy(rows[1].header:find("level 14 to 21", 1, true), "level window header")
	eq(rows[2].kind, "kill")
	local gatherHeader
	for _, r in ipairs(rows) do if r.header and r.header:find("Mining", 1, true) then gatherHeader = r end end
	truthy(gatherHeader, "mining section")
	ns.Farm.rowFrames[2].scripts.OnClick(ns.Farm.rowFrames[2])
	eq(ns.Heat.mode, "database", "heatmap switched to database source")
	eq(ns.Heat.mapID, 1429)
	truthy(ns.Heat.highlight.shown, "spot highlighted")
	local cells = ns.Heat:ComputeCells(1429)
	truthy(#cells >= 3, "database cells drawn")
	ns.Heat.frame:Hide()
	ns.Heat.mode = "kills"
	f:Hide()
	M.profs = nil
end)

---------------------------------------------------------------------------
-- Loot learning, mob tooltips, heatmap
---------------------------------------------------------------------------
test("loot windows teach drop rates per NPC, including AoE loot and coin", function()
	local g1 = "Creature-0-1-2-3-1234-00000001"
	local g2 = "Creature-0-1-2-3-1234-00000002"
	M.loot = {
		{ type = 2, text = "12 Copper", sources = { g1, 5, g2, 7 } },
		{ type = 1, link = M.Link(2589), qty = 2, sources = { g1, 2 } },
	}
	M.units.target = { guid = g1, name = "Kobold Miner" }
	M.Fire("LOOT_READY")
	M.Fire("LOOT_OPENED")   -- second event for the same window must not double count
	M.Fire("LOOT_CLOSED")
	local mob = ns.db.mobs[1234]
	eq(mob.k, 2, "two kills")
	eq(mob.m, 12, "coin")
	eq(mob.i[2589][1], 1, "drop count")
	eq(mob.i[2589][2], 2, "quantity")
	eq(mob.n, "Kobold Miner", "name")
	local cell = math.floor(0.252 * 40) * 60 + math.floor(0.505 * 60)
	eq(ns.db.heat[1429][cell][1234], 2, "heat cell")
end)

test("empty corpses of tapped targets count as kills", function()
	local g3 = "Creature-0-1-2-3-1234-00000003"
	M.units.target = { guid = g3, name = "Kobold Miner", dead = true }
	M.Fire("UNIT_HEALTH", "target")
	M.Advance(3)
	eq(ns.db.mobs[1234].k, 3, "third kill without loot")
	M.units.target = nil
end)

test("mob tooltip: loot per kill and drop chances with right-aligned values", function()
	-- Creature 1234 is not in the database: personal data only. Linen vendor 13c:
	-- value per kill = (12 coin + 2 linen x 13) / 3 kills = 12.7c
	local tt = CreateFrame("GameTooltip")
	tt.lines = {}
	M.tooltipPostCalls[Enum.TooltipDataType.Unit](tt, { guid = "Creature-0-1-2-3-1234-00000009" })
	local lines = PlainLines(tt.lines)
	contains(lines, "Loot per kill (you 3) || 13c")
	contains(lines, "Linen Cloth || ")
	contains(lines, " 33% 13c -", "chance, vendor price, no auction data yet")
	contains(lines, "  Money || 4c")
	ns.settings.mobTooltips = false
	tt.lines = {}
	M.tooltipPostCalls[Enum.TooltipDataType.Unit](tt, { guid = "Creature-0-1-2-3-1234-00000009" })
	eq(#tt.lines, 0, "toggle off hides the lines")
	ns.settings.mobTooltips = true
end)

test("mob tooltip: database creature shows weighted drops, world drops and skinning", function()
	M.profs = { { "Skinning", 110, 393 } }
	ns.Farm.profCache = nil
	local tt = CreateFrame("GameTooltip")
	tt.lines = {}
	M.tooltipPostCalls[Enum.TooltipDataType.Unit](tt, { guid = "Creature-0-1-2-3-500-00000001" })
	local lines = PlainLines(tt.lines)
	contains(lines, "Loot per kill (vanilla) || 50c")
	contains(lines, "  Drops ||  Chance Vendor AH net", "column header")
	contains(lines, "Fang || ")
	contains(lines, " 50% 1s 00c -", "one vendor and one auction price per item")
	contains(lines, "  Skinning (you can skin it) || 50c")
	tt.lines = {}
	M.tooltipPostCalls[Enum.TooltipDataType.Unit](tt, { guid = "Creature-0-1-2-3-501-00000001" })
	lines = PlainLines(tt.lines)
	contains(lines, "Loot per kill (vanilla) || 1s 24c")
	contains(lines, "  Random world drops || 1.0%")
	ns:SetStats(2589, 10, 12, 15, 20, 100)
	ns.Farm:Invalidate()
	tt.lines = {}
	M.tooltipPostCalls[Enum.TooltipDataType.Unit](tt, { guid = "Creature-0-1-2-3-501-00000002" })
	contains(PlainLines(tt.lines), " 40% 13c 12c", "auction net shown once known: 15c - 5% - 2c deposit")
	contains(lines, "  Money || 1s 00c")
	M.profs = nil
	ns.Farm.profCache = nil
end)

test("heatmap window opens, colours cells and toggles", function()
	local cells, maxAvg = ns.Heat:ComputeCells(1429)
	eq(#cells, 1, "one cell")
	truthy(maxAvg > 0, "value")
	local r, g, b = ns.Heat.HeatColor(1)
	truthy(r > 0.9 and b < 0.2, "high value is red")
	r, g, b = ns.Heat.HeatColor(0)
	truthy(b > 0.9, "low value is blue")
	BagBroker_ToggleHeatmap()
	truthy(ns.Heat.frame:IsShown(), "shown")
	eq(ns.Heat.mapID, 1429, "current zone")
	truthy(ns.Heat.summary.text:find("3 kills recorded", 1, true), "summary text")
	SlashCmdList.BAGBROKER("map")
	eq(ns.Heat.frame:IsShown(), false, "slash command toggles it off (macro friendly)")
end)

---------------------------------------------------------------------------
-- Full-bag replacement
---------------------------------------------------------------------------
test("full bags: the cheapest unprotected item is destroyed for more valuable loot", function()
	M.SetBags({ [0] = { size = 4,
		[1] = ItemSlot(1000, 1),                  -- grey 50c: cheapest
		[2] = ItemSlot(6948),                     -- hearthstone: protected
		[3] = ItemSlot(2002, 1, { bound = true }), -- soulbound green gear: protected
		[4] = ItemSlot(4001, 20) } })              -- 20 x 190 net
	M.loot = { { type = 1, link = M.Link(7000), qty = 1, sources = { "Creature-0-1-2-3-99-1", 1 } } }
	M.ResetCalls()
	M.Fire("LOOT_OPENED")
	M.Advance(2)
	eq(M.CountCalls("DeleteCursorItem"), 0, "nothing destroyed without a click (hardware event rule)")
	local prompt = _G.BagBrokerReplacePrompt
	truthy(prompt and prompt:IsShown(), "prompt shown")
	truthy(prompt.text.text:find("Broken Fang", 1, true) and prompt.text.text:find("Shiny Loot", 1, true), "prompt names both items")
	truthy(_G.BagBrokerReplaceButton, "named button for /click macros")
	_G.BagBrokerReplaceButton.scripts.OnClick(_G.BagBrokerReplaceButton)
	local del = M.FindCall("DeleteCursorItem")
	truthy(del, "an item was destroyed on click")
	eq(del[2] .. ":" .. del[3], "0:1", "the grey item")
	M.Advance(1)
	truthy(M.FindCall("LootSlot"), "loot taken")
	M.Fire("LOOT_CLOSED")
	eq(prompt:IsShown(), false, "prompt closes with the loot window")
end)

test("full bags: a blocked destroy is reported and the cursor cleared", function()
	M.SetBags({ [0] = { size = 1, [1] = ItemSlot(1000, 1) } })
	M.loot = { { type = 1, link = M.Link(7000), qty = 1, sources = { "Creature-0-1-2-3-99-4", 1 } } }
	M.ResetCalls()
	M.Fire("LOOT_OPENED")
	M.Advance(1)
	M.deleteFails = true
	BagBroker_ReplaceLoot()
	M.deleteFails = false
	eq(M.cursor, nil, "cursor cleared")
	eq(M.CountCalls("LootSlot"), 0, "no loot attempted")
	contains(M.printed, "The game blocked destroying the item")
	M.Fire("LOOT_CLOSED")
end)

test("full bags: nothing is destroyed when the loot is worth less", function()
	M.SetBags({ [0] = { size = 1, [1] = ItemSlot(4001, 20) } })
	M.loot = { { type = 1, link = M.Link(1000), qty = 1, sources = { "Creature-0-1-2-3-99-2", 1 } } }
	M.ResetCalls()
	M.Fire("LOOT_OPENED")
	M.Advance(2)
	eq(M.CountCalls("DeleteCursorItem"), 0)
	M.Fire("LOOT_CLOSED")
end)

test("full bags: loot that stacks into an existing stack needs no replacement", function()
	M.SetBags({ [0] = { size = 2, [1] = ItemSlot(1000, 1), [2] = ItemSlot(2589, 5) } })
	M.loot = { { type = 1, link = M.Link(2589), qty = 3, sources = { "Creature-0-1-2-3-99-3", 3 } } }
	M.ResetCalls()
	M.Fire("LOOT_OPENED")
	M.Advance(2)
	eq(M.CountCalls("DeleteCursorItem"), 0)
	M.Fire("LOOT_CLOSED")
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
test("slash commands change settings and lists", function()
	SlashCmdList.BAGBROKER("sell off")
	eq(ns.settings.autoSell, false)
	SlashCmdList.BAGBROKER("sell on")
	eq(ns.settings.autoSell, true)
	SlashCmdList.BAGBROKER("compare p25")
	eq(ns.settings.compare, "p25")
	SlashCmdList.BAGBROKER("compare qty")
	eq(ns.settings.compare, "p25", "invalid statistic rejected")
	ns.settings.compare = "p50"
	SlashCmdList.BAGBROKER("keep " .. M.Link(4000))
	eq(ns.db.keep[4000], true)
	SlashCmdList.BAGBROKER("junk " .. M.Link(4000))
	eq(ns.db.keep[4000], nil, "moved off the keep list")
	eq(ns.db.junk[4000], true)
	SlashCmdList.BAGBROKER("forget " .. M.Link(4000))
	eq(ns.db.junk[4000], nil)
	SlashCmdList.BAGBROKER("wall 20")
	eq(ns.settings.wallFraction, 0.2)
	ns.settings.wallFraction = 0.1
	SlashCmdList.BAGBROKER("status")
	contains(M.printed, "Loot data: 2 mobs")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)

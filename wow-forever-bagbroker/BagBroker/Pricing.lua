-- BagBroker: pure pricing helpers (no game API calls, unit-tested outside the client).
local _, ns = ...

local P = {}
ns.Pricing = P

local floor = math.floor

---------------------------------------------------------------------------
-- Money text
---------------------------------------------------------------------------
function P.FormatMoneyText(copper)
	copper = floor((copper or 0) + 0.5)
	local g = floor(copper / 10000)
	local s = floor((copper % 10000) / 100)
	local c = copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return table.concat(parts, " ")
end

-- Accepts "1g 20s 5c", "1g20s", "35s", "80c", "1.25" (gold) or "12" (gold). Returns copper or nil.
function P.ParseMoney(text)
	if type(text) ~= "string" then return nil end
	local s = text:lower():gsub(",", "."):gsub("%s+", "")
	if s == "" or s:find("[^%d%.gsc]") then return nil end
	if s:find("[gsc]") then
		local g = s:match("([%d%.]+)g")
		local sv = s:match("(%d+)s")
		local c = s:match("(%d+)c")
		local rest = s:gsub("[%d%.]+g", ""):gsub("%d+s", ""):gsub("%d+c", "")
		if rest ~= "" then return nil end
		local gold = tonumber(g or "0")
		if not gold then return nil end
		return floor(gold * 10000 + 0.5) + (tonumber(sv) or 0) * 100 + (tonumber(c) or 0)
	end
	local gold = tonumber(s)
	if not gold then return nil end
	return floor(gold * 10000 + 0.5)
end

---------------------------------------------------------------------------
-- Statistics
---------------------------------------------------------------------------
-- entries: array of { price = unit price, qty = units }. Quantiles are weighted by units,
-- so a single large stack counts as many offers. Returns min, p25, p50, p75, totalQuantity.
function P.WeightedQuantiles(entries)
	if not entries or #entries == 0 then return nil end
	table.sort(entries, function(a, b) return a.price < b.price end)
	local total = 0
	for i = 1, #entries do total = total + entries[i].qty end
	if total <= 0 then return nil end
	local targets = { 0.25 * total, 0.50 * total, 0.75 * total }
	local out, t, cum = {}, 1, 0
	for i = 1, #entries do
		cum = cum + entries[i].qty
		while t <= 3 and cum >= targets[t] do
			out[t] = entries[i].price
			t = t + 1
		end
		if t > 3 then break end
	end
	local last = entries[#entries].price
	return entries[1].price, out[1] or last, out[2] or last, out[3] or last, total
end

-- Merges listings that share a unit price and sorts them cheapest first.
function P.GroupLevels(listings)
	local byPrice, levels = {}, {}
	for _, l in ipairs(listings or {}) do
		if l.price and l.price > 0 and (l.qty or 0) > 0 then
			local level = byPrice[l.price]
			if not level then
				level = { price = l.price, qty = 0 }
				byPrice[l.price] = level
				levels[#levels + 1] = level
			end
			level.qty = level.qty + l.qty
		end
	end
	table.sort(levels, function(a, b) return a.price < b.price end)
	return levels
end

local function WeightedMedian(levels, total)
	local cum = 0
	for _, level in ipairs(levels) do
		cum = cum + level.qty
		if cum >= total / 2 then return level.price end
	end
	return levels[#levels].price
end

---------------------------------------------------------------------------
-- Posting price suggestion
---------------------------------------------------------------------------
-- listings: competitor listings { price, qty } (own auctions excluded), or nil when no live
--   search result is available yet.
-- opts.stats: saved statistics { min, p25, p50, p75 } for this item, if any.
-- opts.wallFraction: cheaper listings that add up to at most this share of total supply are a
--   thin layer that will be bought out first, so we price under the next real wall instead.
-- opts.silverOnly: the server does not accept copper values.
-- Returns unitPrice, reasonCode, details.
function P.SuggestPrice(listings, opts)
	opts = opts or {}
	local stats = opts.stats
	local price, reason, details

	if listings == nil then
		if not stats then return nil, "nodata" end
		price, reason = stats[3], "estimate"
	else
		local levels = P.GroupLevels(listings)
		local total = 0
		for _, level in ipairs(levels) do total = total + level.qty end
		if total == 0 then
			if not stats then return nil, "nodata" end
			-- No competition: ask for the upper quartile of what the market has carried before.
			price, reason = stats[4] or stats[3], "nocompetition"
		else
			local wall = opts.wallFraction or 0.10
			local outlierRatio = opts.outlierRatio or 0.5
			local outlierShare = opts.outlierShare or 0.34
			local median = WeightedMedian(levels, total)
			local cheaper, target = 0, nil
			for i, level in ipairs(levels) do
				local after = cheaper + level.qty
				local thin = after <= total * wall
				local outlier = level.price < median * outlierRatio and after <= total * outlierShare
				if (thin or outlier) and i < #levels then
					cheaper = after
				else
					target = level.price
					break
				end
			end
			local undercut = opts.silverOnly and 100 or 1
			price = target - undercut
			if cheaper > 0 then
				reason, details = "wall", { skipped = cheaper, target = target }
			else
				reason, details = "undercut", { target = target }
			end
		end
	end

	if opts.silverOnly then
		price = floor(price / 100) * 100
		if price < 100 then price = 100 end
	end
	if price < 1 then price = 1 end
	return floor(price), reason, details
end

-- Human-readable explanation used by the panel.
function P.DescribeReason(reason, details, formatMoney)
	formatMoney = formatMoney or P.FormatMoneyText
	if reason == "wall" then
		return ("skips %d cheaper unit(s), undercuts the wall at %s"):format(details.skipped, formatMoney(details.target))
	elseif reason == "undercut" then
		return ("undercuts the lowest listing (%s)"):format(formatMoney(details.target))
	elseif reason == "nocompetition" then
		return "no competing listings: upper quartile of scan history"
	elseif reason == "estimate" then
		return "estimate from the last full scan (median), live search pending"
	elseif reason == "manual" then
		return "set by you"
	end
	return "no price data: type a price"
end

-- Net proceeds of a sale after the auction house cut.
function P.NetAfterCut(price, cut)
	return floor(price * (1 - (cut or 0.05)))
end

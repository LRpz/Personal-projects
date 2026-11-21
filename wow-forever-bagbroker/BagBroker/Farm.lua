-- BagBroker: farming advisor.
-- Combines the shipped public loot database (FarmData.lua) with your own kills, then ranks
-- farming spots for your level and gathering spots for your professions.
--
-- Weighting: the database counts as `priorKills` observations (default 25). With n personal kills
--   value = (priorKills * databaseValue + n * personalValue) / (priorKills + n)
-- so 5 kills move the estimate by 5/30 (17%), 100 kills by 100/125 (80%). The same rule applies
-- to each drop chance and to the money per kill. Creatures missing from the database (most new
-- Forever content) use personal data only.
local _, ns = ...

local Farm = { gen = 0, mobCache = {}, refCache = {}, itemCache = {} }
ns.Farm = Farm

local GRID_W, GRID_H = 60, 40
local SKILL_LINES = { [182] = "herbalism", [186] = "mining", [393] = "skinning" }
local SKILL_NAMES = { Herbalism = "herbalism", Mining = "mining", Skinning = "skinning" }
local PROF_LABELS = { herbalism = "Herbalism", mining = "Mining", skinning = "Skinning" }
Farm.PROF_LABELS = PROF_LABELS

local function DB() return ns.FarmDB end

---------------------------------------------------------------------------
-- Values (cached; invalidated when prices or personal data change)
---------------------------------------------------------------------------
function Farm:Invalidate()
	self.gen = self.gen + 1
	wipe(self.mobCache)
	wipe(self.refCache)
	wipe(self.itemCache)
end

-- Unit value of an item: vendor price from the database (or the client), or auction net if higher.
function Farm:ItemValue(itemID)
	local v = self.itemCache[itemID]
	if v then return v end
	local entry = DB() and DB().items[itemID]
	v = ns:GetUnitValue(itemID, entry and entry[1] or nil, true)
	self.itemCache[itemID] = v
	return v
end

function Farm:ItemName(itemID)
	local name, _, quality = (C_Item and C_Item.GetItemInfo or GetItemInfo)(itemID)
	if name then return ns.QualityColor(quality) .. name .. "|r" end
	local entry = DB() and DB().items[itemID]
	if entry and entry[3] then return ns.QualityColor(entry[2]) .. entry[3] .. "|r" end
	return ns:GetItemDisplayName(itemID)
end

function Farm:RefValue(refID)
	local v = self.refCache[refID]
	if v then return v end
	v = 0
	local ref = DB().refs[refID]
	if ref then
		for i = 1, #ref, 2 do v = v + ref[i + 1] * self:ItemValue(ref[i]) end
	end
	self.refCache[refID] = v
	return v
end

-- Database copper per kill (money + drops + world drops), or nil when the database has no loot.
function Farm:DbValue(npcID)
	local m = DB() and DB().mobs[npcID]
	if not m or not m[11] then return nil end
	local total = (m[5] or 0) + (m[10] or 0)
	local loot = m[7]
	for i = 1, #loot, 3 do total = total + loot[i + 1] * loot[i + 2] * self:ItemValue(loot[i]) end
	local refs = m[8]
	for i = 1, #refs, 2 do total = total + refs[i + 1] * self:RefValue(refs[i]) end
	return total
end

-- Personal copper per kill.
function Farm:PersonalValue(mob)
	if not mob or (mob.k or 0) <= 0 then return nil end
	local total = mob.m or 0
	for itemID, entry in pairs(mob.i or {}) do total = total + (entry[2] or 0) * self:ItemValue(itemID) end
	return total / mob.k
end

-- Combined value per kill. Returns value, personalKills, source ("database", "mine", "both").
function Farm:MobValue(npcID)
	local cached = self.mobCache[npcID]
	if cached then return cached[1], cached[2], cached[3] end
	local K = ns.settings.priorKills or 25
	local mob = ns.db.mobs[npcID]
	local n = mob and mob.k or 0
	local personal = self:PersonalValue(mob)
	local db = self:DbValue(npcID)
	local value, source
	if db and personal then
		value, source = (K * db + n * personal) / (K + n), "both"
	elseif db then
		value, source = db, "database"
	elseif personal then
		value, source = personal, "mine"
	end
	self.mobCache[npcID] = { value, n, source }
	return value, n, source
end

---------------------------------------------------------------------------
-- Professions
---------------------------------------------------------------------------
function Farm:GetProfessions()
	local now = GetTime()
	if self.profCache and now - self.profCacheTime < 5 then return self.profCache end
	local profs = {}
	if GetProfessions and GetProfessionInfo then
		local list = { GetProfessions() }
		for i = 1, 5 do
			local index = list[i]
			if index then
				local name, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
				local key = SKILL_LINES[skillLine] or SKILL_NAMES[name]
				if key then profs[key] = rank end
			end
		end
	end
	if not next(profs) and GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local name, isHeader, _, rank = GetSkillLineInfo(i)
			if not isHeader and SKILL_NAMES[name] then profs[SKILL_NAMES[name]] = rank end
		end
	end
	self.profCache, self.profCacheTime = profs, now
	return profs
end

-- Vanilla rule: level 1-10 needs 1, level 11-20 needs (level - 10) x 10, above 20 needs level x 5.
function Farm.SkinningRequired(level)
	if level <= 10 then return 1 end
	if level <= 20 then return (level - 10) * 10 end
	return level * 5
end

-- Extra value per kill from skinning, when the character can skin this creature.
function Farm:SkinValue(npcID, skill)
	local m = DB() and DB().mobs[npcID]
	if not skill or not m or (m[6] or 0) == 0 then return 0 end
	if self.SkinningRequired(m[3] > 0 and m[3] or m[2]) > skill then return 0 end
	local loot = DB().skins[m[6]]
	if not loot then return 0 end
	local v = 0
	for i = 1, #loot, 2 do v = v + loot[i + 1] * self:ItemValue(loot[i]) end
	return v
end

-- Skill-up colour of a gathering node: orange, yellow, green or grey.
function Farm.SkillColor(skill, required)
	if skill < required + 25 then return "|cffff8040" end
	if skill < required + 50 then return "|cffffff00" end
	if skill < required + 100 then return "|cff40c040" end
	return "|cff808080"
end

---------------------------------------------------------------------------
-- Drop table shown on mob tooltips
---------------------------------------------------------------------------
-- Returns { {id, chance}, ... } sorted by chance, money per kill, world-drop chance, kills, source.
function Farm:DropTable(npcID)
	local K = ns.settings.priorKills or 25
	local m = DB() and DB().mobs[npcID]
	local mob = ns.db.mobs[npcID]
	local n = mob and mob.k or 0
	local hasDb = m and m[11]
	if not hasDb and n == 0 then return nil end
	local wDb = hasDb and K or 0
	local denom = wDb + n
	local chances = {}
	if hasDb then
		local loot = m[7]
		for i = 1, #loot, 3 do chances[loot[i]] = wDb * loot[i + 1] end
	end
	for itemID, entry in pairs(mob and mob.i or {}) do
		chances[itemID] = (chances[itemID] or 0) + (entry[1] or 0)
	end
	local list = {}
	for itemID, weighted in pairs(chances) do
		list[#list + 1] = { id = itemID, chance = weighted / denom }
	end
	table.sort(list, function(a, b) return a.chance > b.chance end)
	local money = ((hasDb and wDb * (m[5] or 0) or 0) + (mob and mob.m or 0)) / denom
	local world = 0
	if hasDb then
		local refs = m[8]
		for i = 1, #refs, 2 do
			local ref = DB().refs[refs[i]]
			local count = 0
			for j = 2, #(ref or {}), 2 do count = count + ref[j] end
			world = world + refs[i + 1] * count
		end
		world = world * wDb / denom
	end
	local source = hasDb and (n > 0 and "both" or "database") or "mine"
	return list, money, math.min(1, world), n, source
end

---------------------------------------------------------------------------
-- Spots
---------------------------------------------------------------------------
local function AddCell(maps, ui, cell, count, value, id)
	local map = maps[ui]
	if not map then
		map = {}
		maps[ui] = map
	end
	local c = map[cell]
	if not c then
		c = { spawns = 0, total = 0, ids = {} }
		map[cell] = c
	end
	c.spawns = c.spawns + count
	c.total = c.total + count * value
	c.ids[id] = (c.ids[id] or 0) + count
end

-- Groups cells into areas (5 x 5 cells) around local maxima. Returns spots sorted by total value.
local function FindSpots(maps, limit, radius, suppress)
	radius, suppress = radius or 2, suppress or 4
	local candidates = {}
	for ui, map in pairs(maps) do
		for cell in pairs(map) do
			local cx, cy = cell % GRID_W, math.floor(cell / GRID_W)
			local total, spawns, ids = 0, 0, {}
			for dy = -radius, radius do
				for dx = -radius, radius do
					local x, y = cx + dx, cy + dy
					if x >= 0 and x < GRID_W and y >= 0 and y < GRID_H then
						local c = map[y * GRID_W + x]
						if c then
							total = total + c.total
							spawns = spawns + c.spawns
							for id, n in pairs(c.ids) do ids[id] = (ids[id] or 0) + n end
						end
					end
				end
			end
			candidates[#candidates + 1] = { ui = ui, cx = cx, cy = cy, total = total, spawns = spawns, ids = ids }
		end
	end
	table.sort(candidates, function(a, b) return a.total > b.total end)
	local picked = {}
	for _, c in ipairs(candidates) do
		local clash = false
		for _, p in ipairs(picked) do
			if p.ui == c.ui and math.abs(p.cx - c.cx) <= suppress and math.abs(p.cy - c.cy) <= suppress then
				clash = true
				break
			end
		end
		if not clash and c.total > 0 then
			picked[#picked + 1] = c
			if #picked >= limit then break end
		end
	end
	return picked
end
Farm.FindSpots = FindSpots

-- Per-cell data for one map and one purpose ("kill" or "gather"); also used by the heatmap.
function Farm:CollectKill(level, profs, onlyMap)
	local maps = {}
	local below, above = ns.settings.farmBelow or 6, ns.settings.farmAbove or 1
	local skinning = profs and profs.skinning
	for npcID, m in pairs(DB().mobs) do
		-- Some records span implausible ranges (for example 8-48): judge those by their top level.
		local minLevel = (m[3] - m[2] > 6) and (m[3] - 2) or m[2]
		if m[4] == 0 and m[2] > 0 and m[3] >= level - below and minLevel <= level + above then
			local value = self:MobValue(npcID)
			if value then
				value = value + self:SkinValue(npcID, skinning)
				for ui, cells in pairs(m[9]) do
					if not onlyMap or ui == onlyMap then
						for i = 1, #cells, 2 do AddCell(maps, ui, cells[i], cells[i + 1], value, npcID) end
					end
				end
			end
		end
	end
	return maps
end

function Farm:NodeValue(node)
	local v = 0
	for i = 1, #node[4], 2 do v = v + node[4][i + 1] * self:ItemValue(node[4][i]) end
	return v
end

function Farm:CollectGather(profs, onlyMap, onlyProf)
	local maps = {}
	for index, node in ipairs(DB().nodes) do
		local skill = profs[node[2]]
		if skill and node[3] <= skill and (not onlyProf or onlyProf == node[2]) then
			local value = self:NodeValue(node)
			for ui, cells in pairs(node[5]) do
				if not onlyMap or ui == onlyMap then
					for i = 1, #cells, 2 do AddCell(maps, ui, cells[i], cells[i + 1], value, index) end
				end
			end
		end
	end
	return maps
end

function Farm:KillSpots(level, profs, limit)
	return FindSpots(self:CollectKill(level, profs), limit or 8)
end

-- Gathering is done along a route through a whole zone, so zones are ranked by total node value.
function Farm:GatherZones(profs, prof, limit)
	local maps = self:CollectGather(profs, nil, prof)
	local zones = {}
	for ui, map in pairs(maps) do
		local total, nodes, ids = 0, 0, {}
		for _, c in pairs(map) do
			total = total + c.total
			nodes = nodes + c.spawns
			for id, n in pairs(c.ids) do ids[id] = (ids[id] or 0) + n end
		end
		zones[#zones + 1] = { ui = ui, total = total, spawns = nodes, ids = ids }
	end
	table.sort(zones, function(a, b) return a.total > b.total end)
	for i = (limit or 5) + 1, #zones do zones[i] = nil end
	return zones
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local ROW_HEIGHT = 30
local WIDTH = 520

local function MapName(ui)
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(ui)
	return info and info.name or ("Map " .. ui)
end

local function TopIds(ids, count)
	local list = {}
	for id, n in pairs(ids) do list[#list + 1] = { id = id, n = n } end
	table.sort(list, function(a, b) return a.n > b.n end)
	local out = {}
	for i = 1, math.min(count, #list) do out[i] = list[i] end
	return out
end

function Farm:BuildRows()
	local rows = {}
	local level = UnitLevel("player") or 1
	local profs = self:GetProfessions()
	self.level, self.profs = level, profs

	rows[#rows + 1] = { header = ("Killing: normal creatures level %d to %d"):format(
		math.max(1, level - (ns.settings.farmBelow or 6)), level + (ns.settings.farmAbove or 1)) }
	for _, spot in ipairs(self:KillSpots(level, profs, 8)) do
		local names = {}
		for _, t in ipairs(TopIds(spot.ids, 2)) do
			local m = DB().mobs[t.id]
			names[#names + 1] = ("%s (%d-%d)"):format(m[1], m[2], m[3])
		end
		rows[#rows + 1] = {
			kind = "kill", ui = spot.ui, cx = spot.cx, cy = spot.cy,
			title = ("%s  %d, %d"):format(MapName(spot.ui), math.floor((spot.cx + 0.5) * 100 / GRID_W), math.floor((spot.cy + 0.5) * 100 / GRID_H)),
			detail = table.concat(names, ", "),
			left = ("%d spawns"):format(spot.spawns),
			perUnit = spot.total / math.max(1, spot.spawns), total = spot.total,
		}
	end
	for _, prof in ipairs({ "mining", "herbalism" }) do
		local skill = profs[prof]
		if skill then
			rows[#rows + 1] = { header = ("%s (skill %d): best zones, value of all node spawn points"):format(PROF_LABELS[prof], skill) }
			for _, zone in ipairs(self:GatherZones(profs, prof, 5)) do
				local parts = {}
				for _, t in ipairs(TopIds(zone.ids, 3)) do
					local node = DB().nodes[t.id]
					parts[#parts + 1] = ("%s%d %s|r"):format(self.SkillColor(skill, node[3]), t.n, node[1])
				end
				rows[#rows + 1] = {
					kind = "gather", prof = prof, ui = zone.ui, title = MapName(zone.ui),
					detail = table.concat(parts, ", "), left = ("%d spawn points"):format(zone.spawns),
					perUnit = zone.total / math.max(1, zone.spawns), total = zone.total,
				}
			end
		end
	end
	if not profs.mining and not profs.herbalism then
		rows[#rows + 1] = { header = "Learn Mining or Herbalism to see gathering routes." }
	end
	return rows
end

function Farm:Create()
	if self.frame then return self.frame end
	local f = ns:CreateWindow("BagBrokerFarmSpots", UIParent, "BagBroker: farming spots")
	f:SetSize(WIDTH, 470)
	f:SetPoint("CENTER", 120, 0)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	tinsert(UISpecialFrames, "BagBrokerFarmSpots")
	self.frame = f

	f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.summary:SetPoint("TOPLEFT", 14, -30)
	f.summary:SetPoint("TOPRIGHT", -14, -30)
	f.summary:SetJustifyH("LEFT")

	local head1 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	head1:SetPoint("TOPRIGHT", -132, -48)
	head1:SetText("Per kill / node")
	local head2 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	head2:SetPoint("TOPRIGHT", -30, -48)
	head2:SetText("Per clear / zone")

	local scroll = CreateFrame("ScrollFrame", "BagBrokerFarmSpotsScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -62)
	scroll:SetPoint("BOTTOMRIGHT", -30, 34)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - 44, 1)
	scroll:SetScrollChild(content)
	self.content = content
	self.rowFrames = {}

	f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.note:SetPoint("BOTTOMLEFT", 14, 12)
	f.note:SetPoint("BOTTOMRIGHT", -14, 12)
	f.note:SetJustifyH("LEFT")
	f.note:SetText("Click a row to show it on the heatmap. Values: database weighted with your kills.")

	f:SetScript("OnShow", function() self:Refresh() end)
	return f
end

function Farm:RowFrame(i)
	local rf = self.rowFrames[i]
	if rf then return rf end
	rf = CreateFrame("Button", nil, self.content)
	rf:SetSize(WIDTH - 44, ROW_HEIGHT)
	local highlight = rf:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	rf.title = rf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	rf.title:SetPoint("TOPLEFT", 4, -2)
	rf.title:SetJustifyH("LEFT")
	rf.detail = rf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rf.detail:SetPoint("TOPLEFT", 4, -16)
	rf.detail:SetPoint("RIGHT", -200, 0)
	rf.detail:SetJustifyH("LEFT")
	rf.detail:SetWordWrap(false)
	rf.per = ns.CreateMoneyColumns(rf, 96)
	rf.per:SetPoint("RIGHT", -100, 0)
	rf.total = ns.CreateMoneyColumns(rf, 96)
	rf.total:SetPoint("RIGHT", -2, 0)
	rf.header = rf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	rf.header:SetPoint("BOTTOMLEFT", 2, 4)
	rf.header:SetJustifyH("LEFT")
	rf:SetScript("OnClick", function()
		local row = rf.row
		if row and row.ui and ns.Heat then ns.Heat:ShowSpot(row) end
	end)
	self.rowFrames[i] = rf
	return rf
end

function Farm:Refresh()
	if not self.frame or not self.frame:IsShown() then return end
	if not DB() then
		self.frame.summary:SetText("Database file FarmData.lua is missing.")
		return
	end
	self:Invalidate()
	self.profCache = nil
	local rows = self:BuildRows()
	local parts = { ("Level %d"):format(self.level) }
	for _, prof in ipairs({ "skinning", "mining", "herbalism" }) do
		if self.profs[prof] then parts[#parts + 1] = ("%s %d"):format(PROF_LABELS[prof], self.profs[prof]) end
	end
	self.frame.summary:SetText(table.concat(parts, "   "))
	for i, row in ipairs(rows) do
		local rf = self:RowFrame(i)
		rf:ClearAllPoints()
		rf:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
		rf.row = row
		local isHeader = row.header ~= nil
		rf.header:SetShown(isHeader)
		rf.title:SetShown(not isHeader)
		rf.detail:SetShown(not isHeader)
		rf.per:SetShown(not isHeader)
		rf.total:SetShown(not isHeader)
		if isHeader then
			rf.header:SetText(row.header)
		else
			rf.title:SetText(row.title)
			rf.detail:SetText(row.left .. ": " .. row.detail)
			rf.per:SetAmount(row.perUnit)
			rf.total:SetAmount(row.total)
		end
		rf:Show()
	end
	for i = #rows + 1, #self.rowFrames do self.rowFrames[i]:Hide() end
	self.content:SetHeight(math.max(1, #rows * ROW_HEIGHT))
end

function Farm:Toggle()
	local f = self:Create()
	f:SetShown(not f:IsShown())
end

function BagBroker_ToggleFarmSpots()
	Farm:Toggle()
end

ns:On("SCAN_COMPLETE", function() Farm:Invalidate() end)
ns:On("KILL_RECORDED", function(_, npcID)
	Farm.mobCache[npcID or 0] = nil
end)
ns:RegisterEvent("PLAYER_LEVEL_UP", function()
	if Farm.frame and Farm.frame:IsShown() then C_Timer.After(1, function() Farm:Refresh() end) end
end)

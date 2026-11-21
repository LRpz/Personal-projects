-- BagBroker: standalone farming heatmap window.
-- A separate, movable zone map (it does not touch the world map, so it coexists with map
-- replacements such as Carbonite). Three sources, cycled with the "Source" button:
--   * My kills: where you looted, coloured by loot value per kill.
--   * Database: creature spawns for your level from the public database, valued per kill
--     (database weighted with your kills, plus skinning when you can skin them).
--   * Gathering: herb and ore nodes your professions can gather, valued per node.
-- Colour runs from blue (low) to red (high); opacity grows with the number of kills or spawns.
-- Toggle with the minimap button, a key binding, "/bb map" or a macro containing "/bb map".
local _, ns = ...

local Heat = { tiles = {}, cells = {}, follow = true, mode = "kills" }
ns.Heat = Heat

local MAP_W, MAP_H = 600, 400
local GRID_W, GRID_H = ns.HEAT_W or 60, ns.HEAT_H or 40
local CELL_W, CELL_H = MAP_W / GRID_W, MAP_H / GRID_H
local MODES = { "kills", "database", "gathering" }
local MODE_LABELS = { kills = "My kills", database = "Database", gathering = "Gathering" }

local STOPS = {
	{ 0.00, 0.20, 0.40, 1.00 },
	{ 0.33, 0.20, 0.90, 0.25 },
	{ 0.66, 1.00, 0.90, 0.00 },
	{ 1.00, 1.00, 0.10, 0.05 },
}

local function HeatColor(t)
	t = math.max(0, math.min(1, t))
	for i = 2, #STOPS do
		local a, b = STOPS[i - 1], STOPS[i]
		if t <= b[1] then
			local f = (t - a[1]) / (b[1] - a[1])
			return a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f, a[4] + (b[4] - a[4]) * f
		end
	end
	return STOPS[#STOPS][2], STOPS[#STOPS][3], STOPS[#STOPS][4]
end
Heat.HeatColor = HeatColor

local function MapName(mapID)
	local info = C_Map.GetMapInfo(mapID)
	return info and info.name or ("Map " .. mapID)
end

local function MobName(npcID)
	local mob = ns.db.mobs[npcID]
	if mob and mob.n then return mob.n end
	local m = ns.FarmDB and ns.FarmDB.mobs[npcID]
	return (m and m[1]) or ("NPC " .. npcID)
end

local function MobValue(npcID)
	if ns.Farm then return ns.Farm:MobValue(npcID) or 0 end
	return ns:GetMobValue(ns.db.mobs[npcID])
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
-- Returns a list of { index, kills, avg, mobs } and the highest average on the map.
function Heat:ComputeCells(mapID)
	local cells, maxAvg = {}, 0
	local function Push(index, count, total, ids)
		if count > 0 then
			local avg = total / count
			cells[#cells + 1] = { index = index, kills = count, avg = avg, mobs = ids }
			if avg > maxAvg then maxAvg = avg end
		end
	end
	if self.mode == "kills" then
		local data = ns.db.heat[mapID]
		if not data then return cells, 0 end
		local values = {}
		for index, cell in pairs(data) do
			local kills, value = 0, 0
			for npcID, n in pairs(cell) do
				values[npcID] = values[npcID] or MobValue(npcID)
				kills = kills + n
				value = value + n * values[npcID]
			end
			Push(index, kills, value, cell)
		end
	elseif ns.Farm and ns.FarmDB then
		local profs = ns.Farm:GetProfessions()
		local maps
		if self.mode == "database" then
			maps = ns.Farm:CollectKill(UnitLevel("player") or 1, profs, mapID)
		else
			maps = ns.Farm:CollectGather(profs, mapID)
		end
		for index, c in pairs(maps[mapID] or {}) do Push(index, c.spawns, c.total, c.ids) end
	end
	return cells, maxAvg
end

function Heat:MapsWithData()
	local list, seen = {}, {}
	local function Add(mapID)
		if not seen[mapID] then
			seen[mapID] = true
			list[#list + 1] = mapID
		end
	end
	if self.mode == "kills" or not ns.FarmDB then
		for mapID in pairs(ns.db.heat) do Add(mapID) end
	elseif self.mode == "database" then
		for _, m in pairs(ns.FarmDB.mobs) do
			for mapID in pairs(m[9]) do Add(mapID) end
		end
	else
		for _, node in ipairs(ns.FarmDB.nodes) do
			for mapID in pairs(node[5]) do Add(mapID) end
		end
	end
	table.sort(list, function(a, b) return MapName(a) < MapName(b) end)
	return list
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
function Heat:DrawTiles(mapID)
	for _, t in ipairs(self.tiles) do t:Hide() end
	local layers = C_Map.GetMapArtLayers(mapID)
	local layer = layers and layers[1]
	local textures = C_Map.GetMapArtLayerTextures(mapID, 1)
	if not layer or not textures then return end
	local sx, sy = MAP_W / layer.layerWidth, MAP_H / layer.layerHeight
	local cols = math.ceil(layer.layerWidth / layer.tileWidth)
	for i, fileID in ipairs(textures) do
		local t = self.tiles[i]
		if not t then
			t = self.map:CreateTexture(nil, "BORDER")
			self.tiles[i] = t
		end
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		t:SetTexture(fileID)
		t:SetSize(layer.tileWidth * sx, layer.tileHeight * sy)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", self.map, "TOPLEFT", col * layer.tileWidth * sx, -row * layer.tileHeight * sy)
		t:Show()
	end
end

local SUMMARY = {
	kills = "%d kills recorded here. Best cell: %s per kill.",
	database = "%d spawns for your level. Best cell: %s per kill.",
	gathering = "%d nodes you can gather. Best cell: %s per node.",
}

function Heat:DrawCells(mapID)
	for _, t in ipairs(self.cells) do t:Hide() end
	local cells, maxAvg = self:ComputeCells(mapID)
	self.cellData = {}
	local total = 0
	for i, cell in ipairs(cells) do
		self.cellData[cell.index] = cell
		total = total + cell.kills
		local t = self.cells[i]
		if not t then
			t = self.overlay:CreateTexture(nil, "ARTWORK")
			t:SetSize(CELL_W, CELL_H)
			self.cells[i] = t
		end
		local cx, cy = cell.index % GRID_W, math.floor(cell.index / GRID_W)
		local intensity = maxAvg > 0 and math.sqrt(cell.avg / maxAvg) or 0
		local r, g, b = HeatColor(intensity)
		t:SetColorTexture(r, g, b, 0.25 + 0.45 * math.min(1, cell.kills / 6))
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", self.map, "TOPLEFT", cx * CELL_W, -cy * CELL_H)
		t:Show()
	end
	self.summary:SetText(SUMMARY[self.mode]:format(total, ns.FormatMoney(maxAvg)))
end

function Heat:SetHighlight(spot)
	local box = self.highlight
	if not spot or not spot.cx then
		box:Hide()
		return
	end
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", self.map, "TOPLEFT", (spot.cx - 2) * CELL_W, -(spot.cy - 2) * CELL_H)
	box:SetSize(5 * CELL_W, 5 * CELL_H)
	box:Show()
end

function Heat:ShowMap(mapID)
	if not mapID then return end
	self.mapID = mapID
	self.frame.TitleText:SetText("BagBroker heatmap: " .. MapName(mapID))
	self.modeButton:SetText("Source: " .. MODE_LABELS[self.mode])
	self:DrawTiles(mapID)
	self:DrawCells(mapID)
	self.hoverIndex = nil
	if self.spot and self.spot.ui ~= mapID then self.spot = nil end
	self:SetHighlight(self.spot)
end

-- Called from the farming spots window.
function Heat:ShowSpot(row)
	self:Create()
	self.mode = row.kind == "gather" and "gathering" or "database"
	self.follow = false
	self.spot = row
	if not self.frame:IsShown() then self.frame:Show() end
	self:ShowMap(row.ui)
end

function Heat:CurrentMap()
	return C_Map.GetBestMapForUnit("player")
end

function Heat:Step(direction)
	local list = self:MapsWithData()
	if #list == 0 then return end
	local pos = 0
	for i, id in ipairs(list) do
		if id == self.mapID then pos = i end
	end
	pos = ((pos - 1 + direction) % #list) + 1
	self.follow = false
	self.spot = nil
	self:ShowMap(list[pos])
end

function Heat:CycleMode()
	local index = 1
	for i, m in ipairs(MODES) do
		if m == self.mode then index = i end
	end
	self.mode = MODES[index % #MODES + 1]
	self.spot = nil
	self:ShowMap(self.mapID or self:CurrentMap())
end

function Heat:UpdatePlayer()
	local arrow = self.arrow
	local pos = self.mapID and C_Map.GetPlayerMapPosition(self.mapID, "player")
	local x, y
	if pos then x, y = pos:GetXY() end
	if not x or ns.IsSecret(x) or x <= 0 or y <= 0 then
		arrow:Hide()
		return
	end
	arrow:ClearAllPoints()
	arrow:SetPoint("CENTER", self.map, "TOPLEFT", x * MAP_W, -y * MAP_H)
	local facing = GetPlayerFacing and GetPlayerFacing()
	if type(facing) == "number" and not ns.IsSecret(facing) then arrow:SetRotation(facing) end
	arrow:Show()
end

local function MoneyRow(label, copper)
	GameTooltip:AddDoubleLine(label, ns.CoinString(copper), 1, 1, 1, 1, 1, 1)
end

function Heat:ShowCellTooltip(cell)
	GameTooltip:SetOwner(self.map, "ANCHOR_CURSOR")
	local list = {}
	for id, n in pairs(cell.mobs) do list[#list + 1] = { id = id, n = n } end
	table.sort(list, function(a, b) return a.n > b.n end)
	if self.mode == "gathering" then
		MoneyRow(("Value per node (%d nodes)"):format(cell.kills), cell.avg)
		for i = 1, math.min(5, #list) do
			local node = ns.FarmDB.nodes[list[i].id]
			MoneyRow(("  %s (%d)"):format(node[1], list[i].n), ns.Farm:NodeValue(node))
		end
	else
		local what = self.mode == "kills" and "kills" or "spawns"
		MoneyRow(("Loot per kill (%d %s)"):format(cell.kills, what), cell.avg)
		for i = 1, math.min(5, #list) do
			local m = list[i]
			MoneyRow(("  %s (%d)"):format(MobName(m.id), m.n), MobValue(m.id))
		end
	end
	GameTooltip:Show()
end

function Heat:UpdateHover()
	local map = self.map
	if not map:IsMouseOver() then
		if self.hoverIndex then
			self.hoverIndex = nil
			GameTooltip:Hide()
		end
		return
	end
	local cursorX, cursorY = GetCursorPosition()
	local scale = map:GetEffectiveScale()
	local x = cursorX / scale - map:GetLeft()
	local y = map:GetTop() - cursorY / scale
	local index = math.floor(y / CELL_H) * GRID_W + math.floor(x / CELL_W)
	if index == self.hoverIndex then return end
	self.hoverIndex = index
	local cell = self.cellData and self.cellData[index]
	if not cell then
		GameTooltip:Hide()
		return
	end
	self:ShowCellTooltip(cell)
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
function Heat:Create()
	if self.frame then return self.frame end
	local f = ns:CreateWindow("BagBrokerHeatmap", UIParent, "BagBroker heatmap")
	f:SetSize(MAP_W + 20, MAP_H + 72)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	tinsert(UISpecialFrames, "BagBrokerHeatmap") -- Escape closes it
	self.frame = f

	local map = CreateFrame("Frame", nil, f)
	map:SetSize(MAP_W, MAP_H)
	map:SetPoint("TOPLEFT", 10, -28)
	map:SetClipsChildren(true)
	map:EnableMouse(true)
	local bg = map:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 1)
	self.map = map

	self.overlay = CreateFrame("Frame", nil, map)
	self.overlay:SetAllPoints()

	local box = CreateFrame("Frame", nil, self.overlay, "BackdropTemplate")
	if box.SetBackdrop then
		box:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
		box:SetBackdropBorderColor(1, 0.82, 0, 1)
	end
	box:Hide()
	self.highlight = box

	local arrow = self.overlay:CreateTexture(nil, "OVERLAY")
	arrow:SetSize(24, 24)
	arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
	self.arrow = arrow

	local function Button(text, width, onClick)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(width, 22)
		b:SetText(text)
		b:SetScript("OnClick", onClick)
		return b
	end
	local prev = Button("<", 28, function() self:Step(-1) end)
	prev:SetPoint("BOTTOMLEFT", 10, 10)
	local nextButton = Button(">", 28, function() self:Step(1) end)
	nextButton:SetPoint("LEFT", prev, "RIGHT", 2, 0)
	local here = Button("Current zone", 100, function()
		self.follow = true
		self.spot = nil
		self:ShowMap(self:CurrentMap())
	end)
	here:SetPoint("LEFT", nextButton, "RIGHT", 4, 0)
	self.modeButton = Button("Source: My kills", 130, function() self:CycleMode() end)
	self.modeButton:SetPoint("LEFT", here, "RIGHT", 4, 0)
	local spots = Button("Best spots", 90, function() BagBroker_ToggleFarmSpots() end)
	spots:SetPoint("BOTTOMRIGHT", -10, 10)

	self.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.summary:SetPoint("LEFT", self.modeButton, "RIGHT", 8, 6)
	self.summary:SetPoint("RIGHT", spots, "LEFT", -6, 0)
	self.summary:SetJustifyH("LEFT")
	self.summary:SetWordWrap(false)
	local legend = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	legend:SetPoint("LEFT", self.modeButton, "RIGHT", 8, -7)
	legend:SetPoint("RIGHT", spots, "LEFT", -6, 0)
	legend:SetJustifyH("LEFT")
	legend:SetWordWrap(false)
	legend:SetText("Blue low, red high value. Opacity: number of kills or spawns.")

	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.1 then return end
		elapsed = 0
		self:UpdatePlayer()
		self:UpdateHover()
	end)
	f:SetScript("OnShow", function()
		local mapID = (self.follow or not self.mapID) and self:CurrentMap() or self.mapID
		self:ShowMap(mapID)
	end)
	f:SetScript("OnHide", function() GameTooltip:Hide() end)
	return f
end

function Heat:Toggle()
	local f = self:Create()
	f:SetShown(not f:IsShown())
end

function BagBroker_ToggleHeatmap()
	Heat:Toggle()
end

ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
	if Heat.frame and Heat.frame:IsShown() and Heat.follow then Heat:ShowMap(Heat:CurrentMap()) end
end)

ns:On("KILL_RECORDED", function(mapID)
	if Heat.frame and Heat.frame:IsShown() and mapID == Heat.mapID and not Heat.redrawQueued then
		Heat.redrawQueued = true
		C_Timer.After(1, function()
			Heat.redrawQueued = false
			if Heat.frame:IsShown() and Heat.mapID then Heat:DrawCells(Heat.mapID) end
		end)
	end
end)

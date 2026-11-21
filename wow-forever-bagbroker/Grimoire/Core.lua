-- Grimoire: warlock coach for WoW Forever. Namespace, saved variables, events and helpers.
local ADDON_NAME, ns = ...

local issecret = issecretvalue or function() return false end
function ns.IsSecret(value) return value ~= nil and issecret(value) and true or false end

ns.defaults = {
	coachShown = true,
	coachScale = 1,
	weights = { sp = 1.0, stamina = 0.6, intellect = 0.45, spirit = 0.35 }, -- spell power > stamina > intellect > spirit
	levelsBelow = 6,      -- gear advisor: items down to this many levels below yours
	levelsAbove = 3,      -- ... and up to this many above (shown with the level they need)
	budget = nil,         -- copper per item; nil = 5% of your gold (50s to 50g)
	talentReminders = true,
}

local frame = CreateFrame("Frame")
local handlers, callbacks = {}, {}
local safecall = securecallfunction or function(fn, ...) return fn(...) end

function ns:RegisterEvent(event, fn)
	local list = handlers[event]
	if not list then
		if not pcall(frame.RegisterEvent, frame, event) then return end
		list = {}
		handlers[event] = list
	end
	list[#list + 1] = fn
end

frame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event] or {}) do safecall(fn, event, ...) end
end)

function ns:On(message, fn)
	callbacks[message] = callbacks[message] or {}
	table.insert(callbacks[message], fn)
end

function ns:Fire(message, ...)
	for _, fn in ipairs(callbacks[message] or {}) do safecall(fn, ...) end
end

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

ns:RegisterEvent("ADDON_LOADED", function(_, name)
	if name ~= ADDON_NAME then return end
	GrimoireDB = GrimoireDB or {}
	GrimoireDB.settings = CopyDefaults(ns.defaults, GrimoireDB.settings or {})
	ns.db = GrimoireDB
	ns.settings = GrimoireDB.settings
	ns:Fire("DB_READY")
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
	local _, class = UnitClass("player")
	ns.isWarlock = class == "WARLOCK"
	ns:Fire("LOGIN")
end)

function ns:Print(msg)
	if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9Grimoire|r: " .. tostring(msg)) end
end

-- A spell the character knows, by English name (returns spell ID and icon), or nil.
function ns.KnownSpell(name)
	if not name then return nil end
	local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
	if type(info) ~= "table" or not info.spellID then return nil end
	if IsPlayerSpell and not IsPlayerSpell(info.spellID) and not (IsSpellKnown and IsSpellKnown(info.spellID, true)) then
		return nil
	end
	return info.spellID, info.iconID
end

ns.MARKERS = {
	[8] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t", -- skull
	[7] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:0|t", -- cross
	[6] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6:0|t", -- square
	[5] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:0|t", -- moon
	[4] = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:0|t", -- triangle
}

-- Window helper: reuses BagBroker's look when it is installed.
function ns:CreateWindow(name, parent, title)
	if BagBrokerAPI and BagBrokerAPI.CreateWindow then return BagBrokerAPI.CreateWindow(name, parent, title) end
	local ok, f = pcall(CreateFrame, "Frame", name, parent, "BasicFrameTemplateWithInset")
	if not ok or not f then f = CreateFrame("Frame", name, parent, "BackdropTemplate") end
	if not f.TitleText then
		f.TitleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		f.TitleText:SetPoint("TOP", 0, -6)
	end
	f.TitleText:SetText(title)
	return f
end

function ns.FormatMoney(copper)
	if BagBrokerAPI then return BagBrokerAPI.FormatMoney(copper) end
	if GetMoneyString then return GetMoneyString(math.floor(copper + 0.5), true) end
	return tostring(math.floor(copper + 0.5)) .. "c"
end

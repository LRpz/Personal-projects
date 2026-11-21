-- Grimoire: slash commands (/grim) and key binding labels.
local _, ns = ...

BINDING_HEADER_GRIMOIRE = "Grimoire (warlock coach)"
_G["BINDING_NAME_CLICK GrimoireMain:LeftButton"] = "Coach: one key for all plans (Shift/Ctrl/Alt pick plans 2-4)"
_G["BINDING_NAME_CLICK GrimoirePlan1:LeftButton"] = "Coach: plan 1 (next step)"
_G["BINDING_NAME_CLICK GrimoirePlan2:LeftButton"] = "Coach: plan 2 (next step)"
_G["BINDING_NAME_CLICK GrimoirePlan3:LeftButton"] = "Coach: plan 3 (next step)"
_G["BINDING_NAME_CLICK GrimoirePlan4:LeftButton"] = "Coach: plan 4 (next step)"
BINDING_NAME_GRIMOIRE_TOGGLE_COACH = "Show or hide the coach"
BINDING_NAME_GRIMOIRE_TOGGLE_GUIDE = "Show or hide the talent guide"

function Grimoire_ToggleGuide()
	ns.Talents:Toggle()
end

local HELP = {
	"/grim coach - show or hide the combat coach (out of combat)",
	"/grim talents - talent plan, demons and tips",
	"/grim gear - how to open the gear upgrades tab",
	"/grim budget <price>|auto - max price per item for gear upgrades (auto = 5% of your gold)",
	"/grim scale <0.6-1.5> - coach size",
	"/grim reminders on|off - talent point reminders on level up",
}

SLASH_GRIMOIRE1 = "/grim"
SLASH_GRIMOIRE2 = "/grimoire"
SlashCmdList.GRIMOIRE = function(msg)
	local command, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	command = (command or ""):lower()
	if command == "coach" then
		Grimoire_ToggleCoach()
	elseif command == "talents" or command == "guide" then
		ns.Talents:Toggle()
	elseif command == "gear" then
		ns:Print("Open the auction house: the Gear tab sits under the BagBroker panel (needs BagBroker).")
	elseif command == "budget" then
		if rest == "auto" or rest == "" then
			ns.settings.budget = nil
		elseif BagBrokerAPI then
			local copper = BagBrokerAPI.ParseMoney(rest)
			if copper and copper > 0 then ns.settings.budget = copper end
		end
		ns:Print("Gear budget: " .. (ns.settings.budget and ns.FormatMoney(ns.settings.budget) or "5% of your gold"))
	elseif command == "scale" then
		local v = tonumber(rest)
		if v and v >= 0.6 and v <= 1.5 and not InCombatLockdown() then
			ns.settings.coachScale = v
			if ns.Coach.frame then ns.Coach.frame:SetScale(v) end
		end
	elseif command == "reminders" then
		ns.settings.talentReminders = rest ~= "off"
		ns:Print("Talent reminders " .. (ns.settings.talentReminders and "on" or "off") .. ".")
	else
		ns:Print("Commands:")
		for _, line in ipairs(HELP) do ns:Print("  " .. line) end
	end
end

-- Grimoire tests: loads BagBroker and Grimoire in TOC order inside the mock client.
-- Usage (from the repository folder): lua5.1 tests/run_grimoire_tests.lua
package.path = "tests/?.lua;" .. package.path
local M = require("mock_wow")

local function Load(dir, toc, ns)
	for line in io.lines(dir .. toc) do
		if line:match("%.lua%s*$") then
			assert(loadfile(dir .. line:match("^%s*(.-)%s*$")))(toc:match("^(.-)%.toc$"), ns)
		end
	end
end

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed = passed + 1; print("PASS  " .. name)
	else failed = failed + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg)
	if a ~= b then error(("%s: expected %s, got %s"):format(msg or "value", tostring(b), tostring(a)), 2) end
end
local function truthy(v, msg) if not v then error(msg or "expected true", 2) end end

-- Fixtures --------------------------------------------------------------------------------------
M.items = {
	-- gear (cloth unless noted); bindType 2 = bind on equip
	[9001] = { name = "Robe of the Void", quality = 2, classID = 4, subclassID = 1, equipLoc = "INVTYPE_ROBE", minLevel = 22, bindType = 2, sellPrice = 500 },
	[9002] = { name = "Leather Vest", quality = 2, classID = 4, subclassID = 2, equipLoc = "INVTYPE_CHEST", minLevel = 22, bindType = 2, sellPrice = 500 },
	[9003] = { name = "Pricey Robe", quality = 3, classID = 4, subclassID = 1, equipLoc = "INVTYPE_ROBE", minLevel = 23, bindType = 2, sellPrice = 900 },
	[9004] = { name = "Owl Ring", quality = 2, classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER", minLevel = 20, bindType = 2, sellPrice = 300 },
	[9005] = { name = "Future Staff", quality = 2, classID = 2, subclassID = 10, equipLoc = "INVTYPE_2HWEAPON", minLevel = 26, bindType = 2, sellPrice = 900 },
	[9006] = { name = "Ancient Cowl", quality = 2, classID = 4, subclassID = 1, equipLoc = "INVTYPE_HEAD", minLevel = 10, bindType = 2, sellPrice = 100 },
	[9007] = { name = "Small Robe", quality = 2, classID = 4, subclassID = 1, equipLoc = "INVTYPE_ROBE", minLevel = 21, bindType = 2, sellPrice = 300 },
	[9100] = { name = "Worn Robe", quality = 1, classID = 4, subclassID = 1, equipLoc = "INVTYPE_ROBE", minLevel = 15 },
	[9101] = { name = "Worn Ring", quality = 1, classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER", minLevel = 10 },
}
M.itemStats = {
	[9001] = { ITEM_MOD_STAMINA_SHORT = 8, ITEM_MOD_INTELLECT_SHORT = 6 },
	[9002] = { ITEM_MOD_STAMINA_SHORT = 20 },
	[9003] = { ITEM_MOD_STAMINA_SHORT = 15, ITEM_MOD_INTELLECT_SHORT = 15 },
	[9004] = { ITEM_MOD_INTELLECT_SHORT = 5, ITEM_MOD_SPIRIT_SHORT = 5 },
	[9005] = { ITEM_MOD_STAMINA_SHORT = 12, ITEM_MOD_INTELLECT_SHORT = 12 },
	[9006] = { ITEM_MOD_STAMINA_SHORT = 3 },
	[9007] = { ITEM_MOD_STAMINA_SHORT = 4 },
	[9100] = { ITEM_MOD_STAMINA_SHORT = 2 },
	[9101] = { ITEM_MOD_SPIRIT_SHORT = 1 },
}
M.itemText = {
	[9001] = { "Robe of the Void", "Equip: Increases damage done by Shadow spells and effects by up to 7." },
	[9004] = { "Owl Ring" },
}
M.equippedLinks = { [5] = M.Link(9100), [11] = M.Link(9101), [12] = M.Link(9101) }
M.level = 22
M.money = 200000  -- 20g: default budget 5% = 1g
M.knownSpells = {
	["Corruption"] = { 172, 136118 }, ["Bane of Agony"] = { 980, 136139 }, ["Immolate"] = { 348, 135817 },
	["Drain Life"] = { 689, 136169 }, ["Fear"] = { 5782, 136183 }, ["Life Tap"] = { 1454, 136126 },
	["Health Funnel"] = { 755, 136168 }, ["Drain Soul"] = { 1120, 136163 },
	["Suffering"] = { 17735, 136220, pet = true }, ["Sacrifice"] = { 7812, 136190, pet = true },
	["Seduction"] = { 6358, 136175, pet = true },
}
M.petFamily = "Voidwalker"
M.units.pet = { guid = "Pet-0-1", name = "Voidwalker" }

local bb, gr = {}, {}
Load("BagBroker/", "BagBroker.toc", bb)
Load("Grimoire/", "Grimoire.toc", gr)
M.Fire("ADDON_LOADED", "BagBroker")
M.Fire("ADDON_LOADED", "Grimoire")
M.Fire("PLAYER_LOGIN")

-- Talent plan -----------------------------------------------------------------------------------
test("talent plan: one point per level 10-60, ranks in order, every tree gate respected", function()
	eq(#gr.TALENT_PLAN, 51, "points")
	local inTree, ranks = { Affliction = 0, Demonology = 0, Destruction = 0 }, {}
	for i, step in ipairs(gr.TALENT_PLAN) do
		local level, nodeID, rank = step[1], step[2], step[3]
		eq(level, 9 + i, "level of point " .. i)
		local node = gr.TALENT_NODES[nodeID]
		truthy(node, "known node " .. nodeID)
		eq(rank, (ranks[nodeID] or 0) + 1, node[1] .. " rank order")
		truthy(rank <= node[4], node[1] .. " max rank")
		truthy(inTree[node[2]] >= node[5], ("%s needs %d points in %s, has %d"):format(node[1], node[5], node[2], inTree[node[2]]))
		ranks[nodeID] = rank
		inTree[node[2]] = inTree[node[2]] + 1
	end
	eq(inTree.Affliction, 40, "Affliction points")
	eq(inTree.Demonology, 11, "Demonology points")
end)

test("talent status: done, next and due points from the talent system", function()
	M.talents = { [105924] = 2 }  -- Improved Corruption 2/5
	local due = gr.Talents:NextSteps(13, gr.Talents:LearnedRanks())
	eq(#due, 2, "two points due at level 13")
	eq(gr.TALENT_NODES[due[1].nodeID][1] .. " " .. due[1].rank, "Improved Corruption 3")
	gr.Talents:Toggle()
	truthy(gr.Talents.frame.summary.text:find("Next: Improved Corruption 3/5", 1, true), gr.Talents.frame.summary.text)
	gr.Talents:Toggle()
end)

-- Coach -----------------------------------------------------------------------------------------
test("coach builds the Voidwalker plans from known spells, with macro conditions and raid icons", function()
	local coach = gr.Coach
	truthy(coach.frame and coach.frame:IsShown(), "coach shown")
	eq(coach.petKey, "Voidwalker")
	local two = coach:Plans()[2]
	eq(two.title, "Two mobs")
	eq(#two.steps, 5, "Siphon Life is not known yet: skipped")
	local b = coach.buttons[2]
	eq(b:GetAttribute("step1"), "/targetenemy [noexists][dead][noharm]\n/tm 8\n/petattack [@target,harm,nodead]\n/cast [@target,harm,nodead] Bane of Agony")
	eq(b:GetAttribute("step3"), "/targetenemy\n/tm 7\n/cast [@target,harm,nodead] Bane of Agony")
	eq(b:GetAttribute("loopStart"), 5, "loop starts with Drain Life")
	local single = coach:Plans()[1]
	eq(single.steps[3].spell, "Immolate", "Immolate below 30, Siphon Life skipped")
end)

test("coach presses step through the opener, loop the filler, reset on right-click and combat end", function()
	local b = gr.Coach.buttons[2]
	local macros = {}
	for i = 1, 7 do macros[i] = M.Press(b) end
	truthy(macros[1]:find("Bane of Agony", 1, true) and macros[2]:find("Corruption", 1, true), "opener order")
	truthy(macros[5]:find("Drain Life", 1, true) and macros[6]:find("Drain Life", 1, true) and macros[7]:find("Drain Life", 1, true), "loop repeats")
	eq(gr.Coach.activePlan, 2, "panel follows the pressed plan")
	truthy(gr.Coach.frame.rows[5].highlight.shown, "next step highlighted")
	eq(M.Press(b, "RightButton"), nil, "right-click casts nothing")
	truthy(M.Press(b):find("Bane of Agony", 1, true), "restarted")
	M.EndCombat(b)
	eq(b:GetAttribute("index"), 1, "combat end resets")
end)

test("one key drives every plan through modifier conditions", function()
	eq(gr.Coach.router:GetAttribute("macrotext"),
		"/click [mod:alt] GrimoirePlan4; [mod:ctrl] GrimoirePlan3; [mod:shift] GrimoirePlan2; GrimoirePlan1")
end)

test("coach follows the demon: Succubus plans use Seduction", function()
	M.petFamily = "Sayaad"
	M.Fire("UNIT_PET", "player")
	local coach = gr.Coach
	eq(coach.petKey, "Succubus", "Sayaad treated as Succubus")
	local two = coach:Plans()[2]
	eq(two.title, "Two humanoids")
	truthy(coach.buttons[2]:GetAttribute("step1"):find("Seduction", 1, true), "Seduction first")
	eq(coach.utility[1].data.spell, "Seduction", "utility row follows the demon")
	truthy(coach.frame.advice.text:find("Succubus", 1, true), "advice line")
	M.petFamily = "Voidwalker"
	M.Fire("UNIT_PET", "player")
	eq(coach.petKey, "Voidwalker")
end)

test("coach rebuilds after combat when spells change during a fight", function()
	M.combat = true
	M.knownSpells["Siphon Life"] = { 18265, 136188 }
	M.Fire("SPELLS_CHANGED")
	eq(#gr.Coach:Plans()[2].steps, 5, "no rebuild in combat")
	M.combat = false
	M.Fire("PLAYER_REGEN_ENABLED")
	eq(#gr.Coach:Plans()[2].steps, 6, "Siphon Life added after combat")
	M.knownSpells["Siphon Life"] = nil
end)

-- Trainer ---------------------------------------------------------------------------------------
test("trainer panel rates spells and learns all core spells in one click", function()
	M.trainer = {
		{ "Corruption", "available", 1, 22, 600 },
		{ "Searing Pain", "available", 1, 22, 600 },
		{ "Rain of Fire", "available", 1, 20, 900 },
		{ "Drain Life", "available", 1, 22, 700 },
		{ "Howl of Terror", "unavailable", 1, 40, 0 },
	}
	M.ResetCalls()
	M.Fire("TRAINER_SHOW")
	M.Advance(0.2)
	local t = gr.Trainer
	truthy(t.frame and t.frame:IsShown(), "panel shown")
	truthy(t.frame.summary.text:find("2 core spell(s)", 1, true), t.frame.summary.text)
	eq(t.frame.learn.text, "Learn core spells (2)")
	t.frame.learn.scripts.OnClick(t.frame.learn)
	local bought = {}
	for _, c in ipairs(M.calls) do if c[1] == "BuyTrainerService" then bought[#bought + 1] = c[3] end end
	eq(table.concat(bought, ","), "Drain Life,Corruption", "core only, highest index first")
end)

-- Gear ------------------------------------------------------------------------------------------
test("full scan keeps the cheapest auction link per equipment item for gear advisors", function()
	M.replicate = {
		{ itemID = 9001, count = 1, buyout = 9000, quality = 2 },
		{ itemID = 9001, count = 1, buyout = 7000, quality = 2 },
		{ itemID = 9100, count = 1, buyout = 100, quality = 1 },   -- white: ignored
		{ itemID = 2589, count = 20, buyout = 400, quality = 1 },
	}
	bb:GetRealmData().lastScan = 0
	M.Fire("AUCTION_HOUSE_SHOW")
	M.Advance(1.5)
	M.Fire("REPLICATE_ITEM_LIST_UPDATE")
	M.Advance(1)
	local gear = BagBrokerAPI.GetGearCandidates()
	eq(#gear, 1, "one variant")
	eq(gear[1][2], 7000, "cheapest kept")
end)

test("gear advisor: best upgrade per slot within budget, warlock-usable, level window", function()
	bb:GetRealmData().gear = {
		{ M.Link(9001), 7000 },   -- robe: +8 sta +6 int +7 shadow -> big upgrade, 70s
		{ M.Link(9002), 1000 },   -- leather: not usable
		{ M.Link(9003), 300000 }, -- better robe but 30g: over the 1g budget
		{ M.Link(9007), 2000 },   -- cheaper, smaller robe upgrade
		{ M.Link(9004), 5000 },   -- ring
		{ M.Link(9005), 9000 },   -- staff needing level 26 (window +3 = 25): excluded
		{ M.Link(9006), 500 },    -- level 10 head: below the window (22 - 6 = 16)
	}
	local rows, considered, pending, budget = gr.Gear:Evaluate()
	eq(budget, 10000, "5% of 20g")
	eq(pending, 0)
	eq(#rows, 2, "chest and ring")
	eq(rows[1].name, "Robe of the Void", "best chest, not the cheapest")
	local w = gr.settings.weights
	local expected = 7 * w.sp + 8 * w.stamina + 6 * w.intellect - 2 * w.stamina
	truthy(math.abs(rows[1].gain - expected) < 0.01, ("gain %.2f vs %.2f"):format(rows[1].gain, expected))
	eq(rows[2].slot, "Ring")
	gr.settings.levelsAbove = 4
	rows = gr.Gear:Evaluate()
	local future
	for _, r in ipairs(rows) do if r.future then future = r end end
	truthy(future and future.name == "Future Staff" and future.minLevel == 26, "upcoming item listed with its level")
	eq(rows[#rows].future, true, "upcoming items after wearable ones")
	gr.settings.levelsAbove = 3
	gr.settings.budget = 400000
	rows = gr.Gear:Evaluate()
	local chest
	for _, r in ipairs(rows) do if r.slot == "Chest" then chest = r end end
	eq(chest.name, "Pricey Robe", "a bigger budget picks the better robe")
	eq(chest.future, true, "it needs level 23, so it is listed after wearable items")
	gr.settings.budget = nil
end)

test("gear tab appears in BagBroker's auction panel and fills its rows", function()
	local panel = bb.Panel
	truthy(panel.frame, "panel created during the scan test")
	eq(#panel.tabs, 2, "Sell and Gear")
	truthy(panel.tabButtons[2].shown, "tab buttons visible")
	panel:SelectTab("gear")
	eq(panel.frame.TitleText.text, "Grimoire: best upgrades in budget")
	eq(panel.sellPage:IsShown(), false, "sell page hidden")
	local row = gr.Gear.rows[1]
	truthy(row and row.shown, "row shown")
	truthy(row.name.text:find("Robe of the Void", 1, true), row.name.text)
	truthy(row.gain.text:find("+", 1, true), "gain shown")
	row.scripts.OnClick(row)
	eq(M.searchText, "Robe of the Void", "row click searches the item in the auction house")
	panel:SelectTab("sell")
	eq(panel.sellPage:IsShown(), true)
end)

test("slash commands set the gear budget", function()
	SlashCmdList.GRIMOIRE("budget 2g")
	eq(gr.settings.budget, 20000)
	SlashCmdList.GRIMOIRE("budget auto")
	eq(gr.settings.budget, nil)
end)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)

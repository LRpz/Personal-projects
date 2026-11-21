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
	["Shadow Bolt"] = { 686, 136197 }, ["Shoot"] = { 5019, 135463 }, ["Death Coil"] = { 6789, 136145 },
}
M.otherSpells = { ["Siphon Life"] = { 18265, 136188 }, ["Searing Pain"] = { 5676, 135827 } }
M.spellText = {
	["Corruption"] = "Corrupts the target, causing 90 Shadow damage over 18 sec.",
	["Bane of Agony"] = "Curses the target with agony, causing 240 Shadow damage over 24 sec. This damage is dealt slowly at first.",
	["Immolate"] = "Burns the enemy for 40 Fire damage and then an additional 60 Fire damage over 15 sec.",
	["Siphon Life"] = "Transfers 15 health from the target to the caster every 3 sec. Lasts 30 sec.",
	["Drain Life"] = "Transfers 10 health every 1 sec from the target to the caster for 5 sec.",
	["Drain Soul"] = "Drains the soul of the target, causing 150 Shadow damage over 15 sec.",
	["Fear"] = "Strikes fear in the enemy, causing it to run in fear for up to 15 sec.",
	["Life Tap"] = "Converts 60 health into 60 mana.",
}
M.spellCooldowns = { ["Death Coil"] = 120000 }
M.petFamily = "Voidwalker"
M.units.pet = { guid = "Pet-0-1", name = "Voidwalker" }
M.units.player = { guid = "Player-1-1", name = "Me", hp = 1000, max = 1000 }

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

-- Coach and assistant ----------------------------------------------------------------------------
local A, S, C = gr.Assist, gr.Spells, gr.Coach
local function Cast(spellID, castGUID)
	M.Fire("UNIT_SPELLCAST_SENT", "player", nil, castGUID, spellID)
	M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", castGUID, spellID)
end
local function Rec() A:Update(0.1); return A.last end
local function Queue(rec, token)
	local list = {}
	for _, s in ipairs(rec.queues[A.byToken[token]] or {}) do list[#list + 1] = s end
	return table.concat(list, ",")
end
local function Kobold(guid, hp, extra)
	local u = { guid = "Creature-0-1-2-3-" .. (extra and extra.npc or 1001) .. "-" .. guid, name = "Kobold", hp = hp, max = hp, level = 20,
		creatureType = "Humanoid", combat = false }
	for k, v in pairs(extra or {}) do u[k] = v end
	return u
end

test("spells: damage and duration read from tooltips at your rank", function()
	local d, t = S.ParseDescription(M.spellText["Corruption"]); eq(d, 90); eq(t, 18)
	d, t = S.ParseDescription(M.spellText["Siphon Life"]); eq(d, 150, "per tick x ticks"); eq(t, 30)
	d, t = S.ParseDescription(M.spellText["Drain Life"]); eq(d, 50); eq(t, 5)
	d, t = S.ParseDescription(M.spellText["Immolate"]); eq(d, 60, "the DoT part"); eq(t, 15)
	d, t = S.ParseDescription(M.spellText["Fear"]); eq(d, nil); eq(t, 15)
	d = S.ParseDescription("Instantly blasts the target for 91 to 104 Shadow damage."); eq(d, 97.5, "direct damage range")
	eq(S:Damage("Bane of Agony"), 240, "known spells cached at login")
	eq(S.info["Life Tap"].healthCost, 60)
	eq(S:Cooldown("Death Coil"), 120)
end)

test("talents decide the specialization (Affliction before any point)", function()
	eq(gr.Talents:Spec(), "Affliction")
	M.talents = { [105906] = 5, [105907] = 3 }  -- Unholy Power, Demonic Embrace
	M.Fire("TRAIT_CONFIG_UPDATED")
	eq(gr.Talents:Spec(), "Demonology")
	M.talents = { [105924] = 2 }
	M.Fire("TRAIT_CONFIG_UPDATED")
	eq(gr.Talents:Spec(), "Affliction")
end)

test("one key: Affliction order (Agony, Corruption), drains to refill, demon sent only when idle", function()
	truthy(C.frame and C.frame:IsShown(), "coach shown")
	eq(C.petKey, "Voidwalker")
	eq(C.roles.dot:GetAttribute("macrotext"), table.concat({
		"/targetenemy [noexists][dead][noharm]",
		"/castsequence [@target,harm,nodead,nochanneling] reset=target/combat Bane of Agony, Corruption, Drain Life, Drain Life, Drain Life",
		"/stopmacro [@pettarget,exists,nodead]",
		"/petattack [@target,harm,nodead]" }, "\n"), "Immolate is left to the assistant (high-health enemies only)")
	eq(C.roles.filler:GetAttribute("macrotext"), "/targetenemy [noexists][dead][noharm]\n/cast [@target,harm,nodead,nochanneling] Drain Life")
	eq(C.roles.control:GetAttribute("macrotext"), "/cast [@target,harm,nodead] Fear")
	eq(C.roles.save:GetAttribute("macrotext"), "/cast [@pet,exists,nodead,nochanneling] Health Funnel; [@target,harm,nodead] Death Coil")
	eq(C.router:GetAttribute("macrotext"), "/click [mod:alt] GrimoireSave; [mod:ctrl] GrimoireControl; [mod:shift] GrimoireFiller; GrimoireDot")
end)

test("one key: Succubus control is Seduction with the demon's family, then Fear", function()
	M.petFamily = "Sayaad"
	M.Fire("UNIT_PET", "player")
	eq(C.petKey, "Succubus")
	eq(C.roles.control:GetAttribute("macrotext"), "/cast [@target,harm,nodead,pet:Sayaad] Seduction; [@target,harm,nodead] Fear")
	eq(C.utility[1].data.spell, "Seduction", "utility row follows the demon")
	M.petFamily = "Voidwalker"
	M.Fire("UNIT_PET", "player")
	eq(C.petKey, "Voidwalker")
end)

test("assist: opener queue on a hostile target before the pull, with its key", function()
	M.bindings["CLICK GrimoireMain:LeftButton"] = "F"
	M.AddPlate("nameplate1", Kobold("A", 600))
	M.targetToken = "nameplate1"
	M.Fire("PLAYER_TARGET_CHANGED")
	local rec = Rec()
	eq(rec.prepull, true)
	eq(Queue(rec, "nameplate1"), "Bane of Agony,Corruption,Immolate", "600 health: lives through Immolate")
	eq(rec.spell, "Bane of Agony")
	eq(rec.switch, false)
	eq(A:KeyHint("Bane of Agony"), "F", "the one key casts it next")
	truthy(C.frame.nowKey.text:find("[F]", 1, true), C.frame.nowKey.text)
	local w = gr.Plates.widgets[M.plates.nameplate1]
	truthy(w and w.shown, "nameplate widget shown")
	eq(w.queue[1].texture, 136139, "Agony icon first on the plate")
	eq(w.label.text, "|cff40ff40NOW|r")
end)

test("assist: a cast leaves the queue; its first tick confirms it landed", function()
	M.combat = true
	M.units.nameplate1.combat = true
	M.units.nameplate1.target = "pet"
	M.petTarget = "nameplate1"
	M.Fire("PLAYER_REGEN_DISABLED")
	M.secretHealth = true  -- Forever hides health in combat
	Cast(980, "cast-1")    -- Bane of Agony
	local mob = A.byToken.nameplate1
	eq(mob.dots["Bane of Agony"].status, "pending")
	eq(A.seqIndex, 2, "the one key moved to Corruption")
	local rec = Rec()
	eq(Queue(rec, "nameplate1"), "Corruption,Immolate")
	eq(A:KeyHint("Corruption"), "F")
	M.Advance(2)
	M.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 10, 32)
	eq(mob.dots["Bane of Agony"].status, "landed", "a shadow tick confirms it")
	eq(A:Health(mob), 590, "health followed from readable damage")
end)

test("assist: a resist puts the spell back in that enemy's queue", function()
	Cast(172, "cast-2")    -- Corruption
	M.Fire("UNIT_COMBAT", "nameplate1", "RESIST", "", 0, 32)
	local mob = A.byToken.nameplate1
	eq(mob.dots["Corruption"], nil, "removed")
	local rec = Rec()
	eq(rec.queues[mob][1], "Corruption", "back first in the queue")
	truthy(mob.flash.text == "Corruption resisted", mob.flash.text)
	truthy(gr.Plates.widgets[M.plates.nameplate1].note.text:find("resisted", 1, true), "note on the plate")
	M.Advance(1)
	Cast(172, "cast-3")
	M.Advance(3)
	M.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 15, 32)
	eq(mob.dots["Corruption"].status, "landed")
end)

test("assist: a third enemy is Feared first, then the next undotted enemy is focused", function()
	M.AddPlate("nameplate2", Kobold("B", 600, { combat = true, target = "pet" }))
	M.AddPlate("nameplate3", Kobold("C", 600, { combat = true, target = "player" }))
	local rec = Rec()
	eq(rec.n, 3)
	eq(rec.spell, "Fear", "Voidwalker handles two without Siphon Life")
	eq(rec.focus, A.byToken.nameplate3, "the one hitting you")
	eq(rec.switch, true)
	truthy(C.frame.nowWhere.text:find("switch", 1, true), C.frame.nowWhere.text)
	eq(gr.Plates.widgets[M.plates.nameplate3].label.text, "|cffffd200NEXT|r")
	M.targetToken = "nameplate3"
	M.Fire("PLAYER_TARGET_CHANGED")
	Cast(5782, "cast-4")  -- Fear
	rec = Rec()
	eq(rec.focus, A.byToken.nameplate2, "the fresh enemy next: most DoTs missing")
	eq(Queue(rec, "nameplate3"), "", "hands off the feared enemy")
	M.Advance(2)
	M.Fire("UNIT_COMBAT", "nameplate3", "WOUND", "", 20, 1)
	eq(A.byToken.nameplate3.control, nil, "damage broke Fear")
	rec = Rec()
	eq(rec.spell, "Fear", "Fear it again")
end)

test("assist: no more casts on an enemy your DoTs already kill; skips DoTs that will not finish", function()
	M.combat, M.secretHealth = false, false
	M.Fire("PLAYER_REGEN_ENABLED")
	for _, t in ipairs({ "nameplate1", "nameplate2", "nameplate3" }) do M.RemovePlate(t) end
	M.AddPlate("nameplate4", Kobold("D", 280, { combat = true, target = "pet" }))
	M.targetToken = "nameplate4"
	M.Fire("PLAYER_TARGET_CHANGED")
	M.combat, M.secretHealth = true, true
	M.Fire("PLAYER_REGEN_DISABLED")
	local rec = Rec()
	eq(Queue(rec, "nameplate4"), "Bane of Agony,Corruption,Immolate")
	Cast(980, "cast-5")
	rec = Rec()
	eq(Queue(rec, "nameplate4"), "Corruption", "40 health beyond Agony: Immolate (60) would not finish, Corruption still pays")
	Cast(172, "cast-6")
	rec = Rec()
	local st = rec.status[A.byToken.nameplate4]
	eq(st.dies, true, "330 DoT damage left vs 280 health")
	eq(Queue(rec, "nameplate4"), "")
	truthy(gr.Plates.widgets[M.plates.nameplate4].note.text:find("dies", 1, true), "plate says it dies")
	M.itemCounts[6265] = 1
	eq(rec.spell, "Drain Soul", "few shards and it dies during the channel")
	M.itemCounts[6265] = 10
	gr.Assist.vitals.player.sync = nil
	rec = Rec()
	eq(rec.spell, "Drain Life", "enough shards: drain (your health unknown)")
end)

test("assist: your health decides drain or wand; demon health asks for Health Funnel", function()
	local v = A.vitals.player
	v.max, v.sync = 1000, { health = 1000, net = v.taken - v.healed, time = GetTime() }
	local rec = Rec()
	eq(rec.spell, "Shoot", "healthy and the enemy dies to DoTs: wand")
	M.Fire("UNIT_COMBAT", "player", "WOUND", "", 400, 1)
	rec = Rec()
	eq(rec.spell, "Drain Life", "below 70%: drain")
	eq(math.floor(rec.playerShare * 100 + 0.5), 60)
	local pv = A.vitals.pet
	pv.max, pv.sync = 500, { health = 500, net = pv.taken - pv.healed, time = GetTime() }
	M.Fire("UNIT_COMBAT", "pet", "WOUND", "", 300, 1)
	rec = Rec()
	eq(rec.spell, "Health Funnel", "demon below half, you above half")
	eq(rec.self, true)
	truthy(C.frame.nowWhere.text:find("your demon", 1, true), C.frame.nowWhere.text)
	M.units.nameplate4.target = "player"
	M.Fire("UNIT_COMBAT", "player", "WOUND", "", 350, 1)
	rec = Rec()
	eq(rec.spell, "Death Coil", "below 35% and it is hitting you")
	M.Fire("UNIT_COMBAT", "player", "HEAL", "", 600, 32)
	M.Fire("UNIT_COMBAT", "pet", "HEAL", "", 300, 32)
end)

test("assist: health learned from a full kill teaches the next one of its kind", function()
	local mob = A.byToken.nameplate4
	M.Fire("UNIT_COMBAT", "nameplate4", "WOUND", "", 200, 32)
	M.Fire("UNIT_COMBAT", "nameplate4", "WOUND", "", 140, 1)
	M.units.nameplate4.dead = true
	M.RemovePlate("nameplate4")
	eq(gr.db.health["n1001:20"].max, 280, "read before the pull: exact")
	M.AddPlate("nameplate5", Kobold("E", 450, { npc = 2002, combat = true, target = "pet" }))
	local e = A.byToken.nameplate5
	eq(A:Health(e), nil, "never seen: unknown")
	M.Fire("UNIT_COMBAT", "nameplate5", "WOUND", "", 250, 1)
	M.Fire("UNIT_COMBAT", "nameplate5", "WOUND", "", 200, 1)
	M.units.nameplate5.dead = true
	M.RemovePlate("nameplate5")
	eq(gr.db.health["n2002:20"].max, 450, "learned from the damage it took")
	M.AddPlate("nameplate6", Kobold("F", 450, { npc = 2002, combat = true, target = "pet" }))
	M.Fire("UNIT_COMBAT", "nameplate6", "WOUND", "", 100, 1)
	eq(A:Health(A.byToken.nameplate6), 350, "the next one starts from the learned health")
	M.RemovePlate("nameplate6")
end)

test("assist: DoT damage correction learned from the ticks you see", function()
	M.combat, M.secretHealth = false, false
	M.Fire("PLAYER_REGEN_ENABLED")
	M.AddPlate("nameplate7", Kobold("G", 5000, { combat = true, target = "pet" }))
	M.targetToken = "nameplate7"
	M.Fire("PLAYER_TARGET_CHANGED")
	M.combat = true
	M.Fire("PLAYER_REGEN_DISABLED")
	Cast(172, "cast-7")
	for _ = 1, 6 do
		M.Advance(2.9)
		A:Update(2.9)
		M.Fire("UNIT_COMBAT", "nameplate7", "WOUND", "", 21.75, 32)
	end
	M.combat = false
	M.Fire("PLAYER_REGEN_ENABLED")
	truthy(gr.db.dotMultiplier and math.abs(gr.db.dotMultiplier - 1.2) < 0.01,
		"130.5 seen / 87 expected -> 1.5, blended to 1.2: " .. tostring(gr.db.dotMultiplier))
	gr.db.dotMultiplier = nil
	M.RemovePlate("nameplate7")
end)

test("assist: Shadow Trance proc asks for an instant Shadow Bolt; secret identity is tolerated", function()
	M.AddPlate("nameplate8", Kobold("H", 900, { combat = true, target = "pet" }))
	M.targetToken = "nameplate8"
	M.Fire("PLAYER_TARGET_CHANGED")
	M.combat = true
	M.Fire("PLAYER_REGEN_DISABLED")
	M.Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 686)
	local rec = Rec()
	eq(rec.spell, "Shadow Bolt")
	eq(rec.rule, "nightfall")
	M.Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 686)
	M.secretIdentity = true
	rec = Rec()
	eq(rec.n, 1, "in combat and engaged even when who-it-attacks is hidden")
	M.secretIdentity = false
end)

test("assist: the action button holding the spell lights up and names its key", function()
	local button = CreateFrame("Button", "ActionButton3", UIParent)
	button.action = 3
	M.actions[3] = { "spell", 980 }
	M.bindings["ACTIONBUTTON3"] = "SHIFT-3"
	M.combat = false
	M.Fire("ACTIONBAR_SLOT_CHANGED")
	M.combat = true
	eq(S:KeyFor("Bane of Agony"), "s3")
	local rec = Rec()
	eq(rec.spell, "Bane of Agony")
	truthy(S.overlays[button] and S.overlays[button].shown, "glow shown")
	M.bindings["CLICK GrimoireMain:LeftButton"] = nil
	eq(A:KeyHint("Bane of Agony"), "s3", "without the one key, the bar key")
end)

test("assist: Destruction rules: Conflagrate as Immolate ends, Shadowburn to finish", function()
	M.knownSpells["Conflagrate"] = { 17962, 135807 }
	M.knownSpells["Shadowburn"] = { 17877, 136191 }
	M.spellText["Shadowburn"] = "Instantly blasts the target for 120 Shadow damage."
	M.spellCooldowns["Conflagrate"], M.spellCooldowns["Shadowburn"] = 10000, 15000
	M.talents = { [105924] = 2, [105889] = 1 }
	for nodeID, node in pairs(gr.TALENT_NODES) do
		if node[1] == "Shadowburn" or node[1] == "Bane" then M.talents[nodeID] = 5 end
	end
	M.combat = false
	M.Fire("SPELLS_CHANGED")
	M.Fire("TRAIT_CONFIG_UPDATED")
	eq(gr.Talents:Spec(), "Destruction")
	truthy(C.roles.dot:GetAttribute("macrotext"):find("Immolate, Corruption, Bane of Agony, Shadow Bolt", 1, true), C.roles.dot:GetAttribute("macrotext"))
	M.combat = true
	local mob = A.byToken.nameplate8
	M.Fire("PLAYER_TARGET_CHANGED")
	Cast(348, "cast-8")   -- Immolate
	M.Advance(13)
	local rec = Rec()
	eq(rec.spell, "Conflagrate", "two seconds of Immolate left")
	A.cooldowns["Conflagrate"] = GetTime() + 10
	M.itemCounts[6265] = 3
	mob.sync = { health = 100, net = mob.taken - mob.healed }
	mob.dots = {}
	rec = Rec()
	eq(rec.spell, "Shadowburn", "100 health left, Shadowburn hits for 120")
	M.knownSpells["Conflagrate"], M.knownSpells["Shadowburn"] = nil, nil
	M.talents = { [105924] = 2 }
	M.combat = false
	M.Fire("SPELLS_CHANGED")
	M.Fire("TRAIT_CONFIG_UPDATED")
	M.Fire("PLAYER_REGEN_ENABLED")
end)

test("hints: the game's curves light Health Funnel (demon below half) and Life Tap (low mana)", function()
	M.units.pet.hp, M.units.pet.max = 40, 100
	M.manaShare = 0.2
	C:UpdateHints()
	eq(C.frame.funnelHint.alpha, 1)
	eq(C.frame.tapHint.alpha, 1)
	M.units.pet.hp, M.manaShare = 90, 0.8
	C:UpdateHints()
	eq(C.frame.funnelHint.alpha, 0.2)
	eq(C.frame.tapHint.alpha, 0.2)
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

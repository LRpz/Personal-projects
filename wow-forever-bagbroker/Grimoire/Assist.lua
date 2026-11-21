-- Grimoire: live combat assistant.
--
-- Forever applies Midnight's addon rules: in combat an addon cannot read enemy health or auras.
-- What it can read: your own casts (UNIT_SPELLCAST_*), enemy nameplates, and the damage numbers
-- each enemy takes (UNIT_COMBAT amounts stay readable, as Does It Die relies on). From those the
-- assistant keeps, per enemy:
--   - the DoTs and control spells you put on it, with their timers from the tooltips;
--   - whether each cast landed: its first tick on that enemy confirms it, a "Resist"/"Immune"
--     right after the cast removes it and puts the spell back in that enemy's queue;
--   - an estimate of its health: its maximum (read while the game allows it, or learned from
--     earlier kills of the same creature) minus the damage it has taken since;
--   - the damage your running DoTs will still deal (tooltip damage, Agony's ramp, and a
--     correction learned from the ticks you actually see).
-- From that it builds a spell queue per enemy (shown on its nameplate), picks the enemy to act
-- on next, and skips casts that would be wasted: no DoT on an enemy your DoTs already kill, no
-- long DoT on an enemy about to die, Drain Soul when it will die during the channel and you need
-- shards. It never casts anything: you press the key (Blizzard's one key press = one action).
local _, ns = ...
local Spells = ns.Spells

local Assist = {
	mobs = {},       -- set of tracked enemies (tables), one per hostile nameplate
	byToken = {},    -- nameplate token -> enemy
	departed = {},   -- GUID -> enemy that left nameplate range (restored when it comes back)
	pending = {},    -- cast GUID -> { token, time }: the enemy a cast in flight was aimed at
	handled = {},    -- cast GUIDs already applied (channel start and success both fire)
	cooldowns = {},  -- spell -> time it is ready again
	procs = {},      -- spell -> true while its proc glow is up (Nightfall lights Shadow Bolt)
	seen = {},       -- which unit tokens deliver UNIT_COMBAT ("target", "nameplate")
	seqIndex = 1,    -- position of the one key's /castsequence (mirrored to name its key)
}
ns.Assist = Assist

local MISS_WINDOW = 1.2     -- a resist arrives right after the cast
local CONFIRM_DELAY = 0.8   -- a matching-school hit after this confirms a DoT landed
local MISSES = { RESIST = true, IMMUNE = true, MISS = true, EVADE = true, REFLECT = true }

---------------------------------------------------------------------------
-- Enemies
---------------------------------------------------------------------------
local function TokenOfPlate(plate)
	if not plate then return nil end
	local token = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
	return ns.Readable(token)
end

function Assist:PlateToken(unit)
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	return ok and TokenOfPlate(plate) or nil
end

local function Hostile(token)
	if not UnitExists(token) then return false end
	local can = UnitCanAttack("player", token)
	if ns.IsSecret(can) then can = true end
	return can and not ns.IsTrue(UnitIsDead(token))
end

-- Creature key for learned health: NPC ID (from the GUID) or name, with the level.
local function CreatureKey(token, guid)
	local level = ns.Readable(UnitLevel(token)) or 0
	local npc = guid and guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)")
	if npc then return "n" .. npc .. ":" .. level end
	local name = ns.Readable(UnitName(token))
	return name and (name .. ":" .. level) or nil
end

function Assist:NewMob(token, guid)
	return { token = token, guid = guid, creature = CreatureKey(token, guid), added = GetTime(), touched = false,
		dots = {}, taken = 0, healed = 0 }
end

-- Reads health while the game allows it (usually before the pull): resyncs the estimate.
function Assist:Sync(mob)
	local token = mob.token
	if not token or not UnitExists(token) then return end
	local max = ns.Readable(UnitHealthMax(token))
	if max and max > 0 then
		mob.maxHealth = max
		if mob.creature then ns.db.health[mob.creature] = { max = max, exact = true } end
	end
	local hp = ns.Readable(UnitHealth(token))
	if hp then mob.sync = { health = hp, net = mob.taken - mob.healed } end
end

function Assist:AddPlate(token)
	if self.byToken[token] or not Hostile(token) then return self.byToken[token] end
	local guid = ns.Readable(UnitGUID(token))
	local mob = guid and self.departed[guid]
	if mob then self.departed[guid] = nil else mob = self:NewMob(token, guid) end
	mob.token = token
	self.byToken[token] = mob
	self.mobs[mob] = true
	self:Sync(mob)
	ns:Fire("ASSIST_PLATE", token, mob)
	return mob
end

function Assist:RemovePlate(token)
	local mob = self.byToken[token]
	if not mob then return end
	local dead = ns.IsTrue(UnitIsDead(token))
	if dead then self:LearnDeath(mob) end
	self.byToken[token] = nil
	self.mobs[mob] = nil
	mob.token = nil
	if not dead and mob.guid then
		mob.departedAt = GetTime()
		self.departed[mob.guid] = mob
	end
	ns:Fire("ASSIST_PLATE_GONE", token)
end

-- The current target as a tracked enemy (its nameplate, or a stand-in without plates).
function Assist:TargetMob(create)
	local token = self:PlateToken("target")
	if token then return self.byToken[token] or (create and self:AddPlate(token)) or nil end
	if self.targetMob and UnitExists("target") then return self.targetMob end
	if create and Hostile("target") then
		self.targetMob = self:NewMob("target", ns.Readable(UnitGUID("target")))
		self:Sync(self.targetMob)
		return self.targetMob
	end
	return nil
end

function Assist:MobFor(token)
	if not token then return nil end
	if token == "target" then return self:TargetMob(true) end
	return self.byToken[token] or self:AddPlate(token)
end

-- Whether an enemy is fighting you or your demon (nil when the game hides it).
function Assist:OnUs(token)
	local t = token .. "target"
	if not UnitExists(t) then return false end
	local a, b = UnitIsUnit(t, "player"), UnitIsUnit(t, "pet")
	if ns.IsSecret(a) or ns.IsSecret(b) then return nil end
	return (a or b) and true or false
end

-- Enemies in the fight, oldest first; before a pull, just the hostile target.
function Assist:Engaged()
	local list, seen = {}, {}
	local function consider(mob)
		local t = mob.token
		if seen[mob] or not t or not UnitExists(t) or ns.IsTrue(UnitIsDead(t)) then return end
		seen[mob] = true
		local onUs = self:OnUs(t)
		if mob.touched or onUs or (onUs == nil and InCombatLockdown() and ns.IsTrue(UnitAffectingCombat(t))) then
			list[#list + 1] = mob
		end
	end
	for mob in pairs(self.mobs) do consider(mob) end
	if self.targetMob then consider(self.targetMob) end
	table.sort(list, function(a, b) return a.added < b.added end)
	if #list == 0 then
		local target = self:TargetMob(true)
		if target then return { target }, true end
	end
	return list, false
end

---------------------------------------------------------------------------
-- Health and DoT damage estimates
---------------------------------------------------------------------------
function Assist:LearnedMax(mob)
	local entry = mob.creature and ns.db.health[mob.creature]
	return entry and entry.max or nil
end

-- Estimated health left, or nil when unknown.
function Assist:Health(mob)
	local net = mob.taken - mob.healed
	if mob.sync then return math.max(0, mob.sync.health - (net - mob.sync.net)) end
	local max = mob.maxHealth or self:LearnedMax(mob)
	if max then return math.max(0, max - net) end
	return nil
end

-- A kill seen in full (every hit observed) teaches the creature's health for next time.
function Assist:LearnDeath(mob)
	if not mob.creature or mob.partial or mob.maxHealth or mob.taken <= 0 then return end
	local entry = ns.db.health[mob.creature]
	if entry and entry.exact then return end
	local samples = entry and entry.samples or {}
	samples[#samples + 1] = mob.taken - mob.healed
	while #samples > 5 do table.remove(samples, 1) end
	local sorted = {}
	for i, v in ipairs(samples) do sorted[i] = v end
	table.sort(sorted)
	ns.db.health[mob.creature] = { max = sorted[math.ceil(#sorted / 2)], samples = samples }
end

function Assist:Multiplier() return ns.db.dotMultiplier or 1 end

-- Share of a DoT's damage still to come (Agony ramps up: its last ticks hit hardest).
function Assist.RemainingShare(spell, dot, now)
	local duration = dot.duration or 0
	if duration <= 0 then return 0 end
	local left = math.max(0, math.min(1, (dot.expires - now) / duration))
	local def = ns.DOT_BY_NAME[spell]
	if not (def and def.ramp) then return left end
	local weights, total, rest = ns.AGONY_WEIGHTS, 0, 0
	local done = #weights * (1 - left)
	for i, w in ipairs(weights) do
		total = total + w
		rest = rest + w * math.max(0, math.min(1, i - done))
	end
	return total > 0 and rest / total or left
end

function Assist:DotRemaining(mob, now)
	local total, mult = 0, self:Multiplier()
	for spell, dot in pairs(mob.dots) do
		if dot.expires > now then total = total + Spells:Damage(spell) * mult * self.RemainingShare(spell, dot, now) end
	end
	return total
end

---------------------------------------------------------------------------
-- Casts, hits and misses
---------------------------------------------------------------------------
function Assist:OnCastSent(unit, targetName, castGUID)
	if unit ~= "player" or not ns.Readable(castGUID) then return end
	local token = self:PlateToken("target") or (UnitExists("target") and "target") or nil
	local name = ns.Readable(targetName)
	if name and UnitExists("mouseover") then
		local over, current = ns.Readable(UnitName("mouseover")), ns.Readable(UnitName("target"))
		if over == name and current ~= name then token = self:PlateToken("mouseover") or token end
	end
	self.pending[castGUID] = { token = token, time = GetTime() }
end

function Assist:AdvanceSequence(name)
	local seq = ns.Coach and ns.Coach.dotSequence
	if not seq or #seq == 0 then return end
	if seq[self.seqIndex] == name then self.seqIndex = self.seqIndex % #seq + 1 end
end

function Assist:OnCastSucceeded(unit, castGUID, spellID)
	if unit ~= "player" and unit ~= "pet" then return end
	local name = ns.SpellName(spellID)
	if not name then return end
	castGUID = ns.Readable(castGUID)
	if castGUID then
		if self.handled[castGUID] then return end
		self.handled[castGUID] = GetTime()
	end
	local now = GetTime()
	local token
	if unit == "pet" then
		token = self:PlateToken("pettarget")
	else
		local p = castGUID and self.pending[castGUID]
		token = p and p.token
		if castGUID then self.pending[castGUID] = nil end
		self:AdvanceSequence(name)
	end
	local cooldown = Spells:Cooldown(name)
	if cooldown > 0 then self.cooldowns[name] = now + cooldown end
	local info = Spells.info[name]
	if unit == "player" and info and info.healthCost then
		self.vitals.player.taken = self.vitals.player.taken + info.healthCost  -- Life Tap costs health
	end
	local mob = self:MobFor(token)
	if mob then
		mob.touched = true
		if ns.DOT_BY_NAME[name] then
			local duration = Spells:Duration(name)
			mob.dots[name] = { applied = now, expires = now + duration, duration = duration, status = "pending" }
		elseif ns.CONTROL[name] then
			mob.control = { spell = name, applied = now, expires = now + Spells:Duration(name), status = "pending" }
		elseif ns.DIRECT[name] then
			mob.lastDirect = { spell = name, time = now }
		end
		if name == "Searing Pain" and ns.Talents and ns.Talents:Has("Demonic Brand") then
			mob.brandUntil = now + ns.THRESHOLDS.brand
		end
		if name == "Drain Life" or name == "Drain Soul" then self.channel = { spell = name, mob = mob } end
		if self.fight then mob.inFight = true end
	end
	self:RequestUpdate()
end

function Assist:OnCastFailed(unit, castGUID)
	castGUID = ns.Readable(castGUID)
	if unit == "player" and castGUID then self.pending[castGUID] = nil end
end

-- A resist or immune right after a cast: the most recent matching cast on that enemy failed.
function Assist:OnMiss(mob, event, school, now)
	local spell, latest
	for name, dot in pairs(mob.dots) do
		local def = ns.DOT_BY_NAME[name]
		if now - dot.applied <= MISS_WINDOW and (not school or def.school == school) and (not latest or dot.applied > latest) then
			spell, latest = name, dot.applied
		end
	end
	local control = mob.control
	if control and now - control.applied <= MISS_WINDOW and (not latest or control.applied > latest) then
		spell, latest = control.spell, control.applied
	end
	local label = event == "IMMUNE" and "immune" or (event == "EVADE" and "evaded" or "resisted")
	if spell then
		if mob.control and mob.control.spell == spell then mob.control = nil else mob.dots[spell] = nil end
		mob.flash = { text = spell .. " " .. label, spell = spell, untilTime = now + 3 }
	elseif mob.lastDirect and now - mob.lastDirect.time <= MISS_WINDOW then
		mob.flash = { text = mob.lastDirect.spell .. " " .. label, spell = mob.lastDirect.spell, untilTime = now + 3 }
	end
end

-- A hit of a DoT's school after the resist window confirms that DoT landed.
function Assist:ConfirmTick(mob, school, now)
	for name, dot in pairs(mob.dots) do
		if dot.status == "pending" and ns.DOT_BY_NAME[name].school == school and now - dot.applied >= CONFIRM_DELAY then
			dot.status = "landed"
		end
	end
end

function Assist:OnCombatEvent(unit, event, _, amount, school)
	if not ns.Readable(unit) or not ns.Readable(event) then return end
	if unit == "player" or unit == "pet" then
		local v, value = self.vitals[unit], ns.Readable(amount)
		if value and event == "WOUND" then v.taken = v.taken + value end
		if value and event == "HEAL" then v.healed = v.healed + value end
		self:RequestUpdate()
		return
	end
	local mob
	if unit == "target" then
		self.seen.target = true
		mob = self:TargetMob(false)
	elseif unit:match("^nameplate%d+$") then
		self.seen.nameplate = true
		mob = self.byToken[unit]
	end
	if not mob then return end
	amount, school = ns.Readable(amount), ns.Readable(school)
	local now = GetTime()
	-- the same hit can arrive once for "target" and once for its nameplate token
	local last = mob.lastEvent
	if last and last.time == now and last.event == event and last.amount == amount and last.school == school and last.unit ~= unit then
		return
	end
	mob.lastEvent = { time = now, event = event, amount = amount, school = school, unit = unit }
	if event == "WOUND" and amount then
		mob.taken = mob.taken + amount
		-- damage breaks Fear and Seduction: the enemy is back in the fight
		local control = mob.control
		if control and now - control.applied >= CONFIRM_DELAY and control.expires > now then
			mob.control = nil
			mob.flash = { text = control.spell .. " broken", spell = control.spell, untilTime = now + 3 }
		end
		if school then
			local hadDirect = mob.lastDirect and now - mob.lastDirect.time <= 1.5
			local draining = self.channel and self.channel.mob == mob
			if not hadDirect and not draining then self:ConfirmTick(mob, school, now) end
			if self.fight and not hadDirect and not draining then
				for name, dot in pairs(mob.dots) do
					if ns.DOT_BY_NAME[name].school == school and dot.expires > now then
						self.fight.observed = self.fight.observed + amount
						break
					end
				end
			end
		end
	elseif event == "HEAL" and amount then
		mob.healed = mob.healed + amount
	elseif MISSES[event] then
		self:OnMiss(mob, event, school, now)
	end
	self:RequestUpdate()
end

---------------------------------------------------------------------------
-- You and your demon: health estimated from readable damage and heals
---------------------------------------------------------------------------
-- Forever hides your and your demon's health in combat, but not the max, nor the damage and heals
-- each takes (UNIT_COMBAT). Health is read whenever the game allows it (before a fight, on a
-- fresh summon) and followed from there.
Assist.vitals = { player = { unit = "player", taken = 0, healed = 0 }, pet = { unit = "pet", taken = 0, healed = 0 } }

function Assist:SyncVitals(v, assumeFull)
	if not UnitExists(v.unit) then v.sync = nil return end
	local max = ns.Readable(UnitHealthMax(v.unit))
	if max and max > 0 then v.max = max end
	local hp = ns.Readable(UnitHealth(v.unit))
	if not hp and assumeFull then hp = v.max end
	if hp then v.sync = { health = hp, net = v.taken - v.healed, time = GetTime() } end
end

-- Health share 0..1, or nil when unknown.
function Assist:Share(v)
	if not (v.sync and v.max and v.max > 0) then return nil end
	local hp = v.sync.health - ((v.taken - v.healed) - v.sync.net)
	return math.max(0, math.min(1, hp / v.max))
end

-- Who an enemy is attacking: "player", "pet", false, or nil when the game hides it.
function Assist:Attacking(token)
	local t = token .. "target"
	if not UnitExists(t) then return false end
	local a, b = UnitIsUnit(t, "player"), UnitIsUnit(t, "pet")
	if ns.IsSecret(a) or ns.IsSecret(b) then return nil end
	return (a and "player") or (b and "pet") or false
end

---------------------------------------------------------------------------
-- Recommendation
---------------------------------------------------------------------------
local T = ns.THRESHOLDS

local function Humanoid(token)
	local kind = ns.Readable(UnitCreatureType(token))
	return kind == "Humanoid"
end

function Assist:Ready(spell, now) return Spells:Known(spell) and (self.cooldowns[spell] or 0) <= now end

function Assist:ControlActive(spell, now)
	for mob in pairs(self.mobs) do
		if mob.control and mob.control.spell == spell and mob.control.expires > now then return true end
	end
	if self.targetMob and self.targetMob.control and self.targetMob.control.spell == spell then
		return self.targetMob.control.expires > now
	end
	return false
end

-- The enemy to take out of the fight (never one carrying DoTs: damage breaks control).
function Assist:PickControl(set, mobs, now)
	for _, spell in ipairs(set.control) do
		local def = ns.CONTROL[spell]
		if self:Ready(spell, now) and not self:ControlActive(spell, now) then
			local best, bestOnPlayer
			for _, mob in ipairs(mobs) do
				local petTarget = ns.IsTrue(UnitIsUnit(mob.token, "pettarget"))
				if not mob.control and not next(mob.dots) and not petTarget and (not def.humanoid or Humanoid(mob.token)) then
					local onPlayer = self:Attacking(mob.token) == "player"
					if not best or (onPlayer and not bestOnPlayer) or (onPlayer == bestOnPlayer and mob.added > best.added) then
						best, bestOnPlayer = mob, onPlayer
					end
				end
			end
			if best then return best, spell end
		end
	end
	return nil, nil
end

-- What to cast when every enemy carries its DoTs, per specialization and your health.
function Assist:Filler(ctx, mob, status)
	local now, hp = ctx.now, ctx.playerShare
	if mob and status and status.health and Spells:Known("Drain Soul") and ctx.shards < (ns.settings.shardTarget or 5) then
		local soul = Spells:Damage("Drain Soul") * self:Multiplier()
		if soul > 0 and status.health <= soul + status.dotLeft then return "Drain Soul", "it dies during the channel: Soul Shard" end
	end
	local drain, wand = Spells:Known("Drain Life"), Spells:Known("Shoot")
	if ctx.spec == "Destruction" then
		if drain and hp and hp < T.drainBelowDestro then return "Drain Life", "you are below half health" end
		if status and status.dies and wand then return "Shoot", "your DoTs finish it: wand, save mana" end
		local immolate = mob and mob.dots["Immolate"]
		if Spells:Known("Incinerate") and immolate and immolate.expires > now then return "Incinerate", "it burns: Incinerate" end
		if Spells:Known("Shadow Bolt") then return "Shadow Bolt", "filler" end
	elseif ctx.spec == "Demonology" then
		if drain and hp and hp < T.drainBelowDemo then return "Drain Life", "you are hurt: drain" end
		if drain and ctx.level >= 30 then return "Drain Life", "Drain Life is the filler from 30" end
		if wand then return "Shoot", "wand until 30, save mana" end
	else
		local soulSiphon = ns.Talents and ns.Talents:Has("Soul Siphon")
		if drain and (hp == nil or hp < T.drainBelow or soulSiphon) and not (status and status.dies and wand and hp and hp >= T.drainBelow) then
			return "Drain Life", soulSiphon and "Soul Siphon: drains grow with your DoTs" or (hp and "you are hurt: drain" or "DoTs are up: drain")
		end
		if wand then return "Shoot", "you are healthy: wand, save mana" end
	end
	if drain then return "Drain Life", "DoTs are up: drain" end
	if Spells:Known("Shadow Bolt") then return "Shadow Bolt", "DoTs are up" end
	return nil, nil
end

-- The situation the rules read.
function Assist:Context()
	local now = GetTime()
	local set, petKey = ns.CurrentSet()
	local mobs, prepull = self:Engaged()
	local ctx = {
		now = now, set = set, petKey = petKey, mobs = mobs, prepull = prepull,
		spec = ns.Talents and ns.Talents:Spec() or "Affliction",
		level = UnitLevel("player") or 1,
		playerShare = self:Share(self.vitals.player),
		petShare = UnitExists("pet") and self:Share(self.vitals.pet) or nil,
		shards = C_Item and C_Item.GetItemCount and ns.Readable(C_Item.GetItemCount(ns.SOUL_SHARD)) or 0,
		onPlayer = 0, onPet = 0, target = self:TargetMob(false),
	}
	for _, mob in ipairs(mobs) do
		local who = self:Attacking(mob.token)
		mob.attacking = who
		if who == "player" then ctx.onPlayer = ctx.onPlayer + 1 elseif who == "pet" then ctx.onPet = ctx.onPet + 1 end
	end
	ctx.rotation = ns.ROTATIONS[ctx.spec] or ns.ROTATIONS.Affliction
	return ctx
end

-- Per-enemy DoT queue for the specialization; "lives" uses the health estimate when there is one.
function Assist:DotQueue(ctx, mob, status)
	local queue, mult = {}, self:Multiplier()
	local pandemic = ns.Talents and ns.Talents:Has("Pandemic")
	for _, entry in ipairs(ctx.rotation.dots) do
		local spell, def = entry.spell, ns.DOT_BY_NAME[entry.spell]
		if Spells:Known(spell) and def and (not def.maxLevel or ctx.level <= def.maxLevel or ctx.spec ~= "Affliction") then
			local active = mob.dots[spell]
			local window = pandemic and Spells:Duration(spell) * 0.3 or 0.6
			local due = not active or active.expires - ctx.now <= window
			local lives = true
			if status.health then
				local damage = Spells:Damage(spell) * mult
				lives = damage <= 0 or (status.health - status.dotLeft) >= damage * entry.lives
			end
			if due and lives then
				if entry.with and not active and self:Ready(entry.with, ctx.now) then queue[#queue + 1] = entry.with end
				queue[#queue + 1] = spell
			end
		end
	end
	return queue
end

-- Rules that act before the DoTs, in priority order. Each returns spell, enemy (nil = yourself or
-- your demon), reason. They read your health, your demon's, enemies' health and who they attack.
Assist.RULES = {
	{ key = "sacrifice", run = function(self, ctx)
		if ctx.petKey == "Voidwalker" and ctx.playerShare and ctx.playerShare < T.sacrifice and self:Ready("Sacrifice", ctx.now) then
			return "Sacrifice", nil, "you are below 25%: Voidwalker shield"
		end
	end },
	{ key = "deathCoil", run = function(self, ctx)
		if ctx.playerShare and ctx.playerShare < T.deathCoil and self:Ready("Death Coil", ctx.now) then
			for _, mob in ipairs(ctx.mobs) do
				if mob.attacking == "player" then return "Death Coil", mob, "you are low and it is hitting you" end
			end
		end
	end },
	{ key = "howl", run = function(self, ctx)
		if ctx.onPlayer >= T.howlOnYou and self:Ready("Howl of Terror", ctx.now) then
			return "Howl of Terror", nil, ctx.onPlayer .. " enemies are hitting you"
		end
	end },
	{ key = "control", run = function(self, ctx)
		if ctx.controlMob then return ctx.controlSpell, ctx.controlMob, #ctx.mobs .. " enemies: take this one out of the fight" end
	end },
	{ key = "funnel", run = function(self, ctx)
		if ctx.petShare and ctx.petShare < T.funnelPet and (ctx.playerShare == nil or ctx.playerShare > T.funnelSelf)
			and Spells:Known("Health Funnel") and #ctx.mobs > 0 then
			return "Health Funnel", nil, "your demon is below half health"
		end
	end },
	{ key = "nightfall", run = function(self, ctx)
		if self.procs["Shadow Bolt"] and Spells:Known("Shadow Bolt") then
			local mob = ctx.target or ctx.mobs[1]
			if mob then return "Shadow Bolt", mob, "Shadow Trance: instant Shadow Bolt" end
		end
	end },
	{ key = "shadowburn", run = function(self, ctx)
		if not self:Ready("Shadowburn", ctx.now) or ctx.shards < T.shardReserve then return end
		local damage = Spells:Damage("Shadowburn") * 1
		for _, mob in ipairs(ctx.mobs) do
			local st = ctx.status[mob]
			if st.health and damage > 0 and st.health <= damage and not st.dies then return "Shadowburn", mob, "finish it with Shadowburn" end
		end
	end },
	{ key = "conflagrate", run = function(self, ctx)
		if not self:Ready("Conflagrate", ctx.now) then return end
		for _, mob in ipairs(ctx.mobs) do
			local imm = mob.dots["Immolate"]
			if imm and imm.status ~= "resisted" and imm.expires > ctx.now and imm.expires - ctx.now <= T.conflagrate then
				return "Conflagrate", mob, "Immolate is ending: Conflagrate it"
			end
		end
	end },
	{ key = "brand", run = function(self, ctx)
		if not (ctx.rotation.brand and ns.Talents and ns.Talents:Has("Demonic Brand") and Spells:Known("Searing Pain")) then return end
		for _, mob in ipairs(ctx.mobs) do
			if ns.IsTrue(UnitIsUnit(mob.token, "pettarget")) and (mob.brandUntil or 0) <= ctx.now then
				return "Searing Pain", mob, "Demonic Brand fell off the demon's target"
			end
		end
	end },
}

-- Builds the per-enemy queues and picks what to do next.
function Assist:Recommend()
	local ctx = self:Context()
	local now, mobs = ctx.now, ctx.mobs
	local rec = { mobs = mobs, n = #mobs, queues = {}, status = {}, prepull = ctx.prepull, set = ctx.set,
		spec = ctx.spec, playerShare = ctx.playerShare, petShare = ctx.petShare, onPlayer = ctx.onPlayer }
	ctx.status = rec.status
	local set = ctx.set
	local capacity = set.capacity + ((set.siphonBonus and Spells:Known("Siphon Life")) and set.siphonBonus or 0)
	local controlled = 0
	for _, mob in ipairs(mobs) do
		local control = mob.control
		if control and control.expires > now then
			controlled = controlled + 1
			if control.status == "pending" and now - control.applied > MISS_WINDOW then control.status = "landed" end
		end
	end
	local extra = #mobs - capacity - controlled
	if extra > 0 and not ctx.prepull then ctx.controlMob, ctx.controlSpell = self:PickControl(set, mobs, now) end

	for _, mob in ipairs(mobs) do
		local health = self:Health(mob)
		local dotLeft = self:DotRemaining(mob, now)
		local status = { health = health, dotLeft = dotLeft, dies = health ~= nil and health > 0 and dotLeft >= health * 0.95 }
		rec.status[mob] = status
		local controlledMob = mob.control and mob.control.expires > now
		if mob == ctx.controlMob then
			rec.queues[mob] = { ctx.controlSpell }
		elseif controlledMob or status.dies then
			rec.queues[mob] = {}
		else
			rec.queues[mob] = self:DotQueue(ctx, mob, status)
		end
	end

	-- rules first (emergencies, control, procs, executes, brand)
	for _, rule in ipairs(self.RULES) do
		local spell, mob, why = rule.run(self, ctx)
		if spell then
			rec.spell, rec.focus, rec.reason, rec.rule = spell, mob, why, rule.key
			if mob and rec.queues[mob] and rec.queues[mob][1] ~= spell then table.insert(rec.queues[mob], 1, spell) end
			break
		end
	end

	local target = ctx.target
	if not rec.spell then
		local focus
		if target and rec.queues[target] and #rec.queues[target] > 0 then
			focus = target
		else
			local bestScore
			for _, mob in ipairs(mobs) do
				local queue = rec.queues[mob]
				if #queue > 0 then
					local missing = 0
					for _, spell in ipairs(queue) do if not mob.dots[spell] then missing = missing + 1 end end
					local score = missing * 10 + (mob == target and 5 or 0)
					if not bestScore or score > bestScore then focus, bestScore = mob, score end
				end
			end
		end
		if focus then
			rec.focus, rec.spell = focus, rec.queues[focus][1]
			local active = focus.dots[rec.spell]
			rec.reason = active and "refresh before it ends" or (ctx.prepull and "opener" or "not on this enemy yet")
		else
			-- every enemy carries its DoTs (or dies to them): fill on the enemy that lives longest
			local fill, best = nil, nil
			for _, mob in ipairs(mobs) do
				local status = rec.status[mob]
				if not (mob.control and mob.control.expires > now) then
					local left = status.health and (status.health - status.dotLeft) or math.huge
					if not best or left > best then fill, best = mob, left end
				end
			end
			if target and rec.status[target] and not rec.status[target].dies and not (target.control and target.control.expires > now) then
				fill = target
			end
			rec.focus = fill
			rec.spell, rec.reason = self:Filler(ctx, fill, fill and rec.status[fill])
		end
	end
	rec.self = rec.spell ~= nil and rec.focus == nil
	rec.switch = rec.focus ~= nil and rec.focus ~= target
	if extra > 0 and not ctx.controlSpell and rec.rule ~= "howl" and Spells:Known("Howl of Terror") then
		rec.alert = "Too many enemies: Howl of Terror when they reach you"
	end
	rec.after = {}
	if rec.focus then
		for i = 2, #(rec.queues[rec.focus] or {}) do rec.after[#rec.after + 1] = rec.queues[rec.focus][i] end
	end
	return rec
end

-- The key that casts a spell: the one key (with modifier) when its next cast matches, else the
-- action bar key holding the spell.
function Assist:KeyHint(spell)
	if not spell then return nil end
	local Coach = ns.Coach
	local main = GetBindingKey and GetBindingKey("CLICK GrimoireMain:LeftButton")
	main = ns.ShortKey(main)
	if main and Coach then
		local seq = Coach.dotSequence or {}
		if seq[self.seqIndex] == spell then return main end
		if spell == Coach.fillerSpell then return "Shift+" .. main end
		if Coach.controlSpells and Coach.controlSpells[spell] then return "Ctrl+" .. main end
		if spell == Coach.saveSpell then return "Alt+" .. main end
	end
	return Spells:KeyFor(spell)
end

---------------------------------------------------------------------------
-- Loop and events
---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
local elapsed, dirty = 0, true

function Assist:RequestUpdate() dirty = true end

function Assist:Update(dt)
	local now = GetTime()
	self:SyncVitals(self.vitals.player)
	self:SyncVitals(self.vitals.pet)
	if self.fight then
		-- expected base DoT damage on enemies whose hits we can see, to learn the real tick size
		for mob in pairs(self.mobs) do
			if self.seen.nameplate or mob == self:TargetMob(false) then
				for name, dot in pairs(mob.dots) do
					if dot.expires > now and dot.duration > 0 then
						self.fight.expected = self.fight.expected + Spells:Damage(name) / dot.duration * dt
					end
				end
			elseif mob.inFight then
				mob.partial = true
			end
		end
	end
	if not (ns.settings.assist and (InCombatLockdown() or UnitExists("target"))) then
		if self.last then
			self.last = nil
			ns:Fire("ASSIST_UPDATE", nil)
			Spells:Glow(nil)
		end
		return
	end
	local rec = self:Recommend()
	self.last = rec
	ns:Fire("ASSIST_UPDATE", rec)
	Spells:Glow(rec.spell)
end

driver:SetScript("OnUpdate", function(_, dt)
	if not ns.isWarlock then return end
	elapsed = elapsed + dt
	if elapsed < 0.1 and not dirty then return end
	Assist:Update(elapsed)
	elapsed, dirty = 0, false
end)

function Assist:StartFight()
	self.fight = { observed = 0, expected = 0 }
	-- demons regenerate quickly out of combat: after 20 seconds of rest, assume full health
	local pet = self.vitals.pet
	if UnitExists("pet") and GetTime() - (self.lastFightEnd or 0) >= 20 and not (pet.sync and GetTime() - pet.sync.time < 2) then
		self:SyncVitals(pet, true)
	end
end

function Assist:EndFight()
	local fight = self.fight
	if fight and fight.expected >= 80 then
		local ratio = math.max(0.6, math.min(3, fight.observed / fight.expected))
		ns.db.dotMultiplier = (ns.db.dotMultiplier or 1) * 0.6 + ratio * 0.4
	end
	self.fight = nil
	self.lastFightEnd = GetTime()
	for mob in pairs(self.mobs) do
		wipe(mob.dots)
		mob.control, mob.touched, mob.inFight, mob.flash = nil, false, nil, nil
		self:Sync(mob)
	end
	self.targetMob = nil
	wipe(self.pending)
	wipe(self.handled)
	self.channel = nil
	self.seqIndex = 1
	self:RequestUpdate()
end

ns:On("DB_READY", function()
	ns.db.health = ns.db.health or {}
end)

ns:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, token) if ns.isWarlock then Assist:AddPlate(token) end end)
ns:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, token) Assist:RemovePlate(token) end)
ns:RegisterEvent("UNIT_SPELLCAST_SENT", function(_, ...) Assist:OnCastSent(...) end)
ns:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, ...) Assist:OnCastSucceeded(...) end)
ns:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", function(_, ...) Assist:OnCastSucceeded(...) end)
ns:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", function(_, unit) if unit == "player" then Assist.channel = nil end end)
ns:RegisterEvent("UNIT_SPELLCAST_FAILED", function(_, ...) Assist:OnCastFailed(...) end)
ns:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", function(_, ...) Assist:OnCastFailed(...) end)
ns:RegisterEvent("UNIT_COMBAT", function(_, ...) Assist:OnCombatEvent(...) end)
ns:RegisterEvent("PLAYER_TARGET_CHANGED", function()
	if Assist.targetMob then
		local mob = Assist.targetMob
		if mob.guid then Assist.departed[mob.guid] = mob; mob.departedAt = GetTime() end
		Assist.targetMob = nil
	end
	Assist.seqIndex = 1  -- the one key's /castsequence restarts on a new target
	Assist:RequestUpdate()
end)
ns:RegisterEvent("PLAYER_REGEN_DISABLED", function() Assist:StartFight() end)
ns:RegisterEvent("UNIT_PET", function(_, unit)
	-- a fresh summon arrives at full health
	if unit == "player" then Assist:SyncVitals(Assist.vitals.pet, not InCombatLockdown()) end
end)
ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() Assist:EndFight() end)
ns:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(_, spellID)
	local name = ns.SpellName(spellID)
	if name then Assist.procs[name] = true; Assist:RequestUpdate() end
end)
ns:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(_, spellID)
	local name = ns.SpellName(spellID)
	if name then Assist.procs[name] = nil; Assist:RequestUpdate() end
end)
ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
	if not (ns.isWarlock and C_NamePlate and C_NamePlate.GetNamePlates) then return end
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local token = TokenOfPlate(plate)
		if token then Assist:AddPlate(token) end
	end
end)

-- Old departed enemies and cast bookkeeping expire.
C_Timer.NewTicker(30, function()
	local now = GetTime()
	for guid, mob in pairs(Assist.departed) do
		if now - (mob.departedAt or now) > 120 then Assist.departed[guid] = nil end
	end
	for id, p in pairs(Assist.pending) do if now - p.time > 10 then Assist.pending[id] = nil end end
	for id, t in pairs(Assist.handled) do if now - t > 30 then Assist.handled[id] = nil end end
end)

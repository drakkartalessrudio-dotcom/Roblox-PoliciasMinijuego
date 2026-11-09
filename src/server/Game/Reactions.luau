--[[
	Reactions · las reglas de TravesurasBrainrot que mezclan varios cores. Cada una escucha
	el evento de un core y llama a la API de otros:

	  Mischief.completed   → Botín, XP, calor (si hubo testigo), estadísticas, álbum
	  Wanted.starReached   → onboarding, estadísticas, 6★ para la Ascensión
	  Wanted.cleared       → XP por escapar
	  Progress.leveledUp   → capacidad de Botín, telemetría, avisos de lo que se desbloquea
	  Cops.knockedDown     → propina por derribar
	  Cops.bossDefeated    → Medalla del Comisario (se reparte a la banda)
	  Cops.caught + Arrest → arresto, rescate y pérdida de Botín
	  Training.*           → pago de la Sala de Entrenamiento
	  Quests.claimed       → recompensa de las misiones
	  Ascension.ascended   → reinicio de la carrera
	  Band.*               → avisos de invitación y telemetría

	Los avisos al cliente salen por Net.send(player, "notify", { kind = … }).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Destinations = require(ReplicatedStorage.Shared.Destinations)
local Net = require(ReplicatedStorage.Shared.Net)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local Telemetry = require(ServerScriptService.Server.Telemetry)
local PlayerData = require(ServerScriptService.Server.Data.PlayerData)
local Areas = require(ServerScriptService.Server.Modules.Areas)
local Arrest = require(ServerScriptService.Server.Modules.Arrest)
local Ascension = require(ServerScriptService.Server.Modules.Ascension)
local Band = require(ServerScriptService.Server.Modules.Band)
local Cops = require(ServerScriptService.Server.Modules.Cops)
local Cosmetics = require(ServerScriptService.Server.Modules.Cosmetics)
local Economy = require(ServerScriptService.Server.Modules.Economy)
local Mischief = require(ServerScriptService.Server.Modules.Mischief)
local Progress = require(ServerScriptService.Server.Modules.Progress)
local Quests = require(ServerScriptService.Server.Modules.Quests)
local Shop = require(ServerScriptService.Server.Modules.Shop)
local Stats = require(ServerScriptService.Server.Modules.Stats)
local Training = require(ServerScriptService.Server.Modules.Training)
local Upgrades = require(ServerScriptService.Server.Modules.Upgrades)
local Wanted = require(ServerScriptService.Server.Modules.Wanted)
local Movement = require(script.Parent.Movement)
local PlayerStats = require(script.Parent.PlayerStats)
local Transit = require(script.Parent.Transit)

local Reactions = {}

local arrestStars: { [Player]: number } = {}
local combo: { [Player]: { number } } = {}

local function rootOf(player: Player): BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function notify(player: Player, payload: { [string]: any })
	Net.send(player, "notify", payload)
end

local function tutorialStep(player: Player): string
	if Progress.hasFlag(player, "tutorial_done") or Progress.level(player) >= Tuning.get("Tutorial.EndLevel") then
		return ""
	elseif not Progress.hasFlag(player, "first_mischief") then
		return "graffiti"
	elseif not Progress.hasFlag(player, "first_escape") then
		return "escape"
	elseif not Progress.hasFlag(player, "first_deposit") then
		return "deposit"
	elseif not Progress.hasFlag(player, "first_upgrade") then
		return "upgrade"
	end
	return ""
end

local function refreshTutorial(player: Player)
	local step = tutorialStep(player)
	player:SetAttribute("TutorialStep", step)
	if step == "" and Progress.hasFlag(player, "first_upgrade") then
		Progress.setFlag(player, "tutorial_done")
	end
end

-- Un paso del funnel de onboarding: se emite una sola vez en la vida del jugador (bandera con fecha).
local function onboard(player: Player, name: string)
	for _, entry in Catalog.onboarding do
		if entry.name == name then
			if Progress.setFlag(player, name) then
				Telemetry.onboarding(player, entry.step, name)
			end
			break
		end
	end
	refreshTutorial(player)
end
Reactions.onboard = onboard

local function incomeFor(player: Player, minutes: number, rate: number, withBand: boolean): (number, number)
	local level = Progress.level(player)
	local money = math.floor(Catalog.incomePerMinute(level) * rate * minutes * PlayerStats.moneyBonus(player, withBand) + 0.5)
	local xp = math.floor(Catalog.xpPerMinute(level) * rate * minutes * PlayerStats.xpBonus(player, withBand) + 0.5)
	return money, xp
end

local function afkRate(player: Player): number
	return Tuning.get("Afk.RatePercent") + Tuning.get("Afk.RatePerCintaLevel") * Upgrades.levelOf(player, "cinta")
end

local function unlocksAt(level: number): { string }
	local list = {}
	for _, destination in Destinations.unlockedAt(level) do
		table.insert(list, destination.name)
	end
	for _, tool in Catalog.tools do
		if Tuning.get(`Tools.{tool.configKey}.Level`) == level then
			table.insert(list, tool.name)
		end
	end
	for _, def in Catalog.mischiefs do
		if Catalog.mischiefConfig(def).Level == level and level > 1 then
			table.insert(list, def.name)
		end
	end
	if level == Tuning.get("Afk.UnlockLevel") then
		table.insert(list, "Sala de Entrenamiento")
	end
	if level == Tuning.get("Ascension.MinLevel") then
		table.insert(list, "Ascensión")
	end
	return list
end

local function comboActive(player: Player): boolean
	local list = combo[player]
	if not list then
		list = {}
		combo[player] = list
	end
	local now = os.clock()
	local fresh = {}
	for _, at in list do
		if now - at <= Tuning.get("Progress.ComboWindow") then
			table.insert(fresh, at)
		end
	end
	combo[player] = fresh
	return #fresh >= Tuning.get("Progress.ComboCount")
end

local function onMischiefCompleted(player: Player, result: Mischief.Result)
	local cfg = result.config
	local def = result.def
	local party = if def.coop then 1 + Tuning.get("Coop.PayPerExtraMember") * (result.partySize - 1) else 1
	local scale = party * result.speedMult
	local risk = PlayerStats.risk(player)
	local money = math.floor(cfg.Money * scale * PlayerStats.moneyBonus(player, true) * risk + 0.5)
	local xp = cfg.Xp * scale * PlayerStats.xpBonus(player, true) * risk
	local hasCombo = comboActive(player)
	if hasCombo then
		xp *= 1 + Tuning.get("Progress.ComboBonus")
		combo[player] = {}
	end
	table.insert(combo[player], os.clock())

	-- ¿Hubo testigo? Un policía que lo ve o lo oye suma calor; el ruido atrae a la patrulla.
	local witnessed = Cops.witnessed(player, result.position, cfg.Noise)
	Cops.alert(result.position, cfg.Noise * (1 - PlayerStats.sigilo(player)), player)
	local added = Economy.addLoot(player, money)
	Progress.addXp(player, math.floor(xp + 0.5))
	if witnessed then
		Wanted.addHeat(player, cfg.Heat, "travesura")
	end
	Band.touch(player)

	Stats.increment(player, "mischief_total", 1)
	if def.tag then
		Stats.increment(player, def.tag, 1)
	end
	if def.coop then
		Stats.increment(player, "band_mischiefs", 1)
		Telemetry.custom(player, "band_mischief", result.partySize, { item = def.id })
	end
	-- Álbum de graffitis: cada muro pintado desbloquea un diseño del catálogo.
	if def.id == "Graffiti" or def.id == "MuralGigante" then
		local designId = `{if def.coop then "banda" else "graffiti"}_{string.format("%02d", math.random(1, 30))}`
		Mischief.unlockDesign(player, designId)
	end
	Telemetry.custom(player, "mischief_complete", money, { item = def.id })
	onboard(player, "first_mischief")
	if def.coop then
		onboard(player, "first_coop_mischief")
	end
	-- El primer graffiti llama al policía guionado del tutorial.
	if tutorialStep(player) == "escape" and Wanted.stars(player) == 0 and Cops.chaserCount(player) == 0 then
		local spawn = Areas.nearest("tutorial_cop_spawn", result.position)
		if spawn then
			Cops.summon("patata", spawn.Position, player, Tuning.get("Tutorial.ScriptedCopSpeed"))
		end
	end
	notify(player, {
		kind = "mischief",
		name = def.name,
		money = added,
		xp = math.floor(xp + 0.5),
		stars = Wanted.stars(player),
		combo = hasCombo,
		full = added < money,
		party = result.partySize,
	})
end

local function onLevelUp(player: Player, level: number)
	Economy.refreshCap(player)
	Telemetry.progressionComplete(player, "Ciudad", level, nil)
	notify(player, { kind = "level", level = level, unlocks = unlocksAt(level) })
	onboard(player, "first_level_up")
end

local function startArrest(player: Player)
	if Arrest.isHeld(player) then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	arrestStars[player] = Wanted.stars(player)
	Cops.dismiss(player)
	Wanted.clear(player, "arrest")
	local window = if #Band.nearby(player, 200) > 0 then Tuning.get("Arrest.RescueSeconds") else Tuning.get("Arrest.JailSeconds")
	if Arrest.begin(player, root.Position, window) then
		Stats.increment(player, "arrests", 1)
		notify(player, { kind = "arrested", window = window, stars = arrestStars[player] })
	end
end

local function onArrestResolved(player: Player, rescuedBy: Player?)
	local stars = arrestStars[player] or 0
	arrestStars[player] = nil
	local fraction = if rescuedBy then Tuning.get("Arrest.RescueLossPercent") else PlayerStats.lossFraction(player, stars)
	local lost = Economy.loseLoot(player, fraction)
	Telemetry.custom(player, "arrest", lost, { stars = tostring(stars) })
	Movement.restore(player)
	if rescuedBy then
		Stats.increment(rescuedBy, "band_rescues", 1)
		Telemetry.custom(rescuedBy, "band_rescue", 1)
		notify(rescuedBy, { kind = "rescued_other", name = player.DisplayName })
	else
		Movement.respawnAtGuarida(player)
	end
	notify(player, { kind = "arrest_result", lost = lost, rescued = rescuedBy ~= nil, by = if rescuedBy then rescuedBy.DisplayName else nil })
end

function Reactions.canRescue(rescuer: Player, victim: Player): boolean
	local id = Band.bandId(rescuer)
	return id ~= nil and id == Band.bandId(victim) and not Arrest.isHeld(rescuer) and rootOf(rescuer) ~= nil
end

-- Al salir: con estrellas se aplica la pérdida del arresto; sin ellas, el Botín se deposita.
function Reactions.onLeaving(player: Player)
	if Wanted.stars(player) > 0 then
		Economy.loseLoot(player, PlayerStats.lossFraction(player, Wanted.stars(player)))
	else
		Economy.deposit(player)
	end
	Cops.dismiss(player)
	Arrest.release(player)
end

function Reactions.start()
	Progress.loaded:Connect(function(player)
		onboard(player, "joined")
		refreshTutorial(player)
		Telemetry.custom(player, "session_level", Progress.level(player))
	end)
	Progress.flagSet:Connect(function(player)
		refreshTutorial(player)
	end)
	Progress.leveledUp:Connect(onLevelUp)

	Mischief.completed:Connect(onMischiefCompleted)
	Mischief.failed:Connect(function(player, defId, reason)
		notify(player, { kind = "mischief_failed", reason = reason, id = defId })
	end)
	Mischief.started:Connect(function(player, session)
		Net.send(player, "mischief_start", {
			id = session.id,
			name = session.spot.def.name,
			game = session.game,
			duration = session.duration,
			party = session.partySize,
			coop = session.spot.def.coop == true,
		})
		Band.touch(player)
	end)

	Wanted.starReached:Connect(function(player, stars)
		onboard(player, "first_star")
		Telemetry.custom(player, "star_reached", stars)
		if stars == 5 then
			Stats.increment(player, "stars5_reached", 1)
		elseif stars == 6 then
			Ascension.markSixStar(player)
		end
		notify(player, { kind = "stars", stars = stars })
	end)
	Wanted.cleared:Connect(function(player, stars, reason)
		if reason ~= "escape" then
			return
		end
		local xp = math.floor(Tuning.get("Progress.EscapeXpPerStar") * stars * PlayerStats.xpBonus(player, true) + 0.5)
		Progress.addXp(player, xp)
		Stats.increment(player, "escapes", 1)
		if stars >= 3 then
			Stats.increment(player, "escapes_3star", 1)
		end
		onboard(player, "first_escape")
		notify(player, { kind = "escaped", xp = xp, stars = stars })
	end)

	Cops.knockedDown:Connect(function(cop, attacker)
		if not attacker then
			return
		end
		local resistance = math.min(Tuning.get(`Cops.{cop.def.configKey}.Resistance`), 50)
		local tip = math.clamp(math.floor(5 + resistance * 0.8), 5, 40)
		Economy.addLoot(attacker, tip)
		Progress.addXp(attacker, tip * 2)
		Telemetry.custom(attacker, "cop_knockdown", 1, { item = cop.def.id })
		Band.touch(attacker)
	end)
	Cops.bossDefeated:Connect(function(_cop, attacker)
		if not attacker then
			return
		end
		local recipients = Band.nearby(attacker, Tuning.get("Band.SharedRewardRange"))
		table.insert(recipients, attacker)
		for _, player in recipients do
			local medal = math.floor(Catalog.incomePerMinute(Progress.level(player)) * 10 * PlayerStats.moneyBonus(player, true))
			Economy.addLoot(player, medal)
			Stats.increment(player, "comisario_defeated", 1)
			notify(player, { kind = "medal", money = medal })
		end
	end)
	Cops.caught:Connect(startArrest)
	Arrest.resolved:Connect(onArrestResolved)

	-- Sala de Entrenamiento y alijo.
	Training.ticked:Connect(function(player, seconds)
		local money, xp = incomeFor(player, seconds / 60, afkRate(player), false)
		if money > 0 then
			Economy.add(player, "dinero", money, "Gameplay")
		end
		if xp > 0 then
			Progress.addXp(player, xp)
		end
		Stats.increment(player, "afk_seconds_total", math.floor(seconds))
	end)
	Training.checkedIn:Connect(function(player, minutes)
		local money, xp = incomeFor(player, minutes, afkRate(player), false)
		if money > 0 then
			Economy.add(player, "dinero", money, "Gameplay")
		end
		if xp > 0 then
			Progress.addXp(player, xp)
		end
		Telemetry.custom(player, "afk_checkin", 1)
	end)
	Training.suspect:Connect(function(player)
		Telemetry.custom(player, "afk_suspect", 1)
	end)
	Training.stateChanged:Connect(function(player, label)
		if label == "active" then
			Telemetry.custom(player, "afk_enter", 1)
		elseif label == "idle" then
			Telemetry.custom(player, "afk_exit", 1)
		end
	end)
	Training.challengeIssued:Connect(function(player, spec)
		Net.send(player, "afk_challenge", spec)
	end)

	Quests.claimed:Connect(function(player, _questId, weekly, streak)
		local factor = 1 + math.min(Tuning.get("Daily.StreakMaxBonus"), streak * Tuning.get("Daily.StreakStep"))
		local minutes = Tuning.get("Daily.RewardMinutesOfIncome") * (if weekly then Tuning.get("Daily.WeeklyMultiplier") else 1)
		local money = math.floor(Catalog.incomePerMinute(Progress.level(player)) * minutes * factor + 0.5)
		Economy.add(player, "dinero", money, "TimedReward")
		notify(player, { kind = "quest_reward", money = money, weekly = weekly })
	end)

	Ascension.ascended:Connect(function(player, count, cerebros)
		Cops.dismiss(player)
		Wanted.clear(player, "ascension")
		Economy.loseLoot(player, 1)
		Progress.reset(player)
		Upgrades.clear(player)
		Economy.set(player, "dinero", Ascension.perkLevel(player, "capital_inicial") * Tuning.get("Perks.CapitalInicial.MoneyPerLevel"))
		Cosmetics.grant(player, `badge_asc_{count}`, "level")
		Economy.refreshCap(player)
		Movement.refreshGroup(player)
		Movement.applySpeed(player)
		Transit.to(player, Destinations.HOME, { force = true }) -- la carrera nueva empieza en La Guarida
		Telemetry.custom(player, "ascension", count, nil)
		notify(player, { kind = "ascended", count = count, cerebros = cerebros })
		task.spawn(PlayerData.save, player)
	end)

	Upgrades.upgraded:Connect(function(player, upgradeId, level)
		onboard(player, "first_upgrade")
		if upgradeId == "bolsillos" then
			Economy.refreshCap(player)
		end
		Movement.applySpeed(player)
		Telemetry.custom(player, "upgrade_bought", level, { item = upgradeId })
	end)

	Band.inviteReceived:Connect(function(target, from)
		Net.send(target, "band_invite", { fromUserId = from.UserId, fromName = from.DisplayName })
	end)
	Band.changed:Connect(function(player)
		Band.touch(player)
	end)
	Shop.passChanged:Connect(function(player, key, owned)
		if key == "aura_vip" and owned then
			Cosmetics.grant(player, "aura_vip", "gamepass")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		combo[player] = nil
		arrestStars[player] = nil
	end)
end

return Reactions

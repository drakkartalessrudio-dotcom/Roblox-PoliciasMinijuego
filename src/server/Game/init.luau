--[[
	Game · composición de TravesurasBrainrot. Es el único lugar que conoce todos los cores:
	les pasa el contenido y las funciones que necesitan, conecta los puentes y los arranca,
	en este orden:

	  1. init de cada core, con su contenido (todavía sin jugadores);
	  2. connect de cada puente, para no perder eventos del arranque;
	  3. start de cada core, y después las reglas propias del juego (World, Effects,
	     Reactions, Intents, Movement), que mezclan varios cores.

	Cadena de una travesura:
	  Mischief.request → Net "mischief_start" → minijuego en el cliente → Net "mischief_submit"
	  → Mischief.completed → Reactions (Botín, XP, calor si hubo testigo, estadísticas).
	Cadena de una persecución:
	  Cops.sightChanged → Cops_Wanted → Wanted (estrellas) → Cops (refuerzos) → Cops.caught
	  → Reactions → Arrest → Arrest.resolved → pérdida de Botín y reaparición en la Guarida.
	Cadena de la Ascensión:
	  Net "ascend" → Ascension.ascend → Ascension.ascended → Reactions (reinicio en un tick).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local LevelLoader = require(script.Parent.LevelLoader)
local Achievements = require(script.Parent.Modules.Achievements)
local Areas = require(script.Parent.Modules.Areas)
local Arrest = require(script.Parent.Modules.Arrest)
local Ascension = require(script.Parent.Modules.Ascension)
local Band = require(script.Parent.Modules.Band)
local Cops = require(script.Parent.Modules.Cops)
local Cosmetics = require(script.Parent.Modules.Cosmetics)
local Economy = require(script.Parent.Modules.Economy)
local Mischief = require(script.Parent.Modules.Mischief)
local Plots = require(script.Parent.Modules.Plots)
local Progress = require(script.Parent.Modules.Progress)
local Quests = require(script.Parent.Modules.Quests)
local Shop = require(script.Parent.Modules.Shop)
local Stats = require(script.Parent.Modules.Stats)
local Tools = require(script.Parent.Modules.Tools)
local Training = require(script.Parent.Modules.Training)
local Upgrades = require(script.Parent.Modules.Upgrades)
local Wanted = require(script.Parent.Modules.Wanted)
local Cops_Wanted = require(script.Parent.Bridges.Cops_Wanted)
local Stats_Quests = require(script.Parent.Bridges.Stats_Quests)
local Wanted_Band = require(script.Parent.Bridges.Wanted_Band)
local Content = require(script.Content)
local Effects = require(script.Effects)
local Hub = require(script.Hub)
local Intents = require(script.Intents)
local Movement = require(script.Movement)
local PlayerStats = require(script.PlayerStats)
local Reactions = require(script.Reactions)
local Transit = require(script.Transit)
local World = require(script.World)

export type Context = {
	built: LevelLoader.Built,
	physics: any,
}

local Game = {}

-- Quién está en cada Sala de Entrenamiento, por orden de llegada (cupo de Afk.ZoneMaxPlayers).
local seats: { [BasePart]: { Player } } = {}

local function seatOf(player: Player, part: BasePart): boolean
	local list = seats[part]
	if not list then
		return false
	end
	local index = table.find(list, player)
	return index ~= nil and index <= Tuning.get("Afk.ZoneMaxPlayers")
end

local function rosterFor(player: Player): { { string | number } }
	local stars = Wanted.stars(player)
	if stars <= 0 then
		return {}
	end
	return Tuning.get("Cops.RosterByStar")[stars]
end

local function patrolType(player: Player): string
	local options = Content.patrolByCap[PlayerStats.starCap(player)] or Content.patrolByCap[1]
	return options[math.random(1, #options)]
end

local function maxCopsFor(player: Player): number
	local size = #Band.nearby(player, 120) + 1
	local single = Tuning.get("Cops.MaxPerPlayer")
	if size <= 1 then
		return single
	end
	return math.clamp(math.floor(Tuning.get("Cops.BandMaxCops") / size), 4, single)
end

local function isProtected(player: Player): boolean
	return World.atHome(player) or Areas.inside(player, "afk") ~= nil or Arrest.isHeld(player)
end

-- La patrulla solo mira a quien está buscado o en plena travesura: sin estrellas se puede
-- pasar delante de un policía. Hacer una travesura a la vista sí lo delata (ver Reactions).
local function canEngage(player: Player): boolean
	return Wanted.stars(player) > 0 or Wanted.state(player) ~= "clear" or Mischief.active(player)
end

function Game.start(context: Context)
	local built = context.built

	-- 1. init de cada core.
	Areas.init({ built = built })
	Progress.init()
	Stats.init()
	Economy.init({ currencies = Content.currencies, capFor = PlayerStats.carryCap })
	Upgrades.init({
		spend = function(player, amount)
			return Economy.spend(player, "dinero", amount, "Shop")
		end,
		levelOf = Progress.level,
	})
	Ascension.init({
		level = Progress.level,
		charge = function(player, fee)
			return Economy.spend(player, "dinero", fee, "Shop")
		end,
		grantCerebros = function(player, amount)
			return Economy.add(player, "cerebros", amount, "Gameplay")
		end,
		spendCerebros = function(player, amount)
			return Economy.spend(player, "cerebros", amount, "Shop")
		end,
	})
	Cosmetics.init({
		spend = function(player, amount)
			return Economy.spend(player, "dinero", amount, "Shop")
		end,
	})
	Quests.init()
	Plots.init({ parts = Areas.parts("plot") })
	Achievements.init({ defs = Catalog.achievements, metric = Hub.metric })
	Wanted.init({ capFor = PlayerStats.starCap, decayBonus = PlayerStats.decayBonus })
	Cops.init({
		types = Content.copTypes,
		spawnPoints = Areas.parts("cop_spawn"),
		heliPoints = Areas.parts("heli_spawn"),
		bossPoints = Areas.parts("comisario_spawn"),
		rosterFor = rosterFor,
		patrolType = patrolType,
		maxFor = maxCopsFor,
		isProtected = isProtected,
		canEngage = canEngage,
		isCovered = function(player)
			return Areas.inside(player, "cubierta") ~= nil
		end,
		sigiloFor = PlayerStats.sigilo,
		difficultyFor = PlayerStats.difficulty,
		speedMultAt = function(position)
			return if Areas.containing(position, "sand") then Tuning.get("World.SandSpeedMult") else 1
		end,
		collisionGroup = Movement.COPS_GROUP,
	})
	Band.init({ names = Content.bandNames, colors = Content.bandColors })
	Arrest.init({ canRescue = Reactions.canRescue })
	Tools.init({
		owns = function(player, toolId)
			return Upgrades.hasTool(player, toolId)
		end,
	})
	Training.init({
		isTraining = function(player)
			local part = Areas.inside(player, "afk")
			return part ~= nil
				and seatOf(player, part)
				and Progress.level(player) >= Tuning.get("Afk.UnlockLevel")
				and Wanted.stars(player) == 0
				and Wanted.state(player) == "clear"
				and not Arrest.isHeld(player)
		end,
		capSeconds = function(player)
			return (Tuning.get("Afk.DailyCapMinutes") + Tuning.get("Afk.DailyCapPerGymLevel") * Upgrades.levelOf(player, "gimnasio")) * 60
		end,
		intervalSeconds = function(player)
			return Tuning.get("Afk.CheckInBaseSeconds") + Tuning.get("Afk.CheckInPerBatteryLevel") * Upgrades.levelOf(player, "bateria")
		end,
		stashCapSeconds = function(player)
			local minutes = if Shop.owns(player, PlayerStats.PASS_STASH) then Tuning.get("Stash.ExtendedCapMinutes") else Tuning.get("Stash.CapMinutes")
			return minutes * 60
		end,
	})

	local spots: { Mischief.Spot } = {}
	for zoneName, def in Catalog.mischiefByZone do
		for _, part in Areas.parts(zoneName) do
			table.insert(spots, { key = Mischief.spotKey(part), part = part, def = def })
		end
	end
	Mischief.init({
		spots = spots,
		maxDesigns = 80,
		durationScale = PlayerStats.durationScale,
		canStart = function(player, def)
			if Arrest.isHeld(player) then
				return false, "arrested"
			end
			if Progress.level(player) < Catalog.mischiefConfig(def).Level then
				return false, "level"
			end
			return true, nil
		end,
		partyFor = function(player, spot)
			local party = { player }
			local level = Catalog.mischiefConfig(spot.def).Level
			for _, member in Band.nearby(player, 2048) do
				local root = member.Character and member.Character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart")
					and (root.Position - spot.part.Position).Magnitude <= Tuning.get("Coop.JoinRange")
					and Progress.level(member) >= level
					and not Arrest.isHeld(member)
					and #party < Tuning.get("Band.MaxMembers")
				then
					table.insert(party, member)
				end
			end
			return party
		end,
	})

	local products = {
		pack_small = { productId = 0, grant = function(player) return Economy.add(player, "dinero", Content.moneyPacks.pack_small, "IAP") end },
		pack_medium = { productId = 0, grant = function(player) return Economy.add(player, "dinero", Content.moneyPacks.pack_medium, "IAP") end },
		pack_large = { productId = 0, grant = function(player) return Economy.add(player, "dinero", Content.moneyPacks.pack_large, "IAP") end },
		soborno = { productId = 0, grant = function(player)
			Cops.dismiss(player)
			Wanted.clear(player, "soborno")
			return true
		end },
	}
	Shop.init({ products = products, passes = Content.passes })

	Movement.init({ built = built, physics = context.physics })
	Transit.init({ built = built })

	-- 2. connect de cada puente.
	Cops_Wanted.connect()
	Wanted_Band.connect()
	Stats_Quests.connect()

	-- 3. start de cada core y reglas propias del juego.
	Areas.start()
	Progress.start()
	Stats.start()
	Economy.start()
	Upgrades.start()
	Ascension.start()
	Cosmetics.start()
	Quests.start()
	Plots.start()
	Achievements.start()
	Training.start()
	Shop.start()
	Wanted.start()
	Cops.start()
	Band.start()
	Mischief.start()
	Tools.start()
	Arrest.start()

	Areas.entered:Connect(function(player, name, part)
		if name == "afk" then
			local list = seats[part]
			if not list then
				list = {}
				seats[part] = list
			end
			if not table.find(list, player) then
				table.insert(list, player)
			end
		end
	end)
	Areas.left:Connect(function(player, name, part)
		if name == "afk" and seats[part] then
			local index = table.find(seats[part], player)
			if index then
				table.remove(seats[part], index)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, list in seats do
			local index = table.find(list, player)
			if index then
				table.remove(list, index)
			end
		end
	end)

	Movement.start()
	World.start()
	Hub.start(built)
	Effects.start()
	Reactions.start()
	Intents.start()
end

-- Bootstrap lo llama al empezar a salir un jugador, antes de que el servicio de datos lo libere.
function Game.onLeaving(player: Player)
	Reactions.onLeaving(player)
end

return Game

--[[
	Plaza · módulo core con las reglas del place de inicio. Cada zona "portal:<place>"
	lleva al jugador a ese place con Travel. En Studio no hay viajes: Travel avisa y
	el jugador se queda.

	API:
	  Plaza.init(options)   niveles construidos del place, antes de start
	  Plaza.start()         conecta los portales y atiende a los jugadores
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Tuning = require(ReplicatedStorage.Shared.Tuning)
local LevelLoader = require(ServerScriptService.Server.LevelLoader)
local Telemetry = require(ServerScriptService.Server.Telemetry)
local Travel = require(ServerScriptService.Server.Travel)

export type Options = {
	built: LevelLoader.Built, -- niveles de la plaza
}

local Plaza = {}

local ONBOARDING_JOINED = 1
local ONBOARDING_PORTAL = 2

local built: LevelLoader.Built
local lastTry: { [Player]: number } = {}

local function playerFromHit(hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

local function onPortalTouched(destination: string, hit: BasePart)
	local player = playerFromHit(hit)
	if not player then
		return
	end
	local now = os.clock()
	if now - (lastTry[player] or -math.huge) < Tuning.get("Travel.PortalCooldown") then
		return
	end
	lastTry[player] = now
	Telemetry.onboarding(player, ONBOARDING_PORTAL, "portal")
	Travel.to({ player }, destination)
end

function Plaza.init(options: Options)
	built = options.built
end

function Plaza.start()
	for _, level in built.levels do
		for _, zone in level.byKind.zone or {} do
			local destination = string.match(tostring(zone:GetAttribute("ZoneName")), "^portal:(.+)$")
			if destination then
				zone.Touched:Connect(function(hit)
					onPortalTouched(destination, hit)
				end)
			end
		end
	end

	local function onPlayerAdded(player: Player)
		Telemetry.onboarding(player, ONBOARDING_JOINED, "joined")
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
	end)
end

return Plaza

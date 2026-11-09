--[[
	Bootstrap: única entrada del servidor. Prepara el núcleo (datos, canal de red,
	mundo y pase de arte) y después llama a Game, que arma los cores, los puentes y el contenido.

	Orden de inicio (references/hooks.md del builder):
	  1. Config, Tuning y Telemetry se cargan al requerirlos; la iluminación del tema.
	  2. El servicio de datos (PlayerData.start).
	  3. El mundo desde Levels.json (LevelLoader).
	  4. El canal de red (Net crea su RemoteEvent al requerirse).
	  5. Game.start: init de los cores, connect de los puentes y start de los cores.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = require(ReplicatedStorage.Shared.Environment)
local Levels = require(ReplicatedStorage.Shared.Levels)
local Net = require(ReplicatedStorage.Shared.Net)
local PlayerData = require(script.Parent.Data.PlayerData)
local EnvironmentLoader = require(script.Parent.EnvironmentLoader)
local Game = require(script.Parent.Game)
local LevelLoader = require(script.Parent.LevelLoader)

-- Primero se conecta la salida del juego y después el servicio de datos: así, cuando un jugador
-- se va, el Botín se deposita (o se pierde) antes de que su perfil se guarde y se libere.
Players.PlayerRemoving:Connect(function(player)
	Game.onLeaving(player)
end)

PlayerData.start() -- empieza a cargar los perfiles; cada core espera el suyo
LevelLoader.applyPhysics(Levels.physics)
local built = LevelLoader.build(Levels)
EnvironmentLoader.apply(built, Environment) -- viste los niveles y aplica la iluminación del tema
assert(Net, "el canal de red no se creó")
Game.start({ built = built, physics = Levels.physics })

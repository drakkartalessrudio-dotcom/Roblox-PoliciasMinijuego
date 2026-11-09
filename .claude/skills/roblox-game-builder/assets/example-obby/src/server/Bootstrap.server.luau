--[[
	Bootstrap: única entrada del servidor. Prepara el núcleo en orden explícito
	(datos, física, mundo y pase de arte) y después llama a Game, que arranca las
	reglas, para que ningún jugador interactúe con un mundo a medio construir.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = require(ReplicatedStorage.Shared.Environment)
local Levels = require(ReplicatedStorage.Shared.Levels)
local PlayerData = require(script.Parent.Data.PlayerData)
local EnvironmentLoader = require(script.Parent.EnvironmentLoader)
local Game = require(script.Parent.Game)
local LevelLoader = require(script.Parent.LevelLoader)

PlayerData.start() -- empieza a cargar los perfiles; Obby espera a cada uno
LevelLoader.applyPhysics(Levels.physics)
local built = LevelLoader.build(Levels)
EnvironmentLoader.apply(built, Environment) -- también aplica la iluminación del tema
Game.start({ built = built, physics = Levels.physics })

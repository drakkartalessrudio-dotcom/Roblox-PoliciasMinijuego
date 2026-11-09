--[[
	Bootstrap: única entrada del servidor. Inicia los sistemas en orden explícito
	(iluminación, física, mundo y reglas) para que ningún jugador interactúe con un mundo a medio
	construir.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Levels = require(ReplicatedStorage.Shared.Levels)
local Style = require(ReplicatedStorage.Shared.Style)
local LevelLoader = require(script.Parent.LevelLoader)
local ObbyService = require(script.Parent.ObbyService)

Style.applyLighting("default")
LevelLoader.applyPhysics(Levels.physics)
local built = LevelLoader.build(Levels)
ObbyService.start(built, Levels.physics)

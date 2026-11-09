--[[
	Bootstrap: única entrada del servidor, la misma en los dos places. Cada place
	construye solo sus niveles (Place.levels) y Game arranca las reglas según su rol.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Levels = require(ReplicatedStorage.Shared.Levels)
local Place = require(ReplicatedStorage.Shared.Place)
local Game = require(script.Parent.Game)
local LevelLoader = require(script.Parent.LevelLoader)

LevelLoader.applyPhysics(Levels.physics)
local built = LevelLoader.build(Levels, nil, { only = Place.levels(Levels) })
Game.start({ built = built, physics = Levels.physics })

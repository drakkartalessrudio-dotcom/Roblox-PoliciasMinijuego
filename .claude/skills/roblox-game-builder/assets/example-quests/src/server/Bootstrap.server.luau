--[[
	Bootstrap: única entrada del servidor. Prepara el núcleo (datos y mundo) y después
	llama a Game, que arma los cores, los puentes y el contenido del juego.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Levels = require(ReplicatedStorage.Shared.Levels)
local PlayerData = require(script.Parent.Data.PlayerData)
local Game = require(script.Parent.Game)
local LevelLoader = require(script.Parent.LevelLoader)

PlayerData.start() -- empieza a cargar los perfiles; cada core espera el suyo
LevelLoader.applyPhysics(Levels.physics)
local built = LevelLoader.build(Levels)
Game.start({ built = built })

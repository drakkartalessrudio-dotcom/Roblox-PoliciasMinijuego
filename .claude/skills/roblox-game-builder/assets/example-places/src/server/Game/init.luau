--[[
	Game · composición de la experiencia de dos places. Es la misma en los dos: según
	el rol del place arranca el core de la plaza o el de la torre. Los cores no saben
	en qué place corren.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Place = require(ReplicatedStorage.Shared.Place)
local LevelLoader = require(script.Parent.LevelLoader)
local Plaza = require(script.Parent.Modules.Plaza)
local Tower = require(script.Parent.Modules.Tower)

export type Context = {
	built: LevelLoader.Built, -- solo los niveles de este place
	physics: any,
}

local Game = {}

function Game.start(context: Context)
	if Place.role() == "start" then
		Plaza.init({ built = context.built })
		Plaza.start()
	else
		Tower.init({ built = context.built, physics = context.physics })
		Tower.start()
	end
end

return Game

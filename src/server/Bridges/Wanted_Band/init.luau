--[[
	Wanted_Band · puente: Wanted emite, Band reacciona. El calor se contagia: el 50 % de
	lo que gana un miembro pasa a los compañeros cercanos. Lo contagiado no vuelve a
	contagiarse. El techo de estrellas de cada compañero lo pone Wanted según su nivel.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Tuning = require(ReplicatedStorage.Shared.Tuning)
local Band = require(ServerScriptService.Server.Modules.Band)
local Wanted = require(ServerScriptService.Server.Modules.Wanted)

local Wanted_Band = {}

function Wanted_Band.connect()
	Wanted.heatAdded:Connect(function(player, amount, reason)
		if reason == "contagio" or reason == "persecucion" or reason == "visto" then
			return
		end
		for _, member in Band.nearby(player, Tuning.get("Band.HeatShareRange")) do
			Wanted.addHeat(member, amount * Tuning.get("Band.HeatShareFraction"), "contagio")
		end
	end)
end

return Wanted_Band

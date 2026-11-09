--[[
	Cops_Wanted · puente: Cops emite, Wanted reacciona. Lo que ven los policías es lo que
	mantiene o sube las estrellas, y derribar a un policía suma calor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Tuning = require(ReplicatedStorage.Shared.Tuning)
local Cops = require(ServerScriptService.Server.Modules.Cops)
local Wanted = require(ServerScriptService.Server.Modules.Wanted)

local Cops_Wanted = {}

function Cops_Wanted.connect()
	Cops.sightChanged:Connect(function(player, seen)
		Wanted.setSeen(player, seen)
	end)
	Cops.knockedDown:Connect(function(_cop, attacker)
		if attacker then
			Wanted.addHeat(attacker, Tuning.get("Heat.CopKnockdown"), "derribo")
		end
	end)
end

return Cops_Wanted

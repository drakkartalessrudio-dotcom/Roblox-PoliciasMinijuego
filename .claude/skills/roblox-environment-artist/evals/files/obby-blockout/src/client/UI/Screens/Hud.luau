--[[
	Hud: nivel, checkpoint, mensaje inicial y aviso de fin.

	Solo presenta el estado que publica el servidor en atributos del jugador
	(Level, LevelCount, Checkpoint y Finished; ver "Estado para la UI" en el GDD).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Tuning"))

local Hud = {}

function Hud.mount(Kit: any)
	local player = Players.LocalPlayer
	local panel = Kit.panel(Kit.slot("top"))
	local status = Kit.label({ text = "Cargando…", kind = "heading", parent = panel, size = UDim2.fromOffset(340, 40) })

	local function render()
		if player:GetAttribute("Finished") == true then
			status.Text = "¡Completaste el obby!"
			return
		end
		local level = player:GetAttribute("Level")
		local count = player:GetAttribute("LevelCount")
		if type(level) ~= "number" or type(count) ~= "number" then
			status.Text = "Cargando…"
			return
		end
		status.Text = `Nivel {level}/{count} · Checkpoint {player:GetAttribute("Checkpoint") or 0}`
	end

	for _, attribute in { "Level", "LevelCount", "Checkpoint" } do
		Kit.bindAttribute(player, attribute, render)
	end
	Kit.bindAttribute(player, "Finished", function(finished)
		render()
		if finished == true then
			Kit.toast("¡Completaste el obby!", 5)
		end
	end)

	Kit.toast(Tuning.get("Hud.HintText"), Tuning.get("Hud.HintSeconds"))
end

return Hud

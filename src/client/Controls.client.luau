--[[
	Controls · entrada del jugador en el cliente: Embestida (Dash), Empujón y herramientas.
	Solo manda INTENCIONES al servidor (Net "use_tool"); el servidor valida el enfriamiento,
	si tiene la herramienta y qué pasa. Los botones táctiles son de la pantalla Actions de la interfaz
	(slot `actions`), que también muestra los enfriamientos.

	  PC          Q Embestida · F Empujón · 1 a 5 herramientas
	  Consola     X Embestida · B Empujón
	  Celular     botones en pantalla

	El impulso del Dash lo aplica este script porque el cliente es el dueño de la física de
	su personaje; el servidor ya subió la velocidad y mide a quién derriba.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Catalog = require(ReplicatedStorage.Shared.Catalog)
local Net = require(ReplicatedStorage.Shared.Net)

local player = Players.LocalPlayer

local function aimDirection(): Vector3
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
end

local function bindTool(actionName: string, toolId: string, keys: { Enum.KeyCode | Enum.UserInputType })
	ContextActionService:BindAction(actionName, function(_, state)
		if state == Enum.UserInputState.Begin then
			Net.send("use_tool", { id = toolId, direction = aimDirection() })
		end
		return Enum.ContextActionResult.Pass
	end, false, table.unpack(keys))
end

bindTool("TB_Dash", "dash", { Enum.KeyCode.Q, Enum.KeyCode.ButtonX })
bindTool("TB_Push", "push", { Enum.KeyCode.F, Enum.KeyCode.ButtonB })

-- Las herramientas compradas aparecen como botón solo cuando el jugador las tiene.
local function refreshTools()
	for _, tool in Catalog.tools do
		local action = `TB_Tool_{tool.id}`
		if player:GetAttribute(`Tool_{tool.id}`) then
			bindTool(action, tool.id, { tool.hotkey })
		else
			ContextActionService:UnbindAction(action)
		end
	end
end

for _, tool in Catalog.tools do
	player:GetAttributeChangedSignal(`Tool_{tool.id}`):Connect(refreshTools)
end
refreshTools()

Net.on("dash", function(payload)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or typeof(payload) ~= "table" then
		return
	end
	local direction, speed = payload.direction, payload.speed
	if typeof(direction) == "Vector3" and type(speed) == "number" then
		root.AssemblyLinearVelocity = Vector3.new(direction.X, 0, direction.Z).Unit * speed + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
	end
end)

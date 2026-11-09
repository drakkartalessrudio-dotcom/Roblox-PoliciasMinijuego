--[[
	Actions: los botones de acción junto al botón de salto (slot `actions`): Embestida,
	Empujón, las herramientas que el jugador ya compró y, con el pase del teléfono,
	Depositar. Cada botón muestra su enfriamiento. Solo envía intenciones (`use_tool`,
	`deposit`); el servidor valida propiedad, enfriamiento y efecto.

	Estado: Tool_<id>, ToolReady_<id>, Pass_phone, Botin y Stars del jugador.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Net = require(Shared:WaitForChild("Net"))

local Actions = {}

local function aimDirection(): Vector3
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
end

function Actions.mount(Kit: any)
	local player = Players.LocalPlayer
	local slot = Kit.slot("actions")

	type Entry = { button: TextButton, id: string, label: string, owned: () -> boolean }
	local entries: { Entry } = {}

	local function add(id: string, label: string, owned: () -> boolean, onActivated: () -> ())
		local button = Kit.button({ text = label, variant = "secondary", parent = slot, onActivated = onActivated })
		table.insert(entries, { button = button, id = id, label = label, owned = owned })
	end

	add("dash", "Embestida", function()
		return true
	end, function()
		Net.send("use_tool", { id = "dash", direction = aimDirection() })
	end)
	add("push", "Empujón", function()
		return true
	end, function()
		Net.send("use_tool", { id = "push", direction = aimDirection() })
	end)
	for _, tool in Catalog.tools do
		add(tool.id, tool.name, function()
			return player:GetAttribute(`Tool_{tool.id}`) == true
		end, function()
			Net.send("use_tool", { id = tool.id, direction = aimDirection() })
		end)
	end
	local deposit = Kit.button({
		text = "Depositar",
		variant = "primary",
		parent = slot,
		onActivated = function()
			Net.send("deposit")
		end,
	})

	local function refresh()
		local now = Workspace:GetServerTimeNow()
		for _, entry in entries do
			entry.button.Visible = entry.owned()
			local readyAt = player:GetAttribute(`ToolReady_{entry.id}`)
			local remaining = if type(readyAt) == "number" then readyAt - now else 0
			entry.button.Text = if remaining > 0.1 then `{entry.label} {math.ceil(remaining)}s` else entry.label
			entry.button.BackgroundTransparency = if remaining > 0.1 then 0.5 else 0
		end
		local loot = player:GetAttribute("Botin")
		local stars = player:GetAttribute("Stars")
		deposit.Visible = player:GetAttribute("Pass_phone") == true and type(loot) == "number" and loot > 0 and stars == 0
	end

	task.spawn(function()
		while true do
			refresh()
			task.wait(0.25)
		end
	end)
end

return Actions

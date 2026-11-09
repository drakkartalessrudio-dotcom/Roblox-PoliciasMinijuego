--[[
	UI: punto de entrada de la interfaz (dueño: roblox-ui-designer).

	Inicia el kit y monta las pantallas de design/UI.md en orden. Cada pantalla es
	un módulo de Screens con una función mount(Kit).
]]

local Kit = require(script:WaitForChild("Kit"))
local Screens = script:WaitForChild("Screens")

local SCREENS = { "Hud", "Alerts", "Actions", "Minigames", "Shop", "Career", "Band", "Sala", "Hub" }

Kit.start()
for _, name in SCREENS do
	local screen = require(Screens:WaitForChild(name)) :: any
	screen.mount(Kit)
end

--[[
	Kit · kit de UI de la fábrica (roblox-ui-designer). Cópialo sin cambios.

	Punto de entrada de la interfaz. Las pantallas del juego (src/client/UI/Screens)
	reciben este módulo y colocan sus elementos raíz en slots o en la capa modal:

	  local Kit = require(script.Parent.Parent.Kit)
	  Kit.start()
	  local status = Kit.label({ text = "", kind = "heading", parent = Kit.slot("top") })
	  Kit.button({ text = "Tienda", binding = { keyboard = Enum.KeyCode.B, gamepad = Enum.KeyCode.ButtonY },
	      parent = Kit.slot("left"), onActivated = function() shop:open() end })

	Requiere src/shared/Style.luau y src/shared/Theme.json (roblox-art-director).
	API completa en references/kit.md del skill.
]]

local Components = require(script:WaitForChild("Components"))
local Input = require(script:WaitForChild("Input"))
local Layout = require(script:WaitForChild("Layout"))

local Kit = {}

Kit.Input = Input

Kit.start = Layout.start
Kit.refresh = Layout.refresh
Kit.slot = Layout.slot
Kit.layer = Layout.layer
Kit.scale = Layout.scale
Kit.chatRect = Layout.chatRect
Kit.touchRects = Layout.touchRects

Kit.panel = Components.panel
Kit.label = Components.label
Kit.button = Components.button
Kit.modal = Components.modal
Kit.toast = Components.toast
Kit.tabs = Components.tabs
Kit.grid = Components.grid
Kit.card = Components.card
Kit.status = Components.status
Kit.bindAttribute = Components.bindAttribute

return Kit

--[[
	Help: botón "Controles" en el riel izquierdo (debajo del chat) y ventana con los
	controles de la entrada que está usando el jugador.
]]

local Help = {}

local TEXTS = {
	Touch = "Muévete con el joystick y salta con el botón de la derecha. Evita la lava naranja.",
	Gamepad = "Stick izquierdo: moverte · A: saltar. Evita la lava naranja.",
	KeyboardAndMouse = "WASD: moverte · Espacio: saltar. Evita la lava naranja.",
}

function Help.mount(Kit: any)
	local modal = Kit.modal("Controles")
	local text = Kit.label({ kind = "body", parent = modal.content, size = UDim2.fromOffset(420, 96) })
	Kit.Input.onChanged(function(preferred: Enum.PreferredInput)
		text.Text = TEXTS[preferred.Name] or TEXTS.KeyboardAndMouse
	end)

	Kit.button({
		text = "Controles",
		variant = "secondary",
		binding = { keyboard = Enum.KeyCode.H, gamepad = Enum.KeyCode.ButtonX },
		parent = Kit.slot("left"),
		onActivated = function()
			if modal:isOpen() then
				modal:close()
			else
				modal:open()
			end
		end,
	})
end

return Help

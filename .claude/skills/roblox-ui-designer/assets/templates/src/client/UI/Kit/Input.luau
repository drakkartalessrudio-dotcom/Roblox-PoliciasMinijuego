--[[
	Input · kit de UI de la fábrica (roblox-ui-designer).

	Sigue el tipo de entrada preferido del jugador (UserInputService.PreferredInput:
	Touch, Gamepad o KeyboardAndMouse) para que botones y textos de ayuda muestren
	el control correcto, y registra atajos de teclado y gamepad sin crear botones
	táctiles extra: en táctil la acción es un botón del kit en pantalla.
]]

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Input = {}

export type Binding = {
	keyboard: Enum.KeyCode?,
	gamepad: Enum.KeyCode?,
}

local listeners: { (Enum.PreferredInput) -> () } = {}

function Input.preferred(): Enum.PreferredInput
	return UserInputService.PreferredInput
end

-- Llama a callback ahora y cada vez que cambia el tipo de entrada preferido.
function Input.onChanged(callback: (Enum.PreferredInput) -> ()): () -> ()
	table.insert(listeners, callback)
	task.spawn(callback, UserInputService.PreferredInput)
	return function()
		local index = table.find(listeners, callback)
		if index then
			table.remove(listeners, index)
		end
	end
end

UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
	for _, callback in table.clone(listeners) do
		task.spawn(callback, UserInputService.PreferredInput)
	end
end)

local GAMEPAD_NAMES: { [string]: string } = {
	ButtonA = "A",
	ButtonB = "B",
	ButtonX = "X",
	ButtonY = "Y",
	ButtonL1 = "LB",
	ButtonR1 = "RB",
	ButtonL2 = "LT",
	ButtonR2 = "RT",
	ButtonSelect = "Select",
	ButtonStart = "Start",
	DPadUp = "↑",
	DPadDown = "↓",
	DPadLeft = "←",
	DPadRight = "→",
}

-- Texto corto del control para la entrada actual: "B" en teclado, "Y" en gamepad,
-- "" en táctil (ahí se toca el botón).
function Input.hint(binding: Binding?): string
	if not binding then
		return ""
	end
	local preferred = UserInputService.PreferredInput
	if preferred == Enum.PreferredInput.Gamepad and binding.gamepad then
		return GAMEPAD_NAMES[binding.gamepad.Name] or binding.gamepad.Name
	elseif preferred == Enum.PreferredInput.KeyboardAndMouse and binding.keyboard then
		return binding.keyboard.Name
	end
	return ""
end

-- Registra un atajo de teclado o gamepad. Devuelve la función para quitarlo.
function Input.bindAction(name: string, binding: Binding, callback: () -> ()): () -> ()
	local keys = {}
	if binding.keyboard then
		table.insert(keys, binding.keyboard)
	end
	if binding.gamepad then
		table.insert(keys, binding.gamepad)
	end
	if #keys == 0 then
		return function() end
	end
	local actionName = "Kit_" .. name
	ContextActionService:BindAction(actionName, function(_, state)
		if state == Enum.UserInputState.Begin then
			callback()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, table.unpack(keys))
	return function()
		ContextActionService:UnbindAction(actionName)
	end
end

return Input

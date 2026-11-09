--[[
	TravelNotice: avisa en el Output cuando un viaje entre places falla. El servidor pone
	en el jugador el atributo TravelFailed con la clave del destino. Un juego con UI lo
	muestra en pantalla (ver patrones del UI designer).
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer

player:GetAttributeChangedSignal("TravelFailed"):Connect(function()
	local destination = player:GetAttribute("TravelFailed")
	if destination then
		warn(`No se pudo viajar a "{destination}". Prueba de nuevo en unos segundos.`)
	end
end)

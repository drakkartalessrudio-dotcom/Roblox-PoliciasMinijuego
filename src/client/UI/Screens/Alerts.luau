--[[
	Alerts: los avisos breves del juego. Convierte los mensajes `notify` del servidor en
	toasts legibles (travesura completada, estrellas, escape, arresto, subida de nivel,
	depósito, errores…). No decide nada: solo cuenta lo que el servidor ya resolvió.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Format = require(script.Parent.Parent:WaitForChild("Format"))

local Alerts = {}

local ABILITIES = {
	vapor = "¡Vapor! Vas más lento un momento",
	red = "¡Te cayó una red del helicóptero!",
	grito = "¡El Comisario grita y te aturde!",
}

local FAIL = {
	failed = "Fallaste la travesura",
	fast = "Muy rápido: no cuenta",
	late = "Se acabó el tiempo",
	slow = "Te quedaste cerca del timbre",
	spotted = "¡Te vieron! Se cortó la travesura",
}

function Alerts.mount(Kit: any)
	local handlers: { [string]: (data: any) -> () } = {
		mischief = function(data)
			local text = `{data.name}: +{Format.money(data.money)} · +{Format.number(data.xp)} XP`
			if data.combo then
				text ..= " · ¡Combo!"
			end
			if data.party and data.party > 1 then
				text ..= ` · Banda x{data.party}`
			end
			Kit.toast(text, 3)
			if data.full then
				Kit.toast("Botín lleno: deposítalo en una Guarida", 4)
			end
		end,
		mischief_failed = function(data)
			Kit.toast(FAIL[data.reason] or "No salió la travesura", 3)
		end,
		stars = function(data)
			Kit.toast(`{data.stars} {if data.stars == 1 then "estrella" else "estrellas"}: ¡corre!`, 3)
		end,
		escaped = function(data)
			Kit.toast(`¡Escapaste! +{Format.number(data.xp)} XP`, 4)
		end,
		arrested = function(data)
			Kit.toast(`¡Te agarraron! Si un compañero llega en {data.window}s te rescata`, data.window)
		end,
		arrest_result = function(data)
			if data.rescued then
				Kit.toast(`¡{data.by or "Un compañero"} te rescató! Perdiste {Format.money(data.lost)}`, 4)
			else
				Kit.toast(`Perdiste {Format.money(data.lost)} de Botín`, 4)
			end
		end,
		rescued_other = function(data)
			Kit.toast(`Rescataste a {data.name}`, 3)
		end,
		deposit = function(data)
			Kit.toast(`Depositaste {Format.money(data.amount)}`, 3)
		end,
		spray = function(data)
			Kit.toast(`Pay'n'Spray: quitaste {data.stars} estrellas por {Format.money(data.cost)}`, 3)
		end,
		level = function(data)
			local text = `¡Nivel {data.level}!`
			if data.unlocks and #data.unlocks > 0 then
				text ..= " Nuevo: " .. table.concat(data.unlocks, ", ")
			end
			Kit.toast(text, 5)
		end,
		medal = function(data)
			Kit.toast(`¡Medalla del Comisario! +{Format.money(data.money)}`, 5)
		end,
		quest_reward = function(data)
			Kit.toast(`Recompensa {if data.weekly then "semanal" else "diaria"}: +{Format.money(data.money)}`, 4)
		end,
		ascended = function(data)
			Kit.toast(`¡Ascensión {data.count}! Ganaste {data.cerebros} Cerebros`, 6)
		end,
		travel_locked = function(data)
			Kit.toast(`{data.name} se abre en el nivel {data.level}`, 3)
		end,
		achievement = function(data)
			Kit.toast(`¡Logro: {data.name}! {data.description}`, 5)
		end,
		ability = function(data)
			Kit.toast(ABILITIES[data.ability] or "¡Cuidado!", 2)
		end,
		error = function(data)
			Kit.toast(Format.error(data.code), 3)
		end,
	}

	Net.on("notify", function(data)
		if type(data) ~= "table" or type(data.kind) ~= "string" then
			return
		end
		local handler = handlers[data.kind]
		if handler then
			handler(data)
		end
	end)

	Net.on("stash_claimed", function(data)
		Kit.toast(`Cobraste el alijo ({Format.minutes(data.seconds)} acumulados)`, 3)
	end)
	Net.on("afk_result", function(data)
		if data.result == "wrong" then
			Kit.toast("Ese no era: prueba otra vez", 2)
		elseif data.result == "fast" then
			Kit.toast("Demasiado rápido: nuevo reto", 2)
		elseif data.result == "locked" then
			Kit.toast("Demasiados errores: espera unos minutos", 3)
		end
	end)
end

return Alerts

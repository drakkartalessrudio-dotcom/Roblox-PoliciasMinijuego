--[[
	Intents · todo lo que el cliente puede PEDIR al servidor, con su validación. El cliente
	manda intenciones ("comprar la mejora X", "usar la tarta hacia aquí"); el servidor
	decide con sus propios datos. Nunca acepta precios, cantidades de recompensa ni
	confirmaciones de compra.

	Mensajes (Net.send desde el cliente):
	  mischief_submit {id, success}   resultado del minijuego (el servidor valida tiempo y cercanía)
	  mischief_cancel                 abandona la travesura en curso
	  use_tool {id, direction?}       dash, push o una herramienta comprada
	  buy_upgrade {id} · buy_tool {id} · buy_cosmetic {id}   solo dentro de una Guarida
	  equip_cosmetic {id} · unequip_cosmetic {slot}
	  deposit                         con el pase del teléfono, desde cualquier lugar; si no, en la Guarida
	  spray                           en el Pay'n'Spray
	  ascend · buy_perk {id}          solo en la Guarida y sin estrellas
	  travel {id}                     viajar a un destino (Transit valida nivel, estrellas y zona segura)
	  plot_go · plot_release          ir a la propia parcela del lobby · soltarla
	  claim_quest {id} · claim_weekly · claim_stash
	  afk_answer {id, choice}         respuesta al reto de check-in
	  band {action, userId?, bandId?, value?}   create invite accept decline join leave kick open color list
	  shop_product {key} · shop_pass {key}      abre el prompt nativo de Roblox
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Destinations = require(ReplicatedStorage.Shared.Destinations)
local Net = require(ReplicatedStorage.Shared.Net)
local Ascension = require(ServerScriptService.Server.Modules.Ascension)
local Band = require(ServerScriptService.Server.Modules.Band)
local Cosmetics = require(ServerScriptService.Server.Modules.Cosmetics)
local Economy = require(ServerScriptService.Server.Modules.Economy)
local Mischief = require(ServerScriptService.Server.Modules.Mischief)
local Plots = require(ServerScriptService.Server.Modules.Plots)
local Quests = require(ServerScriptService.Server.Modules.Quests)
local Shop = require(ServerScriptService.Server.Modules.Shop)
local Tools = require(ServerScriptService.Server.Modules.Tools)
local Training = require(ServerScriptService.Server.Modules.Training)
local Upgrades = require(ServerScriptService.Server.Modules.Upgrades)
local Wanted = require(ServerScriptService.Server.Modules.Wanted)
local Effects = require(script.Parent.Effects)
local Hub = require(script.Parent.Hub)
local Transit = require(script.Parent.Transit)
local World = require(script.Parent.World)

local Intents = {}

local function fail(player: Player, code: string?)
	Net.send(player, "notify", { kind = "error", code = code or "unknown" })
end

local function inGuarida(player: Player): boolean
	return World.atHome(player)
end

local function idPayload(payload: any): { id: string }?
	if type(payload) == "table" and Net.isId(payload.id, 32) then
		return { id = payload.id }
	end
	return nil
end

local function purchase(kind: string, action: (Player, string) -> (boolean, string?))
	Net.on(kind, idPayload, function(player, payload)
		if not inGuarida(player) then
			fail(player, "away")
			return
		end
		local ok, reason = action(player, payload.id)
		if not ok then
			fail(player, reason)
		end
	end, 0.3)
end

function Intents.start()
	Net.on("mischief_submit", function(payload)
		if type(payload) == "table" and type(payload.id) == "string" and #payload.id <= 48 and type(payload.success) == "boolean" then
			return { id = payload.id, success = payload.success }
		end
		return nil
	end, function(player, payload)
		local ok, reason = Mischief.submit(player, payload.id, payload.success)
		if not ok and reason ~= "stale" then
			fail(player, reason)
		end
	end, 0.2)

	Net.on("mischief_cancel", function()
		return true
	end, function(player)
		Mischief.cancel(player)
	end, 0.2)

	Net.on("use_tool", function(payload)
		if type(payload) ~= "table" or not Net.isId(payload.id, 16) then
			return nil
		end
		local direction = payload.direction
		if direction ~= nil and not Net.isDirection(direction) then
			return nil
		end
		return { id = payload.id, direction = direction }
	end, function(player, payload)
		Effects.aim[player] = payload.direction
		local ok, reason = Tools.use(player, payload.id)
		if not ok and reason ~= "cooldown" then
			fail(player, reason)
		end
	end, 0.1)

	purchase("buy_upgrade", function(player, id)
		return Upgrades.buy(player, id)
	end)
	purchase("buy_tool", function(player, id)
		return Upgrades.buyTool(player, id)
	end)
	purchase("buy_cosmetic", function(player, id)
		return Cosmetics.buy(player, id)
	end)
	purchase("buy_perk", function(player, id)
		return Ascension.buyPerk(player, id)
	end)

	Net.on("equip_cosmetic", idPayload, function(player, payload)
		if not Cosmetics.equip(player, payload.id) then
			fail(player, "locked")
		end
	end, 0.3)
	Net.on("unequip_cosmetic", function(payload)
		if type(payload) == "table" and Net.isId(payload.slot, 16) then
			return { slot = payload.slot }
		end
		return nil
	end, function(player, payload)
		Cosmetics.unequip(player, payload.slot)
	end, 0.3)

	Net.on("deposit", function()
		return true
	end, function(player)
		local ok, reason = World.deposit(player)
		if not ok and reason ~= "empty" then
			fail(player, reason)
		end
	end, 0.5)
	Net.on("spray", function()
		return true
	end, function(player)
		local ok, reason = World.spray(player)
		if not ok then
			fail(player, reason)
		end
	end, 0.5)

	Net.on("ascend", function()
		return true
	end, function(player)
		if not inGuarida(player) then
			fail(player, "away")
			return
		end
		if Wanted.stars(player) > 0 or Wanted.state(player) ~= "clear" then
			fail(player, "wanted")
			return
		end
		local can, reason = Ascension.canAscend(player)
		if not can then
			fail(player, reason)
			return
		end
		Economy.deposit(player) -- el Botín se cobra antes de reiniciar
		local ok, why = Ascension.ascend(player)
		if not ok then
			fail(player, why)
		end
	end, 1)

	Net.on("travel", idPayload, function(player, payload)
		local ok, reason = Transit.to(player, payload.id)
		if not ok then
			local destination = Destinations.byId[payload.id]
			if destination then
				Hub.travelError(player, destination, reason)
			else
				fail(player, reason)
			end
		end
	end, 0.5)
	Net.on("plot_go", function()
		return true
	end, function(player)
		if not Hub.goToPlot(player) then
			fail(player, "away")
		end
	end, 1)
	Net.on("plot_release", function()
		return true
	end, function(player)
		Plots.release(player)
	end, 0.5)

	Net.on("claim_quest", idPayload, function(player, payload)
		if not Quests.claim(player, payload.id) then
			fail(player, "unavailable")
		end
	end, 0.3)
	Net.on("claim_weekly", function()
		return true
	end, function(player)
		if not Quests.claimWeekly(player) then
			fail(player, "unavailable")
		end
	end, 0.3)
	Net.on("claim_stash", function()
		return true
	end, function(player)
		if not inGuarida(player) then
			fail(player, "away")
			return
		end
		local seconds = Training.claimStash(player)
		if not seconds then
			fail(player, "empty")
			return
		end
		Net.send(player, "stash_claimed", { seconds = seconds })
	end, 0.5)

	Net.on("afk_answer", function(payload)
		if type(payload) == "table" and type(payload.id) == "string" and #payload.id <= 48 and Net.isId(payload.choice, 16) then
			return { id = payload.id, choice = payload.choice }
		end
		return nil
	end, function(player, payload)
		local result = Training.answer(player, payload.id, payload.choice)
		Net.send(player, "afk_result", { result = result })
	end, 0.2)

	Net.on("band", function(payload)
		if type(payload) ~= "table" or type(payload.action) ~= "string" or #payload.action > 12 then
			return nil
		end
		local cleaned = { action = payload.action } :: { [string]: any }
		if type(payload.userId) == "number" and payload.userId == payload.userId then
			cleaned.userId = math.floor(payload.userId)
		end
		if type(payload.bandId) == "string" and #payload.bandId <= 16 then
			cleaned.bandId = payload.bandId
		end
		if type(payload.value) == "boolean" or type(payload.value) == "number" then
			cleaned.value = payload.value
		end
		return cleaned
	end, function(player, payload)
		local action = payload.action
		local target = if payload.userId then Players:GetPlayerByUserId(payload.userId) else nil
		local ok: boolean, reason: string? = true, nil
		if action == "create" then
			ok, reason = Band.create(player)
		elseif action == "invite" and target then
			ok, reason = Band.invite(player, target)
		elseif action == "accept" then
			ok, reason = Band.accept(player)
		elseif action == "decline" then
			Band.decline(player)
		elseif action == "join" and payload.bandId then
			ok, reason = Band.join(player, payload.bandId)
		elseif action == "leave" then
			Band.leave(player)
		elseif action == "kick" and target then
			ok = Band.kick(player, target)
		elseif action == "open" then
			ok = Band.setOpen(player, payload.value == true)
		elseif action == "color" and type(payload.value) == "number" then
			ok = Band.setColor(player, math.floor(payload.value))
		elseif action == "list" then
			Net.send(player, "band_list", Band.listOpen())
		else
			ok, reason = false, "unknown"
		end
		if not ok then
			fail(player, reason or "band")
		end
	end, 0.3)

	Net.on("shop_product", function(payload)
		if type(payload) == "table" and Net.isId(payload.key, 24) then
			return { key = payload.key }
		end
		return nil
	end, function(player, payload)
		local ok, reason = Shop.requestProduct(player, payload.key)
		if not ok then
			fail(player, reason)
		end
	end, 1)
	Net.on("shop_pass", function(payload)
		if type(payload) == "table" and Net.isId(payload.key, 24) then
			return { key = payload.key }
		end
		return nil
	end, function(player, payload)
		local ok, reason = Shop.requestPass(player, payload.key)
		if not ok then
			fail(player, reason)
		end
	end, 1)

	Players.PlayerRemoving:Connect(function(player)
		Mischief.cancel(player)
	end)
end

return Intents

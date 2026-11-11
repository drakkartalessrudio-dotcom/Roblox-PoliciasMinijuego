--[[
	World · lo que hacen las zonas del mundo en TravesurasBrainrot: la Guarida (depósito
	de Botín), el Pay'n'Spray, los escondites y el distrito en el que está cada jugador.
	Mezcla Areas con Economy, Wanted y Cops, así que es de Game.

	  guarida      zona segura: ProximityPrompt para depositar (se mantiene Deposit.HoldSeconds).
               En el lobby, todo el lobby cuenta como casa (tienda, Ascensión y depósito)
	  payspray     quita las estrellas por Dinero
	  hide         escondite: lo gestiona Game/Hiding (aquí solo se declara la zona)
	  distrito     atributo District del jugador (id del nivel de Levels.json)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Telemetry = require(ServerScriptService.Server.Telemetry)
local Tuning = require(ReplicatedStorage.Shared.Tuning)
local Areas = require(ServerScriptService.Server.Modules.Areas)
local Cops = require(ServerScriptService.Server.Modules.Cops)
local Economy = require(ServerScriptService.Server.Modules.Economy)
local Progress = require(ServerScriptService.Server.Modules.Progress)
local Shop = require(ServerScriptService.Server.Modules.Shop)
local Stats = require(ServerScriptService.Server.Modules.Stats)
local Wanted = require(ServerScriptService.Server.Modules.Wanted)

local World = {}

-- Un jugador depositó su Botín en una Guarida (part) con el prompt: lo escucha Compinche para animarse.
World.deposited = Signal.new() :: Signal.Signal<Player, number, BasePart>

local function rootOf(player: Player): BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Dentro de la Guarida de un distrito o en cualquier punto del lobby (La Guarida).
function World.atHome(player: Player): boolean
	return Areas.inside(player, "guarida") ~= nil or Areas.inside(player, "lobby") ~= nil
end

-- Quién puede depositar: en casa (Guarida o lobby), o desde cualquier lugar con el pase del teléfono.
function World.canDeposit(player: Player): (boolean, string?)
	if Wanted.stars(player) > 0 or Wanted.state(player) ~= "clear" then
		return false, "wanted"
	end
	if not World.atHome(player) and not Shop.owns(player, "phone") then
		return false, "away"
	end
	return true, nil
end

function World.deposit(player: Player): (boolean, string?, number?)
	local ok, reason = World.canDeposit(player)
	if not ok then
		return false, reason
	end
	if Economy.loot(player) <= 0 then
		return false, "empty"
	end
	local amount = Economy.deposit(player)
	if amount <= 0 then
		return false, "data"
	end
	Stats.increment(player, "deposits", 1)
	Net.send(player, "notify", { kind = "deposit", amount = amount })
	return true, nil, amount
end

function World.spray(player: Player): (boolean, string?)
	local root = rootOf(player)
	if not root then
		return false, "dead"
	end
	local part = Areas.nearest("payspray", root.Position, Tuning.get("Spray.Range"))
	if not part then
		return false, "away"
	end
	local stars = Wanted.stars(player)
	if stars <= 0 then
		return false, "clean"
	end
	local cost = math.floor(Tuning.get("Spray.CostPerStar") * stars * (1 + Tuning.get("Spray.LevelFactor") * Progress.level(player)) + 0.5)
	if not Economy.spend(player, "dinero", cost, "Shop") then
		return false, "funds"
	end
	Cops.dismiss(player)
	Wanted.clear(player, "spray")
	Net.send(player, "notify", { kind = "spray", cost = cost, stars = stars })
	return true, nil
end

local function addPrompt(part: BasePart, action: string, object: string, hold: number, handler: (Player) -> ())
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(handler)
end

function World.start()
	for _, part in Areas.parts("guarida") do
		addPrompt(part, "Depositar Botín", "Guarida", Tuning.get("Deposit.HoldSeconds"), function(player)
			local ok, reason, amount = World.deposit(player)
			if not ok and reason ~= "empty" then
				Net.send(player, "notify", { kind = "error", code = reason })
			elseif ok and amount then
				World.deposited:Fire(player, amount, part)
			end
		end)
	end
	for _, part in Areas.parts("payspray") do
		addPrompt(part, "Quitar estrellas", "Pay'n'Spray", 0.5, function(player)
			local ok, reason = World.spray(player)
			if not ok then
				Net.send(player, "notify", { kind = "error", code = reason })
			end
		end)
	end

	Areas.entered:Connect(function(player, name, part)
		if name == "distrito" then
			local levelId = part:GetAttribute("LevelId")
			if player:GetAttribute("District") ~= levelId then
				player:SetAttribute("District", levelId)
				Telemetry.custom(player, "district_entered", nil, { district = tostring(levelId) })
			end
		end
	end)
end

return World

--[[
	Band · módulo core: las bandas co-op de hasta 8 jugadores. Es estado de la sesión:
	no se guarda. Un jugador crea una banda, invita a otros o la deja abierta, y quienes
	juegan juntos reciben un bono de Botín y XP por cada compañero activo y cercano.

	Los nombres de banda salen de una lista del juego (no hay texto libre del jugador, así
	que no hace falta filtrarlo ni guardarlo).

	Publica atributos del jugador:
	  BandId ("" si no tiene), BandName, BandColor (hexadecimal), BandSize, BandLeader,
	  BandOpen, BandMembers (UserIds separados por coma), BandBonus (aditivo).

	No sabe qué hace el bono ni el contagio de calor: Game y los puentes lo usan.

	API:
	  Band.init(options)                       { names, colors }
	  Band.start()
	  Band.create(player)                      -> (boolean, string?)
	  Band.invite(player, target)              -> (boolean, string?)     solo el jefe
	  Band.accept(player)                      -> (boolean, string?)     acepta la última invitación
	  Band.decline(player)
	  Band.join(player, bandId)                -> (boolean, string?)     solo bandas abiertas
	  Band.leave(player)
	  Band.kick(leader, target)                -> boolean
	  Band.setOpen(player, open)               -> boolean                solo el jefe
	  Band.setColor(player, index)             -> boolean                solo el jefe
	  Band.bandId(player)                      -> string?
	  Band.members(player)                     -> { Player }             incluye al jugador
	  Band.nearby(player, range)               -> { Player }             otros miembros a esa distancia
	  Band.bonus(player)                       -> number                 BonusPerMember × compañeros activos cerca
	  Band.touch(player)                       marca actividad
	  Band.listOpen()                          -> { { id, name, size, leader } }
	  Band.changed                             Signal (player)           cambió su banda o su bono
	  Band.inviteReceived                      Signal (target, from)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Shared.Signal)
local Tuning = require(ReplicatedStorage.Shared.Tuning)

export type Options = {
	names: { string },
	colors: { string }, -- hexadecimales #RRGGBB
}

type BandData = {
	id: string,
	name: string,
	colorIndex: number,
	leader: Player,
	members: { Player },
	open: boolean,
}

local Band = {}

Band.changed = Signal.new() :: Signal.Signal<Player>
Band.inviteReceived = Signal.new() :: Signal.Signal<Player, Player>

local names: { string } = { "Banda" }
local colors: { string } = { "#FF9F1C" }
local bands: { [string]: BandData } = {}
local playerBand: { [Player]: string } = {}
local invites: { [Player]: { from: Player, bandId: string, expires: number } } = {}
local lastInviteAt: { [Player]: { [Player]: number } } = {}
local lastActive: { [Player]: number } = {}
local lastPosition: { [Player]: Vector3 } = {}
local counter = 0
local random = Random.new()

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function bandOf(player: Player): BandData?
	local id = playerBand[player]
	return if id then bands[id] else nil
end

local function bonusOf(player: Player): number
	local data = bandOf(player)
	if not data then
		return 0
	end
	local root = rootOf(player)
	if not root then
		return 0
	end
	local now = os.clock()
	local count = 0
	for _, member in data.members do
		if member ~= player then
			local other = rootOf(member)
			if other
				and (other.Position - root.Position).Magnitude <= Tuning.get("Band.BonusRange")
				and now - (lastActive[member] or 0) <= Tuning.get("Band.ActiveWindowSeconds")
			then
				count += 1
			end
		end
	end
	return count * Tuning.get("Band.BonusPerMember")
end

local function publish(player: Player)
	local data = bandOf(player)
	if data then
		local ids = {}
		for _, member in data.members do
			table.insert(ids, tostring(member.UserId))
		end
		player:SetAttribute("BandId", data.id)
		player:SetAttribute("BandName", data.name)
		player:SetAttribute("BandColor", colors[data.colorIndex] or colors[1])
		player:SetAttribute("BandSize", #data.members)
		player:SetAttribute("BandLeader", data.leader == player)
		player:SetAttribute("BandOpen", data.open)
		player:SetAttribute("BandMembers", table.concat(ids, ","))
	else
		player:SetAttribute("BandId", "")
		player:SetAttribute("BandName", "")
		player:SetAttribute("BandSize", 0)
		player:SetAttribute("BandLeader", false)
		player:SetAttribute("BandOpen", false)
		player:SetAttribute("BandMembers", "")
	end
	player:SetAttribute("BandBonus", bonusOf(player))
	Band.changed:Fire(player)
end

local function publishAll(data: BandData)
	for _, member in data.members do
		publish(member)
	end
end

local function removeMember(player: Player)
	local data = bandOf(player)
	playerBand[player] = nil
	if not data then
		return
	end
	local index = table.find(data.members, player)
	if index then
		table.remove(data.members, index)
	end
	if #data.members == 0 then
		bands[data.id] = nil
	else
		if data.leader == player then
			data.leader = data.members[1]
		end
		publishAll(data)
	end
	if player.Parent then
		publish(player)
	end
end

local function addMember(player: Player, data: BandData)
	playerBand[player] = data.id
	table.insert(data.members, player)
	invites[player] = nil
	publishAll(data)
end

function Band.init(options: Options)
	names = options.names
	colors = options.colors
end

function Band.start()
	Players.PlayerAdded:Connect(function(player)
		publish(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		removeMember(player)
		invites[player] = nil
		lastInviteAt[player] = nil
		lastActive[player] = nil
		lastPosition[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		publish(player)
	end
	-- La actividad también se detecta por movimiento; el bono se refresca dos veces por segundo.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.5 then
			return
		end
		elapsed = 0
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if root then
				local previous = lastPosition[player]
				if previous and (root.Position - previous).Magnitude > 2 then
					lastActive[player] = os.clock()
				end
				lastPosition[player] = root.Position
			end
			if playerBand[player] then
				local bonus = bonusOf(player)
				if player:GetAttribute("BandBonus") ~= bonus then
					player:SetAttribute("BandBonus", bonus)
				end
			end
		end
	end)
end

function Band.touch(player: Player)
	lastActive[player] = os.clock()
end

function Band.bandId(player: Player): string?
	return playerBand[player]
end

function Band.members(player: Player): { Player }
	local data = bandOf(player)
	return if data then table.clone(data.members) else { player }
end

function Band.nearby(player: Player, range: number): { Player }
	local list = {}
	local data = bandOf(player)
	local root = rootOf(player)
	if not data or not root then
		return list
	end
	for _, member in data.members do
		if member ~= player then
			local other = rootOf(member)
			if other and (other.Position - root.Position).Magnitude <= range then
				table.insert(list, member)
			end
		end
	end
	return list
end

function Band.bonus(player: Player): number
	return bonusOf(player)
end

function Band.create(player: Player): (boolean, string?)
	if playerBand[player] then
		return false, "already"
	end
	counter += 1
	local data: BandData = {
		id = `band{counter}`,
		name = names[random:NextInteger(1, #names)],
		colorIndex = random:NextInteger(1, #colors),
		leader = player,
		members = {},
		open = false,
	}
	bands[data.id] = data
	addMember(player, data)
	return true, nil
end

function Band.invite(player: Player, target: Player): (boolean, string?)
	local data = bandOf(player)
	if not data then
		return false, "no_band"
	end
	if data.leader ~= player then
		return false, "not_leader"
	end
	if target == player or playerBand[target] then
		return false, "target_busy"
	end
	if #data.members >= Tuning.get("Band.MaxMembers") then
		return false, "full"
	end
	local now = os.clock()
	local history = lastInviteAt[player]
	if not history then
		history = {}
		lastInviteAt[player] = history
	end
	if history[target] and now - history[target] < Tuning.get("Band.InviteCooldownSeconds") then
		return false, "cooldown"
	end
	history[target] = now
	invites[target] = { from = player, bandId = data.id, expires = now + Tuning.get("Band.InviteExpireSeconds") }
	Band.inviteReceived:Fire(target, player)
	return true, nil
end

function Band.accept(player: Player): (boolean, string?)
	local invite = invites[player]
	if not invite or os.clock() > invite.expires then
		invites[player] = nil
		return false, "expired"
	end
	local data = bands[invite.bandId]
	if not data then
		invites[player] = nil
		return false, "gone"
	end
	if playerBand[player] then
		return false, "already"
	end
	if #data.members >= Tuning.get("Band.MaxMembers") then
		return false, "full"
	end
	addMember(player, data)
	return true, nil
end

function Band.decline(player: Player)
	invites[player] = nil
end

function Band.join(player: Player, bandId: string): (boolean, string?)
	local data = bands[bandId]
	if not data or not data.open then
		return false, "closed"
	end
	if playerBand[player] then
		return false, "already"
	end
	if #data.members >= Tuning.get("Band.MaxMembers") then
		return false, "full"
	end
	addMember(player, data)
	return true, nil
end

function Band.leave(player: Player)
	removeMember(player)
end

function Band.kick(leader: Player, target: Player): boolean
	local data = bandOf(leader)
	if not data or data.leader ~= leader or target == leader or playerBand[target] ~= data.id then
		return false
	end
	removeMember(target)
	return true
end

function Band.setOpen(player: Player, open: boolean): boolean
	local data = bandOf(player)
	if not data or data.leader ~= player then
		return false
	end
	data.open = open
	publishAll(data)
	return true
end

function Band.setColor(player: Player, index: number): boolean
	local data = bandOf(player)
	if not data or data.leader ~= player or not colors[index] then
		return false
	end
	data.colorIndex = index
	publishAll(data)
	return true
end

function Band.listOpen(): { { id: string, name: string, size: number, leader: string } }
	local list = {}
	for _, data in bands do
		if data.open and #data.members < Tuning.get("Band.MaxMembers") then
			table.insert(list, { id = data.id, name = data.name, size = #data.members, leader = data.leader.DisplayName })
		end
	end
	return list
end

return Band

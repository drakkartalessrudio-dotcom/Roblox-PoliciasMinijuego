--[[
	Band: la banda co-op de hasta 8. Crear una banda, invitar a otros jugadores del
	servidor, dejarla abierta, unirse a una abierta, rescatar y salir. Muestra el bono de
	banda que calcula el servidor.

	Estado del jugador: BandId, BandName, BandSize, BandLeader, BandOpen, BandMembers y
	BandBonus. Mensajes del servidor: `band_invite` y `band_list`. Envía la intención `band`
	con una acción (create, invite, accept, decline, join, leave, kick, open, list); el
	servidor valida quién es el jefe, el cupo y las invitaciones.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Tuning = require(Shared:WaitForChild("Tuning"))

local Band = {}

function Band.mount(Kit: any)
	local player = Players.LocalPlayer
	local modal = Kit.modal("Banda")
	local body = Kit.panel(modal.content)
	local invite = Kit.modal("Invitación a una banda")
	local inviteText = Kit.label({ text = "", kind = "body", parent = invite.content, size = UDim2.fromOffset(360, 56) })

	local openBands: { { id: string, name: string, size: number, leader: string } }? = nil

	local function clear()
		for _, child in body:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function act(action: string, extra: { [string]: any }?)
		local payload = { action = action } :: { [string]: any }
		if extra then
			for key, value in extra do
				payload[key] = value
			end
		end
		Net.send("band", payload)
	end

	local function render()
		clear()
		local bandId = player:GetAttribute("BandId")
		if type(bandId) ~= "string" or bandId == "" then
			Kit.label({ text = "Juega en banda: más Botín y XP, travesuras que solo se hacen entre varios y rescates entre compañeros.", kind = "body", parent = body, size = UDim2.fromOffset(460, 60) })
			Kit.button({
				text = "Crear banda",
				variant = "primary",
				parent = body,
				onActivated = function()
					act("create")
				end,
			})
			Kit.button({
				text = "Ver bandas abiertas",
				variant = "secondary",
				parent = body,
				onActivated = function()
					act("list")
				end,
			})
			if openBands then
				if #openBands == 0 then
					Kit.status(body, "empty", "No hay bandas abiertas ahora")
				end
				for _, band in openBands do
					Kit.button({
						text = `Unirme a {band.name} ({band.size}/{Tuning.get("Band.MaxMembers")}) · jefe {band.leader}`,
						variant = "secondary",
						parent = body,
						onActivated = function()
							act("join", { bandId = band.id })
						end,
					})
				end
			end
			return
		end

		local size = player:GetAttribute("BandSize") or 0
		local bonus = math.floor((player:GetAttribute("BandBonus") or 0) * 100 + 0.5)
		local isLeader = player:GetAttribute("BandLeader") == true
		Kit.label({ text = `{player:GetAttribute("BandName")} · {size}/{Tuning.get("Band.MaxMembers")}`, kind = "heading", parent = body, size = UDim2.fromOffset(460, 34) })
		Kit.label({
			text = `Bono ahora: +{bonus} % de Botín y XP (cada compañero activo a menos de {Tuning.get("Band.BonusRange")} studs suma +{math.floor(Tuning.get("Band.BonusPerMember") * 100)} %)`,
			kind = "body",
			color = "reward",
			parent = body,
			size = UDim2.fromOffset(460, 52),
		})

		local members = tostring(player:GetAttribute("BandMembers") or "")
		for idText in string.gmatch(members, "%d+") do
			local member = Players:GetPlayerByUserId(tonumber(idText) or 0)
			if member then
				local row = Kit.panel(body, Enum.FillDirection.Horizontal)
				Kit.label({ text = member.DisplayName .. (if member == player then " (tú)" else ""), kind = "label", parent = row, size = UDim2.fromOffset(250, 32) })
				if isLeader and member ~= player then
					Kit.button({
						text = "Expulsar",
						variant = "danger",
						parent = row,
						onActivated = function()
							act("kick", { userId = member.UserId })
						end,
					})
				end
			end
		end

		if isLeader then
			local open = player:GetAttribute("BandOpen") == true
			Kit.button({
				text = if open then "Cerrar la banda" else "Abrir la banda",
				variant = "secondary",
				parent = body,
				onActivated = function()
					act("open", { value = not open })
				end,
			})
			Kit.label({ text = "Invitar jugadores del servidor", kind = "label", parent = body, size = UDim2.fromOffset(460, 26) })
			local any = false
			for _, other in Players:GetPlayers() do
				local otherBand = other:GetAttribute("BandId")
				if other ~= player and (otherBand == nil or otherBand == "") then
					any = true
					Kit.button({
						text = `Invitar a {other.DisplayName}`,
						variant = "secondary",
						parent = body,
						onActivated = function()
							act("invite", { userId = other.UserId })
						end,
					})
				end
			end
			if not any then
				Kit.status(body, "empty", "No hay jugadores sin banda ahora")
			end
		end
		Kit.button({
			text = "Salir de la banda",
			variant = "danger",
			parent = body,
			onActivated = function()
				act("leave")
			end,
		})
	end

	Net.on("band_list", function(list)
		openBands = list
		render()
	end)
	Net.on("band_invite", function(data)
		inviteText.Text = `{data.fromName} te invita a su banda`
		invite:open()
		Kit.toast(`{data.fromName} te invita a su banda`, 5)
	end)
	Kit.button({
		text = "Aceptar",
		variant = "primary",
		parent = invite.content,
		onActivated = function()
			act("accept")
			invite:close()
		end,
	})
	Kit.button({
		text = "Rechazar",
		variant = "secondary",
		parent = invite.content,
		onActivated = function()
			act("decline")
			invite:close()
		end,
	})

	for _, attribute in { "BandId", "BandName", "BandSize", "BandLeader", "BandOpen", "BandMembers" } do
		player:GetAttributeChangedSignal(attribute):Connect(render)
	end
	Players.PlayerAdded:Connect(render)
	Players.PlayerRemoving:Connect(function()
		task.defer(render)
	end)
	render()

	Kit.button({
		text = "Banda",
		variant = "secondary",
		binding = { keyboard = Enum.KeyCode.G, gamepad = Enum.KeyCode.ButtonR1 },
		parent = Kit.slot("left"),
		onActivated = function()
			render()
			modal:open()
		end,
	})
end

return Band

--[[
	Minigames: los minijuegos de las travesuras. El servidor manda `mischief_start` con el
	tipo de juego y su duración; esta pantalla lo juega con un dedo (o el ratón) y avisa el
	resultado con `mischief_submit`. El servidor valida distancia, tiempo y enfriamiento:
	el cliente nunca decide el pago.

	Tipos (game.type):
	  sequence   tocar los números en orden (graffiti, sombrillas, mural gigante)
	  hold       mantener pulsado sin soltar (hidrante, caja fuerte)
	  mash       tocar rápido muchas veces (castillo de arena, cajero)
	  timing     tocar cuando la marca pasa por la zona (carrito, bocinas, estatua, sinfonía)
	  memory     repetir una secuencia de símbolos (semáforos, contenedor)
	  timbrazo   lo resuelve el servidor: solo se muestra el aviso de salir corriendo

	Si el jugador termina muy rápido, espera hasta el mínimo que exige el servidor antes de
	enviar el resultado, para que una buena jugada no cuente como "demasiado rápida".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Style = require(Shared:WaitForChild("Style"))
local Tuning = require(Shared:WaitForChild("Tuning"))

local Minigames = {}

local AREA = Vector2.new(320, 190)
local SYMBOLS = { "🔺", "🟦", "🟡", "🟢" }

type Spec = {
	id: string,
	name: string,
	game: { type: string, count: number?, taps: number?, seconds: number? },
	duration: number,
	party: number,
	coop: boolean,
}

function Minigames.mount(Kit: any)
	local layer = Kit.layer("menu")

	local window = Kit.panel(layer)
	window.Name = "Minijuego"
	window.Visible = false
	window.AnchorPoint = Vector2.new(0.5, 0)
	window.Position = UDim2.new(0.5, 0, 0, 90)
	local title = Kit.label({ text = "", kind = "heading", parent = window, size = UDim2.fromOffset(AREA.X, 34) })
	local timerBack = Instance.new("Frame")
	timerBack.Name = "Tiempo"
	timerBack.BackgroundColor3 = Style.color("panelAlt")
	timerBack.BorderSizePixel = 0
	timerBack.Size = UDim2.fromOffset(AREA.X, 8)
	timerBack.Parent = window
	local timerFill = Instance.new("Frame")
	timerFill.Name = "Fill"
	timerFill.BackgroundColor3 = Style.color("accent")
	timerFill.BorderSizePixel = 0
	timerFill.Size = UDim2.fromScale(1, 1)
	timerFill.Parent = timerBack
	local info = Kit.label({ text = "", kind = "label", color = "textMuted", parent = window, size = UDim2.fromOffset(AREA.X, 22) })
	local area = Instance.new("Frame")
	area.Name = "Area"
	area.BackgroundColor3 = Style.color("panelAlt")
	area.BorderSizePixel = 0
	area.ClipsDescendants = true
	area.Size = UDim2.fromOffset(AREA.X, AREA.Y)
	area.Parent = window
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = area
	Kit.button({
		text = "Cancelar",
		variant = "secondary",
		parent = window,
		onActivated = function()
			Net.send("mischief_cancel")
			window.Visible = false
		end,
	})

	local runId = 0 -- invalida un minijuego anterior cuando empieza otro

	local function clearArea()
		for _, child in area:GetChildren() do
			if not child:IsA("UICorner") then
				child:Destroy()
			end
		end
	end

	-- Cierra el minijuego: espera el mínimo del servidor si ganó y envía el resultado.
	local function finish(spec: Spec, token: number, success: boolean, startedAt: number)
		if token ~= runId then
			return
		end
		runId += 1
		clearArea()
		info.Text = if success then "¡Listo!" else "Fallaste"
		if success then
			local minimum = (Tuning.get("Mischief.MinDurationRatio") + 0.06) * spec.duration
			local wait = minimum - (os.clock() - startedAt)
			if wait > 0 then
				task.wait(wait)
			end
		end
		Net.send("mischief_submit", { id = spec.id, success = success })
		task.delay(0.6, function()
			if token + 1 == runId then
				window.Visible = false
			end
		end)
	end

	local function games(spec: Spec, token: number, done: (boolean) -> ())
		local kind = spec.game.type
		if kind == "sequence" then
			local count = spec.game.count or 6
			local slots = {}
			for slot = 0, 14 do
				table.insert(slots, slot)
			end
			for index = #slots, 2, -1 do
				local pick = math.random(1, index)
				slots[index], slots[pick] = slots[pick], slots[index]
			end
			local nextNumber = 1
			info.Text = "Toca los números en orden"
			for number = 1, count do
				local slot = slots[number]
				local x = (slot % 5) * (AREA.X / 5) + (AREA.X / 10) - 26 + math.random(-6, 6)
				local y = (slot // 5) * (AREA.Y / 3) + (AREA.Y / 6) - 26 + math.random(-6, 6)
				local dot
				dot = Kit.button({
					text = tostring(number),
					variant = "primary",
					parent = area,
					onActivated = function()
						if number == nextNumber then
							nextNumber += 1
							dot:Destroy()
							if nextNumber > count then
								done(true)
							end
						end
					end,
				})
				dot.Size = UDim2.fromOffset(52, 52)
				dot.Position = UDim2.fromOffset(x, y)
			end
		elseif kind == "mash" then
			local taps = spec.game.taps or 14
			local count = 0
			info.Text = `Toca rápido: 0/{taps}`
			local button = Kit.button({
				text = "¡Toca!",
				variant = "primary",
				parent = area,
				onActivated = function()
					count += 1
					info.Text = `Toca rápido: {count}/{taps}`
					if count >= taps then
						done(true)
					end
				end,
			})
			button.Size = UDim2.fromOffset(200, 90)
			button.Position = UDim2.fromOffset((AREA.X - 200) / 2, (AREA.Y - 90) / 2)
		elseif kind == "hold" then
			local need = (spec.game.seconds or 8) * 0.75
			local held = 0
			local holding = false
			info.Text = "Mantén pulsado sin soltar"
			local button = Kit.button({ text = "Mantén", variant = "primary", parent = area, onActivated = function() end })
			button.Size = UDim2.fromOffset(200, 90)
			button.Position = UDim2.fromOffset((AREA.X - 200) / 2, (AREA.Y - 90) / 2)
			local function isPress(input: InputObject): boolean
				return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
			end
			button.InputBegan:Connect(function(input)
				if isPress(input) then
					holding = true
				end
			end)
			button.InputEnded:Connect(function(input)
				if isPress(input) then
					holding = false
					held = 0
				end
			end)
			local connection
			connection = RunService.Heartbeat:Connect(function(dt)
				if token ~= runId then
					connection:Disconnect()
					return
				end
				if holding then
					held += dt
					info.Text = `Mantén… {math.floor(held / need * 100)}%`
					if held >= need then
						connection:Disconnect()
						done(true)
					end
				end
			end)
		elseif kind == "timing" then
			local beats = spec.game.count or 3
			local hits, presses = 0, 0
			local zoneWidth = 64
			local trackWidth = AREA.X - 20
			local track = Instance.new("Frame")
			track.BackgroundColor3 = Style.color("panel")
			track.BorderSizePixel = 0
			track.Position = UDim2.fromOffset(10, 40)
			track.Size = UDim2.fromOffset(trackWidth, 34)
			track.Parent = area
			local zone = Instance.new("Frame")
			zone.BackgroundColor3 = Style.color("goal")
			zone.BorderSizePixel = 0
			zone.Size = UDim2.fromOffset(zoneWidth, 34)
			zone.Parent = track
			local marker = Instance.new("Frame")
			marker.BackgroundColor3 = Style.color("text")
			marker.BorderSizePixel = 0
			marker.Size = UDim2.fromOffset(8, 34)
			marker.Parent = track
			local function placeZone()
				zone.Position = UDim2.fromOffset(math.random(10, trackWidth - zoneWidth - 10), 0)
			end
			placeZone()
			local speed = 1.15 + 0.12 * beats / 3
			local started = os.clock()
			local connection
			connection = RunService.Heartbeat:Connect(function()
				if token ~= runId then
					connection:Disconnect()
					return
				end
				local phase = ((os.clock() - started) * speed) % 2
				local alpha = if phase < 1 then phase else 2 - phase
				marker.Position = UDim2.fromOffset(alpha * (trackWidth - 8), 0)
			end)
			info.Text = `Toca cuando la marca pase por la zona: 0/{beats}`
			local button = Kit.button({
				text = "¡Ya!",
				variant = "primary",
				parent = area,
				onActivated = function()
					local center = marker.Position.X.Offset + 4
					local left = zone.Position.X.Offset
					if center >= left and center <= left + zoneWidth then
						hits += 1
					end
					presses += 1
					info.Text = `Toca cuando la marca pase por la zona: {presses}/{beats}`
					placeZone()
					if presses >= beats then
						connection:Disconnect()
						done(hits >= math.ceil(beats * 0.6))
					end
				end,
			})
			button.Size = UDim2.fromOffset(160, 64)
			button.Position = UDim2.fromOffset((AREA.X - 160) / 2, 100)
		elseif kind == "memory" then
			local length = spec.game.count or 4
			local order = {}
			for index = 1, length do
				order[index] = math.random(1, #SYMBOLS)
			end
			local buttons = {}
			local showing = true
			local progress = 0
			info.Text = "Mira la secuencia…"
			local function flash(button: TextButton)
				local original = button.BackgroundColor3
				button.BackgroundColor3 = Style.color("interactive")
				task.wait(0.35)
				button.BackgroundColor3 = original
				task.wait(0.15)
			end
			for index, symbol in SYMBOLS do
				local button = Kit.button({
					text = symbol,
					variant = "secondary",
					parent = area,
					onActivated = function()
						if showing or token ~= runId then
							return
						end
						if order[progress + 1] == index then
							progress += 1
							if progress >= length then
								done(true)
							end
						else
							done(false)
						end
					end,
				})
				button.Size = UDim2.fromOffset(64, 64)
				button.Position = UDim2.fromOffset(18 + (index - 1) * 76, 62)
				buttons[index] = button
			end
			task.spawn(function()
				task.wait(0.4)
				for _, index in order do
					if token ~= runId then
						return
					end
					flash(buttons[index])
				end
				showing = false
				info.Text = "Ahora repítela"
			end)
		else
			done(false)
		end
	end

	local function play(spec: Spec)
		runId += 1
		local token = runId
		clearArea()
		window.Visible = true
		title.Text = if spec.coop then `{spec.name} · Banda x{spec.party}` else spec.name
		local startedAt = os.clock()
		local finished = false
		local function done(success: boolean)
			if finished then
				return
			end
			finished = true
			finish(spec, token, success, startedAt)
		end
		games(spec, token, done)
		task.spawn(function()
			while token == runId and not finished do
				local left = spec.duration - (os.clock() - startedAt)
				timerFill.Size = UDim2.fromScale(math.clamp(left / spec.duration, 0, 1), 1)
				if left <= 0 then
					done(false)
					return
				end
				task.wait(0.05)
			end
		end)
	end

	Net.on("mischief_start", function(spec: any)
		if type(spec) ~= "table" or type(spec.game) ~= "table" then
			return
		end
		if spec.game.type == "timbrazo" then
			Kit.toast(`¡Corre! Aléjate {Tuning.get("Mischief.TimbrazoDistance")} studs del timbre`, Tuning.get("Mischief.TimbrazoSeconds"))
			return
		end
		play(spec)
	end)

	-- Arrestado o sin sesión: el minijuego se cierra (el servidor ya canceló la travesura).
	Net.on("notify", function(data)
		if type(data) == "table" and (data.kind == "arrested" or data.kind == "mischief_failed") then
			runId += 1
			window.Visible = false
		end
	end)
end

return Minigames

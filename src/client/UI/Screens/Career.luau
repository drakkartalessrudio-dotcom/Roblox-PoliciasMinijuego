--[[
	Career: la carrera a largo plazo. Pestañas: Misiones (diarias, cartel semanal, racha y
	alijo de la Guarida) y Ascensión (prestigio, bono y perks de Cerebros).

	Solo muestra el estado del servidor (Quest<i>…, QuestStreak, Weekly…, Level,
	AscensionCount, AscensionBonus, AscensionFee, Perk_<id>, Dinero, Cerebros) y envía
	intenciones (`claim_quest`, `claim_weekly`, `claim_stash`, `ascend`, `buy_perk`). Ascender
	pide una segunda pulsación porque reinicia el nivel, el Dinero y las mejoras.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Net = require(Shared:WaitForChild("Net"))
local Tuning = require(Shared:WaitForChild("Tuning"))
local Format = require(script.Parent.Parent:WaitForChild("Format"))

local Career = {}

local CONFIRM_SECONDS = 4

function Career.mount(Kit: any)
	local player = Players.LocalPlayer
	local modal = Kit.modal("Carrera")
	local tabs = Kit.tabs(modal.content, { "Misiones", "Ascensión" })

	local function number(attribute: string): number
		local value = player:GetAttribute(attribute)
		return if type(value) == "number" then value else 0
	end

	local updates: { () -> () } = {}

	-- Misiones.
	local missions = tabs.pages["Misiones"]
	local streakLabel = Kit.label({ text = "", kind = "label", color = "reward", parent = missions, size = UDim2.fromOffset(520, 26) })
	Kit.button({
		text = "Cobrar alijo",
		variant = "secondary",
		parent = missions,
		onActivated = function()
			Net.send("claim_stash")
		end,
	})
	Kit.label({ text = "El alijo se acumula mientras no estás (con tope) y se cobra en una Guarida", kind = "body", color = "textMuted", parent = missions, size = UDim2.fromOffset(520, 40) })

	local function questRow(titleText: () -> string, progress: () -> (number, number, boolean), claim: () -> ())
		local row = Kit.panel(missions)
		local title = Kit.label({ text = "", kind = "label", parent = row, size = UDim2.fromOffset(500, 26) })
		local detail = Kit.label({ text = "", kind = "number", color = "textMuted", parent = row, size = UDim2.fromOffset(500, 24) })
		local button = Kit.button({ text = "Cobrar", variant = "primary", parent = row, onActivated = claim })
		table.insert(updates, function()
			local have, goal, claimed = progress()
			title.Text = titleText()
			detail.Text = if claimed then "Cobrada" else `{math.min(have, goal)}/{goal}`
			button.Visible = not claimed and goal > 0 and have >= goal
			row.Visible = title.Text ~= ""
		end)
	end

	for index = 1, Tuning.get("Daily.QuestCount") do
		questRow(function()
			local id = player:GetAttribute(`Quest{index}Id`)
			local quest = if type(id) == "string" then Catalog.dailyById[id] else nil
			return if quest then quest.text else ""
		end, function()
			return number(`Quest{index}Progress`), number(`Quest{index}Goal`), player:GetAttribute(`Quest{index}Claimed`) == true
		end, function()
			local id = player:GetAttribute(`Quest{index}Id`)
			if type(id) == "string" then
				Net.send("claim_quest", { id = id })
			end
		end)
	end
	questRow(function()
		return `Se Busca: {Catalog.weeklyQuest.text}`
	end, function()
		return number("WeeklyProgress"), number("WeeklyGoal"), player:GetAttribute("WeeklyClaimed") == true
	end, function()
		Net.send("claim_weekly")
	end)

	table.insert(updates, function()
		local streak = number("QuestStreak")
		local bonus = math.min(Tuning.get("Daily.StreakMaxBonus"), streak * Tuning.get("Daily.StreakStep"))
		streakLabel.Text = `Racha: {streak} {if streak == 1 then "día" else "días"} (+{math.floor(bonus * 100)} % de recompensa). Faltar un día no la pierde.`
	end)

	-- Ascensión.
	local ascension = tabs.pages["Ascensión"]
	local summary = Kit.label({ text = "", kind = "body", parent = ascension, size = UDim2.fromOffset(520, 96) })
	local armedAt = 0
	local ascendButton
	ascendButton = Kit.button({
		text = "Ascender",
		variant = "danger",
		parent = ascension,
		onActivated = function()
			if os.clock() - armedAt <= CONFIRM_SECONDS then
				armedAt = 0
				Net.send("ascend")
			else
				armedAt = os.clock()
				ascendButton.Text = "¿Seguro? Reinicia nivel, Dinero y mejoras"
				task.delay(CONFIRM_SECONDS, function()
					if os.clock() - armedAt >= CONFIRM_SECONDS then
						ascendButton.Text = "Ascender"
					end
				end)
			end
		end,
	})
	table.insert(updates, function()
		local level = number("Level")
		local maxLevel = Tuning.get("Ascension.MinLevel")
		local count = number("AscensionCount")
		local bonus = math.floor(number("AscensionBonus") * 100 + 0.5)
		if count >= Tuning.get("Ascension.Max") then
			summary.Text = `Ascensiones: {count}/{Tuning.get("Ascension.Max")} · Bono +{bonus} % de XP y Dinero. ¡Llegaste al máximo!`
			ascendButton.Visible = false
		else
			ascendButton.Visible = true
			summary.Text = `Ascensiones: {count}/{Tuning.get("Ascension.Max")} · Bono actual +{bonus} %\nNivel {level}/{maxLevel} · Cuota {Format.money(number("AscensionFee"))}\nSe hace en una Guarida, sin estrellas. Ganas Cerebros y un bono permanente.`
		end
	end)

	Kit.label({ text = "Perks (se pagan con Cerebros y no se reinician)", kind = "label", parent = ascension, size = UDim2.fromOffset(520, 26) })
	local costs = Tuning.get("Perks.CostByLevel")
	for _, perk in Catalog.perks do
		local row = Kit.panel(ascension)
		local title = Kit.label({ text = "", kind = "label", parent = row, size = UDim2.fromOffset(500, 26) })
		Kit.label({ text = perk.description, kind = "body", color = "textMuted", parent = row, size = UDim2.fromOffset(500, 28) })
		local button = Kit.button({
			text = "Comprar",
			variant = "primary",
			parent = row,
			onActivated = function()
				Net.send("buy_perk", { id = perk.id })
			end,
		})
		table.insert(updates, function()
			local level = number(`Perk_{perk.id}`)
			title.Text = `{perk.name} · nivel {level}/{#costs}`
			button.Visible = level < #costs
			button.Text = `Comprar ({costs[level + 1] or 0} 🧠)`
			button.BackgroundTransparency = if number("Cerebros") >= (costs[level + 1] or math.huge) then 0 else 0.55
		end)
	end

	local dirty = false
	local function refresh()
		dirty = false
		for _, update in updates do
			update()
		end
	end
	player.AttributeChanged:Connect(function()
		if not dirty then
			dirty = true
			task.defer(refresh)
		end
	end)
	refresh()

	Kit.button({
		text = "Carrera",
		variant = "secondary",
		binding = { keyboard = Enum.KeyCode.J, gamepad = Enum.KeyCode.ButtonL1 },
		parent = Kit.slot("left"),
		onActivated = function()
			refresh()
			modal:open()
		end,
	})
end

return Career

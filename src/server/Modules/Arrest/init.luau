--[[
	Arrest · módulo core: lo que pasa entre que un policía agarra al jugador y que
	reaparece. El arrestado queda en la Camioneta (inmóvil) durante una ventana; un
	compañero de banda que llegue a tiempo y la toque lo libera. Si nadie llega, se
	cumple el arresto. Es estado de sesión.

	No sabe de Botín ni de Guaridas: publica `resolved` con quién lo rescató (o nadie) y
	Game aplica la pérdida y lo hace reaparecer.

	Publica atributos del jugador: Arrested (booleano) y ArrestEndsAt (hora del servidor).

	API:
	  Arrest.init(options)                  { canRescue(rescuer, victim) -> boolean }
	  Arrest.begin(player, position, window)  -> boolean  empieza el arresto (false si ya lo está)
	  Arrest.isHeld(player)                 -> boolean
	  Arrest.release(player)                libera sin pasar por `resolved` (salida del juego)
	  Arrest.resolved                       Signal (player, rescuedBy?)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Shared.Signal)
local Style = require(ReplicatedStorage.Shared.Style)
local Tuning = require(ReplicatedStorage.Shared.Tuning)

export type Options = {
	canRescue: (rescuer: Player, victim: Player) -> boolean,
}

type Hold = {
	van: Part,
	token: number,
	savedSpeed: number,
}

local Arrest = {}

Arrest.resolved = Signal.new() :: Signal.Signal<Player, Player?>

local options: Options? = nil
local holds: { [Player]: Hold } = {}
local counter = 0

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function buildVan(position: Vector3): Part
	local van = Instance.new("Part")
	van.Name = "Camioneta"
	van.Size = Vector3.new(8, 5, 14)
	van.Anchored = true
	van.CanCollide = false
	van.Color = Color3.new(1, 1, 1)
	van.Material = Enum.Material.SmoothPlastic
	van.CFrame = CFrame.new(position + Vector3.new(0, 2.5, 0))
	local bar = Instance.new("Part")
	bar.Name = "Sirena"
	bar.Size = Vector3.new(6, 0.8, 1.5)
	bar.Anchored = true
	bar.CanCollide = false
	bar.Material = Enum.Material.Neon
	bar.Color = Style.color("hazard")
	bar.CFrame = van.CFrame * CFrame.new(0, 2.9, -3)
	bar.Parent = van
	van.Parent = Workspace
	return van
end

local function setFrozen(player: Player, frozen: boolean, saved: number?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(player)
	if humanoid then
		if frozen then
			humanoid.WalkSpeed = 0
			humanoid.JumpHeight = 0
		end
	end
	if root then
		root.Anchored = frozen
	end
end

local function finish(player: Player, rescuedBy: Player?)
	local hold = holds[player]
	if not hold then
		return
	end
	holds[player] = nil
	hold.van:Destroy()
	setFrozen(player, false)
	player:SetAttribute("Arrested", false)
	player:SetAttribute("ArrestEndsAt", 0)
	Arrest.resolved:Fire(player, rescuedBy)
end

function Arrest.init(opts: Options)
	options = opts
end

function Arrest.start()
	Players.PlayerRemoving:Connect(function(player)
		Arrest.release(player)
	end)
end

function Arrest.isHeld(player: Player): boolean
	return holds[player] ~= nil
end

function Arrest.begin(player: Player, position: Vector3, window: number): boolean
	assert(options)
	if holds[player] then
		return false
	end
	counter += 1
	local van = buildVan(position)
	local token = counter
	holds[player] = { van = van, token = token, savedSpeed = 0 }
	setFrozen(player, true)
	player:SetAttribute("Arrested", true)
	player:SetAttribute("ArrestEndsAt", Workspace:GetServerTimeNow() + window)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Rescatar"
	prompt.ObjectText = `a {player.DisplayName}`
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = Tuning.get("Arrest.RescueRange")
	prompt.RequiresLineOfSight = false
	prompt.Parent = van
	prompt.Triggered:Connect(function(rescuer: Player)
		local hold = holds[player]
		if hold and hold.token == token and rescuer ~= player and options and options.canRescue(rescuer, player) then
			finish(player, rescuer)
		end
	end)
	task.delay(window, function()
		local hold = holds[player]
		if hold and hold.token == token then
			finish(player, nil)
		end
	end)
	return true
end

function Arrest.release(player: Player)
	local hold = holds[player]
	if hold then
		holds[player] = nil
		hold.van:Destroy()
		if player.Parent then
			setFrozen(player, false)
			player:SetAttribute("Arrested", false)
		end
	end
end

return Arrest

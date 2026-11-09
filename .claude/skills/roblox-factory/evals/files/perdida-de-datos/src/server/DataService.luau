-- Perfiles de los jugadores: monedas y pico.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local store = DataStoreService:GetDataStore("Minas")

local DataService = {}

local DEFAULTS = { coins = 0, pickaxe = "wood" }
local profiles: { [Player]: { coins: number, pickaxe: string } } = {}

function DataService.get(player: Player)
	return profiles[player]
end

local function load(player: Player)
	local ok, data = pcall(function()
		return store:GetAsync("Player_" .. player.UserId)
	end)
	if not ok or not data then
		-- Si la carga falla, el jugador empieza de cero.
		data = table.clone(DEFAULTS)
	end
	profiles[player] = data
	player:SetAttribute("Coins", data.coins)
end

local function save(player: Player)
	local data = profiles[player]
	if data then
		pcall(function()
			store:SetAsync("Player_" .. player.UserId, data)
		end)
	end
	profiles[player] = nil
end

function DataService.start()
	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(save)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
end

return DataService

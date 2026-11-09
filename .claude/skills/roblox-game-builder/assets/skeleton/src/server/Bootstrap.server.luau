--[[
	Bootstrap: única entrada del servidor. Primero prepara el núcleo (mundo, datos)
	y después llama a Game, que arma los módulos del juego. No requiere módulos ni
	puentes directamente: la composición es de Game.
]]

local Game = require(script.Parent.Game)

Game.start()

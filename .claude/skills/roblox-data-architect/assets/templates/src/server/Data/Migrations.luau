--!strict
--[[
	Migrations · funciones de las operaciones "custom" de DataSchema.json.
	Dueño: roblox-data-architect. Empieza vacío: agrega una función por cada operación
	custom, con el mismo nombre.

	Cada función recibe las secciones del perfil que se está migrando y las cambia en el
	lugar. Después, el servicio completa los valores por defecto y descarta lo que el
	esquema no conoce. Las operaciones move, add, set y remove no van aquí: las aplica
	Profile.

	  function Migrations.flagsFromBooleans(sections, info)
	      -- info.from y info.to son las versiones
	  end
]]

type Sections = { [string]: any }
type Migration = (sections: Sections, info: { from: number, to: number }) -> ()

local Migrations: { [string]: Migration } = {}

return Migrations

--!strict
--[[
	Migrations de Valle de Gremios: las operaciones "custom" de DataSchema.json.
	Va en src/server/Data/Migrations.luau. Cada función recibe las secciones del perfil
	que se está migrando y las cambia en el lugar; después el servicio completa los
	valores por defecto y descarta lo que el esquema no conoce.
]]

type Sections = { [string]: any }
type Migration = (sections: Sections, info: { from: number, to: number }) -> ()

local Migrations: { [string]: Migration } = {}

local FLAGS = {
	tookFirstMission = "first_mission",
	tookSecondMission = "second_mission",
	tookThirdMission = "third_mission",
}

-- 1 → 2: cada booleano de onboarding en true pasa a una bandera con la fecha de la última entrada.
function Migrations.flagsFromBooleans(sections: Sections, _info)
	local onboarding = sections.onboarding or {}
	local at = if sections.meta and type(sections.meta.lastJoinAt) == "number" then sections.meta.lastJoinAt else 0
	local flags = {}
	for field, flag in FLAGS do
		if onboarding[field] == true then
			flags[flag] = at
		end
	end
	sections.onboarding = { flags = flags }
end

return Migrations

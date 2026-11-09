--!strict
--[[
	VehicleModelPlan · lógica pura (sin Instances) para armar y manejar los autos del manifest v2
	(skills/roblox-vehicle-modeler/references/manifest-format.md). Se prueba con Lune.

	El manifest ya viene en el marco de Roblox: +X derecha, +Y arriba, +Z atrás (la trompa apunta a -Z), en studs,
	con el origen en el piso bajo el centro del auto. Por eso aquí no hay giros ni permutaciones de ejes: un punto
	del manifest es un punto del modelo, y el chasis cumple el contrato de VehicleRig (frente = -Z, derecha = +X).
]]

export type Vec = { number }

export type PartInfo = {
	kind: string,
	material: string,
	color: Vec,
	transparency: number,
	center: Vec,
	size: Vec,
	tris: number,
}

export type Wheel = { hub: Vec, radius: number, width: number, steer: boolean, drive: boolean }

export type Rig = {
	wheels: { [string]: Wheel },
	wheelRadius: number,
	seat: { position: Vec, size: Vec, side: string },
	collision: { center: Vec, size: Vec, fidelity: string }?,
	groundClearance: number?,
	trackWidth: number?,
	wheelbase: number?,
}

export type Entry = {
	schema: number,
	asset: string,
	tier: number?,
	bodyType: string,
	tris: { total: number, budget: number? },
	parts: { [string]: PartInfo },
	sockets: { [string]: Vec },
	rig: Rig,
}

export type Op = {
	name: string,
	kind: string,
	material: string,
	color: Vec,
	transparency: number,
	center: Vec,
	size: Vec,
}

local Plan = {}

Plan.SCHEMA = 2
Plan.WHEEL_TAGS = { "FL", "FR", "RL", "RR" }

Plan.REQUIRED_PARTS = {
	"Chassis",
	"Windows",
	"Tire_FL",
	"Tire_FR",
	"Tire_RL",
	"Tire_RR",
	"Rim_FL",
	"Rim_FR",
	"Rim_RL",
	"Rim_RR",
}

-- Sockets obligatorios (sección 3.1 de la guía de arte).
Plan.REQUIRED_SOCKETS = {
	"Socket_Spoiler",
	"Socket_Wheel_FL",
	"Socket_Wheel_FR",
	"Socket_Wheel_RL",
	"Socket_Wheel_RR",
	"Socket_Exhaust",
	"Socket_FrontBumper",
	"Socket_RearBumper",
	"Socket_RoofExtra",
}

-- "Tire_FL" -> "Tire", "Chassis" -> "Chassis"
function Plan.kindOf(partName: string): string
	return (string.match(partName, "^(%a+)_") or partName) :: string
end

local function minus(a: Vec, b: Vec): Vec
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end

local function chassisCenter(entry: Entry): Vec
	return entry.parts.Chassis.center
end

-- Operaciones ordenadas por nombre: la pieza, su material y dónde va (marco del modelo, centro del chasis incluido).
function Plan.operations(entry: Entry): { Op }
	local ops: { Op } = {}
	for name, info in entry.parts do
		table.insert(ops, {
			name = name,
			kind = info.kind or Plan.kindOf(name),
			material = info.material,
			color = info.color,
			transparency = info.transparency,
			center = info.center,
			size = info.size,
		})
	end
	table.sort(ops, function(a, b)
		return a.name < b.name
	end)
	return ops
end

-- Posición de un socket relativa al centro del Chassis (para el Attachment hijo del Chassis).
function Plan.socketOffset(entry: Entry, socketName: string): Vec?
	local socket = entry.sockets[socketName]
	if not socket or not entry.parts.Chassis then
		return nil
	end
	return minus(socket, chassisCenter(entry))
end

-- Compresión estática de un resorte de frecuencia `frequency` (Hz) bajo la gravedad `gravity` (studs/s²).
function Plan.staticCompression(frequency: number, gravity: number): number
	local omega = 2 * math.pi * frequency
	return gravity / (omega * omega)
end

-- Cuánto debe subir el origen del rayo sobre el buje para que, en reposo, el neumático toque el piso
-- (largo libre del resorte menos su compresión estática).
function Plan.restSpring(suspensionLength: number, frequency: number, gravity: number): number
	return math.max(0, suspensionLength - Plan.staticCompression(frequency, gravity))
end

-- Dónde va el Socket_Wheel_* que usa el manejo como origen del rayo: el buje subido `restSpring`.
function Plan.raySocketOffset(entry: Entry, tag: string, restSpring: number): Vec?
	local wheel = entry.rig.wheels[tag]
	if not wheel or not entry.parts.Chassis then
		return nil
	end
	local offset = minus(wheel.hub, chassisCenter(entry))
	return { offset[1], offset[2] + restSpring, offset[3] }
end

-- Posición del buje de una rueda relativa al centro del Chassis (para el WheelWeld).
function Plan.wheelOffset(entry: Entry, tag: string): Vec?
	local wheel = entry.rig.wheels[tag]
	if not wheel or not entry.parts.Chassis then
		return nil
	end
	return minus(wheel.hub, chassisCenter(entry))
end

-- Posición del asiento del conductor relativa al centro del Chassis.
function Plan.seatOffset(entry: Entry): Vec
	return minus(entry.rig.seat.position, chassisCenter(entry))
end

-- Qué pieza se recolorea con la pintura del cuerpo ("body"), con las llantas ("rim") o ninguna.
function Plan.paintTarget(partName: string): string?
	local kind = Plan.kindOf(partName)
	if kind == "Chassis" or kind == "Bed" then
		return "body"
	elseif kind == "Rim" then
		return "rim"
	end
	return nil
end

-- Cociente entre el tamaño importado de una pieza y el del manifest, o nil si los tamaños no son comparables.
-- Un valor distinto de 1 indica que Studio importó a otra escala (el ensamblador lo corrige con Size).
function Plan.scaleRatio(importedSize: Vec, manifestSize: Vec): number?
	local ratios = {}
	for axis = 1, 3 do
		if manifestSize[axis] > 1e-6 and importedSize[axis] > 1e-6 then
			table.insert(ratios, importedSize[axis] / manifestSize[axis])
		end
	end
	if #ratios == 0 then
		return nil
	end
	table.sort(ratios)
	return ratios[(#ratios + 1) // 2]
end

-- Valida que el manifest sirve para armar y manejar el auto: devuelve la lista de problemas (vacía = ok).
function Plan.validate(entry: Entry): { string }
	local problems: { string } = {}
	if entry.schema ~= Plan.SCHEMA then
		table.insert(problems, `schema {tostring(entry.schema)}, se esperaba {Plan.SCHEMA}`)
	end
	for _, name in Plan.REQUIRED_PARTS do
		if not entry.parts[name] then
			table.insert(problems, `falta la pieza {name}`)
		end
	end
	for _, name in Plan.REQUIRED_SOCKETS do
		if not entry.sockets[name] then
			table.insert(problems, `falta el socket {name}`)
		end
	end
	for _, tag in Plan.WHEEL_TAGS do
		if not entry.rig.wheels[tag] then
			table.insert(problems, `falta la rueda {tag} en rig.wheels`)
		end
	end
	if not entry.rig.seat then
		table.insert(problems, "falta rig.seat")
	end
	local front, rear = entry.sockets.Socket_FrontBumper, entry.sockets.Socket_RearBumper
	if front and rear and not (front[3] < rear[3]) then
		table.insert(problems, "la trompa no apunta a -Z: Socket_FrontBumper debe tener menor Z que Socket_RearBumper")
	end
	return problems
end

return Plan

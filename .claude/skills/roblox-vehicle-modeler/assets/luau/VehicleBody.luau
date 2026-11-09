--!strict
--[[
	VehicleBody · vuelve conducible un auto ensamblado con VehicleAssembler, cumpliendo el contrato de VehicleRig
	(Chassis con Socket_Wheel_*, DriverSeat y WheelWeld_* opcionales). Es contenido del juego, no del core de manejo:
	el manejo no sabe de mallas ni de manifests.

	  local car = VehicleBody.build(imported, "T1_Sedan", { suspensionLength = 1.2, suspensionFrequency = 3 })
	  car:PivotTo(CFrame.new(0, 5, 0))
	  car.Parent = workspace

	Qué agrega sobre el ensamblador:
	  * Socket_Wheel_* sube `restSpring` sobre el buje: es el origen del rayo de suspensión. Con eso el auto en reposo
	    queda apoyado con los neumáticos en el piso (largo del resorte menos su compresión estática).
	  * WheelWeld_FL/FR/RL/RR: Weld del Chassis al neumático con C0 en el buje, para animar giro y dirección; la llanta
	    se suelda al neumático y gira con él.
	  * DriverSeat: VehicleSeat con la posición y el tamaño de rig.seat.
	  * Atributo WheelRadius del Chassis, que lee el manejo.
	El eje de giro es X porque el neumático y el chasis comparten orientación y el eje del auto va en X.
]]

local Workspace = game:GetService("Workspace")

local Plan = require(script.Parent.VehicleModelPlan)
local VehicleAssembler = require(script.Parent.VehicleAssembler)

export type Options = {
	suspensionLength: number, -- studs, largo libre del resorte (Config.Driving.DefaultProfile.suspensionLength)
	suspensionFrequency: number, -- Hz (Config.Driving.DefaultProfile.suspensionFrequency)
}

local VehicleBody = {}

local function vector(values: { number }): Vector3
	return Vector3.new(values[1], values[2], values[3])
end

local function weldWheel(chassis: BasePart, wheel: BasePart, tag: string, offset: Vector3)
	local old = wheel:FindFirstChildWhichIsA("WeldConstraint")
	if old then
		old:Destroy()
	end
	local weld = Instance.new("Weld")
	weld.Name = `WheelWeld_{tag}`
	weld.Part0 = chassis
	weld.Part1 = wheel
	weld.C0 = CFrame.new(offset)
	weld.Parent = wheel
end

function VehicleBody.build(imported: Instance, assetKey: string, options: Options): Model
	local entry = assert(VehicleAssembler.entry(assetKey), `[VehicleBody] '{assetKey}' no está en VehicleModels.json`)
	local model = VehicleAssembler.build(imported, assetKey)
	local chassis = model.PrimaryPart :: BasePart
	local rest = Plan.restSpring(options.suspensionLength, options.suspensionFrequency, Workspace.Gravity)

	chassis:SetAttribute("WheelRadius", entry.rig.wheelRadius)
	chassis.RootPriority = 10

	for _, tag in Plan.WHEEL_TAGS do
		local tire = model:FindFirstChild(`Tire_{tag}`) :: BasePart?
		local rim = model:FindFirstChild(`Rim_{tag}`) :: BasePart?
		local hub = Plan.wheelOffset(entry, tag)
		local ray = Plan.raySocketOffset(entry, tag, rest)
		if tire and hub then
			weldWheel(chassis, tire, tag, vector(hub))
			tire.CanCollide = false
			tire.CanQuery = false
		end
		if tire and rim then
			local old = rim:FindFirstChildWhichIsA("WeldConstraint")
			if old then
				old:Destroy()
			end
			local weld = Instance.new("WeldConstraint")
			weld.Name = `Weld_{rim.Name}`
			weld.Part0 = tire
			weld.Part1 = rim
			weld.Parent = rim
			rim.CanCollide = false
			rim.CanQuery = false
		end
		local socket = VehicleAssembler.socket(model, `Socket_Wheel_{tag}`)
		if socket and ray then
			socket.Position = vector(ray)
		end
	end

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = vector(entry.rig.seat.size)
	seat.Transparency = 1
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.HeadsUpDisplay = false
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.Massless = true
	seat.CFrame = chassis.CFrame * CFrame.new(vector(Plan.seatOffset(entry)))
	seat.Parent = model
	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0 = chassis
	seatWeld.Part1 = seat
	seatWeld.Parent = seat
	return model
end

-- Revisa en Studio un modelo importado (o ya armado) y devuelve un informe: línea por problema o dato.
-- Se corre desde la barra de comandos:
--   print(table.concat(require(game.ReplicatedStorage.Shared.VehicleBody).verify(selected, "T1_Sedan"), "\n"))
function VehicleBody.verify(imported: Instance, assetKey: string): { string }
	local report: { string } = {}
	local entry = VehicleAssembler.entry(assetKey)
	if not entry then
		return { `ERROR '{assetKey}' no está en VehicleModels.json` }
	end
	for _, problem in Plan.validate(entry) do
		table.insert(report, `ERROR manifest: {problem}`)
	end

	local chassis = imported:FindFirstChild("Chassis", true)
	if not (chassis and chassis:IsA("BasePart")) then
		table.insert(report, "ERROR el modelo no tiene la malla Chassis")
		return report
	end
	local size = chassis.Size
	local ratio = Plan.scaleRatio({ size.X, size.Y, size.Z }, entry.parts.Chassis.size)
	local expected = entry.parts.Chassis.size
	table.insert(
		report,
		string.format(
			"INFO Chassis importado %.2f x %.2f x %.2f studs; manifest %.2f x %.2f x %.2f",
			size.X,
			size.Y,
			size.Z,
			expected[1],
			expected[2],
			expected[3]
		)
	)
	if ratio and math.abs(ratio - 1) > 0.02 then
		table.insert(
			report,
			`AVISO escala de importación {string.format("%.3f", ratio)}: el ensamblador la corrige con Size`
		)
	end
	-- Ejes: la longitud debe correr por Z y el chasis no debe venir girado.
	if size.Z < size.X then
		table.insert(
			report,
			"ERROR el Chassis es más ancho que largo: el FBX llegó girado (la longitud debe ir en Z)"
		)
	end
	local look = chassis.CFrame.LookVector
	if look:Dot(Vector3.new(0, 0, -1)) < 0.99 then
		table.insert(report, `AVISO el Chassis llegó con rotación (LookVector {look}); el ensamblador no la corrige`)
	end
	for _, name in Plan.REQUIRED_PARTS do
		if not imported:FindFirstChild(name, true) then
			table.insert(report, `ERROR falta la malla {name}`)
		end
	end
	if #report == 1 then
		table.insert(report, "OK sin problemas")
	end
	return report
end

return VehicleBody

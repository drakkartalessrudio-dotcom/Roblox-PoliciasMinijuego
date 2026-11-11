--[[
	Config: valores ajustables de TravesurasBrainrot, con los nombres de "Parámetros
	ajustables" del GDD. Se leen con Tuning.get("Seccion.Valor") en el momento de usarlos.
	Los comentarios dicen la unidad y el efecto de cada valor.
]]

local Config = {
	Server = {
		MaxPlayers = 16, -- jugadores por servidor
	},
	World = {
		SandSpeedMult = 0.85, -- multiplicador de velocidad sobre arena (jugadores y policías terrestres)
	},
	Travel = {
		FadeSeconds = 0.35, -- el cliente funde a negro este tiempo antes del teletransporte (y lo mismo al llegar)
		CooldownSeconds = 3, -- espera entre viajes de un mismo jugador
		StreamTimeoutSeconds = 4, -- cuánto espera el servidor a que el mapa de destino se cargue en el cliente
	},
	Plots = {
		MaxPerPlayer = 1, -- parcelas del lobby que puede reclamar un jugador
		StandRefreshSeconds = 5, -- cada cuánto se actualiza el cartel de cada parcela
	},
	Achievements = {
		RefreshSeconds = 5, -- cada cuánto se recalculan los logros de cada jugador
	},
	Player = {
		BaseWalkSpeed = 16, -- studs/s a nivel 1
		SpeedPerLevel = 0.4, -- studs/s ganados por nivel
		MaxSpeed = 60, -- tope de velocidad (studs/s)
		DashSpeedMult = 1.8, -- multiplicador de velocidad durante el Dash
		DashSeconds = 0.35, -- duración del Dash
		DashCooldown = 5, -- segundos entre Dash
		PushCooldown = 3, -- segundos entre Empujones
		PushRange = 6, -- alcance del Empujón (studs)
		SpeedRefreshSeconds = 0.5, -- cada cuánto el servidor recalcula la velocidad
	},
	Progress = {
		MaxLevel = 50, -- nivel máximo antes de la Ascensión
		XpBase = 30, -- base de la curva de XP
		XpExponent = 1.4, -- exponente de la curva de XP: 30 × n^1,4
		ComboBonus = 0.25, -- XP extra tras un combo de travesuras
		ComboCount = 3, -- travesuras seguidas para el combo
		ComboWindow = 60, -- segundos en que se cuentan
		EscapeXpPerStar = 50, -- XP por escapar con cada estrella
	},
	Heat = {
		StarThresholds = { 20, 60, 120, 200, 320, 480 }, -- calor mínimo para cada estrella
		StarCapByLevel = { { 1, 2 }, { 6, 3 }, { 14, 4 }, { 26, 5 }, { 40, 6 } }, -- { nivel, techo de estrellas }
		DecayPerSecond = 5, -- calor que baja por segundo en "Buscando"
		LoseSightSeconds = 10, -- segundos sin ser visto para pasar a "Buscando"
		ChasePressurePer5s = 1, -- calor extra cada 5 s con un policía viéndote
		CopKnockdown = 20, -- calor por derribar un policía
		RiskPayoutPerStar = 0.4, -- premio de riesgo por estrella: ×(1 + 0,4 × ★)
		SmallWitness = 8, -- referencia de calor de una travesura pequeña
	},
	Hide = {
		SecondsPerStar = 3, -- segundos escondido para bajar una estrella
		MinCopDistance = 8, -- distancia mínima de un policía para que cuente esconderse
	},
	Detect = {
		FillSecondsNear = 0.5, -- segundos para detectarte de cerca
		FillSecondsFar = 1.6, -- segundos para detectarte de lejos
		ConeDegrees = 100, -- ángulo del cono de visión
		HearingScale = 1.0, -- multiplicador del radio de oído (ruido de las travesuras)
		MuffledHearing = 0.3, -- fracción del radio de oído cuando hay una pared de por medio
		TickSeconds = 0.15, -- cada cuánto piensan los policías
		MischiefVisionMult = 1.6, -- una travesura a la vista llama la atención: multiplica el alcance de visión
		MischiefFillMult = 0.7, -- y acorta la barra de detección
		ChaseVisionMult = 1.5, -- histéresis: en persecución (!) el policía ve a su objetivo con este múltiplo del alcance normal
	},
	Guard = {
		ActivateRadius = 260, -- una guardia aparece en su puesto cuando un jugador está a esta distancia
		RespawnSeconds = 10, -- espera antes de reponer una guardia retirada o derribada del todo
		WaitSeconds = 2, -- pausa al llegar a un punto de guardia, antes de mirar
		ScanDegrees = 100, -- barrido de la mirada, de derecha a izquierda
		ScanSeconds = 3, -- duración del barrido
		TurnDegreesPerSecond = 240, -- rapidez máxima para girar la cabeza
		ArriveRadius = 3.5, -- distancia a la que cuenta como llegado a un punto
		WalkTimeoutSeconds = 20, -- si no llega a su siguiente punto, se teletransporta
		ReturnSeconds = 5, -- tras perderte, si no vuelve a su último punto en este tiempo, se teletransporta
	},
	Cops = {
		Patata = { Speed = 14, VisionRange = 40, Resistance = 12 },
		Capibara = { Speed = 22, VisionRange = 55, Resistance = 18 },
		Tiburon = { Speed = 30, VisionRange = 60, Resistance = 30 },
		Cafetera = { Speed = 38, VisionRange = 65, Resistance = 40 },
		Helicoptero = { Speed = 46, VisionRange = 80, Resistance = 999 },
		Comisario = { Speed = 52, VisionRange = 90, Resistance = 999 },
		-- Progresión de alerta: los policías se "espabilan" con las estrellas del jugador. Índice = estrellas
		-- (1 a 6; sin estrellas, p. ej. en plena travesura, se usa la entrada de ★1). Multiplican a
		-- Speed y VisionRange de cada tipo, y a los segundos de la barra de detección.
		AlertVisionByStar = { 0.45, 0.6, 0.7, 0.8, 0.9, 1.0 }, -- Patata ★1: 40 × 0,45 = 18 studs; Comisario ★6: 90
		AlertSpeedByStar = { 0.85, 0.92, 0.96, 1.0, 1.0, 1.0 }, -- Patata ★1: 14 × 0,85 ≈ 12 (más lenta que el nivel 1)
		AlertFillByStar = { 1.4, 1.25, 1.1, 1.0, 0.9, 0.8 }, -- ×segundos de detección: de ★1 cuesta más fijarte
		-- Policías por estrella: lista de { tipo, cantidad } acumulativa (se toma la entrada de la estrella actual).
		-- Barrio Papa (techo ★2): solo Patatas. La Capibara debuta en ★3 (Colegio, nivel 6).
		RosterByStar = {
			{ { "patata", 2 } },
			{ { "patata", 3 } },
			{ { "patata", 2 }, { "capibara", 1 }, { "tiburon", 2 } },
			{ { "patata", 2 }, { "capibara", 2 }, { "tiburon", 2 }, { "cafetera", 2 } },
			{ { "patata", 2 }, { "capibara", 2 }, { "tiburon", 3 }, { "cafetera", 2 }, { "helicoptero", 1 } },
			{ { "patata", 3 }, { "capibara", 2 }, { "tiburon", 3 }, { "cafetera", 3 }, { "helicoptero", 2 }, { "comisario", 1 } },
		},
		MaxPerPlayer = 14, -- máximo de policías perseguidores por jugador
		PatrolPerPlayer = 3, -- caminantes (patrulla ambiental que aparece, cruza y desaparece) cerca de cada jugador
		WalkerSpawnMin = 5, -- segundos mínimos entre la aparición de un caminante y el siguiente (por jugador)
		WalkerSpawnMax = 12, -- segundos máximos
		WalkerMinTrip = 90, -- distancia mínima entre el punto de aparición y el destino de un caminante
		WalkerMaxTrip = 320, -- distancia máxima del trayecto
		WalkerMaxSeconds = 120, -- tiempo máximo de un caminante antes de irse
		WalkerVanishDistance = 70, -- un caminante no desaparece si hay un jugador más cerca que esto
		HunterRange = 1500, -- los cazadores (Helicóptero, Comisario) buscan al jugador con más estrellas dentro de este radio
		PatrolRadius = 320, -- distancia máxima de una patrulla ambiental a su jugador
		SpawnMinDistance = 70, -- distancia mínima para aparecer fuera de la vista
		SpawnMaxDistance = 260, -- distancia máxima para aparecer
		DespawnDistance = 420, -- distancia a la que un policía se retira
		DifficultyPerAscension = 0.04, -- aumento de velocidad y visión por Ascensión
		DifficultyCap = 0.4, -- tope de ese aumento
		GrabDistance = 3.5, -- distancia de agarre (studs)
		GrabTime = 0.7, -- segundos dentro de esa distancia para agarrar
		KnockdownSeconds = 4, -- tiempo en ragdoll
		SearchSeconds = 8, -- segundos buscando tu última posición
		StunMobileFactor = 0, -- velocidad mientras está aturdido
		CafeteraSlow = 0.7, -- multiplicador de velocidad del vapor
		CafeteraSlowSeconds = 3, -- duración del vapor
		TiburonLungeSeconds = 6, -- segundos entre saltos-embestida
		TiburonLungeWarn = 0.6, -- aviso antes del salto
		BandMaxCops = 30, -- máximo de perseguidores por banda
		FlyHeight = 38, -- altura del Helicóptero (studs)
	},
	Arrest = {
		LossPercent = 0.4, -- fracción del Botín perdida al arresto
		LossPercentHighHeat = 0.6, -- con ★5 o más
		LossMin = 0.1, -- mínimo con mejoras de Bolsillos
		JailSeconds = 5, -- segundos de espera tras el arresto
		RescueSeconds = 5, -- tiempo que la Camioneta espera a un rescatador
		RescueLossPercent = 0.2, -- fracción perdida si lo rescatan
		RescueRange = 8, -- distancia para rescatar
	},
	Spray = {
		CostPerStar = 120, -- costo del Pay'n'Spray por estrella
		LevelFactor = 0.05, -- crecimiento del costo con el nivel
		Range = 14, -- distancia máxima al Pay'n'Spray
	},
	Carry = {
		BaseCap = 300, -- capacidad base de Botín
		CapPerLevel = 40, -- capacidad por nivel de jugador
		CapPerPocketLevel = 150, -- capacidad por nivel de Bolsillos
	},
	Deposit = {
		HoldSeconds = 1.5, -- tiempo de depósito en la Guarida
		Range = 18, -- distancia máxima a la Guarida
	},
	Mischief = {
		SpotCooldown = 45, -- segundos entre repetir el mismo punto (por jugador)
		StartRange = 14, -- distancia máxima al punto
		MinDurationRatio = 0.6, -- fracción de la duración nominal que se exige como mínimo
		GraceSeconds = 8, -- margen sobre la duración nominal antes de expirar
		-- Id, nivel, dinero, XP, calor, ruido (studs) y duración (s)
		Graffiti = { Level = 1, Money = 15, Xp = 25, Heat = 8, Noise = 10, Duration = 7 },
		Timbrazo = { Level = 1, Money = 20, Xp = 30, Heat = 10, Noise = 15, Duration = 5 },
		Hidrante = { Level = 6, Money = 45, Xp = 60, Heat = 20, Noise = 30, Duration = 8 },
		Carrito = { Level = 6, Money = 40, Xp = 55, Heat = 15, Noise = 12, Duration = 5 },
		Castillo = { Level = 14, Money = 60, Xp = 80, Heat = 18, Noise = 15, Duration = 6 },
		Sombrillas = { Level = 14, Money = 75, Xp = 100, Heat = 25, Noise = 25, Duration = 7 },
		Bocinas = { Level = 20, Money = 90, Xp = 120, Heat = 30, Noise = 60, Duration = 10 },
		Semaforos = { Level = 20, Money = 70, Xp = 90, Heat = 12, Noise = 5, Duration = 6 },
		Cajero = { Level = 26, Money = 150, Xp = 200, Heat = 35, Noise = 20, Duration = 6 },
		Estatua = { Level = 26, Money = 200, Xp = 250, Heat = 40, Noise = 25, Duration = 12 },
		Contenedor = { Level = 40, Money = 400, Xp = 500, Heat = 60, Noise = 35, Duration = 9 },
		TimbrazoDistance = 40, -- studs a recorrer tras el timbre
		TimbrazoSeconds = 5, -- segundos para recorrerlos
		TimbrazoMaxMult = 1.8, -- premio máximo por velocidad
		DestrozoMoney = 2, -- Dinero por objeto atravesado a gran velocidad
	},
	SpotFx = {
		-- ID del audio del timbre (el archivo está en assets/audio/doorbell_toyphone.wav; súbelo a Creator Hub
		-- y pega aquí el número o "rbxassetid://número"). Vacío = el timbre se ve pero no suena.
		DoorbellSoundId = "102559465808384",
		DoorbellVolume = 0.9, -- volumen del timbre (0 a 1)
		DoorbellRange = 110, -- studs a los que se oye el timbre
		SignDistance = 120, -- studs desde los que se ve el cartel sobre cada punto de graffiti y timbre
		MuralFade = 0.45, -- segundos que tarda en aparecer el mural pintado
	},
	Coop = {
		PayPerExtraMember = 0.25, -- aumento del pago por miembro en travesuras de banda
		JoinRange = 60, -- distancia para sumar a un compañero a la travesura
		MuralGigante = { Level = 6, MinPlayers = 2, Money = 40, Xp = 60, Heat = 20, Noise = 20, Duration = 12 },
		Sinfonia = { Level = 20, MinPlayers = 3, Money = 140, Xp = 190, Heat = 40, Noise = 80, Duration = 10 },
		CajaFuerte = { Level = 26, MinPlayers = 4, Money = 320, Xp = 420, Heat = 55, Noise = 40, Duration = 12 },
	},
	Band = {
		MaxMembers = 8, -- tamaño máximo de una banda
		BonusPerMember = 0.12, -- bono de Botín y XP por cada otro miembro activo y cercano
		BonusRange = 80, -- distancia (studs) para contar a un compañero
		ActiveWindowSeconds = 30, -- un miembro cuenta si hizo una acción en estos segundos
		HeatShareFraction = 0.5, -- fracción del calor que se contagia
		HeatShareRange = 100, -- distancia del contagio de calor
		SharedRewardRange = 100, -- distancia para repartir derribos y medallas
		InviteCooldownSeconds = 10, -- espera entre invitaciones al mismo jugador
		InviteExpireSeconds = 60, -- segundos que dura una invitación
	},
	Upgrades = {
		MaxLevel = 10, -- nivel máximo de cada línea normal
		CostFactor = 1.45, -- crecimiento del costo por nivel
		Zapatillas = { BaseCost = 100, SpeedPerLevel = 1.5 },
		Sigilo = { BaseCost = 150, ReductionPerLevel = 0.04 },
		Bolsillos = { BaseCost = 120, LossReductionPerLevel = 0.03 },
		Manos = { BaseCost = 200, TimeReductionPerLevel = 0.04 },
		Fortachon = { BaseCost = 250, PowerPerLevel = 0.08 },
		Cinta = { BaseCost = 300, CostFactor = 1.45, MaxLevel = 10 },
		Bateria = { BaseCost = 400, CostFactor = 1.6, MaxLevel = 5 },
		Gimnasio = { BaseCost = 600, CostFactor = 1.6, MaxLevel = 5 },
	},
	Tools = {
		Tarta = { Cost = 300, Level = 4, Cooldown = 6, StunSeconds = 2, Range = 60 },
		Banana = { Cost = 800, Level = 9, Cooldown = 8, SlipSeconds = 3, Lifetime = 40 },
		Humo = { Cost = 2000, Level = 16, Cooldown = 20, BlindSeconds = 5, Radius = 28 },
		Patineta = { Cost = 4000, Level = 22, Cooldown = 25, SpeedMult = 1.35, Seconds = 8 },
		Senuelo = { Cost = 8000, Level = 30, Cooldown = 30, Seconds = 6 },
	},
	Ascension = {
		MinLevel = 50, -- nivel mínimo para ascender
		Max = 10, -- máximo de Ascensiones
		FeeBase = 20000, -- cuota base (Dinero)
		FeeGrowth = 1.15, -- crecimiento de la cuota por Ascensión
		BonusEarly = 0.5, -- bono por Ascensión (1ª a 6ª)
		BonusLate = 0.25, -- bono por Ascensión (7ª a 10ª)
		EarlyCount = 6, -- cuántas Ascensiones usan BonusEarly
		CerebrosBase = 2, -- Cerebros por Ascensión
		CerebrosSixStar = 1, -- Cerebro extra si llegó a ★6
	},
	Perks = {
		CostByLevel = { 1, 2, 3, 4, 5 }, -- costo en Cerebros de cada nivel de perk
		PiesDeRayo = { SpeedPerLevel = 1 },
		SigiloInnato = { ReductionPerLevel = 0.03 },
		CapitalInicial = { MoneyPerLevel = 300 },
		SangreFria = { DecayBonusPerLevel = 0.08 },
	},
	Economy = {
		BonusCap = 8, -- tope del bono total aditivo
		PassMoneyBonus = 1.0, -- bono del pase ×2 Dinero (aditivo)
		IncomeBase = 70, -- Dinero/min a nivel 0 en el modelo de diseño (para recompensas por minutos)
		IncomePerLevel = 10, -- Dinero/min ganado por nivel en el modelo de diseño
	},
	Daily = {
		QuestCount = 3, -- misiones diarias
		RewardMinutesOfIncome = 8, -- recompensa en minutos de ingreso
		StreakMaxBonus = 0.5, -- bono máximo por racha
		StreakStep = 0.1, -- bono por día de racha
		WeeklyMultiplier = 6, -- recompensa semanal = diaria × este valor
	},
	Stash = {
		RatePercent = 0.08, -- fracción del ingreso por minuto del alijo
		CapMinutes = 90, -- tope del alijo
		ExtendedCapMinutes = 240, -- tope con el pase de alijo extendido
	},
	Afk = {
		UnlockLevel = 8, -- nivel que desbloquea la Sala de Entrenamiento
		TickSeconds = 5, -- cada cuánto el servidor verifica la zona y paga
		RatePercent = 0.15, -- ganancia AFK base
		RatePerCintaLevel = 0.02, -- ganancia AFK por nivel de Cinta
		DailyCapMinutes = 40, -- tope diario de entrenamiento pagado
		DailyCapPerGymLevel = 8, -- minutos extra por nivel de Gimnasio
		CheckInBaseSeconds = 360, -- intervalo base entre check-ins
		CheckInPerBatteryLevel = 108, -- segundos extra por nivel de Batería
		CheckInJitter = 0.15, -- variación aleatoria del intervalo (±)
		CheckInMaxSeconds = 1020, -- intervalo máximo con variación
		ChallengeWindowSeconds = 60, -- tiempo para responder el reto
		ChallengeMinReactionSeconds = 0.35, -- una respuesta más rápida no es humana
		ChallengeWrongLimit = 3, -- errores seguidos antes de la pausa
		ChallengeLockMinutes = 5, -- pausa tras los errores
		CheckInBonusMinutes = 1, -- bono por responder bien (minutos de ganancia AFK)
		SuspectStreak = 5, -- retos con tiempos casi idénticos para marcar
		SuspectToleranceSeconds = 0.02, -- diferencia máxima para considerarlos idénticos
		ZoneMaxPlayers = 6, -- jugadores por sala
	},
	Tutorial = {
		ScriptedCopSpeed = 14, -- velocidad del policía guionado
		EndLevel = 6, -- el tutorial no se muestra desde este nivel (quien ya lo superó no lo repite)
	},
	Shop = {
		ReceiptPruneAt = 450, -- recibos guardados a partir de los cuales se podan los más viejos
	},
}

return Config

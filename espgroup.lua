local gui

-- [0] BASE ------------------------------------------------------
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local HttpService  = game:GetService("HttpService")
local VirtualUser  = game:GetService("VirtualUser")
local Workspace    = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

local ALIVE     = true
local conns     = {}
local unloadFns = {}

-- registra conexoes para poder desconectar tudo no unload
local function hook(signal, fn)
	local c = signal:Connect(fn)
	table.insert(conns, c)
	return c
end

local function onUnload(fn)
	table.insert(unloadFns, fn)
end

-- cria instancias sem depender da API do executor
local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

-- raiz das UIs: gethui() esconde a interface da varredura de PlayerGui
-- que alguns jogos fazem (anti-cheat local roda no cliente e manda o
-- kick pro servidor); sem gethui, cai no PlayerGui normalmente
local function uiRoot()
	local ok, h = pcall(gethui)
	if ok and typeof(h) == "Instance" then
		return h
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

-- HttpGet do executor com fallback para a API request()
local function httpGet(url)
	local ok, res = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(res) == "string" then
		return res
	end
	if type(request) == "function" then
		local ok2, res2 = pcall(request, { Url = url, Method = "GET" })
		if ok2 and type(res2) == "table" and type(res2.Body) == "string" then
			return res2.Body
		end
	end
	return nil
end

-- leitura/gravacao de arquivos do executor (cache da key)
local function fileRead(path)
	if type(readfile) ~= "function" then
		return nil
	end
	local ok, res = pcall(readfile, path)
	if ok and type(res) == "string" then
		return res
	end
	return nil
end

local function fileWrite(path, data)
	if type(writefile) ~= "function" then
		return false
	end
	local ok = pcall(writefile, path, data)
	return ok == true
end

-- [1] CONFIGURACAO ---------------------------------------------
-- [1] CONFIGURACAO ---------------------------------------------
local Config = {
	Info = {
		Name    = "Esp steal a egg menu",
		Author  = "Esp House",
		Version = "2.1",
	},

	Key = {
		Enabled         = true,     -- false = pula a key (testes)
		TestKeys        = { "DEMO", "ESP-HOUSE-TEST", "ESPHOUSE2026" },
		ValidateURL     = "",       -- ex: "https://seu-servidor.com/validate?key=" (url .. chave)
		LinkvertiseURL  = "",       -- ex: "https://linkvertise.com/123456/egg" (botao Get Key)
		CacheFile       = "esp_house_key.txt",
		SaveKey         = true,     -- guarda key valida no executor (nao pede de novo)
	},

	ESP = {
		Eggs        = false,        -- "Egg ESP": Highlight nos ovos
		ShowName    = false,        -- nome do ovo na tag
		ShowRarity  = false,        -- raridade (atributo Rarity ou o nome)
		ShowValue   = false,        -- valor (atributos Value/Cash/Price)
		ShowDistance = true,        -- distancia em metros na tag
		Boxes       = false,        -- SelectionBox nos ovos
		Tracers     = false,        -- linhas do rodape ate os ovos
		MaxDistance  = 900,         -- alcance maximo das tags/highlights
		UpdateRate  = 0.35,         -- entre varreduras de ovos
		LabelRate   = 0.12,         -- entre atualizacoes das tags
		EggColor    = Color3.fromRGB(244, 182, 63),
		ShowRarities = "All",      -- "Egg Rarities to Show" (dropdown aba Local)
	},

	Steal = {
		Enabled         = false,    -- "Auto Steal / Instant Grab"
		EggPatterns     = { "egg", "ovo", "ovum" },
		ExitPatterns    = { "saida", "exit", "gate", "biome", "portal",
			"vender", "venda", "sell", "deposit", "entrega", "drop",
			"final", "safe", "home", "base", "collector", "coletor" },
		ScanInterval    = 1.0,      -- segundos entre buscas de ovo
		ScanRange       = 150,      -- studs
		ExitRange       = 700,      -- alcance da saida do bioma
		WallScanRange   = 14,       -- raycast da parede mais proxima
		WallSnapOffset  = 2.2,      -- studs de distancia da parede
		MicroStep       = 0.45,     -- studs por frame (movimento "humano")
		HoldTime        = 1.2,      -- tempo colado na parede com o ovo
		-- ROUBO EXPRESSO (padrao): vai de tween rapido, pega o ovo e
		-- volta pro ponto de onde voce tava - "em segundos"
		QuickHeist      = true,
		QuickSpeed      = 240,      -- studs/s no roubo expresso
		StealthMaxSpeed = 80,       -- teto com Modo Furtivo (5x corrida;
		                            -- 120+ sustentado = flag de velocidade)
		ReturnHome      = true,     -- volta automatica ao ponto original
		WalkToExit      = false,    -- opcional: passa na saida antes de voltar
		CarryHome       = false,    -- "Auto Place Egg / Auto Deliver"
		                            -- (com ovo na mao: vai pra base - nunca
		                            -- teleport seco: dispara kick BAC)
		CarryCooldown   = 4,        -- segundos entre tentativas de entrega
		-- filtros da pagina Farm (dropdowns)
		TargetArea      = "Best Unlocked",
		TargetRarity    = "All",
		TargetMutation  = "Any",
		TargetValue     = "Any",
		-- modos da aba Main: cada um mira so aquele tipo de ovo
		ModeSelected    = false,   -- "Auto Steal Selected Eggs" (segue filtros)
		ModeSecret      = false,   -- "Auto Steal Secret Egg"
		ModeBig         = false,   -- "Auto Steal Big Egg"
		ModeRarest      = false,   -- "Auto Steal Rarest Egg"
		-- sliders da aba Main
		StealSpeed      = 1000,    -- 100..1000: agilidade do roubo (maior = mais rapido)
		RunSpeed        = 100,     -- 16..300: WalkSpeed SO durante o roubo (restaura depois)
	},

	-- tabelas dos filtros: texto do ovo (ou atributo Rarity) que passa
	Filters = {
		Rarity = {
			All = {},
			Rare = { "raro", "rare" },
			Epic = { "epico", "epic" },
			Mutant = { "mutant", "mutante" },
			Divine = { "divino", "divine" },
			-- raridades da UI nova (abas Main/Best Egg/Local)
			Common    = { "common", "comum" },
			Legendary = { "legendary", "legendario" },
			Secret    = { "secret", "secreto" },
			Eternal   = { "eternal", "eterno" },
		},
		Mutation = {
			["Any"] = {},
			["Mutated only"] = { "mutado", "mutated", "mutation", "mutant" },
		},
		Value = {
			Any = {},
			High = { "gold", "dourado", "shiny", "brilhante", "raro", "rare",
				"epico", "epic", "divino", "divine" },
			Highest = { "divino", "divine", "mitic", "mythic", "legend",
				"secret", "dourado", "gold", "shiny" },
		},
	},

	Guardian = {
		Ghost          = false,     -- "Anti Hit" / desvio do Auto Boss
		AntiFollow     = false,     -- "Anti-Follow" (colisao)
		Names          = { "guardian", "guardiao", "boss", "warden", "chef" },
		ScanInterval   = 0.6,
		DangerDistance = 16,        -- studs: blink quando chegar perto
		FollowRadius   = 14,        -- studs: desliga colisao dentro disso
		BlinkCooldown  = 4,         -- segundos entre blinks
		BlinkDistance  = 9,         -- deslocamento total do blink
		BlinkSteps     = 7,         -- frames para distribuir o blink
	},

	Auto = {
		-- pagina Pets
		Hatch          = false,     -- "Auto Hatch"
		EquipBest      = false,     -- "Auto Equip Best"
		Merge          = false,     -- "Auto Fuse"
		Upgrade        = false,     -- "Auto Upgrade" (pets)
		Sell           = false,     -- "Auto Sell"
		SellUpTo       = "Common",  -- "Sell up to" (dropdown)
		-- pagina Progresso
		Train          = false,     -- "Auto Train Treadmill"
		BuyTrail       = false,     -- "Auto Buy Trails"
		BuyUpgrades    = false,     -- "Auto Buy Upgrades"
		-- pagina Eventos
		Event          = false,     -- "Auto Event"
		Boss           = false,     -- "Auto Boss (Dr. Scramble)"
		Claim          = false,     -- "Auto Claim Rewards"
		-- legados v1.2 (mesmos motores, sem widget nesta UI)
		Coins          = false,
		BuyEgg         = false,
		TargetOnly     = false,
		BuyBelt        = false,
		Delay          = 2,          -- pacing de compra (s)
		InteractDelay  = 1.0,        -- acao de hatch/merge/etc
		CollectRadius  = 14,
		BuyRadius      = 60,
		Radius         = 160,        -- alcance das automacoes novas
		HatchPatterns   = { "hatch", "incubat", "chocar", "eggincubator", "choc" },
		MergePatterns   = { "merge", "combinar", "fusion", "fundir", "fusao", "fuse" },
		CoinPatterns    = { "coin", "moeda", "reward", "recompensa", "cash" },
		BuyPatterns     = { "comprar", "buy", "purchase", "loja", "shop" },
		BeltPatterns    = { "belt", "esteira", "conveyor" },
		TrailPatterns   = { "trail", "trilha" },
		EquipPatterns   = { "equip best", "equipar melhor", "equipar", "equip",
			"melhor", "best team", "auto equip" },
		SellPatterns    = { "sell", "vender", "venda", "vende" },
		TrainPatterns   = { "treadmill", "esteira", "treinar", "train",
			"treino", "workout" },
		UpgradePatterns = { "evoluir", "evolve", "upgrade", "melhorar",
			"upgrad", "evolution" },
		BuyUpgradePatterns = { "melhoria", "melhorar", "upgrade", "upg",
			"melhorias", "upgrade base" },
		EventPatterns   = { "event", "evento", "ao vivo", "live" },
		BossPatterns    = { "scramble", "boss", "chefe", "dr scramble", "fight" },
		ClaimPatterns   = { "recompensa", "reward", "claim", "resgatar",
			"mastery", "maestria" },
		MergeRemote     = "",        -- opcional: nome do RemoteEvent de merge
	},

	Player = {
		WalkSpeedTarget = 16,       -- slider "Speed Hack" (16-200)
		BaseWalkSpeed   = 16,
		JumpPower       = 50,
		SpeedRamp       = 3,        -- studs/s de subida (evita flag de speedhack)
		InfiniteJump    = false,
		Noclip          = false,
		Fly             = false,    -- "Fly"
		FlySpeed        = 60,       -- studs/s do voo
		God             = false,    -- "God Mode" (vida local)
		AntiTrap        = false,    -- "Anti Trap"
		AntiAFK         = false,
		-- novos da UI 2em-1 (abas Local/Misc)
		TPWalk          = false,   -- deslocamento curto por frame enquanto anda
		TPWalkSpeed     = 60,      -- studs/s do TPWalk (teto do furtivo aplica)
		InstantPrompt   = false,   -- "Instant Proximity Prompt" (HoldDuration=0)
		AntiRagdoll     = false,   -- "Anti Ragdoll" (nao cai de costas)
		AntiRejoin      = false,   -- "Anti Rejoin" (reexec se trocar de servidor)
		ReexecURL       = "",      -- URL do loadstring pro Anti Rejoin (opcional)
		-- "custom" = voce mexeu no slider. Enquanto for false o script
		-- NAO escreve nada no Humanoid (escrita passiva = flag de kick)
		SpeedCustom     = false,
		JumpCustom      = false,
	},

	Game = {
		Biomes     = { "Todos" },            -- legado (Diagnosticar v1)
		Biome      = "Todos",
		EggTargets = { "Todos" },
		TargetEgg  = "Todos",
		-- nomes de zona/bioma/area que o scan procura no mapa
		-- (o filtro "Target Area" usa "area 1"... por nome)
		ZonePatterns = { "bioma", "zone", "zona", "area", "regiao", "biome",
			"savanna", "desert", "deserto", "winter", "neve", "snow", "gelo", "ice",
			"lava", "fogo", "fire", "praia", "beach", "floresta", "forest",
			"montanha", "mountain", "oceano", "ocean", "cidade", "city",
			"grama", "grass", "vulcao", "volcano", "pantano", "swamp", "ilha", "island" },
		-- pecas de armadilha do mapa (Anti Trap)
		TrapPatterns = { "trap", "armadilha", "spike", "espinho", "thorn",
			"quicksand", "cacto", "cactus", "lava" },
	},

	Teleport = {
		BasePatterns  = { "minha base", "my base", "mybase", "base", "spawn",
			"hub", "lobby", "casa", "house", "plot", "incubator", "incubadora" },
		ExitPatterns  = { "saida", "saida do bioma", "exit", "gate", "biome",
			"portal", "vender", "venda", "sell", "final", "deposit" },
		AvoidPatterns = { "baseplate", "terrain", "ground", "mapa", "map_" },
		ExactBase     = "",        -- caminho exato opcional, ex: "Workspace.Map.MyBase"
		ExactExit     = "",
		Duration      = 0.6,       -- minimo do tween (sem teleport seco)
		MaxSpeed      = 300,       -- studs/s max: a duracao escala com a
		                           -- distancia (0.6s fixo p/ base longe =
		                           -- velocidade absurda = flag de teleport)
		StealthSpeed  = 100,       -- teto de studs/s com Modo Furtivo
	},

	-- anti-deteccao: o anti-cheat do SERVIDOR (BAC / erro 267)
	-- marca velocidade/teleporte/noclip anormais e spam de interacoes.
	-- Esta UI nova nao tem toggle do Modo Furtivo: ele fica SEMPRE
	-- ligado aqui e entrega o pacing seguro por padrao.
	Stealth = {
		Enabled     = true,                 -- pacing + limites sempre ativos
		MaxSpeed    = 200,                  -- teto do slider Speed Hack
		Humanize    = 0.35,                 -- variacao +-35% nos delays (0 = off)
		ActionGap   = { 0.6, 1.8 },         -- espera aleatoria entre interacoes (s)
		BootDelay   = { 4, 9 },             -- espera antes das 1as automacoes (s)
		MicroStep   = 0.3,                  -- studs/frame no furtivo (passo humano)
		BlinkSteps  = 14,                   -- blink do guardiao mais fracionado
	},

	-- aba "Best Egg": quadro do melhor ovo + teleguiado (estilo Lennon)
	BestEgg = {
		Enabled    = false,   -- "Guided Teleport" (dispara ao ligar)
		Loop       = false,   -- repete o teleguiado com espera humana
		Filter     = {},      -- chips { Legendary, Secret, Eternal, Divine }
		                      -- tabela vazia = todas as raridades
		Range      = 900,     -- alcance do scan (studs)
		UpdateRate = 3,       -- entre atualizacoes do quadro (s)
		GoCooldown = 4.5,     -- espera entre teleports no Loop (s)
	},

	-- aba "Webhook": logs no Discord (HTTP do executor, fora do Roblox)
	Webhook = {
		URL          = "",    -- "Webhook URL"
		Send         = false, -- master switch ("Send Webhook")
		NotifyStolen = false, -- avisa a cada ovo roubado
	},
}

-- [2] KEY SYSTEM ------------------------------------------------
local KeySys = { validated = false }

local function trim(s)
	return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

function KeySys.validate(key)
	key = trim(key):upper()
	if key == "" then
		return false, "chave vazia"
	end

	-- (1) chaves locais de teste (offline, para desenvolvimento)
	for _, k in ipairs(Config.Key.TestKeys) do
		if k == key then
			KeySys.validated = true
			return true, "chave de teste aceita"
		end
	end

	-- (2) validacao remota via HTTP
	if Config.Key.ValidateURL ~= "" then
		local url = Config.Key.ValidateURL .. HttpService:UrlEncode(key)
		local body = httpGet(url)
		if type(body) == "string" then
			local low = trim(body):lower()
			if low == "ok" or low == "valid" or low == "true"
				or low:find('"valid":true', 1, true)
				or low:find('"status":"ok"', 1, true)
				or low:find('"ok":true', 1, true) then
				KeySys.validated = true
				return true, "chave validada pelo servidor"
			end
			return false, "servidor recusou a chave"
		end
		return false, "sem conexao com o servidor de chaves"
	end

	return false, "sem servidor configurado (use chave de teste)"
end

function KeySys.save(key)
	if Config.Key.SaveKey then
		fileWrite(Config.Key.CacheFile, trim(key))
	end
end

-- tenta reusar a key ja salva no executor
function KeySys.loadCache()
	local data = fileRead(Config.Key.CacheFile)
	if data and data ~= "" then
		local ok = KeySys.validate(data)
		if ok then
			return trim(data)
		end
	end
	return nil
end

local function unlocked()
	return (not Config.Key.Enabled) or KeySys.validated
end

-- [2.5] UTILITARIOS ANTI-DETECCAO -------------------------------
-- atrasos humanizados: evita ciclos com periodo identico (flag tipica
-- de macro) e espaca interacoes com prompts/remotes (anti-spam)
local function jit(d)
	local h = Config.Stealth.Humanize
	if h <= 0 then
		return d
	end
	return d * (1 + (math.random() * 2 - 1) * h)
end

local function gap()
	local g = Config.Stealth.ActionGap
	return g[1] + math.random() * (g[2] - g[1])
end

local function bootDelay()
	local b = Config.Stealth.BootDelay
	return b[1] + math.random() * (b[2] - b[1])
end

local function stealth()
	return Config.Stealth.Enabled
end

-- velocidade alvo ja com o teto do Modo Furtivo aplicado
local function speedTarget()
	local t = Config.Player.WalkSpeedTarget
	if stealth() then
		t = math.min(t, Config.Stealth.MaxSpeed)
	end
	return t
end

-- step do micro-movimento considerando o modo furtivo
local function microStep()
	return stealth() and Config.Stealth.MicroStep or Config.Steal.MicroStep
end

-- cache do Workspace: evita GetDescendants repetidos (era a maior
-- fonte de travamento) - atualiza no maximo 2x por segundo
local wsCache = { t = -9, list = nil }
local function wsDescendants()
	if not wsCache.list or (os.clock() - wsCache.t) >= 0.4 then
		wsCache.t = os.clock()
		wsCache.list = Workspace:GetDescendants()
	end
	return wsCache.list
end

-- nomes em minusculo guardados uma unica vez por instancia
local lowMemo = setmetatable({}, { __mode = "k" })
local function lowName(d)
	local v = lowMemo[d]
	if v == nil then
		v = string.lower(d.Name)
		lowMemo[d] = v
	end
	return v
end

-- monta um comparador de padroes ja em minusculo (sem alocar por item)
local function makeMatcher(pats)
	local lp = {}
	for i, p in ipairs(pats) do
		lp[i] = string.lower(p)
	end
	return function(low)
		for i = 1, #lp do
			if low:find(lp[i], 1, true) then
				return true
			end
		end
		return false
	end
end

-- declarado aqui para o modulo Steal dar avisos; definido na Parte C
local toast

-- [3] MOVIMENTO SEGURO -----------------------------------------
local Move = {}

function Move.getRoot()
	local char = LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

function Move.getHumanoid()
	local char = LocalPlayer.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

function Move.instPos(inst)
	if inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return inst.Position
end

function Move.nameHas(name, patterns)
	local low = string.lower(name)
	for _, p in ipairs(patterns) do
		if low:find(string.lower(p), 1, true) then
			return true
		end
	end
	return false
end

-- micro-movimento: anda em passos pequenos por frame em vez de
-- teleportar (simula movimento humano, dificulta deteccao simples)
function Move.microTo(targetPos, step, maxSeconds)
	step = step or Config.Steal.MicroStep
	maxSeconds = maxSeconds or 4
	local deadline = os.clock() + maxSeconds
	while ALIVE and os.clock() < deadline do
		local root = Move.getRoot()
		if not root then
			return false
		end
		local delta = targetPos - root.Position
		local dist = delta.Magnitude
		if dist <= 0.3 then
			return true
		end
		local advance = math.min(step, dist)
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		root.CFrame = root.CFrame + (delta.Unit * advance)
		RunService.RenderStepped:Wait()
	end
	return false
end

-- teleporte curto suave via TweenService (para distancias maiores)
function Move.tweenTo(targetCFrame, duration)
	local root = Move.getRoot()
	if not root then
		return false
	end
	duration = duration or Config.Teleport.Duration
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
	local tween = TweenService:Create(
		root,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = targetCFrame }
	)
	tween:Play()
	-- zera a velocidade EM TODO PASSO do tween: sem isso o personagem
	-- sai do tween com velocity acumulada e "voa" pro lado aleatorio
	local conn = RunService.Heartbeat:Connect(function()
		if root.Parent then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)
	tween.Completed:Wait()
	conn:Disconnect()
	if root.Parent then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	return true
end

-- teleporte INSTANTANEO (milissegundos): um unico set de CFrame
function Move.snapTo(targetCFrame)
	local root = Move.getRoot()
	if not root then
		return false
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = targetCFrame
	RunService.RenderStepped:Wait() -- deixa um frame aplicar
	if root.Parent then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	return true
end

-- acha a parede mais proxima com 8 raycasts horizontais
function Move.nearestWall(origin, range)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local char = LocalPlayer.Character
	if char then
		params.FilterDescendantsInstances = { char }
	end
	local best = nil
	for i = 1, 8 do
		local angle = (i / 8) * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local hit = Workspace:Raycast(origin, dir * range, params)
		if hit and (not best or hit.Distance < best.Distance) then
			best = hit
		end
	end
	return best
end

-- interage com prompts/click detectors do jogo (compativel com
-- fireproximityprompt do Delta/Xeno, com fallback pcall)
function Move.tryInteract(inst)
	if not inst then
		return false
	end
	if stealth() then
		task.wait(gap()) -- espaca interacoes (nao dispara prompt/remote em rajada)
	end
	-- inst pode ser o proprio ProximityPrompt (busca por texto)
	local pp
	if inst:IsA("ProximityPrompt") then
		pp = inst
	else
		pp = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
	end
	if pp then
		if type(fireproximityprompt) == "function" then
			if pcall(fireproximityprompt, pp) then
				return true
			end
		end
		local ok = pcall(function()
			pp.HoldDuration = 0
			pp:InputHoldBegin()
		end)
		if ok then
			task.delay(0.2, function()
				pcall(function()
					pp:InputHoldEnd()
				end)
			end)
			return true
		end
	end
	local cd = inst:FindFirstChildWhichIsA("ClickDetector", true)
	if cd then
		if pcall(function()
			cd:FireClick()
		end) then
			return true
		end
	end
	return false
end

-- busca generica no Workspace por padroes de nome
-- opts = { origin, radius, excludeLocal, avoid }
function Move.scanFor(patterns, opts)
	opts = opts or {}
	local origin = opts.origin
	local radius = opts.radius or math.huge
	-- padroes ja em minusculo uma unica vez por chamada
	local pats = {}
	for i, p in ipairs(patterns) do
		pats[i] = string.lower(p)
	end
	local avoid = nil
	if opts.avoid then
		avoid = {}
		for i, p in ipairs(opts.avoid) do
			avoid[i] = string.lower(p)
		end
	end
	local best, bestDist = nil, math.huge
	for _, d in ipairs(wsDescendants()) do
		if d:IsA("BasePart") or d:IsA("Model") then
			local low = lowName(d)
			local hit = false
			for i = 1, #pats do
				if low:find(pats[i], 1, true) then
					hit = true
					break
				end
			end
			if hit and avoid then
				for i = 1, #avoid do
					if low:find(avoid[i], 1, true) then
						hit = false
						break
					end
				end
			end
			if hit then
				local skip = false
				if opts.excludeLocal and LocalPlayer.Character
					and d:IsDescendantOf(LocalPlayer.Character) then
					skip = true
				end
				if not skip then
					local pos = Move.instPos(d)
					if pos then
						local dist = origin and (pos - origin).Magnitude or 0
						if dist <= radius and dist < bestDist then
							best, bestDist = d, dist
						end
					end
				end
			end
		end
	end
	return best, bestDist
end

-- busca por ProximityPrompts cujo TEXTO (ObjectText/ActionText)
-- bate com os padroes - muitos jogos deixam o objeto chamado "Part"
-- e so o prompt fala "Ovo / Roubar"
function Move.scanPrompt(patterns, opts)
	opts = opts or {}
	local origin = opts.origin
	local radius = opts.radius or math.huge
	local pats = {}
	for i, p in ipairs(patterns) do
		pats[i] = string.lower(p)
	end
	local best, bestDist = nil, math.huge
	for _, d in ipairs(wsDescendants()) do
		if d:IsA("ProximityPrompt") then
			local hay = string.lower(d.ObjectText .. " " .. d.ActionText .. " " .. d.Name)
			local hit = false
			for i = 1, #pats do
				if hay:find(pats[i], 1, true) then
					hit = true
					break
				end
			end
			if hit then
				local anchor = d.Adornee or d.Parent
				local pos = anchor and Move.instPos(anchor)
				if pos then
					local dist = origin and (pos - origin).Magnitude or 0
					if dist <= radius and dist < bestDist then
						best, bestDist = d, dist
					end
				end
			end
		end
	end
	return best, bestDist
end

-- alvo combinado: o mais proximo entre nome-de-objeto e texto-de-prompt
-- retorna inst, posicao, distancia
function Move.findTarget(patterns, opts)
	local a, da = Move.scanFor(patterns, opts)
	local pa = a and Move.instPos(a)
	local b, db = Move.scanPrompt(patterns, opts)
	local pb = nil
	if b then
		pb = (b.Adornee and Move.instPos(b.Adornee))
			or (b.Parent and Move.instPos(b.Parent))
	end
	if b and pb and (not a or not pa or db < da) then
		return b, pb, db
	end
	return a, pa, da
end

-- esta com o ovo na mao? (atributo do jogo ou objeto de ovo dentro
-- do personagem/mochila) - usado pelo teleport "volta pra base"
function Move.isCarrying()
	local function truthy(v)
		if v == true then
			return true
		end
		if type(v) == "string" then
			local low = string.lower(v)
			return v ~= "" and low ~= "false" and low ~= "0" and low ~= "no"
		end
		return false
	end
	local function attrHit(container)
		for name, value in pairs(container:GetAttributes()) do
			local low = string.lower(name)
			local eggish = low:find("egg", 1, true) or low:find("ovo", 1, true)
				or low:find("carry", 1, true) or low:find("hold", 1, true)
				or low:find("carreg", 1, true) or low:find("holdin", 1, true)
			if eggish then
				if truthy(value) then
					return true
				end
				-- numero so vale se o nome indicar estado (CarryCount)
				if type(value) == "number" and value > 0
					and (low:find("carry", 1, true) or low:find("hold", 1, true)
						or low:find("carreg", 1, true)) then
					return true
				end
			end
		end
		return false
	end
	if attrHit(LocalPlayer) then
		return true
	end
	local match = makeMatcher(Config.Steal.EggPatterns)
	local char = LocalPlayer.Character
	if char then
		if attrHit(char) then
			return true
		end
		for _, d in ipairs(char:GetDescendants()) do
			if match(lowName(d)) then
				return true
			end
		end
	end
	local bp = LocalPlayer:FindFirstChild("Backpack")
	if bp then
		for _, d in ipairs(bp:GetDescendants()) do
			if match(lowName(d)) then
				return true
			end
		end
	end
	return false
end

-- resolve um caminho exato opcional ("Workspace.Map.MyBase")
function Move.resolveExact(path)
	if path == "" then
		return nil
	end
	local cur = game
	for name in string.gmatch(path, "[^%.]+") do
		cur = cur:FindFirstChild(name)
		if not cur then
			return nil
		end
	end
	return cur
end

-- [4] MODULO A - CACHES DE SCAN (ovos + guardioes) -------------
-- caches de scan compartilhados com o bypass de guardian
local eggScan  = { list = {}, time = 0 }
local gardScan = { list = {}, time = 0 }

local function rescanEggs()
	eggScan.time = os.clock()
	eggScan.list = {}
	local list = eggScan.list
	local match = makeMatcher(Config.Steal.EggPatterns)
	for _, d in ipairs(wsDescendants()) do
		if match(lowName(d)) and (d:IsA("BasePart") or d:IsA("Model")) then
			local inChar = LocalPlayer.Character and d:IsDescendantOf(LocalPlayer.Character)
			if not inChar then
				list[#list + 1] = d
			end
		end
	end
end

local function rescanGuardians()
	gardScan.time = os.clock()
	gardScan.list = {}
	local list = gardScan.list
	local match = makeMatcher(Config.Guardian.Names)
	for _, d in ipairs(wsDescendants()) do
		if d:IsA("Model") and match(lowName(d)) then
			local hrp = d:FindFirstChild("HumanoidRootPart", true) or d.PrimaryPart
			if hrp then
				list[#list + 1] = d
			end
		end
	end
end


-- [4] MODULO A - ESP DE OVOS (destaque + nome/raridade/valor/distancia)
local EggESP = { entries = {} }   -- inst -> { hl, box, bill, lab }
local espLines = {}               -- inst -> frame da tracer

local RARITY_WORDS = {
	"divine", "divino", "mythic", "mitic", "legendary", "legendario",
	"epic", "epico", "rare", "raro", "mutant", "mutante", "shiny",
	"brilhante", "golden", "dourado", "common", "comum",
}

local function anyEspOn()
	local e = Config.ESP
	return e.Eggs or e.Boxes or e.Tracers or e.ShowName or e.ShowRarity
		or e.ShowValue or e.ShowDistance
end

local function labelsOn()
	local e = Config.ESP
	return e.ShowName or e.ShowRarity or e.ShowValue or e.ShowDistance
end

local function parseRarity(name)
	local n = string.lower(name)
	for _, w in ipairs(RARITY_WORDS) do
		if n:find(w, 1, true) then
			return w
		end
	end
	return nil
end

local function labelText(inst, dist)
	local e = Config.ESP
	local out = {}
	if e.ShowName then
		out[#out + 1] = inst.Name
	end
	if e.ShowRarity then
		local ok, a = pcall(function()
			return inst:GetAttribute("Rarity")
		end)
		local r = (ok and a ~= nil and tostring(a)) or parseRarity(inst.Name)
		if r then
			out[#out + 1] = r
		end
	end
	if e.ShowValue then
		local ok, v = pcall(function()
			return inst:GetAttribute("Value") or inst:GetAttribute("Cash")
				or inst:GetAttribute("Price") or inst:GetAttribute("EggValue")
		end)
		if ok and v ~= nil then
			out[#out + 1] = tostring(v)
		end
	end
	if e.ShowDistance and dist then
		out[#out + 1] = math.floor(dist) .. "m"
	end
	return table.concat(out, "\n")
end

local function dropEntry(inst)
	local en = EggESP.entries[inst]
	if en then
		if en.hl then pcall(function() en.hl:Destroy() end) end
		if en.box then pcall(function() en.box:Destroy() end) end
		if en.bill then pcall(function() en.bill:Destroy() end) end
		EggESP.entries[inst] = nil
	end
	local ln = espLines[inst]
	if ln then
		pcall(function() ln:Destroy() end)
		espLines[inst] = nil
	end
end

local function dropAll()
	for inst in pairs(EggESP.entries) do
		dropEntry(inst)
	end
	for inst in pairs(espLines) do
		dropEntry(inst)
	end
end

local function buildEntry(inst)
	local e = Config.ESP
	local en = {}
	if e.Eggs then
		local hl = Instance.new("Highlight")
		hl.FillColor = e.EggColor
		hl.OutlineColor = e.EggColor
		hl.FillTransparency = 0.72
		hl.OutlineTransparency = 0.15
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = inst
		hl.Parent = uiRoot()
		en.hl = hl
	end
	if e.Boxes then
		local box = Instance.new("SelectionBox")
		box.Adornee = inst
		box.Color3 = e.EggColor
		box.LineThickness = 0.03
		box.Parent = uiRoot()
		en.box = box
	end
	if labelsOn() then
		local bill = Instance.new("BillboardGui")
		bill.Size = UDim2.fromOffset(150, 44)
		bill.StudsOffset = Vector3.new(0, 2.6, 0)
		bill.AlwaysOnTop = true
		bill.MaxDistance = e.MaxDistance
		bill.Adornee = inst
		local lab = Instance.new("TextLabel")
		lab.Size = UDim2.fromScale(1, 1)
		lab.BackgroundTransparency = 1
		lab.Font = Enum.Font.GothamBold
		lab.TextSize = 12
		lab.TextColor3 = Color3.new(1, 1, 1)
		lab.TextStrokeTransparency = 0.35
		lab.Text = ""
		lab.Parent = bill
		bill.Parent = uiRoot()
		en.bill = bill
		en.lab = lab
	end
	EggESP.entries[inst] = en
end

-- a chamam os toggles da pagina Visual: destroi tudo e o proximo
-- ciclo reconstrói com os flags atuais
function EggESP.apply()
	dropAll()
end

local function makeTracer()
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = Config.ESP.EggColor
	f.BackgroundTransparency = 0.35
	f.BorderSizePixel = 0
	f.Visible = false
	f.Parent = uiRoot()
	return f
end

local function updateTracers()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vs = cam.ViewportSize
	local from = Vector2.new(vs.X / 2, vs.Y)
	for inst, f in pairs(espLines) do
		local p = Move.instPos(inst)
		local pos, vis
		if p then
			pos, vis = cam:WorldToViewportPoint(p + Vector3.new(0, 2, 0))
		end
		if pos and vis then
			local to = Vector2.new(pos.X, pos.Y)
			local mid = (from + to) / 2
			f.Position = UDim2.fromOffset(mid.X, mid.Y)
			f.Size = UDim2.fromOffset((to - from).Magnitude, 2)
			f.Rotation = math.deg(math.atan2(to.Y - from.Y, to.X - from.X))
			f.Visible = true
		else
			f.Visible = false
		end
	end
end

-- "Egg Rarities to Show" (dropdown aba Local): ovos de outras
-- raridades ficam sem destaque, tag, caixa e tracer
local function espRarityPass(inst)
	local sel = Config.ESP.ShowRarities
	if not sel or sel == "All" then
		return true
	end
	local pats = Config.Filters.Rarity[sel]
	if not pats or #pats == 0 then
		return true
	end
	local ok, rar = pcall(function()
		return inst:GetAttribute("Rarity")
	end)
	local hay = string.lower(inst.Name .. " "
		.. ((ok and rar ~= nil) and tostring(rar) or ""))
	for _, p in ipairs(pats) do
		if hay:find(string.lower(p), 1, true) then
			return true
		end
	end
	return false
end

-- loop principal: varre, cria, atualiza e limpa
task.spawn(function()
	while ALIVE do
		task.wait(Config.ESP.UpdateRate)
		if not unlocked() or not anyEspOn() then
			if next(EggESP.entries) or next(espLines) then
				dropAll()
			end
			continue
		end
		rescanEggs()
		local root = Move.getRoot()
		local origin = root and root.Position or Vector3.zero
		local seen = {}
		for _, d in ipairs(eggScan.list) do
			local p = Move.instPos(d)
			if p and espRarityPass(d) and (p - origin).Magnitude <= Config.ESP.MaxDistance then
				seen[d] = true
				if not EggESP.entries[d] then
					buildEntry(d)
				end
			end
		end
		-- someu do raio / do mapa
		for inst in pairs(EggESP.entries) do
			if not seen[inst] then
				dropEntry(inst)
			end
		end
		-- tags: texto reconstruido a cada ciclo (distancia muda)
		for inst, en in pairs(EggESP.entries) do
			if en.lab then
				local p = Move.instPos(inst)
				local dist = p and (p - origin).Magnitude
				local text = labelText(inst, dist)
				if en.lab.Text ~= text then
					en.lab.Text = text
				end
				if en.bill then
					en.bill.Enabled = text ~= ""
				end
			end
		end
		-- tracers
		if Config.ESP.Tracers then
			for inst in pairs(seen) do
				if not espLines[inst] then
					espLines[inst] = makeTracer()
				end
			end
			for inst in pairs(espLines) do
				if not seen[inst] then
					dropEntry(inst)
				end
			end
			updateTracers()
		else
			for inst in pairs(espLines) do
				dropEntry(inst)
			end
		end
	end
end)

onUnload(function()
	dropAll()
end)

-- [4b] WEBHOOK DISCORD (HTTP do executor - fora do Roblox) ------
-- request() e game:HttpPost sao APIs do EXECUTOR: o trafego nao
-- passa pelo servidor do jogo (nunca usa HttpService aqui)
local Webhook = {}

function Webhook.send(content)
	local url = Config.Webhook.URL
	if url == "" or not Config.Webhook.Send then
		return false
	end
	local payload = HttpService:JSONEncode({
		content = tostring(content),
		username = "Esp House",
	})
	if type(request) == "function" then
		local ok = pcall(request, {
			Url = url,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = payload,
		})
		if ok then
			return true
		end
	end
	-- fallback: HttpPost do executor (mesma lib HTTP por baixo)
	local ok2 = pcall(function()
		game:HttpPost(url, payload, "application/json")
	end)
	if not ok2 then
		warn("[EspHouse] Webhook falhou - confira a URL")
	end
	return ok2
end

-- teste do botao "Test Webhook" (independe do master switch)
function Webhook.test()
	local url = Config.Webhook.URL
	if url == "" then
		return false, "sem URL"
	end
	local save = Config.Webhook.Send
	Config.Webhook.Send = true
	local ok = Webhook.send("Teste do Esp House 2em-1 - "
		.. os.date("%H:%M:%S"))
	Config.Webhook.Send = save
	return ok
end

-- [5] MODULO B - EGG STEAL (Safe Steal / bug da parede) ---------
local Steal = { busy = false }

-- filtros da pagina Farm (Raridade / Mutacao / Valor): texto do ovo,
-- do prompt e do atributo Rarity quando o jogo expoe um
local function filterText(inst)
	local n = lowName(inst)
	if inst:IsA("ProximityPrompt") then
		n = n .. " " .. string.lower(inst.ObjectText or "")
			.. " " .. string.lower(inst.ActionText or "")
	end
	local ok, rar = pcall(function()
		return inst:GetAttribute("Rarity")
	end)
	if ok and type(rar) == "string" then
		n = n .. " " .. string.lower(rar)
	end
	return n
end

local function matchAny(text, pats)
	for _, p in ipairs(pats or {}) do
		if text:find(string.lower(p), 1, true) then
			return true
		end
	end
	return false
end

local function passesFilters(inst)
	local f = Config.Steal
	local n = filterText(inst)
	if f.TargetRarity ~= "All"
		and not matchAny(n, Config.Filters.Rarity[f.TargetRarity]) then
		return false
	end
	if f.TargetMutation == "Mutated only"
		and not matchAny(n, Config.Filters.Mutation["Mutated only"]) then
		return false
	end
	if f.TargetValue ~= "Any"
		and not matchAny(n, Config.Filters.Value[f.TargetValue]) then
		return false
	end
	-- modos "Secret/Big/Rarest" da aba Main: uniao dos tipos ligados
	local modes = {}
	if f.ModeSecret then
		modes[#modes + 1] = "secret"
		modes[#modes + 1] = "secreto"
	end
	if f.ModeBig then
		modes[#modes + 1] = "big"
		modes[#modes + 1] = "grande"
		modes[#modes + 1] = "giant"
	end
	if f.ModeRarest then
		-- "mais raro" = palavras de raridade de topo
		modes[#modes + 1] = "rarest"
		modes[#modes + 1] = "divine"
		modes[#modes + 1] = "divino"
		modes[#modes + 1] = "eternal"
		modes[#modes + 1] = "eterno"
		modes[#modes + 1] = "mythic"
		modes[#modes + 1] = "mitic"
	end
	if #modes > 0 and not matchAny(n, modes) then
		return false
	end
	return true
end

-- "Run Speed (To Egg)": WalkSpeed boost SO durante o roubo;
-- guarda o valor original e restaura sempre (nunca escrita passiva)
local function runBoost(on)
	local hum = Move.getHumanoid()
	if on then
		if not hum then
			return
		end
		local target = Config.Steal.RunSpeed or 0
		if target <= (Config.Player.BaseWalkSpeed or 16) then
			return -- slider no minimo (16): nenhuma escrita
		end
		if target <= hum.WalkSpeed then
			return -- ja esta mais rapido (speed hack): nao abaixa
		end
		if stealth() then
			-- o teto do Modo Furtivo tambem vale pra corrida do roubo
			target = math.min(target, Config.Steal.StealthMaxSpeed)
		end
		Steal.savedSpeed = hum.WalkSpeed
		hum.WalkSpeed = target
	elseif Steal.savedSpeed then
		if hum then
			pcall(function()
				hum.WalkSpeed = Steal.savedSpeed
			end)
		end
		Steal.savedSpeed = nil
	end
end

function Steal.step()
	if Steal.busy then
		return false, "ocupado"
	end
	Steal.busy = true
	local status, grabbed = "ok", false
	local ok, err = pcall(function()
		local root = Move.getRoot()
		if not root then
			status = "noroot"
			return
		end
		local originCF = root.CFrame
		local originPos = root.Position

		-- filtro "Ovo alvo": se voce escolheu um ovo especifico na
		-- pagina Ovos (e "Somente ovo alvo" ligado), so esse vale
		local patterns = Config.Steal.EggPatterns
		if Config.Auto.TargetOnly and Config.Game.TargetEgg ~= "Todos" then
			patterns = { string.lower(Config.Game.TargetEgg) }
		end

		-- filtro "Target Area": Area 1/2/3 = procura os ovos perto da
		-- zona com aquele nome ("Best Unlocked" = sem filtro de origem)
		local origin = originPos
		if Config.Steal.TargetArea ~= "Best Unlocked" then
			local zone = Move.scanFor({ string.lower(Config.Steal.TargetArea) },
				{ radius = 100000 })
			if zone then
				origin = Move.instPos(zone) or originPos
			end
		end

		-- 1) acha o ovo mais proximo (nome do objeto OU texto do
		--    prompt, ex.: "Ovo / Roubar")
		local egg, eggPos = Move.findTarget(patterns, {
			origin = origin,
			radius = Config.Steal.ScanRange,
			excludeLocal = true,
		})
		-- filtros da pagina Farm: se o ovo escolhido nao passa
		-- (raridade/mutacao/valor), varre os candidatos ate achar um
		if egg and not passesFilters(egg) then
			egg, eggPos = nil, nil
			local match = makeMatcher(patterns)
			local best, bestD = nil, nil
			for _, d in ipairs(wsDescendants()) do
				if (d:IsA("BasePart") or d:IsA("Model")) and match(lowName(d))
					and passesFilters(d)
					and not (LocalPlayer.Character and d:IsDescendantOf(LocalPlayer.Character)) then
					local p = Move.instPos(d)
					if p then
						local dd = (p - origin).Magnitude
						if dd <= Config.Steal.ScanRange and (not bestD or dd < bestD) then
							best, bestD = d, dd
						end
					end
				end
			end
			if best then
				egg = best
				eggPos = Move.instPos(best)
			end
		end
		if not egg or not eggPos then
			status = "noegg"
			return
		end
		Steal.lastEggName = egg.Name
		-- corrida ate o ovo (restaurada no fim do step, logo abaixo)
		runBoost(true)

		-- duracao do tween expresso (studs/s, com jitter humano)
		local function heistDur(destPos)
			local speed = Config.Steal.QuickSpeed
			-- "Steal Speed" (slider 100..1000): multiplica a agilidade
			speed = speed * (0.6 + (Config.Steal.StealSpeed or 1000) / 1000 * 0.6)
			if stealth() then
				-- teto de seguranca do furtivo: rapido o bastante pra ser
				-- expresso, lento o bastante pra nao parecer teleport
				speed = math.min(speed * 0.5, Config.Steal.StealthMaxSpeed)
			end
			local here = Move.getRoot()
			local d = here and (destPos - here.Position).Magnitude or 50
			return math.clamp(d / speed, 0.35, 2.2) * jit(1)
		end
		-- CFrame no destino mantendo a facing atual
		local function atPos(p)
			local r = Move.getRoot()
			local rot = r and (r.CFrame - r.CFrame.Position) or CFrame.new()
			return CFrame.new(p + Vector3.new(0, 3, 0)) * rot
		end

		-- ===== ROUBO EXPRESSO (padrao) =====
		-- voa ate o ovo em segundos, pega, e volta pro ponto de
		-- onde voce tava - o boss te perde no caminho de volta
		if Config.Steal.QuickHeist then
			-- 2) ate o ovo
			Move.tweenTo(atPos(eggPos), heistDur(eggPos))
			task.wait(jit(0.25))

			-- 3) pega (prompt / click / toque)
			grabbed = Move.tryInteract(egg)
			if not grabbed then
				-- prompt so responde encostando: micro-abordagem
				Move.microTo(eggPos, microStep(), 1.5)
				grabbed = Move.tryInteract(egg)
			end
			task.wait(jit(0.4)) -- tempo pro jogo registrar a coleta

			if not grabbed then
				status = "nointeract"
			else
				-- 4) opcional: passa na saida/entrega antes de voltar
				if Config.Steal.WalkToExit then
					local exit = Move.scanFor(Config.Steal.ExitPatterns, {
						origin = originPos,
						radius = Config.Steal.ExitRange,
						avoid = Config.Teleport.AvoidPatterns,
					})
					if exit then
						local ep = Move.instPos(exit)
						Move.tweenTo(atPos(ep), heistDur(ep))
						task.wait(jit(0.3))
					else
						status = "noexit" -- ovo pego, mas sem saida no raio
					end
				end
			end

			-- 5) volta automatica ao ponto original
			if Config.Steal.ReturnHome then
				if Move.getRoot() then
					Move.tweenTo(originCF, heistDur(originPos))
				end
			end
			Steal.lastHeist = os.clock()
			return
		end

		-- ===== CAMINHADA LENTA (QuickHeist desligado) =====
		-- 2) se o ovo estiver longe, caminha ate perto ANTES de
		--    interagir: prompt forcado a distancia e rejeitado por
		--    muitos jogos (era por isso que "nao fazia nada")
		if (eggPos - root.Position).Magnitude > 12 then
			Move.microTo(eggPos, microStep(), 10) -- 10s ≈ 180 studs
			root = Move.getRoot() or root
		end

		-- 3) interage (prompt / click / toque)
		local interacted = Move.tryInteract(egg)

		-- 4) "bug da parede": encosta o personagem na parede mais
		--    proxima em micro-passos de CFrame, mantendo o ovo entre
		--    voce e a parede (a IA do guardiao nao alcanca o objeto)
		local wall = Move.nearestWall(eggPos, Config.Steal.WallScanRange)
			or Move.nearestWall(root.Position, Config.Steal.WallScanRange)
		if wall then
			local hug = wall.Position + wall.Normal * Config.Steal.WallSnapOffset
			hug = Vector3.new(hug.X, root.Position.Y, hug.Z)
			Move.microTo(hug, microStep(), 2.5)
			task.wait(jit(Config.Steal.HoldTime))
			Move.tryInteract(egg)
		elseif not interacted then
			-- sem resposta: caminha ate encostar de vez no ovo
			Move.microTo(eggPos, microStep(), 2.0)
		end

		-- 5) leva o ovo ate a saida/entrega (micro-passos, o
		--    Distance Ghost protege o caminho durante a fuga)
		if Config.Steal.WalkToExit then
			local root2 = Move.getRoot()
			if root2 then
				local exit = Move.scanFor(Config.Steal.ExitPatterns, {
					origin = root2.Position,
					radius = Config.Steal.ExitRange,
					avoid = Config.Teleport.AvoidPatterns,
				})
				if exit then
					Move.microTo(Move.instPos(exit), microStep(), 14)
				else
					status = "noexit" -- ovo pego mas sem para onde levar
				end
			end
		end
	end)
	Steal.busy = false
	runBoost(false) -- restaura o WalkSpeed original em todo fim de step
	if not ok then
		warn("[EspHouse] Steal: " .. tostring(err))
		return false, "erro"
	end
	if status ~= "ok" then
		return false, status
	end
	return true
end

-- condicao dos modos de roubo da aba Main (qualquer um liga o loop)
local function stealOn()
	return Config.Steal.Enabled or Config.Steal.ModeSecret
		or Config.Steal.ModeBig or Config.Steal.ModeRarest
end

-- "Steal Speed" (100..1000) -> intervalo entre tentativas 1.25s..0.35s
local function stealInterval()
	local base = Config.Steal.ScanInterval
		* (1.35 - (Config.Steal.StealSpeed or 1000) / 1000)
	return math.clamp(base, 0.35, 2.5)
end

task.spawn(function()
	-- espera um pouco apos o carregamento (evita acao imediata = flag)
	local startAt = os.clock() + bootDelay()
	local lastWhy, lastAt, lastOk = nil, 0, 0
	while ALIVE do
		if (stealOn() or Config.Steal.CarryHome)
			and unlocked() and os.clock() >= startAt
			and os.clock() >= (Steal.firstAt or 0) then
			-- COM O OVO NA MAO: volta pra base. Com Modo Furtivo usa
			-- tween curto - teleport SECO com ovo na mao foi o que
			-- dispara o BAC (kick ~2s depois, visto no video). Sem
			-- furtivo, snap instantaneo (como pedido, arriscado).
			if Config.Steal.CarryHome and Move.isCarrying()
				and (os.clock() - (Steal.lastCarry or -9)) >= Config.Steal.CarryCooldown then
				Steal.lastCarry = os.clock()
				local instant = not stealth()
				local okTP, msg = Teleport.go(Config.Teleport.ExactBase,
					Config.Teleport.BasePatterns, 900, true, true, instant)
				if okTP then
					if toast then
						toast(instant and "Ovo na mao: teleportado pra base!"
							or "Ovo na mao: indo pra base, rapidinho...")
					end
				elseif msg and msg ~= "personagem nao encontrado" and toast then
					toast(msg) -- ex.: "local nao encontrado - Diagnosticar"
				end
				task.wait(jit(stealInterval()))
			elseif stealOn() then
				local okStep, why = Steal.step()
				if okStep then
					lastWhy = nil
					-- aba Webhook: avisa a cada ovo (se ligado)
					if Config.Webhook.NotifyStolen and Steal.lastEggName then
						Webhook.send("Ovo roubado: **"
							.. Steal.lastEggName .. "**")
					end
					-- avisa o sucesso de vez em quando (feedback)
					if toast and (os.clock() - lastOk) > 60 then
						lastOk = os.clock()
						toast("Steal: ovo roubado e voltei ao seu ponto!")
					end
				elseif why and why ~= "ocupado" and why ~= "noroot"
					and why ~= lastWhy and (os.clock() - lastAt) > 25 then
					lastWhy, lastAt = why, os.clock()
					if why == "noegg" and toast then
						toast("Steal: nenhum ovo no raio - clique em Diagnosticar (Ajustes > Script)")
					elseif why == "noexit" and toast then
						toast("Steal: sem saida/entrega no raio - clique em Diagnosticar (Ajustes > Script)")
					elseif why == "nointeract" and toast then
						toast("Steal: ovo sem prompt - clique em Diagnosticar (Ajustes > Script)")
					elseif why == "erro" and toast then
						toast("Steal com erro - veja o Output do executor")
					end
				end
				task.wait(jit(stealInterval()))
			else
				task.wait(0.4)
			end
		else
			task.wait(0.4)
		end
	end
end)

-- [6] MODULO B - GUARDIAN BYPASS (Ghost + Anti-Follow) ----------
local Guardian = { lastBlink = 0, snap = nil }

function Guardian.restoreCollision()
	local snap = Guardian.snap
	if snap then
		for _, item in ipairs(snap.parts) do
			if item.part.Parent then
				pcall(function()
					item.part.CanCollide = item.was
				end)
			end
		end
		Guardian.snap = nil
	end
end

local function disableCollision(model)
	Guardian.restoreCollision()
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			parts[#parts + 1] = { part = d, was = d.CanCollide }
			pcall(function()
				d.CanCollide = false
			end)
		end
	end
	Guardian.snap = { model = model, parts = parts }
end

-- blink: deslocamento curto distribuido em varios frames
-- (nao e teleport seco; quebra o pathfinding da IA do guardiao)
function Guardian.blink(fromPos)
	local root = Move.getRoot()
	if not root then
		return
	end
	local away = Vector3.new(root.Position.X - fromPos.X, 0, root.Position.Z - fromPos.Z)
	if away.Magnitude < 0.1 then
		local look = root.CFrame.LookVector
		away = Vector3.new(-look.X, 0, -look.Z)
	end
	if away.Magnitude < 0.1 then
		return
	end
	away = away.Unit
	local side = Vector3.new(-away.Z, 0, away.X) * (math.random() >= 0.5 and 1 or -1)
	local dir = away + side * 0.5
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude > 0 then
		dir = dir.Unit
	else
		return
	end
	local steps = Config.Guardian.BlinkSteps
	if stealth() then
		-- fraciona o blink para nao passar de um passo humano por frame
		steps = math.max(steps, math.ceil(
			Config.Guardian.BlinkDistance / Config.Stealth.MicroStep
		))
	end
	local per = Config.Guardian.BlinkDistance / steps
	task.spawn(function()
		for _ = 1, steps do
			if not ALIVE then
				return
			end
			local hr = Move.getRoot()
			if not hr then
				return
			end
			local v = hr.AssemblyLinearVelocity
			hr.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
			hr.CFrame = hr.CFrame + dir * per
			RunService.RenderStepped:Wait()
		end
	end)
end

hook(RunService.Heartbeat, function()
	if not ALIVE or not unlocked() then
		return
	end
	local cfg = Config.Guardian
	if not (cfg.Ghost or cfg.AntiFollow) then
		if Guardian.snap then
			Guardian.restoreCollision()
		end
		return
	end
	local root = Move.getRoot()
	if not root then
		return
	end

	local nearest, nearD = nil, math.huge
	for _, m in ipairs(gardScan.list) do
		if m.Parent then
			local hrp = m:FindFirstChild("HumanoidRootPart", true) or m.PrimaryPart
			if hrp then
				local d = (hrp.Position - root.Position).Magnitude
				if d < nearD then
					nearest, nearD = m, d
				end
			end
		end
	end
	if not nearest then
		if Guardian.snap then
			Guardian.restoreCollision()
		end
		return
	end

	-- Anti-Follow: so desliga a colisao enquanto o guardiao esta
	-- perto; restaura o CanCollide original em seguida
	if cfg.AntiFollow and nearD <= cfg.FollowRadius then
		if not Guardian.snap or Guardian.snap.model ~= nearest then
			disableCollision(nearest)
		end
	elseif Guardian.snap then
		Guardian.restoreCollision()
	end

	-- Distance Ghost (pausa durante o roubo expresso: o tween do
	-- roubo e o blink brigariam pelo mesmo CFrame do personagem)
	if cfg.Ghost and not Steal.busy and nearD <= cfg.DangerDistance
		and (os.clock() - Guardian.lastBlink) >= jit(cfg.BlinkCooldown) then
		Guardian.lastBlink = os.clock()
		local hrp = nearest:FindFirstChild("HumanoidRootPart", true) or nearest.PrimaryPart
		if hrp then
			Guardian.blink(hrp.Position)
		end
	end
end)

onUnload(function()
	Guardian.restoreCollision()
end)

-- [7] MODULO C - AUTOMATIONS (hatch, merge, coins, compras) -----
local Auto = {}

local function nearestTo(patterns, radius)
	local root = Move.getRoot()
	if not root then
		return nil
	end
	-- nome do objeto OU texto do prompt (ex.: "Chocar", "Comprar")
	local inst = Move.findTarget(patterns, {
		origin = root.Position,
		radius = radius,
		excludeLocal = true,
	})
	return inst
end

local function actHatch()
	local inst = nearestTo(Config.Auto.HatchPatterns, Config.Auto.BuyRadius)
	if inst then
		Move.tryInteract(inst)
	end
end

local function actMerge()
	if Config.Auto.MergeRemote ~= "" then
		local rs = game:GetService("ReplicatedStorage")
		local rem = rs:FindFirstChild(Config.Auto.MergeRemote, true)
		if rem and rem:IsA("RemoteEvent") then
			pcall(function()
				rem:FireServer()
			end)
			return
		end
	end
	local inst = nearestTo(Config.Auto.MergePatterns, Config.Auto.BuyRadius)
	if inst then
		Move.tryInteract(inst)
	end
end

local function actCoins()
	local root = Move.getRoot()
	if not root then
		return
	end
	local inst = Move.scanFor(Config.Auto.CoinPatterns, {
		origin = root.Position,
		radius = Config.Auto.CollectRadius,
		excludeLocal = true,
	})
	if inst then
		if not Move.tryInteract(inst) then
			Move.microTo(Move.instPos(inst), microStep(), 1.2)
		end
	end
end

local function actBuyEgg()
	local inst
	if Config.Auto.TargetOnly and Config.Game.TargetEgg ~= "Todos"
		and Config.Game.TargetEgg ~= "" then
		inst = nearestTo({ string.lower(Config.Game.TargetEgg) }, Config.Auto.BuyRadius)
	end
	if not inst then
		-- prompt "Comprar/buy" primeiro, depois o ovo em si
		inst = nearestTo(Config.Auto.BuyPatterns, Config.Auto.BuyRadius)
			or nearestTo(Config.Steal.EggPatterns, Config.Auto.BuyRadius)
	end
	if inst then
		Move.tryInteract(inst)
	end
end

local function actBuyBelt()
	local inst = nearestTo(Config.Auto.BeltPatterns, Config.Auto.BuyRadius)
	if inst then
		Move.tryInteract(inst)
	end
end

local function actBuyTrail()
	local inst = nearestTo(Config.Auto.TrailPatterns, Config.Auto.BuyRadius)
	if inst then
		Move.tryInteract(inst)
	end
end

Auto.actions = {
	Hatch = actHatch, Merge = actMerge, Coins = actCoins,
	BuyEgg = actBuyEgg, BuyBelt = actBuyBelt, BuyTrail = actBuyTrail,
}

-- clica num botao da GUI do jogo (quando nao existe prompt): usa o
-- VirtualInputManager do proprio Roblox; pcall porque nem todo
-- executor expoe a API. Ignora a nossa UI (gui) no scan.
local function guiClick(pats)
	local okV, VIM = pcall(function()
		return game:GetService("VirtualInputManager")
	end)
	if not okV or not VIM then
		return false
	end
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then
		return false
	end
	for _, d in ipairs(pg:GetDescendants()) do
		if d:IsA("TextButton") and d.Visible and not d:IsDescendantOf(gui) then
			local txt = string.lower(d.Text or "")
			if txt ~= "" and matchAny(txt, pats) then
				local pos = d.AbsolutePosition + d.AbsoluteSize / 2
				local function send(down)
					pcall(function()
						VIM:SendMouseButtonEvent(pos.X, pos.Y, 0, down, game, 0)
					end)
				end
				send(true)
				task.wait(0.05)
				send(false)
				return true
			end
		end
	end
	return false
end

-- acao generica: prompt mais proximo com o texto esperado
local function actPrompt(pats, radius)
	local inst = nearestTo(pats, radius or Config.Auto.Radius)
	if inst then
		return Move.tryInteract(inst)
	end
	return false
end

local function actEquipBest()
	if actPrompt(Config.Auto.EquipPatterns) then
		return
	end
	guiClick(Config.Auto.EquipPatterns)
end

local function actPetUpgrade()
	actPrompt(Config.Auto.UpgradePatterns, Config.Auto.BuyRadius)
end

local function actSell()
	-- "Sell up to": com tier > Common, prefere a estacao daquele tier
	local tier = Config.Auto.SellUpTo
	if tier ~= "Common" then
		local inst = nearestTo({ string.lower(tier) }, Config.Auto.BuyRadius)
		if inst then
			Move.tryInteract(inst)
			return
		end
	end
	actPrompt(Config.Auto.SellPatterns, Config.Auto.BuyRadius)
end

local function actTrain()
	local inst = nearestTo(Config.Auto.TrainPatterns, Config.Auto.Radius)
	if not inst then
		return
	end
	if inst:IsA("ProximityPrompt") then
		Move.tryInteract(inst)
	else
		-- esteira costuma ser plataforma: sobe em cima e o jogo treina
		local p = Move.instPos(inst)
		local root = Move.getRoot()
		if p and root and (p - root.Position).Magnitude > 6 then
			Move.microTo(p, microStep(), 3)
		end
	end
end

local function actBuyUpgrades()
	if not actPrompt(Config.Auto.BuyUpgradePatterns) then
		actPrompt(Config.Auto.BuyPatterns, Config.Auto.BuyRadius)
	end
end

local function actEvent()
	if not actPrompt(Config.Auto.EventPatterns) then
		guiClick(Config.Auto.EventPatterns)
	end
end

local function actBoss()
	actPrompt(Config.Auto.BossPatterns, Config.Auto.Radius)
end

local function actClaim()
	if not actPrompt(Config.Auto.ClaimPatterns) then
		guiClick(Config.Auto.ClaimPatterns)
	end
end

task.spawn(function()
	local t = {}
	local keys = {
		"Hatch", "Merge", "Coins", "BuyEgg", "BuyBelt", "BuyTrail",
		"EquipBest", "Upgrade", "Sell", "Train", "BuyUpgrades",
		"Event", "Boss", "Claim",
	}
	for _, k in ipairs(keys) do
		t[k] = 0
	end
	-- espera aleatoria apos o carregamento (acao imediata = flag tipica)
	local startAt = os.clock() + bootDelay()

	-- roda a acao se o toggle estiver ligado e o delay tiver passado
	local function runIf(key, on, delay, fn)
		if not on then
			return
		end
		local now = os.clock()
		if (now - t[key]) >= delay then
			t[key] = now
			if stealth() then
				task.wait(gap()) -- espaca as interacoes (anti-spam)
			end
			local ok, err = pcall(fn)
			if not ok then
				warn("[EspHouse] Auto." .. key .. ": " .. tostring(err))
			end
		end
	end

	while ALIVE do
		if unlocked() and os.clock() >= startAt then
			local inter = jit(Config.Auto.InteractDelay)
			local buy = jit(math.max(0.5, Config.Auto.Delay))
			-- pagina Pets
			runIf("Hatch", Config.Auto.Hatch, inter, actHatch)
			runIf("EquipBest", Config.Auto.EquipBest, buy, actEquipBest)
			runIf("Merge", Config.Auto.Merge, inter, actMerge)
			runIf("Upgrade", Config.Auto.Upgrade, inter, actPetUpgrade)
			runIf("Sell", Config.Auto.Sell, buy, actSell)
			-- pagina Progresso
			runIf("Train", Config.Auto.Train, inter, actTrain)
			runIf("BuyTrail", Config.Auto.BuyTrail, buy, actBuyTrail)
			runIf("BuyUpgrades", Config.Auto.BuyUpgrades, buy, actBuyUpgrades)
			-- pagina Eventos
			runIf("Event", Config.Auto.Event, buy, actEvent)
			runIf("Boss", Config.Auto.Boss, jit(0.8), actBoss)
			runIf("Claim", Config.Auto.Claim, buy, actClaim)
			-- legados v1.2 (sem widget nesta UI, mas disponiveis na API)
			runIf("Coins", Config.Auto.Coins, inter, actCoins)
			runIf("BuyEgg", Config.Auto.BuyEgg, buy, actBuyEgg)
			runIf("BuyBelt", Config.Auto.BuyBelt, buy, actBuyBelt)
			task.wait(jit(0.25))
		else
			task.wait(0.5)
		end
	end
end)

-- [8] MODULO C - PLAYER (speed seguro, jump, noclip, antiafk) --
local PlayerX = {}

-- speed booster gradual: nunca da um salto seco de WalkSpeed
-- REGRA ANTI-KICK: enquanto o jogador nao mexer no slider, o script
-- NUNCA escreve no Humanoid (o jogo fica no controle total)
hook(RunService.Heartbeat, function(dt)
	if not ALIVE or not unlocked() then
		return
	end
	local cfg = Config.Player
	if not cfg.SpeedCustom then
		return -- padrao intocado: nenhuma escrita, nenhuma flag
	end
	local hum = Move.getHumanoid()
	if not hum then
		return
	end
	local target = speedTarget() -- teto do Modo Furtivo ja aplicado
	local cur = hum.WalkSpeed
	-- guarda o valor original do jogo na 1a escrita (unload restaura)
	if PlayerX.origSpeed == nil then
		PlayerX.origSpeed = cur
	end
	if cur < target then
		hum.WalkSpeed = math.min(target, cur + cfg.SpeedRamp * dt)
	elseif cur > target then
		hum.WalkSpeed = target -- diminuir e seguro/nao e detectado
	end
end)

-- aplica jump power na hora (slider) e ao respawn
function PlayerX.applyJump()
	if not Config.Player.JumpCustom then
		return -- padrao intocado: nao toca em UseJumpPower/JumpPower
	end
	local hum = Move.getHumanoid()
	if hum then
		-- guarda o original do jogo na 1a escrita (unload restaura)
		if PlayerX.origJump == nil then
			PlayerX.origJump = { use = hum.UseJumpPower, power = hum.JumpPower }
		end
		hum.UseJumpPower = true
		hum.JumpPower = Config.Player.JumpPower
	end
end

hook(LocalPlayer.CharacterAdded, function(char)
	local hum = char:WaitForChild("Humanoid", 5)
	if hum then
		-- personagem novo: original recapturado daqui (nunca restaurar
		-- valores de outro humanoid)
		PlayerX.origSpeed = nil
		PlayerX.origJump = nil
		if Config.Player.JumpCustom then
			hum.UseJumpPower = true
			hum.JumpPower = Config.Player.JumpPower
		end
		if Config.Player.SpeedCustom and speedTarget() > Config.Player.BaseWalkSpeed then
			hum.WalkSpeed = Config.Player.BaseWalkSpeed -- deixa o ramp subir
		end
	end
	if PlayerX.noclipSnap then
		PlayerX.noclipSnap = nil -- personagem novo, snapshot antigo nao serve
	end
end)

-- infinite jump
hook(UIS.JumpRequest, function()
	if not ALIVE or not unlocked() or not Config.Player.InfiniteJump then
		return
	end
	local hum = Move.getHumanoid()
	if hum then
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end)

-- noclip com snapshot do CanCollide (restauravel no unload)
local function noclipOff()
	local snap = PlayerX.noclipSnap
	if snap then
		for _, item in ipairs(snap) do
			if item.part.Parent then
				pcall(function()
					item.part.CanCollide = item.was
				end)
			end
		end
		PlayerX.noclipSnap = nil
	end
end

hook(RunService.Heartbeat, function()
	if not ALIVE or not unlocked() then
		return
	end
	local char = LocalPlayer.Character
	if not char then
		return
	end
	if Config.Player.Noclip then
		if not PlayerX.noclipSnap then
			local snap = {}
			for _, p in ipairs(char:GetDescendants()) do
				if p:IsA("BasePart") then
					snap[#snap + 1] = { part = p, was = p.CanCollide }
				end
			end
			PlayerX.noclipSnap = snap
		end
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") and p.CanCollide then
				p.CanCollide = false
			end
		end
	elseif PlayerX.noclipSnap then
		noclipOff()
	end
end)

-- anti afk
hook(LocalPlayer.Idled, function()
	if ALIVE and unlocked() and Config.Player.AntiAFK then
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new(0, 0))
		end)
	end
end)

onUnload(function()
	noclipOff()
	-- restaura APENAS o que o script escreveu (se nunca mexeu, nao
	-- toca no Humanoid - regra anti-kick de escrita zero)
	local hum = Move.getHumanoid()
	if hum then
		if PlayerX.origSpeed then
			hum.WalkSpeed = PlayerX.origSpeed
		end
		if PlayerX.origJump then
			hum.UseJumpPower = PlayerX.origJump.use
			hum.JumpPower = PlayerX.origJump.power
		end
	end
end)

-- [8b] PLAYER - FLY / GOD / ANTI TRAP (extras da UI nova) --------
-- fly: CFrame relativo a camera, velocidade zerada a cada frame
local flyConn = nil

local function setFly(on)
	if flyConn then
		pcall(function()
			flyConn:Disconnect()
		end)
		flyConn = nil
	end
	if not on or not ALIVE then
		return
	end
	flyConn = hook(RunService.RenderStepped, function(dt)
		if not ALIVE or not unlocked() or not Config.Player.Fly then
			return
		end
		local root = Move.getRoot()
		if not root then
			return
		end
		local cf = workspace.CurrentCamera.CFrame
		local dir = Vector3.zero
		if UIS:IsKeyDown(Enum.KeyCode.W) then dir = dir + cf.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.S) then dir = dir - cf.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + cf.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - cf.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
		if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end
		if dir.Magnitude > 0 then
			root.CFrame = root.CFrame + dir.Unit * Config.Player.FlySpeed * dt
		end
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)
end

-- god local: mantem a vida cheia no cliente. O dano vem do servidor,
-- entao segura o que da pra segurar sem escrita passiva
task.spawn(function()
	while ALIVE do
		task.wait(0.5)
		if unlocked() and Config.Player.God then
			local hum = Move.getHumanoid()
			if hum and hum.Health < hum.MaxHealth then
				hum.Health = hum.MaxHealth
			end
		end
	end
end)

-- anti trap: desliga a colisao local das armadilhas (volta ao normal
-- quando voce desliga o toggle ou descarrega o script)
local trapSnap = nil

local function trapOff()
	if trapSnap then
		for _, item in ipairs(trapSnap) do
			if item.p.Parent then
				pcall(function()
					item.p.CanCollide = item.w
				end)
			end
		end
		trapSnap = nil
	end
end

task.spawn(function()
	local match = makeMatcher(Config.Game.TrapPatterns)
	while ALIVE do
		task.wait(0.8)
		if unlocked() and Config.Player.AntiTrap then
			if not trapSnap then
				local snap = {}
				for _, d in ipairs(wsDescendants()) do
					if d:IsA("BasePart") and match(lowName(d)) then
						snap[#snap + 1] = { p = d, w = d.CanCollide }
						pcall(function()
							d.CanCollide = false
						end)
					end
				end
				trapSnap = snap
			end
		elseif trapSnap then
			trapOff()
		end
	end
end)

onUnload(trapOff)
onUnload(function()
	setFly(false)
end)

-- [8c] INSTANT PROXIMITY PROMPT ---------------------------------
-- tira o tempo de segurar o botao (HoldDuration=0 so no cliente;
-- guarda os valores originais e restaura no unload/desligar)
local instantSnap = nil

local function instantOff()
	if instantSnap then
		for _, item in ipairs(instantSnap) do
			if item.pp.Parent then
				pcall(function()
					item.pp.HoldDuration = item.was
				end)
			end
		end
		instantSnap = nil
	end
end

local function instantApply()
	instantOff()
	if not Config.Player.InstantPrompt then
		return
	end
	local snap = {}
	for _, d in ipairs(wsDescendants()) do
		if d:IsA("ProximityPrompt") then
			snap[#snap + 1] = { pp = d, was = d.HoldDuration }
			pcall(function()
				d.HoldDuration = 0
			end)
		end
	end
	instantSnap = snap
end

hook(Workspace.DescendantAdded, function(d)
	if ALIVE and unlocked() and Config.Player.InstantPrompt
		and d:IsA("ProximityPrompt") then
		pcall(function()
			d.HoldDuration = 0
		end)
	end
end)

onUnload(instantOff)

-- [8d] ANTI RAGDOLL ---------------------------------------------
-- mantem o personagem de pe ao cair (Ragdoll/Physics -> GettingUp).
-- Apenas cliente: estado de Humanoid nao gera flag de escrita
local ragHum = nil

local function ragdollRefresh()
	local hum = Move.getHumanoid()
	ragHum = hum
	if not hum then
		return
	end
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,
			not Config.Player.AntiRagdoll)
	end)
	if Config.Player.AntiRagdoll then
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
	end
end

hook(LocalPlayer.CharacterAdded, function()
	task.wait(0.5)
	ragdollRefresh()
end)
task.spawn(ragdollRefresh)

hook(RunService.Heartbeat, function()
	if not ALIVE or not unlocked() or not Config.Player.AntiRagdoll then
		return
	end
	if ragHum and ragHum.Parent then
		local st = ragHum:GetState()
		if st == Enum.HumanoidStateType.Physics
			or st == Enum.HumanoidStateType.Ragdoll then
			pcall(function()
				ragHum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end)
		end
	end
end)

-- [8e] ANTI REJOIN ----------------------------------------------
-- se o jogo tentar te mudar de servidor: avisa e (com URL configurada)
-- deixa o script pronto pra voltar sozinho via queue_on_teleport
hook(LocalPlayer.OnTeleport, function()
	if not (ALIVE and unlocked() and Config.Player.AntiRejoin) then
		return
	end
	print("[EspHouse] Anti Rejoin: jogo tentou trocar de servidor")
	local url = Config.Player.ReexecURL
	if url ~= "" and type(queue_on_teleport) == "function" then
		pcall(queue_on_teleport,
			"loadstring(game:HttpGet('" .. url .. "'))()")
		print("[EspHouse] Anti Rejoin: reexecucao enfileirada")
	end
end)

-- [8f] TPWALK ----------------------------------------------------
-- deslocamento curto por frame na direcao do andar (teleporte
-- "encurtado" controlado): raycast na frente nao atravessa parede,
-- teto do Modo Furtivo vale, pausa durante o roubo/voo
hook(RunService.Heartbeat, function(dt)
	if not ALIVE or not unlocked() or not Config.Player.TPWalk then
		return
	end
	if Steal.busy or Config.Player.Fly then
		return
	end
	local hum = Move.getHumanoid()
	local root = Move.getRoot()
	if not hum or not root or hum.Health <= 0 then
		return
	end
	local md = hum.MoveDirection
	if md.Magnitude < 0.05 then
		return
	end
	local speed = Config.Player.TPWalkSpeed or 60
	if stealth() then
		speed = math.min(speed, Config.Steal.StealthMaxSpeed)
	end
	local dir = Vector3.new(md.X, 0, md.Z)
	if dir.Magnitude < 0.01 then
		return
	end
	dir = dir.Unit
	local stepLen = speed * dt
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LocalPlayer.Character }
	local hit = Workspace:Raycast(root.Position, dir * (stepLen + 1.5), params)
	if hit then
		return -- parede na frente: deixa a caminhada normal agir
	end
	root.CFrame = root.CFrame + dir * stepLen
end)

-- [9] TELEPORT (Tween suave, sem teleport seco) -----------------
local Teleport = {}

function Teleport.go(exactPath, patterns, radius, allowSpawn, force, instant)
	if stealth() and not force then
		return false, "Modo Furtivo ativo: teleport bloqueado (desligue em Configuracoes > Seguranca)"
	end
	local pos = nil
	local exact = Move.resolveExact(exactPath)
	if exact then
		pos = Move.instPos(exact)
	else
		local root = Move.getRoot()
		if root then
			local inst = Move.scanFor(patterns, {
				origin = root.Position,
				radius = radius or 900,
				avoid = Config.Teleport.AvoidPatterns,
			})
			if inst then
				pos = Move.instPos(inst)
			end
			-- fallback: se nao achou o padrao, vai pro spawn mais proximo
			-- (na maioria dos jogos a "base" e o spawn)
			if not pos and allowSpawn then
				local sp = Move.scanFor({ "spawn", "spawnpoint" }, {
					origin = root.Position,
					radius = 6000,
				})
				if sp then
					pos = Move.instPos(sp)
				end
			end
		end
	end
	if not pos then
		return false, "local nao encontrado - veja Diagnosticar (Ajustes > Script)"
	end
	local root = Move.getRoot()
	if not root then
		return false, "personagem nao encontrado"
	end
	local target = CFrame.new(pos + Vector3.new(0, 4, 0)) * (root.CFrame - root.CFrame.Position)
	if instant then
		Move.snapTo(target) -- milissegundos (um unico set de CFrame)
		return true, "teleportado (instantaneo)"
	end
	-- duracao escala com a distancia (studs/s constante): um tween de
	-- duracao fixa pra base longe vira velocidade absurda = flag
	local dist = (pos - root.Position).Magnitude
	local speed = Config.Teleport.MaxSpeed
	if stealth() then
		speed = math.min(speed, Config.Teleport.StealthSpeed)
	end
	Move.tweenTo(target, math.clamp(dist / speed, 0.35, 4))
	return true, "teleportado"
end

-- [9b] BEST EGG (quadro do melhor ovo + teleguiado) -------------
-- UI.setBoard e uma funcao da interface [10]: referencia adiantada
-- (mesmo truque do "toast" declarado la em cima)
local UIBoardUpdate = nil

local BestEgg = { lastGo = 0 }

-- valor do ovo: atributos Value/Cash/Price/EggValue ou numero no
-- nome ("Sacred Moth 35.97M" -> 35970000)
local function eggValue(inst)
	local ok, v = pcall(function()
		return inst:GetAttribute("Value") or inst:GetAttribute("Cash")
			or inst:GetAttribute("Price") or inst:GetAttribute("EggValue")
	end)
	local MULT = { k = 1e3, m = 1e6, b = 1e9 }
	if ok and type(v) == "number" then
		return v
	end
	if ok and type(v) == "string" then
		local num, suf = v:match("([%d%,%.]+)%s*([kKmMbB]?)")
		local n = num and tonumber((num:gsub(",", "")))
		if n then
			return n * (MULT[string.lower(suf or "")] or 1)
		end
	end
	local num, suf = inst.Name:match("([%d%.]+)%s*([kKmMbB]?)")
	local n = num and tonumber(num)
	if n then
		return n * (MULT[string.lower(suf or "")] or 1)
	end
	return 0
end

-- raridade crua do ovo (atributo Rarity ou palavra no nome)
local function eggRarity(inst)
	local ok, rar = pcall(function()
		return inst:GetAttribute("Rarity")
	end)
	if ok and rar ~= nil and tostring(rar) ~= "" then
		return string.lower(tostring(rar))
	end
	return parseRarity(inst.Name) or ""
end

-- chips "Rarity Filter": nenhum chip ativo = todas as raridades
local CHIP_WORDS = {
	Legendary = { "legendary", "legendario" },
	Secret = { "secret", "secreto" },
	Eternal = { "eternal", "eterno" },
	Divine = { "divine", "divino" },
}

local function bestPass(inst)
	local anyOn = false
	for _, on in pairs(Config.BestEgg.Filter) do
		if on then
			anyOn = true
			break
		end
	end
	if not anyOn then
		return true
	end
	local r = eggRarity(inst)
	if r == "" then
		return false -- sem raridade identificavel: fora do filtro
	end
	for chip, on in pairs(Config.BestEgg.Filter) do
		if on and CHIP_WORDS[chip] then
			for _, w in ipairs(CHIP_WORDS[chip]) do
				if r:find(w, 1, true) then
					return true
				end
			end
		end
	end
	return false
end

-- lista dos ovos por valor (maior primeiro) dentro do Range
function BestEgg.scan()
	rescanEggs()
	local list = {}
	local root = Move.getRoot()
	local origin = root and root.Position or Vector3.zero
	for _, d in ipairs(eggScan.list) do
		if not (LocalPlayer.Character
			and d:IsDescendantOf(LocalPlayer.Character)) then
			local p = Move.instPos(d)
			if p and (p - origin).Magnitude <= Config.BestEgg.Range
				and bestPass(d) then
				list[#list + 1] = {
					inst = d,
					name = d.Name,
					rarity = eggRarity(d),
					value = eggValue(d),
				}
			end
		end
	end
	table.sort(list, function(a, b)
		return a.value > b.value
	end)
	return list
end

-- teleguiado: tween pro melhor ovo (nunca teleport seco - o teto
-- do Modo Furtivo vale aqui tambem)
function BestEgg.go()
	local list = BestEgg.scan()
	if #list == 0 then
		if toast then
			toast("Best Egg: nenhum ovo no raio (clique em Diagnosticar)")
		end
		return false
	end
	local best = list[1]
	local root = Move.getRoot()
	if not root then
		return false
	end
	local pos = Move.instPos(best.inst)
	if not pos then
		return false
	end
	BestEgg.lastGo = os.clock()
	local target = CFrame.new(pos + Vector3.new(0, 3, 0))
		* (root.CFrame - root.CFrame.Position)
	local speed = stealth() and Config.Teleport.StealthSpeed
		or Config.Teleport.MaxSpeed
	local dist = (pos - root.Position).Magnitude
	Move.tweenTo(target, math.clamp(dist / speed, 0.35, 4) * jit(1))
	if toast then
		toast("Best Egg: " .. best.name .. " (valor "
			.. tostring(best.value) .. ")")
	end
	return true, best
end

-- quadro ao vivo + Loop do teleguiado
task.spawn(function()
	local lastBoard = 0
	while ALIVE do
		task.wait(0.5)
		if not unlocked() then
			continue
		end
		-- quadro do melhor ovo (a cada UpdateRate)
		if UIBoardUpdate
			and os.clock() - lastBoard >= Config.BestEgg.UpdateRate then
			lastBoard = os.clock()
			local ok, list = pcall(BestEgg.scan)
			if ok and list then
				local top = { list[1], list[2], list[3], list[4] }
				pcall(UIBoardUpdate, top)
			end
		end
		-- Loop repete o teleguiado com espera humana
		if Config.BestEgg.Loop and Config.BestEgg.Enabled
			and not Steal.busy
			and os.clock() - BestEgg.lastGo >= Config.BestEgg.GoCooldown then
			pcall(BestEgg.go)
		end
	end
end)

-- [10] INTERFACE (UI) - menu Claude (PT/EN) + registry de widgets --
-- (mesmo visual do "menu esp.lua"; aqui cada widget guarda entrada
--  para a fiação [11] ligar as funcoes de jogo aos ids em ingles)

local LOGO_ID = "rbxassetid://0" -- << coloque o ID da logo aqui
local DISCORD_URL = "https://discord.gg/UYFurBscpq"
local KEY_LINK = "COLE_AQUI_O_LINK_DO_LINKVERTISE" -- << link que o botao "Get Key" copia
local DEFAULT_LANG = "pt"

local THEME = {
	bg = Color3.fromRGB(239, 235, 226), side = Color3.fromRGB(221, 215, 201),
	card = Color3.fromRGB(248, 246, 240), line = Color3.fromRGB(196, 189, 172),
	ink = Color3.fromRGB(20, 20, 20), mute = Color3.fromRGB(108, 102, 90),
	accent = Color3.fromRGB(244, 182, 63), off = Color3.fromRGB(205, 199, 184),
	discord = Color3.fromRGB(88, 101, 242), bad = Color3.fromRGB(190, 60, 50), good = Color3.fromRGB(60, 140, 80),
}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")

----------------------------------------------------------------
-- helpers
----------------------------------------------------------------
local function new(class, props, children)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	for _, c in ipairs(children or {}) do c.Parent = o end
	return o
end
local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function stroke(c) return new("UIStroke", { Color = c, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end

----------------------------------------------------------------
-- idiomas (chave = texto em ingles; PT traduz)
----------------------------------------------------------------
local PT = {
	["Farm"] = "Coleta",
	["Pets"] = "Pets",
	["Progress"] = "Progresso",
	["Player"] = "Jogador",
	["Visuals"] = "Visual",
	["Events"] = "Eventos",
	["Settings"] = "Ajustes",
	["AUTO FARM"] = "COLETA AUTOMÁTICA",
	["FILTERS"] = "FILTROS",
	["HATCHING"] = "CHOCAGEM",
	["INVENTORY"] = "INVENTÁRIO",
	["SELLING"] = "VENDA",
	["TRAINING"] = "TREINO",
	["UPGRADES"] = "MELHORIAS",
	["MOVEMENT"] = "MOVIMENTAÇÃO",
	["PROTECTION"] = "PROTEÇÃO",
	["ESP"] = "ESP",
	["INFO"] = "INFORMAÇÕES",
	["EVENTS"] = "EVENTOS",
	["LANGUAGE"] = "IDIOMA",
	["SYSTEM"] = "SISTEMA",
	["SCRIPT"] = "SCRIPT",
	["CREDITS"] = "CRÉDITOS",
	["Auto Steal / Instant Grab"] = "Roubo Automático / Instantâneo",
	["Grabs eggs instantly, no animation"] = "Pega os ovos na hora, sem animação",
	["Auto Place Egg / Auto Deliver"] = "Colocar / Entregar Ovo Automático",
	["Puts the egg in your incubator"] = "Coloca o ovo na sua incubadora",
	["Target Area"] = "Área Alvo",
	["Best Unlocked"] = "Melhor Liberada",
	["Area 1"] = "Área 1",
	["Area 2"] = "Área 2",
	["Area 3"] = "Área 3",
	["Target Rarity"] = "Raridade Alvo",
	["All"] = "Todas",
	["Rare"] = "Raro",
	["Epic"] = "Épico",
	["Mutant"] = "Mutante",
	["Divine"] = "Divino",
	["Target Mutation"] = "Mutação Alvo",
	["Any"] = "Qualquer",
	["Mutated only"] = "Só mutados",
	["Target Value"] = "Valor Alvo",
	["High"] = "Alto",
	["Highest"] = "Mais alto",
	["Auto Hatch"] = "Chocar Automático",
	["Hatches eggs as soon as they are ready"] = "Choca os ovos assim que ficam prontos",
	["Auto Equip Best"] = "Equipar Melhores",
	["Equips your best pets"] = "Equipa os melhores pets",
	["Auto Fuse"] = "Fundir Automático",
	["Merges duplicate pets"] = "Funde pets repetidos",
	["Auto Upgrade"] = "Melhorar Automático",
	["Upgrades low-level pets"] = "Evolui pets de nível baixo",
	["Auto Sell"] = "Vender Automático",
	["Sells unwanted low-tier eggs and pets"] = "Vende ovos e pets de baixa categoria",
	["Sell up to"] = "Vender até",
	["Common"] = "Comum",
	["Auto Train Treadmill"] = "Treinar na Esteira",
	["Trains on the treadmill nonstop"] = "Treina na esteira sem parar",
	["Auto Buy Trails"] = "Comprar Trilhas",
	["Buys new speed trails when affordable"] = "Compra trilhas novas quando tiver dinheiro",
	["Auto Buy Upgrades"] = "Comprar Melhorias",
	["Buys base upgrades when affordable"] = "Compra melhorias da base quando tiver dinheiro",
	["Speed Hack (Walkspeed)"] = "Velocidade (WalkSpeed)",
	["Fly"] = "Voar",
	["Infinite Jump"] = "Pulo Infinito",
	["Noclip"] = "Noclip",
	["Walk through walls"] = "Atravessa paredes",
	["God Mode"] = "Modo Deus",
	["Blocks damage and stuns"] = "Bloqueia dano e atordoamento",
	["Anti Hit"] = "Anti Dano",
	["Guards cannot make you drop the egg"] = "Guardas não fazem você perder o ovo",
	["Anti Trap"] = "Anti Armadilha",
	["Ignores map traps"] = "Ignora armadilhas do mapa",
	["Egg ESP"] = "ESP de Ovos",
	["Highlights every egg on the map"] = "Destaca todos os ovos do mapa",
	["Show Name"] = "Mostrar Nome",
	["Show Rarity"] = "Mostrar Raridade",
	["Show Value"] = "Mostrar Valor",
	["Show Distance"] = "Mostrar Distância",
	["Boxes"] = "Caixas",
	["Tracers"] = "Linhas",
	["Auto Event"] = "Evento Automático",
	["Joins and completes live events"] = "Entra e completa eventos ativos",
	["Auto Boss (Dr. Scramble)"] = "Chefe Automático (Dr. Scramble)",
	["Fights the boss and dodges attacks"] = "Enfrenta o chefe e desvia dos ataques",
	["Auto Claim Rewards"] = "Resgatar Recompensas",
	["Collects mastery rewards"] = "Coleta recompensas de maestria",
	["Language"] = "Idioma",
	["Anti-AFK"] = "Anti-AFK",
	["Prevents the 20-minute idle kick"] = "Evita a desconexão por 20 min parado",
	["Toggle Menu"] = "Abrir / Fechar Menu",
	["Unload Script"] = "Descarregar Script",
	["Unload"] = "Descarregar",
	["Enter your key to continue"] = "Insira sua key para continuar",
	["Paste your key here"] = "Cole sua key aqui",
	["Get Key"] = "Obter Key",
	["Verify"] = "Verificar",
	["Join our Discord"] = "Entrar no Discord",
	["Enter the key."] = "Digite a key.",
	["Verifying..."] = "Verificando...",
	["Valid key."] = "Key válida.",
	["Invalid key."] = "Key inválida.",
	["Discord link copied"] = "Link do Discord copiado",
	["Key link copied"] = "Link da key copiado",
	["Preview: use the DEMO key"] = "Preview: use a key DEMO",
	["Diagnose"] = "Diagnosticar",
	["Run"] = "Rodar",
	-- ===== UI 2em-1: abas e secoes =====
	["Main"] = "Principal",
	["Best Egg"] = "Melhor Ovo",
	["Misc"] = "Diversos",
	["Local"] = "Local",
	["Webhook"] = "Webhook",
	["Config"] = "Configurações",
	["AUTO STEAL EGG"] = "ROUBO AUTOMÁTICO DE OVOS",
	["BEST EGG SYSTEM"] = "SISTEMA DO MELHOR OVO",
	["BEST EGG"] = "MELHOR OVO",
	["ANTI"] = "ANTI",
	["UPGRADES / FUSE AND TRAILS"] = "MELHORIAS / FUSÃO E TRILHAS",
	["DISCORD WEBHOOK"] = "WEBHOOK DO DISCORD",
	["INTERFACE"] = "INTERFACE",
	["CONFIG"] = "CONFIGURAÇÃO",
	["DELIVERY"] = "ENTREGA",
	["PETS"] = "PETS",
	-- ===== UI 2em-1: linhas da aba Main =====
	["Areas to Steal"] = "Áreas para Roubar",
	["Egg Rarities to Steal"] = "Raridades para Roubar",
	["Auto Steal Selected Eggs"] = "Roubar Ovos Selecionados",
	["Steals only the eggs you filtered"] = "Rouba só os ovos que você filtrou",
	["Auto Steal Secret Egg"] = "Roubar Ovo Secreto",
	["Auto Steal Big Egg"] = "Roubar Ovo Grande",
	["Auto Steal Rarest Egg"] = "Roubar o Ovo Mais Raro",
	["Steal Speed"] = "Velocidade do Roubo",
	["Run Speed (To Egg)"] = "Velocidade de Corrida (até o Ovo)",
	-- ===== UI 2em-1: Best Egg =====
	["Rarity Filter"] = "Filtro de Raridade",
	["Guided Teleport"] = "Teleguiado",
	["Goes to the best egg on the map"] = "Vai até o melhor ovo do mapa",
	["Loop"] = "Repetir",
	["Repeats the guided teleport"] = "Repete o teleguiado",
	-- ===== UI 2em-1: Misc =====
	["Anti Ragdoll"] = "Anti Queda",
	["Anti Rejoin"] = "Anti Rejoin",
	["Anti AFK"] = "Anti AFK",
	["Auto Upgrade Base"] = "Melhorias da Base Auto",
	["Auto Upgrade Treadmill"] = "Melhorias da Esteira Auto",
	["Auto Claim Index Rewards"] = "Resgatar Recompensas do Índice",
	-- ===== UI 2em-1: Local =====
	["Walk Speed"] = "Velocidade (WalkSpeed)",
	["Fly Speed"] = "Velocidade do Voo",
	["Instant Proximity Prompt"] = "Prompt Instantâneo",
	["Skips the hold time on prompts"] = "Remove o tempo de segurar dos prompts",
	["Egg Rarities to Show"] = "Raridades de Ovos p/ Mostrar",
	["ESP Egg"] = "ESP de Ovos",
	-- ===== UI 2em-1: Webhook =====
	["Webhook URL"] = "Link do Webhook",
	["Paste the webhook link"] = "Cole o link do webhook",
	["Send Webhook"] = "Enviar Webhook",
	["Sends logs to your Discord channel"] = "Envia logs pro seu canal do Discord",
	["Notify on Egg Stolen"] = "Avisar ao Roubar Ovo",
	["Test Webhook"] = "Testar Webhook",
	["Test"] = "Testar",
	-- ===== UI 2em-1: Config =====
	["Save Config"] = "Salvar Config",
	["Load Config"] = "Carregar Config",
	["Save"] = "Salvar",
	["Load"] = "Carregar",
	["Webhook sent"] = "Webhook enviado",
	["Webhook needs URL"] = "Webhook precisa do link",
	["Config saved"] = "Config salva",
	["Config loaded"] = "Config carregada",
	-- ===== valores de dropdown/chip que ainda nao existiam =====
	["Legendary"] = "Lendário",
	["Secret"] = "Secreto",
	["Eternal"] = "Eterno",
}

local lang = DEFAULT_LANG
local bound, chips = {}, {}

local function tr(k)
	if lang == "pt" and PT[k] then return PT[k] end
	return k
end
local function refresh(e)
	e[1][e[4] or "Text"] = tr(e[2]) .. (e[3] or "")
end
local function bind(obj, key, suffix, prop) -- liga um texto ao sistema de idioma
	local e = { obj, key, suffix, prop }
	refresh(e)
	table.insert(bound, e)
	return e
end
local function setLanguage(l)
	lang = l
	for _, e in ipairs(bound) do refresh(e) end
	for _, c in ipairs(chips) do
		for code, b in pairs(c) do
			b.BackgroundColor3 = THEME.accent
			b.BackgroundTransparency = (code == lang) and 0 or 1
		end
	end
end
local function langChips(parent, pos)
	local f = new("Frame", {
		Size = UDim2.fromOffset(84, 26), Position = pos, BackgroundColor3 = THEME.bg,
		BorderSizePixel = 0, Parent = parent,
	}, { corner(6), stroke(THEME.line), new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder }) })
	local btns = {}
	for i, code in ipairs({ "pt", "en" }) do
		local b = new("TextButton", {
			Text = string.upper(code), Font = Enum.Font.FredokaOne, TextSize = 13, TextColor3 = THEME.ink,
			AutoButtonColor = false, BorderSizePixel = 0, Size = UDim2.new(0.5, 0, 1, 0), LayoutOrder = i, Parent = f,
		}, { corner(6) })
		b.MouseButton1Click:Connect(function() setLanguage(code) end)
		btns[code] = b
	end
	table.insert(chips, btns)
end

----------------------------------------------------------------
-- registry: cada widget guarda a entrada; a fiação [11] liga as
-- funcoes de jogo aos ids em ingles (chaves da tabela PT/EN)
----------------------------------------------------------------
local regT, regS, regD, regB = {}, {}, {}, {}
local regC, regI = {}, {} -- chips (Rarity Filter) e campos de texto (Webhook)
local boardRefs = { rows = {} } -- refs do quadro "Best Egg" (UI.setBoard)
local UI = {}

function UI.onToggle(key, fn)
	local e = regT[key]
	if e then e.onChange = fn end
end
function UI.getToggle(key)
	local e = regT[key]
	return (e and e.state) or false
end
-- so visual + estado (nao dispara o handler - usado no boot)
function UI.setToggle(key, on)
	local e = regT[key]
	if not e then return end
	e.state = not not on
	local info = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(e.track, info, { BackgroundColor3 = e.state and THEME.accent or THEME.off }):Play()
	TweenService:Create(e.track.Knob, info, {
		Position = e.state and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3),
		BackgroundColor3 = e.state and THEME.ink or THEME.card,
	}):Play()
end
function UI.onSlider(key, fn)
	local e = regS[key]
	if e then e.onChange = fn end
end
function UI.getSlider(key)
	local e = regS[key]
	return e and e.value
end
function UI.setSlider(key, v) -- visual + valor (sem handler)
	local e = regS[key]
	if not e then return end
	v = math.clamp(math.floor(v + 0.5), e.min, e.max)
	e.value = v
	local rr = (v - e.min) / (e.max - e.min)
	e.fill.Size = UDim2.fromScale(rr, 1)
	e.knob.Position = UDim2.new(rr, -7, 0.5, -7)
	e.label.Text = tostring(v)
end
function UI.onDrop(key, fn)
	local e = regD[key]
	if e then e.onChange = fn end
end
function UI.getDrop(key)
	local e = regD[key]
	return e and e.options[e.idx]
end
-- troca a lista de opcoes mantendo o valor atual e o handler (fix
-- do dropdown que travava em lista de uma opcao)
function UI.setDrop(key, options)
	local e = regD[key]
	if not e or not options or #options == 0 then return end
	local cur = e.options[e.idx]
	e.options = options
	e.idx = 1
	for i, o in ipairs(options) do
		if o == cur then e.idx = i; break end
	end
	e.entry[2] = options[e.idx]
	refresh(e.entry)
end
function UI.onButton(key, fn)
	local e = regB[key]
	if e then e.onClick = fn end
end
function UI.toast(msg)
	toast(msg)
end
-- chips de selecao multipla (aba Best Egg)
function UI.onChip(key, fn)
	local e = regC[key]
	if e then e.onChange = fn end
end
function UI.getChips(key)
	local e = regC[key]
	return e and e.state or {}
end
-- aplica um chip (silent = nao dispara o handler, pro boot/load)
function UI.setChip(key, word, on, silent)
	local e = regC[key]
	if not e or e.state[word] == nil then
		return
	end
	e.state[word] = not not on
	local b = e.btns[word]
	if b then
		b.BackgroundColor3 = THEME.accent
		b.BackgroundTransparency = e.state[word] and 0 or 1
	end
	if not silent and e.onChange then
		pcall(e.onChange, word, e.state[word])
	end
end
-- campo de texto (Webhook URL)
function UI.onInput(key, fn)
	local e = regI[key]
	if e then e.onChange = fn end
end
function UI.getInput(key)
	local e = regI[key]
	return e and e.getText() or ""
end
function UI.setInput(key, text, silent)
	local e = regI[key]
	if not e then
		return
	end
	e.setText(tostring(text or ""))
	if not silent and e.onChange then
		pcall(e.onChange, e.getText())
	end
end
-- quadro do melhor ovo: lista rankeada vinda do modulo [9b]
function UI.setBoard(list)
	if not boardRefs.name then
		return
	end
	list = list or {}
	local best = list[1]
	boardRefs.name.Text = (best and best.name) or "—"
	boardRefs.value.Text = (best and tostring(best.value)) or "—"
	for i = 1, 4 do
		local rowR = boardRefs.rows[i]
		local e = list[i]
		if rowR then
			rowR.rank.Text = "#" .. i
			rowR.name.Text = (e and e.name) or "—"
			rowR.value.Text = (e and tostring(e.value)) or ""
		end
	end
end
UIBoardUpdate = UI.setBoard -- liga o loop do modulo [9b] nesta funcao

----------------------------------------------------------------
-- janela (nomes de instancia camuflados: a UI nova nao aparece
-- na varredura de PlayerGui por nome de script)
----------------------------------------------------------------
gui = new("ScreenGui", {
	Name = "MainScreen", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = uiRoot(),
})
local win = new("Frame", {
	Name = "Window", Size = UDim2.fromOffset(620, 420), Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = THEME.bg, BorderSizePixel = 0,
	ClipsDescendants = true, Parent = gui,
}, { corner(12), stroke(THEME.line) })

local side = new("Frame", { Name = "Sidebar", Size = UDim2.new(0, 132, 1, 0), BackgroundColor3 = THEME.side, BorderSizePixel = 0, Parent = win })
new("Frame", { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0), BackgroundColor3 = THEME.line, BorderSizePixel = 0, Parent = side })
new("ImageLabel", {
	Name = "Logo", Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0.5, -23, 0, 14),
	BackgroundTransparency = 1, Image = LOGO_ID, ScaleType = Enum.ScaleType.Fit, Parent = side,
})
local tabHolder = new("Frame", {
	Name = "Tabs", Size = UDim2.new(1, -16, 0, 250), Position = UDim2.fromOffset(8, 74),
	BackgroundTransparency = 1, Parent = side,
}, { new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })

new("TextLabel", {
	Name = "Brand", Text = "Esp House", Font = Enum.Font.FredokaOne, TextSize = 14, TextColor3 = THEME.ink,
	BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -94), Parent = side,
})
new("Frame", { Size = UDim2.new(1, -16, 0, 1), Position = UDim2.new(0, 8, 1, -68), BackgroundColor3 = THEME.line, BorderSizePixel = 0, Parent = side })
local discordBtn = new("TextButton", {
	Name = "Discord", Text = "Discord", Font = Enum.Font.FredokaOne, TextSize = 15, TextColor3 = THEME.ink,
	AutoButtonColor = false, BackgroundColor3 = THEME.card, BorderSizePixel = 0,
	Size = UDim2.new(1, -16, 0, 34), Position = UDim2.new(0, 8, 1, -50), Parent = side,
}, { corner(8), stroke(THEME.line) })
new("Frame", {
	Size = UDim2.fromOffset(10, 10), Position = UDim2.new(0, 14, 0.5, -5),
	BackgroundColor3 = THEME.discord, BorderSizePixel = 0, Parent = discordBtn,
}, { corner(5) })

local content = new("Frame", { Name = "Content", Size = UDim2.new(1, -132, 1, 0), Position = UDim2.fromOffset(132, 0), BackgroundTransparency = 1, Parent = win })
local title = new("TextLabel", {
	Name = "Title", Text = "", Font = Enum.Font.FredokaOne, TextSize = 22, TextColor3 = THEME.ink,
	TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
	Size = UDim2.new(1, -160, 0, 52), Position = UDim2.fromOffset(18, 0), Parent = content,
})
new("TextLabel", {
	Name = "Badge", Text = "Steal an Egg", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = THEME.ink,
	BackgroundColor3 = THEME.accent, Size = UDim2.fromOffset(92, 22), Position = UDim2.new(1, -108, 0, 15), Parent = content,
}, { corner(11) })
new("Frame", { Size = UDim2.new(1, -32, 0, 1), Position = UDim2.fromOffset(16, 52), BackgroundColor3 = THEME.line, BorderSizePixel = 0, Parent = content })
local pages = new("Frame", { Name = "Pages", Size = UDim2.new(1, 0, 1, -62), Position = UDim2.fromOffset(0, 62), BackgroundTransparency = 1, Parent = content })

----------------------------------------------------------------
-- componentes
----------------------------------------------------------------
local order = 0
local function nx() order += 1 return order end

local function makePage(name)
	return new("ScrollingFrame", {
		Name = "Panel", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.line, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false, Parent = pages,
	}, {
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16) }),
	})
end

local function section(page, key)
	local l = new("TextLabel", {
		Name = "Section", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = THEME.mute, TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = nx(), Parent = page,
	})
	bind(l, key)
end

local function row(page, key, descKey, h)
	h = h or 48
	local r = new("Frame", {
		Name = "Row", Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = THEME.card, BorderSizePixel = 0,
		LayoutOrder = nx(), Parent = page,
	}, { corner(8), stroke(THEME.line) })
	local nameL = new("TextLabel", {
		Name = "Label", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = THEME.ink, TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1, Position = UDim2.fromOffset(12, descKey and 8 or 0),
		Size = descKey and UDim2.new(1, -140, 0, 16) or UDim2.new(1, -140, 1, 0), Parent = r,
	})
	bind(nameL, key)
	if descKey and descKey ~= "" then
		local d = new("TextLabel", {
			Name = "Hint", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = THEME.mute, TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -140, 0, 14), Parent = r,
		})
		bind(d, descKey)
	end
	return r
end

local switches, sliderList = {}, {}

local function toggle(page, key, desc)
	local r = row(page, key, desc)
	local track = new("TextButton", {
		Name = "Switch", Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(40, 20),
		Position = UDim2.new(1, -52, 0.5, -10), BackgroundColor3 = THEME.off, BorderSizePixel = 0, Parent = r,
	}, { corner(10) })
	new("Frame", {
		Name = "Knob", Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(3, 3),
		BackgroundColor3 = THEME.card, BorderSizePixel = 0, Parent = track,
	}, { corner(7) })
	local entry = { track = track, key = key, state = false, onChange = nil }
	regT[key] = entry
	table.insert(switches, entry)
end

local function slider(page, key, min, max, value)
	local r = row(page, key, "", 58)
	local ratio = (value - min) / (max - min)
	local label = new("TextLabel", {
		Name = "Value", Text = tostring(value), Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = THEME.ink,
		TextXAlignment = Enum.TextXAlignment.Right, BackgroundTransparency = 1,
		Size = UDim2.fromOffset(60, 16), Position = UDim2.new(1, -72, 0, 8), Parent = r,
	})
	local bar = new("Frame", {
		Name = "Track", Size = UDim2.new(1, -24, 0, 6), Position = UDim2.fromOffset(12, 38),
		BackgroundColor3 = THEME.off, BorderSizePixel = 0, Parent = r,
	}, { corner(3) })
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(ratio, 1), BackgroundColor3 = THEME.accent, BorderSizePixel = 0, Parent = bar }, { corner(3) })
	local knob = new("Frame", {
		Name = "Knob", Size = UDim2.fromOffset(14, 14), Position = UDim2.new(ratio, -7, 0.5, -7),
		BackgroundColor3 = THEME.ink, BorderSizePixel = 0, Parent = bar,
	}, { corner(7) })
	local hit = new("TextButton", { Name = "Hit", Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0.5, -13), Parent = bar })
	local entry = { bar = bar, fill = fill, knob = knob, label = label, hit = hit, min = min, max = max, value = value, onChange = nil }
	regS[key] = entry
	table.insert(sliderList, entry)
end

local function dropdown(page, key, options) -- clique troca a opcao
	local r = row(page, key)
	local e = bind(new("TextButton", {
		Name = "Pick", Text = "", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = THEME.ink, AutoButtonColor = false,
		BackgroundColor3 = THEME.bg, Size = UDim2.fromOffset(130, 28), Position = UDim2.new(1, -142, 0.5, -14),
		BorderSizePixel = 0, Parent = r,
	}, { corner(6), stroke(THEME.line) }), options[1], "  \u{25BC}")
	local d = { options = options, idx = 1, entry = e, onChange = nil }
	regD[key] = d
	e[1].MouseButton1Click:Connect(function()
		d.idx = d.idx % #d.options + 1
		e[2] = d.options[d.idx]
		refresh(e)
		if d.onChange then
			local ok, err = pcall(d.onChange, d.options[d.idx])
			if not ok then warn("[EspHouse] dropdown " .. key .. ": " .. tostring(err)) end
		end
	end)
end

local function button(page, key, labelKey)
	local r = row(page, key)
	local b = new("TextButton", {
		Name = "Go", Font = Enum.Font.FredokaOne, TextSize = 14, TextColor3 = THEME.ink, AutoButtonColor = false,
		BackgroundColor3 = THEME.accent, Size = UDim2.fromOffset(110, 28), Position = UDim2.new(1, -122, 0.5, -14),
		BorderSizePixel = 0, Parent = r,
	}, { corner(6) })
	bind(b, labelKey)
	local be = { onClick = nil }
	regB[key] = be
	b.MouseButton1Click:Connect(function()
		if be.onClick then
			local ok, err = pcall(be.onClick)
			if not ok then warn("[EspHouse] botao " .. key .. ": " .. tostring(err)) end
		end
	end)
end

local function keybind(page, key, value)
	local r = row(page, key)
	new("TextLabel", {
		Name = "Key", Text = value, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = THEME.ink, BackgroundColor3 = THEME.bg,
		Size = UDim2.fromOffset(88, 28), Position = UDim2.new(1, -100, 0.5, -14), BorderSizePixel = 0, Parent = r,
	}, { corner(6), stroke(THEME.line) })
end

local function langRow(page, key)
	local r = row(page, key)
	langChips(r, UDim2.new(1, -96, 0.5, -13))
end

-- chips de selecao multipla (aba "Rarity Filter")
local function chipRow(page, key, options)
	local r = row(page, key, "", 76)
	local holder = new("Frame", {
		Size = UDim2.new(1, -24, 0, 28), Position = UDim2.fromOffset(12, 38),
		BackgroundTransparency = 1, Parent = r,
	}, { new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local w = math.floor((432 - 6 * (#options - 1)) / #options)
	local entry = { state = {}, btns = {}, onChange = nil }
	for i, opt in ipairs(options) do
		local b = new("TextButton", {
			Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = THEME.ink,
			AutoButtonColor = false, BackgroundColor3 = THEME.card,
			BorderSizePixel = 0, Size = UDim2.fromOffset(w, 28),
			LayoutOrder = i, Parent = holder,
		}, { corner(6), stroke(THEME.line) })
		bind(b, opt)
		entry.state[opt] = false
		entry.btns[opt] = b
		b.MouseButton1Click:Connect(function()
			entry.state[opt] = not entry.state[opt]
			b.BackgroundColor3 = entry.state[opt] and THEME.accent or THEME.card
			if entry.onChange then
				local ok, err = pcall(entry.onChange, opt, entry.state[opt])
				if not ok then
					warn("[EspHouse] chip " .. key .. ": " .. tostring(err))
				end
			end
		end)
	end
	regC[key] = entry
end

-- campo de texto (aba Webhook: URL)
local function inputRow(page, key, placeholderKey)
	local r = row(page, key)
	local box = new("TextBox", {
		Text = "", PlaceholderColor3 = THEME.mute, ClearTextOnFocus = false,
		Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = THEME.ink,
		TextXAlignment = Enum.TextXAlignment.Left, ClipsDescendants = true,
		BackgroundColor3 = THEME.card, BorderSizePixel = 0,
		Size = UDim2.fromOffset(210, 28), Position = UDim2.new(1, -222, 0.5, -14),
		Parent = r,
	}, { corner(6), stroke(THEME.line),
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }) })
	bind(box, placeholderKey, nil, "PlaceholderText")
	local entry = {
		getText = function() return box.Text end,
		setText = function(t) box.Text = t end,
		onChange = nil,
	}
	box.FocusLost:Connect(function()
		if entry.onChange then
			local ok, err = pcall(entry.onChange, box.Text)
			if not ok then
				warn("[EspHouse] input " .. key .. ": " .. tostring(err))
			end
		end
	end)
	regI[key] = entry
end

-- quadro do melhor ovo (dados ao vivo via UI.setBoard)
local function eggBoard(page, key)
	local card = new("Frame", {
		Size = UDim2.new(1, 0, 0, 192), BackgroundColor3 = THEME.card,
		BorderSizePixel = 0, LayoutOrder = nx(), Parent = page,
	}, { corner(8), stroke(THEME.line) })
	bind(new("TextLabel", {
		Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = THEME.mute,
		TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 14), Position = UDim2.fromOffset(12, 8),
		Parent = card,
	}), key)
	local nameL = new("TextLabel", {
		Text = "—", Font = Enum.Font.FredokaOne, TextSize = 20,
		TextColor3 = THEME.ink, TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1, Size = UDim2.fromOffset(240, 28),
		Position = UDim2.fromOffset(12, 22), Parent = card,
	})
	local valueL = new("TextLabel", {
		Text = "—", Font = Enum.Font.FredokaOne, TextSize = 20,
		TextColor3 = THEME.good, TextXAlignment = Enum.TextXAlignment.Right,
		BackgroundTransparency = 1, Size = UDim2.fromOffset(120, 28),
		Position = UDim2.new(1, -132, 0, 22), Parent = card,
	})
	new("Frame", { Size = UDim2.new(1, -24, 0, 1),
		Position = UDim2.fromOffset(12, 58), BackgroundColor3 = THEME.line,
		BorderSizePixel = 0, Parent = card })
	boardRefs.name = nameL
	boardRefs.value = valueL
	for i = 1, 4 do
		local y = 64 + (i - 1) * 30
		local rankL = new("TextLabel", {
			Text = "#" .. i, Font = Enum.Font.GothamBold, TextSize = 11,
			TextColor3 = THEME.mute, TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1, Size = UDim2.fromOffset(28, 30),
			Position = UDim2.fromOffset(12, y), Parent = card,
		})
		local rowName = new("TextLabel", {
			Text = "—", Font = Enum.Font.GothamBold, TextSize = 13,
			TextColor3 = THEME.ink, TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1, Size = UDim2.fromOffset(240, 30),
			Position = UDim2.fromOffset(42, y), Parent = card,
		})
		local rowVal = new("TextLabel", {
			Text = "", Font = Enum.Font.GothamBold, TextSize = 12,
			TextColor3 = THEME.good, TextXAlignment = Enum.TextXAlignment.Right,
			BackgroundTransparency = 1, Size = UDim2.fromOffset(100, 30),
			Position = UDim2.new(1, -112, 0, y), Parent = card,
		})
		boardRefs.rows[i] = { rank = rankL, name = rowName, value = rowVal }
	end
end

----------------------------------------------------------------
-- paginas
----------------------------------------------------------------
local P = {}
local TAB_ORDER = { "Main", "Best Egg", "Misc", "Local", "Webhook", "Config" }

-- ===== aba Main: roubo com filtros =====
P.Main = makePage("Main")
section(P.Main, "AUTO STEAL EGG")
dropdown(P.Main, "Areas to Steal", { "Best Unlocked", "Area 1", "Area 2", "Area 3" })
dropdown(P.Main, "Egg Rarities to Steal", { "All", "Legendary", "Secret", "Eternal", "Divine" })
toggle(P.Main, "Auto Steal Selected Eggs", "Steals only the eggs you filtered")
toggle(P.Main, "Auto Steal Secret Egg")
toggle(P.Main, "Auto Steal Big Egg")
toggle(P.Main, "Auto Steal Rarest Egg")
slider(P.Main, "Steal Speed", 100, 1000, 1000)
slider(P.Main, "Run Speed (To Egg)", 16, 300, 100)
section(P.Main, "DELIVERY")
toggle(P.Main, "Auto Place Egg / Auto Deliver", "Puts the egg in your incubator")
section(P.Main, "FILTERS")
dropdown(P.Main, "Target Mutation", { "Any", "Mutated only" })
dropdown(P.Main, "Target Value", { "Any", "High", "Highest" })

-- ===== aba Best Egg: quadro + teleguiado =====
P.BestEgg = makePage("Best Egg")
section(P.BestEgg, "BEST EGG SYSTEM")
eggBoard(P.BestEgg, "BEST EGG")
chipRow(P.BestEgg, "Rarity Filter", { "Legendary", "Secret", "Eternal", "Divine" })
toggle(P.BestEgg, "Guided Teleport", "Goes to the best egg on the map")
toggle(P.BestEgg, "Loop", "Repeats the guided teleport")

-- ===== aba Misc: protecoes, upgrades, pets e eventos =====
P.Misc = makePage("Misc")
section(P.Misc, "ANTI")
toggle(P.Misc, "Anti Trap", "Ignores map traps")
toggle(P.Misc, "Anti Ragdoll")
toggle(P.Misc, "Anti Rejoin")
toggle(P.Misc, "Anti AFK", "Prevents the 20-minute idle kick")
section(P.Misc, "UPGRADES / FUSE AND TRAILS")
toggle(P.Misc, "Auto Upgrade Base", "Buys base upgrades when affordable")
toggle(P.Misc, "Auto Upgrade Treadmill", "Trains on the treadmill nonstop")
toggle(P.Misc, "Auto Claim Index Rewards", "Collects mastery rewards")
toggle(P.Misc, "Auto Fuse", "Merges duplicate pets")
toggle(P.Misc, "Auto Buy Trails", "Buys new speed trails when affordable")
section(P.Misc, "PETS")
toggle(P.Misc, "Auto Hatch", "Hatches eggs as soon as they are ready")
toggle(P.Misc, "Auto Equip Best", "Equips your best pets")
toggle(P.Misc, "Auto Upgrade", "Upgrades low-level pets")
toggle(P.Misc, "Auto Sell", "Sells unwanted low-tier eggs and pets")
dropdown(P.Misc, "Sell up to", { "Common", "Rare", "Epic" })
section(P.Misc, "EVENTS")
toggle(P.Misc, "Auto Event", "Joins and completes live events")
toggle(P.Misc, "Auto Boss (Dr. Scramble)", "Fights the boss and dodges attacks")

-- ===== aba Local: movimento, protecao e ESP =====
P.Local = makePage("Local")
section(P.Local, "MOVEMENT")
slider(P.Local, "Walk Speed", 16, 300, 100)
toggle(P.Local, "TPWalk")
slider(P.Local, "Fly Speed", 10, 300, 100)
toggle(P.Local, "Fly")
toggle(P.Local, "Instant Proximity Prompt", "Skips the hold time on prompts")
toggle(P.Local, "Infinite Jump")
toggle(P.Local, "Noclip", "Walk through walls")
section(P.Local, "PROTECTION")
toggle(P.Local, "God Mode", "Blocks damage and stuns")
toggle(P.Local, "Anti Hit", "Guards cannot make you drop the egg")
section(P.Local, "ESP")
dropdown(P.Local, "Egg Rarities to Show", { "All", "Common", "Rare", "Legendary", "Secret", "Eternal", "Divine" })
toggle(P.Local, "ESP Egg", "Highlights every egg on the map")
toggle(P.Local, "Show Name")
toggle(P.Local, "Show Rarity")
toggle(P.Local, "Show Value")
toggle(P.Local, "Show Distance")
toggle(P.Local, "Boxes")
toggle(P.Local, "Tracers")

-- ===== aba Webhook: logs no Discord =====
P.Webhook = makePage("Webhook")
section(P.Webhook, "DISCORD WEBHOOK")
inputRow(P.Webhook, "Webhook URL", "Paste the webhook link")
toggle(P.Webhook, "Send Webhook", "Sends logs to your Discord channel")
toggle(P.Webhook, "Notify on Egg Stolen")
button(P.Webhook, "Test Webhook", "Test")

-- ===== aba Config: idioma, atalhos, arquivos =====
P.Config = makePage("Config")
section(P.Config, "LANGUAGE")
langRow(P.Config, "Language")
section(P.Config, "INTERFACE")
keybind(P.Config, "Toggle Menu", "RightShift")
section(P.Config, "CONFIG")
button(P.Config, "Save Config", "Save")
button(P.Config, "Load Config", "Load")
button(P.Config, "Unload Script", "Unload")
section(P.Config, "SCRIPT")
button(P.Config, "Diagnose", "Run")
section(P.Config, "CREDITS")
keybind(P.Config, "Esp House", "v2.2")

----------------------------------------------------------------
-- abas
----------------------------------------------------------------
local tabButtons = {}
for i, name in ipairs(TAB_ORDER) do
	local b = new("TextButton", {
		Name = "Tab", Font = Enum.Font.FredokaOne, TextSize = 15, TextColor3 = THEME.ink, AutoButtonColor = false,
		BackgroundColor3 = THEME.card, BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 32), LayoutOrder = i, Parent = tabHolder,
	}, { corner(8) })
	new("Frame", {
		Name = "Mark", Size = UDim2.new(0, 3, 0, 18), Position = UDim2.new(0, 0, 0.5, -9),
		BackgroundColor3 = THEME.accent, BorderSizePixel = 0, Visible = false, Parent = b,
	}, { corner(2) })
	bind(b, name)
	tabButtons[name] = b
end
local titleEntry = bind(title, TAB_ORDER[1])

----------------------------------------------------------------
-- comportamento visual (navegacao, switches, sliders)
----------------------------------------------------------------
local function openTab(name)
	for n, page in pairs(P) do page.Visible = (n == name) end
	for n, b in pairs(tabButtons) do
		b.BackgroundTransparency = (n == name) and 0 or 1
		b.Mark.Visible = (n == name)
	end
	titleEntry[2] = name
	refresh(titleEntry)
end
for name, b in pairs(tabButtons) do
	b.MouseButton1Click:Connect(function() openTab(name) end)
end

for _, e in ipairs(switches) do
	local track = e.track
	track.MouseButton1Click:Connect(function()
		e.state = not e.state
		local st = e.state
		local info = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(track, info, { BackgroundColor3 = st and THEME.accent or THEME.off }):Play()
		TweenService:Create(track.Knob, info, {
			Position = st and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3),
			BackgroundColor3 = st and THEME.ink or THEME.card,
		}):Play()
		if e.onChange then
			local ok, err = pcall(e.onChange, st)
			if not ok then warn("[EspHouse] toggle " .. e.key .. ": " .. tostring(err)) end
		end
	end)
end

local function isPress(i)
	return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end
for _, sl in ipairs(sliderList) do
	local dragging = false
	local function setFromX(x)
		local r = math.clamp((x - sl.bar.AbsolutePosition.X) / sl.bar.AbsoluteSize.X, 0, 1)
		sl.value = math.floor(sl.min + (sl.max - sl.min) * r + 0.5)
		local rr = (sl.value - sl.min) / (sl.max - sl.min)
		sl.fill.Size = UDim2.fromScale(rr, 1)
		sl.knob.Position = UDim2.new(rr, -7, 0.5, -7)
		sl.label.Text = tostring(sl.value)
		if sl.onChange then
			local ok, err = pcall(sl.onChange, sl.value)
			if not ok then warn("[EspHouse] slider: " .. tostring(err)) end
		end
	end
	sl.hit.InputBegan:Connect(function(i)
		if isPress(i) then dragging = true setFromX(i.Position.X) end
	end)
	UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			setFromX(i.Position.X)
		end
	end)
	UIS.InputEnded:Connect(function(i)
		if isPress(i) then dragging = false end
	end)
end

----------------------------------------------------------------
-- toast, links e tela de key
----------------------------------------------------------------
local toastLabel = new("TextLabel", {
	Name = "Toast", Size = UDim2.fromOffset(300, 32), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24),
	BackgroundColor3 = THEME.ink, BackgroundTransparency = 1, TextColor3 = THEME.card, TextTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 12, Text = "", Parent = gui,
}, { corner(8) })
local toastId = 0
function toast(msg) -- atribui o local declarado la em cima (backend chama ele)
	toastId += 1
	local id = toastId
	local info = TweenInfo.new(0.2)
	toastLabel.Text = tostring(msg)
	TweenService:Create(toastLabel, info, { BackgroundTransparency = 0, TextTransparency = 0 }):Play()
	task.delay(3.2, function()
		if id == toastId then
			TweenService:Create(toastLabel, info, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		end
	end)
end

-- Roblox normal nao abre links externos: copia pro clipboard; se nao der, mostra o link.
local function copyLink(url, okKey)
	local clip = setclipboard or toclipboard
	if clip and pcall(clip, url) then toast(tr(okKey)) else toast(url) end
end
discordBtn.MouseButton1Click:Connect(function() copyLink(DISCORD_URL, "Discord link copied") end)

win.Visible = false
local keyFrame = new("Frame", {
	Name = "LoginPanel", Size = UDim2.fromOffset(380, 270), Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = THEME.bg, BorderSizePixel = 0, Parent = gui,
}, { corner(12), stroke(THEME.line) })
langChips(keyFrame, UDim2.new(1, -96, 0, 12))
new("ImageLabel", {
	Name = "Logo", Size = UDim2.fromOffset(44, 44), Position = UDim2.new(0.5, -22, 0, 16), BackgroundTransparency = 1,
	Image = LOGO_ID, ScaleType = Enum.ScaleType.Fit, Parent = keyFrame,
})
new("TextLabel", {
	Name = "Brand", Text = "Esp House", Font = Enum.Font.FredokaOne, TextSize = 22, TextColor3 = THEME.ink,
	BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 64), Parent = keyFrame,
})
bind(new("TextLabel", {
	Name = "Hint", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = THEME.mute, BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 92), Parent = keyFrame,
}), "Enter your key to continue")

local keyInput = new("TextBox", {
	Name = "CodeBox", Text = "", PlaceholderColor3 = THEME.mute, ClearTextOnFocus = false,
	Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = THEME.ink, TextXAlignment = Enum.TextXAlignment.Left,
	BackgroundColor3 = THEME.card, BorderSizePixel = 0, Size = UDim2.new(1, -48, 0, 36),
	Position = UDim2.fromOffset(24, 122), Parent = keyFrame,
}, { corner(8), stroke(THEME.line), new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
bind(keyInput, "Paste your key here", nil, "PlaceholderText")

local keyStatus = new("TextLabel", {
	Name = "Status", Font = Enum.Font.GothamMedium, TextSize = 11, TextColor3 = THEME.mute, BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 164), Parent = keyFrame,
})
local statusEntry = bind(keyStatus, "")

local getKeyBtn = new("TextButton", {
	Name = "GetKey", Font = Enum.Font.FredokaOne, TextSize = 15, TextColor3 = THEME.ink, AutoButtonColor = false,
	BackgroundColor3 = THEME.card, BorderSizePixel = 0, Size = UDim2.fromOffset(160, 34),
	Position = UDim2.fromOffset(24, 188), Parent = keyFrame,
}, { corner(8), stroke(THEME.line) })
bind(getKeyBtn, "Get Key")
local verifyBtn = new("TextButton", {
	Name = "Verify", Font = Enum.Font.FredokaOne, TextSize = 15, TextColor3 = THEME.ink, AutoButtonColor = false,
	BackgroundColor3 = THEME.accent, BorderSizePixel = 0, Size = UDim2.fromOffset(160, 34),
	Position = UDim2.new(1, -184, 0, 188), Parent = keyFrame,
}, { corner(8) })
bind(verifyBtn, "Verify")
local keyDiscord = new("TextButton", {
	Name = "Discord", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = THEME.mute, BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -30), Parent = keyFrame,
})
bind(keyDiscord, "Join our Discord")

local function setStatus(msg, color)
	statusEntry[2] = msg
	refresh(statusEntry)
	keyStatus.TextColor3 = color
end

-- validador: DEMO (+ chaves de teste) e servidor HTTP opcional
local function checkKey(key)
	return KeySys.validate(key)
end

local verifying = false
verifyBtn.MouseButton1Click:Connect(function()
	if verifying then return end
	local key = keyInput.Text:gsub("%s", "")
	if key == "" then setStatus("Enter the key.", THEME.bad) return end
	verifying = true
	setStatus("Verifying...", THEME.mute)
	local ok = checkKey(key)
	verifying = false
	if ok then
		KeySys.save(key)
		setStatus("Valid key.", THEME.good)
		task.wait(0.4)
		keyFrame.Visible = false
		win.Visible = true
		toast("Esp House v2.2 carregado | key: DEMO")
	else
		setStatus("Invalid key.", THEME.bad)
	end
end)
getKeyBtn.MouseButton1Click:Connect(function() copyLink(KEY_LINK, "Key link copied") end)
keyDiscord.MouseButton1Click:Connect(function() copyLink(DISCORD_URL, "Discord link copied") end)

-- RightShift abre/fecha o menu (linha "Toggle Menu")
UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.RightShift and KeySys.validated then
		win.Visible = not win.Visible
	end
end)

-- arrastar pela sidebar / titulo (linhas de widgets continuam clicaveis)
do
	local dragging, startPos, startP
	local function begin(i)
		if i.Target and i.Target:IsA("GuiButton") then return end
		dragging = true
		startPos = i.Position
		startP = win.Position
	end
	side.InputBegan:Connect(function(i)
		if isPress(i) then begin(i) end
	end)
	title.InputBegan:Connect(function(i)
		if isPress(i) then begin(i) end
	end)
	UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - startPos
			win.Position = UDim2.new(startP.X.Scale, startP.X.Offset + d.X, startP.Y.Scale, startP.Y.Offset + d.Y)
		end
	end)
	UIS.InputEnded:Connect(function(i)
		if isPress(i) then dragging = false end
	end)
end

openTab(TAB_ORDER[1])
setLanguage(DEFAULT_LANG)

-- [11] FIACAO: cada widget da UI nova liga numa funcao de jogo ----
-- (ids = chaves em ingles da tabela PT/EN; mensagens em portugues)

-- descarregar: corta loops/conexoes, restaura o que o script mexeu
local function shutdown()
	if not ALIVE then
		return
	end
	ALIVE = false
	for _, f in ipairs(unloadFns) do
		pcall(f)
	end
	for _, c in ipairs(conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	pcall(function()
		gui:Destroy()
	end)
end

-- helper: os toggles de ESP destroem e reconstruem as tags
local function espToggle(key, field)
	UI.onToggle(key, function(on)
		Config.ESP[field] = on
		EggESP.apply()
	end)
end

-- ===== aba Main =====
UI.onToggle("Auto Steal Selected Eggs", function(on)
	Config.Steal.Enabled = on
	if on then
		-- nao age no mesmo clique do usuario (acao imediata = flag)
		Steal.firstAt = os.clock() + jit(2)
		toast("Roubo ligado: acho o ovo, pego e volto em segundos")
	else
		toast("Roubo desligado")
	end
end)
UI.onToggle("Auto Steal Secret Egg", function(on)
	Config.Steal.ModeSecret = on
	if on then Steal.firstAt = os.clock() + jit(2) end
	toast(on and "Modo Secreto: so ovos com 'secret' no nome"
		or "Modo Secreto desligado")
end)
UI.onToggle("Auto Steal Big Egg", function(on)
	Config.Steal.ModeBig = on
	if on then Steal.firstAt = os.clock() + jit(2) end
	toast(on and "Modo Grande: so ovos 'big/giant/grande'"
		or "Modo Grande desligado")
end)
UI.onToggle("Auto Steal Rarest Egg", function(on)
	Config.Steal.ModeRarest = on
	if on then Steal.firstAt = os.clock() + jit(2) end
	toast(on and "Modo Mais Raro: so ovos de raridade de topo"
		or "Modo Mais Raro desligado")
end)
UI.onSlider("Steal Speed", function(v)
	Config.Steal.StealSpeed = v
	if v >= 950 then
		toast("Roubo no maximo: se kickar, abaixe a Steal Speed")
	end
end)
UI.onSlider("Run Speed (To Egg)", function(v)
	Config.Steal.RunSpeed = v
	-- so escreve no Humanoid DURANTE o roubo (regra anti-kick)
	if v > 200 then
		toast("Corrida " .. v .. ": alta chance de kick - desligue se expulsar")
	end
end)
UI.onToggle("Auto Place Egg / Auto Deliver", function(on)
	Config.Steal.CarryHome = on
	toast(on and "Entrega ligada: com ovo na mao, vou pra base rapido"
		or "Entrega desligada")
end)
UI.onDrop("Areas to Steal", function(v)
	Config.Steal.TargetArea = v
	toast("Area alvo: " .. tr(v))
end)
UI.onDrop("Egg Rarities to Steal", function(v)
	Config.Steal.TargetRarity = v
	toast("Raridade alvo: " .. tr(v) .. (v == "All" and "" or " (filtra ovos)"))
end)
UI.onDrop("Target Mutation", function(v)
	Config.Steal.TargetMutation = v
	toast("Mutacao: " .. tr(v))
end)
UI.onDrop("Target Value", function(v)
	Config.Steal.TargetValue = v
	toast("Valor alvo: " .. tr(v))
end)

-- ===== aba Best Egg =====
UI.onChip("Rarity Filter", function(word, on)
	Config.BestEgg.Filter[word] = on
	toast(on and ("Filtro no quadro: " .. word)
		or ("Filtro " .. word .. " removido"))
end)
UI.onToggle("Guided Teleport", function(on)
	Config.BestEgg.Enabled = on
	if on then
		toast("Teleguiado: indo pro melhor ovo...")
		task.spawn(function()
			pcall(BestEgg.go)
		end)
	else
		toast("Teleguiado desligado")
	end
end)
UI.onToggle("Loop", function(on)
	Config.BestEgg.Loop = on
	if on and not Config.BestEgg.Enabled then
		-- Loop implica o teleguiado ligado
		Config.BestEgg.Enabled = true
		UI.setToggle("Guided Teleport", true)
	end
	toast(on and "Loop: repete o teleguiado com espera" or "Loop desligado")
end)

-- ===== aba Misc =====
UI.onToggle("Anti Trap", function(on) Config.Player.AntiTrap = on end)
UI.onToggle("Anti Ragdoll", function(on)
	Config.Player.AntiRagdoll = on
	ragdollRefresh()
	toast(on and "Anti Queda: fico de pe ao cair" or "Anti Queda desligado")
end)
UI.onToggle("Anti Rejoin", function(on)
	Config.Player.AntiRejoin = on
	if on and Config.Player.ReexecURL == "" then
		toast("Anti Rejoin so avisa; pra reexec, configure ReexecURL")
	else
		toast(on and "Anti Rejoin ligado" or "Anti Rejoin desligado")
	end
end)
UI.onToggle("Anti AFK", function(on) Config.Player.AntiAFK = on end)
UI.onToggle("Auto Upgrade Base", function(on) Config.Auto.BuyUpgrades = on end)
UI.onToggle("Auto Upgrade Treadmill", function(on)
	Config.Auto.Train = on
	toast(on and "Esteira: treino automatico na prancha" or "Esteira desligada")
end)
UI.onToggle("Auto Claim Index Rewards", function(on) Config.Auto.Claim = on end)
UI.onToggle("Auto Fuse", function(on) Config.Auto.Merge = on end)
UI.onToggle("Auto Buy Trails", function(on) Config.Auto.BuyTrail = on end)
UI.onToggle("Auto Hatch", function(on) Config.Auto.Hatch = on end)
UI.onToggle("Auto Equip Best", function(on)
	Config.Auto.EquipBest = on
	toast(on and "Equipar melhores: procuro prompt ou botao do jogo"
		or "Equipar melhores desligado")
end)
UI.onToggle("Auto Upgrade", function(on) Config.Auto.Upgrade = on end)
UI.onToggle("Auto Sell", function(on) Config.Auto.Sell = on end)
UI.onDrop("Sell up to", function(v)
	Config.Auto.SellUpTo = v
	toast("Vender ate: " .. tr(v))
end)
UI.onToggle("Auto Event", function(on) Config.Auto.Event = on end)
UI.onToggle("Auto Boss (Dr. Scramble)", function(on)
	Config.Auto.Boss = on
	-- briga + desvia: mantem o Ghost ligado junto (ou o estado do Anti Hit)
	Config.Guardian.Ghost = on or UI.getToggle("Anti Hit")
	toast(on and "Chefe: ataco o prompt e desvio dos ataques" or "Chefe desligado")
end)

-- ===== aba Local =====
UI.onSlider("Walk Speed", function(v)
	Config.Player.WalkSpeedTarget = v
	-- so escreve no Humanoid depois que voce mexe no slider (regra
	-- anti-kick: escrita passiva = flag). teto do furtivo vale
	Config.Player.SpeedCustom = (v > Config.Player.BaseWalkSpeed)
	if v > 100 then
		toast("Velocidade " .. v .. ": alta chance de kick - desligue se expulsar")
	end
end)
UI.onToggle("TPWalk", function(on)
	Config.Player.TPWalk = on
	toast(on and "TPWalk: andar com teleporte curto (teto do furtivo vale)"
		or "TPWalk desligado")
end)
UI.onSlider("Fly Speed", function(v)
	Config.Player.FlySpeed = v
end)
UI.onToggle("Fly", function(on)
	Config.Player.Fly = on
	setFly(on)
	toast(on and "Voando: WASD + Espaco sobe, Ctrl desce" or "Voo desligado")
end)
UI.onToggle("Instant Proximity Prompt", function(on)
	Config.Player.InstantPrompt = on
	instantApply()
	toast(on and "Prompt instantaneo: sem tempo de segurar"
		or "Prompt normal restaurado")
end)
UI.onToggle("Infinite Jump", function(on) Config.Player.InfiniteJump = on end)
UI.onToggle("Noclip", function(on)
	Config.Player.Noclip = on
	toast(on and "Noclip ligado: atravessa paredes" or "Noclip desligado")
end)
UI.onToggle("God Mode", function(on)
	Config.Player.God = on
	toast(on and "Modo Deus: recupero a vida local" or "Modo Deus desligado")
end)
UI.onToggle("Anti Hit", function(on)
	Config.Guardian.Ghost = on
	toast(on and "Anti Dano: guardiao que chegar perto leva blink" or "Anti Dano desligado")
end)

-- ===== aba Local: ESP =====
UI.onDrop("Egg Rarities to Show", function(v)
	Config.ESP.ShowRarities = v
	EggESP.apply()
	toast("ESP mostrando: " .. tr(v))
end)
espToggle("ESP Egg", "Eggs")
espToggle("Show Name", "ShowName")
espToggle("Show Rarity", "ShowRarity")
espToggle("Show Value", "ShowValue")
espToggle("Show Distance", "ShowDistance")
espToggle("Boxes", "Boxes")
espToggle("Tracers", "Tracers")

-- (Auto Event e Auto Boss agora ficam ligados na aba Misc)

-- ===== aba Config: webhook, diagnostico e descarga =====
UI.onInput("Webhook URL", function(text)
	Config.Webhook.URL = (tostring(text or ""):gsub("%s+", ""))
	toast(Config.Webhook.URL ~= "" and "Webhook salvo"
		or "Webhook URL vazia")
end)
UI.onToggle("Send Webhook", function(on)
	Config.Webhook.Send = on
	toast(on and "Webhook: enviando logs pro Discord" or "Webhook desligado")
end)
UI.onToggle("Notify on Egg Stolen", function(on)
	Config.Webhook.NotifyStolen = on
	toast(on and "Avisarei no Discord a cada ovo roubado"
		or "Aviso de ovo desligado")
end)
UI.onButton("Test Webhook", function()
	if Config.Webhook.URL == "" then
		toast("Webhook precisa do link")
		return
	end
	local ok = Webhook.test()
	toast(ok and "Webhook enviado" or "Falha no webhook (veja Output)")
end)

UI.onButton("Diagnose", function()
	local eggMatch = makeMatcher(Config.Steal.EggPatterns)
	local zoneMatch = makeMatcher(Config.Game.ZonePatterns)
	local gardMatch = makeMatcher(Config.Guardian.Names)
	local eggs, prompts, guards = 0, 0, 0
	local zones = {}
	for _, d in ipairs(wsDescendants()) do
		if d:IsA("ProximityPrompt") then
			prompts = prompts + 1
			print("[Diag] prompt: " .. tostring(d.ObjectText) .. " | " .. tostring(d.ActionText))
		elseif d:IsA("BasePart") or d:IsA("Model") then
			local n = lowName(d)
			if eggMatch(n) then
				eggs = eggs + 1
			end
			if zoneMatch(n) and #zones < 16 then
				zones[#zones + 1] = d.Name
			end
			if d:IsA("Model") and gardMatch(n) then
				guards = guards + 1
			end
		end
	end
	print(string.format("[Diag] ovos=%d | prompts=%d | guardioes=%d", eggs, prompts, guards))
	for _, z in ipairs(zones) do
		print("[Diag] zona/area: " .. z)
	end
	toast(string.format("Diag: %d ovos | %d prompts | %d guardioes (ver Output)",
		eggs, prompts, guards))
end)

UI.onButton("Unload Script", shutdown)

-- persistencia: snapshot dos widgets + idioma (JSON no arquivo do
-- executor; le gravacao via writefile/readfile)
local CFG_FILE = "esp_house_config.json"

local function snapshot()
	local snap = { toggles = {}, sliders = {}, drops = {},
		chips = {}, inputs = {}, lang = lang }
	for k, e in pairs(regT) do snap.toggles[k] = e.state end
	for k, e in pairs(regS) do snap.sliders[k] = e.value end
	for k, e in pairs(regD) do snap.drops[k] = e.options[e.idx] end
	for k, e in pairs(regC) do
		local t = {}
		for word, on in pairs(e.state) do
			t[word] = on
		end
		snap.chips[k] = t
	end
	for k, e in pairs(regI) do
		snap.inputs[k] = e.getText()
	end
	return snap
end

local function applyDrop(k, v)
	local e = regD[k]
	if not e then return end
	for i, o in ipairs(e.options) do
		if o == v then e.idx = i; break end
	end
	e.entry[2] = e.options[e.idx]
	refresh(e.entry)
	if e.onChange then
		pcall(e.onChange, e.options[e.idx])
	end
end

local function applySnapshot(snap)
	for k, v in pairs(snap.toggles or {}) do
		UI.setToggle(k, v)
		local e = regT[k]
		if e and e.onChange then pcall(e.onChange, v) end
	end
	for k, v in pairs(snap.sliders or {}) do
		UI.setSlider(k, v)
		local e = regS[k]
		if e and e.onChange then pcall(e.onChange, v) end
	end
	for k, v in pairs(snap.drops or {}) do
		applyDrop(k, v)
	end
	for k, t in pairs(snap.chips or {}) do
		for word, on in pairs(t) do
			UI.setChip(k, word, on) -- com handler: sincroniza a Config
		end
	end
	for k, v in pairs(snap.inputs or {}) do
		UI.setInput(k, v)
	end
	if snap.lang and snap.lang ~= lang then
		setLanguage(snap.lang)
	end
end

UI.onButton("Save Config", function()
	if not fileWrite(CFG_FILE, HttpService:JSONEncode(snapshot())) then
		toast("Sem permissao de arquivo neste executor")
		return
	end
	toast("Config salva")
end)
UI.onButton("Load Config", function()
	local data = fileRead(CFG_FILE)
	if not data then
		toast("Nenhuma config salva ainda")
		return
	end
	local ok, snap = pcall(function()
		return HttpService:JSONDecode(data)
	end)
	if not ok or type(snap) ~= "table" then
		warn("[EspHouse] config corrompida: " .. tostring(snap))
		toast("Config invalida (veja Output)")
		return
	end
	local ok2, err = pcall(applySnapshot, snap)
	if not ok2 then
		warn("[EspHouse] load config: " .. tostring(err))
		toast("Erro ao carregar config")
		return
	end
	toast("Config carregada")
end)

-- ===== boot: sincroniza visual com a Config e tenta a key salva =====
UI.setToggle("Show Distance", Config.ESP.ShowDistance) -- padrao ligado
UI.setSlider("Walk Speed", Config.Player.WalkSpeedTarget)
UI.setSlider("Fly Speed", Config.Player.FlySpeed)

local cached = KeySys.loadCache()
if cached then
	keyFrame.Visible = false
	win.Visible = true
	setStatus("Key em cache ativada.", THEME.good)
	toast("Esp House v2.2 | key de teste: DEMO")
else
	toast("Preview: use a key DEMO")
end

-- API opcional no console do executor:
--   getgenv().EspHouseMenu.toggle("Fly", true)
pcall(function()
	getgenv().EspHouseMenu = {
		toggle = function(key, on)
			local e = regT[key]
			if not e then
				return false
			end
			UI.setToggle(key, on)
			if e.onChange then
				pcall(e.onChange, e.state)
			end
			return true
		end,
		toast = UI.toast,
		unload = shutdown,
	}
end)

print("[EspHouse] v2.2 carregado | key de teste: DEMO | RightShift abre o menu")

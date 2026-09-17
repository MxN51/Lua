--[[
    Build a Gun Army v.2.2
]]--

--!nonstrict
-- BaGAS v2.2 (hardened): fail-closed plot, no globals leak, os.clock, modern fly.

-- Services
print("[Script] booting...")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

if not game:IsLoaded() then game.Loaded:Wait() end
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[BaGAS] ABORT: LocalPlayer = nil (injected mid-game, not at menu)")
    return
end

-- Service connections registry (to disconnect on Unload).
-- (Connections on GUI objects are auto-cleaned by SG:Destroy().)
local Connections = {}
local function trackConn(conn) table.insert(Connections, conn) return conn end
-- Locals (ex-globaux implicites, évite pollution _G + survie après Unload)
local _buyLogged = false
local _buyDumpN = 0

local Character, Humanoid, RootPart
local function refreshChar(char)
    if not char then Character, Humanoid, RootPart = nil, nil, nil return end
    Character = char
    Humanoid = char:WaitForChild("Humanoid", 5)
    if not Humanoid then warn("[BaGAS] No Humanoid in " .. tostring(char:GetFullName())) end
    RootPart = char:WaitForChild("HumanoidRootPart", 5)
    if not RootPart then warn("[BaGAS] No HumanoidRootPart, TP paused until respawn") end
end
-- Non-bloquant: n'attend pas CharacterAdded au boot (menu sans perso)
task.spawn(function() pcall(refreshChar, LocalPlayer.Character) end)
task.spawn(function()
    local c = LocalPlayer.Character
    if not c then c = LocalPlayer.CharacterAdded:Wait() end
    if c then pcall(refreshChar, c) end
end)
trackConn(LocalPlayer.CharacterAdded:Connect(function(c) task.wait(0.5) pcall(refreshChar, c) end))

-- ============================================================
-- CONFIG
-- ============================================================
local Config = {
    MasterAutoFarm = false,
    AutoBuyAffordable = false,
    AutoPlaceUpgrade = false, -- merged Place + Upgrade (single Farm toggle)
    AutoPlace = false, -- legacy (forced by AutoPlaceUpgrade, kept for compat)
    AutoUpgrade = false, -- legacy (forced by AutoPlaceUpgrade, kept for compat)
    AutoRebirth = false,
    AutoPickupCoins = false,

    -- legacy: Filter toggles removed from Farm tab (keys kept for compat)
    EnableDPSFilter = false,
    MinDPS = 0,
    EnableRarityFilter = false,
    AutoDiscardNonAffordable = false,

    FlyEnabled = false, FlySpeed = 50,
    NoClipEnabled = false,
    WalkSpeedEnabled = false, SpeedValue = 16,
    JumpPowerEnabled = false, JumpValue = 50,
    InfiniteJump = false,

    AntiAFK = false,

    PlaceDelay = 0.5, BuyPause = 1, -- View roll pause: 0.5s = fast (names sometimes "?"), 1s = default, 2s = reliable names (Farm/Delays slider)
    RebirthWave = 20, RebirthCheckDelay = 1,

    MenuKey = Enum.KeyCode.RightShift,
    MenuOpen = false, ActiveTab = "Farm",

    BoughtCount = 0, PlacedCount = 0, UpgradedCount = 0, RebirthCount = 0, PlaceIndex = 0,
    NeedPlace = false, PlaceAttempts = 0,
    SkippedCount = 0, LastBoxAction = "-",
}

-- ============================================================
-- UTILS
-- ============================================================
local function fmt(n)
    n = tonumber(n) or 0
    if n >= 1e12 then return string.format("%.2fT", n/1e12)
    elseif n >= 1e9 then return string.format("%.2fB", n/1e9)
    elseif n >= 1e6 then return string.format("%.2fM", n/1e6)
    elseif n >= 1e3 then return string.format("%.2fK", n/1e3)
    else return tostring(n) end
end
local function notify(t, m)
    pcall(function() StarterGui:SetCore("SendNotification", {Title=t or "BaGAS", Text=m or "", Duration=3}) end)
end
local function tw(o,p,d,s,dir)
    pcall(function()
        TweenService:Create(o, TweenInfo.new(d or 0.18, s or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out), p):Play()
    end)
end
local function make(class, props)
    local inst = Instance.new(class)
    for k,v in pairs(props) do if k~="Parent" then pcall(function() inst[k]=v end) end end
    if props.Parent then inst.Parent = props.Parent end
    return inst
end

-- ============================================================
-- THEMES (multi-thèmes, interface uniquement)
-- T reste la référence courante (mêmes clés qu'avant pour compat).
-- ============================================================
local Themes = {
    Claude = {
        BG           = Color3.fromRGB(17, 17, 19),
        Surface      = Color3.fromRGB(27, 27, 31),
        Surface2     = Color3.fromRGB(40, 40, 46),
        Primary      = Color3.fromRGB(214, 120, 82),
        PrimaryDark  = Color3.fromRGB(178, 96, 60),
        PrimaryLight = Color3.fromRGB(242, 160, 110),
        Text         = Color3.fromRGB(236, 233, 227),
        TextDim      = Color3.fromRGB(158, 153, 144),
        TextFaint    = Color3.fromRGB(110, 106, 100),
        Success      = Color3.fromRGB(214, 120, 82),
        ToggleOff    = Color3.fromRGB(58, 58, 64),
        Stroke       = Color3.fromRGB(255, 255, 255),
        Danger       = Color3.fromRGB(198, 72, 72),
        Dot          = Color3.fromRGB(214, 120, 82),
    },
    Midnight = {
        BG           = Color3.fromRGB(11, 14, 21),
        Surface      = Color3.fromRGB(18, 24, 37),
        Surface2     = Color3.fromRGB(28, 36, 54),
        Primary      = Color3.fromRGB(88, 130, 255),
        PrimaryDark  = Color3.fromRGB(62, 96, 205),
        PrimaryLight = Color3.fromRGB(140, 172, 255),
        Text         = Color3.fromRGB(232, 238, 252),
        TextDim      = Color3.fromRGB(148, 162, 190),
        TextFaint    = Color3.fromRGB(100, 112, 136),
        Success      = Color3.fromRGB(88, 130, 255),
        ToggleOff    = Color3.fromRGB(48, 56, 76),
        Stroke       = Color3.fromRGB(255, 255, 255),
        Danger       = Color3.fromRGB(220, 90, 90),
        Dot          = Color3.fromRGB(88, 130, 255),
    },
    Emerald = {
        BG           = Color3.fromRGB(10, 17, 14),
        Surface      = Color3.fromRGB(17, 28, 23),
        Surface2     = Color3.fromRGB(27, 42, 34),
        Primary      = Color3.fromRGB(52, 199, 123),
        PrimaryDark  = Color3.fromRGB(36, 158, 96),
        PrimaryLight = Color3.fromRGB(110, 225, 165),
        Text         = Color3.fromRGB(230, 244, 236),
        TextDim      = Color3.fromRGB(145, 170, 155),
        TextFaint    = Color3.fromRGB(98, 120, 107),
        Success      = Color3.fromRGB(52, 199, 123),
        ToggleOff    = Color3.fromRGB(46, 60, 52),
        Stroke       = Color3.fromRGB(255, 255, 255),
        Danger       = Color3.fromRGB(220, 90, 90),
        Dot          = Color3.fromRGB(52, 199, 123),
    },
    Violet = {
        BG           = Color3.fromRGB(15, 12, 21),
        Surface      = Color3.fromRGB(24, 20, 34),
        Surface2     = Color3.fromRGB(36, 30, 52),
        Primary      = Color3.fromRGB(167, 120, 255),
        PrimaryDark  = Color3.fromRGB(130, 88, 215),
        PrimaryLight = Color3.fromRGB(195, 160, 255),
        Text         = Color3.fromRGB(238, 232, 252),
        TextDim      = Color3.fromRGB(162, 150, 190),
        TextFaint    = Color3.fromRGB(112, 102, 136),
        Success      = Color3.fromRGB(167, 120, 255),
        ToggleOff    = Color3.fromRGB(56, 50, 76),
        Stroke       = Color3.fromRGB(255, 255, 255),
        Danger       = Color3.fromRGB(220, 90, 90),
        Dot          = Color3.fromRGB(167, 120, 255),
    },
    Crimson = {
        BG           = Color3.fromRGB(18, 11, 12),
        Surface      = Color3.fromRGB(29, 19, 20),
        Surface2     = Color3.fromRGB(44, 29, 30),
        Primary      = Color3.fromRGB(235, 92, 92),
        PrimaryDark  = Color3.fromRGB(190, 66, 66),
        PrimaryLight = Color3.fromRGB(250, 140, 140),
        Text         = Color3.fromRGB(250, 232, 232),
        TextDim      = Color3.fromRGB(180, 148, 148),
        TextFaint    = Color3.fromRGB(125, 100, 100),
        Success      = Color3.fromRGB(235, 92, 92),
        ToggleOff    = Color3.fromRGB(66, 50, 50),
        Stroke       = Color3.fromRGB(255, 255, 255),
        Danger       = Color3.fromRGB(235, 92, 92),
        Dot          = Color3.fromRGB(235, 92, 92),
    },
    Arctic = {
        BG           = Color3.fromRGB(226, 232, 240),
        Surface      = Color3.fromRGB(241, 245, 249),
        Surface2     = Color3.fromRGB(203, 213, 225),
        Primary      = Color3.fromRGB(37, 99, 235),
        PrimaryDark  = Color3.fromRGB(29, 78, 190),
        PrimaryLight = Color3.fromRGB(96, 140, 250),
        Text         = Color3.fromRGB(15, 23, 42),
        TextDim      = Color3.fromRGB(71, 85, 105),
        TextFaint    = Color3.fromRGB(148, 163, 184),
        Success      = Color3.fromRGB(37, 99, 235),
        ToggleOff    = Color3.fromRGB(180, 190, 205),
        Stroke       = Color3.fromRGB(15, 23, 42),
        Danger       = Color3.fromRGB(200, 60, 60),
        Dot          = Color3.fromRGB(37, 99, 235),
    },
}
local ThemeOrder = {"Claude", "Midnight", "Emerald", "Violet", "Crimson", "Arctic"}
Config.Theme = Config.Theme or "Claude"
if not Themes[Config.Theme] then Config.Theme = "Claude" end
-- T = thème courant (mutable, mêmes clés que l'ancien T pour compat totale).
local T = {}
local RefreshThemeUI = nil -- assigné après construction du GUI (recolor live)
local function ApplyThemeData(name)
    local th = Themes[name] or Themes.Claude
    for k, v in pairs(th) do T[k] = v end
    Config.Theme = name
end
ApplyThemeData(Config.Theme)
local function setTheme(name)
    if not Themes[name] then return end
    ApplyThemeData(name)
    if RefreshThemeUI then pcall(RefreshThemeUI) end
    pcall(notify, "Theme", name .. " appliqué")
end

-- ============================================================
-- PLOT DETECTION (lightweight, cached)
-- ============================================================
local cachedPlot, _plotCacheT = nil, 0
local PLOT_CACHE_TTL = 5 -- re-valide au max toutes les 5s, évite GetDescendants à chaque cycle
local function getPlot()
    local now = os.clock()
    if cachedPlot and cachedPlot.Parent and (now - _plotCacheT) < PLOT_CACHE_TTL then return cachedPlot end
    -- 0) assignedPlot attribute (found in your dump: LocalPlayer:GetAttribute("assignedPlot") = "Plot_6")
    local assigned = LocalPlayer:GetAttribute("assignedPlot")
    if typeof(assigned)=="string" and assigned~="" then
        local plots = Workspace:FindFirstChild("Plots")
        if plots then
            local direct = plots:FindFirstChild(assigned)
            if direct then cachedPlot=direct _plotCacheT=now return direct end
        end
        local wsPlot = Workspace:FindFirstChild(assigned)
        if wsPlot and (wsPlot:IsA("Folder") or wsPlot:IsA("Model")) then
            -- vérifie ownership avant de croire le nom (anti cross-plot)
            local okOwner = false
            pcall(function()
                local o = wsPlot:FindFirstChild("Owner")
                if o and o:IsA("ValueBase") then
                    okOwner = (o.Value == LocalPlayer or o.Value == LocalPlayer.Name)
                end
                if not okOwner then
                    local av = wsPlot:GetAttribute("Owner") or wsPlot:GetAttribute("OwnerName")
                    if av == LocalPlayer.Name then okOwner = true end
                end
                if not okOwner and wsPlot:GetAttribute("assignedPlot") == nil then
                    -- sans info owner on accepte seulement si Plots/assignedPlot pointe ici
                    okOwner = true
                end
            end)
            if okOwner then cachedPlot=wsPlot _plotCacheT=now return wsPlot end
        end
        -- PAS de scan Workspace:GetDescendants() ici: trop lourd, appelé à chaque cycle.
        -- Le rescan profond est réservé au bouton Rescan / Diagnostic.
    end
    -- 1) Workspace.Plots (protégé pcall: ValueBase.Value peut throw)
    local plots = Workspace:FindFirstChild("Plots")
    if plots then
        for _, plot in ipairs(plots:GetChildren()) do
            local owned = false
            pcall(function()
                local o = plot:FindFirstChild("Owner")
                if o and o:IsA("ValueBase") then
                    local v = o.Value
                    if v == LocalPlayer or v == LocalPlayer.Name then owned = true end
                    if typeof(v) == "Instance" and v.Name == LocalPlayer.Name then owned = true end
                end
                if not owned then
                    local av = plot:GetAttribute("Owner") or plot:GetAttribute("OwnerName")
                    if av == LocalPlayer.Name then owned = true end
                end
            end)
            if owned then cachedPlot = plot _plotCacheT = os.clock() return plot end
        end
    end
    -- 2) top-level folders/models with Owner (léger: GetChildren seulement)
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("Folder") or obj:IsA("Model") then
            local owned2 = false
            pcall(function()
                local o = obj:FindFirstChild("Owner")
                if o and o:IsA("ValueBase") then
                    local v = o.Value
                    if v == LocalPlayer or v == LocalPlayer.Name then owned2 = true end
                end
                if not owned2 then
                    local av = obj:GetAttribute("Owner") or obj:GetAttribute("OwnerName")
                    if av == LocalPlayer.Name then owned2 = true end
                end
            end)
            if owned2 then cachedPlot=obj _plotCacheT=os.clock() return obj end
        end
    end
    -- FAIL-CLOSED: on ne retourne JAMAIS le plot d'un autre joueur.
    -- L'ancien "last resort: first plot with Slots" farmait le voisin.
    -- Le scan profond reste dispo via Rescan/Diagnostic uniquement.
    if cachedPlot and cachedPlot.Parent then _plotCacheT = os.clock() return cachedPlot end
    return nil
end
-- Scan profond manuel (bouton Rescan uniquement, jamais en boucle farm)
local function deepScanPlot()
    local assigned = LocalPlayer:GetAttribute("assignedPlot")
    if typeof(assigned) == "string" and assigned ~= "" then
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d.Name == assigned and (d:IsA("Folder") or d:IsA("Model")) then
                if d:FindFirstChild("WeaponBoxPrompt", true) or d:FindFirstChild("WeaponBasePart", true) then
                    cachedPlot = d _plotCacheT = os.clock() return d
                end
            end
        end
    end
    return getPlot()
end

-- cache for cash/wave (found once = reused, ultra lightweight)
local _cashObj, _cashAttrRoot, _cashAttrKey, _cashUI
local _waveObj, _waveAttrRoot, _waveAttrKey, _waveUI
local _triedHeavyCash, _triedHeavyWave = false, false
-- Parse précoce (avant getPlayerCash) pour gérer "$4.3M / 4,096.5B" dans le cache UI
local function parseMoneyEarly(t)
    if typeof(t) ~= "string" or t == "" then return nil end
    local tl = t:lower()
    local hasSuffix = tl:find("k") or tl:find("m") or tl:find("b") or tl:find("t")
    local cleaned = t:gsub("[^%d.,]", "")
    if cleaned == "" then return nil end
    if cleaned:find(",") and cleaned:find("%.") then
        cleaned = cleaned:gsub(",", "")
    else
        cleaned = cleaned:gsub(",", ".")
    end
    local n = tonumber(cleaned:match("[%d.]+"))
    if not n then return nil end
    if hasSuffix then
        if tl:find("t") then n *= 1e12 elseif tl:find("b") then n *= 1e9
        elseif tl:find("m") then n *= 1e6 elseif tl:find("k") then n *= 1e3 end
    else
        -- sans suffixe: chiffres bruts (ex "12,345" -> 12345 déjà géré)
        if not cleaned:find("%.") then n = tonumber(cleaned:gsub("%.", "")) or n end
    end
    return n
end

local function getPlayerCash()
    if _cashObj and _cashObj.Parent then
        local ok, value = pcall(function() return _cashObj.Value end)
        if ok then
            if typeof(value) == "number" then return value end
            if typeof(value) == "string" then
                local n = tonumber(value:gsub("[^%d.]", ""))
                if n then return n end
            end
        end
        _cashObj = nil
    end
    if _cashAttrRoot and _cashAttrKey then
        local av = _cashAttrRoot:GetAttribute(_cashAttrKey)
        if typeof(av)=="number" then return av end
    end
    if _cashUI and _cashUI.Parent then
        local okT, t = pcall(function() return _cashUI.Text end)
        if okT and typeof(t) == "string" then
            local n = parseMoneyEarly(t)
            if n then return n end
        end
    end
    local function tryValue(v)
        if typeof(v)=="number" then return v end
        if typeof(v)=="string" then
            local n = tonumber(v:gsub("[^%d]",""))
            if n then return n end
        end
        return nil
    end
    -- 1) leaderstats: deep scan (children + attributes, case-insensitive)
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if ls then
        for _, c in ipairs(ls:GetChildren()) do
            if c:IsA("ValueBase") then
                local n = c.Name:lower()
                if n:find("cash") or n:find("money") or n:find("coin") or n:find("gold") or n:find("currency") or n:find("balance") then
                    _cashObj = c
                    local val = tryValue(c.Value)
                    if val then return val end
                end
            end
        end
        for k,v in pairs(ls:GetAttributes()) do
            if k:lower():find("cash") or k:lower():find("money") or k:lower():find("coin") or k:lower():find("currency") then
                if typeof(v)=="number" then _cashAttrRoot=ls _cashAttrKey=k return v end
            end
        end
    end
    -- 2) LocalPlayer: shallow descendant scan (max 3 levels, cheap)
    local function scanPlayerCash(root)
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("ValueBase") then
                local n = d.Name:lower()
                if n=="cash" or n=="money" or n=="coins" or n=="coinsvalue" or n=="currency" or n:find("cash") or n:find("money") or n:find("coin") then
                    local val = tryValue(d.Value)
                    if val ~= nil then
                        _cashObj = d
                        return val
                    end
                end
            end
        end
        return nil
    end
    local v2 = scanPlayerCash(LocalPlayer)
    if v2 ~= nil then return v2 end
    -- Attribut "currency" exact vu en dump (LocalPlayer:GetAttribute("currency")) en priorité,
    -- avant le scan générique (évite de rater si nom exact sans substring cash/money).
    pcall(function()
        for _, key in ipairs({"currency", "Currency", "Cash", "cash", "Money", "money", "Coins", "coins"}) do
            local av0 = LocalPlayer:GetAttribute(key)
            if typeof(av0) == "number" then _cashAttrRoot = LocalPlayer _cashAttrKey = key v2 = av0 end
            if v2 ~= nil then return end
        end
    end)
    if v2 ~= nil then return v2 end
    for k,v in pairs(LocalPlayer:GetAttributes()) do
        if k:lower():find("cash") or k:lower():find("money") or k:lower():find("coin") or k:lower():find("currency") then
            if typeof(v)=="number" then _cashAttrRoot=LocalPlayer _cashAttrKey=k return v end
            if typeof(v)=="string" then local n=tonumber(v:gsub("[^%d.]","")) if n then _cashAttrRoot=LocalPlayer _cashAttrKey=k return n end end
        end
    end
    -- 2b) ReplicatedStorage: heavy scan only once
    if not _triedHeavyCash then
        _triedHeavyCash = true
        local rsCash = nil
        pcall(function()
            local rs = ReplicatedStorage
            for _, d in ipairs(rs:GetDescendants()) do
                if d:IsA("ValueBase") and d.Name:lower():find("cash") then
                    if d:GetAttribute("Owner")==LocalPlayer.Name or d.Parent.Name:lower():find(LocalPlayer.Name:lower()) then
                        _cashObj=d rsCash=tryValue(d.Value) return
                    end
                end
            end
        end)
        if rsCash ~= nil then return rsCash end
    end
    -- 3) inside the plot
    local plot = getPlot()
    if plot then
        for _, name in ipairs({"Cash","Money","Coins","Currency"}) do
            local obj = plot:FindFirstChild(name)
            if obj and obj:IsA("ValueBase") then _cashObj=obj return tryValue(obj.Value) or 0 end
            local av = plot:GetAttribute(name)
            if typeof(av)=="number" then _cashAttrRoot=plot _cashAttrKey=name return av end
        end
        for _, c in ipairs(plot:GetDescendants()) do
            if c:IsA("ValueBase") and c.Name:lower():find("cash") then _cashObj=c return tryValue(c.Value) or 0 end
        end
    end
    -- 4) PlayerGui text containing $ (last resort, heavy once then cached)
    if _cashUI and _cashUI.Parent then
        local t=_cashUI.Text local n=tonumber(t:gsub("[^%d]","")) if n then return n end
    end
    if not _triedHeavyCash then
        -- already marked tried above, we scan GUI only if RS was already tried
        -- doing it here at the same time (once only)
    end
    local guiCash = nil
    if not _cashUI then
        pcall(function()
            local pg = LocalPlayer:FindFirstChild("PlayerGui")
            if pg then
                for _, d in ipairs(pg:GetDescendants()) do
                    if d:FindFirstAncestor("BaGASMenu") then
                        -- ignore our own GUI
                    elseif d:IsA("TextLabel") or d:IsA("TextButton") then
                        local t = d.Text
                        if t and t:find("%$") then
                            local num = t:gsub("[^%d]","")
                            local n = tonumber(num)
                            if n and n > 0 and n < 1e15 then
                                local parentName = d.Parent and d.Parent.Name:lower() or ""
                                if parentName:find("cash") or parentName:find("money") or parentName:find("coin") or t:find("Cash") or t:find("Money") or d.Name:lower():find("cash") then
                                    _cashUI = d
                                    guiCash = n
                                    break
                                end
                            end
                        end
                        if d.Name:lower():find("cash") or (d.Parent and d.Parent.Name:lower():find("cash")) then
                            local num2 = t:gsub("[^%d]","")
                            local n2 = tonumber(num2)
                            if n2 and n2>0 then _cashUI=d guiCash=n2 break end
                        end
                    end
                end
            end
        end)
        if guiCash then return guiCash end
    end
    return 0
end

local function getPlayerWave()
    if _waveObj and _waveObj.Parent then
        local ok, val = pcall(function() return _waveObj.Value end)
        if ok and typeof(val)=="number" then return val end
        if ok and typeof(val)=="string" then local n=tonumber(val:gsub("[^%d]","")) if n then return n end end
    end
    if _waveAttrRoot and _waveAttrKey then
        local av = _waveAttrRoot:GetAttribute(_waveAttrKey)
        if typeof(av)=="number" then return av end
    end
    if _waveUI and _waveUI.Parent then
        local t = _waveUI.Text
        local n = tonumber(t:gsub("[^%d]",""))
        if n then return n end
    end
    local function tryNum(v)
        if typeof(v)=="number" then return v end
        if typeof(v)=="string" then local n=tonumber(v:gsub("[^%d]","")) if n then return n end end
        return nil
    end
    -- NOMS STRICTS "wave": "Level"/"Stage" exclus (Level=1 du joueur bloquait la wave à 1,
    -- idem Stage statique). La wave ne se lit que via des sources contenant "wave".
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if ls then
        for _, c in ipairs(ls:GetChildren()) do
            if c:IsA("ValueBase") then
                local n = c.Name:lower()
                if n:find("wave") then
                    _waveObj=c
                    local val = tryNum(c.Value)
                    if val then return val end
                end
            end
        end
        for _, key in ipairs({"Wave","Waves","CurrentWave","WaveNumber"}) do
            local av = ls:GetAttribute(key)
            if typeof(av)=="number" then _waveAttrRoot=ls _waveAttrKey=key return av end
        end
    end
    -- Plot AVANT le joueur: CurrentWave du plot = source la plus fiable (dump: 57).
    -- Le Level=1 du joueur ne doit jamais passer avant.
    do
        local plotFirst = getPlot()
        if plotFirst then
            for _, name in ipairs({"CurrentWave","CurrentWaveValue","Wave","Waves","WaveNumber"}) do
                local obj = plotFirst:FindFirstChild(name)
                if obj and obj:IsA("ValueBase") then
                    local v0 = tryNum(obj.Value)
                    if v0 then _waveObj = obj return v0 end
                end
                local av0 = plotFirst:GetAttribute(name)
                if typeof(av0)=="number" then _waveAttrRoot=plotFirst _waveAttrKey=name return av0 end
                for k,v in pairs(plotFirst:GetAttributes()) do
                    if k:lower()==name:lower() and typeof(v)=="number" then _waveAttrRoot=plotFirst _waveAttrKey=k return v end
                end
            end
            for k,v in pairs(plotFirst:GetAttributes()) do
                if k:lower():find("wave") and typeof(v)=="number" then _waveAttrRoot=plotFirst _waveAttrKey=k return v end
            end
        end
    end
    -- LocalPlayer descendants
    for _, d in ipairs(LocalPlayer:GetDescendants()) do
        if d:IsA("ValueBase") then
            local n=d.Name:lower()
            if n:find("wave") then
                if d.Parent==LocalPlayer or d.Parent.Name:lower():find("wave") or d.Parent.Name:lower():find("data") then
                    _waveObj=d
                    local v=tryNum(d.Value) if v then return v end
                end
            end
        end
    end
    for _, name in ipairs({"Wave","Waves","CurrentWave","WaveNumber"}) do
        local av = LocalPlayer:GetAttribute(name)
        if typeof(av)=="number" then _waveAttrRoot=LocalPlayer _waveAttrKey=name return av end
    end
    local plot = getPlot()
    if plot then
        for _, c in ipairs(plot:GetDescendants()) do
            if c:IsA("ValueBase") and c.Name:lower():find("wave") then
                _waveObj=c
                local v=tryNum(c.Value) if v then return v end
            end
        end
    end
    -- PlayerGui fallback: text "Wave 12" (cached after 1 scan); we ignore the BaGAS GUI itself
    if _waveUI and _waveUI.Parent then
        local t=_waveUI.Text local n=tonumber(t:gsub("[^%d]","")) if n then return n end
    end
    if not _triedHeavyWave then
        _triedHeavyWave = true
        local guiWave = nil
        local bestUI, bestN = nil, 0
        pcall(function()
            local pg = LocalPlayer:FindFirstChild("PlayerGui")
            if pg then
                for _, d in ipairs(pg:GetDescendants()) do
                    if not d:FindFirstAncestor("BaGASMenu") and d:IsA("TextLabel") then
                        local t = d.Text
                        if t and t:lower():find("wave") then
                            local n = tonumber(t:gsub("[^%d]",""))
                            if n and n > bestN then bestN=n bestUI=d end
                        end
                    end
                end
            end
        end)
        if bestUI then _waveUI=bestUI return bestN end
    end
    return 0
end

-- Debug helper: dump all possible sources for cash/wave
local function dumpCurrencySources()
    print("=== CURRENCY / WAVE SOURCES ===")
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if ls then
        print("leaderstats children:")
        for _, c in ipairs(ls:GetChildren()) do
            print("  ", c.ClassName, c.Name, "=", tostring(c.Value))
            for ak, av in pairs(c:GetAttributes()) do print("    attr", ak, "=", tostring(av)) end
        end
        print("leaderstats attributes:")
        for k,v in pairs(ls:GetAttributes()) do print("  attr", k, "=", tostring(v)) end
    else print("No leaderstats") end
    print("LocalPlayer children + descendants ValueBase:")
    for _, d in ipairs(LocalPlayer:GetDescendants()) do
        if d:IsA("ValueBase") then
            print("  ", d:GetFullName(), "=", tostring(d.Value))
        end
    end
    print("LocalPlayer attributes:")
    for k,v in pairs(LocalPlayer:GetAttributes()) do print("  attr", k, "=", tostring(v)) end
    print("assignedPlot attr:", tostring(LocalPlayer:GetAttribute("assignedPlot")))
    print("currency attr:", tostring(LocalPlayer:GetAttribute("currency")), " Type:", typeof(LocalPlayer:GetAttribute("currency")))
    local plot = getPlot()
    if plot then
        print("Plot", plot.Name, "ValueBase (descendants):")
        for _, d in ipairs(plot:GetDescendants()) do
            if d:IsA("ValueBase") then print("  ", d.Name, "=", tostring(d.Value), " parent=", d.Parent.Name) end
        end
        print("Plot attributes:")
        for k,v in pairs(plot:GetAttributes()) do print("  plot attr", k, "=", tostring(v)) end
    else print("No plot") end
    print("PlayerGui TextLabels avec $ ou Wave:")
    pcall(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            for _, d in ipairs(pg:GetDescendants()) do
                if d:IsA("TextLabel") or d:IsA("TextButton") then
                    local t = d.Text
                    if t and (t:find("%$") or t:lower():find("wave") or t:lower():find("cash") or t:lower():find("money")) then
                        print("  UI:", d:GetFullName(), " text='", t, "'")
                    end
                end
            end
        end
    end)
    print("Cash via getPlayerCash():", getPlayerCash())
    print("Wave via getPlayerWave():", getPlayerWave())
    print("=== END CURRENCY SOURCES ===")
end

-- ============================================================
-- PROMPTS (lightweight)
-- ============================================================
local _fppFn, _fppNextRetry = nil, 0 -- retry périodique si injecté en retard
local function getRemoteFire()
    local now = os.clock()
    if _fppFn == nil or (_fppFn == false and now >= _fppNextRetry) then
        local f = rawget(_G, "fireproximityprompt")
        if typeof(f) ~= "function" and typeof(getgenv) == "function" then
            pcall(function() f = getgenv().fireproximityprompt end)
        end
        if typeof(f) == "function" then _fppFn = f
        else _fppFn = false _fppNextRetry = now + 10 end
    end
    if _fppFn == false then return nil end
    return _fppFn
end
local function hasRemoteFire() return getRemoteFire() ~= nil end
-- Direct Hold (simulated E key in place): fallback quand remote fire absent.
-- Ne mute plus RequiresLineOfSight définitivement (restauré après).
local function firePromptLegacy(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end
    if prompt.Enabled == false then return false end
    local prevLOS
    local ok = pcall(function()
        local hold = prompt.HoldDuration or 0
        prevLOS = prompt.RequiresLineOfSight
        prompt.RequiresLineOfSight = false
        if prompt.Enabled then
            prompt:InputHoldBegin()
            task.wait(hold > 0 and hold + 0.1 or 0.2)
            prompt:InputHoldEnd()
        end
    end)
    pcall(function()
        if prevLOS ~= nil then prompt.RequiresLineOfSight = prevLOS end
    end)
    return ok
end
local function firePrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end
    if prompt.Enabled == false then return false end
    -- ATTENTION: fireproximityprompt ne bypass pas toujours la distance côté serveur.
    -- Le TP reste nécessaire (géré par l'appelant). Ici on fire + vérifie Enabled.
    local fpp = getRemoteFire()
    if fpp then
        local ok = pcall(fpp, prompt)
        return ok
    end
    return firePromptLegacy(prompt)
end
-- Physical part associated with a prompt (to TP within range)
-- NB: MeshPart/UnionOperation héritent de BasePart -> un seul FindFirstChildWhichIsA suffit.
local function getPromptPart(prompt)
    if not prompt then return nil end
    local parent = prompt.Parent
    if parent then
        if parent:IsA("BasePart") then
            return parent
        end
        local part = parent:FindFirstChildWhichIsA("BasePart", true)
        if part then return part end
    end
    return nil
end
local function gotoPart(part, height)
    if not part or not RootPart or not RootPart.Parent then return false end
    if not part:IsDescendantOf(game) then return false end
    local ok = pcall(function()
        -- vélocités tuées AVANT et APRÈS (sinon le perso garde l'élan et ragdoll à l'arrivée)
        RootPart.AssemblyLinearVelocity = Vector3.zero
        RootPart.AssemblyAngularVelocity = Vector3.zero
        RootPart.CFrame = part.CFrame + Vector3.new(0, height or 2, 0)
        RootPart.AssemblyLinearVelocity = Vector3.zero
        RootPart.AssemblyAngularVelocity = Vector3.zero
    end)
    return ok
end
-- Anti-trip autour d'un TP (le perso tombe de +3 studs et le Humanoid trip/ragdoll) :
-- on désactive trip AVANT, on relève + réactive APRÈS la chute. Même bloc = resto garantie.
local function setTripDisabled(disabled)
    pcall(function()
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, not disabled)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, not disabled)
        end
    end)
end
-- Anti-ragdoll après un TP (le perso tombe de +3 studs et le Humanoid trip/ragdoll) :
-- on relève + on tue l'élan. Appelé après les waits de chute, jamais pendant le vol.
local function stabilizeAfterTP()
    pcall(function()
        if RootPart and RootPart.Parent then
            RootPart.AssemblyLinearVelocity = Vector3.zero
            RootPart.AssemblyAngularVelocity = Vector3.zero
        end
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            local st = hum:GetState()
            if st == Enum.HumanoidStateType.Ragdoll
                or st == Enum.HumanoidStateType.FallingDown
                or st == Enum.HumanoidStateType.Physics then
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
            if hum.Seated then hum.Seated = false end
        end
    end)
end
local _fcdFn, _fcdNextRetry = nil, 0
local function getFireClick()
    local now = os.clock()
    if _fcdFn == nil or (_fcdFn == false and now >= _fcdNextRetry) then
        local f = rawget(_G, "fireclickdetector")
        if typeof(f) ~= "function" and typeof(getgenv) == "function" then
            pcall(function() f = getgenv().fireclickdetector end)
        end
        if typeof(f) == "function" then _fcdFn = f
        else _fcdFn = false _fcdNextRetry = now + 10 end
    end
    if _fcdFn == false then return nil end
    return _fcdFn
end
local function fireClick(det)
    if not det or not det:IsA("ClickDetector") then return false end
    local fcd = getFireClick()
    if typeof(fcd) == "function" then
        return pcall(fcd, det)
    end
    return false
end
local _fsFn, _fsNextRetry = nil, 0 -- cache firesignal avec retry
local function getFireSignal()
    local now = os.clock()
    if _fsFn == nil or (_fsFn == false and now >= _fsNextRetry) then
        local f = rawget(_G, "firesignal")
        if typeof(f) ~= "function" and typeof(getgenv) == "function" then
            pcall(function() f = getgenv().firesignal end)
        end
        if typeof(f) == "function" then _fsFn = f
        else _fsFn = false _fsNextRetry = now + 10 end
    end
    if _fsFn == false then return nil end
    return _fsFn
end
-- firetouchinterest : SEUL moyen fiable de ramasser un loot server-sided sans TP joueur.
local _ftiFn, _ftiNextRetry = nil, 0
local function getFireTouch()
    local now = os.clock()
    if _ftiFn == nil or (_ftiFn == false and now >= _ftiNextRetry) then
        local f = rawget(_G, "firetouchinterest")
        if typeof(f) ~= "function" and typeof(getgenv) == "function" then
            pcall(function() f = getgenv().firetouchinterest end)
        end
        if typeof(f) == "function" then _ftiFn = f
        else _ftiFn = false _ftiNextRetry = now + 10 end
    end
    if _ftiFn == false then return nil end
    return _ftiFn
end
-- Rafale firetouchinterest: tous les begin d'un coup, 1 seul wait, tous les end.
-- 60 coins en ~0.1s au lieu de 60x0.1s en un-par-un (l'ancien fireTouch attendait
-- 0.05s PAR pièce, ce qui bloquait la boucle farm).
local function fireTouchBatch(parts, target, cap)
    local fti = getFireTouch()
    if typeof(fti) ~= "function" then return 0 end
    if not target or not target.Parent then return 0 end
    cap = math.min(cap or #parts, #parts)
    for i = 1, cap do
        local part = parts[i]
        if part and part.Parent then
            pcall(function() fti(part, target, 0) end)
        end
    end
    task.wait(0.08)
    for i = 1, cap do
        local part = parts[i]
        if part and part.Parent then
            pcall(fti, part, target, 1)
        end
    end
    return cap
end
-- Real mouse click at button center (when firesignal is absent).
-- Hide our menu during the click, restoration GUARANTEED even if click fails
-- (otherwise BaGAS menu stays hidden - bug seen in-game).
local function clickButtonReal(btn)
    local pos, size
    pcall(function() pos, size = btn.AbsolutePosition, btn.AbsoluteSize end)
    if not pos or not size or size.X < 2 or size.Y < 2 then return false end
    -- Keep BaGAS visible: hiding Main here caused the apparent close/open flicker.
    local x, y = pos.X + size.X / 2, pos.Y + size.Y / 2
    local clicked = false
    -- attempt 1: synthetic mouse click
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game)
        clicked = true
    end)
    -- attempt 2: Enter key on focused button (if mouse click failed;
    -- ignored if button is not selectable, otherwise engine spams an error)
    if not clicked then
        local selectable = false
        pcall(function() selectable = btn.Selectable ~= false end)
        if selectable then
            pcall(function()
                -- Do not assign GuiService.SelectedObject. Some game buttons are not
                -- selectable GuiObjects and Roblox displays an invalid-GuiObject warning.
                clicked = false
            end)
        end
        pcall(function() game:GetService("GuiService").SelectedObject = nil end)
        if not clicked and os.clock()%8<0.6 then print("[Gui] VIM non supporté : aucun clic possible") end
    end
    return clicked
end
-- Software click on a game button (e.g. big yellow Rebirth button)
-- FIX: un seul signal (Activated prioritaire, sinon MouseButton1Click). Double-fire = double achat.
local function clickButton(btn)
    if not btn or not btn:IsA("GuiButton") then return false end
    if not btn.Visible then
        local vis = true
        pcall(function()
            local p = btn
            while p and p ~= game do
                if p:IsA("GuiObject") and not p.Visible then vis = false break end
                p = p.Parent
            end
        end)
        if not vis then
            if os.clock()%10<0.6 then print("[Gui] Bouton caché, clic ignoré:", btn:GetFullName()) end
            return false
        end
    end
    local fs = getFireSignal()
    if fs then
        -- Activated couvre la plupart des jeux modernes ; fallback Click sinon
        local okA = pcall(fs, btn.Activated)
        if okA then return true end
        local ok1 = pcall(fs, btn.MouseButton1Click)
        if ok1 then return true end
    end
    -- fallback : vrai clic souris (firesignal absent ou inefficace)
    if os.clock()%8<0.6 then print("[Gui] Clic souris réel sur", btn:GetFullName()) end
    return clickButtonReal(btn)
end
-- Click sur Frame/ImageLabel (ex: RebirthFrame) : vrai clic VIM au centre.
-- L'ancien fake InputObject table était rejeté ; le firesignal seul ne suffit pas sur une Frame.
local function clickFrameReal(guiObj)
    local pos, size = nil, nil
    pcall(function() pos, size = guiObj.AbsolutePosition, guiObj.AbsoluteSize end)
    if not pos or not size or size.X < 2 or size.Y < 2 then return false end
    local vis = true
    pcall(function()
        local p = guiObj
        while p and p ~= game do
            if p:IsA("GuiObject") and not p.Visible then vis = false break end
            p = p.Parent
        end
    end)
    if not vis then return false end
    local x, y = pos.X + size.X / 2, pos.Y + size.Y / 2
    local ok = false
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game)
        ok = true
    end)
    return ok
end
local function fireGuiInput(guiObj)
    if guiObj:IsA("GuiButton") then
        return clickButton(guiObj)
    end
    -- Frame: firesignal InputBegan (si jeu l'écoute) PUIS vrai clic VIM (marche sans firesignal)
    local fs = getFireSignal()
    if fs then
        pcall(function()
            -- InputBegan sans faux InputObject typé: certaines implémentations UNC acceptent 0 arg
            local sig = (guiObj :: any).InputBegan
            if sig then fs(sig) end
        end)
    end
    return clickFrameReal(guiObj)
end
local function findRebirthGui()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    return pg:FindFirstChild("RebirthGui", true)
end
local function findPrompt(parent, keywords)
    if not parent then return nil end
    -- direct
    for _, k in ipairs(keywords) do
        local c = parent:FindFirstChild(k)
        if c and c:IsA("ProximityPrompt") then return c end
    end
    -- descendants (limité au parent, pas tout Workspace)
    for _, d in ipairs(parent:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            for _, k in ipairs(keywords) do
                if d.Name:lower():find(k:lower(),1,true) then return d end
            end
        end
    end
    return nil
end

-- ============================================================
-- FARM LOGIC
-- ============================================================
local getPendingSignature, findPendingObject, pendingWeaponName, findRolledWeapon, rolledIdentity, findOverheadWeapon, stripRich, rolledStableKey, rolledHasOffer -- forward : définis plus bas, utilisés par le buy
-- Weapon Box: find the physical part (for visible TP onto it)
local function findWeaponBoxPart(plot)
    if not plot then return nil end
    for _, name in ipairs({"WeaponBoxBuy","WeaponBox","MysteryBox","Shop","Crate","Box"}) do
        local obj = plot:FindFirstChild(name, true)
        if obj then
            if obj:IsA("BasePart") or obj:IsA("MeshPart") or obj:IsA("UnionOperation") then
                return obj
            end
            local part = obj:FindFirstChildWhichIsA("BasePart", true) or obj:FindFirstChildWhichIsA("MeshPart", true)
            if part then return part end
        end
    end
    for _, d in ipairs(plot:GetDescendants()) do
        local n = d.Name:lower()
        if n:find("weaponbox") or n:find("mysterybox") or n:find("weaponcrate") then
            if d:IsA("BasePart") or d:IsA("MeshPart") or d:IsA("UnionOperation") then
                return d
            end
            if d.Parent and (d.Parent:IsA("BasePart") or d.Parent:IsA("MeshPart")) then
                return d.Parent
            end
        end
    end
    return nil
end

-- Real box price read from game UI (WeaponBoxGui > ... > ItemPrice "$4.3M")
-- Handles: "$4.3M", "$4,096.5B" (US thousands), "$4.10T" (FR decimal)
local function parseMoneyText(t)
    if typeof(t) ~= "string" or t == "" then return nil end
    local cleaned = t:gsub("[^%d.,]", "")
    if cleaned == "" then return nil end
    if cleaned:find(",") and cleaned:find("%.") then
        cleaned = cleaned:gsub(",", "") -- virgule = séparateur de milliers ("4,096.5")
    else
        cleaned = cleaned:gsub(",", ".") -- virgule = décimale FR ("4,10")
    end
    local n = tonumber(cleaned:match("[%d.]+"))
    if not n then return nil end
    local mult = 1
    local tl = t:lower()
    if tl:find("t") then mult = 1e12
    elseif tl:find("b") then mult = 1e9
    elseif tl:find("m") then mult = 1e6
    elseif tl:find("k") then mult = 1e3 end
    return n * mult
end
local function getWeaponBoxPrice()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local gui = pg:FindFirstChild("WeaponBoxGui", true)
    if not gui then return nil end
    -- PASS 1: nom contient "price" (chemin officiel ItemPrice)
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            if d.Name:lower():find("price") then
                local raw = ""
                pcall(function() raw = d.Text or "" end)
                local p = parseMoneyText(raw)
                if p then return p, raw end
            end
        end
    end
    -- PASS 2: tout texte avec $ + suffixe K/M/B/T (le nom varie selon versions)
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local raw = ""
            pcall(function() raw = d.Text or "" end)
            if typeof(raw) == "string" and raw:find("%$") then
                local p = parseMoneyText(raw)
                -- prix box = montant plausible (>0, <1e18), pas un dégât à 12$
                if p and p > 0 and p < 1e18 then return p, raw end
            end
        end
    end
    return nil
end
-- Box GUI button: BuyButton (buy) / DiscardButton (discard)
-- FIX: exclut les boutons Robux ("buyrobux", "buy r$") qui déclencheraient le popup.
local function findBoxButton(nameKeys, textKeys)
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local gui = pg:FindFirstChild("WeaponBoxGui", true)
    if not gui then return nil end
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("TextButton") or d:IsA("ImageButton") then
            local n = d.Name:lower()
            if n:find("robux", 1, true) or n:find("r%$") then continue end
            local t = ""
            pcall(function() t = d.Text or "" end)
            local tl = t:lower()
            if tl:find("robux", 1, true) or tl:find("r%$") then continue end
            for _, k in ipairs(nameKeys) do
                if n:find(k, 1, true) then return d end
            end
            for _, k in ipairs(textKeys) do
                if tl:find(k, 1, true) then return d end
            end
        end
    end
    return nil
end
-- Official box remotes (source WeaponBoxGuiScript):
-- Buy = RemoteEvents.WeaponBoxBuy:FireServer()  /  Discard = RemoteEvents.WeaponBoxDiscard:FireServer()
-- + découverte floue cachée (le nom exact varie selon MAJ) : 1er scan profond, ensuite cache.
local _boxRemotesCache, _boxRemotesT, _boxRemotesLogT = nil, 0, 0
local function getBoxRemotes()
    local now = os.clock()
    if _boxRemotesCache and (now - _boxRemotesT) < 30 then
        return _boxRemotesCache[1], _boxRemotesCache[2]
    end
    local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
    local buy, disc = nil, nil
    if folder then
        pcall(function()
            buy = folder:FindFirstChild("WeaponBoxBuy")
            disc = folder:FindFirstChild("WeaponBoxDiscard")
        end)
    end
    if buy and not buy:IsA("RemoteEvent") then buy = nil end
    if disc and not disc:IsA("RemoteEvent") then disc = nil end
    pcall(function()
        if not buy then
            local b2 = ReplicatedStorage:FindFirstChild("WeaponBoxBuy", true)
            if b2 and b2:IsA("RemoteEvent") then buy = b2 end
        end
        if not disc then
            local d2 = ReplicatedStorage:FindFirstChild("WeaponBoxDiscard", true)
            if d2 and d2:IsA("RemoteEvent") then disc = d2 end
        end
        -- Fallback flou: tout RemoteEvent avec "box"+"buy"/"roll"/"open" (1 seul scan profond)
        if (not buy or not disc) and folder then
            for _, d in ipairs(folder:GetChildren()) do
                if d:IsA("RemoteEvent") then
                    local n = d.Name:lower()
                    if not buy and n:find("box") and (n:find("buy") or n:find("roll") or n:find("open")) then buy = d end
                    if not disc and n:find("box") and (n:find("discard") or n:find("delete") or n:find("trash") or n:find("reroll")) then disc = d end
                end
            end
        end
    end)
    _boxRemotesCache, _boxRemotesT = {buy, disc}, now
    if (buy == nil or disc == nil) and (now - _boxRemotesLogT) > 15 then
        _boxRemotesLogT = now
        print("[Buy] Remotes: buy=" .. tostring(buy and buy:GetFullName() or "nil") .. " disc=" .. tostring(disc and disc:GetFullName() or "nil"))
    end
    return buy, disc
end

-- ============================================================
-- ANTI-ROBUX POPUP (strict fail-closed)
-- Server responds to ANY too-expensive attempt with the popup
-- "Buy Robux and item / Instant Money". So we touch
-- nothing as soon as price is unknown, cash is unknown (0),
-- or funds are insufficient. No "let's try anyway".
-- ============================================================
local function canAffordNow(price)
    if typeof(price) ~= "number" or price <= 0 then return false end
    local cash = 0
    pcall(function() cash = getPlayerCash() end)
    if typeof(cash) ~= "number" or cash <= 0 then return false end
    return cash >= price
end
-- Close the Robux popup if it appears anyway (safety net).
-- Roblox prompt closes with Escape: we simulate the key.
local function closeRobuxPopup()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Escape, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
    end)
    -- + direct click on prompt close buttons (X / Close / Cancel)
    -- Limité au ScreenGui du popup (pas tout CoreGui en aveugle)
    pcall(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        local scopes = {}
        if pg then table.insert(scopes, pg) end
        if typeof(gethui) == "function" then
            local okH, hui = pcall(gethui)
            if okH and hui then table.insert(scopes, hui) end
        end
        for _, cont in ipairs(scopes) do
            if cont then
                for _, d in ipairs(cont:GetDescendants()) do
                    if d:IsA("TextLabel") then
                        local okT, txt = pcall(function() return d.Text end)
                        if okT and typeof(txt) == "string"
                        and (txt:find("Buy Robux") or txt:find("Instant Money")) then
                        local root = d:FindFirstAncestorWhichIsA("ScreenGui") or d.Parent
                        if root then
                            for _, b in ipairs(root:GetDescendants()) do
                                if b:IsA("GuiButton") then
                                    local bt = ""
                                    pcall(function() bt = b.Text or b.Name or "" end)
                                    if bt == "X" or bt:lower():find("close") or bt:lower():find("cancel") or b.Name:lower():find("close") then
                                        pcall(function()
                                            local fs = getFireSignal()
                                            if fs then pcall(fs, b.Activated) end
                                        end)
                                    end
                                end
                            end
                        end
                        break
                        end
                    end
                end
            end
        end
    end)
end
-- Detect if Robux popup is visible (for cooldown + auto-close).
-- THROTTLÉ 1s + early-out: l'ancien scan CoreGui complet toutes les 0.5s lagguait.
local _popupCacheV, _popupCacheT = false, 0
local function isRobuxPopupVisible()
    local now = os.clock()
    if now - _popupCacheT < 1 then return _popupCacheV end
    local found = false
    pcall(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then
            -- cherche seulement les ScreenGui récents / prompts, pas tout PlayerGui en profondeur aveugle
            for _, d in ipairs(pg:GetDescendants()) do
                if d:IsA("TextLabel") then
                    local okT, txt = pcall(function() return d.Text end)
                    if okT and typeof(txt) == "string"
                        and (txt:find("Buy Robux") or txt:find("Instant Money")) then
                        local vis = true
                        pcall(function()
                            local p = d
                            while p and p ~= game do
                                if p:IsA("GuiObject") and not p.Visible then vis = false break end
                                p = p.Parent
                            end
                        end)
                        if vis then found = true break end
                    end
                end
                if found then break end
            end
        end
        -- CoreGui/gethui uniquement si rien trouvé (accès protégé, coûteux)
        if not found and typeof(gethui) == "function" then
            local okH, hui = pcall(gethui)
            if okH and hui then
                for _, d in ipairs(hui:GetDescendants()) do
                    if d:IsA("TextLabel") then
                        local okT, txt = pcall(function() return d.Text end)
                        if okT and typeof(txt) == "string" and (txt:find("Buy Robux") or txt:find("Instant Money")) then
                            found = true break
                        end
                    end
                end
            end
        end
    end)
    _popupCacheV, _popupCacheT = found, now
    return found
end

local function triggerWeaponBox()
    local plot = getPlot()
    if not plot then
        if os.clock()%5<0.6 then print("[Buy] No plot detected - box TP impossible") end
        return false
    end
    -- PASS 1: precise box keywords (never a slot)
    local prompt = findPrompt(plot, {"WeaponBoxPrompt","MysteryBox","ShopPrompt","BuyWeapon","OpenBox"})
    if not prompt then
        -- PASS 2: generic, but we EXCLUDE slot prompts (WeaponBasePart),
        -- otherwise buy would randomly fire one of the 42 slots instead of the box
        for _, d in ipairs(plot:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local par = d.Parent
                if not (par and par.Name == "WeaponBasePart") then
                    local n = d.Name:lower()
                    if n:find("box") or n:find("buy") or n:find("roll") or n:find("shop") then
                        prompt = d
                        break
                    end
                end
            end
        end
    end
    if not prompt then
        -- fallback ClickDetector (some games use this)
        for _, d in ipairs(plot:GetDescendants()) do
            if d:IsA("ClickDetector") then
                local n = d.Parent and d.Parent.Name:lower() or ""
                if n:find("box") or n:find("weapon") or n:find("shop") or n:find("buy") then
                    if fireClick(d) then Config.BoughtCount += 1 return true end
                end
            end
        end
        return false
    end
    -- known price? (used for skip AND purchase confirmation via cash decrease)
    -- Skip also applies in MASTER, otherwise master buys without checking price
    local buyPrice
    if Config.AutoBuyAffordable or Config.MasterAutoFarm then
        local box = plot:FindFirstChild("WeaponBox", true) or plot:FindFirstChild("WeaponBoxBuy", true)
        if box then
            buyPrice = box:GetAttribute("Cost") or box:GetAttribute("Price") or box:GetAttribute("cost") or box:GetAttribute("price")
            -- le prix peut être sur le parent (ex: WeaponBox model) ou sur le prompt lui-même
            if not buyPrice then
                pcall(function()
                    local par = box.Parent
                    if par then buyPrice = par:GetAttribute("Cost") or par:GetAttribute("Price") end
                end)
            end
        end
        -- prix sur l'offre déjà présente (source la plus fiable après un roll)
        if not buyPrice then
            pcall(function()
                local rw0 = findRolledWeapon(plot)
                if rw0 and rolledHasOffer(rw0) then
                    local c0 = rw0:GetAttribute("Cost")
                    if typeof(c0) == "number" and c0 > 0 then buyPrice = c0 end
                end
            end)
        end
        -- UI stale après discard: juste après un discard réussi, l'UI affiche encore
        -- l'ancien prix cher -> on l'ignore pour rouvrir aussitôt (sinon deadlock).
        local justDiscarded = (os.clock() - (Config.JustDiscardedT or -99)) < 3
        if not buyPrice and not justDiscarded then
            local p2, raw2 = getWeaponBoxPrice()
            buyPrice = p2
            if raw2 and os.clock()%10<0.6 then print("[Buy] Price brut UI: '" .. raw2 .. "'") end
        elseif justDiscarded and os.clock()%8<0.6 then
            print("[Buy] Post-discard: prix UI ignoré (stale), réouverture...")
        end
        if buyPrice then
            Config.LastBoxPrice = buyPrice
        elseif os.clock()%10<0.6 then
            print("[Buy] Price not found (probe: 1 ouverture pour révéler l'UI, sinon voir Diagnostic)")
        end
    end
    -- TP to box if far - ALWAYS (even if too expensive: we only re-TP from far,
    -- so no loop, and user sees the movement)
    local promptPart = prompt and getPromptPart(prompt) or nil
    local tpTarget = promptPart or findWeaponBoxPart(plot)
    -- prefer the Zone: game requires TOUCHING it (Zone.Touched) to validate
    pcall(function()
        local boxM = plot:FindFirstChild("WeaponBox", true)
        local z = boxM and boxM:FindFirstChild("Zone", true)
        if z and (z:IsA("BasePart") or z:IsA("MeshPart") or z:IsA("UnionOperation")) then
            tpTarget = z
        end
    end)
    if tpTarget and RootPart then
        local dist = 9999
        pcall(function() dist = (RootPart.Position - tpTarget.Position).Magnitude end)
        local range = (prompt and prompt.MaxActivationDistance) or 10
        if dist > math.min(range, 10) then
            setTripDisabled(true)
            gotoPart(tpTarget, 3)
            if os.clock()%8<0.6 then
                print("[Buy] TP to box:", tpTarget:GetFullName(), "| plot:", plot.Name, "| prompt:", prompt.Name)
            end
            -- laisse la position se répliquer + toucher la Zone (le serveur valide la
            -- distance ET le touch) avant de firer, sinon le 1er open est rejeté.
            -- Trip désactivé pendant la chute -> pas de ragdoll à l'atterrissage.
            task.wait(0.5)
            stabilizeAfterTP()
            setTripDisabled(false)
        end
    elseif not tpTarget and os.clock()%5<0.6 then
        print("[Buy] Box not found in", plot.Name, "- firing prompt without TP")
    end
    -- (too-expensive skip is done lower, by offered weapon: BUY if affordable, DISCARD otherwise)
    if not _buyLogged then
        _buyLogged = true
        print("[Buy] Firing prompt:", prompt.Name, "(", prompt.Parent and prompt.Parent.Name or "?", ")")
    end
    local cashBefore = getPlayerCash()
    local sigBefore = getPendingSignature()
    local function buyDump()
        _buyDumpN = (_buyDumpN or 0) + 1
        if _buyDumpN > 2 then return end
        pcall(function()
            local rwD = findRolledWeapon(getPlot())
            if rwD then
                print("[Buy] RolledWeapon:", string.sub(rolledIdentity(rwD) or "?", 1, 300))
            else
                print("[Buy] Pas de RolledWeapon dans la box")
            end
            local chD = LocalPlayer.Character
            if chD then
                for _, c in ipairs(chD:GetChildren()) do
                    if c:IsA("Model") or c:IsA("Tool") then print("[Buy] Overhead:", c.ClassName, c.Name) end
                end
            end
            local po = findPendingObject()
            if po then
                print("[Buy] Pending:", po:GetFullName(), "| class:", po.ClassName)
            else
                print("[Buy] Pending nom:", tostring(pendingWeaponName()))
            end
        end)
    end
    local function boxOpened()
        local opened = false
        pcall(function()
            local cashAfter = getPlayerCash()
            if cashAfter < cashBefore then
                if buyPrice and buyPrice > 0 then
                    if (cashBefore - cashAfter) >= buyPrice * 0.5 then opened = true end
                else
                    opened = true
                end
            end
            local sigAfter = getPendingSignature()
            if sigAfter and sigAfter ~= sigBefore and sigAfter ~= Config.LastPlacedSig then
                opened = true
            end
        end)
        return opened
    end
    -- GARDE ANTI-POPUP SANS DEADLOCK:
    -- - box VIDE + prix/cash connus + fonds insuffisants -> on attend (pas de popup :
    --   le roll lui-même coûte, ex: 30.20M vs 1.05M).
    -- - offre DÉJÀ PRÉSENTE -> JAMAIS de blocage ici : la Phase 2 gère (BUY si abordable,
    --   DISCARD rapide sinon). Bloquer sur le prix de l'offre empêchait tout skip.
    -- - si prix OU cash INCONNUS -> on autorise 1 PROBE throttlé 2s (fire + check popup
    --   immédiat). Sans probe, l'UI prix n'apparaît jamais et le buy reste mort à vie.
    -- (check offre hissé ici pour servir aussi à la Phase 1 -> 1 seul scan)
    local _rwCheck = findRolledWeapon(plot)
    local _offerPresent = (_rwCheck ~= nil and rolledHasOffer(_rwCheck))
    do
        local cashO = 0
        pcall(function() cashO = getPlayerCash() end)
        local priceKnown = (typeof(buyPrice) == "number" and buyPrice > 0)
        local cashKnown = (typeof(cashO) == "number" and cashO > 0)
        -- a popup is open: we close it and touch nothing this cycle
        if isRobuxPopupVisible() then
            closeRobuxPopup()
            Config.LastPopupT = os.clock()
            return false
        end
        if (os.clock() - (Config.LastPopupT or 0)) < 5 then return false end
        if _offerPresent then
            -- rien à ouvrir, on laisse passer vers Phase 2 (buy/discard), quel que soit cash
            if os.clock()%10<0.6 then print("[Buy] Offre présente, décision Phase 2 (prix " .. (buyPrice and fmt(buyPrice) or "?") .. " | cash " .. fmt(cashO) .. ")") end
        elseif priceKnown and cashKnown then
            if (os.clock() - (Config.LastTooExpensiveT or 0)) < 5 then
                local need = (Config.LastTooExpensivePrice or buyPrice) * 1.05
                if cashO < need then
                    if os.clock()%8<0.6 then print("[Buy] Too-expensive cooldown - waiting for funds:", fmt(cashO), "<", fmt(need)) end
                    return false
                end
            end
            local needOpen = math.max(buyPrice, Config.LastTooExpensivePrice or 0)
            if cashO < needOpen then
                if os.clock()%8<0.6 then print("[Buy] Waiting for funds before opening - price:", fmt(buyPrice), "| cash:", fmt(cashO)) end
                return false
            end
        else
            -- PROBE: 1 tentative / 2s max quand détection incomplète (même rythme que
            -- l'open throttle, sinon la 1re ouverture met 6s+ et paraît morte).
            if (os.clock() - (Config.LastProbeT or 0)) < 2 then return false end
            if not priceKnown and not cashKnown then
                if os.clock()%8<0.6 then print("[Buy] Prix+cash inconnus -> probe unique (voir Diagnostic si répété)") end
            elseif not priceKnown then
                if os.clock()%8<0.6 then print("[Buy] Prix inconnu (cash " .. fmt(cashO) .. ") -> probe unique") end
            else
                if os.clock()%8<0.6 then print("[Buy] Cash inconnu (prix " .. fmt(buyPrice) .. ") -> probe unique") end
            end
            Config.LastProbeT = os.clock()
            -- pas de return: on laisse la PHASE 1 firer UNE fois, le check popup juste après sécurise
        end
        Config.OpenUnknownSince = nil
    end
    -- PHASE 1: OPENING seulement si PAS d'offre réelle (le template vide ne compte pas,
    -- sinon la box ne s'ouvre plus jamais après un achat). Ne reroll jamais sur une offre.
    -- (Bought counter only increases on VERIFIED acquisition, not on fires)
    -- Throttle 2s between attempts (otherwise roll animation glitches).
    -- (_rwCheck déjà scanné dans la garde ci-dessus)
    if not _offerPresent then
        if (os.clock() - (Config.LastOpenFireT or 0)) < 2 then return false end
        Config.LastOpenFireT = os.clock()
        firePrompt(prompt)
        task.wait(0.25)
        -- opening itself can trigger popup if price estimate
        -- was stale: we close it immediately and memorize refused price.
        if isRobuxPopupVisible() then
            print("[Buy] Robux popup after opening → closing, waiting for funds")
            closeRobuxPopup()
            Config.LastPopupT = os.clock()
            Config.LastTooExpensivePrice = buyPrice
            Config.LastTooExpensiveT = os.clock()
            return false
        end
        if not boxOpened() and hasRemoteFire() then
            if os.clock()%8<0.6 then print("[Buy] Remote fire had no effect, trying direct hold") end
            firePromptLegacy(prompt)
            task.wait(0.25)
            if isRobuxPopupVisible() then
                closeRobuxPopup()
                Config.LastPopupT = os.clock()
                Config.LastTooExpensivePrice = buyPrice
                Config.LastTooExpensiveT = os.clock()
                return false
            end
        end
    end
    -- PHASE 2: offered weapon → BUY (affordable) or DISCARD (too expensive, frees box)
    -- (if opening directly charged, it was a direct purchase: no buttons needed)
    local openBought = boxOpened()
    local rw = findRolledWeapon(plot)
    if not rw or not rolledHasOffer(rw) then
        Config.LastPreviewSig = nil
        -- ne reset LastRolledInst que si vraiment rien (template seul): évite respam log
        if not rw then Config.LastRolledInst = nil end
        if openBought then
            Config.BoughtCount += 1
            Config.NeedPlace = true
            Config.PlaceAttempts = 0
            Config.LastTooExpensivePrice = nil
            Config.LastTooExpensiveT = nil
            if os.clock()%5<0.6 then print("[Buy] Purchase confirmed on opening - placement needed") end
            buyDump()
            return true
        end
        return false
    end
    -- Witness: does offered instance change? (no = DISCARD ineffective, box stuck)
    -- + INFALLIBLE "new roll" detector: 2 identical consecutive rolls or unreadable roll ("?")
    -- have same sig, but NEVER same instance → showcase pause no longer skipped.
    local isNewInst = (Config.LastRolledInst ~= rw)
    if isNewInst then
        Config.LastRolledInst = rw
        if os.clock() - (Config.LastNewRollLog or 0) > 3 then
            Config.LastNewRollLog = os.clock()
            print("[Buy] New offer:", tostring(pendingWeaponName() or "?"))
        end
    end
    -- OFFICIAL PRICE: Cost attribute of rolled weapon (game source, priority over UI),
    -- otherwise re-read UI (UI updates in 0.1s via game script)
    local priceFromOffer = false
    pcall(function()
        local c = rw:GetAttribute("Cost")
        if typeof(c) == "number" and c > 0 then buyPrice = c priceFromOffer = true end
    end)
    if not buyPrice then
        local pu = getWeaponBoxPrice()
        if pu then buyPrice = pu end
    end
    if buyPrice then Config.LastBoxPrice = buyPrice end
    -- Prix toujours inconnu après roll: on attend 2 cycles pour laisser l'UI se mettre à jour,
    -- puis DISCARD (gratuit, jamais de popup) pour libérer la box au lieu de rester bloqué à vie.
    if typeof(buyPrice) ~= "number" or buyPrice <= 0 then
        local sig = tostring(rolledStableKey(rw) or tostring(rw:GetDebugId() or "?"))
        if Config.PriceUnknownSig ~= sig then
            Config.PriceUnknownSig = sig
            Config.PriceUnknownT = os.clock()
            if os.clock()%5<0.6 then print("[Buy] Prix offre inconnu, attente UI...") end
            return false
        end
        if (os.clock() - (Config.PriceUnknownT or 0)) < 4 then return false end
        -- 4s sans prix -> discard de sécurité (throttlé 2s)
        if (os.clock() - (Config.LastDiscardFireT or 0)) > 2 then
            Config.LastDiscardFireT = os.clock()
            local _, rdisc2 = getBoxRemotes()
            if rdisc2 then pcall(function() rdisc2:FireServer() end) task.wait(0.3) end
            print("[Buy] Prix introuvable après 4s -> discard sécurité (box libérée)")
        end
        Config.PriceUnknownSig = nil
        return false
    else
        Config.PriceUnknownSig = nil
    end
    local unitName, unitTier = nil, nil
    local function readNames()
        pcall(function()
            local un = rw:GetAttribute("unitName")
            local ut = rw:GetAttribute("unitTier")
            if typeof(un) == "string" and un ~= "" then unitName = stripRich(un) end
            if ut ~= nil then unitTier = stripRich(tostring(ut)) end
        end)
        pcall(function()
            local gui = rw:FindFirstChild("WeaponBillboardGui", true)
            local frame = gui and gui:FindFirstChild("WeaponBoardFrame", true)
            local scope = frame or rw
            local function label(nm)
                local o = scope:FindFirstChild(nm, false) or rw:FindFirstChild(nm, true)
                if o then
                    local okT, txt = pcall(function() return o.Text end)
                    if okT and typeof(txt) == "string" then
                        txt = stripRich(txt)
                        if #txt > 2 then return txt end
                    end
                end
                return nil
            end
            if not unitName then unitName = label("UnitTextName") end
            local rar = label("UnitTextRarity")
            if rar and (not unitTier or not unitTier:lower():find(rar:lower(), 1, true)) then
                unitTier = (unitTier and (unitTier .. " ") or "") .. rar
            end
            if not unitTier then unitTier = label("UnitTier") or label("UnitTierSymbol") end
        end)
    end
    readNames()
    -- FAST-SKIP: offre manifestement trop chère (prix source OFFRE, pas estimation) ->
    -- on saute la pause showcase et on discard aussitôt au lieu d'attendre 1s+ pour rien.
    local fastDiscard = false
    if priceFromOffer and typeof(buyPrice) == "number" and buyPrice > 0 then
        local cashQ = 0
        pcall(function() cashQ = getPlayerCash() end)
        if typeof(cashQ) == "number" and cashQ > 0 and cashQ < buyPrice then
            fastDiscard = true
            print("[Buy] Roll trop cher, skip rapide (" .. fmt(buyPrice) .. " > " .. fmt(cashQ) .. ")")
        end
    end
    -- SHOWCASE PAUSE: let animation/visual play BEFORE deciding (otherwise invisible).
    -- Once per roll: new instance OR new content (same weapon 2x in a row = 2 pauses).
    -- Adjustable: "View roll pause" slider (click value to type exact number).
    -- (sautée en fastDiscard: le prix offre suffit, pas besoin d'attendre les noms)
    if not fastDiscard then
        local rsig = tostring(rolledStableKey(rw) or "?")
        local isNew = isNewInst or (Config.LastPreviewSig ~= rsig)
        if isNew then
            Config.LastPreviewSig = rsig
            local pause = math.clamp(tonumber(Config.BuyPause) or 1, 0.5, 5) -- 0.5s = rapide ("?" possibles), 1s = défaut, 2s = noms fiables
            print("[Buy] Showcase: pause " .. tostring(pause) .. "s (" .. string.sub(rsig, 1, 60) .. ")")
            task.wait(pause)
        end
        readNames() -- ALWAYS fresh (not only on first preview): otherwise "?" stuck
        if unitName then
            -- memorize last NAMED roll (name + price + time)
            Config.LastKnownName, Config.LastKnownTier, Config.LastKnownPrice, Config.LastKnownT = unitName, unitTier, buyPrice, os.clock()
        elseif buyPrice and buyPrice == Config.LastKnownPrice and (os.clock() - (Config.LastKnownT or 99)) < 15 then
            -- game replaces model with a copy WITHOUT billboard just before/after purchase
            -- (same price = same weapon): reuse name instead of showing "+ ?"
            unitName, unitTier = Config.LastKnownName, Config.LastKnownTier
        end
        if isNew then
            print("[Buy] Roll: " .. tostring(unitName or "?") .. " | tier: " .. tostring(unitTier or "?") .. " | price: " .. (buyPrice and fmt(buyPrice) or "?"))
        end
    end
    local cash = 0
    pcall(function() cash = getPlayerCash() end)
    local rbuy, rdisc = getBoxRemotes()
    -- Cash inconnu: DISCARD reste sûr (gratuit), mais BUY est risqué (popup).
    -- On discard si on a un discard disponible pour ne pas bloquer la box,
    -- sinon on attend 1 cycle (laisse le cache cash se remplir).
    if typeof(cash) ~= "number" or cash <= 0 then
        if rdisc and (os.clock() - (Config.LastDiscardFireT or 0)) > 3 then
            -- prix inconnu? on a déjà géré plus haut. Ici prix connu mais cash inconnu:
            -- on ne buy pas, mais on ne bloque pas non plus si l'offre est manifestement
            -- hors de prix via LastTooExpensive.
            if os.clock()%5<0.6 then print("[Buy] Cash inconnu, attente cache (discard dispo, box non bloquée)...") end
        elseif os.clock()%5<0.6 then
            print("[Buy] Cash inconnu (" .. tostring(cash) .. "), vérifie Settings>Diagnostic Cash/Wave. Ni buy ni discard ce cycle.")
        end
        return false
    end
    if cash < buyPrice then
        if not Config.WasPricedOut then
            Config.WasPricedOut = true
            notify("Buy", "Too expensive (" .. fmt(buyPrice) .. " > " .. fmt(cash) .. ") - discarded, next")
        end
        if os.clock()%5<0.6 then print("[Buy] Too expensive, DISCARD - price:", fmt(buyPrice), "| cash:", fmt(cash)) end
        -- Discard vérifié: remote PUIS bouton GUI si la box est toujours occupée.
        -- (Le remote seul peut être ignoré sans effet, comme le Buy l'était.)
        -- Le throttle ne valide JAMAIS à lui seul: seule la disparition de l'offre compte.
        local function discardDone(rwBefore)
            task.wait(0.3)
            local gone = false
            pcall(function()
                if not rwBefore or rwBefore.Parent == nil then gone = true end
                local rwNow = findRolledWeapon(plot)
                if rwNow ~= rwBefore then gone = true end
                if rwNow and not rolledHasOffer(rwNow) then gone = true end
            end)
            return gone
        end
        local discarded = false
        if rdisc and (os.clock() - (Config.LastDiscardFireT or 0)) > 1 then
            Config.LastDiscardFireT = os.clock()
            if os.clock()%8<0.6 then print("[Buy] FireServer WeaponBoxDiscard") end
            pcall(function() rdisc:FireServer() end)
            if discardDone(rw) then discarded = true end
        end
        if not discarded then
            local dbtn = findBoxButton({"discardbutton", "discard", "delete", "trash", "skip"}, {"discard", "delete", "trash", "jeter", "suppr", "skip"})
            if dbtn then
                if os.clock()%8<0.6 then print("[Buy] Clic DiscardButton (" .. dbtn:GetFullName() .. ")") end
                clickButton(dbtn)
                if discardDone(rw) then
                    discarded = true
                else
                    -- firesignal ignoré par le jeu? Vrai clic souris en dernier recours.
                    if os.clock()%8<0.6 then print("[Buy] Discard non confirmé, vrai clic...") end
                    clickButtonReal(dbtn)
                    if discardDone(rw) then discarded = true end
                end
            elseif not rdisc and os.clock()%8<0.6 then
                print("[Buy] Ni remote ni DiscardButton trouvés")
            end
        end
        if discarded then
            -- box libérée: reset l'état d'offre pour que le prochain cycle ROUVRE aussitôt
            Config.LastRolledInst = nil
            Config.LastPreviewSig = nil
            Config.LastDiscardCountedSig = nil
            Config.LastTooExpensivePrice = nil -- pas de cooldown après un discard réussi
            Config.LastTooExpensiveT = nil
            Config.JustDiscardedT = os.clock()
            Config.LastProbeT = 0 -- réautorise le probe immédiat (prix UI stale ignoré)
            Config.LastOpenFireT = 0
        end
        local dsig = tostring(rolledStableKey(rw) or "?")
        if Config.LastDiscardCountedSig ~= dsig then
            Config.LastDiscardCountedSig = dsig
            Config.SkippedCount += 1
        end
        Config.LastBoxAction = "x " .. tostring(unitName or "?") .. " (" .. fmt(buyPrice) .. ")"
        if os.clock()%8<0.6 then print("[Buy] x Discarded:", tostring(unitName or "?"), tostring(unitTier or ""), "(" .. fmt(buyPrice) .. " too expensive)") end
        if not discarded then
            -- memorize refused price SEULEMENT si la box est toujours occupée :
            -- après un discard réussi on veut rouvrir aussitôt, pas attendre.
            -- (L'UI peut être stale 1 cycle, mais le cooldown est géré par LastDiscardFireT.)
            Config.LastTooExpensivePrice = buyPrice
            Config.LastTooExpensiveT = os.clock()
        end
        return false
    end
    Config.WasPricedOut = false
    -- ANTI-POPUP: FINAL re-check at instant T (anti race-condition with
    -- parallel upgrade that may have spent in between). No wait between
    -- this check and following FireServer.
    if not canAffordNow(buyPrice) then
        if os.clock()%5<0.6 then print("[Buy] Insufficient funds at instant T, purchase cancelled (anti-popup)") end
        local freshCash = 0
        pcall(function() freshCash = getPlayerCash() end)
        if typeof(freshCash) == "number" and freshCash > 0 and freshCash < buyPrice then
            Config.LastTooExpensivePrice = buyPrice
            Config.LastTooExpensiveT = os.clock()
        end
        if isRobuxPopupVisible() then closeRobuxPopup() Config.LastPopupT = os.clock() end
        return false
    end
    -- Vérif multi-signaux: cash peut arrondir ($29 vs 381.92K), overhead peut tarder.
    -- On valide si AU MOINS un signal bouge après 0.4s (laisse le serveur répliquer).
    local function confirmBought(cashB, ohPre, sigBefore, rwBefore, plotRef)
        task.wait(0.4)
        local ok = false
        pcall(function()
            if getPlayerCash() < cashB then ok = true end
            local ohNow = findOverheadWeapon()
            if ohNow and ohNow ~= ohPre then ok = true end
            local sigNow = getPendingSignature()
            if sigNow and sigNow ~= sigBefore then ok = true end
            if rwBefore then
                if rwBefore.Parent == nil then ok = true end
                local rwNow = findRolledWeapon(plotRef)
                if rwNow ~= rwBefore then ok = true end
            end
        end)
        return ok
    end
    local function markBought(src)
        Config.BoughtCount += 1
        Config.NeedPlace = true
        Config.PlaceAttempts = 0
        Config.LastTooExpensivePrice = nil
        Config.LastTooExpensiveT = nil
        if os.clock()%5<0.6 then print("[Buy] Purchase confirmed (" .. tostring(src) .. ") - placement needed") end
        print("[Buy] + " .. tostring(unitName or "?") .. " " .. tostring(unitTier or "") .. " (" .. (buyPrice and fmt(buyPrice) or "?") .. ")")
        Config.LastBoxAction = "+ " .. tostring(unitName or "?") .. " (" .. (buyPrice and fmt(buyPrice) or "?") .. ")"
        buyDump()
    end
    -- DIRECT SERVER PURCHASE (remote d'abord, puis bouton BUY même si remote existe :
    -- le remote seul peut être ignoré sans args, le bouton GUI est la voie officielle vue en jeu)
    do
        local cashB = getPlayerCash()
        local ohPre = findOverheadWeapon()
        local sigPre = getPendingSignature()
        local fired = false
        if rbuy then
            if os.clock()%8<0.6 then print("[Buy] FireServer WeaponBoxBuy") end
            pcall(function() rbuy:FireServer() end)
            fired = true
            task.wait(0.3)
            if isRobuxPopupVisible() then
                print("[Buy] Robux popup detected after purchase attempt → closing + memorizing price")
                closeRobuxPopup()
                Config.LastPopupT = os.clock()
                Config.LastTooExpensivePrice = buyPrice
                Config.LastTooExpensiveT = os.clock()
                return false
            end
            if confirmBought(cashB, ohPre, sigPre, rw, plot) then markBought("remote") return true end
        end
        -- fallback GUI: TOUJOURS essayé si le remote n'a pas confirmé (pas seulement si absent)
        if not canAffordNow(buyPrice) then
            if os.clock()%5<0.6 then print("[Buy] Insufficient funds at instant T, Buy click cancelled (anti-popup)") end
            if isRobuxPopupVisible() then closeRobuxPopup() Config.LastPopupT = os.clock() end
            return false
        end
        local bbtn = findBoxButton({"buybutton", "buy"}, {"buy", "achet"})
        if bbtn then
            if os.clock()%8<0.6 then print("[Buy] Clic BuyButton (" .. bbtn:GetFullName() .. ")") end
            local cashB2 = getPlayerCash()
            local ohPre2 = findOverheadWeapon()
            local sigPre2 = getPendingSignature()
            clickButton(bbtn)
            if isRobuxPopupVisible() then
                closeRobuxPopup()
                Config.LastPopupT = os.clock()
                Config.LastTooExpensivePrice = buyPrice
                Config.LastTooExpensiveT = os.clock()
                return false
            end
            if confirmBought(cashB2, ohPre2, sigPre2, rw, plot) then markBought("gui") return true end
            if not fired and os.clock()%8<0.6 then
                print("[Buy] Ni remote ni BuyButton n'a confirmé (cash " .. fmt(getPlayerCash()) .. " vs prix " .. fmt(buyPrice) .. ")")
            end
        elseif not rbuy and os.clock()%8<0.6 then
            print("[Buy] Neither remote nor BuyButton found")
        end
    end
    -- last resort: re-fire le prompt BOX (E Buy vu en jeu) + prompt interne arme (1x/3s)
    -- ANTI-POPUP: never claim if too expensive / price or cash unknown.
    if (os.clock() - (Config.LastClaimT or 0)) > 3 then
        if not canAffordNow(buyPrice) then
            if os.clock()%8<0.6 then print("[Buy] Claim cancelled (too expensive or price/cash unknown, anti-popup)") end
        else
            Config.LastClaimT = os.clock()
            -- 1) prompt box lui-même (E Buy sur le coffre) : dans ce jeu c'est lui qui vend
            pcall(function()
                if prompt and prompt.Parent then
                    print("[Buy] Re-fire box prompt (last resort)")
                    firePrompt(prompt)
                end
            end)
            task.wait(0.3)
            if isRobuxPopupVisible() then
                closeRobuxPopup()
                Config.LastPopupT = os.clock()
                Config.LastTooExpensivePrice = buyPrice
                Config.LastTooExpensiveT = os.clock()
                return false
            end
            if boxOpened() then
                -- la box a réagi (cash/pending bougé) : laisse le prochain cycle confirmer
                return false
            end
            local claim = rw:FindFirstChild("WeaponProxPrompt", true)
            if claim and claim:IsA("ProximityPrompt") then
                print("[Buy] Claim rolled weapon (last resort)")
                firePrompt(claim)
                task.wait(0.3)
                if isRobuxPopupVisible() then
                    closeRobuxPopup()
                    Config.LastPopupT = os.clock()
                    Config.LastTooExpensivePrice = buyPrice
                    Config.LastTooExpensiveT = os.clock()
                end
            end
        end
    end
    return false
end
local function buyWeaponBox() return triggerWeaponBox() end

-- REAL game slots: parts "WeaponBasePart" (parents of 42 WeaponProxPrompt).
-- CACHE 5s: GetDescendants() à chaque cycle = lag. Tri stable par nom court.
local _slotsCache, _slotsPlot, _slotsT = {}, nil, 0
local function findWeaponSlots(plot)
    if not plot then return {} end
    local now = os.clock()
    if plot == _slotsPlot and (now - _slotsT) < 5 and #_slotsCache > 0 then return _slotsCache end
    local list, seen = {}, {}
    for _, d in ipairs(plot:GetDescendants()) do
        -- EXCLUDE box content (internal RolledWeapon/WeaponBasePart trapped the finder)
        if d:FindFirstAncestor("WeaponBox") or d:FindFirstAncestor("RolledWeapon") then continue end
        if d.Name == "WeaponBasePart" and d:IsA("BasePart") then
            if not seen[d] then seen[d] = true table.insert(list, d) end
        elseif d:IsA("ProximityPrompt") and d.Name:lower():find("weaponproxprompt", 1, true) then
            local p = d.Parent
            if p and p:IsA("BasePart") then
                if not seen[p] then seen[p] = true table.insert(list, p) end
            end
        end
    end
    table.sort(list, function(a, b) return a.Name < b.Name end)
    _slotsCache, _slotsPlot, _slotsT = list, plot, now
    return list
end

-- Occupied/empty heuristic: attributes, prompt text (Place vs Upgrade),
-- children (placed units can be Model/ValueBase)
local function slotHasWeapon(slot)
    if slot:GetAttribute("Occupied") == true or slot:GetAttribute("HasWeapon") == true then return true end
    if slot:GetAttribute("UnitId") ~= nil or slot:GetAttribute("WeaponId") ~= nil or slot:GetAttribute("Unit") ~= nil then return true end
    for _, c in ipairs(slot:GetChildren()) do
        if c:IsA("Model") or c:IsA("Tool") or c:IsA("ValueBase") then return true end
        if not c:IsA("ProximityPrompt") and not c:IsA("ClickDetector") then
            local n = c.Name:lower()
            if n:find("weapon") or n:find("gun") or n:find("unit") or n:find("tower") then return true end
        end
    end
    -- placed units sometimes live in Folder Units: prompt text betrays state
    local pr = slot:FindFirstChildOfClass("ProximityPrompt")
    if pr then
        local at = ((pr.ActionText or "") .. " " .. (pr.ObjectText or "")):lower()
        if at:find("upgrade") or at:find("level") or at:find("collect") or at:find("sell") then return true end
    end
    return false
end

local function findSlots(plot)
    -- OBSOLETE: this game has no "Slots" folder (see findWeaponSlots).
    -- Kept for compat: returns nil.
    return nil
end

-- Rolled weapon pending INSIDE the box (Model WeaponBox/RolledWeapon).
-- Scoring: les attributs priment LARGEMENT (l'ancien `+ #Descendants` choisissait le template vide),
-- mais on retourne TOUJOURS le meilleur (jamais nil si un RolledWeapon existe) pour ne pas
-- bloquer buy/place en boucle Phase1. C'est à l'appelant de gérer le prix inconnu.
findRolledWeapon = function(plot)
    if not plot then return nil end
    local best, bestScore = nil, -1
    pcall(function()
        for _, d in ipairs(plot:GetDescendants()) do
            if d.Name == "RolledWeapon" and d:IsA("Model") then
                local score = 0
                pcall(function()
                    if d:GetAttribute("unitName") then score += 100 end
                    if d:GetAttribute("Cost") then score += 50 end
                    if d:GetAttribute("unitTier") then score += 20 end
                end)
                -- enfants plafonnés à +1 pour départager, jamais pour battre les attrs
                pcall(function() score += math.min(#d:GetDescendants(), 10) * 0.1 end)
                if d:FindFirstAncestor("WeaponBox") then score += 5 end
                if score > bestScore then best, bestScore = d, score end
            end
        end
    end)
    return best
end
-- Offre RÉELLE vs template vide: le template "RolledWeapon" existe même box fermée
-- (sans unitName/Cost). Sans ce check, la Phase 1 croit qu'une offre est présente
-- et ne fire jamais l'ouverture. Utilisé UNIQUEMENT par le buy (place intouché).
rolledHasOffer = function(rw)
    if not rw then return false end
    -- STRICT: unitName requis. Le template vide n'a ni unitName ni Cost,
    -- et son billboard peut contenir un placeholder ("?", "Weapon") -> on l'ignore.
    -- (Cost seul ne suffit pas: le template peut porter le prix de base.)
    local hasName, hasCost, hasLabel = false, false, false
    pcall(function()
        local un = rw:GetAttribute("unitName")
        if typeof(un) == "string" and un ~= "" then hasName = true end
        local co = rw:GetAttribute("Cost")
        if typeof(co) == "number" and co > 0 then hasCost = true end
    end)
    if hasName then return true end
    -- Timing roll (attrs pas encore répliqués <0.5s): Cost + vrai nom billboard ensemble
    pcall(function()
        local o = rw:FindFirstChild("UnitTextName", true)
        if o then
            local okT, txt = pcall(function() return o.Text end)
            if okT and typeof(txt) == "string" then
                local clean = stripRich(txt)
                if #clean > 2 and clean ~= "?" and clean:lower() ~= "weapon" then hasLabel = true end
            end
        end
    end)
    if hasCost and hasLabel then return true end
    return false
end
-- Clean billboard rich-text ("<font ...>Epic</font>" -> "Epic")
stripRich = function(s)
    if typeof(s) ~= "string" then return "" end
    s = s:gsub("<[^>]+>", "")
    s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s
end
-- STABLE weapon key (names/rarities/price only - not DPS/XP/level/targets that change).
-- Used for signatures, slot memory and counters (anti-duplicates/loops).
rolledStableKey = function(rw)
    if not rw then return nil end
    local parts = {}
    pcall(function()
        local un = rw:GetAttribute("unitName")
        local ut = rw:GetAttribute("unitTier")
        local co = rw:GetAttribute("Cost")
        if typeof(un) == "string" and un ~= "" then table.insert(parts, "n=" .. un) end
        if ut ~= nil then table.insert(parts, "t=" .. tostring(ut)) end
        if typeof(co) == "number" then table.insert(parts, "c=" .. tostring(co)) end
    end)
    pcall(function()
        local gui = rw:FindFirstChild("WeaponBillboardGui", true)
        local frame = gui and gui:FindFirstChild("WeaponBoardFrame", true)
        local scope = frame or rw
        for _, nm in ipairs({"UnitTextName", "UnitTextRarity", "UnitTierSymbol", "UnitTier"}) do
            local o = scope:FindFirstChild(nm, false) or rw:FindFirstChild(nm, true)
            if o then
                local okT, txt = pcall(function() return o.Text end)
                if okT and typeof(txt) == "string" then
                    txt = stripRich(txt)
                    if #txt > 0 then table.insert(parts, nm .. "=" .. txt) end
                end
            end
        end
    end)
    if #parts == 0 then return nil end
    return table.concat(parts, "|")
end
-- Rolled weapon identity : attributs + noms d'enfants + textes des billboards
rolledIdentity = function(rw)
    if not rw then return nil end
    local parts = {rw.Name}
    pcall(function()
        for k, v in pairs(rw:GetAttributes()) do table.insert(parts, k .. "=" .. tostring(v)) end
    end)
    pcall(function()
        for _, c in ipairs(rw:GetDescendants()) do
            table.insert(parts, c.Name)
            local okT, txt = pcall(function() return c.Text end)
            if okT and typeof(txt) == "string" and txt ~= "" then
                table.insert(parts, txt)
            end
        end
    end)
    return table.concat(parts, " | ")
end

-- Pending weapon signature (change à chaque nouvelle arme / shiny / electric / cosmic)
-- Le template vide de la box est IGNORÉ (sinon "rolled:?" fantôme arme NeedPlace en boucle
-- et le place tourne tous les slots pour une arme qui n'existe pas).
getPendingSignature = function()
    local plot0 = getPlot()
    if plot0 then
        local rw0 = findRolledWeapon(plot0)
        if rw0 and rolledHasOffer(rw0) then
            return "rolled:" .. (rolledStableKey(rw0) or "?")
        end
    end
    local char = LocalPlayer.Character
    if char then
        for _, obj in ipairs(char:GetDescendants()) do
            if obj.Name:lower():find("pending") then
                return obj:GetFullName() .. "|" .. obj.ClassName
            end
        end
    end
    -- visuel au-dessus de la tête (toute pièce non-standard du perso ou flottant au-dessus)
    local ohS = findOverheadWeapon()
    if ohS then return "overhead:" .. ohS.Name end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, obj in ipairs(bp:GetChildren()) do
            if obj:IsA("Tool") and obj.Name:lower():find("pending") then
                return "bp:" .. obj.Name
            end
        end
    end
    for k, v in pairs(LocalPlayer:GetAttributes()) do
        local kl = k:lower()
        if kl:find("pending") or kl:find("newweapon") or kl:find("tobeplaced") then
            return "attr:" .. k .. "=" .. tostring(v)
        end
    end
    local plot = getPlot()
    if plot then
        for k, v in pairs(plot:GetAttributes()) do
            local kl = k:lower()
            if kl:find("pending") then
                return "plot:" .. k .. "=" .. tostring(v)
            end
        end
    end
    return nil
end

-- Objet pending brut (pour lire son NOM = type d'arme récupérée)
findPendingObject = function()
    local char = LocalPlayer.Character
    if char then
        for _, obj in ipairs(char:GetDescendants()) do
            if obj.Name:lower():find("pending") then return obj end
        end
    end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, obj in ipairs(bp:GetChildren()) do
            if obj:IsA("Tool") and obj.Name:lower():find("pending") then return obj end
        end
    end
    return nil
end
-- Weapon visual ABOVE DE LA TÊTE : Model/Tool en enfant direct du perso
-- (a normal character only has Parts/Accessories/Humanoid directly),
-- otherwise Model floating just above player in Workspace
-- Standard body parts (to ignore in weapon visual detection)
local _stdBody = {head=true, torso=true, uppertorso=true, lowertorso=true, humanoidrootpart=true, ["left arm"]=true, ["right arm"]=true, ["left leg"]=true, ["right leg"]=true, leftupperarm=true, leftlowerarm=true, lefthand=true, rightupperarm=true, rightlowerarm=true, righthand=true, leftupperleg=true, leftlowerleg=true, leftfoot=true, rightupperleg=true, rightlowerleg=true, rightfoot=true, humanoid=true, bodycolors=true, shirt=true, pants=true, shirtgraphic=true}
local _stdClass = {Script=true, LocalScript=true, ModuleScript=true, Accessory=true, Shirt=true, Pants=true, BodyColors=true, CharacterMesh=true, Humanoid=true, HumanoidDescription=true, Animator=true, Folder=true}
local _coinLike = {coin=true, loot=true, drop=true, cash=true, money=true, orb=true, currency=true}
local function _coinName(n)
    n = n:lower()
    for k in pairs(_coinLike) do if n:find(k, 1, true) then return true end end
    return false
end
-- Cache throttle overhead (locals, PAS de champs sur la fonction: Luau interdit func._x)
local _overheadCacheV, _overheadCacheT = nil, 0
findOverheadWeapon = function()
    local char = LocalPlayer.Character
    if char then
        for _, obj in ipairs(char:GetChildren()) do
            if not _stdClass[obj.ClassName] then
                if obj:IsA("Model") or obj:IsA("Tool") then return obj end
                if not _stdBody[obj.Name:lower()] then return obj end
            end
        end
    end
    -- Fallback Workspace: TOUT modèle flottant au-dessus (sémantique d'origine qui fait marcher
    -- buy+place), mais via GetPartBoundsInBox throttlé 1s au lieu de GetChildren()+GetPivot() total.
    -- PAS de filtre par nom: une arme peut s'appeler "AK-47", "Pistol", etc.
    if RootPart and RootPart.Parent then
        local now = os.clock()
        if (_overheadCacheT or 0) + 1 > now and _overheadCacheV ~= nil then
            local c = _overheadCacheV
            if c == false then return nil end
            local okPar = false
            pcall(function() okPar = (c :: any).Parent ~= nil end)
            if okPar then return c end
        end
        _overheadCacheT = now
        local found = nil
        pcall(function()
            local rp = RootPart.Position
            local parts = Workspace:GetPartBoundsInBox(
                CFrame.new(rp + Vector3.new(0, 5, 0)),
                Vector3.new(14, 18, 14)
            )
            for _, pt in ipairs(parts) do
                local m = pt:FindFirstAncestorWhichIsA("Model")
                if m and not _coinName(m.Name) and not m:IsDescendantOf(char) then
                    local okP, piv = pcall(function() return (m :: Model):GetPivot().Position end)
                    if okP and piv then
                        local dy = piv.Y - rp.Y
                        if dy > 2.5 and dy < 14 then
                            local dxz = Vector2.new(piv.X - rp.X, piv.Z - rp.Z).Magnitude
                            if dxz < 7 then found = m break end
                        end
                    end
                end
            end
        end)
        _overheadCacheV = found or false
        return found
    end
    return nil
end
pendingWeaponName = function()
    -- priorité absolue : unitName/unitTier officiels de l'arme rollée (source du jeu)
    local plotN = getPlot()
    if plotN then
        local rwN = findRolledWeapon(plotN)
        if rwN then
            local bits = {}
            pcall(function()
                local un = rwN:GetAttribute("unitName")
                local ut = rwN:GetAttribute("unitTier")
                if typeof(un) == "string" and un ~= "" then table.insert(bits, stripRich(un)) end
                if ut ~= nil then table.insert(bits, stripRich(tostring(ut))) end
            end)
            -- labels NOM/RARETÉ du billboard (chemin direct). PAS les stats (DPS/Damage/Level :
            -- valeurs volatiles qui pollueraient le nom + feraient flapper les signatures)
            pcall(function()
                local gui = rwN:FindFirstChild("WeaponBillboardGui", true)
                local frame = gui and gui:FindFirstChild("WeaponBoardFrame", true)
                local scope = frame or rwN
                for _, nm in ipairs({"UnitTextName", "UnitTextRarity", "UnitTierSymbol", "UnitTier"}) do
                    local o = scope:FindFirstChild(nm, false) or rwN:FindFirstChild(nm, true)
                    if o then
                        local okT, txt = pcall(function() return o.Text end)
                        if okT and typeof(txt) == "string" then
                            txt = stripRich(txt)
                            if #txt > 2 then table.insert(bits, txt) end
                        end
                    end
                end
            end)
            if #bits > 0 then return table.concat(bits, " ") end
            return rwN.Name ~= "RolledWeapon" and rwN.Name or nil
        end
    end
    local ohN = findOverheadWeapon()
    if ohN then return ohN.Name end
    local o = findPendingObject()
    if o then return o.Name end
    for k, v in pairs(LocalPlayer:GetAttributes()) do
        local kl = k:lower()
        if (kl:find("pending") or kl:find("newweapon") or kl:find("tobeplaced")) and typeof(v) == "string" and v ~= "" then
            return v
        end
    end
    return nil
end

-- Textual identity of a slot (nom, attributs, enfants, textes du prompt)
local function slotIdentityText(slot)
    local parts = {slot.Name}
    pcall(function()
        for k, v in pairs(slot:GetAttributes()) do table.insert(parts, k .. "=" .. tostring(v)) end
    end)
    for _, c in ipairs(slot:GetChildren()) do table.insert(parts, c.Name) end
    local pr = slot:FindFirstChildOfClass("ProximityPrompt")
    if pr then
        table.insert(parts, pr.ActionText or "")
        table.insert(parts, pr.ObjectText or "")
    end
    return table.concat(parts, " "):lower()
end
-- Rarity words : la VARIANTE (shiny/electric/cosmic) ne définit pas le slot, le TYPE d'arme oui.
-- We match full name first, puis sans les mots de rareté.
local _rarityStop = {shiny=true, electric=true, elektrik=true, cosmic=true, golden=true, gold=true, diamond=true, rainbow=true, dark=true, normal=true, common=true, rare=true, epic=true, legendary=true}
local function weaponTokens(name, stripRarity)
    local toks = {}
    for tok in name:lower():gmatch("%w+") do
        if #tok >= 3 and (not stripRarity or not _rarityStop[tok]) then
            table.insert(toks, tok)
        end
    end
    return toks
end
-- Return THE slot corresponding à l'arme (ou nil si aucun match)
local function findSlotForWeapon(slots, weaponName)
    if not weaponName or weaponName == "" then return nil end
    for _, strip in ipairs({false, true}) do
        local toks = weaponTokens(weaponName, strip)
        if #toks > 0 then
            local best, bestScore
            for _, slot in ipairs(slots) do
                local idt = slotIdentityText(slot)
                local score = 0
                for _, tok in ipairs(toks) do
                    if idt:find(tok, 1, true) then score += 1 end
                end
                if score > 0 and (not bestScore or score > bestScore) then best, bestScore = slot, score end
            end
            if best then return best end
        end
    end
    return nil
end

-- Learned memory : clé arme -> index du slot (tableau findWeaponSlots trié).
-- Learned ONLY sur placement vérifié (pending parti ou nouvelle Unit).
local WeaponSlotMemory = {}
local function weaponKeys(name)
    if not name or name == "" then return nil, nil end
    local exact = name:lower()
    local toks = weaponTokens(name, true)
    local typeKey = (#toks > 0) and table.concat(toks, " ") or nil
    return exact, typeKey
end
local function rememberSlot(name, idx)
    local exact, typeKey = weaponKeys(name)
    if exact then WeaponSlotMemory[exact] = idx end
    if typeKey and typeKey ~= exact then WeaponSlotMemory[typeKey] = idx end
end
local function recallSlot(name)
    local exact, typeKey = weaponKeys(name)
    if exact and WeaponSlotMemory[exact] then return WeaponSlotMemory[exact] end
    if typeKey and WeaponSlotMemory[typeKey] then return WeaponSlotMemory[typeKey] end
    return nil
end
-- Snapshot of placed Units (Folder Units : Unit1..Unit42) : une NOUVELLE Unit = placement vérifié
local function unitsSet(plot)
    local set = {}
    pcall(function()
        local ufold = plot:FindFirstChild("Units", true)
        if ufold then
            for _, u in ipairs(ufold:GetChildren()) do set[u] = true end
        end
    end)
    return set
end

local function placeWeapon()
    local plot = getPlot()
    if not plot then
        return false
    end
    -- Slots = WeaponBasePart of plot (42 in diagnostic)
    local slots = findWeaponSlots(plot)
    if #slots == 0 then
        if Config.PlacedCount==0 and os.clock()%5<0.6 then print("[Place] Aucun WeaponBasePart trouvé dans", plot.Name) end
        return false
    end
    -- WE ONLY PLACE ON CONFIRMED NEW WEAPON (achetée, en main / overhead) :
    -- Une simple offre dans la box ("rolled:...") N'ARME PAS le place (sinon on TP sur les
    -- slots pour une arme pas encore achetée). Seul le buy confirmé (NeedPlace=true) ou un
    -- pending réel hors-box (overhead/bp/attr) arme.
    local pendSig = getPendingSignature()
    local isBoxOfferOnly = pendSig and pendSig:sub(1, 7) == "rolled:"
    if pendSig and not isBoxOfferOnly and pendSig ~= Config.LastPlacedSig then
        Config.NeedPlace = true
        -- reset attempts ONLY on NEW weapon (otherwise reset every cycle = invisible infinite loop)
        if pendSig ~= Config.LastAttemptSig then
            Config.LastAttemptSig = pendSig
            Config.PlaceAttempts = 0
            print("[Place] New weapon to place:", pendSig)
        end
    end
    -- slow retry after abandon (covers slots over time, without spam)
    if not Config.NeedPlace and pendSig and not isBoxOfferOnly and pendSig ~= Config.LastPlacedSig then
        if (os.clock() - (Config.LastAbandonT or 0)) > 15 then
            Config.NeedPlace = true
            if os.clock()%8<0.6 then print("[Place] New attempt (slow) for:", pendSig) end
        end
    end
    -- Rien en main et rien à faire -> STOP (évite de vriller sur tous les slots après un placement)
    if Config.NeedPlace and not pendSig then
        Config.NeedPlace = false
        Config.PlaceAttempts = 0
        return false
    end
    if not Config.NeedPlace then
        return false
    end
    -- attempt cap: 15s pause between series (no spam on stubborn slot)
    if (Config.PlaceAttempts or 0) >= 4 then
        if (os.clock() - (Config.LastAbandonT or 0)) > 15 then
            Config.PlaceAttempts = 0
            if os.clock()%8<0.6 then print("[Place] New series of attempts for:", tostring(pendSig)) end
        else
            return false
        end
    end
    -- SLOT MUST MATCH RETRIEVED WEAPON (never tour plots):
    -- 1) learned memory  2) name match  3) bounded discovery WITHOUT TP (remote fire)
    local wname = pendingWeaponName()
    local exactKey, typeKey = weaponKeys(wname)
    local targetSlot, targetIdx, trusted = nil, nil, false
    if wname then
        local memIdx = recallSlot(wname)
        if memIdx and slots[memIdx] then
            local memSlot = slots[memIdx]
            if slotHasWeapon(memSlot) then
                -- Slot mémorisé occupé: doublon (même arme) ou mémoire périmée (autre arme).
                local m2 = findSlotForWeapon(slots, wname)
                if m2 == memSlot then
                    -- doublon confirmé: déjà posée, on ne re-TP/re-fire PAS dessus
                    if os.clock()%5<0.6 then print("[Place] Weapon already placed, skip:", wname) end
                    Config.LastPlacedSig = pendSig
                    Config.NeedPlace = false
                    Config.PlaceAttempts = 0
                    return false
                else
                    -- mémoire périmée: oublie, retombe sur match/discovery SANS firer ce cycle
                    if exactKey then WeaponSlotMemory[exactKey] = nil end
                    if typeKey then WeaponSlotMemory[typeKey] = nil end
                    if os.clock()%8<0.6 then print("[Place] Mémoire périmée pour", wname, "- rematch...") end
                end
            else
                targetSlot, targetIdx, trusted = memSlot, memIdx, true
                if os.clock()%8<0.6 then print("[Place] Memorized slot for", wname, "-> #", memIdx) end
            end
        end
        if not targetSlot then
            local matched = findSlotForWeapon(slots, wname)
            if matched then
                for i, s in ipairs(slots) do if s == matched then targetIdx = i break end end
                if slotHasWeapon(matched) then
                    -- weapon already placed on its slot → skip, no duplicate
                    if os.clock()%5<0.6 then print("[Place] Weapon already placed, skip:", wname) end
                    if exactKey then WeaponSlotMemory[exactKey] = targetIdx end
                    Config.LastPlacedSig = pendSig
                    Config.NeedPlace = false
                    Config.PlaceAttempts = 0
                    return false
                end
                targetSlot, trusted = matched, true
            end
        end
    end
    if not targetSlot then
        -- SANS nom d'arme on ne devine JAMAIS (sinon TP sur tous les slots pour un fantôme).
        if not wname or wname == "" then
            if os.clock()%8<0.6 then print("[Place] En attente (arme en main sans nom lisible, pas de TP aveugle)...") end
            return false
        end
        -- discovery: ONE slot at a time, rotating. Uniquement prompts ACTIVÉS et vides.
        -- (2e passe SANS check Enabled retirait des slots occupés/désactivés -> tour infini.)
        -- (server validates distance: remote fire alone = rejected, TP required)
        local startIdx = (Config.PlaceIndex or 0) % #slots + 1
        for i = 0, #slots - 1 do
            local idx = (startIdx - 1 + i) % #slots + 1
            local pr = slots[idx]:FindFirstChildOfClass("ProximityPrompt")
            if pr and pr.Enabled and not slotHasWeapon(slots[idx]) then targetSlot, targetIdx = slots[idx], idx break end
        end
        if not targetSlot then
            if os.clock()%8<0.6 then print("[Place] Aucun slot actionnable (", #slots, " occupés/désactivés) - attente") end
            return false
        end
        Config.PlaceIndex = targetIdx
        if os.clock()%8<0.6 then print("[Place] Discovery WITH TP for", tostring(wname), "-> slot #", targetIdx) end
    end
    -- Re-vérif juste avant TP: le slot a pu se remplir entre-temps (anti tour inutile)
    if slotHasWeapon(targetSlot) then
        if os.clock()%8<0.6 then print("[Place] Slot #", tostring(targetIdx), "rempli entre-temps, abandon ce cycle") end
        return false
    end
    local slotPart = nil
    pcall(function()
        if targetSlot:IsA("BasePart") or targetSlot:IsA("MeshPart") or targetSlot:IsA("UnionOperation") then
            slotPart = targetSlot
        else
            slotPart = targetSlot:FindFirstChildWhichIsA("BasePart", true) or targetSlot:FindFirstChildWhichIsA("MeshPart", true)
        end
    end)
    do -- Systematic TP (trusted or discovery): server validates distance, remote fire = rejected
        -- SINGLE TP to THE matching slot (never tour plots)
        if slotPart and RootPart then
            local offset = slotPart.Size.Y / 2 + 1.5
            RootPart.CFrame = slotPart.CFrame + Vector3.new(0, offset, 0)
            if os.clock()%8<0.6 then print("[Place] TP plot:", plot.Name, "| slot #", targetIdx) end
        elseif RootPart then
            pcall(function() RootPart.CFrame = CFrame.new(targetSlot:GetPivot().Position + Vector3.new(0,2,0)) end)
        else
            if os.clock()%5<0.6 then print("[Place] RootPart not found - TP impossible") end
            return false
        end
        task.wait(math.max(Config.PlaceDelay, 0.3))
    end
    -- (fire follows right after, within range)
    -- slot IS the part: its direct prompt is WeaponProxPrompt
    local prompt = nil
    prompt = targetSlot:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then prompt = findPrompt(targetSlot, {"WeaponProx","Place","Slot","Build","Set","Equip"}) end
    if not prompt then
        for _, d in ipairs(targetSlot:GetDescendants()) do if d:IsA("ProximityPrompt") then prompt=d break end end
    end
    if not prompt then
        -- fallback ClickDetector in slot (some games don't use ProximityPrompt)
        for _, d in ipairs(targetSlot:GetDescendants()) do
            if d:IsA("ClickDetector") then
                if fireClick(d) then Config.PlacedCount += 1 return true end
            end
        end
        if Config.PlacedCount==0 then print("[Place] No ProximityPrompt in slot", targetSlot.Name) end
        return false
    end
    do
        local range = prompt.MaxActivationDistance or 10
        if slotPart and RootPart then
            local dist = (RootPart.Position - slotPart.Position).Magnitude
            if dist > range + 2 then
                RootPart.CFrame = slotPart.CFrame + Vector3.new(0, 1.5, 0)
                task.wait(0.2)
            end
        end
    end
    local unitsBefore = unitsSet(plot)
    local ok = firePrompt(prompt)
    if not ok then
        if os.clock()%8<0.6 then print("[Place] firePrompt failed on", prompt.Name, "| Enabled:", tostring(prompt.Enabled), "| Hold:", tostring(prompt.HoldDuration), "| MaxDist:", tostring(prompt.MaxActivationDistance)) end
        return false
    end
    -- verified: pending gone OR new Unit appeared → we LEARN weapon->slot mapping
    task.wait(0.5)
    local placedNow, newUnitName = false, nil
    pcall(function()
        local after = unitsSet(plot)
        for u in pairs(after) do
            if not unitsBefore[u] then placedNow = true newUnitName = u.Name break end
        end
    end)
    if pendSig and getPendingSignature() ~= pendSig then placedNow = true end
    if placedNow then
        if wname and targetIdx then rememberSlot(wname, targetIdx) end
        if pendSig then Config.LastPlacedSig = pendSig end
        Config.PlacedCount += 1
        Config.NeedPlace = false
        Config.PlaceAttempts = 0
        print("[Place] Placed:", tostring(wname), "-> slot #", tostring(targetIdx), newUnitName and ("(Unit: " .. newUnitName .. ")") or "")
    else
        -- still not placed: we will retry, but not infinitely
        Config.PlaceAttempts = (Config.PlaceAttempts or 0) + 1
        if Config.PlaceAttempts >= 4 then
            Config.NeedPlace = false
            Config.PlaceAttempts = 0
            Config.LastAbandonT = os.clock()
            if os.clock()%5<0.6 then print("[Place] Abandoned after 4 attempts (server refused) - retry in 15s") end
        end
    end
    return true
end

local function upgradeAllWeapons()
    local plot = getPlot()
    if not plot then return end
    local slots = findWeaponSlots(plot)
    if #slots == 0 then return end
    -- NEVER upgrade with pending in hand (otherwise places on wrong slot!)
    if getPendingSignature() then
        if os.clock()%10<0.6 then print("[Upgrade] Paused (weapon pending placement)") end
        return
    end
    -- ANTI-POPUP: upgrades also cost cash. When funds are
    -- tight ( "too expensive" cooldown active ), we save cash for box
    -- instead of risking too-expensive purchase on upgrade side (= Robux popup).
    if isRobuxPopupVisible() then
        closeRobuxPopup()
        Config.LastPopupT = os.clock()
        return
    end
    if Config.LastTooExpensivePrice and (os.clock() - (Config.LastTooExpensiveT or 0)) < 10 then
        local cashU = 0
        pcall(function() cashU = getPlayerCash() end)
        if cashU <= 0 or cashU < Config.LastTooExpensivePrice * 1.1 then
            return
        end
    end
    local n=0
    -- Avec fireproximityprompt on fire SANS TP (sinon tour des 42 slots toutes les 8s
    -- = le "vrille" vu en jeu). TP uniquement en fallback sans exploit.
    local canRemote = hasRemoteFire()
    for _, slot in ipairs(slots) do
        local prompt = slot:FindFirstChildOfClass("ProximityPrompt")
        if prompt then
            if not canRemote then
                local part = getPromptPart(prompt)
                if part and RootPart then
                    local dist = 9999
                    pcall(function() dist = (RootPart.Position - part.Position).Magnitude end)
                    local range = prompt.MaxActivationDistance or 10
                    if dist > math.min(range, 10) then
                        gotoPart(part, 2)
                        task.wait(0.2)
                    end
                end
            elseif prompt.Enabled == false then
                continue
            end
            if firePrompt(prompt) then n+=1 end
            task.wait(canRemote and 0.05 or 0.1)
        end
    end
    if n > 0 then
        Config.UpgradedCount += n
        if os.clock()%8<1 then print("[Upgrade] Fired", n, "prompts on", #slots, "slots") end
    end
end

local _rebirthRemoteCache, _rebirthRemoteT = nil, 0
local function getRebirthRemote()
    local now = os.clock()
    if _rebirthRemoteCache ~= nil and (now - _rebirthRemoteT) < 30 then
        return (_rebirthRemoteCache == false) and nil or _rebirthRemoteCache
    end
    -- Exact path seen in RebirthGuiScript: ReplicatedStorage.RemoteEvents.RebirthButtonPress
    local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
    if folder then
        local r = folder:FindFirstChild("RebirthButtonPress")
        if r and r:IsA("RemoteEvent") then _rebirthRemoteCache, _rebirthRemoteT = r, now return r end
    end
    local r2 = ReplicatedStorage:FindFirstChild("RebirthButtonPress", true)
    if r2 and r2:IsA("RemoteEvent") then _rebirthRemoteCache, _rebirthRemoteT = r2, now return r2 end
    -- Fallback flou: tout RemoteEvent "rebirth"/"prestige" (1 scan)
    pcall(function()
        local pool = {}
        if folder then for _, d in ipairs(folder:GetChildren()) do table.insert(pool, d) end end
        if #pool == 0 then pool = ReplicatedStorage:GetChildren() end
        for _, d in ipairs(pool) do
            if d:IsA("RemoteEvent") then
                local n = d.Name:lower()
                if n:find("rebirth") or n:find("prestige") then
                    _rebirthRemoteCache, _rebirthRemoteT = d, now
                    print("[Rebirth] Remote flou trouvé: " .. d:GetFullName())
                    return
                end
            end
        end
    end)
    if _rebirthRemoteCache and _rebirthRemoteCache ~= false then return _rebirthRemoteCache end
    _rebirthRemoteCache, _rebirthRemoteT = false, now
    return nil
end

local function doRebirth()
    local waveBefore = getPlayerWave()
    -- rebirth resets cash + price: anti-popup memory must never survive
    -- beyond (also covers plot path that doesn't go through RebirthCount).
    -- It will rebuild itself on next discard if needed.
    Config.LastTooExpensivePrice = nil
    Config.LastTooExpensiveT = nil
    -- PATH 1: direct server (source RebirthGuiScript: RebirthButtonPress:FireServer(), no argument).
    -- Infallible: ignores GUI visible/hidden state (Frame.Visible=false at start).
    local rr = getRebirthRemote()
    if rr then
        if os.clock()%5<0.6 then print("[Rebirth] FireServer RebirthButtonPress (wave:", waveBefore, ")") end
        local ok = pcall(function() rr:FireServer() end)
        if ok then
            task.wait(1.5)
            if getPlayerWave() < waveBefore then
                Config.RebirthCount += 1
                -- cash and prices reset after rebirth: purge anti-popup memory
                Config.LastTooExpensivePrice = nil
                Config.LastTooExpensiveT = nil
                notify("Rebirth","Rebirth completed!")
                return true
            end
            -- Fire ok mais wave inchangée = prérequis manquant, PAS un succès
            return false
        end
    elseif os.clock()%10<0.6 then
        print("[Rebirth] Remote RebirthButtonPress not found")
    end
    -- PATH 1: big yellow button of RebirthGui (observed in-game under waves)
    local rgui = findRebirthGui()
    if rgui then
        -- 1) real GuiButton with text rebirth/prestige/reset (+ nom contient rebirth même si texte vide)
        for _, d in ipairs(rgui:GetDescendants()) do
            if d:IsA("TextButton") or d:IsA("ImageButton") then
                local t = ""
                pcall(function() t = d.Text or "" end)
                local tl = t:lower()
                local nm = d.Name:lower()
                if ((tl:find("rebirth") or tl:find("prestige") or tl:find("reset")) or (nm:find("rebirth") or nm:find("prestige")))
                    and not tl:find("lock") and not nm:find("lock") then
                    if os.clock()%5<0.6 then print("[Rebirth] Clic bouton:", d:GetFullName(), "text='" .. t .. "'") end
                    if clickButton(d) then
                        task.wait(1.5)
                            if getPlayerWave() < waveBefore then
                                Config.RebirthCount += 1
                                -- cash and prices reset after rebirth: purge anti-popup memory
                                Config.LastTooExpensivePrice = nil
                                Config.LastTooExpensiveT = nil
                                notify("Rebirth","Rebirth completed!")
                                return true
                            end
                            return false
                    end
                end
            end
        end
        -- 2) RebirthFrame = simple Frame clickable via InputBegan (seen in StarterGui)
        for _, d in ipairs(rgui:GetDescendants()) do
            local cn = d.Name:lower()
            if (d:IsA("Frame") or d:IsA("ImageLabel")) and cn:find("rebirth") and not cn:find("lock") then
                if os.clock()%5<0.6 then print("[Rebirth] Clic frame:", d:GetFullName()) end
                if fireGuiInput(d) then
                    task.wait(1.5)
                        if getPlayerWave() < waveBefore then
                            Config.RebirthCount += 1
                            -- cash and prices reset after rebirth: purge anti-popup memory
                            Config.LastTooExpensivePrice = nil
                            Config.LastTooExpensiveT = nil
                            notify("Rebirth","Rebirth completed!")
                            return true
                        end
                        return false
                end
            end
        end
        if os.clock()%10<0.6 then print("[Rebirth] Nothing clickable in RebirthGui (voir Diagnostic)") end
    elseif os.clock()%10<0.6 then
        print("[Rebirth] RebirthGui introuvable (wave=" .. tostring(waveBefore) .. "), essai prompt plot...")
    end
    -- PATH 2: old plot path (prompt / click)
    local plot = getPlot()
    if not plot then return false end
    local btn = plot:FindFirstChild("RebirthButtonPress")
    if not btn then btn = findPrompt(plot, {"Rebirth","Reborn","Prestige"}) end
    if not btn then return false end
    local prompt = btn:IsA("ProximityPrompt") and btn or btn:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then
        if btn:IsA("ClickDetector") then
            return fireClick(btn)
        end
        local det = btn:IsA("BasePart") and btn:FindFirstChildOfClass("ClickDetector") or nil
        if det then return fireClick(det) end
        return false
    end
    -- BUG FIX: TP within range before firing
    local part = getPromptPart(prompt)
    if part then gotoPart(part, 2) task.wait(0.25) end
    local ok = firePrompt(prompt)
    if ok then notify("Rebirth","Rebirth completed!") end
    return ok
end

local _pickupTpT = 0
-- RAFALES: 1 sweep toutes les 1.5s, jusqu'à 60 pièces d'un coup (au lieu d'une par une
-- en continu, dont les waits unitaires bloquaient la boucle buy/place).
local PICKUP_INTERVAL = 1.5
local PICKUP_BATCH = 60
local function pickupCoins()
    local seen = {}
    local list = {}
    local function addCoin(obj)
        if obj and not seen[obj] then
            seen[obj] = true
            table.insert(list, obj)
        end
    end
    local function isCoinLike(inst)
        if not inst then return false end
        local okN, n = pcall(function() return inst.Name:lower() end)
        if not okN or not n then return false end
        if n:find("coin") or n:find("loot") or n:find("drop") or n:find("cash") or n:find("money") or n:find("orb") or n:find("currency") or n:find("gem") or n:find("reward") then return true end
        return false
    end
    local function scanContainer(container, whitelistAll)
        if not container then return end
        local ok, desc = pcall(function() return container:GetDescendants() end)
        if not ok or not desc then return end
        for _, c in ipairs(desc) do
            if c:IsA("BasePart") then
                if whitelistAll then
                    -- LootSpawnedClient: tout est loot, mais on exclut le décor géant ancré
                    local okS, big = pcall(function() return c.Size.Magnitude > 40 end)
                    if not (okS and big) then addCoin(c) end
                elseif isCoinLike(c) or isCoinLike(c.Parent) then
                    addCoin(c)
                end
            end
            if #list >= PICKUP_BATCH then break end
        end
    end
    local lootNames = {"LootSpawnedClient","Loot","Drops","Coins","CoinDrops","LootDrops","DroppedLoot"}
    for _, name in ipairs(lootNames) do
        local folder = Workspace:FindFirstChild(name)
        if folder then
            scanContainer(folder, name == "LootSpawnedClient")
            if #list > 0 then break end
        end
    end
    if #list == 0 then
        for _, obj in ipairs(Workspace:GetChildren()) do
            if obj:IsA("Folder") or obj:IsA("Model") then
                local n = obj.Name:lower()
                if n:find("loot") or n:find("coin") or n:find("drop") or n:find("reward") or n:find("gem") then
                    scanContainer(obj, n:find("lootspawned") ~= nil)
                end
            end
            if #list >= PICKUP_BATCH then break end
        end
    end
    -- Fallback restauré: pièces en vrac directement sous Workspace
    if #list == 0 then
        for _, d in ipairs(Workspace:GetChildren()) do
            if d:IsA("BasePart") and isCoinLike(d) then addCoin(d) end
            if #list >= 30 then break end
        end
    end
    if #list == 0 then
        if os.clock() % 10 < 0.6 then print("[Coins] Aucun loot trouvé (dossiers " .. table.concat(lootNames, ",") .. " vides, voir Diagnostic)") end
        return
    end
    local root = RootPart
    if not root or not root.Parent then return end
    local fti = getFireTouch()
    -- trie par distance (proche d'abord) pour magnet/TP efficaces
    pcall(function()
        local rp = root.Position
        table.sort(list, function(a, b)
            local pa, pb = nil, nil
            pcall(function() pa = a.Position end)
            pcall(function() pb = b.Position end)
            if not pa then return false end
            if not pb then return true end
            return (pa - rp).Magnitude < (pb - rp).Magnitude
        end)
    end)
    -- RAFALE par grandes quantités (pas d'un-par-un avec waits unitaires) :
    -- 1) touch batch (1 seul wait pour tout le lot), 2) prompts/clicks sans wait,
    -- 3) magnet groupé, 4) 1 TP fallback throttlé.
    local batchCap = math.min(#list, PICKUP_BATCH)
    local touched, magneted = 0, 0
    if fti and root and root.Parent then
        touched = fireTouchBatch(list, root, batchCap)
    else
        for i = 1, batchCap do
            local cp = list[i]
            if cp and cp.Parent then
                pcall(function()
                    local pr = cp:FindFirstChildOfClass("ProximityPrompt")
                    if pr then firePrompt(pr) end
                    local cd = cp:FindFirstChildOfClass("ClickDetector")
                    if cd then fireClick(cd) end
                end)
                pcall(function()
                    if cp.Parent and cp:IsA("BasePart") and not cp.Anchored and cp.Size.Magnitude < 40 then
                        cp.AssemblyLinearVelocity = Vector3.zero
                        cp.AssemblyAngularVelocity = Vector3.zero
                        cp.CFrame = root.CFrame + Vector3.new(math.random(-3, 3), 0.5, math.random(-3, 3))
                        magneted += 1
                    end
                end)
            end
        end
        -- dernier recours: 1 TP joueur sur la plus proche (throttlé, le Touched serveur valide)
        if magneted == 0 and (os.clock() - _pickupTpT) > 2 and root and root.Parent then
            local target = nil
            for i = 1, batchCap do
                local cp = list[i]
                if cp and cp.Parent and cp:IsA("BasePart") then target = cp break end
            end
            if target then
                _pickupTpT = os.clock()
                pcall(function()
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.CFrame = target.CFrame + Vector3.new(0, 3, 0)
                end)
                if os.clock() % 8 < 0.6 then print("[Coins] TP joueur sur loot (sans firetouchinterest): " .. tostring(target:GetFullName())) end
                task.wait(0.2)
            end
        end
    end
    if (touched + magneted) > 0 and os.clock() % 8 < 0.6 then
        print("[Coins] Rafale: touch=" .. touched .. " magnet=" .. magneted .. "/" .. #list .. (fti and "" or " (SANS firetouchinterest: installe UNC complet)"))
    end
end

-- ============================================================
-- FLY (CFrame rigide 2026: aucune physique, donc ni spin ni balancement.
-- L'ancien LinearVelocity+AlignOrientation se battait avec AutoRotate/la gravité.)
-- ============================================================
local FlyOn = false
local _flySavedAutoRotate = nil
local function startFly()
    if FlyOn or not RootPart or not RootPart.Parent then return end
    FlyOn = true
    pcall(function()
        -- Ancré = gravité 0 : le perso reste figé dans l'air (sans ça, ~1.6 studs/s
        -- de descente entre les frames car la gravité agit entre 2 sets de CFrame).
        RootPart.Anchored = true
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            if _flySavedAutoRotate == nil then _flySavedAutoRotate = hum.AutoRotate end
            hum.AutoRotate = false -- AutoRotate faisait tourner le perso contre l'orientation
            hum.PlatformStand = true -- corps rigide: pas d'équilibre bipède, pas de ragdoll
            RootPart.AssemblyLinearVelocity = Vector3.zero
            RootPart.AssemblyAngularVelocity = Vector3.zero
        end
    end)
end
local function stopFly()
    FlyOn = false
    pcall(function()
        if RootPart and RootPart.Parent then RootPart.Anchored = false end
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            if _flySavedAutoRotate ~= nil then hum.AutoRotate = _flySavedAutoRotate end
            _flySavedAutoRotate = nil
            if hum.Health > 0 then
                hum.PlatformStand = false
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end
    end)
    pcall(function()
        if RootPart and RootPart.Parent then
            RootPart.AssemblyLinearVelocity = Vector3.zero
            RootPart.AssemblyAngularVelocity = Vector3.zero
        end
    end)
end
-- Nettoie le fly à la mort (évite objets fantômes sur nouveau perso)
trackConn(LocalPlayer.CharacterAdded:Connect(function() stopFly() end))
local function updateFly(dt)
    if not Config.FlyEnabled then if FlyOn then stopFly() end return end
    if not RootPart or not RootPart.Parent then return end
    if not FlyOn then startFly() end
    if not FlyOn then return end
    dt = math.clamp(tonumber(dt) or 0.033, 0.001, 0.1) -- clamp anti saut téléport sur lag spike
    pcall(function()
        local cam = Workspace.CurrentCamera
        if not cam then return end
        local dir = Vector3.zero
        local cf = cam.CFrame
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0,1,0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.new(0,1,0) end
        -- Déplacement CFrame direct (aucune force/torque -> aucun spin possible),
        -- orientation = caméra (sans roll parasite), vélocités tuées (anti fling).
        local flat = cf - cf.Position
        if dir.Magnitude > 0 then
            local step = dir.Unit * Config.FlySpeed * dt
            RootPart.CFrame = CFrame.new(RootPart.Position + step) * flat
        else
            -- sur place: on fige la position (anti gravité) mais on suit la caméra
            RootPart.CFrame = CFrame.new(RootPart.Position) * flat
        end
        RootPart.AssemblyLinearVelocity = Vector3.zero
        RootPart.AssemblyAngularVelocity = Vector3.zero
        -- le jeu/respawn peut désancrer : on réimpose, sinon ça redescend.
        if not RootPart.Anchored then RootPart.Anchored = true end
        -- le jeu peut reset PlatformStand/AutoRotate (respawn/dégâts): on réimpose.
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            if not hum.PlatformStand then hum.PlatformStand = true end
            if hum.AutoRotate then hum.AutoRotate = false end
            if hum.Seated then hum.Seated = false end
        end
    end)
end
local noClipStates = setmetatable({}, {__mode = "k"})
local _ncLast = 0
local function updateNoClip()
    -- throttlé 10Hz au lieu de 60Hz (Heartbeat) : divise par 6 le coût GetDescendants
    if os.clock() - _ncLast < 0.1 then return end
    _ncLast = os.clock()
    local char = LocalPlayer.Character
    if not char then return end
    if Config.NoClipEnabled then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then
                if noClipStates[p] == nil then noClipStates[p] = p.CanCollide end
                p.CanCollide = false
            end
        end
    else
        for p, canCollide in pairs(noClipStates) do
            if p and p.Parent then pcall(function() p.CanCollide = canCollide end) end
            noClipStates[p] = nil
        end
    end
end

local savedWalkSpeed, savedJumpPower, savedUseJumpPower
local _mvLastApplied = ""
local _mvThrottleT = 0
local function updateMovement()
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    -- n'applique que si valeur désirée différente (évite fight avec scripts jeu + détection)
    local key = tostring(Config.WalkSpeedEnabled) .. ":" .. tostring(Config.SpeedValue) .. ":" .. tostring(Config.JumpPowerEnabled) .. ":" .. tostring(Config.JumpValue)
    if key == _mvLastApplied then
        -- vérifie dérive (jeu qui reset) 1x/s seulement
        if os.clock() - _mvThrottleT < 1 then return end
    end
    _mvThrottleT = os.clock()
    _mvLastApplied = key
    if Config.WalkSpeedEnabled then
        if savedWalkSpeed == nil then savedWalkSpeed = hum.WalkSpeed end
        if hum.WalkSpeed ~= Config.SpeedValue then hum.WalkSpeed = Config.SpeedValue end
    elseif savedWalkSpeed ~= nil then
        pcall(function() hum.WalkSpeed = savedWalkSpeed end)
        savedWalkSpeed = nil
    end
    if Config.JumpPowerEnabled then
        if savedJumpPower == nil then
            savedJumpPower, savedUseJumpPower = hum.JumpPower, hum.UseJumpPower
        end
        pcall(function() hum.UseJumpPower = true end)
        if hum.JumpPower ~= Config.JumpValue then hum.JumpPower = Config.JumpValue end
    elseif savedJumpPower ~= nil then
        pcall(function() hum.JumpPower, hum.UseJumpPower = savedJumpPower, savedUseJumpPower end)
        savedJumpPower, savedUseJumpPower = nil, nil
    end
end
trackConn(UserInputService.JumpRequest:Connect(function()
    if not Config.InfiniteJump then return end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum and hum.FloorMaterial ~= Enum.Material.Air then
        -- même en l'air on autorise (infinite), mais pas ragdoll/nage/mort
        local st = hum:GetState()
        if st ~= Enum.HumanoidStateType.Dead and st ~= Enum.HumanoidStateType.Physics then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    elseif hum then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end))
local antiAFKThread
local function setAntiAFK(on)
    if on then
        if antiAFKThread then return end
        antiAFKThread = task.spawn(function()
            while Config.AntiAFK and not Config.Unloaded do
                pcall(function()
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F15, false, game)
                    task.wait(0.05)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F15, false, game)
                end)
                task.wait(300)
            end
            antiAFKThread = nil
        end)
    else
        Config.AntiAFK = false
        antiAFKThread = nil
    end
end

-- ============================================================
-- GUI BUILD
-- ============================================================
-- cleanup old gui
pcall(function()
    local pg = LocalPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("BaGASMenu")
    if old then old:Destroy() end
    local old2 = pg:FindFirstChild("BaGASV2")
    if old2 then old2:Destroy() end
end)

-- Interface construite dans buildGUI() : la limite Luau est de 200 registres/locaux PAR FONCTION.
-- Le chunk principal reste donc largement en dessous ; seuls les handles retournés sont exposés (GUI.*).
local GUI
local function buildGUI()
local SG = make("ScreenGui", {Name="BaGASMenu", ResetOnSpawn=false, ZIndexBehavior=Enum.ZIndexBehavior.Sibling, DisplayOrder=999, Parent=LocalPlayer:WaitForChild("PlayerGui")})

-- Registres pour recolor live lors d'un changement de thème (interface uniquement)
local ToggleRefreshers = {}
local SliderThemers = {} -- {fill, knobStroke, valBox}
local SectionHeaders = {} -- {label, line}
local CardStrokes = {} -- UIStroke à recolorer (bordures cartes)

local WIN_W, WIN_H, HEAD_H = 440, 560, 60
local MF = make("Frame", {Name="Main", Size=UDim2.new(0,WIN_W,0,WIN_H), Position=UDim2.new(0.5,-WIN_W/2,0.5,-WIN_H/2), BackgroundColor3=T.BG, BorderSizePixel=0, Visible=false, Parent=SG})
make("UICorner", {CornerRadius=UDim.new(0,14), Parent=MF})
local MFStroke = make("UIStroke", {Color=T.Primary, Thickness=1, Transparency=0.78, Parent=MF})
local MFScale = make("UIScale", {Scale=1, Parent=MF})

-- Title bar moderne (draggable) : logo + titre + pill version + boutons ronds
local TitleBar = make("Frame", {Name="TitleBar", Size=UDim2.new(1,0,0,HEAD_H), BackgroundColor3=T.BG, BorderSizePixel=0, Parent=MF})
make("UICorner", {CornerRadius=UDim.new(0,14), Parent=TitleBar})
local TitleHide = make("Frame", {Size=UDim2.new(1,0,0,18), Position=UDim2.new(0,0,1,-18), BackgroundColor3=T.BG, BorderSizePixel=0, Parent=TitleBar})
local TitleGrad = make("UIGradient", {Color=ColorSequence.new({ColorSequenceKeypoint.new(0, T.BG), ColorSequenceKeypoint.new(1, T.Surface)}), Rotation=90, Parent=TitleBar})
local TitleLine = make("Frame", {Size=UDim2.new(1,-24,0,1), Position=UDim2.new(0,12,1,-1), BackgroundColor3=T.Surface2, BorderSizePixel=0, Parent=TitleBar})

local Logo = make("Frame", {Size=UDim2.new(0,34,0,34), Position=UDim2.new(0,12,0.5,-17), BackgroundColor3=T.Primary, BorderSizePixel=0, Parent=TitleBar})
make("UICorner", {CornerRadius=UDim.new(0,10), Parent=Logo})
local LogoGrad = make("UIGradient", {Color=ColorSequence.new({ColorSequenceKeypoint.new(0, T.PrimaryLight), ColorSequenceKeypoint.new(1, T.PrimaryDark)}), Rotation=35, Parent=Logo})
make("TextLabel", {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text="B", TextColor3=Color3.fromRGB(255,255,255), TextSize=17, Font=Enum.Font.GothamBlack, Parent=Logo})

make("TextLabel", {Size=UDim2.new(1,-170,0,19), Position=UDim2.new(0,54,0,10), BackgroundTransparency=1, Text="BaGAS <font color=\"#888888\">//</font> CONTROL PANEL", RichText=true, TextColor3=T.Text, TextSize=14, Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, Parent=TitleBar})
local SubTitle = make("TextLabel", {Size=UDim2.new(1,-170,0,13), Position=UDim2.new(0,54,0,30), BackgroundTransparency=1, Text="BUILD A GUN ARMY  •  v2.2", TextColor3=T.TextDim, TextSize=10, Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Left, Parent=TitleBar})
local VerPill = make("Frame", {Size=UDim2.new(0,52,0,18), Position=UDim2.new(0,54,0,42), BackgroundColor3=T.Surface2, BorderSizePixel=0, Parent=TitleBar})
make("UICorner", {CornerRadius=UDim.new(1,0), Parent=VerPill})
local VerPillTxt = make("TextLabel", {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text="● ONLINE", TextColor3=T.PrimaryLight, TextSize=8, Font=Enum.Font.GothamBold, Parent=VerPill})

local function iconBtn(posX, txt, hoverC)
    local b = make("TextButton", {Size=UDim2.new(0,28,0,28), Position=UDim2.new(1,posX,0.5,-14), BackgroundColor3=T.Surface2, Text=txt, TextColor3=T.TextDim, TextSize=14, Font=Enum.Font.GothamBold, AutoButtonColor=false, Parent=TitleBar})
    make("UICorner", {CornerRadius=UDim.new(1,0), Parent=b})
    b.MouseEnter:Connect(function() tw(b, {BackgroundColor3=hoverC or T.Surface2, TextColor3=T.Text}, 0.12) end)
    b.MouseLeave:Connect(function() tw(b, {BackgroundColor3=T.Surface2, TextColor3=T.TextDim}, 0.15) end)
    return b
end
local CloseBtn = iconBtn(-38, "×", Color3.fromRGB(200, 70, 70))
local MinBtn = iconBtn(-72, "–", T.Surface2)

-- Stats bar moderne : 3 cartes (noms StatCash/StatWave/StatCount conservés pour la boucle stats)
local StatsBar = make("Frame", {Size=UDim2.new(1,-16,0,48), Position=UDim2.new(0,8,0,HEAD_H+2), BackgroundTransparency=1, BorderSizePixel=0, Parent=MF})
make("UIListLayout", {FillDirection=Enum.FillDirection.Horizontal, Padding=UDim.new(0,8), SortOrder=Enum.SortOrder.LayoutOrder, Parent=StatsBar})
local function statCard(order, icon, accent)
    local card = make("Frame", {Size=UDim2.new(0.3333,-6,1,0), BackgroundColor3=T.Surface, BorderSizePixel=0, LayoutOrder=order, Parent=StatsBar})
    make("UICorner", {CornerRadius=UDim.new(0,10), Parent=card})
    local st = make("UIStroke", {Color=T.Stroke, Thickness=1, Transparency=0.92, Parent=card})
    table.insert(CardStrokes, st)
    local ic = make("TextLabel", {Size=UDim2.new(0,22,1,0), Position=UDim2.new(0,8,0,0), BackgroundTransparency=1, Text=icon, TextColor3=accent, TextSize=13, Font=Enum.Font.GothamBold, Parent=card})
    local val = make("TextLabel", {Size=UDim2.new(1,-34,1,0), Position=UDim2.new(0,30,0,0), BackgroundTransparency=1, Text="-", TextColor3=T.Text, TextSize=11, Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, Parent=card})
    return card, val, ic
end
local StatCash = select(2, statCard(1, "$", T.PrimaryLight))
local StatWave = select(2, statCard(2, "◈", T.Text))
local StatCount = select(2, statCard(3, "⬢", T.TextDim))
StatCash.Text = "$0"
StatWave.Text = "Wave 0"
StatCount.Text = "0 placed"

-- Tab bar moderne : pilules avec indicateur animé
local TabBar = make("Frame", {Size=UDim2.new(1,-16,0,40), Position=UDim2.new(0,8,0,HEAD_H+56), BackgroundColor3=T.Surface, BorderSizePixel=0, Parent=MF})
make("UICorner", {CornerRadius=UDim.new(0,12), Parent=TabBar})
local TabBarStroke = make("UIStroke", {Color=T.Stroke, Thickness=1, Transparency=0.92, Parent=TabBar})
table.insert(CardStrokes, TabBarStroke)
make("UIPadding", {PaddingTop=UDim.new(0,4), PaddingBottom=UDim.new(0,4), PaddingLeft=UDim.new(0,4), PaddingRight=UDim.new(0,4), Parent=TabBar})
local TabNames = {"Farm","Movement","Player","Settings"}
local TabIcons = {Farm="◆", Movement="✦", Player="●", Settings="⚙"}
local TabBtns = {}
local Indicator = make("Frame", {Size=UDim2.new(0.25,-4,1,0), Position=UDim2.new(0,2,0,0), BackgroundColor3=T.Primary, BorderSizePixel=0, Parent=TabBar})
make("UICorner", {CornerRadius=UDim.new(0,9), Parent=Indicator})
local IndicatorGrad = make("UIGradient", {Color=ColorSequence.new({ColorSequenceKeypoint.new(0, T.Primary), ColorSequenceKeypoint.new(1, T.PrimaryDark)}), Rotation=25, Parent=Indicator})
for i, name in ipairs(TabNames) do
    local btn = make("TextButton", {Name=name, Size=UDim2.new(0.25,0,1,0), Position=UDim2.new((i-1)*0.25,0,0,0), BackgroundTransparency=1, Text=(TabIcons[name] or "•").."  "..name, TextColor3=(name==Config.ActiveTab and Color3.fromRGB(255,255,255) or T.TextDim), TextSize=11, Font=Enum.Font.GothamBold, AutoButtonColor=false, ZIndex=2, Parent=TabBar})
    btn.MouseEnter:Connect(function()
        if Config.ActiveTab ~= name then tw(btn, {TextColor3=T.Text}, 0.12) end
    end)
    btn.MouseLeave:Connect(function()
        if Config.ActiveTab ~= name then tw(btn, {TextColor3=T.TextDim}, 0.15) end
    end)
    TabBtns[name]=btn
end

-- Content moderne
local Content = make("Frame", {Size=UDim2.new(1,-16,1,-(HEAD_H+106)), Position=UDim2.new(0,8,0,HEAD_H+100), BackgroundTransparency=1, Parent=MF})
local Pages = {}
local orders = {Farm=0, Movement=0, Player=0, Settings=0}
for _, name in ipairs(TabNames) do
    local sf = make("ScrollingFrame", {Name=name.."Page", Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, BorderSizePixel=0, ScrollBarThickness=2, ScrollBarImageColor3=T.Primary, ScrollBarImageTransparency=0.25, CanvasSize=UDim2.new(0,0,0,0), Visible=(name==Config.ActiveTab), Parent=Content})
    make("UIListLayout", {Padding=UDim.new(0,8), SortOrder=Enum.SortOrder.LayoutOrder, Parent=sf})
    make("UIPadding", {PaddingTop=UDim.new(0,2), PaddingBottom=UDim.new(0,10), PaddingLeft=UDim.new(0,2), PaddingRight=UDim.new(0,6), Parent=sf})
    Pages[name]=sf
end
local function tagCanvas()
    for _, pg in pairs(Pages) do
        local ll = pg:FindFirstChildOfClass("UIListLayout")
        if ll then pg.CanvasSize = UDim2.new(0,0,0, ll.AbsoluteContentSize.Y + 12) end
    end
end
for _, pg in pairs(Pages) do
    -- FIX: AbsoluteContentSize (pas AbsoluteWindowSize) + layout change
    local ll = pg:FindFirstChildOfClass("UIListLayout")
    if ll then ll:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(tagCanvas) end
    pg:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(tagCanvas)
end

local function nextOrder(tab) orders[tab]+=1 return orders[tab] end

local function section(tab, title)
    local pg = Pages[tab]
    local row = make("Frame", {Size=UDim2.new(1,0,0,22), BackgroundTransparency=1, LayoutOrder=nextOrder(tab), Parent=pg})
    local pill = make("Frame", {Size=UDim2.new(0,3,0,14), Position=UDim2.new(0,2,0.5,-7), BackgroundColor3=T.Primary, BorderSizePixel=0, Parent=row})
    make("UICorner", {CornerRadius=UDim.new(1,0), Parent=pill})
    local lbl = make("TextLabel", {Size=UDim2.new(1,-14,1,0), Position=UDim2.new(0,12,0,0), BackgroundTransparency=1, Text=string.upper(title), TextColor3=T.TextDim, TextSize=10, Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left, Parent=row})
    table.insert(SectionHeaders, {pill=pill, label=lbl})
    task.defer(tagCanvas)
end

local function toggle(tab, key, label, cb)
    local pg = Pages[tab]
    local row = make("Frame", {Size=UDim2.new(1,0,0,44), BackgroundColor3=T.Surface, BorderSizePixel=0, LayoutOrder=nextOrder(tab), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,10), Parent=row})
    local stroke = make("UIStroke", {Color=T.Stroke, Thickness=1, Transparency=0.93, Parent=row})
    table.insert(CardStrokes, stroke)
    local dotA = make("Frame", {Size=UDim2.new(0,6,0,6), Position=UDim2.new(0,12,0.5,-3), BackgroundColor3=Config[key] and T.Primary or T.TextFaint, BorderSizePixel=0, Parent=row})
    make("UICorner", {CornerRadius=UDim.new(1,0), Parent=dotA})
    make("TextLabel", {Size=UDim2.new(1,-72,1,0), Position=UDim2.new(0,26,0,0), BackgroundTransparency=1, Text=label, TextColor3=T.Text, TextSize=12, Font=Enum.Font.GothamMedium, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, Parent=row})

    local bg = make("Frame", {Size=UDim2.new(0,42,0,22), Position=UDim2.new(1,-54,0.5,-11), BackgroundColor3=Config[key] and T.Success or T.ToggleOff, BorderSizePixel=0, Parent=row})
    make("UICorner", {CornerRadius=UDim.new(1,0), Parent=bg})
    local dot = make("Frame", {Size=UDim2.new(0,16,0,16), Position=Config[key] and UDim2.new(1,-19,0.5,-8) or UDim2.new(0,3,0.5,-8), BackgroundColor3=Color3.fromRGB(255,255,255), BorderSizePixel=0, Parent=bg})
    make("UICorner", {CornerRadius=UDim.new(1,0), Parent=dot})
    local dotStroke = make("UIStroke", {Color=T.Primary, Thickness=1, Transparency=Config[key] and 0 or 1, Parent=dot})

    local function refresh()
        local on = Config[key]
        tw(bg, {BackgroundColor3 = on and T.Success or T.ToggleOff}, 0.16)
        tw(dot, {Position = on and UDim2.new(1,-19,0.5,-8) or UDim2.new(0,3,0.5,-8)}, 0.18, Enum.EasingStyle.Back)
        tw(dotA, {BackgroundColor3 = on and T.Primary or T.TextFaint}, 0.16)
        tw(dotStroke, {Transparency = on and 0 or 1}, 0.16)
    end
    table.insert(ToggleRefreshers, refresh)
    local hit = make("TextButton", {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text="", AutoButtonColor=false, Parent=row})
    hit.MouseEnter:Connect(function() tw(stroke, {Transparency=0.82}, 0.12) end)
    hit.MouseLeave:Connect(function() tw(stroke, {Transparency=0.93}, 0.15) end)
    hit.MouseButton1Click:Connect(function()
        Config[key] = not Config[key]
        refresh()
        if cb then pcall(cb, Config[key]) end
    end)
    task.defer(tagCanvas)
    return refresh
end

local function slider(tab, key, label, min, max, step, suffix)
    local pg = Pages[tab]
    local row = make("Frame", {Size=UDim2.new(1,0,0,56), BackgroundColor3=T.Surface, BorderSizePixel=0, LayoutOrder=nextOrder(tab), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,10), Parent=row})
    local stroke = make("UIStroke", {Color=T.Stroke, Thickness=1, Transparency=0.93, Parent=row})
    table.insert(CardStrokes, stroke)
    make("TextLabel", {Size=UDim2.new(0.55,0,0,16), Position=UDim2.new(0,12,0,7), BackgroundTransparency=1, Text=label, TextColor3=T.Text, TextSize=11, Font=Enum.Font.GothamMedium, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, Parent=row})
    local val = Config[key]
    -- editable value via keyboard (e.g. type 23 or 104) + drag slider; both sync
    local valBox = make("TextBox", {Size=UDim2.new(0,86,0,20), Position=UDim2.new(1,-98,0,5), BackgroundColor3=T.Surface2, Text=tostring(val)..(suffix or ""), TextColor3=T.PrimaryLight, TextSize=11, Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Center, ClearTextOnFocus=false, Parent=row})
    make("UICorner", {CornerRadius=UDim.new(0,7), Parent=valBox})
    local track = make("Frame", {Size=UDim2.new(1,-24,0,6), Position=UDim2.new(0,12,0,34), BackgroundColor3=T.Surface2, BorderSizePixel=0, Parent=row})
    make("UICorner", {CornerRadius=UDim.new(1,0), Parent=track})
    local frac = math.clamp((val-min)/(max-min),0,1)
    local fill = make("Frame", {Size=UDim2.new(frac,0,1,0), BackgroundColor3=T.Primary, BorderSizePixel=0, Parent=track})
    make("UICorner", {CornerRadius=UDim.new(1,0), Parent=fill})
    local fillGrad = make("UIGradient", {Color=ColorSequence.new({ColorSequenceKeypoint.new(0, T.PrimaryLight), ColorSequenceKeypoint.new(1, T.PrimaryDark)}), Rotation=0, Parent=fill})
    local knob = make("Frame", {Size=UDim2.new(0,16,0,16), Position=UDim2.new(frac,-8,0.5,-8), BackgroundColor3=Color3.fromRGB(255,255,255), BorderSizePixel=0, Parent=track})
    make("UICorner", {CornerRadius=UDim.new(1,0), Parent=knob})
    local knobStroke = make("UIStroke", {Color=T.Primary, Thickness=1.5, Parent=knob})
    table.insert(SliderThemers, {fill=fill, grad=fillGrad, knobStroke=knobStroke, valBox=valBox, track=track})
    local dragging=false
    local function paint(v)
        local f = math.clamp((v-min)/(max-min),0,1)
        fill.Size = UDim2.new(f,0,1,0)
        knob.Position = UDim2.new(f,-8,0.5,-8)
        valBox.Text = tostring(v)..(suffix or "")
    end
    local function setFromX(x)
        local rel = math.clamp((x - track.AbsolutePosition.X)/math.max(track.AbsoluteSize.X,1),0,1)
        local raw = min + rel*(max-min)
        local stepped = math.floor(raw/step+0.5)*step
        stepped = math.clamp(stepped, min, max)
        Config[key]=stepped
        paint(stepped)
    end
    -- free input: exact value (clamped, WITHOUT step snap) to type 23, 104, 0.35...
    valBox.FocusLost:Connect(function(enter)
        if not enter then paint(Config[key]) return end
        local num = tonumber(string.match(valBox.Text, "^%s*([%d%.]+)") or "")
        if num then
            num = math.clamp(num, min, max)
            Config[key]=num
            paint(num)
        else
            paint(Config[key])
        end
    end)
    local hit = make("TextButton", {Size=UDim2.new(1,-12,0,22), Position=UDim2.new(0,6,0,22), BackgroundTransparency=1, Text="", Parent=row})
    hit.MouseButton1Down:Connect(function() dragging=true setFromX(UserInputService:GetMouseLocation().X) end)
    trackConn(UserInputService.InputEnded:Connect(function(inp) if inp.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end))
    trackConn(UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType==Enum.UserInputType.MouseMovement then setFromX(inp.Position.X) end
    end))
    task.defer(tagCanvas)
end

-- ============================================================
-- TAB SWITCH
-- ============================================================
local function switchTab(name)
    Config.ActiveTab = name
    for n, pg in pairs(Pages) do pg.Visible = (n==name) end
    for n, btn in pairs(TabBtns) do
        btn.TextColor3 = (n==name and Color3.fromRGB(255,255,255) or T.TextDim)
    end
    local idx = 1 for i,n in ipairs(TabNames) do if n==name then idx=i break end end
    tw(Indicator, {Position = UDim2.new((idx-1)*0.25, 3, 0, 0)}, 0.2, Enum.EasingStyle.Quart)
    task.defer(tagCanvas)
end
for name, btn in pairs(TabBtns) do btn.MouseButton1Click:Connect(function() switchTab(name) end) end
pcall(switchTab, Config.ActiveTab)

-- Recolor live (appelé par setTheme) : ne touche à aucune logique farm
RefreshThemeUI = function()
    pcall(function()
        MF.BackgroundColor3 = T.BG
        MFStroke.Color = T.Primary
        TitleBar.BackgroundColor3 = T.BG
        TitleHide.BackgroundColor3 = T.BG
        TitleGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, T.BG), ColorSequenceKeypoint.new(1, T.Surface)})
        TitleLine.BackgroundColor3 = T.Surface2
        Logo.BackgroundColor3 = T.Primary
        LogoGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, T.PrimaryLight), ColorSequenceKeypoint.new(1, T.PrimaryDark)})
        SubTitle.TextColor3 = T.TextDim
        VerPill.BackgroundColor3 = T.Surface2
        VerPillTxt.TextColor3 = T.PrimaryLight
        CloseBtn.BackgroundColor3 = T.Surface2
        MinBtn.BackgroundColor3 = T.Surface2
        CloseBtn.TextColor3 = T.TextDim
        MinBtn.TextColor3 = T.TextDim
        for _, _st in ipairs(CardStrokes) do
            pcall(function() _st.Color = T.Stroke end)
        end
        TabBar.BackgroundColor3 = T.Surface
        Indicator.BackgroundColor3 = T.Primary
        IndicatorGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, T.Primary), ColorSequenceKeypoint.new(1, T.PrimaryDark)})
        for _, pg in pairs(Pages) do
            if pg:IsA("ScrollingFrame") then pg.ScrollBarImageColor3 = T.Primary end
            for _, ch in ipairs(pg:GetChildren()) do
                if ch:IsA("Frame") and ch.LayoutOrder and ch.LayoutOrder > 0 then
                    -- ligne carte directe (toggle/slider/stats/detect/theme) : fond Surface
                    if ch.Size.Y.Offset >= 28 then ch.BackgroundColor3 = T.Surface end
                end
            end
        end
        for _, card in ipairs(StatsBar:GetChildren()) do
            if card:IsA("Frame") then card.BackgroundColor3 = T.Surface end
        end
        StatCash.TextColor3 = T.PrimaryLight
        StatWave.TextColor3 = T.Text
        StatCount.TextColor3 = T.TextDim
        for _, h in ipairs(SectionHeaders) do
            h.pill.BackgroundColor3 = T.Primary
            h.label.TextColor3 = T.TextDim
        end
        for _, s in ipairs(SliderThemers) do
            s.fill.BackgroundColor3 = T.Primary
            s.grad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, T.PrimaryLight), ColorSequenceKeypoint.new(1, T.PrimaryDark)})
            s.knobStroke.Color = T.Primary
            s.valBox.TextColor3 = T.PrimaryLight
            s.valBox.BackgroundColor3 = T.Surface2
            s.track.BackgroundColor3 = T.Surface2
        end
        for _, r in ipairs(ToggleRefreshers) do pcall(r) end
        switchTab(Config.ActiveTab)
    end)
end

-- Drag
do
    local dragging=false
    local startMouse, startPos
    local dragHit = make("TextButton", {Size=UDim2.new(1,-120,1,0), BackgroundTransparency=1, Text="", AutoButtonColor=false, Parent=TitleBar})
    dragHit.MouseButton1Down:Connect(function()
        dragging=true
        startMouse = UserInputService:GetMouseLocation()
        startPos = MF.Position
    end)
    trackConn(UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType==Enum.UserInputType.MouseMovement then
            local d = UserInputService:GetMouseLocation() - startMouse
            MF.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    trackConn(UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
    end))
end

-- Minimize / Close (même comportement, animation modernisée)
local minimized=false
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        tw(MF, {Size=UDim2.new(0,WIN_W,0,HEAD_H)}, 0.22, Enum.EasingStyle.Quart)
        StatsBar.Visible=false; TabBar.Visible=false; Content.Visible=false
    else
        StatsBar.Visible=true; TabBar.Visible=true; Content.Visible=true
        tw(MF, {Size=UDim2.new(0,WIN_W,0,WIN_H)}, 0.26, Enum.EasingStyle.Back)
        task.defer(tagCanvas)
    end
end)
CloseBtn.MouseButton1Click:Connect(function()
    Config.MenuOpen=false
    tw(MFScale, {Scale=0.96}, 0.15)
    tw(MF, {Size=UDim2.new(0,WIN_W,0,HEAD_H)}, 0.18)
    task.delay(0.18, function() if not Config.MenuOpen then MF.Visible=false end end)
end)
local function openMenu()
    Config.MenuOpen=true; MF.Visible=true
    if minimized then minimized=false StatsBar.Visible=true TabBar.Visible=true Content.Visible=true end
    MF.Size=UDim2.new(0,WIN_W,0,HEAD_H)
    MFScale.Scale=0.96
    tw(MFScale, {Scale=1}, 0.22, Enum.EasingStyle.Back)
    tw(MF, {Size=UDim2.new(0,WIN_W,0,WIN_H)}, 0.28, Enum.EasingStyle.Back)
    task.defer(tagCanvas)
end
local function closeMenu()
    Config.MenuOpen=false
    tw(MFScale, {Scale=0.96}, 0.15)
    tw(MF, {Size=UDim2.new(0,WIN_W,0,HEAD_H)}, 0.18)
    task.delay(0.18, function() if not Config.MenuOpen then MF.Visible=false end end)
end
trackConn(UserInputService.InputBegan:Connect(function(inp,gp)
    if gp then return end
    if inp.KeyCode==Config.MenuKey then
        if Config.MenuOpen then closeMenu() else openMenu() end
    end
end))

-- ============================================================
-- BUILD CONTENT
-- ============================================================
section("Farm","Auto Farm")
local refreshAutoBuy, refreshAutoPlace, refreshAutoRebirth, refreshAutoPickup
toggle("Farm","MasterAutoFarm","Master Auto Farm (enable all)", function(v)
    Config.AutoBuyAffordable = v
    Config.AutoPlaceUpgrade = v
    Config.AutoPlace = v
    Config.AutoUpgrade = v
    Config.AutoRebirth = v
    Config.AutoPickupCoins = v
    if refreshAutoBuy then refreshAutoBuy() end
    if refreshAutoPlace then refreshAutoPlace() end
    if refreshAutoRebirth then refreshAutoRebirth() end
    if refreshAutoPickup then refreshAutoPickup() end
    notify("Farm", v and "MASTER ON - all farms active" or "MASTER OFF - all farms disabled")
end)
refreshAutoBuy = toggle("Farm","AutoBuyAffordable","Auto Buy Weapon Box", function(v) notify("Farm", v and "Auto Buy ON" or "Auto Buy OFF") end)
refreshAutoPlace = toggle("Farm","AutoPlaceUpgrade","Auto Place + Upgrade", function(v)
    Config.AutoPlace = v
    Config.AutoUpgrade = v
    notify("Farm", v and "Place + Upgrade ON" or "Place + Upgrade OFF")
end)
refreshAutoRebirth = toggle("Farm","AutoRebirth","Auto Rebirth", function(v) notify("Farm", v and "Auto Rebirth ON" or "Auto Rebirth OFF") end)
refreshAutoPickup = toggle("Farm","AutoPickupCoins","Auto Pickup Coins", function(v) notify("Farm", v and "Pickup ON" or "Pickup OFF") end)

section("Farm","Delays")
slider("Farm","PlaceDelay","Place Delay",0.1,3,0.1,"s")
slider("Farm","BuyPause","View roll pause (0.5 fast / 1 default)",0.5,5,0.5,"s")
slider("Farm","RebirthWave","Rebirth at Wave",1,200,1,"")
slider("Farm","RebirthCheckDelay","Rebirth check",0.5,5,0.5,"s")

section("Movement","Fly & Noclip")
toggle("Movement","FlyEnabled","Fly  (WASD + Space/Shift)", function(v) if not v then stopFly() end end)
slider("Movement","FlySpeed","Fly Speed",10,200,5,"")
toggle("Movement","NoClipEnabled","NoClip")

section("Movement","Speed")
toggle("Movement","WalkSpeedEnabled","Custom WalkSpeed", function() updateMovement() end)
slider("Movement","SpeedValue","WalkSpeed",16,200,1,"")
toggle("Movement","JumpPowerEnabled","Custom JumpPower", function() updateMovement() end)
slider("Movement","JumpValue","JumpPower",50,300,5,"")
toggle("Movement","InfiniteJump","Infinite Jump")

section("Player","Utilities")
toggle("Player","AntiAFK","Anti-AFK", function(v) setAntiAFK(v) end)

section("Settings","Theme")
local ThemeBtnRefs = {}
do
    local pg = Pages.Settings
    local card = make("Frame", {Size=UDim2.new(1,0,0,108), BackgroundColor3=T.Surface, BorderSizePixel=0, LayoutOrder=nextOrder("Settings"), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,10), Parent=card})
    local cardStroke = make("UIStroke", {Color=T.Stroke, Thickness=1, Transparency=0.93, Parent=card})
    table.insert(CardStrokes, cardStroke)
    make("TextLabel", {Size=UDim2.new(1,-24,0,16), Position=UDim2.new(0,12,0,8), BackgroundTransparency=1, Text="THEME  •  "..string.upper(Config.Theme), TextColor3=T.TextDim, TextSize=10, Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left, Parent=card})
    local grid = make("Frame", {Size=UDim2.new(1,-24,0,72), Position=UDim2.new(0,12,0,28), BackgroundTransparency=1, Parent=card})
    make("UIGridLayout", {CellSize=UDim2.new(0.3333,-6,0,32), CellPadding=UDim2.new(0,6,0,8), SortOrder=Enum.SortOrder.LayoutOrder, Parent=grid})
    local function paintThemeBtns()
        for name, refs in pairs(ThemeBtnRefs) do
            local selected = (Config.Theme == name)
            refs.btn.BackgroundColor3 = selected and T.Primary or T.Surface2
            refs.label.TextColor3 = selected and Color3.fromRGB(255,255,255) or T.TextDim
            refs.sel.Color = T.PrimaryLight
            refs.sel.Transparency = selected and 0 or 1
        end
    end
    for idx, name in ipairs(ThemeOrder) do
        local th = Themes[name]
        local b = make("TextButton", {Size=UDim2.new(0.3333,-6,0,32), BackgroundColor3=(Config.Theme==name and T.Primary or T.Surface2), Text="", AutoButtonColor=false, LayoutOrder=idx, Parent=grid})
        make("UICorner", {CornerRadius=UDim.new(0,8), Parent=b})
        local sel = make("UIStroke", {Color=T.PrimaryLight, Thickness=1.5, Transparency=(Config.Theme==name and 0 or 1), Parent=b})
        local dot = make("Frame", {Size=UDim2.new(0,14,0,14), Position=UDim2.new(0,8,0.5,-7), BackgroundColor3=th.Dot, BorderSizePixel=0, Parent=b})
        make("UICorner", {CornerRadius=UDim.new(1,0), Parent=dot})
        local lbl = make("TextLabel", {Size=UDim2.new(1,-28,1,0), Position=UDim2.new(0,26,0,0), BackgroundTransparency=1, Text=name, TextColor3=((Config.Theme==name) and Color3.fromRGB(255,255,255) or T.TextDim), TextSize=10, Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd, Parent=b})
        ThemeBtnRefs[name] = {btn=b, label=lbl, sel=sel}
        b.MouseEnter:Connect(function()
            if Config.Theme ~= name then tw(b, {BackgroundColor3=T.Surface2}, 0.1) tw(lbl, {TextColor3=T.Text}, 0.1) end
        end)
        b.MouseLeave:Connect(function() paintThemeBtns() end)
        b.MouseButton1Click:Connect(function()
            setTheme(name)
            paintThemeBtns()
            for _, ch in ipairs(card:GetChildren()) do
                if ch:IsA("TextLabel") and ch.Text:find("THEME") then ch.Text = "THEME  •  "..string.upper(name) end
            end
        end)
    end
    -- le recolor live met aussi à jour la grille de thèmes (sans toucher la logique)
    local _prevRefresh = RefreshThemeUI
    RefreshThemeUI = function()
        if _prevRefresh then pcall(_prevRefresh) end
        pcall(function()
            card.BackgroundColor3 = T.Surface
            for _, ch in ipairs(card:GetChildren()) do
                if ch:IsA("TextLabel") and ch.Text:find("THEME") then
                    ch.TextColor3 = T.TextDim
                    ch.Text = "THEME  •  "..string.upper(Config.Theme)
                end
            end
            paintThemeBtns()
        end)
    end
    task.defer(tagCanvas)
end

section("Settings","Stats")
local statsLbl
do
    local pg = Pages.Settings
    local fr = make("Frame", {Size=UDim2.new(1,0,0,70), BackgroundColor3=T.Surface, BorderSizePixel=0, LayoutOrder=nextOrder("Settings"), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,10), Parent=fr})
    local st = make("UIStroke", {Color=T.Stroke, Thickness=1, Transparency=0.93, Parent=fr})
    table.insert(CardStrokes, st)
    statsLbl = make("TextLabel", {Size=UDim2.new(1,-14,1,-8), Position=UDim2.new(0,7,0,4), BackgroundTransparency=1, Text="Bought: 0 | Skipped: 0\nPlaced: 0 | Upgraded: 0\nRebirths: 0", TextColor3=T.TextDim, TextSize=11, Font=Enum.Font.Code, TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top, Parent=fr})
    task.defer(tagCanvas)
end

section("Settings","Live detection")
local detectLbl
local detectFrameStroke
do
    local pg = Pages.Settings
    local fr = make("Frame", {Size=UDim2.new(1,0,0,68), BackgroundColor3=T.Surface, BorderSizePixel=0, LayoutOrder=nextOrder("Settings"), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,10), Parent=fr})
    detectFrameStroke = make("UIStroke", {Color=T.Primary, Transparency=0.55, Thickness=1, Parent=fr})
    detectLbl = make("TextLabel", {Size=UDim2.new(1,-12,1,-8), Position=UDim2.new(0,6,0,4), BackgroundTransparency=1, Text="Plot: ...\nCash: ... | Box: ...\nLast: -", TextColor3=T.PrimaryLight, TextSize=10, Font=Enum.Font.Code, TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top, Parent=fr})
    task.defer(tagCanvas)
end

local btnRescanRef, btnRescanGrad
do
    local pg = Pages.Settings
    local btnRescan = make("TextButton", {Size=UDim2.new(1,0,0,32), BackgroundColor3=T.Primary, Text="↻  Rescan Cash / Wave / Plot", TextColor3=Color3.fromRGB(255,255,255), TextSize=11, Font=Enum.Font.GothamBold, AutoButtonColor=false, LayoutOrder=nextOrder("Settings"), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,10), Parent=btnRescan})
    btnRescanGrad = make("UIGradient", {Color=ColorSequence.new({ColorSequenceKeypoint.new(0, T.PrimaryLight), ColorSequenceKeypoint.new(1, T.PrimaryDark)}), Rotation=25, Parent=btnRescan})
    btnRescan.MouseEnter:Connect(function() tw(btnRescan, {BackgroundTransparency=0.08}, 0.12) end)
    btnRescan.MouseLeave:Connect(function() tw(btnRescan, {BackgroundTransparency=0}, 0.15) end)
    btnRescanRef = btnRescan
    btnRescan.MouseButton1Click:Connect(function()
        _cashObj=nil _cashAttrRoot=nil _cashAttrKey=nil _cashUI=nil _triedHeavyCash=false
        _waveObj=nil _waveAttrRoot=nil _waveAttrKey=nil _waveUI=nil _triedHeavyWave=false
        cachedPlot=nil _slotsCache, _slotsPlot, _slotsT = {}, nil, 0
        _plotCacheT = 0
        notify("Rescan","Cache cleared, rescanning…")
        task.wait(0.5)
        local c=getPlayerCash(); local w=getPlayerWave(); local p=deepScanPlot()
        print("[Rescan] Cash:",c," Wave:",w," Plot:",p and p.Name or "nil")
    end)
    task.defer(tagCanvas)
end

section("Settings","Diagnostic")
local diagBtnRef, diagBtn2Ref
do
    local pg = Pages.Settings
    local btn = make("TextButton", {Size=UDim2.new(1,0,0,36), BackgroundColor3=T.Surface2, Text="◉  Run diagnostic  (console F9)", TextColor3=T.Text, TextSize=11, Font=Enum.Font.GothamBold, AutoButtonColor=false, LayoutOrder=nextOrder("Settings"), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,10), Parent=btn})
    local bst = make("UIStroke", {Color=T.Stroke, Thickness=1, Transparency=0.9, Parent=btn})
    table.insert(CardStrokes, bst)
    btn.MouseEnter:Connect(function() tw(btn, {BackgroundColor3=T.Surface}, 0.12) end)
    btn.MouseLeave:Connect(function() tw(btn, {BackgroundColor3=T.Surface2}, 0.15) end)
    diagBtnRef = btn
    btn.MouseButton1Click:Connect(function()
        task.spawn(function()
            pcall(function()
                local plot = getPlot()
                print("=== BaGAS DIAGNOSTIC ===")
                print("Plot:", plot and (plot.ClassName.." "..plot.Name) or "nil")
                if plot then
                    print("Plot enfants:", #plot:GetChildren())
                    for _, c in ipairs(plot:GetChildren()) do print(" >", c.ClassName, c.Name) end
                    local prompts={}
                    for _, d in ipairs(plot:GetDescendants()) do if d:IsA("ProximityPrompt") then table.insert(prompts, d.Name.." ("..d.Parent.Name..")") end end
                    print("Prompts:", #prompts)
                    for _, p in ipairs(prompts) do print(" >", p) end
                    local wslots = findWeaponSlots(plot)
                    local emptyN = 0
                    for _, s in ipairs(wslots) do if not slotHasWeapon(s) then emptyN += 1 end end
                    print("WeaponBasePart:", #wslots, "(vides:", emptyN, ")")
                    local ufold = plot:FindFirstChild("Units", true)
                    print("Units posées:", ufold and #ufold:GetChildren() or 0)
                    if ufold then
                        print("--- UNITS (nom : classe | attrs | enfants) ---")
                        pcall(function()
                            for _, u in ipairs(ufold:GetChildren()) do
                                local at = {}
                                pcall(function() for k, v in pairs(u:GetAttributes()) do table.insert(at, k .. "=" .. tostring(v)) end end)
                                local ch = {}
                                pcall(function()
                                    for _, c in ipairs(u:GetChildren()) do
                                        if #ch < 8 then table.insert(ch, c.Name) end
                                    end
                                end)
                                print("  U", u.Name, ":", u.ClassName, "| attrs{" .. table.concat(at, ",") .. "} | child{" .. table.concat(ch, ",") .. "}")
                            end
                        end)
                    end
                    local rwDiag = findRolledWeapon(plot)
                    print("RolledWeapon:", rwDiag and ("OUI " .. string.sub(rolledIdentity(rwDiag) or "?", 1, 200)) or "non")
                    if rwDiag then
                        print("Rolled ATTRS (clé = valeur) :")
                        pcall(function()
                            for k, v in pairs(rwDiag:GetAttributes()) do print("   attr", k, "=", tostring(v)) end
                        end)
                        print("Rolled LABELS (nom = texte) :")
                        pcall(function()
                            local gui = rwDiag:FindFirstChild("WeaponBillboardGui", true)
                            local frame = gui and gui:FindFirstChild("WeaponBoardFrame", true)
                            local scope = frame or rwDiag
                            for _, nm in ipairs({"UnitTextName", "UnitTextRarity", "UnitTextDPS", "UnitTier", "UnitTierSymbol", "NewText", "DmgText", "ExtraText", "FireRateText", "LevelText"}) do
                                local o = scope:FindFirstChild(nm, false) or rwDiag:FindFirstChild(nm, true)
                                if o then
                                    local okT, txt = pcall(function() return o.Text end)
                                    print("   ", nm, "=", okT and tostring(txt) or "?")
                                end
                            end
                        end)
                    end
                    print("--- CARTE DES SLOTS (pour correspondance arme->slot) ---")
                    for i, s in ipairs(wslots) do
                        local attrs = {}
                        pcall(function()
                            for k, v in pairs(s:GetAttributes()) do table.insert(attrs, k .. "=" .. tostring(v)) end
                        end)
                        local childs = {}
                        for _, c in ipairs(s:GetChildren()) do table.insert(childs, c.Name .. ":" .. c.ClassName) end
                        local pr = s:FindFirstChildOfClass("ProximityPrompt")
                        local ptxt = pr and (tostring(pr.ActionText) .. "|" .. tostring(pr.ObjectText) .. "|en=" .. tostring(pr.Enabled) .. "|hold=" .. tostring(pr.HoldDuration) .. "|dist=" .. tostring(pr.MaxActivationDistance)) or "-"
                        print(string.format("  [%d] %s | attrs{%s} | child{%s} | prompt{%s}", i, s:GetFullName(), table.concat(attrs, ","), table.concat(childs, ","), ptxt))
                    end
                    print("Pending actuel:", tostring(pendingWeaponName()))
                    local rgd = findRebirthGui()
                    if rgd then
                        print("--- RebirthGui TREE ---")
                        for _, d in ipairs(rgd:GetDescendants()) do
                            local t = ""
                            pcall(function() t = d.Text or "" end)
                            print("  ", d.ClassName, d:GetFullName(), "text='" .. tostring(t) .. "'")
                        end
                    else
                        print("RebirthGui introuvable")
                    end
                    print("--- REMOTES (ReplicatedStorage, max 80) ---")
                    pcall(function()
                        local n = 0
                        for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
                            if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("BindableEvent") or d:IsA("BindableFunction") then
                                n += 1
                                if n <= 80 then print("  ", d.ClassName, d:GetFullName()) end
                            end
                        end
                        print("  total remotes:", n)
                    end)
                end
                local ls = LocalPlayer:FindFirstChild("leaderstats")
                if ls then for _, s in ipairs(ls:GetChildren()) do print(" >", s.Name, "=", tostring(s.Value)) end else print("Pas de leaderstats") end
                print("=== FIN DIAGNOSTIC ===")
            end)
            pcall(dumpCurrencySources)
        end)
        notify("Diagnostic","Check console (F9)")
    end)
    local btn2 = make("TextButton", {Size=UDim2.new(1,0,0,32), BackgroundColor3=T.Surface, Text="Dump Cash/Wave sources (F9)", TextColor3=T.TextDim, TextSize=10, Font=Enum.Font.GothamMedium, AutoButtonColor=false, LayoutOrder=nextOrder("Settings"), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,10), Parent=btn2})
    local bst2 = make("UIStroke", {Color=T.Stroke, Thickness=1, Transparency=0.93, Parent=btn2})
    table.insert(CardStrokes, bst2)
    btn2.MouseEnter:Connect(function() tw(btn2, {TextColor3=T.Text}, 0.12) end)
    btn2.MouseLeave:Connect(function() tw(btn2, {TextColor3=T.TextDim}, 0.15) end)
    diagBtn2Ref = btn2
    btn2.MouseButton1Click:Connect(function()
        task.spawn(function() pcall(dumpCurrencySources) end)
        notify("Dump","Cash/Wave → console F9")
    end)
    task.defer(tagCanvas)
end

section("Settings","Unload")
local function unloadScript()
    if Config.Unloaded then return end
    Config.Unloaded = true
    -- stop les flags actifs + restaure le perso (vitesse, saut, collisions, fly)
    Config.AntiAFK = false
    Config.FlyEnabled = false
    Config.NoClipEnabled = false
    Config.WalkSpeedEnabled = false
    Config.JumpPowerEnabled = false
    Config.InfiniteJump = false
    Config.MasterAutoFarm = false
    Config.AutoBuyAffordable = false
    Config.AutoPlaceUpgrade = false
    Config.AutoPlace = false
    Config.AutoUpgrade = false
    Config.AutoRebirth = false
    Config.AutoPickupCoins = false
    pcall(stopFly)
    pcall(updateMovement)
    -- force restore noclip même si Heartbeat déjà coupé
    pcall(function()
        Config.NoClipEnabled = false
        local char = LocalPlayer.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    local saved = noClipStates[p]
                    if saved ~= nil then p.CanCollide = saved end
                end
            end
        end
    end)
    -- restaure RequiresLineOfSight modifiés par legacy fire
    pcall(function()
        local plot = cachedPlot
        if plot and plot.Parent then
            for _, d in ipairs(plot:GetDescendants()) do
                if d:IsA("ProximityPrompt") then pcall(function() d.RequiresLineOfSight = true end) end
            end
        end
    end)
    -- déconnecte tout ce qui est branché sur les services (boucles/inputs)
    for _, c in ipairs(Connections) do
        pcall(function() c:Disconnect() end)
    end
    -- purge caches (ré-exécution propre sans rejoin)
    cachedPlot, _plotCacheT = nil, 0
    _slotsCache, _slotsPlot, _slotsT = {}, nil, 0
    _cashObj, _cashAttrRoot, _cashAttrKey, _cashUI = nil, nil, nil, nil
    _waveObj, _waveAttrRoot, _waveAttrKey, _waveUI = nil, nil, nil, nil
    _buyLogged, _buyDumpN = false, 0
    _overheadCacheV, _overheadCacheT = nil, 0
    _pickupTpT, _mvThrottleT = 0, 0
    -- détruit le GUI (ses propres connexions meurent avec lui)
    pcall(function() GUI.SG:Destroy() end)
    print("[BaGAS] Script unloaded: GUI destroyed, loops stopped, character restored")
end
do
    local pg = Pages.Settings
    local un = make("TextButton", {Size=UDim2.new(1,0,0,36), BackgroundColor3=T.Danger, Text="⏻  UNLOAD script", TextColor3=Color3.fromRGB(255,255,255), TextSize=12, Font=Enum.Font.GothamBold, AutoButtonColor=false, LayoutOrder=nextOrder("Settings"), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,10), Parent=un})
    local unGrad = make("UIGradient", {Color=ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(0,0,0))}), Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(1, 0.92)}), Rotation=25, Parent=un})
    un.MouseEnter:Connect(function() tw(un, {BackgroundTransparency=0.1}, 0.12) end)
    un.MouseLeave:Connect(function() tw(un, {BackgroundTransparency=0}, 0.15) end)
    un.MouseButton1Click:Connect(function() unloadScript() end)
    task.defer(tagCanvas)
    -- Recolor final des boutons d'action (Rescan/Diagnostic/Unload/Détection) au changement de thème
    local _prev2 = RefreshThemeUI
    RefreshThemeUI = function()
        if _prev2 then pcall(_prev2) end
        pcall(function()
            if btnRescanRef then
                btnRescanRef.BackgroundColor3 = T.Primary
                if btnRescanGrad then btnRescanGrad.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, T.PrimaryLight), ColorSequenceKeypoint.new(1, T.PrimaryDark)}) end
            end
            if diagBtnRef then
                diagBtnRef.BackgroundColor3 = T.Surface2
                diagBtnRef.TextColor3 = T.Text
            end
            if diagBtn2Ref then
                diagBtn2Ref.BackgroundColor3 = T.Surface
                diagBtn2Ref.TextColor3 = T.TextDim
            end
            if un then un.BackgroundColor3 = T.Danger end
            if detectFrameStroke then detectFrameStroke.Color = T.Primary end
            if detectLbl then detectLbl.TextColor3 = T.PrimaryLight end
        end)
    end
end

do
    local pg = Pages.Settings
    make("TextLabel", {Size=UDim2.new(1,0,0,34), BackgroundTransparency=1, Text="BaGAS v2.2  •  RightShift = menu\nDrag top bar to move  •  Thème : "..tostring(Config.Theme), TextColor3=T.TextFaint, TextSize=10, Font=Enum.Font.Gotham, TextWrapped=true, LayoutOrder=nextOrder("Settings"), Parent=pg})
    task.defer(tagCanvas)
end

    return {SG = SG, StatCash = StatCash, StatWave = StatWave, StatCount = StatCount, statsLbl = statsLbl, detectLbl = detectLbl}
end
GUI = buildGUI()

-- ============================================================
-- HEARTBEAT (lightweight, single connection)
-- ============================================================
trackConn(RunService.Heartbeat:Connect(function(dt)
    if Config.Unloaded then return end
    pcall(updateFly, dt)
    pcall(updateNoClip)
    pcall(updateMovement)
end))

-- ============================================================
-- AUTO FARM (single thread + logs d'erreur + debounce rebirth/upgrade)
-- ============================================================
local _lastUpgradeInline, _lastRebirthTry = 0, 0
task.spawn(function()
    while not Config.Unloaded do
        local ok, err = pcall(function()
            if Config.MasterAutoFarm then
                -- MASTER: buy + place (upgrade et pickup tournent dans leurs threads dédiés)
                buyWeaponBox() task.wait(0.35)
                placeWeapon() task.wait(Config.PlaceDelay)
                -- inline upgrade UNIQUEMENT si pas de remote ET throttlé 8s (évite bloc 12s à chaque cycle)
                if not hasRemoteFire() and (os.clock() - _lastUpgradeInline) > 8 then
                    _lastUpgradeInline = os.clock()
                    upgradeAllWeapons() task.wait(0.8)
                end
                local w = getPlayerWave()
                if w >= Config.RebirthWave and (os.clock() - _lastRebirthTry) > 10 then
                    _lastRebirthTry = os.clock()
                    doRebirth() task.wait(Config.RebirthCheckDelay)
                end
            else
                if Config.AutoBuyAffordable then buyWeaponBox() task.wait(0.2) end
                if Config.AutoPlaceUpgrade or Config.AutoPlace then placeWeapon() task.wait(Config.PlaceDelay) end
                if (Config.AutoPlaceUpgrade or Config.AutoUpgrade) and not hasRemoteFire() and (os.clock() - _lastUpgradeInline) > 8 then
                    _lastUpgradeInline = os.clock()
                    upgradeAllWeapons() task.wait(0.3)
                end
                if Config.AutoRebirth and getPlayerWave() >= Config.RebirthWave and (os.clock() - _lastRebirthTry) > 10 then
                    _lastRebirthTry = os.clock()
                    doRebirth()
                end
            end
        end)
        if not ok and os.clock() % 10 < 0.6 then warn("[BaGAS farm] " .. tostring(err)) end
        task.wait(0.45)
    end
end)

-- Decoupled Upgrade: every 8s in own thread (remote fire, no TP),
-- to no longer slow down buy/place loop (42 prompts per cycle = ~10s lost before)
task.spawn(function()
    while not Config.Unloaded do
        if (Config.MasterAutoFarm or Config.AutoPlaceUpgrade or Config.AutoUpgrade) and hasRemoteFire() then
            pcall(upgradeAllWeapons)
        end
        task.wait(8)
    end
end)

-- Pickup DÉCOUPLÉ en RAFALES: 1 sweep toutes les 1.5s, jusqu'à 60 pièces d'un coup.
-- (Avant: un-par-un avec waits unitaires DANS la boucle farm -> buy/place bloqués.)
task.spawn(function()
    while not Config.Unloaded do
        if Config.MasterAutoFarm or Config.AutoPickupCoins then
            pcall(pickupCoins)
        end
        task.wait(PICKUP_INTERVAL)
    end
end)

-- Watchdog ANTI-ROBUX POPUP: throttlé 2s (le détecteur lui-même cache 1s).
-- L'ancien 0.5s scannait PlayerGui+CoreGui en boucle = lag.
task.spawn(function()
    while not Config.Unloaded do
        pcall(function()
            if isRobuxPopupVisible() then
                print("[AntiPopup] Popup Robux détecté → fermeture auto")
                closeRobuxPopup()
                Config.LastPopupT = os.clock()
            end
        end)
        task.wait(2)
    end
end)

-- Stats bar update (1s, lightweight)
task.spawn(function()
    while not Config.Unloaded do
        pcall(function()
            local cash = getPlayerCash()
            local wave = getPlayerWave()
            GUI.StatCash.Text = "$"..fmt(cash)
            GUI.StatWave.Text = "Wave "..tostring(wave)
            GUI.StatCount.Text = string.format("%d placed • %d↑", Config.PlacedCount, Config.UpgradedCount)
            if GUI.statsLbl then
                GUI.statsLbl.Text = string.format("Bought: %d | Skipped: %d\nPlaced: %d | Upgraded: %d\nRebirths: %d", Config.BoughtCount, Config.SkippedCount, Config.PlacedCount, Config.UpgradedCount, Config.RebirthCount)
            end
            if GUI.detectLbl then
                local plot = getPlot()
                local plotName = plot and (plot.Name.." ("..plot.ClassName..")") or "nil"
                local boxTxt = Config.LastBoxPrice and fmt(Config.LastBoxPrice) or "?"
                GUI.detectLbl.Text = string.format("Plot: %s\nCash: %s | Box: %s\nLast: %s", plotName, fmt(cash), boxTxt, tostring(Config.LastBoxAction or "-"))
                -- color by detection
                if cash==0 and wave==0 and (not plot) then
                    GUI.detectLbl.TextColor3 = Color3.fromRGB(220,80,80)
                elseif cash==0 or wave==0 then
                    GUI.detectLbl.TextColor3 = Color3.fromRGB(220,180,80)
                else
                    GUI.detectLbl.TextColor3 = T.PrimaryLight
                end
            end
        end)
        task.wait(1)
    end
end)

-- ============================================================
-- STARTUP - lightweight diagnostic once
-- ============================================================
notify("BaGAS v2.2","Loaded! RightShift = menu")
print("[BaGAS v2.2] Menu: RightShift | Drag title bar | Tabs Farm/Movement/Player/Settings")
task.spawn(function()
    task.wait(2)
    pcall(function()
        local plot = getPlot()
        print("[BaGAS] Plot:", plot and (plot.ClassName.." "..plot.Name) or "nil - open Settings > Diagnostic for details")
        if not plot then
            print("[BaGAS] Tip: if Plot=nil, farm cannot work. Run diagnostic in Settings.")
        else
            local n=0 for _, d in ipairs(plot:GetDescendants()) do if d:IsA("ProximityPrompt") then n+=1 end end
            print("[BaGAS] Prompts in plot:", n)
            print("[BaGAS] WeaponBasePart:", #findWeaponSlots(plot))
        end
        print("[BaGAS] Remote fire (without TP):", hasRemoteFire() and "OUI" or "NON")
    end)
end)

--[[
    Prism v2.1 - Build a Gun Army
]]--

-- Services
print("[Prism] booting...")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[Prism] ABORT: LocalPlayer = nil (injected mid-game, not at menu)")
    return
end
if not game:IsLoaded() then game.Loaded:Wait() end

-- Service connections registry (to disconnect on Unload).
-- (Connections on GUI objects are auto-cleaned by SG:Destroy().)
local Connections = {}
local function trackConn(conn) table.insert(Connections, conn) return conn end

local Character, Humanoid, RootPart
local function refreshChar(char)
    Character = char
    Humanoid = char:WaitForChild("Humanoid", 5)
    RootPart = char:WaitForChild("HumanoidRootPart", 5)
end
pcall(function() refreshChar(LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()) end)
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

    PlaceDelay = 0.5, BuyPause = 2, -- View roll pause: 0.5s = fast (names sometimes "?"), 2s = reliable names (Farm/Delays slider)
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
    pcall(function() StarterGui:SetCore("SendNotification", {Title=t or "Prism", Text=m or "", Duration=3}) end)
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
-- CLAUDE THEME
-- ============================================================
local T = {
    BG           = Color3.fromRGB(19,19,21),
    Surface      = Color3.fromRGB(31,31,34),
    Surface2     = Color3.fromRGB(43,43,47),
    Primary      = Color3.fromRGB(214,120,82),
    PrimaryDark  = Color3.fromRGB(180,100,62),
    PrimaryLight = Color3.fromRGB(240,155,105),
    Text         = Color3.fromRGB(235,232,226),
    TextDim      = Color3.fromRGB(150,146,138),
    TextFaint    = Color3.fromRGB(110,106,100),
    Success      = Color3.fromRGB(214,120,82),
    ToggleOff    = Color3.fromRGB(62,62,66),
}

-- ============================================================
-- PLOT DETECTION (lightweight, cached)
-- ============================================================
local cachedPlot
local function getPlot()
    if cachedPlot and cachedPlot.Parent then return cachedPlot end
    -- 0) assignedPlot attribute (found in your dump: LocalPlayer:GetAttribute("assignedPlot") = "Plot_6")
    local assigned = LocalPlayer:GetAttribute("assignedPlot")
    if typeof(assigned)=="string" and assigned~="" then
        local plots = Workspace:FindFirstChild("Plots")
        if plots then
            local direct = plots:FindFirstChild(assigned)
            if direct then cachedPlot=direct return direct end
        end
        local wsPlot = Workspace:FindFirstChild(assigned)
        if wsPlot then cachedPlot=wsPlot return wsPlot end
        -- search in all Workspace descendants if name matches
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d.Name==assigned and (d:IsA("Folder") or d:IsA("Model")) then
                -- check that it actually has Slots or a prompt
                if d:FindFirstChild("Slots", true) or d:FindFirstChild("WeaponBoxPrompt", true) then
                    cachedPlot=d return d
                end
            end
        end
    end
    -- 1) Workspace.Plots
    local plots = Workspace:FindFirstChild("Plots")
    if plots then
        for _, plot in ipairs(plots:GetChildren()) do
            local o = plot:FindFirstChild("Owner")
            if o then
                local v = o.Value
                if v == LocalPlayer or (typeof(v)=="string" and v==LocalPlayer.Name) then
                    cachedPlot = plot return plot
                end
                if typeof(v)=="Instance" and v.Name==LocalPlayer.Name then cachedPlot=plot return plot end
            end
            local av = plot:GetAttribute("Owner") or plot:GetAttribute("OwnerName")
            if av and (av==LocalPlayer.Name or av==LocalPlayer) then cachedPlot=plot return plot end
        end
    end
    -- 2) top-level folders/models with Owner
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("Folder") or obj:IsA("Model") then
            local o = obj:FindFirstChild("Owner")
            if o then
                local v = o.Value
                if v==LocalPlayer or (typeof(v)=="string" and v==LocalPlayer.Name) then cachedPlot=obj return obj end
            end
            local av = obj:GetAttribute("Owner") or obj:GetAttribute("OwnerName")
            if av and (av==LocalPlayer.Name) then cachedPlot=obj return obj end
        end
    end
    -- 3) Fallback: any Folder/Model containing Slots
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("Folder") or obj:IsA("Model") then
            local hasSlots = false
            for _, d in ipairs(obj:GetDescendants()) do if d.Name=="Slots" then hasSlots=true break end end
            if hasSlots then
                local owner = obj:FindFirstChild("Owner")
                if not owner then
                    for _, c in ipairs(obj:GetChildren()) do
                        if c:IsA("StringValue") and c.Value==LocalPlayer.Name then cachedPlot=obj return obj end
                        if c:IsA("ObjectValue") and c.Value==LocalPlayer then cachedPlot=obj return obj end
                    end
                end
            end
        end
    end
    -- 4) Last resort: first Folder/Model with Slots found
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:IsA("Folder") or obj:IsA("Model") then
            for _, d in ipairs(obj:GetDescendants()) do
                if d.Name=="Slots" then cachedPlot=obj return obj end
            end
        end
    end
    return nil
end

-- cache for cash/wave (found once = reused, ultra lightweight)
local _cashObj, _cashAttrRoot, _cashAttrKey, _cashUI
local _waveObj, _waveAttrRoot, _waveAttrKey, _waveUI
local _triedHeavyCash, _triedHeavyWave = false, false

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
        local t = _cashUI.Text
        local n = tonumber(t:gsub("[^%d]",""))
        if n then return n end
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
                    if d:FindFirstAncestor("PrismMenu") then
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
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if ls then
        for _, c in ipairs(ls:GetChildren()) do
            if c:IsA("ValueBase") then
                local n = c.Name:lower()
                if n:find("wave") or n:find("stage") or n:find("level") or n=="waves" then
                    _waveObj=c
                    local val = tryNum(c.Value)
                    if val then return val end
                end
            end
        end
        for _, key in ipairs({"Wave","Waves","Stage","Level","CurrentWave","WaveNumber"}) do
            local av = ls:GetAttribute(key)
            if typeof(av)=="number" then _waveAttrRoot=ls _waveAttrKey=key return av end
        end
    end
    -- LocalPlayer descendants
    for _, d in ipairs(LocalPlayer:GetDescendants()) do
        if d:IsA("ValueBase") then
            local n=d.Name:lower()
            if n=="wave" or n=="waves" or n=="stage" or n=="currentwave" or n:find("wave") then
                if d.Parent==LocalPlayer or d.Parent.Name:lower():find("wave") or d.Parent.Name:lower():find("data") then
                    _waveObj=d
                    local v=tryNum(d.Value) if v then return v end
                end
            end
        end
    end
    for _, name in ipairs({"Wave","wave","Waves","Stage","Level","CurrentWave"}) do
        local av = LocalPlayer:GetAttribute(name)
        if typeof(av)=="number" then _waveAttrRoot=LocalPlayer _waveAttrKey=name return av end
    end
    local plot = getPlot()
    if plot then
        -- priority: CurrentWave on plot (seen in your dump: plot attr CurrentWave = 57)
        for _, name in ipairs({"CurrentWave","CurrentWaveValue","Wave","Waves","Stage","Level"}) do
            local obj = plot:FindFirstChild(name)
            if obj and obj:IsA("ValueBase") then _waveObj=obj local v=tryNum(obj.Value) if v then return v end end
            local av = plot:GetAttribute(name)
            if typeof(av)=="number" then _waveAttrRoot=plot _waveAttrKey=name return av end
            -- case-insensitive attributes
            for k,v in pairs(plot:GetAttributes()) do
                if k:lower()==name:lower() and typeof(v)=="number" then _waveAttrRoot=plot _waveAttrKey=k return v end
            end
        end
        for k,v in pairs(plot:GetAttributes()) do
            if k:lower():find("wave") and typeof(v)=="number" then _waveAttrRoot=plot _waveAttrKey=k return v end
        end
        for _, c in ipairs(plot:GetDescendants()) do
            if c:IsA("ValueBase") and (c.Name:lower():find("wave") or c.Name:lower():find("stage")) then
                _waveObj=c
                local v=tryNum(c.Value) if v then return v end
            end
        end
    end
    -- PlayerGui fallback: text "Wave 12" (cached after 1 scan); we ignore the Prism GUI itself
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
                    if not d:FindFirstAncestor("PrismMenu") and d:IsA("TextLabel") then
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
local _fppFn -- cache (nil = not yet searched, false = absent)
local function getRemoteFire()
    if _fppFn == nil then
        local f = rawget(_G, "fireproximityprompt")
        if typeof(f) ~= "function" and typeof(getgenv) == "function" then
            pcall(function() f = getgenv().fireproximityprompt end)
        end
        _fppFn = (typeof(f) == "function") and f or false
    end
    if _fppFn == false then return nil end
    return _fppFn
end
local function hasRemoteFire() return getRemoteFire() ~= nil end
-- Direct Hold (simulated E key in place): fallback when remote fire fails
local function firePromptLegacy(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end
    if prompt.Enabled == false then return false end
    local ok = pcall(function()
        local hold = prompt.HoldDuration or 0
        prompt.RequiresLineOfSight = false
        if prompt.Enabled then
            prompt:InputHoldBegin()
            task.wait(hold > 0 and hold + 0.1 or 0.2)
            prompt:InputHoldEnd()
        end
    end)
    return ok
end
local function firePrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end
    if prompt.Enabled == false then return false end
    -- Exploit: fireproximityprompt if available (works even from far away, WITHOUT TP)
    local fpp = getRemoteFire()
    if fpp then
        local ok = pcall(fpp, prompt)
        return ok
    end
    return firePromptLegacy(prompt)
end
-- Physical part associated with a prompt (to TP within range)
local function getPromptPart(prompt)
    if not prompt then return nil end
    local parent = prompt.Parent
    if parent then
        if parent:IsA("BasePart") or parent:IsA("MeshPart") or parent:IsA("UnionOperation") then
            return parent
        end
        local part = parent:FindFirstChildWhichIsA("BasePart", true) or parent:FindFirstChildWhichIsA("MeshPart", true)
        if part then return part end
    end
    return nil
end
local function gotoPart(part, height)
    if not part or not RootPart then return false end
    local ok = pcall(function()
        RootPart.CFrame = part.CFrame + Vector3.new(0, height or 2, 0)
    end)
    return ok
end
local function fireClick(det)
    if not det or not det:IsA("ClickDetector") then return false end
    local fcd = rawget(_G, "fireclickdetector")
    if typeof(fcd) ~= "function" and typeof(getgenv) == "function" then
        pcall(function() fcd = getgenv().fireclickdetector end)
    end
    if typeof(fcd) == "function" then
        return pcall(fcd, det)
    end
    return false
end
local _fsFn -- cache firesignal (nil = not yet searched, false = absent)
local function getFireSignal()
    if _fsFn == nil then
        local f = rawget(_G, "firesignal")
        if typeof(f) ~= "function" and typeof(getgenv) == "function" then
            pcall(function() f = getgenv().firesignal end)
        end
        _fsFn = (typeof(f) == "function") and f or false
    end
    if _fsFn == false then return nil end
    return _fsFn
end
-- Real mouse click at button center (when firesignal is absent).
-- Hide our menu during the click, restoration GUARANTEED even if click fails
-- (otherwise Prism menu stays hidden - bug seen in-game).
local function clickButtonReal(btn)
    local pos, size
    pcall(function() pos, size = btn.AbsolutePosition, btn.AbsoluteSize end)
    if not pos or not size or size.X < 2 or size.Y < 2 then return false end
    local menuMain = nil
    pcall(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        local sg = pg and pg:FindFirstChild("PrismMenu")
        local m = sg and sg:FindFirstChild("Main")
        if m and m.Visible then menuMain = m m.Visible = false end
    end)
    task.wait(0.08)
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
                local gs = game:GetService("GuiService")
                gs.SelectedObject = btn
                task.wait(0.05)
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
                task.wait(0.05)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
                clicked = true
            end)
        end
        pcall(function() game:GetService("GuiService").SelectedObject = nil end)
        if not clicked and tick()%8<0.6 then print("[Gui] VIM non supporté : aucun clic possible") end
    end
    -- restoration ALWAYS
    pcall(function()
        if menuMain then menuMain.Visible = true end
    end)
    return clicked
end
-- Software click on a game button (e.g. big yellow Rebirth button)
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
            if tick()%10<0.6 then print("[Gui] Bouton caché, clic ignoré:", btn:GetFullName()) end
            return false
        end
    end
    local fs = getFireSignal()
    if fs then
        local ok1 = pcall(fs, btn.MouseButton1Click)
        pcall(fs, btn.Activated)
        if ok1 then return true end
    end
    -- fallback : vrai clic souris (firesignal absent ou inefficace)
    if tick()%8<0.6 then print("[Gui] Clic souris réel sur", btn:GetFullName()) end
    return clickButtonReal(btn)
end
-- Click on Frame/ImageLabel (e.g. RebirthFrame) via InputBegan + synthetic input
local function fireGuiInput(guiObj)
    local fs = getFireSignal()
    if not fs then
        if tick()%10<0.6 then print("[Gui] firesignal indisponible - clic impossible sur", guiObj:GetFullName()) end
        return false
    end
    if guiObj:IsA("GuiButton") then
        return clickButton(guiObj)
    end
    local fake = {UserInputType = Enum.UserInputType.MouseButton1, UserInputState = Enum.UserInputState.Begin, Position = Vector2.new(0, 0), Delta = Vector2.new(0, 0)}
    local ok = pcall(fs, guiObj.InputBegan, fake, false)
    pcall(fs, guiObj.MouseButton1Down, 0, 0)
    return ok
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
local getPendingSignature, findPendingObject, pendingWeaponName, findRolledWeapon, rolledIdentity, findOverheadWeapon, stripRich, rolledStableKey -- forward : définis plus bas, utilisés par le buy
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
    return nil
end
-- Box GUI button: BuyButton (buy) / DiscardButton (discard)
local function findBoxButton(nameKeys, textKeys)
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local gui = pg:FindFirstChild("WeaponBoxGui", true)
    if not gui then return nil end
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("TextButton") or d:IsA("ImageButton") then
            local n = d.Name:lower()
            for _, k in ipairs(nameKeys) do
                if n:find(k, 1, true) then return d end
            end
            local t = ""
            pcall(function() t = d.Text or "" end)
            local tl = t:lower()
            for _, k in ipairs(textKeys) do
                if tl:find(k, 1, true) then return d end
            end
        end
    end
    return nil
end
-- Official box remotes (source WeaponBoxGuiScript):
-- Buy = RemoteEvents.WeaponBoxBuy:FireServer()  /  Discard = RemoteEvents.WeaponBoxDiscard:FireServer()
local function getBoxRemotes()
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
    if not buy or not disc then
        pcall(function()
            if not buy then
                local b2 = ReplicatedStorage:FindFirstChild("WeaponBoxBuy", true)
                if b2 and b2:IsA("RemoteEvent") then buy = b2 end
            end
            if not disc then
                local d2 = ReplicatedStorage:FindFirstChild("WeaponBoxDiscard", true)
                if d2 and d2:IsA("RemoteEvent") then disc = d2 end
            end
        end)
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
    pcall(function()
        local containers = {}
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then table.insert(containers, pg) end
        if typeof(gethui) == "function" then
            local okH, hui = pcall(gethui)
            if okH and hui then table.insert(containers, hui) end
        end
        pcall(function() table.insert(containers, game:GetService("CoreGui")) end)
        for _, cont in ipairs(containers) do
            if cont then
                for _, d in ipairs(cont:GetDescendants()) do
                    if d:IsA("TextLabel") and typeof(d.Text) == "string"
                        and (d.Text:find("Buy Robux") or d.Text:find("Instant Money")) then
                        local root = d:FindFirstAncestorWhichIsA("ScreenGui") or d.Parent
                        if root then
                            for _, b in ipairs(root:GetDescendants()) do
                                if b:IsA("GuiButton") then
                                    local bt = ""
                                    pcall(function() bt = b.Text or b.Name or "" end)
                                    if bt == "X" or bt:lower():find("close") or bt:lower():find("cancel") or b.Name:lower():find("close") then
                                        pcall(function()
                                            local fs = getFireSignal()
                                            if fs then fs(b.MouseButton1Click) pcall(fs, b.Activated) end
                                        end)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end
-- Detect if Robux popup is visible (for cooldown + auto-close).
local function isRobuxPopupVisible()
    local found = false
    pcall(function()
        local containers = {}
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then table.insert(containers, pg) end
        if typeof(gethui) == "function" then
            local okH, hui = pcall(gethui)
            if okH and hui then table.insert(containers, hui) end
        end
        pcall(function() table.insert(containers, game:GetService("CoreGui")) end)
        for _, cont in ipairs(containers) do
            if cont then
                for _, d in ipairs(cont:GetDescendants()) do
                    if d:IsA("TextLabel") and typeof(d.Text) == "string"
                        and (d.Text:find("Buy Robux") or d.Text:find("Instant Money")) then
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
            end
            if found then break end
        end
    end)
    return found
end

local function triggerWeaponBox()
    local plot = getPlot()
    if not plot then
        if tick()%5<0.6 then print("[Buy] No plot detected - box TP impossible") end
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
            buyPrice = box:GetAttribute("Cost") or box:GetAttribute("Price")
        end
        if not buyPrice then
            local p2, raw2 = getWeaponBoxPrice()
            buyPrice = p2
            if raw2 and tick()%10<0.6 then print("[Buy] Price brut UI: '" .. raw2 .. "'") end
        end
        if buyPrice then
            Config.LastBoxPrice = buyPrice
        elseif tick()%10<0.6 then
            print("[Buy] Price not found (fail-open: trying anyway)")
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
            gotoPart(tpTarget, 3)
            if tick()%8<0.6 then
                print("[Buy] TP to box:", tpTarget:GetFullName(), "| plot:", plot.Name, "| prompt:", prompt.Name)
            end
            task.wait(0.2)
        end
    elseif not tpTarget and tick()%5<0.6 then
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
    -- ANTI-ROBUX POPUP: NEVER open if price unknown, cash unknown,
    -- insufficient funds, popup visible, or cooldown after "too expensive".
    -- Read price is only an ESTIMATE (UI not yet updated after a
    -- discard): we also require cash >= last refused price + 5% margin.
    do
        local cashO = 0
        pcall(function() cashO = getPlayerCash() end)
        if typeof(buyPrice) ~= "number" or buyPrice <= 0 then
            if tick()%8<0.6 then print("[Buy] Unknown price -> no opening (anti-Robux popup)") end
            return false
        end
        if typeof(cashO) ~= "number" or cashO <= 0 then
            if tick()%8<0.6 then print("[Buy] Unknown cash -> no opening (anti-Robux popup)") end
            return false
        end
        -- a popup is open: we close it and touch nothing this cycle
        if isRobuxPopupVisible() then
            closeRobuxPopup()
            Config.LastPopupT = tick()
            return false
        end
        if (tick() - (Config.LastPopupT or 0)) < 5 then return false end
        if (tick() - (Config.LastTooExpensiveT or 0)) < 5 then
            local need = (Config.LastTooExpensivePrice or buyPrice) * 1.05
            if cashO < need then
                if tick()%8<0.6 then print("[Buy] Too-expensive cooldown - waiting for funds:", fmt(cashO), "<", fmt(need)) end
                return false
            end
        end
        local needOpen = math.max(buyPrice, Config.LastTooExpensivePrice or 0) * 1.05
        if cashO < needOpen then
            if tick()%8<0.6 then print("[Buy] Waiting for funds before opening - price:", fmt(buyPrice), "| cash:", fmt(cashO)) end
            return false
        end
        Config.OpenUnknownSince = nil
    end
    -- PHASE 1: OPENING only if no weapon is offered (otherwise we reroll over it!)
    -- (Bought counter only increases on VERIFIED acquisition, not on fires)
    -- Throttle 2s between attempts (otherwise roll animation glitches).
    if not findRolledWeapon(plot) then
        if (tick() - (Config.LastOpenFireT or 0)) < 2 then return false end
        Config.LastOpenFireT = tick()
        firePrompt(prompt)
        task.wait(0.35)
        -- opening itself can trigger popup if price estimate
        -- was stale: we close it immediately and memorize refused price.
        if isRobuxPopupVisible() then
            print("[Buy] Robux popup after opening → closing, waiting for funds")
            closeRobuxPopup()
            Config.LastPopupT = tick()
            Config.LastTooExpensivePrice = buyPrice
            Config.LastTooExpensiveT = tick()
            return false
        end
        if not boxOpened() and hasRemoteFire() then
            if tick()%8<0.6 then print("[Buy] Remote fire had no effect, trying direct hold") end
            firePromptLegacy(prompt)
            task.wait(0.35)
            if isRobuxPopupVisible() then
                closeRobuxPopup()
                Config.LastPopupT = tick()
                Config.LastTooExpensivePrice = buyPrice
                Config.LastTooExpensiveT = tick()
                return false
            end
        end
    end
    -- PHASE 2: offered weapon → BUY (affordable) or DISCARD (too expensive, frees box)
    -- (if opening directly charged, it was a direct purchase: no buttons needed)
    local openBought = boxOpened()
    local rw = findRolledWeapon(plot)
    if not rw then
        Config.LastPreviewSig = nil
        Config.LastRolledInst = nil
        if openBought then
            Config.BoughtCount += 1
            Config.NeedPlace = true
            Config.PlaceAttempts = 0
            Config.LastTooExpensivePrice = nil
            Config.LastTooExpensiveT = nil
            if tick()%5<0.6 then print("[Buy] Purchase confirmed on opening - placement needed") end
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
        if tick() - (Config.LastNewRollLog or 0) > 3 then
            Config.LastNewRollLog = tick()
            print("[Buy] New offer:", tostring(pendingWeaponName() or "?"))
        end
    end
    -- OFFICIAL PRICE: Cost attribute of rolled weapon (game source, priority over UI),
    -- otherwise re-read UI (UI updates in 0.1s via game script)
    pcall(function()
        local c = rw:GetAttribute("Cost")
        if typeof(c) == "number" and c > 0 then buyPrice = c end
    end)
    if not buyPrice then
        local pu = getWeaponBoxPrice()
        if pu then buyPrice = pu end
    end
    if buyPrice then Config.LastBoxPrice = buyPrice end
    -- Price still unknown? We WAIT, we NEVER fire blindly (= Robux popup).
    -- Permanent fail-closed: no "let's try anyway", even after 3s.
    if typeof(buyPrice) ~= "number" or buyPrice <= 0 then
        if tick()%5<0.6 then print("[Buy] Unknown price, waiting (anti-Robux popup)...") end
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
    -- SHOWCASE PAUSE: let animation/visual play BEFORE deciding (otherwise invisible).
    -- Once per roll: new instance OR new content (same weapon 2x in a row = 2 pauses).
    -- Adjustable: "View roll pause" slider (click value to type exact number).
    do
        local rsig = tostring(rolledStableKey(rw) or "?")
        local isNew = isNewInst or (Config.LastPreviewSig ~= rsig)
        if isNew then
            Config.LastPreviewSig = rsig
            local pause = math.clamp(tonumber(Config.BuyPause) or 2, 0.5, 5) -- 0.5s = rapide ("?" possibles), 2s = noms fiables
            print("[Buy] Showcase: pause " .. tostring(pause) .. "s (" .. string.sub(rsig, 1, 60) .. ")")
            task.wait(pause)
        end
        readNames() -- ALWAYS fresh (not only on first preview): otherwise "?" stuck
        if unitName then
            -- memorize last NAMED roll (name + price + time)
            Config.LastKnownName, Config.LastKnownTier, Config.LastKnownPrice, Config.LastKnownT = unitName, unitTier, buyPrice, tick()
        elseif buyPrice and buyPrice == Config.LastKnownPrice and (tick() - (Config.LastKnownT or 99)) < 15 then
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
    -- ANTI-POPUP: unknown cash => we wait, touch nothing (neither buy nor discard).
    if typeof(cash) ~= "number" or cash <= 0 then
        if tick()%5<0.6 then print("[Buy] Unknown cash, waiting (anti-Robux popup)...") end
        return false
    end
    if cash < buyPrice then
        if not Config.WasPricedOut then
            Config.WasPricedOut = true
            notify("Buy", "Too expensive (" .. fmt(buyPrice) .. " > " .. fmt(cash) .. ") - discarded, next")
        end
        if tick()%5<0.6 then print("[Buy] Too expensive, DISCARD - price:", fmt(buyPrice), "| cash:", fmt(cash)) end
        if rdisc then
            if (tick() - (Config.LastDiscardFireT or 0)) > 1 then
                Config.LastDiscardFireT = tick()
                if tick()%8<0.6 then print("[Buy] FireServer WeaponBoxDiscard") end
                pcall(function() rdisc:FireServer() end)
                task.wait(0.3)
            end
        else
            local dbtn = findBoxButton({"discardbutton", "discard", "delete", "trash"}, {"discard", "delete", "trash", "jeter", "suppr"})
            if dbtn then
                if tick()%8<0.6 then print("[Buy] Clic DiscardButton") end
                clickButton(dbtn)
                task.wait(0.3)
            end
        end
        local dsig = tostring(rolledStableKey(rw) or "?")
        if Config.LastDiscardCountedSig ~= dsig then
            Config.LastDiscardCountedSig = dsig
            Config.SkippedCount += 1
        end
        Config.LastBoxAction = "x " .. tostring(unitName or "?") .. " (" .. fmt(buyPrice) .. ")"
        if tick()%8<0.6 then print("[Buy] x Discarded:", tostring(unitName or "?"), tostring(unitTier or ""), "(" .. fmt(buyPrice) .. " too expensive)") end
        -- memorize refused price: open estimate is often STALE just
        -- after a discard (UI not updated) → block any reopen while
        -- cash < refused price (otherwise loop open → Robux popup → discard → open...).
        Config.LastTooExpensivePrice = buyPrice
        Config.LastTooExpensiveT = tick()
        return false
    end
    Config.WasPricedOut = false
    -- ANTI-POPUP: FINAL re-check at instant T (anti race-condition with
    -- parallel upgrade that may have spent in between). No wait between
    -- this check and following FireServer.
    if not canAffordNow(buyPrice) then
        if tick()%5<0.6 then print("[Buy] Insufficient funds at instant T, purchase cancelled (anti-popup)") end
        local freshCash = 0
        pcall(function() freshCash = getPlayerCash() end)
        if typeof(freshCash) == "number" and freshCash > 0 and freshCash < buyPrice then
            Config.LastTooExpensivePrice = buyPrice
            Config.LastTooExpensiveT = tick()
        end
        if isRobuxPopupVisible() then closeRobuxPopup() Config.LastPopupT = tick() end
        return false
    end
    -- DIRECT SERVER PURCHASE (priority: infallible, no GUI required)
    if rbuy then
        if tick()%8<0.6 then print("[Buy] FireServer WeaponBoxBuy") end
        local cashB = getPlayerCash()
        local ohPre = findOverheadWeapon()
        pcall(function() rbuy:FireServer() end)
        task.wait(0.4)
        if isRobuxPopupVisible() then
            print("[Buy] Robux popup detected after purchase attempt → closing + memorizing price")
            closeRobuxPopup()
            Config.LastPopupT = tick()
            Config.LastTooExpensivePrice = buyPrice
            Config.LastTooExpensiveT = tick()
            return false
        end
        local boughtOk = false
        pcall(function()
            if getPlayerCash() < cashB then boughtOk = true end
            -- overhead NEW ONLY (an already present overhead proves nothing)
            local ohNow = findOverheadWeapon()
            if ohNow and (not ohPre or ohNow ~= ohPre) then boughtOk = true end
        end)
        if boughtOk then
            Config.BoughtCount += 1
            Config.NeedPlace = true
            Config.PlaceAttempts = 0
            Config.LastTooExpensivePrice = nil
            Config.LastTooExpensiveT = nil
            if tick()%5<0.6 then print("[Buy] Purchase confirmed - placement needed") end
            print("[Buy] + " .. tostring(unitName or "?") .. " " .. tostring(unitTier or "") .. " (" .. (buyPrice and fmt(buyPrice) or "?") .. ")")
            Config.LastBoxAction = "+ " .. tostring(unitName or "?") .. " (" .. (buyPrice and fmt(buyPrice) or "?") .. ")"
            buyDump()
            return true
        end
    end
    -- fallback: GUI button (only if remote is absent: avoids double purchases + menu flicker)
    if not rbuy then
        -- same final guard before any purchase click
        if not canAffordNow(buyPrice) then
            if tick()%5<0.6 then print("[Buy] Insufficient funds at instant T, Buy click cancelled (anti-popup)") end
            if isRobuxPopupVisible() then closeRobuxPopup() Config.LastPopupT = tick() end
            return false
        end
        local bbtn = findBoxButton({"buybutton", "buy"}, {"buy", "achet"})
        if bbtn then
            if tick()%8<0.6 then print("[Buy] Clic BuyButton") end
            local cashB = getPlayerCash()
            local ohPre = findOverheadWeapon()
            clickButton(bbtn)
            task.wait(0.35)
            local boughtOk = false
            pcall(function()
                if getPlayerCash() < cashB then boughtOk = true end
                -- overhead NEW ONLY (an already present overhead proves nothing)
                local ohNow = findOverheadWeapon()
                if ohNow and (not ohPre or ohNow ~= ohPre) then boughtOk = true end
            end)
            if boughtOk then
                Config.BoughtCount += 1
                Config.NeedPlace = true
                Config.PlaceAttempts = 0
                Config.LastTooExpensivePrice = nil
                Config.LastTooExpensiveT = nil
                if tick()%5<0.6 then print("[Buy] Purchase confirmed - placement needed") end
                print("[Buy] + " .. tostring(unitName or "?") .. " " .. tostring(unitTier or "") .. " (" .. (buyPrice and fmt(buyPrice) or "?") .. ")")
                Config.LastBoxAction = "+ " .. tostring(unitName or "?") .. " (" .. (buyPrice and fmt(buyPrice) or "?") .. ")"
                buyDump()
                return true
            end
        elseif tick()%8<0.6 then
            print("[Buy] Neither remote nor BuyButton found")
        end
    end
    -- last resort: weapon's internal prompt (1x/3s)
    -- ANTI-POPUP: never claim if too expensive / price or cash unknown.
    if (tick() - (Config.LastClaimT or 0)) > 3 then
        if not canAffordNow(buyPrice) then
            if tick()%8<0.6 then print("[Buy] Claim cancelled (too expensive or price/cash unknown, anti-popup)") end
        else
            Config.LastClaimT = tick()
            local claim = rw:FindFirstChild("WeaponProxPrompt", true)
            if claim and claim:IsA("ProximityPrompt") then
                print("[Buy] Claim rolled weapon (last resort)")
                firePrompt(claim)
                task.wait(0.3)
                if isRobuxPopupVisible() then
                    closeRobuxPopup()
                    Config.LastPopupT = tick()
                    Config.LastTooExpensivePrice = buyPrice
                    Config.LastTooExpensiveT = tick()
                end
            end
        end
    end
    return false
end
local function buyWeaponBox() return triggerWeaponBox() end

-- REAL game slots: parts "WeaponBasePart" (parents of 42 WeaponProxPrompt).
-- There is NO "Slots" folder in this game (seen in diagnostic: Folder Build/Units + WeaponBasePart).
local function findWeaponSlots(plot)
    if not plot then return {} end
    local list, seen = {}, {}
    for _, d in ipairs(plot:GetDescendants()) do
        -- EXCLUDE box content (internal RolledWeapon/WeaponBasePart trapped the finder)
        if d:FindFirstAncestor("WeaponBox") or d:FindFirstAncestor("RolledWeapon") then continue end
        if d.Name == "WeaponBasePart" and (d:IsA("BasePart") or d:IsA("MeshPart") or d:IsA("UnionOperation")) then
            if not seen[d] then seen[d] = true table.insert(list, d) end
        elseif d:IsA("ProximityPrompt") and d.Name:lower():find("weaponproxprompt", 1, true) then
            local p = d.Parent
            if p and (p:IsA("BasePart") or p:IsA("MeshPart") or p:IsA("UnionOperation")) then
                if not seen[p] then seen[p] = true table.insert(list, p) end
            end
        end
    end
    table.sort(list, function(a, b) return a:GetFullName() < b:GetFullName() end)
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
-- This is THE official pending: as long as it's there, box may refuse to reopen.
findRolledWeapon = function(plot)
    -- Multiple RolledWeapon can coexist (empty template + real rolled):
    -- we take the most COMPLETE (attributes > children > inside WeaponBox)
    if not plot then return nil end
    local best, bestScore = nil, -1
    pcall(function()
        for _, d in ipairs(plot:GetDescendants()) do
            if d.Name == "RolledWeapon" and d:IsA("Model") then
                local score = 0
                pcall(function()
                    if d:GetAttribute("unitName") then score += 10 end
                    if d:GetAttribute("Cost") then score += 5 end
                end)
                pcall(function() score += #d:GetDescendants() end)
                if d:FindFirstAncestor("WeaponBox") then score += 3 end
                if score > bestScore then best, bestScore = d, score end
            end
        end
    end)
    return best
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
getPendingSignature = function()
    local plot0 = getPlot()
    if plot0 then
        local rw0 = findRolledWeapon(plot0)
        if rw0 then
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
    if RootPart then
        local rp = RootPart.Position
        for _, m in ipairs(Workspace:GetChildren()) do
            if (m:IsA("Model") or m:IsA("MeshPart") or m:IsA("BasePart")) and not _coinName(m.Name) then
                local okP, piv = pcall(function() return m:GetPivot().Position end)
                if okP and piv then
                    local dy = piv.Y - rp.Y
                    if dy > 2.5 and dy < 14 then
                        local dxz = Vector2.new(piv.X - rp.X, piv.Z - rp.Z).Magnitude
                        if dxz < 7 then return m end
                    end
                end
            end
        end
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
        if Config.PlacedCount==0 and tick()%5<0.6 then print("[Place] Aucun WeaponBasePart trouvé dans", plot.Name) end
        return false
    end
    -- WE ONLY PLACE ON CONFIRMED NEW WEAPON (new, shiny, electric, cosmic...):
    -- NeedPlace is armed only when buy decreased cash / made pending appear.
    -- Without this, place would keep spamming slots in loop for nothing.
    local pendSig = getPendingSignature()
    if pendSig and pendSig ~= Config.LastPlacedSig then
        Config.NeedPlace = true
        -- reset attempts ONLY on NEW weapon (otherwise reset every cycle = invisible infinite loop)
        if pendSig ~= Config.LastAttemptSig then
            Config.LastAttemptSig = pendSig
            Config.PlaceAttempts = 0
            print("[Place] New weapon to place:", pendSig)
        end
    end
    -- slow retry after abandon (covers slots over time, without spam)
    if not Config.NeedPlace and pendSig and pendSig ~= Config.LastPlacedSig then
        if (tick() - (Config.LastAbandonT or 0)) > 15 then
            Config.NeedPlace = true
            if tick()%8<0.6 then print("[Place] New attempt (slow) for:", pendSig) end
        end
    end
    if not Config.NeedPlace then
        return false
    end
    -- attempt cap: 15s pause between series (no spam on stubborn slot)
    if (Config.PlaceAttempts or 0) >= 4 then
        if (tick() - (Config.LastAbandonT or 0)) > 15 then
            Config.PlaceAttempts = 0
            if tick()%8<0.6 then print("[Place] New series of attempts for:", tostring(pendSig)) end
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
            targetSlot, targetIdx, trusted = slots[memIdx], memIdx, true
            if tick()%8<0.6 then print("[Place] Memorized slot for", wname, "-> #", memIdx) end
        else
            local matched = findSlotForWeapon(slots, wname)
            if matched then
                for i, s in ipairs(slots) do if s == matched then targetIdx = i break end end
                if slotHasWeapon(matched) then
                    -- weapon already placed on its slot → skip, no duplicate
                    if tick()%5<0.6 then print("[Place] Weapon already placed, skip:", wname) end
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
        -- discovery: ONE slot at a time, rotating. Prefer ENABLED prompts.
        -- (server validates distance: remote fire alone = rejected, TP required)
        local startIdx = (Config.PlaceIndex or 0) % #slots + 1
        for i = 0, #slots - 1 do
            local idx = (startIdx - 1 + i) % #slots + 1
            local pr = slots[idx]:FindFirstChildOfClass("ProximityPrompt")
            if pr and pr.Enabled and not slotHasWeapon(slots[idx]) then targetSlot, targetIdx = slots[idx], idx break end
        end
        if not targetSlot then
            for i = 0, #slots - 1 do
                local idx = (startIdx - 1 + i) % #slots + 1
                if not slotHasWeapon(slots[idx]) then targetSlot, targetIdx = slots[idx], idx break end
            end
        end
        if not targetSlot then
            if tick()%8<0.6 then print("[Place] No empty slot (", #slots, " all occupied)") end
            return false
        end
        Config.PlaceIndex = targetIdx
        if tick()%8<0.6 then print("[Place] Discovery WITH TP for", tostring(wname), "-> slot #", targetIdx) end
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
            if tick()%8<0.6 then print("[Place] TP plot:", plot.Name, "| slot #", targetIdx) end
        elseif RootPart then
            pcall(function() RootPart.CFrame = CFrame.new(targetSlot:GetPivot().Position + Vector3.new(0,2,0)) end)
        else
            if tick()%5<0.6 then print("[Place] RootPart not found - TP impossible") end
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
        if tick()%8<0.6 then print("[Place] firePrompt failed on", prompt.Name, "| Enabled:", tostring(prompt.Enabled), "| Hold:", tostring(prompt.HoldDuration), "| MaxDist:", tostring(prompt.MaxActivationDistance)) end
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
            Config.LastAbandonT = tick()
            if tick()%5<0.6 then print("[Place] Abandoned after 4 attempts (server refused) - retry in 15s") end
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
        if tick()%10<0.6 then print("[Upgrade] Paused (weapon pending placement)") end
        return
    end
    -- ANTI-POPUP: upgrades also cost cash. When funds are
    -- tight ( "too expensive" cooldown active ), we save cash for box
    -- instead of risking too-expensive purchase on upgrade side (= Robux popup).
    if isRobuxPopupVisible() then
        closeRobuxPopup()
        Config.LastPopupT = tick()
        return
    end
    if Config.LastTooExpensivePrice and (tick() - (Config.LastTooExpensiveT or 0)) < 10 then
        local cashU = 0
        pcall(function() cashU = getPlayerCash() end)
        if cashU <= 0 or cashU < Config.LastTooExpensivePrice * 1.1 then
            return
        end
    end
    local n=0
    -- Server validates distance: TP to each slot (remote fire is rejected).
    for _, slot in ipairs(slots) do
        local prompt = slot:FindFirstChildOfClass("ProximityPrompt")
        if prompt then
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
            if firePrompt(prompt) then n+=1 end
            task.wait(0.1)
        end
    end
    if n > 0 then
        Config.UpgradedCount += n
        if tick()%8<1 then print("[Upgrade] Fired", n, "prompts on", #slots, "slots") end
    end
end

local function getRebirthRemote()
    -- Exact path seen in RebirthGuiScript: ReplicatedStorage.RemoteEvents.RebirthButtonPress
    local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
    if folder then
        local r = folder:FindFirstChild("RebirthButtonPress")
        if r and r:IsA("RemoteEvent") then return r end
    end
    local r2 = ReplicatedStorage:FindFirstChild("RebirthButtonPress", true)
    if r2 and r2:IsA("RemoteEvent") then return r2 end
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
        if tick()%5<0.6 then print("[Rebirth] FireServer RebirthButtonPress (wave:", waveBefore, ")") end
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
            return true
        end
    elseif tick()%10<0.6 then
        print("[Rebirth] Remote RebirthButtonPress not found")
    end
    -- PATH 1: big yellow button of RebirthGui (observed in-game under waves)
    local rgui = findRebirthGui()
    if rgui then
        -- 1) real GuiButton with text rebirth/prestige/reset
        for _, d in ipairs(rgui:GetDescendants()) do
            if d:IsA("TextButton") or d:IsA("ImageButton") then
                local t = ""
                pcall(function() t = d.Text or "" end)
                local tl = t:lower()
                if (tl:find("rebirth") or tl:find("prestige") or tl:find("reset")) and not tl:find("lock") then
                    if tick()%5<0.6 then print("[Rebirth] Clic bouton:", d:GetFullName(), "text='" .. t .. "'") end
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
                            return true
                    end
                end
            end
        end
        -- 2) RebirthFrame = simple Frame clickable via InputBegan (seen in StarterGui)
        for _, d in ipairs(rgui:GetDescendants()) do
            local cn = d.Name:lower()
            if (d:IsA("Frame") or d:IsA("ImageLabel")) and cn:find("rebirth") and not cn:find("lock") then
                if tick()%5<0.6 then print("[Rebirth] Clic frame:", d:GetFullName()) end
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
                        return true
                end
            end
        end
        if tick()%10<0.6 then print("[Rebirth] Nothing clickable in RebirthGui (voir Diagnostic)") end
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
        local n = inst.Name:lower()
        if n:find("coin") or n:find("loot") or n:find("drop") or n:find("cash") or n:find("money") or n:find("orb") then return true end
        if inst:FindFirstChild("CurrencyPickup") or inst:FindFirstChild("CoinPickup") or inst:FindFirstChild("TouchInterest") then return true end
        return false
    end
    local function scanContainer(container, whitelistAll)
        if not container then return end
        for _, c in ipairs(container:GetDescendants()) do
            if c:IsA("BasePart") or c:IsA("MeshPart") or c:IsA("UnionOperation") or c:IsA("TrussPart") then
                -- BUG FIX: in LootSpawnedClient, EVERY part is loot (even without "coin" in name)
                if whitelistAll or isCoinLike(c) or isCoinLike(c.Parent) then
                    addCoin(c)
                end
            end
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
                if n:find("loot") or n:find("coin") or n:find("drop") then
                    scanContainer(obj, n:find("lootspawned") ~= nil)
                end
            end
        end
    end
    if #list == 0 then
        for _, d in ipairs(Workspace:GetChildren()) do
            if (d:IsA("BasePart") or d:IsA("MeshPart") or d:IsA("UnionOperation")) and isCoinLike(d) then
                addCoin(d)
            end
        end
    end
    -- MAGNET: coins come to player (no player TP)
    local root = RootPart
    if not root then return end
    local magnetPos = root.CFrame
    local moved = 0
    for _, cp in ipairs(list) do
        if moved >= 40 then break end
        if not cp.Parent then continue end
        pcall(function()
            local pr = cp:FindFirstChildOfClass("ProximityPrompt")
            if pr then firePrompt(pr) end
            local cd = cp:FindFirstChildOfClass("ClickDetector")
            if cd then fireClick(cd) end
            local parent = cp.Parent
            if parent then
                local ppr = parent:FindFirstChildOfClass("ProximityPrompt")
                if ppr then firePrompt(ppr) end
                local pcd = parent:FindFirstChildOfClass("ClickDetector")
                if pcd then fireClick(pcd) end
            end
        end)
        -- teleport coin EXACTLY onto player (not around: otherwise not collected)
        -- + velocity cancelled + anchored: otherwise it keeps initial velocity and flies away
        pcall(function()
            if cp.Parent then
                cp.AssemblyLinearVelocity = Vector3.zero
                cp.AssemblyAngularVelocity = Vector3.zero
                pcall(function() cp.Anchored = true end)
                cp.CFrame = magnetPos + Vector3.new(0, 0.5, 0)
                moved += 1
            end
        end)
    end
end

-- ============================================================
-- FLY / NOCLIP / MOVEMENT
-- ============================================================
local FlyBV, FlyBG
local function startFly()
    if FlyBV or not RootPart then return end
    pcall(function()
        FlyBV = Instance.new("BodyVelocity")
        FlyBV.MaxForce = Vector3.new(1e9,1e9,1e9)
        FlyBV.Velocity = Vector3.zero
        FlyBV.Parent = RootPart
        FlyBG = Instance.new("BodyGyro")
        FlyBG.MaxTorque = Vector3.new(1e9,1e9,1e9)
        FlyBG.P = 9e3; FlyBG.D = 500
        FlyBG.Parent = RootPart
    end)
end
local function stopFly()
    pcall(function() if FlyBV and FlyBV.Parent then FlyBV:Destroy() end end)
    pcall(function() if FlyBG and FlyBG.Parent then FlyBG:Destroy() end end)
    FlyBV=nil; FlyBG=nil
end
local function updateFly()
    if not Config.FlyEnabled then if FlyBV then stopFly() end return end
    if not RootPart or not RootPart.Parent then return end
    if not FlyBV then startFly() end
    if not FlyBV then return end
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
        FlyBV.Velocity = dir.Magnitude>0 and dir.Unit*Config.FlySpeed or Vector3.zero
        FlyBG.CFrame = cf
    end)
end
local noClipStates = setmetatable({}, {__mode = "k"})
local function updateNoClip()
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
            if p and p.Parent then p.CanCollide = canCollide end
            noClipStates[p] = nil
        end
    end
end

local savedWalkSpeed, savedJumpPower, savedUseJumpPower
local function updateMovement()
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if Config.WalkSpeedEnabled then
        if savedWalkSpeed == nil then savedWalkSpeed = hum.WalkSpeed end
        hum.WalkSpeed = Config.SpeedValue
    elseif savedWalkSpeed ~= nil then
        hum.WalkSpeed = savedWalkSpeed
        savedWalkSpeed = nil
    end
    if Config.JumpPowerEnabled then
        if savedJumpPower == nil then
            savedJumpPower, savedUseJumpPower = hum.JumpPower, hum.UseJumpPower
        end
        hum.UseJumpPower = true
        hum.JumpPower = Config.JumpValue
    elseif savedJumpPower ~= nil then
        hum.JumpPower, hum.UseJumpPower = savedJumpPower, savedUseJumpPower
        savedJumpPower, savedUseJumpPower = nil, nil
    end
end
trackConn(UserInputService.JumpRequest:Connect(function()
    if not Config.InfiniteJump then return end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end))
local antiAFKThread
local function setAntiAFK(on)
    if on then
        if antiAFKThread then return end
        antiAFKThread = task.spawn(function()
            while Config.AntiAFK do
                pcall(function() VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F15, false, game) end)
                task.wait(300)
            end
            antiAFKThread=nil
        end)
    else
        Config.AntiAFK = false
        antiAFKThread=nil
    end
end

-- ============================================================
-- GUI BUILD
-- ============================================================
-- cleanup old gui
pcall(function()
    local pg = LocalPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("PrismMenu")
    if old then old:Destroy() end
    local old2 = pg:FindFirstChild("PrismV2")
    if old2 then old2:Destroy() end
end)

local SG = make("ScreenGui", {Name="PrismMenu", ResetOnSpawn=false, ZIndexBehavior=Enum.ZIndexBehavior.Sibling, DisplayOrder=999, Parent=LocalPlayer:WaitForChild("PlayerGui")})

local MF = make("Frame", {Name="Main", Size=UDim2.new(0,360,0,520), Position=UDim2.new(0.5,-180,0.5,-260), BackgroundColor3=T.BG, BorderSizePixel=0, Visible=false, Parent=SG})
make("UICorner", {CornerRadius=UDim.new(0,16), Parent=MF})
make("UIStroke", {Color=T.Primary, Thickness=1.2, Transparency=0.55, Parent=MF})

-- Title bar (draggable)
local TitleBar = make("Frame", {Name="TitleBar", Size=UDim2.new(1,0,0,44), BackgroundColor3=T.Primary, BorderSizePixel=0, Parent=MF})
make("UICorner", {CornerRadius=UDim.new(0,16), Parent=TitleBar})
make("Frame", {Size=UDim2.new(1,0,0,16), Position=UDim2.new(0,0,1,-16), BackgroundColor3=T.Primary, BorderSizePixel=0, Parent=TitleBar}) -- hide corners
make("UIGradient", {Color=ColorSequence.new({ColorSequenceKeypoint.new(0, T.Primary), ColorSequenceKeypoint.new(1, T.PrimaryDark)}), Rotation=90, Parent=TitleBar})

make("TextLabel", {Size=UDim2.new(1,-90,0,18), Position=UDim2.new(0,16,0,6), BackgroundTransparency=1, Text="Prism", TextColor3=Color3.fromRGB(255,255,255), TextSize=16, Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left, Parent=TitleBar})
make("TextLabel", {Size=UDim2.new(1,-90,0,12), Position=UDim2.new(0,16,0,24), BackgroundTransparency=1, Text="Build a Gun Army  •  v2.1", TextColor3=Color3.fromRGB(255,230,210), TextSize=10, Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Left, Parent=TitleBar})

local CloseBtn = make("TextButton", {Size=UDim2.new(0,28,0,28), Position=UDim2.new(1,-36,0,8), BackgroundColor3=Color3.fromRGB(255,255,255), BackgroundTransparency=0.88, Text="×", TextColor3=Color3.fromRGB(80,40,20), TextSize=18, Font=Enum.Font.GothamBold, Parent=TitleBar})
make("UICorner", {CornerRadius=UDim.new(0,8), Parent=CloseBtn})
local MinBtn = make("TextButton", {Size=UDim2.new(0,28,0,28), Position=UDim2.new(1,-68,0,8), BackgroundColor3=Color3.fromRGB(255,255,255), BackgroundTransparency=0.88, Text="-", TextColor3=Color3.fromRGB(80,40,20), TextSize=12, Font=Enum.Font.GothamBold, Parent=TitleBar})
make("UICorner", {CornerRadius=UDim.new(0,8), Parent=MinBtn})

-- Stats bar
local StatsBar = make("Frame", {Size=UDim2.new(1,0,0,28), Position=UDim2.new(0,0,0,44), BackgroundColor3=T.Surface, BorderSizePixel=0, Parent=MF})
local StatCash = make("TextLabel", {Size=UDim2.new(0.34,0,1,0), BackgroundTransparency=1, Text="$0", TextColor3=T.PrimaryLight, TextSize=11, Font=Enum.Font.GothamBold, Parent=StatsBar})
local StatWave = make("TextLabel", {Size=UDim2.new(0.33,0,1,0), Position=UDim2.new(0.34,0,0,0), BackgroundTransparency=1, Text="Wave 0", TextColor3=T.Text, TextSize=11, Font=Enum.Font.GothamBold, Parent=StatsBar})
local StatCount = make("TextLabel", {Size=UDim2.new(0.33,0,1,0), Position=UDim2.new(0.67,0,0,0), BackgroundTransparency=1, Text="0 placed", TextColor3=T.TextDim, TextSize=11, Font=Enum.Font.Gotham, Parent=StatsBar})

-- Tab bar
local TabBar = make("Frame", {Size=UDim2.new(1,-12,0,32), Position=UDim2.new(0,6,0,78), BackgroundColor3=T.Surface, BorderSizePixel=0, Parent=MF})
make("UICorner", {CornerRadius=UDim.new(0,10), Parent=TabBar})
local TabNames = {"Farm","Movement","Player","Settings"}
local TabBtns = {}
local Indicator = make("Frame", {Size=UDim2.new(0.25,-6,0,2), Position=UDim2.new(0,3,1,-2), BackgroundColor3=T.Primary, BorderSizePixel=0, Parent=TabBar})
make("UICorner", {CornerRadius=UDim.new(1,0), Parent=Indicator})
for i, name in ipairs(TabNames) do
    local btn = make("TextButton", {Name=name, Size=UDim2.new(0.25,0,1,0), Position=UDim2.new((i-1)*0.25,0,0,0), BackgroundTransparency=1, Text=name, TextColor3=(name==Config.ActiveTab and T.Primary or T.TextDim), TextSize=11, Font=Enum.Font.GothamBold, Parent=TabBar})
    TabBtns[name]=btn
end

-- Content
local Content = make("Frame", {Size=UDim2.new(1,-12,1,-118), Position=UDim2.new(0,6,0,116), BackgroundTransparency=1, Parent=MF})
local Pages = {}
local orders = {Farm=0, Movement=0, Player=0, Settings=0}
for _, name in ipairs(TabNames) do
    local sf = make("ScrollingFrame", {Name=name.."Page", Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, BorderSizePixel=0, ScrollBarThickness=3, ScrollBarImageColor3=T.Primary, CanvasSize=UDim2.new(0,0,0,0), Visible=(name==Config.ActiveTab), Parent=Content})
    make("UIListLayout", {Padding=UDim.new(0,6), SortOrder=Enum.SortOrder.LayoutOrder, Parent=sf})
    make("UIPadding", {PaddingTop=UDim.new(0,2), PaddingBottom=UDim.new(0,8), PaddingLeft=UDim.new(0,2), PaddingRight=UDim.new(0,4), Parent=sf})
    Pages[name]=sf
end
local function tagCanvas()
    for _, pg in pairs(Pages) do
        local ll = pg:FindFirstChildOfClass("UIListLayout")
        if ll then pg.CanvasSize = UDim2.new(0,0,0, ll.AbsoluteContentSize.Y + 12) end
    end
end
for _, pg in pairs(Pages) do pg:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(tagCanvas) end

local function nextOrder(tab) orders[tab]+=1 return orders[tab] end

local function section(tab, title)
    local pg = Pages[tab]
    local row = make("Frame", {Size=UDim2.new(1,0,0,20), BackgroundTransparency=1, LayoutOrder=nextOrder(tab), Parent=pg})
    make("TextLabel", {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text="  "..string.upper(title), TextColor3=T.PrimaryLight, TextSize=11, Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left, Parent=row})
    make("Frame", {Size=UDim2.new(1,0,0,1), Position=UDim2.new(0,0,1,-1), BackgroundColor3=T.Primary, BackgroundTransparency=0.7, BorderSizePixel=0, Parent=row})
    task.defer(tagCanvas)
end

local function toggle(tab, key, label, cb)
    local pg = Pages[tab]
    local row = make("Frame", {Size=UDim2.new(1,0,0,36), BackgroundColor3=T.Surface, BorderSizePixel=0, LayoutOrder=nextOrder(tab), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,8), Parent=row})
    make("TextLabel", {Size=UDim2.new(1,-62,1,0), Position=UDim2.new(0,12,0,0), BackgroundTransparency=1, Text=label, TextColor3=T.Text, TextSize=12, Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Left, Parent=row})

    local bg = make("Frame", {Size=UDim2.new(0,40,0,20), Position=UDim2.new(1,-50,0.5,-10), BackgroundColor3=Config[key] and T.Success or T.ToggleOff, BorderSizePixel=0, Parent=row})
    make("UICorner", {CornerRadius=UDim.new(1,0), Parent=bg})
    local dot = make("Frame", {Size=UDim2.new(0,16,0,16), Position=Config[key] and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8), BackgroundColor3=Color3.fromRGB(255,255,255), BorderSizePixel=0, Parent=bg})
    make("UICorner", {CornerRadius=UDim.new(1,0), Parent=dot})

    local function refresh()
        local on = Config[key]
        tw(bg, {BackgroundColor3 = on and T.Success or T.ToggleOff}, 0.16)
        tw(dot, {Position = on and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)}, 0.16, Enum.EasingStyle.Back)
    end
    local hit = make("TextButton", {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text="", Parent=row})
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
    local row = make("Frame", {Size=UDim2.new(1,0,0,48), BackgroundColor3=T.Surface, BorderSizePixel=0, LayoutOrder=nextOrder(tab), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,8), Parent=row})
    make("TextLabel", {Size=UDim2.new(0.55,0,0,14), Position=UDim2.new(0,12,0,6), BackgroundTransparency=1, Text=label, TextColor3=T.Text, TextSize=11, Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Left, Parent=row})
    local val = Config[key]
    -- editable value via keyboard (e.g. type 23 or 104) + drag slider; both sync
    local valBox = make("TextBox", {Size=UDim2.new(0.4,0,0,14), Position=UDim2.new(0.55,0,0,6), BackgroundTransparency=1, Text=tostring(val)..(suffix or ""), TextColor3=T.Primary, TextSize=11, Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Right, ClearTextOnFocus=false, Parent=row})
    local track = make("Frame", {Size=UDim2.new(1,-24,0,4), Position=UDim2.new(0,12,0,30), BackgroundColor3=T.Surface2, BorderSizePixel=0, Parent=row})
    make("UICorner", {CornerRadius=UDim.new(1,0), Parent=track})
    local frac = math.clamp((val-min)/(max-min),0,1)
    local fill = make("Frame", {Size=UDim2.new(frac,0,1,0), BackgroundColor3=T.Primary, BorderSizePixel=0, Parent=track})
    make("UICorner", {CornerRadius=UDim.new(1,0), Parent=fill})
    local knob = make("Frame", {Size=UDim2.new(0,14,0,14), Position=UDim2.new(frac,-7,0.5,-7), BackgroundColor3=Color3.fromRGB(255,255,255), BorderSizePixel=0, Parent=track})
    make("UICorner", {CornerRadius=UDim.new(1,0), Parent=knob})
    make("UIStroke", {Color=T.Primary, Thickness=1.2, Parent=knob})
    local dragging=false
    local function paint(v)
        local f = math.clamp((v-min)/(max-min),0,1)
        fill.Size = UDim2.new(f,0,1,0)
        knob.Position = UDim2.new(f,-7,0.5,-7)
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
    for n, btn in pairs(TabBtns) do btn.TextColor3 = (n==name and T.Primary or T.TextDim) end
    local idx = 1 for i,n in ipairs(TabNames) do if n==name then idx=i break end end
    tw(Indicator, {Position = UDim2.new((idx-1)*0.25, 3, 1, -2)}, 0.18)
    task.defer(tagCanvas)
end
for name, btn in pairs(TabBtns) do btn.MouseButton1Click:Connect(function() switchTab(name) end) end

-- Drag
do
    local dragging=false
    local startMouse, startPos
    local dragHit = make("TextButton", {Size=UDim2.new(1,-76,1,0), BackgroundTransparency=1, Text="", Parent=TitleBar})
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

-- Minimize / Close
local minimized=false
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        tw(MF, {Size=UDim2.new(0,360,0,44)}, 0.22, Enum.EasingStyle.Quart)
        StatsBar.Visible=false; TabBar.Visible=false; Content.Visible=false
    else
        StatsBar.Visible=true; TabBar.Visible=true; Content.Visible=true
        tw(MF, {Size=UDim2.new(0,360,0,520)}, 0.26, Enum.EasingStyle.Back)
        task.defer(tagCanvas)
    end
end)
CloseBtn.MouseButton1Click:Connect(function()
    Config.MenuOpen=false
    tw(MF, {Size=UDim2.new(0,360,0,44)}, 0.18)
    task.delay(0.18, function() if not Config.MenuOpen then MF.Visible=false end end)
end)
local function openMenu()
    Config.MenuOpen=true; MF.Visible=true
    if minimized then minimized=false StatsBar.Visible=true TabBar.Visible=true Content.Visible=true end
    MF.Size=UDim2.new(0,360,0,44)
    tw(MF, {Size=UDim2.new(0,360,0,520)}, 0.28, Enum.EasingStyle.Back)
    task.defer(tagCanvas)
end
local function closeMenu()
    Config.MenuOpen=false
    tw(MF, {Size=UDim2.new(0,360,0,44)}, 0.18)
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
toggle("Farm","MasterAutoFarm","Master Auto Farm (enable all)", function(v)
    notify("Farm", v and "MASTER ON - all farms active" or "MASTER OFF")
end)
toggle("Farm","AutoBuyAffordable","Auto Buy Weapon Box", function(v) notify("Farm", v and "Auto Buy ON" or "Auto Buy OFF") end)
toggle("Farm","AutoPlaceUpgrade","Auto Place + Upgrade", function(v)
    Config.AutoPlace = v
    Config.AutoUpgrade = v
    notify("Farm", v and "Place + Upgrade ON" or "Place + Upgrade OFF")
end)
toggle("Farm","AutoRebirth","Auto Rebirth", function(v) notify("Farm", v and "Auto Rebirth ON" or "Auto Rebirth OFF") end)
toggle("Farm","AutoPickupCoins","Auto Pickup Coins", function(v) notify("Farm", v and "Pickup ON" or "Pickup OFF") end)

section("Farm","Delays")
slider("Farm","PlaceDelay","Place Delay",0.1,3,0.1,"s")
slider("Farm","BuyPause","View roll pause (0.5 fast / 2 reliable)",0.5,5,0.5,"s")
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
do
    local pg = Pages.Settings
    local row = make("Frame", {Size=UDim2.new(1,0,0,36), BackgroundColor3=T.Surface, BorderSizePixel=0, LayoutOrder=nextOrder("Settings"), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,8), Parent=row})
    make("TextLabel", {Size=UDim2.new(0.5,0,1,0), Position=UDim2.new(0,12,0,0), BackgroundTransparency=1, Text="Theme", TextColor3=T.Text, TextSize=11, Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Left, Parent=row})
    local b = make("TextButton", {Size=UDim2.new(0,72,0,22), Position=UDim2.new(1,-84,0.5,-11), BackgroundColor3=T.Primary, Text="Claude", TextColor3=Color3.fromRGB(255,255,255), TextSize=11, Font=Enum.Font.GothamBold, Parent=row})
    make("UICorner", {CornerRadius=UDim.new(0,8), Parent=b})
    b.MouseButton1Click:Connect(function() notify("Theme","Claude - only theme for now") end)
    task.defer(tagCanvas)
end

section("Settings","Stats")
local statsLbl
do
    local pg = Pages.Settings
    local fr = make("Frame", {Size=UDim2.new(1,0,0,70), BackgroundColor3=T.Surface, BorderSizePixel=0, LayoutOrder=nextOrder("Settings"), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,8), Parent=fr})
    statsLbl = make("TextLabel", {Size=UDim2.new(1,-14,1,-8), Position=UDim2.new(0,7,0,4), BackgroundTransparency=1, Text="Bought: 0 | Skipped: 0\nPlaced: 0 | Upgraded: 0\nRebirths: 0", TextColor3=T.TextDim, TextSize=11, Font=Enum.Font.Code, TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top, Parent=fr})
    task.defer(tagCanvas)
end

section("Settings","Live detection")
local detectLbl
do
    local pg = Pages.Settings
    local fr = make("Frame", {Size=UDim2.new(1,0,0,68), BackgroundColor3=T.Surface, BorderSizePixel=0, LayoutOrder=nextOrder("Settings"), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,8), Parent=fr})
    make("UIStroke", {Color=T.Primary, Transparency=0.7, Thickness=1, Parent=fr})
    detectLbl = make("TextLabel", {Size=UDim2.new(1,-12,1,-8), Position=UDim2.new(0,6,0,4), BackgroundTransparency=1, Text="Plot: ...\nCash: ... | Box: ...\nLast: -", TextColor3=T.PrimaryLight, TextSize=10, Font=Enum.Font.Code, TextXAlignment=Enum.TextXAlignment.Left, TextYAlignment=Enum.TextYAlignment.Top, Parent=fr})
    task.defer(tagCanvas)
end

do
    local pg = Pages.Settings
    local btnRescan = make("TextButton", {Size=UDim2.new(1,0,0,28), BackgroundColor3=T.Primary, Text="↻ Rescan Cash/Wave/Plot", TextColor3=Color3.fromRGB(255,255,255), TextSize=11, Font=Enum.Font.GothamBold, LayoutOrder=nextOrder("Settings"), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,8), Parent=btnRescan})
    btnRescan.MouseButton1Click:Connect(function()
        _cashObj=nil _cashAttrRoot=nil _cashAttrKey=nil _cashUI=nil _triedHeavyCash=false
        _waveObj=nil _waveAttrRoot=nil _waveAttrKey=nil _waveUI=nil _triedHeavyWave=false
        cachedPlot=nil
        notify("Rescan","Cache cleared, rescanning…")
        task.wait(0.5)
        local c=getPlayerCash(); local w=getPlayerWave(); local p=getPlot()
        print("[Rescan] Cash:",c," Wave:",w," Plot:",p and p.Name or "nil")
    end)
    task.defer(tagCanvas)
end

section("Settings","Diagnostic")
do
    local pg = Pages.Settings
    local btn = make("TextButton", {Size=UDim2.new(1,0,0,34), BackgroundColor3=T.Surface2, Text="Run diagnostic  (console F9)", TextColor3=T.Text, TextSize=11, Font=Enum.Font.GothamBold, LayoutOrder=nextOrder("Settings"), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,8), Parent=btn})
    btn.MouseButton1Click:Connect(function()
        task.spawn(function()
            pcall(function()
                local plot = getPlot()
                print("=== PRISM DIAGNOSTIC ===")
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
    local btn2 = make("TextButton", {Size=UDim2.new(1,0,0,30), BackgroundColor3=T.Surface, Text="Dump Cash/Wave sources (F9)", TextColor3=T.TextDim, TextSize=10, Font=Enum.Font.Gotham, LayoutOrder=nextOrder("Settings"), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,8), Parent=btn2})
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
    pcall(stopFly)
    pcall(updateMovement)
    pcall(updateNoClip)
    -- déconnecte tout ce qui est branché sur les services (boucles/inputs)
    for _, c in ipairs(Connections) do
        pcall(function() c:Disconnect() end)
    end
    -- détruit le GUI (ses propres connexions meurent avec lui)
    pcall(function() SG:Destroy() end)
    print("[Prism] Script unloaded: GUI destroyed, loops stopped, character restored")
end
do
    local pg = Pages.Settings
    local un = make("TextButton", {Size=UDim2.new(1,0,0,32), BackgroundColor3=Color3.fromRGB(170,60,60), Text="UNLOAD script (Unload)", TextColor3=Color3.fromRGB(255,255,255), TextSize=12, Font=Enum.Font.GothamBold, LayoutOrder=nextOrder("Settings"), Parent=pg})
    make("UICorner", {CornerRadius=UDim.new(0,8), Parent=un})
    un.MouseButton1Click:Connect(function() unloadScript() end)
    task.defer(tagCanvas)
end

do
    local pg = Pages.Settings
    make("TextLabel", {Size=UDim2.new(1,0,0,32), BackgroundTransparency=1, Text="Prism v2.1  •  RightShift = menu\nDrag top bar to move", TextColor3=T.TextFaint, TextSize=10, Font=Enum.Font.Gotham, TextWrapped=true, LayoutOrder=nextOrder("Settings"), Parent=pg})
    task.defer(tagCanvas)
end

-- ============================================================
-- HEARTBEAT (lightweight, single connection)
-- ============================================================
trackConn(RunService.Heartbeat:Connect(function()
    if Config.Unloaded then return end
    pcall(updateFly)
    pcall(updateNoClip)
    pcall(updateMovement)
end))

-- ============================================================
-- AUTO FARM (single thread)
-- ============================================================
task.spawn(function()
    while not Config.Unloaded do
        pcall(function()
            if Config.MasterAutoFarm then
                -- MASTER: buy + place + magnet (upgrade runs in its own slow thread)
                buyWeaponBox() task.wait(0.35)
                placeWeapon() task.wait(Config.PlaceDelay)
                if not hasRemoteFire() then upgradeAllWeapons() task.wait(0.8) end
                pickupCoins() task.wait(0.25)
                if getPlayerWave() >= Config.RebirthWave then doRebirth() task.wait(Config.RebirthCheckDelay) end
            else
                if Config.AutoBuyAffordable then buyWeaponBox() task.wait(0.2) end
                if Config.AutoPlaceUpgrade or Config.AutoPlace then placeWeapon() task.wait(Config.PlaceDelay) end
                if (Config.AutoPlaceUpgrade or Config.AutoUpgrade) and not hasRemoteFire() then upgradeAllWeapons() task.wait(0.3) end
                if Config.AutoPickupCoins then pickupCoins() task.wait(0.15) end
                if Config.AutoRebirth and getPlayerWave() >= Config.RebirthWave then doRebirth() end
            end
        end)
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

-- Watchdog ANTI-ROBUX POPUP: if "Buy Robux and item" popup appears despite
-- guards (e.g. race-condition), we close it immediately + arm cooldown.
task.spawn(function()
    while not Config.Unloaded do
        pcall(function()
            if isRobuxPopupVisible() then
                print("[AntiPopup] Popup Robux détecté → fermeture auto")
                closeRobuxPopup()
                Config.LastPopupT = tick()
            end
        end)
        task.wait(0.5)
    end
end)

-- Stats bar update (1s, lightweight)
task.spawn(function()
    while not Config.Unloaded do
        pcall(function()
            local cash = getPlayerCash()
            local wave = getPlayerWave()
            StatCash.Text = "$"..fmt(cash)
            StatWave.Text = "Wave "..tostring(wave)
            StatCount.Text = string.format("%d placed • %d↑", Config.PlacedCount, Config.UpgradedCount)
            if statsLbl then
                statsLbl.Text = string.format("Bought: %d | Skipped: %d\nPlaced: %d | Upgraded: %d\nRebirths: %d", Config.BoughtCount, Config.SkippedCount, Config.PlacedCount, Config.UpgradedCount, Config.RebirthCount)
            end
            if detectLbl then
                local plot = getPlot()
                local plotName = plot and (plot.Name.." ("..plot.ClassName..")") or "nil"
                local boxTxt = Config.LastBoxPrice and fmt(Config.LastBoxPrice) or "?"
                detectLbl.Text = string.format("Plot: %s\nCash: %s | Box: %s\nLast: %s", plotName, fmt(cash), boxTxt, tostring(Config.LastBoxAction or "-"))
                -- color by detection
                if cash==0 and wave==0 and (not plot) then
                    detectLbl.TextColor3 = Color3.fromRGB(220,80,80)
                elseif cash==0 or wave==0 then
                    detectLbl.TextColor3 = Color3.fromRGB(220,180,80)
                else
                    detectLbl.TextColor3 = T.PrimaryLight
                end
            end
        end)
        task.wait(1)
    end
end)

-- ============================================================
-- STARTUP - lightweight diagnostic once
-- ============================================================
notify("Prism v2.1","Loaded! RightShift = menu")
print("[Prism v2.1] Menu: RightShift | Drag title bar | Tabs Farm/Movement/Player/Settings")
task.spawn(function()
    task.wait(2)
    pcall(function()
        local plot = getPlot()
        print("[Prism] Plot:", plot and (plot.ClassName.." "..plot.Name) or "nil - open Settings > Diagnostic for details")
        if not plot then
            print("[Prism] Tip: if Plot=nil, farm cannot work. Run diagnostic in Settings.")
        else
            local n=0 for _, d in ipairs(plot:GetDescendants()) do if d:IsA("ProximityPrompt") then n+=1 end end
            print("[Prism] Prompts in plot:", n)
            print("[Prism] WeaponBasePart:", #findWeaponSlots(plot))
        end
        print("[Prism] Remote fire (without TP):", hasRemoteFire() and "OUI" or "NON")
    end)
end)

local LINK = "https://work.ink/2IAE/build-a-gun-army-auto-farm"
local DESCRIPTION = "Follow this link and the steps to get the Build A Gun Army Auto Farm script. Thanks, have fun!"

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

-- Parent safe pour exploit / Studio
local function getParent()
    local ok, hui = pcall(function() return gethui and gethui() end)
    if ok and hui then return hui end
    local ok2, coreGui = pcall(function() return game:GetService("CoreGui") end)
    -- Studio n'autorise pas CoreGui, on fallback sur PlayerGui
    if LocalPlayer then
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then return pg end
    end
    return coreGui
end

-- Supprime l'ancien GUI si ré-exécuté
do
    local parent = getParent()
    local old = parent:FindFirstChild("WorkInkGUI")
    if old then old:Destroy() end
end

local parent = getParent()

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "WorkInkGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent = parent

-- Fond semi-transparent pour focus
local Overlay = Instance.new("Frame")
Overlay.Name = "Overlay"
Overlay.Size = UDim2.fromScale(1, 1)
Overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
Overlay.BackgroundTransparency = 0.35
Overlay.BorderSizePixel = 0
Overlay.Parent = ScreenGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Position = UDim2.fromScale(0.5, 0.5)
Main.Size = UDim2.fromOffset(380, 230)
Main.BackgroundColor3 = Color3.fromRGB(25, 25, 28)
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 12)
Corner.Parent = Main

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(214, 120, 82)
Stroke.Thickness = 1.2
Stroke.Transparency = 0.3
Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
Stroke.Parent = Main

-- Draggable
Main.Active = true
Main.Draggable = true

-- Titre barre
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 38)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = Main

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 12)
TitleCorner.Parent = TitleBar

local FixCorner = Instance.new("Frame")
FixCorner.Size = UDim2.new(1, 0, 0, 12)
FixCorner.Position = UDim2.new(0, 0, 1, -12)
FixCorner.BackgroundColor3 = Color3.fromRGB(35, 35, 38)
FixCorner.BorderSizePixel = 0
FixCorner.Parent = TitleBar

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(14, 0)
Title.Size = UDim2.new(1, -50, 1, 0)
Title.Font = Enum.Font.GothamBold
Title.Text = "Build A Gun Army - Auto Farm"
Title.TextColor3 = Color3.fromRGB(235, 232, 226)
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.AnchorPoint = Vector2.new(1, 0.5)
CloseBtn.Position = UDim2.new(1, -6, 0.5, 0)
CloseBtn.Size = UDim2.fromOffset(28, 28)
CloseBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 53)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 14
CloseBtn.AutoButtonColor = true
CloseBtn.Parent = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 8)
CloseCorner.Parent = CloseBtn

-- Description
local Desc = Instance.new("TextLabel")
Desc.Name = "Description"
Desc.BackgroundTransparency = 1
Desc.Position = UDim2.fromOffset(16, 50)
Desc.Size = UDim2.new(1, -32, 0, 60)
Desc.Font = Enum.Font.Gotham
Desc.Text = DESCRIPTION
Desc.TextColor3 = Color3.fromRGB(200, 198, 193)
Desc.TextSize = 13
Desc.TextWrapped = true
Desc.TextYAlignment = Enum.TextYAlignment.Top
Desc.Parent = Main

-- Zone Lien
local LinkBox = Instance.new("Frame")
LinkBox.Name = "LinkBox"
LinkBox.Position = UDim2.fromOffset(16, 118)
LinkBox.Size = UDim2.new(1, -32, 0, 38)
LinkBox.BackgroundColor3 = Color3.fromRGB(43, 43, 47)
LinkBox.BorderSizePixel = 0
LinkBox.Parent = Main

local LinkCorner = Instance.new("UICorner")
LinkCorner.CornerRadius = UDim.new(0, 8)
LinkCorner.Parent = LinkBox

local LinkStroke = Instance.new("UIStroke")
LinkStroke.Color = Color3.fromRGB(60, 60, 65)
LinkStroke.Thickness = 1
LinkStroke.Parent = LinkBox

local LinkText = Instance.new("TextBox")
LinkText.Name = "LinkText"
LinkText.BackgroundTransparency = 1
LinkText.Position = UDim2.fromOffset(10, 0)
LinkText.Size = UDim2.new(1, -20, 1, 0)
LinkText.Font = Enum.Font.Code
LinkText.Text = LINK
LinkText.TextColor3 = Color3.fromRGB(90, 170, 255)
LinkText.TextSize = 11
LinkText.TextXAlignment = Enum.TextXAlignment.Left
LinkText.TextTruncate = Enum.TextTruncate.AtEnd
LinkText.ClearTextOnFocus = false
LinkText.TextEditable = false
LinkText.Parent = LinkBox

-- Boutons en bas
local CopyBtn = Instance.new("TextButton")
CopyBtn.Name = "CopyBtn"
CopyBtn.Position = UDim2.fromOffset(16, 170)
CopyBtn.Size = UDim2.new(1, -32, 0, 38)
CopyBtn.BackgroundColor3 = Color3.fromRGB(214, 120, 82)
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.Text = "COPY LINK"
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.TextSize = 13
CopyBtn.AutoButtonColor = true
CopyBtn.Parent = Main

local CopyCorner = Instance.new("UICorner")
CopyCorner.CornerRadius = UDim.new(0, 8)
CopyCorner.Parent = CopyBtn

local CopiedLabel = Instance.new("TextLabel")
CopiedLabel.Name = "CopiedLabel"
CopiedLabel.BackgroundTransparency = 1
CopiedLabel.Position = UDim2.new(0, 0, 1, -18)
CopiedLabel.Size = UDim2.new(1, 0, 0, 14)
CopiedLabel.Font = Enum.Font.Gotham
CopiedLabel.Text = ""
CopiedLabel.TextColor3 = Color3.fromRGB(120, 220, 120)
CopiedLabel.TextSize = 11
CopiedLabel.Visible = false
CopiedLabel.Parent = Main

-- Animations ouverture
Main.Size = UDim2.fromOffset(0, 0)
TweenService:Create(Main, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Size = UDim2.fromOffset(380, 230)
}):Play()
TweenService:Create(Overlay, TweenInfo.new(0.2), {BackgroundTransparency = 0.35}):Play()

-- Fonctions fermeture
local function close()
    TweenService:Create(Main, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
        Size = UDim2.fromOffset(0, 0)
    }):Play()
    TweenService:Create(Overlay, TweenInfo.new(0.18), {BackgroundTransparency = 1}):Play()
    task.wait(0.2)
    ScreenGui:Destroy()
end

CloseBtn.MouseButton1Click:Connect(close)
Overlay.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        -- optionnel : fermer en cliquant hors du GUI, commente si tu veux pas
        -- close()
    end
end)

-- Copie
local function notifyCopied()
    CopiedLabel.Text = "✓ Link Copied ! Paste it in your internet browser"
    CopiedLabel.Visible = true
    task.delay(2.5, function()
        if CopiedLabel then CopiedLabel.Visible = false end
    end)
    -- feedback bouton
    local orig = CopyBtn.Text
    CopyBtn.Text = "COPIED ✓"
    CopyBtn.BackgroundColor3 = Color3.fromRGB(75, 150, 75)
    task.wait(1.2)
    if CopyBtn then
        CopyBtn.Text = orig
        CopyBtn.BackgroundColor3 = Color3.fromRGB(214, 120, 82)
    end
end

CopyBtn.MouseButton1Click:Connect(function()
    local copied = false
    if setclipboard then
        pcall(setclipboard, LINK)
        copied = true
    elseif toclipboard then
        pcall(toclipboard, LINK)
        copied = true
    elseif set_clipboard then
        pcall(set_clipboard, LINK)
        copied = true
    end
    -- fallback : selectionne le texte pour copie manuelle CTRL+C
    if not copied then
        LinkText:CaptureFocus()
        LinkText.CursorPosition = #LINK + 1
    end
    notifyCopied()
end)

LinkText.Focused:Connect(function()
    LinkText.CursorPosition = #LINK + 1
    LinkText.SelectionStart = 1
end)

-- Raccourci ECHAP pour fermer
game:GetService("UserInputService").InputBegan:Connect(function(input, gp)
    if input.KeyCode == Enum.KeyCode.Escape and ScreenGui.Parent then
        close()
    end
end)

print("[WorkInkGUI] Affiche - " .. LINK)

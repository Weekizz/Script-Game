--[[
    Game Tools V2 - LocalScript
    À mettre dans StarterPlayer > StarterPlayerScripts de TON jeu.

    Onglets :
      AIM    : aim assist 0-100, cercle FOV, cibles joueurs / NPC, statut en direct
      VISUEL : highlight (ESP) des joueurs / NPC
      FLY    : fly 1-256, noclip, boutons montée/descente mobile (owner uniquement)

    Touches PC : Q = aim, F = fly, Espace = monter, Ctrl gauche = descendre
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- =====================================================================
--  REGLAGES
-- =====================================================================
local CONFIG = {
    -- Aim assist
    AimEnabled = false,
    AssistPower = 40,        -- 0 à 100
    FovRadius = 180,         -- rayon du cercle (pixels)
    ShowFovCircle = true,
    MaxDistance = 250,       -- studs
    AimTargets = "Both",     -- "Players", "NPC", "Both"
    AimPart = "Head",        -- "Head", "Torso", "Root"
    TeamCheck = true,        -- ignorer les alliés
    WallCheck = true,        -- ignorer les cibles derrière un mur
    AimKey = Enum.KeyCode.Q,

    -- Visuel (highlight)
    EspEnabled = false,
    EspTargets = "Both",
    EspIncludeAllies = true,
    EspColorIndex = 1,
    EspFillTransparency = 50, -- 0 à 100

    -- Fly (owner)
    FlySpeed = 60,           -- 1 à 256
    FlyKey = Enum.KeyCode.F,
    Noclip = false,
}

-- Qui peut utiliser le fly (en plus du créateur du jeu)
local OWNER_NAMES = { "kts_knigth" } -- en minuscules
local OWNER_IDS = {}                 -- ex: { 123456789 }

local COLORS = {
    { "Rouge", Color3.fromRGB(255, 60, 60) },
    { "Orange", Color3.fromRGB(255, 150, 40) },
    { "Jaune", Color3.fromRGB(255, 220, 50) },
    { "Vert", Color3.fromRGB(70, 230, 110) },
    { "Cyan", Color3.fromRGB(50, 220, 240) },
    { "Bleu", Color3.fromRGB(70, 120, 255) },
    { "Violet", Color3.fromRGB(170, 90, 255) },
    { "Blanc", Color3.fromRGB(255, 255, 255) },
}

local THEME = {
    Bg = Color3.fromRGB(17, 17, 23),
    Panel = Color3.fromRGB(28, 28, 38),
    Item = Color3.fromRGB(38, 38, 52),
    Accent = Color3.fromRGB(88, 101, 242),
    On = Color3.fromRGB(67, 200, 120),
    Off = Color3.fromRGB(80, 80, 98),
    Text = Color3.fromRGB(240, 240, 245),
    Sub = Color3.fromRGB(160, 160, 175),
}

-- =====================================================================
--  OWNER
-- =====================================================================
local function isOwner(player)
    if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
        return true
    end
    if game.CreatorType == Enum.CreatorType.Group then
        local ok, rank = pcall(function()
            return player:GetRankInGroup(game.CreatorId)
        end)
        if ok and rank == 255 then
            return true
        end
    end
    if table.find(OWNER_IDS, player.UserId) then
        return true
    end
    if table.find(OWNER_NAMES, string.lower(player.Name)) then
        return true
    end
    return false
end

local canFly = isOwner(LocalPlayer)

-- =====================================================================
--  CIBLES (joueurs + NPC)
-- =====================================================================
local npcSet = {} -- [Model] = Humanoid

local function registerHumanoid(hum)
    local model = hum.Parent
    if not model or not model:IsA("Model") then return end
    if Players:GetPlayerFromCharacter(model) then return end
    npcSet[model] = hum
end

for _, d in ipairs(workspace:GetDescendants()) do
    if d:IsA("Humanoid") then
        registerHumanoid(d)
    end
end

workspace.DescendantAdded:Connect(function(d)
    if d:IsA("Humanoid") then
        task.defer(registerHumanoid, d)
    end
end)

workspace.DescendantRemoving:Connect(function(d)
    if d:IsA("Humanoid") and d.Parent then
        npcSet[d.Parent] = nil
    end
end)

local function isAlly(player)
    return LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team
end

-- Appelle fn(model, humanoid, name) pour chaque cible
local function forEachTarget(mode, includeAllies, fn)
    if mode == "Players" or mode == "Both" then
        for _, player in ipairs(Players:GetPlayers()) do
            local char = player.Character
            if player ~= LocalPlayer and char and (includeAllies or not isAlly(player)) then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                    fn(char, hum, player.Name)
                end
            end
        end
    end

    if mode == "NPC" or mode == "Both" then
        local myChar = LocalPlayer.Character
        for model, hum in pairs(npcSet) do
            if model.Parent and hum.Parent
                and not Players:GetPlayerFromCharacter(model)
                and not (myChar and model:IsDescendantOf(myChar)) then
                fn(model, hum, model.Name)
            end
        end
    end
end

-- =====================================================================
--  AIM ASSIST
-- =====================================================================
local PART_NAMES = {
    Head = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" },
    Torso = { "UpperTorso", "Torso", "HumanoidRootPart" },
    Root = { "HumanoidRootPart", "UpperTorso", "Torso" },
}

local function getAimPart(model)
    for _, name in ipairs(PART_NAMES[CONFIG.AimPart]) do
        local p = model:FindFirstChild(name)
        if p and p:IsA("BasePart") then
            return p
        end
    end
    return model.PrimaryPart
end

local function isVisible(part, model)
    local origin = Camera.CFrame.Position
    local ignore = { LocalPlayer.Character }
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.RespectCanCollide = true

    for _ = 1, 4 do
        params.FilterDescendantsInstances = ignore
        local result = workspace:Raycast(origin, part.Position - origin, params)
        if not result then
            return true
        end
        local inst = result.Instance
        if inst:IsDescendantOf(model) then
            return true
        end
        if inst.Transparency >= 0.9 then
            table.insert(ignore, inst) -- on traverse les parts quasi invisibles
        else
            return false
        end
    end
    return false
end

local function getBestTarget()
    local viewport = Camera.ViewportSize
    local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
    local camPos = Camera.CFrame.Position
    local bestPart, bestName, bestDist = nil, nil, CONFIG.FovRadius

    forEachTarget(CONFIG.AimTargets, not CONFIG.TeamCheck, function(model, hum, name)
        if hum.Health <= 0 then return end

        local part = getAimPart(model)
        if not part then return end
        if (part.Position - camPos).Magnitude > CONFIG.MaxDistance then return end

        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen then return end

        local d = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
        if d < bestDist and (not CONFIG.WallCheck or isVisible(part, model)) then
            bestPart, bestName, bestDist = part, name, d
        end
    end)

    return bestPart, bestName
end

local aimStatus = "Aim désactivé"
local aimLocked = false

local function updateAim(dt)
    aimLocked = false

    if not CONFIG.AimEnabled then
        aimStatus = "Aim désactivé"
        return
    end

    local power = math.clamp(CONFIG.AssistPower, 0, 100)
    if power <= 0 then
        aimStatus = "Puissance à 0 : aucune aide"
        return
    end

    local part, name = getBestTarget()
    if not part then
        aimStatus = "Aucune cible dans le cercle"
        return
    end

    aimLocked = true
    local dist = math.floor((part.Position - Camera.CFrame.Position).Magnitude)
    aimStatus = "Cible : " .. name .. " (" .. dist .. " studs)"

    local goal = CFrame.new(Camera.CFrame.Position, part.Position)

    if power >= 100 then
        Camera.CFrame = goal -- 100 = lock total
        return
    end

    -- 1 à 99 : plus le chiffre est haut, plus la caméra est attirée
    local base = (power / 100) ^ 1.5
    local alpha = 1 - (1 - base) ^ (dt * 60) -- indépendant des FPS
    Camera.CFrame = Camera.CFrame:Lerp(goal, alpha)
end

-- =====================================================================
--  VISUEL : HIGHLIGHT
-- =====================================================================
local espHighlights = {} -- [Model] = Highlight

local function syncEsp()
    local seen = {}

    if CONFIG.EspEnabled then
        local enemyColor = COLORS[CONFIG.EspColorIndex][2]

        forEachTarget(CONFIG.EspTargets, CONFIG.EspIncludeAllies, function(model, hum)
            if hum.Health <= 0 then return end
            seen[model] = true

            local h = espHighlights[model]
            if not h or not h.Parent then
                h = Instance.new("Highlight")
                h.Name = "GT_ESP"
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.Adornee = model
                h.Parent = model
                espHighlights[model] = h
            end

            local plr = Players:GetPlayerFromCharacter(model)
            local ally = plr ~= nil and isAlly(plr)
            h.FillColor = ally and THEME.On or enemyColor
            h.OutlineColor = Color3.new(1, 1, 1)
            h.FillTransparency = CONFIG.EspFillTransparency / 100
        end)
    end

    for model, h in pairs(espHighlights) do
        if not seen[model] then
            h:Destroy()
            espHighlights[model] = nil
        end
    end
end

local espTimer = 0
RunService.Heartbeat:Connect(function(dt)
    espTimer = espTimer + dt
    if espTimer >= 0.25 then
        espTimer = 0
        syncEsp()
    end
end)

-- =====================================================================
--  FLY + NOCLIP
-- =====================================================================
local flying = false
local flyVelocity, flyGyro
local flyUp, flyDown = false, false
local setFly -- défini plus bas (interface)

local function stopFly()
    flying = false
    if flyVelocity then flyVelocity:Destroy() flyVelocity = nil end
    if flyGyro then flyGyro:Destroy() flyGyro = nil end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = false end
end

local function startFly()
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return false end

    flyVelocity = Instance.new("BodyVelocity")
    flyVelocity.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    flyVelocity.Velocity = Vector3.zero
    flyVelocity.Parent = root

    flyGyro = Instance.new("BodyGyro")
    flyGyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    flyGyro.P = 9e4
    flyGyro.CFrame = root.CFrame
    flyGyro.Parent = root

    hum.PlatformStand = true
    flying = true
    return true
end

local function updateFly(dt)
    if not flying then return end

    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or not flyVelocity or not flyVelocity.Parent then
        setFly(false)
        return
    end

    local look = Camera.CFrame.LookVector
    local right = Camera.CFrame.RightVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    local flatRight = Vector3.new(right.X, 0, right.Z)
    if flatLook.Magnitude > 0.001 then flatLook = flatLook.Unit end
    if flatRight.Magnitude > 0.001 then flatRight = flatRight.Unit end

    -- Joystick (mobile) ou ZQSD/WASD (PC) via MoveDirection
    local move = hum.MoveDirection
    local forward = move:Dot(flatLook)
    local side = move:Dot(flatRight)

    local dir = look * forward + right * side
    if flyUp or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        dir = dir + Vector3.new(0, 1, 0)
    end
    if flyDown or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
        dir = dir - Vector3.new(0, 1, 0)
    end

    local target = Vector3.zero
    if dir.Magnitude > 0.05 then
        target = dir.Unit * math.clamp(CONFIG.FlySpeed, 1, 256)
    end

    -- Lissage pour que ce soit fluide
    flyVelocity.Velocity = flyVelocity.Velocity:Lerp(target, math.clamp(dt * 12, 0, 1))

    if flatLook.Magnitude > 0.001 then
        flyGyro.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook)
    end
end

RunService.Stepped:Connect(function()
    if not CONFIG.Noclip then return end
    local char = LocalPlayer.Character
    if not char then return end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            d.CanCollide = false
        end
    end
end)

-- =====================================================================
--  INTERFACE : OUTILS
-- =====================================================================
local function new(className, props, parent)
    local inst = Instance.new(className)
    for key, value in pairs(props) do
        inst[key] = value
    end
    if parent then
        inst.Parent = parent
    end
    return inst
end

local function corner(parent, radius)
    return new("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, parent)
end

local function stroke(parent, color, thickness, transparency)
    return new("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
end

local gui = new("ScreenGui", {
    Name = "GameToolsGui",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 100,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, LocalPlayer:WaitForChild("PlayerGui"))

-- Cercle FOV (centre de l'écran)
local fovCircle = new("Frame", {
    Name = "FovCircle",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.fromOffset(CONFIG.FovRadius * 2, CONFIG.FovRadius * 2),
    BackgroundTransparency = 1,
    Visible = CONFIG.ShowFovCircle,
}, gui)
corner(fovCircle, 9999)
local fovStroke = stroke(fovCircle, Color3.new(1, 1, 1), 2, 0.35)

-- Fenêtre principale
local window = new("Frame", {
    Name = "Window",
    Size = UDim2.fromOffset(310, 350),
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -12, 0.5, 0),
    BackgroundColor3 = THEME.Bg,
    BackgroundTransparency = 0.04,
    Active = true,
}, gui)
corner(window, 12)
stroke(window, Color3.fromRGB(70, 70, 95), 1.5, 0)

local uiScale = new("UIScale", { Scale = 1 }, window)
local function updateScale()
    uiScale.Scale = math.clamp(Camera.ViewportSize.Y / 470, 0.6, 1)
end
updateScale()
Camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

-- En-tête (zone pour déplacer la fenêtre)
local header = new("Frame", {
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = THEME.Panel,
    Active = true,
}, window)
corner(header, 12)

new("TextLabel", {
    Size = UDim2.new(1, -60, 1, 0),
    Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1,
    Text = "GAME TOOLS",
    TextColor3 = THEME.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local minimizeButton = new("TextButton", {
    Size = UDim2.fromOffset(30, 26),
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -8, 0.5, 0),
    BackgroundColor3 = THEME.Item,
    Text = "–",
    TextColor3 = THEME.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 18,
}, header)
corner(minimizeButton, 8)

-- Bouton flottant quand la fenêtre est réduite
local floatButton = new("TextButton", {
    Size = UDim2.fromOffset(44, 44),
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -12, 0, 12),
    BackgroundColor3 = THEME.Accent,
    Text = "☰",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 22,
    Visible = false,
}, gui)
corner(floatButton, 22)

minimizeButton.Activated:Connect(function()
    window.Visible = false
    floatButton.Visible = true
end)

floatButton.Activated:Connect(function()
    window.Visible = true
    floatButton.Visible = false
end)

-- Déplacement de la fenêtre
do
    local dragging, dragStart, startPos, dragInput = false, nil, nil, nil

    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = window.Position
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput) then
            local delta = input.Position - dragStart
            window.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            dragInput = nil
        end
    end)
end

-- Onglets
local tabBar = new("Frame", {
    Size = UDim2.new(1, -16, 0, 32),
    Position = UDim2.new(0, 8, 0, 46),
    BackgroundTransparency = 1,
}, window)
new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, tabBar)

local pagesHolder = new("Frame", {
    Size = UDim2.new(1, -16, 1, -90),
    Position = UDim2.new(0, 8, 0, 84),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
}, window)

local tabs = {}
local tabCount = 3

local function selectTab(name)
    for tabName, tab in pairs(tabs) do
        local active = tabName == name
        tab.page.Visible = active
        tab.button.BackgroundColor3 = active and THEME.Accent or THEME.Item
        tab.button.TextColor3 = active and Color3.new(1, 1, 1) or THEME.Sub
    end
end

local function makeTab(name, order)
    local button = new("TextButton", {
        Size = UDim2.new(1 / tabCount, -6 * (tabCount - 1) / tabCount, 1, 0),
        BackgroundColor3 = THEME.Item,
        Text = name,
        TextColor3 = THEME.Sub,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        LayoutOrder = order,
    }, tabBar)
    corner(button, 8)

    local page = new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = THEME.Accent,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    }, pagesHolder)
    new("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, page)
    new("UIPadding", {
        PaddingRight = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 8),
    }, page)

    tabs[name] = { button = button, page = page }
    button.Activated:Connect(function()
        selectTab(name)
    end)
    return page
end

-- ----- Composants -----
local function makeSection(page, text)
    return new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = string.upper(text),
        TextColor3 = THEME.Sub,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = #page:GetChildren(),
    }, page)
end

local function makeLabel(page, text)
    return new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = THEME.Sub,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = #page:GetChildren(),
    }, page)
end

local function makeToggle(page, text, default, callback)
    local row = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = THEME.Item,
        AutoButtonColor = false,
        Text = "",
        LayoutOrder = #page:GetChildren(),
    }, page)
    corner(row, 8)

    new("TextLabel", {
        Size = UDim2.new(1, -70, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local pill = new("Frame", {
        Size = UDim2.fromOffset(44, 22),
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        BackgroundColor3 = THEME.Off,
    }, row)
    corner(pill, 11)

    local knob = new("Frame", {
        Size = UDim2.fromOffset(18, 18),
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 2, 0.5, 0),
        BackgroundColor3 = Color3.new(1, 1, 1),
    }, pill)
    corner(knob, 9)

    local state = default
    local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad)

    local function refresh(animate)
        local knobPos = UDim2.new(0, state and 24 or 2, 0.5, 0)
        local pillColor = state and THEME.On or THEME.Off
        if animate then
            TweenService:Create(knob, tweenInfo, { Position = knobPos }):Play()
            TweenService:Create(pill, tweenInfo, { BackgroundColor3 = pillColor }):Play()
        else
            knob.Position = knobPos
            pill.BackgroundColor3 = pillColor
        end
    end

    local object = {}

    function object.set(value, silent)
        state = value
        refresh(true)
        if not silent then
            callback(state)
        end
    end

    function object.get()
        return state
    end

    row.Activated:Connect(function()
        object.set(not state)
    end)

    refresh(false)
    return object
end

local function makeSlider(page, text, minValue, maxValue, default, callback, suffix)
    suffix = suffix or ""

    local holder = new("Frame", {
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundColor3 = THEME.Item,
        Active = true,
        LayoutOrder = #page:GetChildren(),
    }, page)
    corner(holder, 8)

    new("TextLabel", {
        Size = UDim2.new(0.65, 0, 0, 18),
        Position = UDim2.new(0, 10, 0, 6),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, holder)

    local valueLabel = new("TextLabel", {
        Size = UDim2.new(0.35, -10, 0, 18),
        Position = UDim2.new(0.65, 0, 0, 6),
        BackgroundTransparency = 1,
        TextColor3 = THEME.Accent,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, holder)

    local bar = new("Frame", {
        Size = UDim2.new(1, -28, 0, 6),
        Position = UDim2.new(0, 14, 0, 35),
        BackgroundColor3 = THEME.Off,
    }, holder)
    corner(bar, 3)

    local fill = new("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = THEME.Accent,
    }, bar)
    corner(fill, 3)

    local knob = new("Frame", {
        Size = UDim2.fromOffset(20, 20),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = Color3.new(1, 1, 1),
    }, bar)
    corner(knob, 10)

    local object = {}

    function object.set(value, silent)
        value = math.clamp(math.floor(value + 0.5), minValue, maxValue)
        local alpha = (value - minValue) / (maxValue - minValue)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueLabel.Text = tostring(value) .. suffix
        if not silent then
            callback(value)
        end
    end

    local dragging = false
    local dragInput = nil

    local function fromInput(input)
        local alpha = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        object.set(minValue + alpha * (maxValue - minValue))
    end

    holder.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragInput = input
            page.ScrollingEnabled = false -- évite que la page défile pendant qu'on règle
            fromInput(input)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput) then
            fromInput(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
            dragging = false
            dragInput = nil
            page.ScrollingEnabled = true
        end
    end)

    object.set(default, true)
    return object
end

-- Choix qui défile au clic : options = { {valeur, "Texte"}, ... }
local function makeChoice(page, text, options, defaultValue, callback)
    local row = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = THEME.Item,
        AutoButtonColor = false,
        Text = "",
        LayoutOrder = #page:GetChildren(),
    }, page)
    corner(row, 8)

    new("TextLabel", {
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = THEME.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local valueLabel = new("TextLabel", {
        Size = UDim2.new(0.5, -10, 1, 0),
        Position = UDim2.new(0.5, 0, 0, 0),
        BackgroundTransparency = 1,
        TextColor3 = THEME.Accent,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, row)

    local index = 1
    for i, option in ipairs(options) do
        if option[1] == defaultValue then
            index = i
        end
    end

    local function refresh()
        valueLabel.Text = options[index][2] .. "  ▸"
    end

    row.Activated:Connect(function()
        index = index % #options + 1
        refresh()
        callback(options[index][1], index)
    end)

    refresh()
end

local function makeButtonRow(page, buttons)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundTransparency = 1,
        LayoutOrder = #page:GetChildren(),
    }, page)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, row)

    local n = #buttons
    for i, info in ipairs(buttons) do
        local b = new("TextButton", {
            Size = UDim2.new(1 / n, -6 * (n - 1) / n, 1, 0),
            BackgroundColor3 = THEME.Accent,
            Text = info[1],
            TextColor3 = Color3.new(1, 1, 1),
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            LayoutOrder = i,
        }, row)
        corner(b, 8)
        b.Activated:Connect(info[2])
    end
end

-- =====================================================================
--  PAGE AIM
-- =====================================================================
local aimPage = makeTab("AIM", 1)

local aimToggle = makeToggle(aimPage, "Aim assist", CONFIG.AimEnabled, function(value)
    CONFIG.AimEnabled = value
end)

local statusLabel = new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 28),
    BackgroundColor3 = THEME.Panel,
    Text = aimStatus,
    TextColor3 = THEME.Sub,
    Font = Enum.Font.GothamMedium,
    TextSize = 13,
    LayoutOrder = #aimPage:GetChildren(),
}, aimPage)
corner(statusLabel, 8)

makeSlider(aimPage, "Puissance de l'aide", 0, 100, CONFIG.AssistPower, function(value)
    CONFIG.AssistPower = value
end)

makeSlider(aimPage, "Taille du cercle FOV", 40, 500, CONFIG.FovRadius, function(value)
    CONFIG.FovRadius = value
    fovCircle.Size = UDim2.fromOffset(value * 2, value * 2)
end, " px")

makeToggle(aimPage, "Afficher le cercle", CONFIG.ShowFovCircle, function(value)
    CONFIG.ShowFovCircle = value
    fovCircle.Visible = value
end)

makeSection(aimPage, "Ciblage")

makeChoice(aimPage, "Cibles", {
    { "Both", "Joueurs + NPC" },
    { "Players", "Joueurs" },
    { "NPC", "NPC" },
}, CONFIG.AimTargets, function(value)
    CONFIG.AimTargets = value
end)

makeChoice(aimPage, "Zone visée", {
    { "Head", "Tête" },
    { "Torso", "Torse" },
    { "Root", "Corps" },
}, CONFIG.AimPart, function(value)
    CONFIG.AimPart = value
end)

makeSlider(aimPage, "Distance max", 20, 500, CONFIG.MaxDistance, function(value)
    CONFIG.MaxDistance = value
end, " studs")

makeToggle(aimPage, "Ignorer les alliés", CONFIG.TeamCheck, function(value)
    CONFIG.TeamCheck = value
end)

makeToggle(aimPage, "Ignorer à travers les murs", CONFIG.WallCheck, function(value)
    CONFIG.WallCheck = value
end)

-- =====================================================================
--  PAGE VISUEL
-- =====================================================================
local visualPage = makeTab("VISUEL", 2)

makeToggle(visualPage, "Highlight (ESP)", CONFIG.EspEnabled, function(value)
    CONFIG.EspEnabled = value
    syncEsp()
end)

makeChoice(visualPage, "Cibles", {
    { "Both", "Joueurs + NPC" },
    { "Players", "Joueurs" },
    { "NPC", "NPC" },
}, CONFIG.EspTargets, function(value)
    CONFIG.EspTargets = value
    syncEsp()
end)

makeToggle(visualPage, "Inclure les alliés", CONFIG.EspIncludeAllies, function(value)
    CONFIG.EspIncludeAllies = value
    syncEsp()
end)

do
    local colorOptions = {}
    for i, c in ipairs(COLORS) do
        colorOptions[i] = { i, c[1] }
    end
    makeChoice(visualPage, "Couleur", colorOptions, CONFIG.EspColorIndex, function(value)
        CONFIG.EspColorIndex = value
        syncEsp()
    end)
end

makeSlider(visualPage, "Transparence", 0, 100, CONFIG.EspFillTransparency, function(value)
    CONFIG.EspFillTransparency = value
    syncEsp()
end, " %")

makeLabel(visualPage, "Les alliés apparaissent en vert. Roblox limite à environ 31 highlights visibles en même temps.")

-- =====================================================================
--  PAGE FLY
-- =====================================================================
local flyPage = makeTab("FLY", 3)

local flyButtonsFrame
local flyToggle

setFly = function(state)
    if state then
        if not startFly() then
            state = false
        end
    else
        stopFly()
    end
    if flyToggle then
        flyToggle.set(state, true)
    end
    if flyButtonsFrame then
        flyButtonsFrame.Visible = state
    end
end

if canFly then
    flyToggle = makeToggle(flyPage, "Fly", false, function(value)
        setFly(value)
    end)

    local speedSlider = makeSlider(flyPage, "Vitesse", 1, 256, CONFIG.FlySpeed, function(value)
        CONFIG.FlySpeed = value
    end)

    makeButtonRow(flyPage, {
        { "Lent", function() speedSlider.set(15) end },
        { "Moyen", function() speedSlider.set(90) end },
        { "Rapide", function() speedSlider.set(250) end },
    })

    makeToggle(flyPage, "Noclip (traverser les murs)", CONFIG.Noclip, function(value)
        CONFIG.Noclip = value
    end)

    makeLabel(flyPage, "Mobile : joystick pour avancer là où ta caméra regarde, boutons ▲ ▼ pour monter/descendre. PC : Espace monte, Ctrl gauche descend, F active le fly.")

    -- Boutons monter / descendre (mobile), visibles seulement en vol
    flyButtonsFrame = new("Frame", {
        Size = UDim2.fromOffset(60, 130),
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -16, 1, -90),
        BackgroundTransparency = 1,
        Visible = false,
    }, gui)

    local function makeHoldButton(text, y, onChange)
        local b = new("TextButton", {
            Size = UDim2.fromOffset(60, 60),
            Position = UDim2.new(0, 0, 0, y),
            BackgroundColor3 = THEME.Accent,
            BackgroundTransparency = 0.15,
            Text = text,
            TextColor3 = Color3.new(1, 1, 1),
            Font = Enum.Font.GothamBold,
            TextSize = 26,
            AutoButtonColor = true,
        }, flyButtonsFrame)
        corner(b, 30)

        b.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                onChange(true)
            end
        end)
        b.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                onChange(false)
            end
        end)
    end

    makeHoldButton("▲", 0, function(v) flyUp = v end)
    makeHoldButton("▼", 70, function(v) flyDown = v end)
else
    makeLabel(flyPage, "Le fly est réservé à l'owner du jeu.")
end

-- =====================================================================
--  BOUCLE PRINCIPALE + TOUCHES
-- =====================================================================
RunService:BindToRenderStep("GameToolsStep", Enum.RenderPriority.Camera.Value + 1, function(dt)
    Camera = workspace.CurrentCamera
    updateFly(dt)
    updateAim(dt)

    if statusLabel.Text ~= aimStatus then
        statusLabel.Text = aimStatus
        statusLabel.TextColor3 = aimLocked and THEME.On or THEME.Sub
    end
    fovStroke.Color = aimLocked and THEME.On or Color3.new(1, 1, 1)
end)

LocalPlayer.CharacterAdded:Connect(function()
    flyUp, flyDown = false, false
    setFly(false)
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == CONFIG.AimKey then
        aimToggle.set(not aimToggle.get())
    elseif input.KeyCode == CONFIG.FlyKey and flyToggle then
        flyToggle.set(not flyToggle.get())
    end
end)

selectTab("AIM")

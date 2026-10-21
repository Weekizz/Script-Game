--[[
    Game Tools - LocalScript
    À mettre dans StarterPlayer > StarterPlayerScripts de TON jeu.

    - Aim assist : puissance 0 (aucune aide) à 100 (lock total)
    - Cercle FOV : affichable / masquable, taille réglable
    - Fly (réservé à l'owner) : vitesse de 1 à 256
    Tout se règle avec des sliders dans le menu (bouton MENU en haut à droite).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ====== REGLAGES ======
local CONFIG = {
    -- Aim assist
    AimEnabled = false,
    AssistPower = 30,            -- 0 à 100
    FovRadius = 180,             -- rayon du cercle en pixels
    ShowFovCircle = true,
    MaxDistance = 150,           -- distance max en studs
    AimPart = "HumanoidRootPart",-- "Head", "UpperTorso", "HumanoidRootPart"
    TeamCheck = true,
    WallCheck = true,
    AimKey = Enum.KeyCode.Q,     -- touche PC

    -- Fly (owner)
    FlySpeed = 60,               -- 1 à 256
    FlyKey = Enum.KeyCode.F,     -- touche PC
}

-- Qui peut utiliser le fly (en plus du créateur du jeu)
local OWNER_NAMES = { "kts_knigth", "REMPLACE_PAR_LE_NOM_DU_COOWNER" } -- noms en minuscules
local OWNER_IDS = {} -- ajoute ici les UserId autorisés, ex. {123456789}

local function isOwner(player)
    if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
        return true
    end
    if game.CreatorType == Enum.CreatorType.Group then
        local ok, rank = pcall(function()
            return player:GetRankInGroup(game.CreatorId)
        end)
        if ok and rank == 255 then return true end
    end
    if table.find(OWNER_IDS, player.UserId) then return true end
    if table.find(OWNER_NAMES, string.lower(player.Name)) then return true end
    return false
end

local canFly = isOwner(LocalPlayer)

-- Le panneau complet est réservé au créateur et aux co-owners listés ci-dessus.
-- Pour un vrai contrôle de sécurité, les actions sensibles doivent aussi être validées côté serveur.
if not canFly then
    return
end

-- ====== HIGHLIGHT ======
local highlightAll = false
local selectedPlayer = nil
local highlights = {}
local fillColor = Color3.fromRGB(255, 0, 0)
local outlineColor = Color3.fromRGB(255, 255, 255)
local fillTransparency = 0.5

local function applyHighlight(player)
    if not player or player == LocalPlayer then return end
    local character = player.Character
    if not character then return end

    local highlight = highlights[player]
    if not highlight or not highlight.Parent then
        highlight = Instance.new("Highlight")
        highlight.Name = "OwnerPanelHighlight"
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlights[player] = highlight
    end

    highlight.FillColor = fillColor
    highlight.OutlineColor = outlineColor
    highlight.FillTransparency = fillTransparency
    highlight.Adornee = character
    highlight.Parent = character
end

local function removeHighlight(player)
    local highlight = highlights[player]
    if highlight then
        highlight:Destroy()
        highlights[player] = nil
    end
end

local function refreshHighlights()
    for player in pairs(highlights) do
        if player.Parent == Players then
            applyHighlight(player)
        else
            removeHighlight(player)
        end
    end
end

local function trackHighlightPlayer(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.5)
        if highlightAll or highlights[player] then
            applyHighlight(player)
        end
    end)
end

for _, player in ipairs(Players:GetPlayers()) do
    trackHighlightPlayer(player)
end

Players.PlayerAdded:Connect(function(player)
    trackHighlightPlayer(player)
    if highlightAll then
        task.wait(0.5)
        applyHighlight(player)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    removeHighlight(player)
    if selectedPlayer == player then selectedPlayer = nil end
end)

-- ====== AIM : CIBLAGE ======
local function isEnemy(player)
    if player == LocalPlayer then return false end
    if CONFIG.TeamCheck and LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team then
        return false
    end
    return true
end

local function isVisible(part, character)
    if not CONFIG.WallCheck then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character }
    local origin = Camera.CFrame.Position
    local result = workspace:Raycast(origin, part.Position - origin, params)
    return result == nil or result.Instance:IsDescendantOf(character)
end

local function getBestTarget()
    local viewport = Camera.ViewportSize
    local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
    local best, bestDist = nil, CONFIG.FovRadius

    for _, player in ipairs(Players:GetPlayers()) do
        if isEnemy(player) then
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local part = char and char:FindFirstChild(CONFIG.AimPart)

            if hum and hum.Health > 0 and part then
                local worldDist = (part.Position - Camera.CFrame.Position).Magnitude
                if worldDist <= CONFIG.MaxDistance then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                    if onScreen then
                        local d = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                        if d < bestDist and isVisible(part, char) then
                            best, bestDist = part, d
                        end
                    end
                end
            end
        end
    end

    return best
end

local function updateAim(dt)
    if not CONFIG.AimEnabled then return end

    local power = math.clamp(CONFIG.AssistPower, 0, 100)
    if power <= 0 then return end -- 0 = aucune aide

    local target = getBestTarget()
    if not target then return end

    local goal = CFrame.new(Camera.CFrame.Position, target.Position)

    if power >= 100 then
        Camera.CFrame = goal -- 100 = lock total
        return
    end

    -- 1 à 99 : plus le chiffre est haut, plus la caméra est attirée
    local base = (power / 100) ^ 2
    local alpha = 1 - (1 - base) ^ (dt * 60) -- indépendant des FPS
    Camera.CFrame = Camera.CFrame:Lerp(goal, alpha)
end

-- ====== FLY ======
local flying = false
local flyVelocity, flyGyro
local flyToggle -- défini plus bas (interface)

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

local function updateFly()
    if not flying then return end

    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or not flyVelocity or not flyVelocity.Parent then
        stopFly()
        if flyToggle then flyToggle.set(false, true) end
        return
    end

    local look = Camera.CFrame.LookVector
    local right = Camera.CFrame.RightVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    local flatRight = Vector3.new(right.X, 0, right.Z)
    if flatLook.Magnitude > 0.001 then flatLook = flatLook.Unit end
    if flatRight.Magnitude > 0.001 then flatRight = flatRight.Unit end

    -- Le joystick (mobile) ou ZQSD/WASD (PC) donne MoveDirection
    local move = hum.MoveDirection
    local forward = move:Dot(flatLook)
    local side = move:Dot(flatRight)

    local dir = look * forward + right * side
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        dir = dir + Vector3.new(0, 1, 0)
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
        dir = dir - Vector3.new(0, 1, 0)
    end

    if dir.Magnitude > 0.05 then
        flyVelocity.Velocity = dir.Unit * math.clamp(CONFIG.FlySpeed, 1, 256)
    else
        flyVelocity.Velocity = Vector3.zero
    end

    if flatLook.Magnitude > 0.001 then
        flyGyro.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook)
    end
end

LocalPlayer.CharacterAdded:Connect(function()
    stopFly()
    if flyToggle then flyToggle.set(false, true) end
end)

-- ====== BOUCLE ======
RunService:BindToRenderStep("GameToolsStep", Enum.RenderPriority.Camera.Value + 1, function(dt)
    Camera = workspace.CurrentCamera
    updateFly()
    updateAim(dt)
end)

-- ====== INTERFACE ======
local gui = Instance.new("ScreenGui")
gui.Name = "GameToolsGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Cercle FOV (au centre de l'écran)
local fovCircle = Instance.new("Frame")
fovCircle.Name = "FovCircle"
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
fovCircle.Size = UDim2.fromOffset(CONFIG.FovRadius * 2, CONFIG.FovRadius * 2)
fovCircle.BackgroundTransparency = 1
fovCircle.Visible = CONFIG.ShowFovCircle
fovCircle.Parent = gui

local circleCorner = Instance.new("UICorner")
circleCorner.CornerRadius = UDim.new(1, 0)
circleCorner.Parent = fovCircle

local circleStroke = Instance.new("UIStroke")
circleStroke.Thickness = 2
circleStroke.Color = Color3.fromRGB(255, 255, 255)
circleStroke.Transparency = 0.3
circleStroke.Parent = fovCircle

-- Panneau du menu
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -10, 0, 52)
panel.Size = UDim2.new(0, 220, 0, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
panel.BackgroundTransparency = 0.15
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 8)
panelPadding.PaddingBottom = UDim.new(0, 8)
panelPadding.PaddingLeft = UDim.new(0, 8)
panelPadding.PaddingRight = UDim.new(0, 8)
panelPadding.Parent = panel

local panelLayout = Instance.new("UIListLayout")
panelLayout.Padding = UDim.new(0, 6)
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.Parent = panel

-- Bouton pour ouvrir / fermer le menu
local menuButton = Instance.new("TextButton")
menuButton.Name = "MenuButton"
menuButton.AnchorPoint = Vector2.new(1, 0)
menuButton.Position = UDim2.new(1, -10, 0, 10)
menuButton.Size = UDim2.new(0, 90, 0, 34)
menuButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
menuButton.BackgroundTransparency = 0.1
menuButton.TextColor3 = Color3.fromRGB(255, 255, 255)
menuButton.Font = Enum.Font.GothamBold
menuButton.TextSize = 16
menuButton.Text = "MENU"
menuButton.Parent = gui

local menuCorner = Instance.new("UICorner")
menuCorner.CornerRadius = UDim.new(0, 8)
menuCorner.Parent = menuButton

menuButton.Activated:Connect(function()
    panel.Visible = not panel.Visible
end)

local order = 0
local function nextOrder()
    order = order + 1
    return order
end

local function makeToggle(text, default, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, 32)
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 15
    button.LayoutOrder = nextOrder()
    button.Parent = panel

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    local state = default

    local function refresh()
        button.Text = text .. " : " .. (state and "ON" or "OFF")
        button.BackgroundColor3 = state and Color3.fromRGB(0, 140, 60) or Color3.fromRGB(140, 30, 30)
    end

    local object = {}
    function object.set(value, silent)
        state = value
        refresh()
        if not silent then callback(state) end
    end
    function object.get()
        return state
    end

    button.Activated:Connect(function()
        object.set(not state)
    end)

    refresh()
    return object
end

local function makeSlider(text, minValue, maxValue, default, callback)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 44)
    holder.BackgroundTransparency = 1
    holder.Active = true
    holder.LayoutOrder = nextOrder()
    holder.Parent = panel

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 18)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = holder

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -16, 0, 8)
    track.Position = UDim2.new(0, 8, 0, 30)
    track.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
    track.Parent = holder

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
    fill.Parent = track

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Size = UDim2.new(0, 20, 0, 20)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.Parent = track

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local object = {}

    function object.set(value, silent)
        value = math.clamp(math.floor(value + 0.5), minValue, maxValue)
        local alpha = (value - minValue) / (maxValue - minValue)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        label.Text = text .. " : " .. tostring(value)
        if not silent then callback(value) end
    end

    local dragging = false
    local dragInput = nil

    local function fromInput(input)
        local alpha = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        object.set(minValue + alpha * (maxValue - minValue))
    end

    holder.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragInput = input
            fromInput(input)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput then
            fromInput(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            dragInput = nil
        end
    end)

    object.set(default, true)
    return object
end

-- ----- Highlight -----
makeToggle("Highlight tous les joueurs", false, function(value)
    highlightAll = value
    for _, player in ipairs(Players:GetPlayers()) do
        if value then
            applyHighlight(player)
        else
            removeHighlight(player)
        end
    end
end)

local function makeActionButton(text, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, 32)
    button.BackgroundColor3 = Color3.fromRGB(55, 75, 100)
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 13
    button.Text = text
    button.LayoutOrder = nextOrder()
    button.Parent = panel
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button
    button.Activated:Connect(callback)
    return button
end

local selectedLabel

local function cycleSelectedPlayer()
    local candidates = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then table.insert(candidates, player) end
    end
    table.sort(candidates, function(a, b) return a.Name:lower() < b.Name:lower() end)
    if #candidates == 0 then
        selectedPlayer = nil
        return
    end
    local index = table.find(candidates, selectedPlayer) or 0
    selectedPlayer = candidates[(index % #candidates) + 1]
    selectedLabel.Text = "Cible : " .. selectedPlayer.Name
end

selectedLabel = Instance.new("TextLabel")
selectedLabel.Size = UDim2.new(1, 0, 0, 24)
selectedLabel.BackgroundTransparency = 1
selectedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
selectedLabel.Font = Enum.Font.Gotham
selectedLabel.TextSize = 13
selectedLabel.Text = "Cible : aucune"
selectedLabel.LayoutOrder = nextOrder()
selectedLabel.Parent = panel

makeActionButton("Choisir le joueur suivant", cycleSelectedPlayer)
makeActionButton("Highlight la cible", function()
    if selectedPlayer then applyHighlight(selectedPlayer) end
end)
makeActionButton("Retirer le highlight de la cible", function()
    if selectedPlayer then removeHighlight(selectedPlayer) end
end)
makeActionButton("Tout retirer", function()
    highlightAll = false
    for player in pairs(highlights) do removeHighlight(player) end
end)

makeSlider("Transparence highlight (0-100)", 0, 100, 50, function(value)
    fillTransparency = value / 100
    refreshHighlights()
end)

makeActionButton("Couleur remplissage : rouge/vert/bleu", function()
    if fillColor == Color3.fromRGB(255, 0, 0) then
        fillColor = Color3.fromRGB(0, 255, 0)
    elseif fillColor == Color3.fromRGB(0, 255, 0) then
        fillColor = Color3.fromRGB(0, 120, 255)
    else
        fillColor = Color3.fromRGB(255, 0, 0)
    end
    refreshHighlights()
end)

makeActionButton("Couleur contour : blanc/noir", function()
    outlineColor = (outlineColor == Color3.fromRGB(255, 255, 255))
        and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(255, 255, 255)
    refreshHighlights()
end)

-- ----- Aim assist -----
local aimToggle = makeToggle("AIM", CONFIG.AimEnabled, function(value)
    CONFIG.AimEnabled = value
end)

makeSlider("Puissance aide (0-100)", 0, 100, CONFIG.AssistPower, function(value)
    CONFIG.AssistPower = value
end)

makeSlider("Taille du cercle FOV", 40, 500, CONFIG.FovRadius, function(value)
    CONFIG.FovRadius = value
    fovCircle.Size = UDim2.fromOffset(value * 2, value * 2)
end)

makeToggle("Cercle FOV", CONFIG.ShowFovCircle, function(value)
    CONFIG.ShowFovCircle = value
    fovCircle.Visible = value
end)

-- ----- Fly (owner uniquement) -----
if canFly then
    flyToggle = makeToggle("FLY", false, function(value)
        if value then
            if not startFly() then
                flyToggle.set(false, true)
            end
        else
            stopFly()
        end
    end)

    makeSlider("Vitesse fly (1-256)", 1, 256, CONFIG.FlySpeed, function(value)
        CONFIG.FlySpeed = value
    end)
end

-- ====== TOUCHES PC ======
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == CONFIG.AimKey then
        aimToggle.set(not aimToggle.get())
    elseif input.KeyCode == CONFIG.FlyKey and flyToggle then
        flyToggle.set(not flyToggle.get())
    end
end)

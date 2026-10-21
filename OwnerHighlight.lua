-- Owner / Co-owner Panel : Highlight + Aim Assist + FOV + Fly

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Rayfield est chargé directement depuis son URL publique.
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local CONFIG = {
    AimEnabled = false,
    AssistPower = 30,
    FovRadius = 180,
    ShowFovCircle = true,
    MaxDistance = 150,
    AimPart = "HumanoidRootPart",
    TeamCheck = true,
    WallCheck = true,
    AimKey = Enum.KeyCode.Q,
    FlySpeed = 60,
    FlyKey = Enum.KeyCode.F,
}

-- Accès au Fly : créateur, rang propriétaire du groupe, ou identifiant/nom listé.
local OWNER_NAMES = { "kts_knigth" }
local OWNER_IDS = {}
local function isOwner(player)
    if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then return true end
    if game.CreatorType == Enum.CreatorType.Group then
        local ok, rank = pcall(function() return player:GetRankInGroup(game.CreatorId) end)
        if ok and rank == 255 then return true end
    end
    if table.find(OWNER_IDS, player.UserId) then return true end
    if table.find(OWNER_NAMES, string.lower(player.Name)) then return true end
    return false
end
local canFly = isOwner(LocalPlayer)

-- HIGHLIGHT
local highlights = {}
local highlightAll = false
local fillColor = Color3.fromRGB(255, 0, 0)
local outlineColor = Color3.fromRGB(255, 255, 255)
local fillTransparency = 0.5

local function applyHighlight(player)
    if player == LocalPlayer then return end
    local char = player.Character
    if not char then return end
    local h = highlights[player]
    if not h or not h.Parent then
        h = Instance.new("Highlight")
        h.Name = "OwnerHighlight"
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlights[player] = h
    end
    h.FillColor = fillColor
    h.OutlineColor = outlineColor
    h.FillTransparency = fillTransparency
    h.Adornee = char
    h.Parent = char
end

local function removeHighlight(player)
    local h = highlights[player]
    if h then h:Destroy(); highlights[player] = nil end
end
local function refreshHighlights()
    for player in pairs(highlights) do
        if player.Parent == Players then applyHighlight(player) end
    end
end
local function trackPlayer(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.5)
        if highlightAll or highlights[player] then applyHighlight(player) end
    end)
end
for _, player in ipairs(Players:GetPlayers()) do trackPlayer(player) end
Players.PlayerAdded:Connect(function(player)
    trackPlayer(player)
    if highlightAll then task.wait(1); applyHighlight(player) end
end)
Players.PlayerRemoving:Connect(removeHighlight)

-- AIM ASSIST
local function isEnemy(player)
    if player == LocalPlayer then return false end
    if CONFIG.TeamCheck and LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team then return false end
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
                        if d < bestDist and isVisible(part, char) then best, bestDist = part, d end
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
    if power <= 0 then return end
    local target = getBestTarget()
    if not target then return end
    local goal = CFrame.new(Camera.CFrame.Position, target.Position)
    if power >= 100 then Camera.CFrame = goal; return end
    local base = (power / 100) ^ 2
    local alpha = 1 - (1 - base) ^ (dt * 60)
    Camera.CFrame = Camera.CFrame:Lerp(goal, alpha)
end

-- FOV CIRCLE
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local fovGui = Instance.new("ScreenGui")
fovGui.Name = "OwnerPanelFOV"
fovGui.ResetOnSpawn = false
fovGui.IgnoreGuiInset = true
fovGui.Parent = playerGui
local fovCircle = Instance.new("Frame")
fovCircle.Name = "FovCircle"
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
fovCircle.Size = UDim2.fromOffset(CONFIG.FovRadius * 2, CONFIG.FovRadius * 2)
fovCircle.BackgroundTransparency = 1
fovCircle.Visible = CONFIG.ShowFovCircle
fovCircle.Parent = fovGui
local circleCorner = Instance.new("UICorner")
circleCorner.CornerRadius = UDim.new(1, 0)
circleCorner.Parent = fovCircle
local circleStroke = Instance.new("UIStroke")
circleStroke.Thickness = 2
circleStroke.Color = Color3.fromRGB(255, 255, 255)
circleStroke.Transparency = 0.3
circleStroke.Parent = fovCircle

-- FLY
local flying = false
local flyVelocity, flyGyro
local flyToggle
local function stopFly()
    flying = false
    if flyVelocity then flyVelocity:Destroy(); flyVelocity = nil end
    if flyGyro then flyGyro:Destroy(); flyGyro = nil end
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
        if flyToggle then flyToggle:Set(false) end
        return
    end
    local look = Camera.CFrame.LookVector
    local right = Camera.CFrame.RightVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    local flatRight = Vector3.new(right.X, 0, right.Z)
    if flatLook.Magnitude > 0.001 then flatLook = flatLook.Unit end
    if flatRight.Magnitude > 0.001 then flatRight = flatRight.Unit end
    local move = hum.MoveDirection
    local forward = move:Dot(flatLook)
    local side = move:Dot(flatRight)
    local dir = look * forward + right * side
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0, 1, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.new(0, 1, 0) end
    flyVelocity.Velocity = dir.Magnitude > 0.05 and dir.Unit * math.clamp(CONFIG.FlySpeed, 1, 256) or Vector3.zero
    if flatLook.Magnitude > 0.001 then flyGyro.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook) end
end
LocalPlayer.CharacterAdded:Connect(function()
    stopFly()
    if flyToggle then flyToggle:Set(false) end
end)

-- RAYFIELD PANEL
local Window = Rayfield:CreateWindow({
    Name = "Owner / Co-owner Panel",
    LoadingTitle = "Owner Panel",
    LoadingSubtitle = "Highlight • Aim Assist • Fly",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
})

local HighlightTab = Window:CreateTab("Highlight", 4483362458)
HighlightTab:CreateSection("Joueurs")
HighlightTab:CreateToggle({
    Name = "Highlight tous les joueurs", CurrentValue = false, Flag = "HighlightAll",
    Callback = function(value)
        highlightAll = value
        for _, player in ipairs(Players:GetPlayers()) do
            if value then applyHighlight(player) else removeHighlight(player) end
        end
    end,
})
local function getPlayerNames()
    local names = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then table.insert(names, player.Name) end
    end
    table.sort(names)
    return names
end
local selectedName
local Dropdown = HighlightTab:CreateDropdown({
    Name = "Choisir un joueur", Options = getPlayerNames(), CurrentOption = {},
    MultipleOptions = false, Flag = "SelectedPlayer",
    Callback = function(option) selectedName = typeof(option) == "table" and option[1] or option end,
})
HighlightTab:CreateButton({Name = "Mettre en highlight", Callback = function()
    local target = selectedName and Players:FindFirstChild(selectedName)
    if target then applyHighlight(target) else Rayfield:Notify({Title = "Highlight", Content = "Sélectionne un joueur.", Duration = 3}) end
end})
HighlightTab:CreateButton({Name = "Retirer le highlight ciblé", Callback = function()
    local target = selectedName and Players:FindFirstChild(selectedName)
    if target then removeHighlight(target) end
end})
HighlightTab:CreateButton({Name = "Actualiser la liste", Callback = function() Dropdown:Refresh(getPlayerNames()) end})
HighlightTab:CreateButton({Name = "Tout retirer", Callback = function()
    highlightAll = false
    for player in pairs(highlights) do removeHighlight(player) end
end})
HighlightTab:CreateSection("Apparence")
HighlightTab:CreateColorPicker({Name = "Couleur de remplissage", Color = fillColor, Flag = "FillColor", Callback = function(color)
    fillColor = color; refreshHighlights()
end})
HighlightTab:CreateColorPicker({Name = "Couleur du contour", Color = outlineColor, Flag = "OutlineColor", Callback = function(color)
    outlineColor = color; refreshHighlights()
end})
HighlightTab:CreateSlider({Name = "Transparence du remplissage", Range = {0, 1}, Increment = 0.05, CurrentValue = fillTransparency, Flag = "FillTransparency", Callback = function(value)
    fillTransparency = value; refreshHighlights()
end})

local AimTab = Window:CreateTab("Aim Assist", 4483362458)
AimTab:CreateToggle({Name = "Activer Aim Assist", CurrentValue = CONFIG.AimEnabled, Flag = "AimEnabled", Callback = function(value)
    CONFIG.AimEnabled = value
end})
AimTab:CreateSlider({Name = "Puissance de l'aide", Range = {0, 100}, Increment = 1, CurrentValue = CONFIG.AssistPower, Flag = "AssistPower", Callback = function(value)
    CONFIG.AssistPower = value
end})
AimTab:CreateSlider({Name = "Rayon FOV", Range = {40, 500}, Increment = 5, CurrentValue = CONFIG.FovRadius, Flag = "FovRadius", Callback = function(value)
    CONFIG.FovRadius = value; fovCircle.Size = UDim2.fromOffset(value * 2, value * 2)
end})
AimTab:CreateToggle({Name = "Afficher le cercle FOV", CurrentValue = CONFIG.ShowFovCircle, Flag = "ShowFovCircle", Callback = function(value)
    CONFIG.ShowFovCircle = value; fovCircle.Visible = value
end})
AimTab:CreateSlider({Name = "Distance maximale", Range = {25, 500}, Increment = 5, CurrentValue = CONFIG.MaxDistance, Flag = "MaxDistance", Callback = function(value)
    CONFIG.MaxDistance = value
end})
AimTab:CreateDropdown({Name = "Partie ciblée", Options = {"Head", "UpperTorso", "HumanoidRootPart"}, CurrentOption = {CONFIG.AimPart}, MultipleOptions = false, Flag = "AimPart", Callback = function(option)
    local value = typeof(option) == "table" and option[1] or option
    if value then CONFIG.AimPart = value end
end})
AimTab:CreateToggle({Name = "Ignorer les alliés", CurrentValue = CONFIG.TeamCheck, Flag = "TeamCheck", Callback = function(value)
    CONFIG.TeamCheck = value
end})
AimTab:CreateToggle({Name = "Vérifier les murs", CurrentValue = CONFIG.WallCheck, Flag = "WallCheck", Callback = function(value)
    CONFIG.WallCheck = value
end})

local FlyTab = Window:CreateTab("Fly", 4483362458)
if canFly then
    flyToggle = FlyTab:CreateToggle({Name = "Activer Fly", CurrentValue = false, Flag = "FlyEnabled", Callback = function(value)
        if value then
            if not startFly() then flyToggle:Set(false) end
        else stopFly() end
    end})
    FlyTab:CreateSlider({Name = "Vitesse Fly", Range = {1, 256}, Increment = 1, CurrentValue = CONFIG.FlySpeed, Flag = "FlySpeed", Callback = function(value)
        CONFIG.FlySpeed = value
    end})
    FlyTab:CreateParagraph({Title = "Commandes PC", Content = "F : activer/désactiver Fly. Espace : monter. Ctrl gauche : descendre. Q : activer/désactiver Aim Assist."})
else
    FlyTab:CreateParagraph({Title = "Accès Fly", Content = "Fly est réservé au créateur, au propriétaire du groupe ou aux noms/identifiants définis dans le script."})
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == CONFIG.AimKey then
        CONFIG.AimEnabled = not CONFIG.AimEnabled
        Rayfield:Notify({Title = "Aim Assist", Content = CONFIG.AimEnabled and "Activé" or "Désactivé", Duration = 1.5})
    elseif input.KeyCode == CONFIG.FlyKey and flyToggle then
        flyToggle:Set(not flying)
    end
end)

RunService:BindToRenderStep("OwnerCoOwnerPanelStep", Enum.RenderPriority.Camera.Value + 1, function(dt)
    Camera = workspace.CurrentCamera
    updateFly()
    updateAim(dt)
end)

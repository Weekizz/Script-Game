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

-- ====== INTERFACE RAYFIELD ======
-- Pour Roblox Studio, place une bibliothèque Rayfield compatible dans
-- ReplicatedStorage sous forme de ModuleScript nommé "Rayfield".
-- Le menu et tous ses contrôles sont créés par Rayfield ; seul le cercle FOV
-- reste un indicateur visuel dans le jeu.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local rayfieldModule = ReplicatedStorage:WaitForChild("Rayfield")
local Rayfield = require(rayfieldModule)

-- Aucun ScreenGui personnalisé : toute l'interface de contrôle est créée par Rayfield.
-- Le rayon FOV reste un réglage de ciblage interne, sans cercle graphique séparé.

local Window = Rayfield:CreateWindow({
    Name = "Owner / Co-Owner Panel",
    LoadingTitle = "Panneau d'administration",
    LoadingSubtitle = "Highlight • Aim Assist • Fly",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
})

local HighlightTab = Window:CreateTab("Highlight", 4483362458)
local AimTab = Window:CreateTab("Aim Assist", 4483362458)
local FlyTab = Window:CreateTab("Fly", 4483362458)

-- ----- Highlight -----
HighlightTab:CreateSection("Joueurs")

HighlightTab:CreateToggle({
    Name = "Highlight tous les joueurs",
    CurrentValue = false,
    Flag = "HighlightAll",
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
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

local selectedName = nil
local playerDropdown = HighlightTab:CreateDropdown({
    Name = "Choisir un joueur",
    Options = getPlayerNames(),
    CurrentOption = {},
    MultipleOptions = false,
    Flag = "SelectedHighlightPlayer",
    Callback = function(option)
        selectedName = (type(option) == "table") and option[1] or option
        selectedPlayer = selectedName and Players:FindFirstChild(selectedName) or nil
    end,
})

HighlightTab:CreateButton({
    Name = "Actualiser la liste des joueurs",
    Callback = function()
        playerDropdown:Refresh(getPlayerNames())
        Rayfield:Notify({ Title = "Liste actualisée", Content = "La liste des joueurs a été actualisée.", Duration = 3 })
    end,
})

HighlightTab:CreateButton({
    Name = "Highlight le joueur sélectionné",
    Callback = function()
        if selectedPlayer and selectedPlayer.Parent == Players then
            applyHighlight(selectedPlayer)
        else
            Rayfield:Notify({ Title = "Aucun joueur", Content = "Sélectionne d'abord un joueur.", Duration = 3 })
        end
    end,
})

HighlightTab:CreateButton({
    Name = "Retirer le highlight de la cible",
    Callback = function()
        if selectedPlayer then removeHighlight(selectedPlayer) end
    end,
})

HighlightTab:CreateButton({
    Name = "Tout retirer",
    Callback = function()
        highlightAll = false
        for player in pairs(highlights) do removeHighlight(player) end
    end,
})

HighlightTab:CreateSection("Apparence")
HighlightTab:CreateColorPicker({
    Name = "Couleur de remplissage",
    Color = fillColor,
    Flag = "HighlightFillColor",
    Callback = function(color)
        fillColor = color
        refreshHighlights()
    end,
})
HighlightTab:CreateColorPicker({
    Name = "Couleur du contour",
    Color = outlineColor,
    Flag = "HighlightOutlineColor",
    Callback = function(color)
        outlineColor = color
        refreshHighlights()
    end,
})
HighlightTab:CreateSlider({
    Name = "Transparence du remplissage (%)",
    Range = { 0, 100 },
    Increment = 5,
    CurrentValue = math.floor(fillTransparency * 100),
    Flag = "HighlightTransparency",
    Callback = function(value)
        fillTransparency = value / 100
        refreshHighlights()
    end,
})

-- ----- Aim Assist -----
AimTab:CreateSection("Assistance de visée")
AimTab:CreateToggle({
    Name = "Activer Aim Assist",
    CurrentValue = CONFIG.AimEnabled,
    Flag = "AimEnabled",
    Callback = function(value)
        CONFIG.AimEnabled = value
    end,
})
AimTab:CreateSlider({
    Name = "Puissance aide (0-100)",
    Range = { 0, 100 },
    Increment = 5,
    CurrentValue = CONFIG.AssistPower,
    Flag = "AimPower",
    Callback = function(value)
        CONFIG.AssistPower = value
    end,
})
AimTab:CreateSlider({
    Name = "Rayon de ciblage FOV",
    Range = { 40, 500 },
    Increment = 10,
    CurrentValue = CONFIG.FovRadius,
    Flag = "FovRadius",
    Callback = function(value)
        CONFIG.FovRadius = value
    end,
})

-- ----- Fly -----
FlyTab:CreateSection("Déplacement")
FlyTab:CreateToggle({
    Name = "Activer Fly",
    CurrentValue = false,
    Flag = "FlyEnabled",
    Callback = function(value)
        if value then
            if not startFly() then
                Rayfield:Notify({ Title = "Fly impossible", Content = "Ton personnage n'est pas encore chargé.", Duration = 3 })
            end
        else
            stopFly()
        end
    end,
})
FlyTab:CreateSlider({
    Name = "Vitesse Fly (1-256)",
    Range = { 1, 256 },
    Increment = 1,
    CurrentValue = CONFIG.FlySpeed,
    Flag = "FlySpeed",
    Callback = function(value)
        CONFIG.FlySpeed = value
    end,
})

Players.PlayerAdded:Connect(function()
    task.wait(0.5)
    pcall(function() playerDropdown:Refresh(getPlayerNames()) end)
end)
Players.PlayerRemoving:Connect(function()
    task.wait(0.1)
    pcall(function() playerDropdown:Refresh(getPlayerNames()) end)
end)

Rayfield:Notify({
    Title = "Panneau chargé",
    Content = "Les outils sont disponibles dans les onglets Highlight, Aim Assist et Fly.",
    Duration = 4,
})

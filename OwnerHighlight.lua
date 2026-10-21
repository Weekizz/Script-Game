--[[
    Highlight Panel - LocalScript
]]

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ====== CHARGEMENT RAYFIELD ======
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

-- ====== LOGIQUE HIGHLIGHT ======
local highlights = {}       -- table : joueur -> Highlight
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
    if h then
        h:Destroy()
        highlights[player] = nil
    end
end

local function refreshAll()
    for player, _ in pairs(highlights) do
        applyHighlight(player)
    end
end

-- Re-applique le highlight quand un joueur respawn
local function trackPlayer(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.5)
        if highlightAll or highlights[player] then
            applyHighlight(player)
        end
    end)
end

for _, p in ipairs(Players:GetPlayers()) do
    trackPlayer(p)
end

Players.PlayerAdded:Connect(function(p)
    trackPlayer(p)
    if highlightAll then
        task.wait(1)
        applyHighlight(p)
    end
end)

Players.PlayerRemoving:Connect(removeHighlight)

-- ====== INTERFACE RAYFIELD ======
local Window = Rayfield:CreateWindow({
    Name = "Highlight Panel",
    LoadingTitle = "Owner Highlight",
    LoadingSubtitle = "par KTS_KNIGTH",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
})

local Tab = Window:CreateTab("Highlight", 4483362458)

Tab:CreateSection("Tous les joueurs")

Tab:CreateToggle({
    Name = "Highlight tous les joueurs",
    CurrentValue = false,
    Flag = "HighlightAll",
    Callback = function(value)
        highlightAll = value
        for _, p in ipairs(Players:GetPlayers()) do
            if value then
                applyHighlight(p)
            else
                removeHighlight(p)
            end
        end
    end,
})

Tab:CreateSection("Joueur ciblé")

local function getPlayerNames()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            table.insert(names, p.Name)
        end
    end
    return names
end

local selectedName = nil

local Dropdown = Tab:CreateDropdown({
    Name = "Choisir un joueur",
    Options = getPlayerNames(),
    CurrentOption = {},
    MultipleOptions = false,
    Flag = "SelectedPlayer",
    Callback = function(option)
        selectedName = option[1]
    end,
})

Tab:CreateButton({
    Name = "Mettre en highlight",
    Callback = function()
        local target = selectedName and Players:FindFirstChild(selectedName)
        if target then
            applyHighlight(target)
        else
            Rayfield:Notify({ Title = "Erreur", Content = "Aucun joueur sélectionné.", Duration = 3 })
        end
    end,
})

Tab:CreateButton({
    Name = "Retirer le highlight",
    Callback = function()
        local target = selectedName and Players:FindFirstChild(selectedName)
        if target then
            removeHighlight(target)
        end
    end,
})

Tab:CreateButton({
    Name = "Actualiser la liste des joueurs",
    Callback = function()
        Dropdown:Refresh(getPlayerNames())
    end,
})

Tab:CreateButton({
    Name = "Tout retirer",
    Callback = function()
        for p, _ in pairs(highlights) do
            removeHighlight(p)
        end
    end,
})

Tab:CreateSection("Apparence")

Tab:CreateColorPicker({
    Name = "Couleur de remplissage",
    Color = fillColor,
    Flag = "FillColor",
    Callback = function(color)
        fillColor = color
        refreshAll()
    end,
})

Tab:CreateColorPicker({
    Name = "Couleur du contour",
    Color = outlineColor,
    Flag = "OutlineColor",
    Callback = function(color)
        outlineColor = color
        refreshAll()
    end,
})

Tab:CreateSlider({
    Name = "Transparence du remplissage",
    Range = { 0, 1 },
    Increment = 0.05,
    CurrentValue = fillTransparency,
    Flag = "FillTransparency",
    Callback = function(value)
        fillTransparency = value
        refreshAll()
    end,
})

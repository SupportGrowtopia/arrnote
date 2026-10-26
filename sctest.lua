--[[
=====================================================================
  ViolenceDistrict_Fluent.lua (v3.4 - Flat 1-Color Low Mode Fix)
  Executor : Xeno / Compatible Luau Executors
  Minimize : RightShift
=====================================================================
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local genv = (type(getgenv) == "function" and getgenv()) or _G
if genv.MAG_VD and type(genv.MAG_VD.destroy) == "function" then
    pcall(genv.MAG_VD.destroy)
end
if genv.VD_ASC and type(genv.VD_ASC.destroy) == "function" then
    pcall(genv.VD_ASC.destroy)
end

------------------------------------------------------------------
-- LOAD FLUENT UI LIBRARY
------------------------------------------------------------------
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Options = Fluent.Options

------------------------------------------------------------------
-- SERVICES & STATE
------------------------------------------------------------------
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UIS               = game:GetService("UserInputService")
local Lighting          = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local LP                = Players.LocalPlayer

local cref = (type(cloneref) == "function") and cloneref or function(x) return x end
local VIM = nil
pcall(function() VIM = cref(game:GetService("VirtualInputManager")) end)

local alive = true
local conns = {}
local function track(c)
    conns[#conns + 1] = c
    return c
end

local S = {
    esp = {
        killer = true,
        survivor = true,
        pallets = true,
        gens = true,
        pumpkins = true,
        hideDone = true,
        fill = true,
        maxDist = 0,
        palletDist = 150
    },
    cross = {
        on = true,
        dot = true,
        size = 8,
        gap = 4,
        thick = 2,
        color = "Green"
    },
    move = { on = false, mode = "WalkSpeed", ws = 24, cf = 10 },
    vis  = {
        full = false,
        bright = 2,
        noDark = true,
        lowMode = false,
        colorScheme = "Original", -- Original, SlateGrey, DarkGrey, LightGrey
        disableBones = true
    },
    aim  = { on = false, fov = 250, dist = 150, smooth = 0.5, part = "HumanoidRootPart", wall = true },
}

local SKC = { on = true, input = "Space", offset = 115, lead = 0.03, learn = true }
local INPUT_LIST = { "Space", "Mouse", "E", "F" }

-- Warna ESP:
-- 1. Killer (Merah) | 2. Survivor (Hijau) | 3. Pallet (Ungu) | 4. Generator (Kuning) | 5. Labu (Cyan)
local COL = {
    killer   = Color3.fromRGB(255, 45, 45),
    survivor = Color3.fromRGB(50, 255, 90),
    pallet   = Color3.fromRGB(190, 80, 255),
    gen      = Color3.fromRGB(255, 230, 40),
    pumpkin  = Color3.fromRGB(0, 255, 255),
}

local CROSS_COLS = {
    Green  = Color3.fromRGB(0, 255, 120),
    Cyan   = Color3.fromRGB(0, 255, 255),
    Red    = Color3.fromRGB(255, 50, 50),
    Yellow = Color3.fromRGB(255, 230, 50),
    White  = Color3.fromRGB(255, 255, 255),
}

local FLAT_PALETTE = {
    SlateGrey = Color3.fromRGB(115, 120, 130),
    DarkGrey  = Color3.fromRGB(65, 68, 75),
    LightGrey = Color3.fromRGB(175, 180, 188),
}

------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------
local function hasKeyword(s, list)
    s = string.lower(tostring(s))
    for _, k in ipairs(list) do
        if s:find(k, 1, true) then return true end
    end
    return false
end

local function inList(v, list)
    for _, x in ipairs(list) do
        if x == v then return true end
    end
    return false
end

local function getRoot()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart"), c
end

local function posOf(inst)
    local ok, p = pcall(function()
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("Model") then return inst:GetPivot().Position end
        return nil
    end)
    if ok then return p end
    return nil
end

local function mount(inst)
    local cands = {}
    if type(gethui) == "function" then
        cands[#cands + 1] = function() return gethui() end
    end
    cands[#cands + 1] = function() return game:GetService("CoreGui") end
    cands[#cands + 1] = function() return LP:WaitForChild("PlayerGui") end
    for _, f in ipairs(cands) do
        local ok, p = pcall(f)
        if ok and p then
            local ok2 = pcall(function() inst.Parent = p end)
            if ok2 and inst.Parent then return true end
        end
    end
    return false
end

local function roleOf(plr)
    if not plr then return nil end
    local char = plr.Character
    if char then
        if CollectionService:HasTag(char, "Killer") then return "Killer" end
        if CollectionService:HasTag(char, "Survivor") then return "Survivor" end
    end
    if CollectionService:HasTag(plr, "Killer") then return "Killer" end
    if CollectionService:HasTag(plr, "Survivor") then return "Survivor" end

    local t = plr.Team
    if t then
        if t.Name == "Killer" then return "Killer" end
        if t.Name == "Survivors" or t.Name == "Survivor" then return "Survivor" end
    end

    if plr:GetAttribute("RoundSurvivor") == true then return "Survivor" end
    return nil
end

------------------------------------------------------------------
-- CROSSHAIR OVERLAY
------------------------------------------------------------------
local crossGui = Instance.new("ScreenGui")
crossGui.Name = "MAG_VD_Crosshair"
crossGui.IgnoreGuiInset = true
crossGui.ResetOnSpawn = false
crossGui.DisplayOrder = 999
mount(crossGui)

local crossRoot = Instance.new("Frame")
crossRoot.Name = "Center"
crossRoot.AnchorPoint = Vector2.new(0.5, 0.5)
crossRoot.Position = UDim2.new(0.5, 0, 0.5, 0)
crossRoot.Size = UDim2.new(0, 0, 0, 0)
crossRoot.BackgroundTransparency = 1
crossRoot.Parent = crossGui

local function mkCrossBar(name)
    local f = Instance.new("Frame")
    f.Name = name
    f.BorderSizePixel = 0
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    local st = Instance.new("UIStroke")
    st.Color = Color3.new(0, 0, 0)
    st.Thickness = 1
    st.Transparency = 0.35
    st.Parent = f
    f.Parent = crossRoot
    return f
end

local crTop   = mkCrossBar("Top")
local crBot   = mkCrossBar("Bottom")
local crLeft  = mkCrossBar("Left")
local crRight = mkCrossBar("Right")
local crDot   = mkCrossBar("Dot")

local function updateCrosshair()
    crossRoot.Visible = S.cross.on
    if not S.cross.on then return end

    local col = CROSS_COLS[S.cross.color] or CROSS_COLS.Green
    local sz  = S.cross.size
    local gap = S.cross.gap
    local th  = S.cross.thick
    local off = gap + (sz / 2)

    crTop.BackgroundColor3   = col
    crBot.BackgroundColor3   = col
    crLeft.BackgroundColor3  = col
    crRight.BackgroundColor3 = col
    crDot.BackgroundColor3   = col

    crTop.Size     = UDim2.new(0, th, 0, sz)
    crTop.Position = UDim2.new(0, 0, 0, -off)

    crBot.Size     = UDim2.new(0, th, 0, sz)
    crBot.Position = UDim2.new(0, 0, 0, off)

    crLeft.Size     = UDim2.new(0, sz, 0, th)
    crLeft.Position = UDim2.new(0, -off, 0, 0)

    crRight.Size     = UDim2.new(0, sz, 0, th)
    crRight.Position = UDim2.new(0, off, 0, 0)

    crDot.Visible  = S.cross.dot
    crDot.Size     = UDim2.new(0, th, 0, th)
    crDot.Position = UDim2.new(0, 0, 0, 0)
end

updateCrosshair()

------------------------------------------------------------------
-- ESP SYSTEM
------------------------------------------------------------------
local espFolder = Instance.new("Folder")
espFolder.Name = "MAG_VD_ESP"
mount(espFolder)

local function makeLabel(adornee, color, size, offsetY)
    local bb = Instance.new("BillboardGui")
    bb.Name = "MAG_VD_BB"
    bb.Adornee = adornee
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.Size = UDim2.new(0, 140, 0, 15)
    bb.StudsOffset = Vector3.new(0, offsetY or 2.5, 0)
    bb.MaxDistance = 1e9
    local t = Instance.new("TextLabel")
    t.Size = UDim2.new(1, 0, 1, 0)
    t.BackgroundTransparency = 1
    t.Font = Enum.Font.GothamBold
    t.TextSize = size or 11
    t.TextColor3 = color
    t.TextStrokeTransparency = 0.35
    t.TextStrokeColor3 = Color3.new(0, 0, 0)
    t.Parent = bb
    bb.Parent = espFolder
    return bb, t
end

local function makeHighlight(adornee, color)
    local hl = Instance.new("Highlight")
    hl.Adornee = adornee
    hl.FillColor = color
    hl.OutlineColor = color
    hl.FillTransparency = S.esp.fill and 0.65 or 1
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = espFolder
    return hl
end

local function destroyEntry(e)
    if not e then return end
    if e.hl then pcall(function() e.hl:Destroy() end) end
    if e.bb then pcall(function() e.bb:Destroy() end) end
end

-- 1 & 2: Killer & Survivor ESP
local pEsp = {}

local function clearPlayersESP()
    for _, e in pairs(pEsp) do destroyEntry(e) end
    pEsp = {}
end

local function updatePlayersESP()
    if not (S.esp.killer or S.esp.survivor) then
        if next(pEsp) ~= nil then clearPlayersESP() end
        return
    end
    local root = getRoot()
    local seen = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local role = roleOf(plr)
            local wanted = (role == "Killer" and S.esp.killer) or (role == "Survivor" and S.esp.survivor)
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if wanted and char and hrp then
                local dist = root and (root.Position - hrp.Position).Magnitude or 0
                if S.esp.maxDist <= 0 or dist <= S.esp.maxDist then
                    seen[plr] = true
                    local col = (role == "Killer") and COL.killer or COL.survivor
                    local e = pEsp[plr]
                    if not e or e.char ~= char or not e.bb.Parent or not e.hl.Parent then
                        destroyEntry(e)
                        e = { char = char }
                        e.hl = makeHighlight(char, col)
                        e.bb, e.lbl = makeLabel(hrp, col, 11, 3.2)
                        pEsp[plr] = e
                    end
                    e.hl.FillColor = col
                    e.hl.OutlineColor = col
                    e.hl.FillTransparency = S.esp.fill and 0.65 or 1
                    e.lbl.TextColor3 = col

                    local tags = ""
                    if char:GetAttribute("Knocked") == true then tags = tags .. " [DOWN]" end
                    local hc = tonumber(char:GetAttribute("HookCount")) or 0
                    if hc > 0 then tags = tags .. " [H" .. string.format("%.0f", hc) .. "]" end
                    local prefix = (role == "Killer") and "[KILLER] " or ""
                    e.lbl.Text = string.format("%s%s (%.0fm)%s", prefix, plr.Name:sub(1, 14), dist, tags)
                end
            end
        end
    end
    for plr, e in pairs(pEsp) do
        if not seen[plr] then
            destroyEntry(e)
            pEsp[plr] = nil
        end
    end
end

-- 3, 4 & 5: Pallet, Generator & Labu ESP
local OBJ = { gen = {}, pallet = {}, pumpkin = {} }
local objEsp = {}
local scanDone = false

local function classify(inst)
    if not (inst:IsA("Model") or inst:IsA("BasePart")) then return nil end

    if CollectionService:HasTag(inst, "Generator") then return "gen" end
    if inst:IsA("Model") and inst.Name == "Generator" and inst.Parent and inst.Parent.Name == "Generators" then
        return "gen"
    end

    if CollectionService:HasTag(inst, "pallet") then return "pallet" end
    if inst.Parent and inst.Parent.Name:lower() == "pallets" then return "pallet" end

    if CollectionService:HasTag(inst, "pumpkin") then return "pumpkin" end
    if inst.Parent and inst.Parent.Name:lower() == "pumpkins" then return "pumpkin" end

    return nil
end

local function ancestorRegistered(inst)
    local p = inst.Parent
    while p and p ~= workspace do
        if OBJ.gen[p] or OBJ.pallet[p] or OBJ.pumpkin[p] then return true end
        p = p.Parent
    end
    return false
end

local function considerObj(inst)
    local kind = classify(inst)
    if not kind then return end
    if ancestorRegistered(inst) then return end
    OBJ[kind][inst] = true
    for _, d in ipairs(inst:GetDescendants()) do
        OBJ.gen[d] = nil
        OBJ.pallet[d] = nil
        OBJ.pumpkin[d] = nil
    end
end

task.spawn(function()
    for _, tag in ipairs({ "Generator", "pallet", "pumpkin" }) do
        local ok, list = pcall(function() return CollectionService:GetTagged(tag) end)
        if ok and list then
            for _, inst in ipairs(list) do
                pcall(considerObj, inst)
            end
        end
    end
    local ds = workspace:GetDescendants()
    for i, d in ipairs(ds) do
        pcall(considerObj, d)
        if i % 1500 == 0 then task.wait() end
    end
    scanDone = true
end)

track(workspace.DescendantAdded:Connect(function(d)
    pcall(considerObj, d)
end))
track(workspace.DescendantRemoving:Connect(function(d)
    OBJ.gen[d] = nil
    OBJ.pallet[d] = nil
    OBJ.pumpkin[d] = nil
end))

local PROG_WORDS = { "progress", "percent", "repair", "charge", "complet", "fill" }

local function readProgress(inst)
    local v = tonumber(inst:GetAttribute("RepairProgress"))
    if v then return v end
    for k, val in pairs(inst:GetAttributes()) do
        if type(val) == "number" and hasKeyword(k, PROG_WORDS) then return val end
    end
    return nil
end

local function adorneeOf(inst, kind)
    if kind == "pallet" and inst:IsA("Model") then
        local intact = inst:FindFirstChild("Intact")
        if intact then
            return intact.PrimaryPart or intact:FindFirstChildWhichIsA("BasePart", true)
        end
    end
    if inst:IsA("BasePart") then return inst end
    return inst.PrimaryPart or inst:FindFirstChild("HitBox") or inst:FindFirstChildWhichIsA("BasePart", true)
end

local function highlightTargetOf(inst, kind)
    if kind == "pallet" and inst:IsA("Model") then
        local intact = inst:FindFirstChild("Intact")
        if intact then return intact end
    end
    return inst
end

local function clearObjESP()
    for _, e in pairs(objEsp) do destroyEntry(e) end
    objEsp = {}
end

local function updateObjESP()
    local want = {}
    if S.esp.gens then want.gen = true end
    if S.esp.pallets then want.pallet = true end
    if S.esp.pumpkins then want.pumpkin = true end
    if next(want) == nil then
        if next(objEsp) ~= nil then clearObjESP() end
        return
    end
    local root = getRoot()
    local seen = {}
    for kind in pairs(want) do
        for inst in pairs(OBJ[kind]) do
            if inst.Parent and inst:IsDescendantOf(workspace) then
                local ad = adorneeOf(inst, kind)
                local pos = posOf(ad or inst)
                if ad and pos then
                    local dist = root and (root.Position - pos).Magnitude or 0
                    local limit = (kind == "pallet") and S.esp.palletDist or S.esp.maxDist
                    local show = (limit <= 0) or (dist <= limit)
                    local text = nil
                    local col = COL[kind]

                    if show and kind == "gen" then
                        local pct = readProgress(inst) or 0
                        if pct >= 99.9 and S.esp.hideDone then
                            show = false
                        else
                            text = string.format("GEN %.0f%% (%.0fm)", pct, dist)
                        end
                    elseif show and kind == "pallet" then
                        text = string.format("PALLET (%.0fm)", dist)
                    elseif show and kind == "pumpkin" then
                        text = string.format("LABU (%.0fm)", dist)
                    end

                    if show then
                        seen[inst] = true
                        local e = objEsp[inst]
                        local hlTarget = highlightTargetOf(inst, kind)
                        if not e or not e.bb or not e.bb.Parent or not e.hl or not e.hl.Parent then
                            destroyEntry(e)
                            e = { kind = kind }
                            e.hl = makeHighlight(hlTarget, col)
                            e.bb, e.lbl = makeLabel(ad, col, (kind == "gen") and 12 or 10, (kind == "gen") and 3 or 2)
                            objEsp[inst] = e
                        end
                        e.hl.Adornee = hlTarget
                        e.hl.FillColor = col
                        e.hl.OutlineColor = col
                        e.hl.FillTransparency = S.esp.fill and 0.65 or 1
                        e.lbl.TextColor3 = col
                        e.lbl.Text = text
                    end
                end
            end
        end
    end
    for inst, e in pairs(objEsp) do
        if not seen[inst] then
            destroyEntry(e)
            objEsp[inst] = nil
        end
    end
end

local function countObjs(kind)
    local n = 0
    for inst in pairs(OBJ[kind]) do
        if inst.Parent then n = n + 1 end
    end
    return n
end

------------------------------------------------------------------
-- LOW MODE (FLAT 1-WARNA / HAPUS TEKSTUR TANPA HILANGKAN BANGUNAN)
------------------------------------------------------------------
local origPartColors = setmetatable({}, { __mode = "k" })

local function isCharacterOrImportant(inst)
    if inst == workspace.Terrain then return true end
    local p = inst
    while p and p ~= workspace do
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character == p then return true end
        end
        if CollectionService:HasTag(p, "Killer") or CollectionService:HasTag(p, "Survivor") or CollectionService:HasTag(p, "Item") then
            return true
        end
        p = p.Parent
    end
    return false
end

local function isWeatherEffect(inst)
    local p = inst
    while p and p ~= workspace do
        local n = p.Name:lower()
        if n == "rain" or n == "foggy wind" then
            return true
        end
        p = p.Parent
    end
    return false
end

local function applyPartColorScheme(part)
    if not origPartColors[part] then
        origPartColors[part] = part.Color
    end
    local targetCol = FLAT_PALETTE[S.vis.colorScheme]
    if targetCol then
        part.Color = targetCol
    else
        part.Color = origPartColors[part]
    end
end

local function optimizeInstance(inst)
    if not S.vis.lowMode then return end
    if inst:IsDescendantOf(espFolder) then return end
    if isCharacterOrImportant(inst) then return end

    -- 1. Hapus semua tekstur ditempel (SurfaceAppearance PBR, Decal, Texture) agar jadi 1 warna polos
    if inst:IsA("SurfaceAppearance") or inst:IsA("Decal") or inst:IsA("Texture") then
        pcall(function() inst:Destroy() end)
        return
    end

    -- 2. Hapus TextureId pada SpecialMesh jika ada
    if inst:IsA("SpecialMesh") then
        pcall(function() inst.TextureId = "" end)
        return
    end

    -- 3. Matikan partikel cuaca/efek berlebih (bukan bangunan)
    if inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
        pcall(function() inst.Enabled = false end)
        return
    end

    -- 4. Ubah blok/bangunan menjadi SmoothPlastic polos 1 warna (TANPA mengubah Transparency bangunan!)
    if inst:IsA("BasePart") then
        if isWeatherEffect(inst) then
            -- Hanya part partikel hujan/kabut cuaca yang disembunyikan
            pcall(function() inst.Transparency = 1 end)
            return
        end

        pcall(function()
            inst.Material = Enum.Material.SmoothPlastic
            inst.MaterialVariant = ""
            inst.Reflectance = 0
            inst.CastShadow = false
            if inst:IsA("MeshPart") then
                inst.TextureID = ""
            end
            applyPartColorScheme(inst)
        end)
    end
end

local function refreshColorSchemeOnly()
    if not S.vis.lowMode then return end
    task.spawn(function()
        local ds = workspace:GetDescendants()
        for i, d in ipairs(ds) do
            if d:IsA("BasePart") and not isCharacterOrImportant(d) and not isWeatherEffect(d) then
                pcall(applyPartColorScheme, d)
            end
            if i % 1000 == 0 then task.wait() end
        end
    end)
end

local function toggleSmartBoneWorkers(disable)
    local ps = LP:FindFirstChild("PlayerScripts")
    if not ps then return end
    local sb = ps:FindFirstChild("SmartBone-Actors")
    if sb then
        for _, d in ipairs(sb:GetDescendants()) do
            if d:IsA("LocalScript") then
                pcall(function() d.Disabled = disable end)
            end
        end
    end
    local mech = ps:FindFirstChild("Mechanics")
    local eff = mech and mech:FindFirstChild("effects")
    local bp = eff and eff:FindFirstChild("bonephysics")
    if bp and bp:IsA("LocalScript") then
        pcall(function() bp.Disabled = disable end)
    end
end

local lowModeRunning = false
local function applyLowModeBatch()
    if not S.vis.lowMode or lowModeRunning then return end
    lowModeRunning = true

    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        Lighting.GlobalShadows = false
        workspace.Terrain.WaterWaveSize = 0
        workspace.Terrain.WaterWaveSpeed = 0
        workspace.Terrain.WaterReflectance = 0
    end)

    if S.vis.disableBones then
        pcall(toggleSmartBoneWorkers, true)
    end

    task.spawn(function()
        local ds = workspace:GetDescendants()
        for i, d in ipairs(ds) do
            if not S.vis.lowMode then break end
            pcall(optimizeInstance, d)
            if i % 600 == 0 then task.wait() end
        end
        lowModeRunning = false
    end)
end

track(workspace.DescendantAdded:Connect(function(d)
    if S.vis.lowMode then
        task.defer(function()
            pcall(optimizeInstance, d)
        end)
    end
end))

------------------------------------------------------------------
-- AUTO SKILL CHECK
------------------------------------------------------------------
local GUI_NAMES  = { "SkillCheckPromptGui", "SkillCheckPromptGui-con" }
local VK         = { Space = 0x20, E = 0x45, F = 0x46, Q = 0x51, R = 0x52, C = 0x43, V = 0x56, X = 0x58, Z = 0x5A, G = 0x47 }
local LEARN_KEYS = { Space = true, E = true, F = true, Q = true, R = true, C = true, V = true, X = true, Z = true, G = true }

local st = {
    active = false, pressed = false,
    goal = 0, line = 0,
    lastLine = 0, lastT = 0, speed = 250,
    autoT = -10, cand = nil, candT = -10,
    pressLine = 0, pressTarget = 0,
    presses = 0, samples = {}, note = "Menunggu skill check...",
}

local function median(t)
    local c = {}
    for i, v in ipairs(t) do c[i] = v end
    table.sort(c)
    local n = #c
    if n == 0 then return nil end
    if n % 2 == 1 then return c[(n + 1) / 2] end
    return (c[n / 2] + c[n / 2 + 1]) / 2
end

local function findCheck()
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    for _, name in ipairs(GUI_NAMES) do
        local g = pg:FindFirstChild(name)
        if g then
            local c = g:FindFirstChild("Check") or g:FindFirstChild("Check", true)
            if c and c:IsA("GuiObject") and c.Visible then
                local goal = c:FindFirstChild("Goal", true)
                local line = c:FindFirstChild("Line", true)
                if goal and line then return c, goal, line end
            end
        end
    end
    return nil
end

local function doPress()
    local name = SKC.input
    local ok = false
    if VIM then
        ok = pcall(function()
            if name == "Mouse" then
                local cam = workspace.CurrentCamera
                local vp = cam and cam.ViewportSize or Vector2.new(600, 400)
                VIM:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, true, game, 1)
                task.wait(0.03)
                VIM:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, false, game, 1)
            else
                local kc = Enum.KeyCode[name]
                VIM:SendKeyEvent(true, kc, false, game)
                task.wait(0.03)
                VIM:SendKeyEvent(false, kc, false, game)
            end
        end)
    end
    if not ok then
        pcall(function()
            if name == "Mouse" then
                mouse1press()
                task.wait(0.03)
                mouse1release()
            else
                keypress(VK[name] or 0x20)
                task.wait(0.03)
                keyrelease(VK[name] or 0x20)
            end
        end)
    end
end

track(UIS.InputBegan:Connect(function(input)
    if not st.active then return end
    if os.clock() - st.autoT < 0.3 then return end
    local n = nil
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        n = "Mouse"
    elseif input.UserInputType == Enum.UserInputType.Keyboard and LEARN_KEYS[input.KeyCode.Name] then
        n = input.KeyCode.Name
    end
    if n then
        st.cand = n
        st.candT = os.clock()
    end
end))

local function onCheckEnd(now)
    if st.pressed then
        st.note = string.format("Terakhir: auto klik di Line %.0f (Target %.0f)", st.pressLine, st.pressTarget)
        return
    end
    if SKC.learn and st.cand and (now - st.candT) < 0.45 then
        if inList(st.cand, INPUT_LIST) then
            SKC.input = st.cand
            if Options.SKC_Input then pcall(function() Options.SKC_Input:SetValue(st.cand) end) end
        end
        local d = st.line - st.goal
        if d > 85 and d < 145 then
            st.samples[#st.samples + 1] = d
            if #st.samples > 8 then table.remove(st.samples, 1) end
            SKC.offset = median(st.samples) or SKC.offset
            if Options.SKC_Offset then pcall(function() Options.SKC_Offset:SetValue(SKC.offset) end) end
            st.note = string.format("Belajar: klik manual di Goal+%.0f -> Offset jadi %.1f", d, SKC.offset)
            Fluent:Notify({
                Title = "Auto Skill Check",
                Content = string.format("Offset baru dipelajari: %.1f (%d sampel)", SKC.offset, #st.samples),
                Duration = 3
            })
        else
            st.note = string.format("Input '%s' dicatat (Goal+%.0f di luar rentang)", st.cand, d)
        end
    end
    st.cand = nil
end

track(RunService.RenderStepped:Connect(function()
    local ok = pcall(function()
        local now = os.clock()
        local c, goal, line = findCheck()
        if c then
            local gr, lr = goal.Rotation, line.Rotation
            if not st.active then
                st.active = true
                st.pressed = false
                st.lastLine, st.lastT = lr, now
            end
            local dt = now - st.lastT
            if dt > 0 and lr ~= st.lastLine then
                local sp = (lr - st.lastLine) / dt
                if sp > 40 and sp < 400 then st.speed = st.speed * 0.8 + sp * 0.2 end
                st.lastLine, st.lastT = lr, now
            end
            st.goal, st.line = gr, lr

            if SKC.on and not st.pressed and gr ~= 0 then
                local target = gr + SKC.offset
                if lr + st.speed * SKC.lead >= target and lr < target + 40 then
                    st.pressed = true
                    st.autoT = now
                    st.pressLine, st.pressTarget = lr, target
                    st.presses = st.presses + 1
                    task.spawn(doPress)
                end
            end
        elseif st.active then
            st.active = false
            onCheckEnd(now)
        end
    end)
    if not ok then st.note = "Error di loop skill check" end
end))

------------------------------------------------------------------
-- VISUAL: FULLBRIGHT & NO DARKNESS
------------------------------------------------------------------
local lightOrig = nil
local effOrig = {}
local darkOrig = nil

local function lightSave()
    if lightOrig then return end
    lightOrig = {
        Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart, GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient, ExposureCompensation = Lighting.ExposureCompensation,
    }
end

local function killEffects(container)
    for _, e in ipairs(container:GetChildren()) do
        if e:IsA("PostEffect") then
            if effOrig[e] == nil then effOrig[e] = { kind = "post", v = e.Enabled } end
            e.Enabled = false
        elseif e:IsA("Atmosphere") then
            if effOrig[e] == nil then effOrig[e] = { kind = "atmo", d = e.Density, h = e.Haze } end
            e.Density = 0
            e.Haze = 0
        end
    end
end

local function lightApply()
    lightSave()
    Lighting.Brightness = S.vis.bright
    Lighting.ClockTime = 14
    Lighting.FogEnd = 1e6
    Lighting.FogStart = 1e6
    Lighting.GlobalShadows = false
    Lighting.Ambient = Color3.fromRGB(190, 190, 190)
    Lighting.OutdoorAmbient = Color3.fromRGB(190, 190, 190)
    Lighting.ExposureCompensation = 0
    killEffects(Lighting)
    local cam = workspace.CurrentCamera
    if cam then killEffects(cam) end
    if S.vis.noDark then
        local pg = LP:FindFirstChildOfClass("PlayerGui")
        local dk = pg and pg:FindFirstChild("Darkness")
        if dk and dk:IsA("ScreenGui") then
            if darkOrig == nil then darkOrig = dk.Enabled end
            dk.Enabled = false
        end
    end
end

local function darkRestore()
    if darkOrig ~= nil then
        local pg = LP:FindFirstChildOfClass("PlayerGui")
        local dk = pg and pg:FindFirstChild("Darkness")
        if dk then pcall(function() dk.Enabled = darkOrig end) end
        darkOrig = nil
    end
end

local function lightRestore()
    if lightOrig then
        for k, v in pairs(lightOrig) do pcall(function() Lighting[k] = v end) end
        lightOrig = nil
    end
    for e, o in pairs(effOrig) do
        if e.Parent then
            pcall(function()
                if o.kind == "post" then
                    e.Enabled = o.v
                else
                    e.Density = o.d
                    e.Haze = o.h
                end
            end)
        end
    end
    effOrig = {}
    darkRestore()
end

track(RunService.RenderStepped:Connect(function()
    if S.vis.full then pcall(lightApply) end
end))

------------------------------------------------------------------
-- MOVE & AUTO AIM
------------------------------------------------------------------
track(RunService.Heartbeat:Connect(function(dt)
    if not S.move.on then return end
    local root, char = getRoot()
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (root and hum) then return end
    if S.move.mode == "WalkSpeed" then
        if hum.WalkSpeed ~= S.move.ws then hum.WalkSpeed = S.move.ws end
    else
        local md = hum.MoveDirection
        if md.Magnitude > 0 then
            root.CFrame = root.CFrame + md * (S.move.cf * dt)
        end
    end
end))

local function pickTarget()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local myRole = roleOf(LP)
    local camPos = cam.CFrame.Position
    local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    local okf, ft = pcall(function() return Enum.RaycastFilterType.Exclude end)
    local best, bestScore = nil, math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local role = roleOf(plr)
            local teamOk
            if myRole == "Killer" then
                teamOk = (role == "Survivor")
            elseif myRole == "Survivor" then
                teamOk = (role == "Killer")
            else
                teamOk = true
            end
            local char = plr.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if teamOk and char and hum and hum.Health > 0 then
                if not (myRole == "Killer" and char:GetAttribute("Knocked") == true) then
                    local part = char:FindFirstChild(S.aim.part) or char:FindFirstChild("HumanoidRootPart")
                    if part then
                        local sp, onScreen = cam:WorldToViewportPoint(part.Position)
                        if onScreen then
                            local d2 = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                            local d3 = (camPos - part.Position).Magnitude
                            if d2 <= S.aim.fov and d3 <= S.aim.dist and d2 < bestScore then
                                local visible = true
                                if S.aim.wall then
                                    local rp = RaycastParams.new()
                                    rp.FilterType = okf and ft or Enum.RaycastFilterType.Blacklist
                                    rp.FilterDescendantsInstances = { LP.Character, char }
                                    visible = workspace:Raycast(camPos, part.Position - camPos, rp) == nil
                                end
                                if visible then
                                    best, bestScore = part, d2
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

RunService:BindToRenderStep("MAG_VD_Aim", Enum.RenderPriority.Camera.Value + 1, function()
    if not S.aim.on then return end
    if not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end
    if UIS:GetFocusedTextBox() then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    local ok, part = pcall(pickTarget)
    if not ok or not part then return end
    local goal = CFrame.lookAt(cam.CFrame.Position, part.Position)
    cam.CFrame = cam.CFrame:Lerp(goal, S.aim.smooth)
end)

------------------------------------------------------------------
-- FLUENT WINDOW & TABS
------------------------------------------------------------------
local Window = Fluent:CreateWindow({
    Title = "Violence District",
    SubTitle = "Fluent Edition v3.4",
    TabWidth = 150,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightShift
})

local Tabs = {
    ESP       = Window:AddTab({ Title = "ESP", Icon = "eye" }),
    Crosshair = Window:AddTab({ Title = "Crosshair", Icon = "crosshair" }),
    Skill     = Window:AddTab({ Title = "Skill Check", Icon = "zap" }),
    MoveAim   = Window:AddTab({ Title = "Move & Aim", Icon = "gauge" }),
    Visual    = Window:AddTab({ Title = "Visual", Icon = "sun" }),
    Settings  = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

-- ================= TAB 1: ESP =================
local EspSec = Tabs.ESP:AddSection("Target ESP")

local T_Killer = EspSec:AddToggle("ESP_Killer", { Title = "1. Killer (Merah + Highlight)", Default = true })
T_Killer:OnChanged(function() S.esp.killer = Options.ESP_Killer.Value end)

local T_Surv = EspSec:AddToggle("ESP_Survivor", { Title = "2. Survivor (Hijau + Highlight)", Default = true })
T_Surv:OnChanged(function() S.esp.survivor = Options.ESP_Survivor.Value end)

local T_Pallet = EspSec:AddToggle("ESP_Pallet", { Title = "3. Pallet (Ungu + Highlight)", Default = true })
T_Pallet:OnChanged(function() S.esp.pallets = Options.ESP_Pallet.Value end)

local T_Gen = EspSec:AddToggle("ESP_Gen", { Title = "4. Generator (Kuning + Highlight + Progress)", Default = true })
T_Gen:OnChanged(function() S.esp.gens = Options.ESP_Gen.Value end)

local T_Pump = EspSec:AddToggle("ESP_Pumpkin", { Title = "5. Labu / Pumpkin (Cyan + Highlight)", Default = true })
T_Pump:OnChanged(function() S.esp.pumpkins = Options.ESP_Pumpkin.Value end)

local EspCfgSec = Tabs.ESP:AddSection("Konfigurasi ESP")

local T_HideDone = EspCfgSec:AddToggle("ESP_HideDone", { Title = "Sembunyikan Generator Selesai (100%)", Default = true })
T_HideDone:OnChanged(function() S.esp.hideDone = Options.ESP_HideDone.Value end)

local T_Fill = EspCfgSec:AddToggle("ESP_Fill", { Title = "Isi Warna Highlight (Fill)", Default = true })
T_Fill:OnChanged(function() S.esp.fill = Options.ESP_Fill.Value end)

EspCfgSec:AddSlider("ESP_MaxDist", {
    Title = "Jarak Maks (Pemain, Gen & Labu)",
    Description = "0 = tampilkan tanpa batas jarak",
    Default = 0, Min = 0, Max = 500, Rounding = 0,
    Callback = function(v) S.esp.maxDist = v end
})

EspCfgSec:AddSlider("ESP_PalletDist", {
    Title = "Jarak Maks Pallet",
    Description = "0 = tampilkan semua pallet",
    Default = 150, Min = 0, Max = 400, Rounding = 0,
    Callback = function(v) S.esp.palletDist = v end
})

local EspInfoParagraph = Tabs.ESP:AddParagraph({
    Title = "Info Peta Saat Ini",
    Content = "Memindai objek di Workspace..."
})

-- ================= TAB 2: CROSSHAIR =================
local CrSec = Tabs.Crosshair:AddSection("Custom Crosshair")

local T_CrOn = CrSec:AddToggle("CR_On", { Title = "Tampilkan Crosshair", Default = true })
T_CrOn:OnChanged(function()
    S.cross.on = Options.CR_On.Value
    updateCrosshair()
end)

local T_CrDot = CrSec:AddToggle("CR_Dot", { Title = "Titik Tengah (Center Dot)", Default = true })
T_CrDot:OnChanged(function()
    S.cross.dot = Options.CR_Dot.Value
    updateCrosshair()
end)

local D_CrCol = CrSec:AddDropdown("CR_Color", {
    Title = "Warna Crosshair",
    Values = { "Green", "Cyan", "Red", "Yellow", "White" },
    Multi = false,
    Default = 1,
})
D_CrCol:OnChanged(function(v)
    S.cross.color = v
    updateCrosshair()
end)

CrSec:AddSlider("CR_Size", {
    Title = "Panjang Garis (Size)",
    Default = 8, Min = 2, Max = 25, Rounding = 0,
    Callback = function(v) S.cross.size = v; updateCrosshair() end
})

CrSec:AddSlider("CR_Gap", {
    Title = "Celah Tengah (Gap)",
    Default = 4, Min = 0, Max = 20, Rounding = 0,
    Callback = function(v) S.cross.gap = v; updateCrosshair() end
})

CrSec:AddSlider("CR_Thick", {
    Title = "Ketebalan (Thickness)",
    Default = 2, Min = 1, Max = 6, Rounding = 0,
    Callback = function(v) S.cross.thick = v; updateCrosshair() end
})

-- ================= TAB 3: SKILL CHECK =================
local SkSec = Tabs.Skill:AddSection("Auto Skill Check")

local T_SkOn = SkSec:AddToggle("SKC_On", { Title = "Aktifkan Auto Skill Check", Default = true })
T_SkOn:OnChanged(function() SKC.on = Options.SKC_On.Value end)

local T_SkLearn = SkSec:AddToggle("SKC_Learn", {
    Title = "Auto-Learn dari Klik Manual",
    Description = "Otomatis menyesuaikan tombol & offset saat kamu menekan manual",
    Default = true
})
T_SkLearn:OnChanged(function() SKC.learn = Options.SKC_Learn.Value end)

local D_SkInput = SkSec:AddDropdown("SKC_Input", {
    Title = "Tombol Skill Check",
    Values = INPUT_LIST,
    Multi = false,
    Default = 1,
})
D_SkInput:OnChanged(function(v) SKC.input = v end)

SkSec:AddSlider("SKC_Offset", {
    Title = "Offset (Line - Goal)",
    Default = 115, Min = 60, Max = 170, Rounding = 1,
    Callback = function(v) SKC.offset = v end
})

SkSec:AddSlider("SKC_Lead", {
    Title = "Lead Time (Kompensasi Lag Detik)",
    Default = 0.03, Min = 0, Max = 0.15, Rounding = 3,
    Callback = function(v) SKC.lead = v end
})

SkSec:AddButton({
    Title = "Reset Offset ke Default (115)",
    Callback = function()
        SKC.offset = 115
        st.samples = {}
        if Options.SKC_Offset then Options.SKC_Offset:SetValue(115) end
        Fluent:Notify({ Title = "Skill Check", Content = "Offset dikembalikan ke 115", Duration = 2 })
    end
})

local SkStatusParagraph = Tabs.Skill:AddParagraph({
    Title = "Live Telemetry",
    Content = "Menunggu skill check..."
})

-- ================= TAB 4: MOVE & AIM =================
local MvSec = Tabs.MoveAim:AddSection("Speed Boost")

local T_MvOn = MvSec:AddToggle("MV_On", { Title = "Aktifkan Speed Boost", Default = false })
T_MvOn:OnChanged(function() S.move.on = Options.MV_On.Value end)

local D_MvMode = MvSec:AddDropdown("MV_Mode", {
    Title = "Mode Kecepatan",
    Values = { "WalkSpeed", "CFrame" },
    Multi = false,
    Default = 1,
})
D_MvMode:OnChanged(function(v) S.move.mode = v end)

MvSec:AddSlider("MV_WS", {
    Title = "WalkSpeed",
    Default = 24, Min = 8, Max = 100, Rounding = 0,
    Callback = function(v) S.move.ws = v end
})

MvSec:AddSlider("MV_CF", {
    Title = "CFrame Speed (Studs/dtk)",
    Default = 10, Min = 0, Max = 60, Rounding = 0,
    Callback = function(v) S.move.cf = v end
})

local AimSec = Tabs.MoveAim:AddSection("Auto Aim (Tahan Klik Kanan)")

local T_AimOn = AimSec:AddToggle("AIM_On", { Title = "Aktifkan Auto Aim", Default = false })
T_AimOn:OnChanged(function() S.aim.on = Options.AIM_On.Value end)

local D_AimPart = AimSec:AddDropdown("AIM_Part", {
    Title = "Bagian Target",
    Values = { "HumanoidRootPart", "Head", "Torso" },
    Multi = false,
    Default = 1,
})
D_AimPart:OnChanged(function(v) S.aim.part = v end)

local T_AimWall = AimSec:AddToggle("AIM_Wall", { Title = "Wall Check (Abaikan Balik Tembok)", Default = true })
T_AimWall:OnChanged(function() S.aim.wall = Options.AIM_Wall.Value end)

AimSec:AddSlider("AIM_FOV", {
    Title = "Radius FOV (px)",
    Default = 250, Min = 50, Max = 800, Rounding = 0,
    Callback = function(v) S.aim.fov = v end
})

AimSec:AddSlider("AIM_Dist", {
    Title = "Jarak Maksimum Target (studs)",
    Default = 150, Min = 20, Max = 500, Rounding = 0,
    Callback = function(v) S.aim.dist = v end
})

AimSec:AddSlider("AIM_Smooth", {
    Title = "Smoothness (1 = Snap Instan)",
    Default = 0.5, Min = 0.05, Max = 1, Rounding = 2,
    Callback = function(v) S.aim.smooth = v end
})

-- ================= TAB 5: VISUAL & LOW MODE =================
local LowSec = Tabs.Visual:AddSection("Low Mode (Bangunan Utuh + Polos 1 Warna)")

local T_LowMode = LowSec:AddToggle("VIS_LowMode", {
    Title = "Aktifkan Low Mode (Hapus Tekstur Blok)",
    Description = "Bangunan tetap utuh, semua tekstur diubah jadi blok polos SmoothPlastic 1 warna",
    Default = false
})
T_LowMode:OnChanged(function()
    S.vis.lowMode = Options.VIS_LowMode.Value
    if S.vis.lowMode then
        applyLowModeBatch()
        Fluent:Notify({
            Title = "Low Mode Aktif",
            Content = "Tekstur bangunan dihapus menjadi blok 1 warna polos (bangunan tetap utuh).",
            Duration = 3
        })
    end
end)

local D_ColScheme = LowSec:AddDropdown("VIS_ColorScheme", {
    Title = "Mode Warna Blok Bangunan",
    Description = "Original = warna dasar tiap blok, lainnya = ratakan semua blok jadi 1 warna",
    Values = { "Original", "SlateGrey", "DarkGrey", "LightGrey" },
    Multi = false,
    Default = 1,
})
D_ColScheme:OnChanged(function(v)
    S.vis.colorScheme = v
    if S.vis.lowMode then
        refreshColorSchemeOnly()
    end
end)

local T_DisBones = LowSec:AddToggle("VIS_DisableBones", {
    Title = "Matikan Fisika SmartBone (Hemat CPU)",
    Description = "Mematikan kalkulasi goyangan kain/aksesoris (SmartBone-Actors)",
    Default = true
})
T_DisBones:OnChanged(function()
    S.vis.disableBones = Options.VIS_DisableBones.Value
    if S.vis.lowMode then
        pcall(toggleSmartBoneWorkers, S.vis.disableBones)
    end
end)

LowSec:AddButton({
    Title = "Terapkan Ulang Low Mode (Refresh Map)",
    Description = "Klik saat baru pindah map / ronde baru",
    Callback = function()
        S.vis.lowMode = true
        if Options.VIS_LowMode then Options.VIS_LowMode:SetValue(true) end
        applyLowModeBatch()
        Fluent:Notify({ Title = "Low Mode", Content = "Seluruh blok bangunan disederhanakan!", Duration = 2 })
    end
})

local VisSec = Tabs.Visual:AddSection("Pencahayaan & Efek")

local T_VisFull = VisSec:AddToggle("VIS_Full", { Title = "Fullbright (Terang & Hapus Kabut)", Default = false })
T_VisFull:OnChanged(function()
    S.vis.full = Options.VIS_Full.Value
    if not S.vis.full then lightRestore() end
end)

local T_VisDark = VisSec:AddToggle("VIS_NoDark", { Title = "Hilangkan Layar Gelap (Darkness GUI)", Default = true })
T_VisDark:OnChanged(function()
    S.vis.noDark = Options.VIS_NoDark.Value
    if not S.vis.noDark then darkRestore() end
end)

VisSec:AddSlider("VIS_Bright", {
    Title = "Tingkat Brightness",
    Default = 2, Min = 0, Max = 6, Rounding = 1,
    Callback = function(v) S.vis.bright = v end
})

-- ================= TAB 6: SETTINGS =================
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("FluentScriptHub")
SaveManager:SetFolder("FluentScriptHub/ViolenceDistrict")

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

------------------------------------------------------------------
-- CLEANUP HANDLER & MAIN LOOP
------------------------------------------------------------------
local hub = {}
local function destroyHub()
    alive = false
    S.vis.full = false
    S.vis.lowMode = false
    S.move.on = false
    S.aim.on = false
    SKC.on = false
    pcall(lightRestore)
    pcall(toggleSmartBoneWorkers, false)
    pcall(function() RunService:UnbindFromRenderStep("MAG_VD_Aim") end)
    pcall(clearPlayersESP)
    pcall(clearObjESP)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(function() crossGui:Destroy() end)
    pcall(function() espFolder:Destroy() end)
    pcall(function() Window:Destroy() end)
    if genv.MAG_VD == hub then genv.MAG_VD = nil end
end
hub.destroy = destroyHub
genv.MAG_VD = hub

Tabs.Settings:AddButton({
    Title = "Unload / Matikan Script",
    Description = "Membersihkan semua ESP, Crosshair, dan menutup UI",
    Callback = destroyHub
})

task.spawn(function()
    while alive do
        task.wait(0.25)
        pcall(updatePlayersESP)
        pcall(updateObjESP)

        pcall(function()
            EspInfoParagraph:SetDesc(string.format(
                "Role Kamu: %s  |  Gen: %d  |  Pallet: %d  |  Labu: %d%s",
                tostring(roleOf(LP) or "Lobby"),
                countObjs("gen"),
                countObjs("pallet"),
                countObjs("pumpkin"),
                scanDone and "" or " (Scanning...)"
            ))

            local stateStr = st.active
                and string.format("AKTIF (Goal: %.0f | Line: %.0f | Target: %.0f)", st.goal, st.line, st.goal + SKC.offset)
                or st.note
            SkStatusParagraph:SetDesc(string.format(
                "Tombol: %s  |  Offset: %.1f  |  Speed Jarum: %.0f/dtk  |  Auto Klik: %d\n%s",
                SKC.input, SKC.offset, st.speed, st.presses, stateStr
            ))
        end)
    end
end)

Window:SelectTab(1)
SaveManager:LoadAutoloadConfig()

Fluent:Notify({
    Title = "Violence District",
    Content = "Fluent Hub v3.4 siap! Low Mode kini menjaga bangunan tetap utuh.",
    Duration = 4
})

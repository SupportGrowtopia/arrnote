--[[
=====================================================================
  ViolenceDistrict_Fluent.lua (v3.6 - Anti-Lag & No-Distance ESP)
  Perbaikan Performa:
  - Hilangkan jarak di ESP (mencegah TextLabel layout & string format terus menerus)
  - ESP Instance Pooling (toggle Enabled = false daripada Destroy/Instance.new)
  - Pembatasan Highlight maksimal 24 (mencegah limit 31 Highlight Roblox & drop FPS)
  - RaycastParams reusable untuk Auto Aim (Zero-Allocation RenderStep)
  - Fullbright guarded check (hanya reapply jika lighting diubah game)
  - Telemetry UI throttling 1.5 detik
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
        palletDist = 120 -- Dibatasi default 120m agar tidak tembus limit 31 Highlight Roblox
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
        colorScheme = "Original",
        disableBones = true
    },
    aim  = { on = false, mode = "Silent", trigger = "Always", fov = 250, dist = 150, smooth = 0.5, part = "HumanoidRootPart", wall = true },
}

-- Auto Skill Check (Tanpa Auto-Learn)
local SKC = { on = true, input = "Space", offset = 115, lead = 0.03 }
local INPUT_LIST = { "Space", "Mouse", "E", "F" }

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
local function getRoot()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart"), c
end

local function posOf(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst.Position end
    if inst:IsA("Model") then
        local ok, cf = pcall(inst.GetPivot, inst)
        if ok and cf then return cf.Position end
    end
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
-- ESP SYSTEM (OPTIMIZED VIA COLLECTION SERVICE TAGS)
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
    local targetFill = S.esp.fill and 0.65 or 1

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
                        e = { char = char, col = col, fill = targetFill, txt = "" }
                        e.hl = makeHighlight(char, col)
                        e.bb, e.lbl = makeLabel(hrp, col, 11, 3.2)
                        pEsp[plr] = e
                    else
                        if not e.hl.Enabled then e.hl.Enabled = true end
                        if not e.bb.Enabled then e.bb.Enabled = true end
                    end
                    -- Hanya update property jika berubah (mencegah GPU redraw)
                    if e.col ~= col then
                        e.col = col
                        e.hl.FillColor = col
                        e.hl.OutlineColor = col
                        e.lbl.TextColor3 = col
                    end
                    if e.fill ~= targetFill then
                        e.fill = targetFill
                        e.hl.FillTransparency = targetFill
                    end

                    local tags = ""
                    if char:GetAttribute("Knocked") == true then tags = tags .. " [DOWN]" end
                    local hc = tonumber(char:GetAttribute("HookCount")) or 0
                    if hc > 0 then tags = tags .. " [H" .. string.format("%.0f", hc) .. "]" end
                    local prefix = (role == "Killer") and "[KILLER] " or ""
                    local newTxt = prefix .. plr.Name:sub(1, 14) .. tags
                    if e.txt ~= newTxt then
                        e.txt = newTxt
                        e.lbl.Text = newTxt
                    end
                end
            end
        end
    end
    for plr, e in pairs(pEsp) do
        if not seen[plr] then
            if plr.Parent == nil or not plr.Character then
                destroyEntry(e)
                pEsp[plr] = nil
            else
                if e.hl and e.hl.Enabled then e.hl.Enabled = false end
                if e.bb and e.bb.Enabled then e.bb.Enabled = false end
            end
        end
    end
end

-- 3, 4 & 5: Pallet, Generator & Labu ESP (Menggunakan Tag Langsung Tanpa Scan Seluruh Workspace)
local OBJ = { gen = {}, pallet = {}, pumpkin = {} }
local objEsp = {}

local TAG_MAP = {
    Generator = "gen",
    pallet    = "pallet",
    pumpkin   = "pumpkin"
}

local function registerTagged(kind, inst)
    if not inst or not (inst:IsA("Model") or inst:IsA("BasePart")) then return end
    local ad, hlTarget = inst, inst
    if kind == "pallet" and inst:IsA("Model") then
        local intact = inst:FindFirstChild("Intact")
        if intact then
            hlTarget = intact
            ad = intact.PrimaryPart or intact:FindFirstChildWhichIsA("BasePart", true) or inst
        end
    elseif inst:IsA("Model") then
        ad = inst.PrimaryPart or inst:FindFirstChild("HitBox") or inst:FindFirstChildWhichIsA("BasePart", true) or inst
    end
    OBJ[kind][inst] = { ad = ad, hlTarget = hlTarget }
end

for tag, kind in pairs(TAG_MAP) do
    local ok, list = pcall(function() return CollectionService:GetTagged(tag) end)
    if ok and list then
        for _, inst in ipairs(list) do
            registerTagged(kind, inst)
        end
    end
    track(CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
        task.defer(registerTagged, kind, inst)
    end))
    track(CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
        OBJ[kind][inst] = nil
        if objEsp[inst] then
            destroyEntry(objEsp[inst])
            objEsp[inst] = nil
        end
    end))
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
    local rootPos = root and root.Position
    local seen = {}
    local targetFill = S.esp.fill and 0.65 or 1
    local activeHighlights = 0

    for _, pe in pairs(pEsp) do
        if pe.hl and pe.hl.Enabled then
            activeHighlights = activeHighlights + 1
        end
    end

    for kind in pairs(want) do
        local col = COL[kind]
        for inst, data in pairs(OBJ[kind]) do
            if inst.Parent then
                local valid = true
                if kind == "pallet" and inst:IsA("Model") and not inst:FindFirstChild("Intact") then
                    valid = false
                    OBJ[kind][inst] = nil
                    if objEsp[inst] then
                        destroyEntry(objEsp[inst])
                        objEsp[inst] = nil
                    end
                end

                if valid then
                    local ad = data.ad
                    if not ad or not ad.Parent then
                        ad = inst:FindFirstChildWhichIsA("BasePart", true)
                        data.ad = ad
                    end
                    local pos = posOf(ad or inst)
                    if ad and pos then
                        local dist = rootPos and (rootPos - pos).Magnitude or 0
                        local limit = (kind == "pallet") and S.esp.palletDist or S.esp.maxDist
                        local show = (limit <= 0) or (dist <= limit)
                        local text = nil

                        if show and kind == "gen" then
                            local pct = tonumber(inst:GetAttribute("RepairProgress")) or 0
                            if pct >= 99.9 and S.esp.hideDone then
                                show = false
                            else
                                text = string.format("GEN %.0f%%", pct)
                            end
                        elseif show and kind == "pallet" then
                            text = "PALLET"
                        elseif show and kind == "pumpkin" then
                            text = "LABU"
                        end

                        if show then
                            seen[inst] = true
                            local e = objEsp[inst]
                            local hlTarget = data.hlTarget or inst
                            if not e or not e.bb or not e.bb.Parent or not e.hl or not e.hl.Parent then
                                destroyEntry(e)
                                e = { kind = kind, fill = targetFill, txt = "" }
                                e.hl = makeHighlight(hlTarget, col)
                                e.bb, e.lbl = makeLabel(ad, col, (kind == "gen") and 12 or 10, (kind == "gen") and 3 or 2)
                                objEsp[inst] = e
                            end

                            -- Batasi highlight maks 24 agar tidak pernah tembus limit 31 Roblox
                            local allowHl = (kind == "gen") or (activeHighlights < 24)
                            if allowHl then
                                activeHighlights = activeHighlights + 1
                                if not e.hl.Enabled then e.hl.Enabled = true end
                            else
                                if e.hl.Enabled then e.hl.Enabled = false end
                            end

                            if not e.bb.Enabled then e.bb.Enabled = true end

                            if e.fill ~= targetFill then
                                e.fill = targetFill
                                e.hl.FillTransparency = targetFill
                            end
                            if e.txt ~= text then
                                e.txt = text
                                e.lbl.Text = text
                            end
                        end
                    end
                end
            else
                OBJ[kind][inst] = nil
                if objEsp[inst] then
                    destroyEntry(objEsp[inst])
                    objEsp[inst] = nil
                end
            end
        end
    end

    for inst, e in pairs(objEsp) do
        if not seen[inst] then
            if inst.Parent == nil then
                destroyEntry(e)
                objEsp[inst] = nil
            else
                if e.hl and e.hl.Enabled then e.hl.Enabled = false end
                if e.bb and e.bb.Enabled then e.bb.Enabled = false end
            end
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
-- LOW MODE (ANTI-LAG INSTAN TANPA FREEZE)
------------------------------------------------------------------
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

local function applyFastLowMode()
    if not S.vis.lowMode then return end
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

    -- Matikan hujan & kabut di Workspace.Map secara instan (tanpa scan ribuan part)
    local mapFolder = workspace:FindFirstChild("Map")
    if mapFolder then
        local rain = mapFolder:FindFirstChild("rain")
        if rain then
            for _, d in ipairs(rain:GetDescendants()) do
                if d:IsA("ParticleEmitter") or d:IsA("Beam") then
                    pcall(function() d.Enabled = false end)
                elseif d:IsA("BasePart") then
                    pcall(function() d.Transparency = 1 end)
                end
            end
        end
        for _, ch in ipairs(mapFolder:GetChildren()) do
            if ch.Name == "Foggy Wind" then
                for _, d in ipairs(ch:GetDescendants()) do
                    if d:IsA("ParticleEmitter") or d:IsA("Beam") then
                        pcall(function() d.Enabled = false end)
                    end
                end
            end
        end
    end
end

-- Fungsi opsional sekali klik untuk mengubah semua blok map menjadi SmoothPlastic 1 warna
local flattenBusy = false
local function flattenMapBlocksOnce()
    if flattenBusy then return end
    flattenBusy = true
    local targetCol = FLAT_PALETTE[S.vis.colorScheme]

    task.spawn(function()
        local folders = { workspace:FindFirstChild("Map"), workspace:FindFirstChild("Lobby") }
        for _, rootFolder in ipairs(folders) do
            if rootFolder then
                local ds = rootFolder:GetDescendants()
                for i, inst in ipairs(ds) do
                    if inst:IsA("BasePart") then
                        pcall(function()
                            inst.Material = Enum.Material.SmoothPlastic
                            inst.Reflectance = 0
                            inst.CastShadow = false
                            if inst:IsA("MeshPart") then
                                inst.TextureID = ""
                            end
                            if targetCol and inst.Transparency < 1 then
                                inst.Color = targetCol
                            end
                        end)
                    elseif inst:IsA("SurfaceAppearance") or inst:IsA("Decal") or inst:IsA("Texture") then
                        pcall(function() inst:Destroy() end)
                    elseif inst:IsA("ParticleEmitter") then
                        pcall(function() inst.Enabled = false end)
                    end
                    if i % 250 == 0 then task.wait() end
                end
            end
        end
        flattenBusy = false
        Fluent:Notify({
            Title = "Selesai",
            Content = "Semua blok bangunan telah diubah menjadi polos 1 warna!",
            Duration = 3
        })
    end)
end

------------------------------------------------------------------
-- AUTO SKILL CHECK (CACHED UI & TANPA AUTO-LEARN)
------------------------------------------------------------------
local GUI_NAMES = { "SkillCheckPromptGui", "SkillCheckPromptGui-con" }
local VK        = { Space = 0x20, E = 0x45, F = 0x46, Q = 0x51, R = 0x52, C = 0x43, V = 0x56, X = 0x58, Z = 0x5A, G = 0x47 }

local st = {
    active = false, pressed = false,
    goal = 0, line = 0,
    lastLine = 0, lastT = 0, speed = 250,
    pressLine = 0, pressTarget = 0,
    presses = 0, note = "Menunggu skill check...",
}

-- Cache referensi UI agar TIDAK memanggil FindFirstChild(..., true) setiap frame
local cachedChecks = {}
local lastCacheScan = 0

local function refreshSkillCheckCache()
    cachedChecks = {}
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    for _, name in ipairs(GUI_NAMES) do
        local g = pg:FindFirstChild(name)
        if g then
            local c = g:FindFirstChild("Check", true)
            if c and c:IsA("GuiObject") then
                local goal = c:FindFirstChild("Goal", true)
                local line = c:FindFirstChild("Line", true)
                if goal and line then
                    cachedChecks[#cachedChecks + 1] = { check = c, goal = goal, line = line }
                end
            end
        end
    end
end

local function getActiveCheckFast(now)
    if #cachedChecks == 0 and (now - lastCacheScan) > 1.5 then
        lastCacheScan = now
        refreshSkillCheckCache()
    end
    for i = 1, #cachedChecks do
        local item = cachedChecks[i]
        if item.check.Parent and item.check.Visible then
            return item.check, item.goal, item.line
        elseif not item.check.Parent then
            cachedChecks = {}
            break
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

track(RunService.RenderStepped:Connect(function()
    if not SKC.on then return end
    local now = os.clock()
    local c, goal, line = getActiveCheckFast(now)
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

        if not st.pressed and gr ~= 0 then
            local target = gr + SKC.offset
            if lr + st.speed * SKC.lead >= target and lr < target + 40 then
                st.pressed = true
                st.pressLine, st.pressTarget = lr, target
                st.presses = st.presses + 1
                task.spawn(doPress)
            end
        end
    elseif st.active then
        st.active = false
        if st.pressed then
            st.note = string.format("Terakhir: auto klik di Line %.0f (Target %.0f)", st.pressLine, st.pressTarget)
        end
    end
end))

------------------------------------------------------------------
-- VISUAL: FULLBRIGHT & NO DARKNESS (DIPINDAH KE LOOP 0.5 DTK AGAR RINGAN)
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

local aimRayParams = RaycastParams.new()
pcall(function()
    aimRayParams.FilterType = Enum.RaycastFilterType.Exclude
end)

local function pickTarget()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local myRole = roleOf(LP)
    local camPos = cam.CFrame.Position
    local mouseLoc = UIS:GetMouseLocation()
    local center = mouseLoc or Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
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
                                    aimRayParams.FilterDescendantsInstances = { LP.Character, char }
                                    visible = workspace:Raycast(camPos, part.Position - camPos, aimRayParams) == nil
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

local currentTargetPart = nil

local function getValidTarget()
    if not S.aim.on then return nil end
    if S.aim.trigger == "RightClick" and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        return nil
    end
    if UIS:GetFocusedTextBox() then return nil end
    return currentTargetPart
end

genv.VD_GET_TARGET = getValidTarget

-- Update target berkala (Zero redundant calculation)
track(RunService.Heartbeat:Connect(function()
    if not S.aim.on then
        currentTargetPart = nil
        return
    end
    if S.aim.trigger == "RightClick" and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        currentTargetPart = nil
        return
    end
    if UIS:GetFocusedTextBox() then
        currentTargetPart = nil
        return
    end
    local ok, target = pcall(pickTarget)
    if ok and target then
        currentTargetPart = target
    else
        currentTargetPart = nil
    end
end))

-- Mode 1: Camera Lock (Hanya jika mode Camera & tahan klik kanan)
RunService:BindToRenderStep("MAG_VD_Aim", Enum.RenderPriority.Camera.Value + 1, function()
    if not S.aim.on or S.aim.mode ~= "Camera" then return end
    if not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end
    if UIS:GetFocusedTextBox() then return end
    local cam = workspace.CurrentCamera
    if not cam or not currentTargetPart then return end
    local goal = CFrame.lookAt(cam.CFrame.Position, currentTargetPart.Position)
    cam.CFrame = cam.CFrame:Lerp(goal, S.aim.smooth)
end)

-- Mode 2: SILENT AIM (Hook __index & __namecall via Xeno Metamethod)
if not genv.VD_SILENT_HOOKED and type(hookmetamethod) == "function" then
    genv.VD_SILENT_HOOKED = true

    -- Hook Mouse.Hit & Mouse.Target
    local oldIndex
    oldIndex = hookmetamethod(game, "__index", function(self, key)
        if not checkcaller() then
            local getTgt = genv.VD_GET_TARGET
            local target = getTgt and getTgt()
            if target and S.aim.mode == "Silent" then
                if typeof(self) == "Instance" and self:IsA("Mouse") then
                    if key == "Hit" or key == "hit" then
                        return CFrame.new(target.Position)
                    elseif key == "Target" or key == "target" then
                        return target
                    end
                end
            end
        end
        return oldIndex(self, key)
    end)

    -- Hook Raycast & FindPartOnRay
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if not checkcaller() then
            local getTgt = genv.VD_GET_TARGET
            local target = getTgt and getTgt()
            if target and S.aim.mode == "Silent" and self == workspace then
                if method == "Raycast" or method == "raycast" then
                    local args = { ... }
                    local origin = args[1]
                    local direction = args[2]
                    if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
                        local mag = direction.Magnitude
                        if mag > 0 then
                            args[2] = (target.Position - origin).Unit * mag
                            return oldNamecall(self, table.unpack(args))
                        end
                    end
                elseif method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
                    local args = { ... }
                    local r = args[1]
                    if typeof(r) == "Ray" then
                        local origin = r.Origin
                        local direction = r.Direction
                        local mag = direction.Magnitude
                        local newDir = (target.Position - origin).Unit * mag
                        args[1] = Ray.new(origin, newDir)
                        return oldNamecall(self, table.unpack(args))
                    end
                end
            end
        end
        return oldNamecall(self, ...)
    end)
end

------------------------------------------------------------------
-- FLUENT WINDOW & TABS
------------------------------------------------------------------
local Window = Fluent:CreateWindow({
    Title = "Violence District",
    SubTitle = "Fluent v3.5 (Anti-Lag Edition)",
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
    Description = "Disarankan 100-150m agar tidak melewati batas 31 Highlight Roblox",
    Default = 120, Min = 0, Max = 400, Rounding = 0,
    Callback = function(v) S.esp.palletDist = v end
})

local EspInfoParagraph = Tabs.ESP:AddParagraph({
    Title = "Info Peta Saat Ini",
    Content = "Memuat data objek..."
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

-- ================= TAB 3: SKILL CHECK (TANPA AUTO-LEARN) =================
local SkSec = Tabs.Skill:AddSection("Auto Skill Check")

local T_SkOn = SkSec:AddToggle("SKC_On", { Title = "Aktifkan Auto Skill Check", Default = true })
T_SkOn:OnChanged(function() SKC.on = Options.SKC_On.Value end)

local D_SkInput = SkSec:AddDropdown("SKC_Input", {
    Title = "Tombol Skill Check",
    Values = INPUT_LIST,
    Multi = false,
    Default = 1,
})
D_SkInput:OnChanged(function(v) SKC.input = v end)

SkSec:AddSlider("SKC_Offset", {
    Title = "Offset (Line - Goal)",
    Description = "Nilai tetap (tidak berubah sendiri)",
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

local AimSec = Tabs.MoveAim:AddSection("Auto Aim & Silent Aim")

local T_AimOn = AimSec:AddToggle("AIM_On", { Title = "Aktifkan Auto Aim", Default = false })
T_AimOn:OnChanged(function() S.aim.on = Options.AIM_On.Value end)

local D_AimMode = AimSec:AddDropdown("AIM_Mode", {
    Title = "Mode Aim",
    Values = { "Silent (Peluru Belok)", "Camera (Lock Kamera)" },
    Multi = false,
    Default = 1,
})
D_AimMode:OnChanged(function(v)
    S.aim.mode = (v == "Camera (Lock Kamera)") and "Camera" or "Silent"
end)

local D_AimTrigger = AimSec:AddDropdown("AIM_Trigger", {
    Title = "Aktivasi Aim",
    Values = { "Selalu Aktif (Dalam FOV)", "Tahan Klik Kanan" },
    Multi = false,
    Default = 1,
})
D_AimTrigger:OnChanged(function(v)
    S.aim.trigger = (v == "Tahan Klik Kanan") and "RightClick" or "Always"
end)

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
    Title = "Smoothness Kamera (Mode Camera Saja)",
    Default = 0.5, Min = 0.05, Max = 1, Rounding = 2,
    Callback = function(v) S.aim.smooth = v end
})

-- ================= TAB 5: VISUAL & LOW MODE =================
local LowSec = Tabs.Visual:AddSection("Fast Low Mode (Tanpa Lag/Freeze)")

local T_LowMode = LowSec:AddToggle("VIS_LowMode", {
    Title = "Aktifkan Fast Low Mode",
    Description = "Matikan bayangan, hujan, kabut & SmartBone secara instan tanpa membebani CPU",
    Default = false
})
T_LowMode:OnChanged(function()
    S.vis.lowMode = Options.VIS_LowMode.Value
    if S.vis.lowMode then
        applyFastLowMode()
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

local D_ColScheme = LowSec:AddDropdown("VIS_ColorScheme", {
    Title = "Pilihan Warna Blok Polos",
    Values = { "Original", "SlateGrey", "DarkGrey", "LightGrey" },
    Multi = false,
    Default = 1,
})
D_ColScheme:OnChanged(function(v)
    S.vis.colorScheme = v
end)

LowSec:AddButton({
    Title = "Ubah Bangunan Jadi Blok Polos 1 Warna (Sekali Klik)",
    Description = "Gunakan saat ronde dimulai untuk menghapus tekstur blok tanpa background lag",
    Callback = function()
        flattenMapBlocksOnce()
    end
})

local VisSec = Tabs.Visual:AddSection("Pencahayaan & Efek")

local T_VisFull = VisSec:AddToggle("VIS_Full", { Title = "Fullbright (Terang & Hapus Kabut)", Default = false })
T_VisFull:OnChanged(function()
    S.vis.full = Options.VIS_Full.Value
    if S.vis.full then
        pcall(lightApply)
    else
        pcall(lightRestore)
    end
end)

local T_VisDark = VisSec:AddToggle("VIS_NoDark", { Title = "Hilangkan Layar Gelap (Darkness GUI)", Default = true })
T_VisDark:OnChanged(function()
    S.vis.noDark = Options.VIS_NoDark.Value
    if not S.vis.noDark then darkRestore() end
end)

VisSec:AddSlider("VIS_Bright", {
    Title = "Tingkat Brightness",
    Default = 2, Min = 0, Max = 6, Rounding = 1,
    Callback = function(v)
        S.vis.bright = v
        if S.vis.full then pcall(lightApply) end
    end
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
    genv.VD_GET_TARGET = nil
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

-- Loop utama diperlambat sedikit (0.3 detik) dan hemat alokasi string
task.spawn(function()
    local lastInfoStr = ""
    local lastSkStr = ""
    local lastTelemetry = 0
    while alive do
        task.wait(0.3)
        pcall(updatePlayersESP)
        pcall(updateObjESP)

        -- Hanya panggil lightApply jika lighting di-reset oleh game
        if S.vis.full and (Lighting.Brightness ~= S.vis.bright or Lighting.ClockTime ~= 14 or Lighting.FogEnd < 1e5) then
            pcall(lightApply)
        end

        local now = os.clock()
        if now - lastTelemetry >= 1.5 then
            lastTelemetry = now
            pcall(function()
                local infoStr = string.format(
                    "Role Kamu: %s  |  Gen: %d  |  Pallet: %d  |  Labu: %d",
                    tostring(roleOf(LP) or "Lobby"),
                    countObjs("gen"),
                    countObjs("pallet"),
                    countObjs("pumpkin")
                )
                if infoStr ~= lastInfoStr then
                    lastInfoStr = infoStr
                    EspInfoParagraph:SetDesc(infoStr)
                end

                local stateStr = st.active
                    and string.format("AKTIF (Goal: %.0f | Line: %.0f | Target: %.0f)", st.goal, st.line, st.goal + SKC.offset)
                    or st.note
                local skStr = string.format(
                    "Tombol: %s  |  Offset: %.1f  |  Speed Jarum: %.0f/dtk  |  Auto Klik: %d\n%s",
                    SKC.input, SKC.offset, st.speed, st.presses, stateStr
                )
                if skStr ~= lastSkStr then
                    lastSkStr = skStr
                    SkStatusParagraph:SetDesc(skStr)
                end
            end)
        end
    end
end)

Window:SelectTab(1)
SaveManager:LoadAutoloadConfig()

Fluent:Notify({
    Title = "Violence District",
    Content = "Fluent Hub v3.6 (Anti-Lag & No-Distance) siap!",
    Duration = 4
})

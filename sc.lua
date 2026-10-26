--[[
=====================================================================
  ViolenceDistrict_Hub.lua  (v3.1 Fixed)
  
  Perbaikan & Fitur:
  - ESP Killer    : Merah + Highlight (Deteksi Tag & Team)
  - ESP Survivor  : Hijau + Highlight (Deteksi Tag, Attribute & Team)
  - ESP Pallet    : Ungu + Highlight (Filter khusus pallet aktif)
  - ESP Generator : Kuning + Highlight + Progress (RepairProgress)
  - ESP Labu      : Cyan + Highlight (Tag "pumpkin" / Folder Pumpkins)
  - Crosshair     : Custom Crosshair di tengah layar (Tab Crosshair)
  - Auto Skill Check, Speed Boost, Fullbright, Auto Aim
=====================================================================
]]

------------------------------------------------------------------
-- BOOT
------------------------------------------------------------------
local CFG = { UI_KEY = Enum.KeyCode.RightShift, CONFIG_FILE = "VD_Hub_Config_v31.json" }

local genv = (type(getgenv) == "function" and getgenv()) or _G
if genv.MAG_VD and type(genv.MAG_VD.destroy) == "function" then
    pcall(genv.MAG_VD.destroy)
end
if genv.VD_ASC and type(genv.VD_ASC.destroy) == "function" then
    pcall(genv.VD_ASC.destroy)
end
if not game:IsLoaded() then game.Loaded:Wait() end

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UIS               = game:GetService("UserInputService")
local Lighting          = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local TweenService      = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")
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

local notify = function() end

local S = {
    esp = {
        killer = true,
        survivor = true,
        gens = true,
        pallets = true,
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
    vis  = { full = false, bright = 2, noDark = true },
    aim  = { on = false, fov = 250, dist = 150, smooth = 0.5, part = "HumanoidRootPart", wall = true },
}

local SKC = { on = true, input = "Space", offset = 115, lead = 0.03, learn = true }
local INPUT_LIST  = { "Space", "Mouse", "E", "F" }
local AIM_PARTS   = { "HumanoidRootPart", "Head", "Torso" }
local CROSS_COLS  = {
    Green  = Color3.fromRGB(0, 255, 120),
    Cyan   = Color3.fromRGB(0, 255, 255),
    Red    = Color3.fromRGB(255, 50, 50),
    Yellow = Color3.fromRGB(255, 230, 50),
    White  = Color3.fromRGB(255, 255, 255),
}

------------------------------------------------------------------
-- HELPER
------------------------------------------------------------------
local function sortedKeys(t)
    local ks = {}
    for k in pairs(t) do ks[#ks + 1] = k end
    table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
    return ks
end

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

local function path(inst)
    local ok, r = pcall(function() return inst:GetFullName() end)
    if ok then return r end
    return tostring(inst)
end

local function fmtv(v)
    local t = typeof(v)
    if t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%.0f", v) end
        return string.format("%.4g", v)
    elseif t == "string" then
        return '"' .. v:gsub("[\r\n]", " "):sub(1, 100) .. '"'
    elseif t == "Vector3" then
        return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
    elseif t == "Instance" then
        return path(v)
    end
    return tostring(v)
end

local function attrLine(inst)
    local ok, a = pcall(function() return inst:GetAttributes() end)
    if not ok then return "" end
    local parts = {}
    for _, k in ipairs(sortedKeys(a)) do parts[#parts + 1] = k .. "=" .. fmtv(a[k]) end
    return table.concat(parts, ", ")
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

local function writeOut(name, lines)
    if type(writefile) ~= "function" then return false end
    return (pcall(writefile, name, table.concat(lines, "\n")))
end

-- Deteksi Role berdasarkan CollectionService Tag, Attribute, dan Team
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

-- Warna ESP sesuai permintaan:
-- 1. Killer (Merah)
-- 2. Survivor (Hijau)
-- 3. Pallet (Ungu)
-- 4. Generator (Kuning)
-- 5. Labu (Cyan)
local COL = {
    killer   = Color3.fromRGB(255, 45, 45),
    survivor = Color3.fromRGB(50, 255, 90),
    pallet   = Color3.fromRGB(190, 80, 255),
    gen      = Color3.fromRGB(255, 230, 40),
    pumpkin  = Color3.fromRGB(0, 255, 255),
}

------------------------------------------------------------------
-- CONFIG (simpan / muat)
------------------------------------------------------------------
local cfgDirty = false
local function markDirty() cfgDirty = true end

local function cfgSave()
    if type(writefile) ~= "function" then return false end
    local data = {
        sk    = { on = SKC.on, input = SKC.input, offset = SKC.offset, lead = SKC.lead, learn = SKC.learn },
        esp   = {
            killer = S.esp.killer, survivor = S.esp.survivor, gens = S.esp.gens,
            pallets = S.esp.pallets, pumpkins = S.esp.pumpkins,
            hideDone = S.esp.hideDone, fill = S.esp.fill, maxDist = S.esp.maxDist, palletDist = S.esp.palletDist
        },
        cross = { on = S.cross.on, dot = S.cross.dot, size = S.cross.size, gap = S.cross.gap, thick = S.cross.thick, color = S.cross.color },
        move  = { mode = S.move.mode, ws = S.move.ws, cf = S.move.cf },
        vis   = { bright = S.vis.bright, noDark = S.vis.noDark },
        aim   = { fov = S.aim.fov, dist = S.aim.dist, smooth = S.aim.smooth, part = S.aim.part, wall = S.aim.wall },
    }
    local ok, js = pcall(function() return HttpService:JSONEncode(data) end)
    if not ok then return false end
    return (pcall(writefile, CFG.CONFIG_FILE, js))
end

local function setNum(tbl, key, v, lo, hi)
    if type(v) == "number" then tbl[key] = math.clamp(v, lo, hi) end
end
local function setBool(tbl, key, v)
    if type(v) == "boolean" then tbl[key] = v end
end

local function cfgLoad()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return end
    local ok, js = pcall(function()
        if not isfile(CFG.CONFIG_FILE) then return nil end
        return readfile(CFG.CONFIG_FILE)
    end)
    if not ok or not js then return end
    local ok2, t = pcall(function() return HttpService:JSONDecode(js) end)
    if not ok2 or type(t) ~= "table" then return end
    if type(t.sk) == "table" then
        setBool(SKC, "on", t.sk.on)
        setBool(SKC, "learn", t.sk.learn)
        setNum(SKC, "offset", t.sk.offset, 40, 200)
        setNum(SKC, "lead", t.sk.lead, 0, 0.3)
        if type(t.sk.input) == "string" and inList(t.sk.input, INPUT_LIST) then SKC.input = t.sk.input end
    end
    if type(t.esp) == "table" then
        setBool(S.esp, "killer", t.esp.killer)
        setBool(S.esp, "survivor", t.esp.survivor)
        setBool(S.esp, "gens", t.esp.gens)
        setBool(S.esp, "pallets", t.esp.pallets)
        setBool(S.esp, "pumpkins", t.esp.pumpkins)
        setBool(S.esp, "hideDone", t.esp.hideDone)
        setBool(S.esp, "fill", t.esp.fill)
        setNum(S.esp, "maxDist", t.esp.maxDist, 0, 1000)
        setNum(S.esp, "palletDist", t.esp.palletDist, 0, 1000)
    end
    if type(t.cross) == "table" then
        setBool(S.cross, "on", t.cross.on)
        setBool(S.cross, "dot", t.cross.dot)
        setNum(S.cross, "size", t.cross.size, 2, 30)
        setNum(S.cross, "gap", t.cross.gap, 0, 25)
        setNum(S.cross, "thick", t.cross.thick, 1, 8)
        if type(t.cross.color) == "string" and CROSS_COLS[t.cross.color] then S.cross.color = t.cross.color end
    end
    if type(t.move) == "table" then
        if t.move.mode == "WalkSpeed" or t.move.mode == "CFrame" then S.move.mode = t.move.mode end
        setNum(S.move, "ws", t.move.ws, 1, 200)
        setNum(S.move, "cf", t.move.cf, 0, 100)
    end
    if type(t.vis) == "table" then
        setNum(S.vis, "bright", t.vis.bright, 0, 10)
        setBool(S.vis, "noDark", t.vis.noDark)
    end
    if type(t.aim) == "table" then
        setNum(S.aim, "fov", t.aim.fov, 20, 2000)
        setNum(S.aim, "dist", t.aim.dist, 5, 1000)
        setNum(S.aim, "smooth", t.aim.smooth, 0.05, 1)
        setBool(S.aim, "wall", t.aim.wall)
        if type(t.aim.part) == "string" and inList(t.aim.part, AIM_PARTS) then S.aim.part = t.aim.part end
    end
end

cfgLoad()

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
-- ESP: kontainer & label ringkas
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

------------------------------------------------------------------
-- ESP: pemain (Killer & Survivor)
------------------------------------------------------------------
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

------------------------------------------------------------------
-- ESP: Generator, Pallet & Labu (Pumpkin)
------------------------------------------------------------------
local OBJ = { gen = {}, pallet = {}, pumpkin = {} }
local objEsp = {}
local scanDone = false

local function classify(inst)
    if not (inst:IsA("Model") or inst:IsA("BasePart")) then return nil end

    -- 1. Generator
    if CollectionService:HasTag(inst, "Generator") then return "gen" end
    if inst:IsA("Model") and inst.Name == "Generator" and inst.Parent and inst.Parent.Name == "Generators" then
        return "gen"
    end

    -- 2. Pallet
    if CollectionService:HasTag(inst, "pallet") then return "pallet" end
    if inst.Parent and inst.Parent.Name:lower() == "pallets" then return "pallet" end

    -- 3. Labu (Pumpkin)
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
-- SKILL: auto skill check
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
    presses = 0, samples = {}, note = "",
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
        st.note = string.format("terakhir: auto klik di line %.0f (target %.0f)", st.pressLine, st.pressTarget)
        return
    end
    if SKC.learn and st.cand and (now - st.candT) < 0.45 then
        if inList(st.cand, INPUT_LIST) then SKC.input = st.cand end
        local d = st.line - st.goal
        if d > 85 and d < 145 then
            st.samples[#st.samples + 1] = d
            if #st.samples > 8 then table.remove(st.samples, 1) end
            SKC.offset = median(st.samples) or SKC.offset
            st.note = string.format("belajar: klik manual di Goal+%.0f, offset jadi %.1f", d, SKC.offset)
            markDirty()
            notify(string.format("Offset dipelajari: %.1f (%d sampel)", SKC.offset, #st.samples), Color3.fromRGB(70, 200, 120))
        else
            st.note = string.format("input '%s' dipelajari (Goal+%.0f di luar rentang, diabaikan)", st.cand, d)
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
    if not ok then st.note = "error di loop skill check" end
end))

------------------------------------------------------------------
-- VISUAL: fullbright
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
-- MOVE: speed boost
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

------------------------------------------------------------------
-- AIM: auto aim saat klik kanan ditahan
------------------------------------------------------------------
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
-- DEBUG: dump
------------------------------------------------------------------
local function dumpDebug()
    local out = {}
    out[#out + 1] = "VD debug " .. os.date("%Y-%m-%d %H:%M:%S")
    out[#out + 1] = "Role kamu: " .. tostring(roleOf(LP))
    for _, plr in ipairs(Players:GetPlayers()) do
        out[#out + 1] = string.format("  player %s role=%s", plr.Name, tostring(roleOf(plr)))
    end
    out[#out + 1] = string.format(
        "Terdeteksi: generator=%d pallet=%d labu=%d (scan selesai=%s)",
        countObjs("gen"), countObjs("pallet"), countObjs("pumpkin"), tostring(scanDone)
    )
    return writeOut("VD_Debug.txt", out)
end

------------------------------------------------------------------
-- GUI: tema & komponen
------------------------------------------------------------------
local T = {
    bg     = Color3.fromRGB(15, 16, 22),
    side   = Color3.fromRGB(19, 20, 28),
    card   = Color3.fromRGB(25, 27, 37),
    card2  = Color3.fromRGB(36, 39, 53),
    stroke = Color3.fromRGB(46, 50, 68),
    accent = Color3.fromRGB(235, 65, 85),
    text   = Color3.fromRGB(235, 237, 245),
    sub    = Color3.fromRGB(150, 155, 175),
    on     = Color3.fromRGB(70, 200, 120),
    off    = Color3.fromRGB(70, 74, 92),
    warn   = Color3.fromRGB(255, 190, 70),
}

local function newInst(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local function corner(inst, r)
    return newInst("UICorner", { CornerRadius = UDim.new(0, r or 6) }, inst)
end

local function stroke(inst, col, th)
    return newInst("UIStroke", { Color = col or T.stroke, Thickness = th or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, inst)
end

local function tween(inst, props, t)
    pcall(function()
        TweenService:Create(inst, TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
    end)
end

local function txt(parent, props)
    local d = {
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12,
        TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
    }
    for k, v in pairs(props) do d[k] = v end
    return newInst("TextLabel", d, parent)
end

local gui = Instance.new("ScreenGui")
gui.Name = "MAG_VD_Hub"
gui.ResetOnSpawn = false
gui.DisplayOrder = 998
mount(gui)

local WIN_W, WIN_H, HEAD_H, FOOT_H, SIDE_W = 600, 440, 40, 26, 130

local win = newInst("Frame", {
    Name = "Win", Size = UDim2.new(0, WIN_W, 0, WIN_H), Position = UDim2.new(0, 30, 0.5, -WIN_H / 2),
    BackgroundColor3 = T.bg, BorderSizePixel = 0, ClipsDescendants = true,
}, gui)
corner(win, 10)
stroke(win, T.stroke, 1)

local header = newInst("Frame", { Size = UDim2.new(1, 0, 0, HEAD_H), BackgroundColor3 = T.side, BorderSizePixel = 0 }, win)
local accentBar = newInst("Frame", { Size = UDim2.new(0, 3, 0, 18), Position = UDim2.new(0, 12, 0.5, -9), BackgroundColor3 = T.accent, BorderSizePixel = 0 }, header)
corner(accentBar, 2)
txt(header, { Size = UDim2.new(0, 240, 0, 18), Position = UDim2.new(0, 24, 0, 5), Text = "VIOLENCE DISTRICT", Font = Enum.Font.GothamBold, TextSize = 13 })
txt(header, { Size = UDim2.new(0, 280, 0, 14), Position = UDim2.new(0, 24, 0, 22), Text = "Hub v3.1  -  RightShift = sembunyi", TextSize = 10, TextColor3 = T.sub })

local bodyFrame = newInst("Frame", {
    Position = UDim2.new(0, 0, 0, HEAD_H), Size = UDim2.new(1, 0, 1, -HEAD_H), BackgroundTransparency = 1,
}, win)

local minimized = false
local function headerBtn(text, x, cb)
    local b = newInst("TextButton", {
        Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(1, x, 0.5, -13), BackgroundColor3 = T.card2,
        AutoButtonColor = false, Text = text, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = T.text, BorderSizePixel = 0,
    }, header)
    corner(b, 6)
    b.MouseEnter:Connect(function() tween(b, { BackgroundColor3 = T.accent }, 0.1) end)
    b.MouseLeave:Connect(function() tween(b, { BackgroundColor3 = T.card2 }, 0.1) end)
    b.MouseButton1Click:Connect(cb)
    return b
end

local hub = {}
local function destroyHub()
    alive = false
    pcall(cfgSave)
    S.vis.full = false
    S.move.on = false
    S.aim.on = false
    SKC.on = false
    pcall(lightRestore)
    pcall(function() RunService:UnbindFromRenderStep("MAG_VD_Aim") end)
    pcall(clearPlayersESP)
    pcall(clearObjESP)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(function() gui:Destroy() end)
    pcall(function() crossGui:Destroy() end)
    pcall(function() espFolder:Destroy() end)
    if genv.MAG_VD == hub then genv.MAG_VD = nil end
end
hub.destroy = destroyHub

headerBtn("x", -34, destroyHub)
headerBtn("-", -66, function()
    minimized = not minimized
    if minimized then
        bodyFrame.Visible = false
        tween(win, { Size = UDim2.new(0, WIN_W, 0, HEAD_H) }, 0.15)
    else
        tween(win, { Size = UDim2.new(0, WIN_W, 0, WIN_H) }, 0.15)
        task.delay(0.1, function() bodyFrame.Visible = true end)
    end
end)

do
    local dragging, dragStart, startPos = false, nil, nil
    header.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = i.Position
            startPos = win.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    track(UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
end

local sidebar = newInst("Frame", {
    Size = UDim2.new(0, SIDE_W, 1, -FOOT_H), BackgroundColor3 = T.side, BorderSizePixel = 0,
}, bodyFrame)
newInst("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, sidebar)
newInst("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, sidebar)

local content = newInst("Frame", {
    Position = UDim2.new(0, SIDE_W, 0, 0), Size = UDim2.new(1, -SIDE_W, 1, -FOOT_H), BackgroundTransparency = 1,
}, bodyFrame)

local footer = newInst("Frame", {
    Position = UDim2.new(0, 0, 1, -FOOT_H), Size = UDim2.new(1, 0, 0, FOOT_H), BackgroundColor3 = T.side, BorderSizePixel = 0,
}, bodyFrame)
local footLbl = txt(footer, {
    Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 10, 0, 0), RichText = true, TextSize = 11, TextColor3 = T.sub, Text = "",
})

local TAB_NAMES  = { "ESP", "Crosshair", "Skill", "Move", "Visual", "Aim", "Config" }
local TAB_LABELS = {
    ESP = "ESP", Crosshair = "Crosshair", Skill = "Auto Skill Check",
    Move = "Speed", Visual = "Visual", Aim = "Auto Aim", Config = "Config"
}
local pages, tabBtns = {}, {}

local function selectTab(name)
    for n, p in pairs(pages) do p.Visible = (n == name) end
    for n, b in pairs(tabBtns) do
        local active = (n == name)
        tween(b.btn, { BackgroundColor3 = active and T.card2 or T.side }, 0.1)
        b.lbl.TextColor3 = active and T.text or T.sub
        b.ind.Visible = active
    end
end

for i, name in ipairs(TAB_NAMES) do
    local b = newInst("TextButton", {
        Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = T.side, AutoButtonColor = false, Text = "",
        BorderSizePixel = 0, LayoutOrder = i,
    }, sidebar)
    corner(b, 6)
    local ind = newInst("Frame", { Size = UDim2.new(0, 3, 0, 16), Position = UDim2.new(0, 0, 0.5, -8), BackgroundColor3 = T.accent, BorderSizePixel = 0, Visible = false }, b)
    corner(ind, 2)
    local l = txt(b, { Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 14, 0, 0), Text = TAB_LABELS[name], Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.sub })
    tabBtns[name] = { btn = b, lbl = l, ind = ind }
    b.MouseButton1Click:Connect(function() selectTab(name) end)

    local pg = newInst("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = T.stroke, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    }, content)
    newInst("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 12) }, pg)
    newInst("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, pg)
    pages[name] = pg
end

-- komponen UI
local function mkCard(page, title)
    local card = newInst("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.card, BorderSizePixel = 0,
    }, page)
    corner(card, 8)
    stroke(card, T.stroke, 1)
    newInst("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, card)
    newInst("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, card)
    if title then
        txt(card, { Size = UDim2.new(1, 0, 0, 14), Text = string.upper(title), Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = T.accent })
    end
    return card
end

local function mkNote(card, text, h)
    return txt(card, {
        Size = UDim2.new(1, 0, 0, h or 28), Text = text, TextWrapped = true, RichText = true,
        TextSize = 11, TextColor3 = T.sub, TextYAlignment = Enum.TextYAlignment.Top,
    })
end

local function mkToggle(card, text, default, cb)
    local state = default and true or false
    local row = newInst("TextButton", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, card)
    txt(row, { Size = UDim2.new(1, -50, 1, 0), Text = text })
    local sw = newInst("Frame", { Size = UDim2.new(0, 36, 0, 18), Position = UDim2.new(1, -36, 0.5, -9), BackgroundColor3 = T.off, BorderSizePixel = 0 }, row)
    corner(sw, 9)
    local knob = newInst("Frame", { Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 2, 0.5, -7), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, sw)
    corner(knob, 7)
    local function render(anim)
        local pos = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        local col = state and T.on or T.off
        if anim then
            tween(knob, { Position = pos }, 0.12)
            tween(sw, { BackgroundColor3 = col }, 0.12)
        else
            knob.Position = pos
            sw.BackgroundColor3 = col
        end
    end
    row.MouseButton1Click:Connect(function()
        state = not state
        render(true)
        cb(state)
    end)
    render(false)
    return {
        set = function(v)
            state = v and true or false
            render(true)
        end,
        get = function() return state end,
    }
end

local function mkSlider(card, label, lo, hi, default, step, fmtFn, cb)
    local row = newInst("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 }, card)
    txt(row, { Size = UDim2.new(0.6, 0, 0, 16), Text = label })
    local val = txt(row, {
        Size = UDim2.new(0.4, 0, 0, 16), Position = UDim2.new(0.6, 0, 0, 0), Text = "", Font = Enum.Font.GothamBold,
        TextColor3 = T.accent, TextXAlignment = Enum.TextXAlignment.Right,
    })
    local trk = newInst("Frame", { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0, 26), BackgroundColor3 = T.card2, BorderSizePixel = 0 }, row)
    corner(trk, 3)
    local fill = newInst("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = T.accent, BorderSizePixel = 0 }, trk)
    corner(fill, 3)
    local knob = newInst("Frame", { Size = UDim2.new(0, 12, 0, 12), Position = UDim2.new(0, -6, 0.5, -6), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2 }, trk)
    corner(knob, 6)
    local hit = newInst("TextButton", { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 16), BackgroundTransparency = 1, Text = "", ZIndex = 3 }, row)
    local value = default
    local dragging = false
    local function apply(v)
        v = math.clamp(math.floor(v / step + 0.5) * step, lo, hi)
        value = v
        local a = (hi > lo) and ((v - lo) / (hi - lo)) or 0
        fill.Size = UDim2.new(a, 0, 1, 0)
        knob.Position = UDim2.new(a, -6, 0.5, -6)
        val.Text = fmtFn(v)
    end
    local function fromX(x)
        local w = trk.AbsoluteSize.X
        if w <= 0 then return end
        local a = math.clamp((x - trk.AbsolutePosition.X) / w, 0, 1)
        apply(lo + (hi - lo) * a)
        cb(value)
    end
    hit.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            fromX(i.Position.X)
        end
    end)
    track(UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            fromX(i.Position.X)
        end
    end))
    track(UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    apply(default)
    return {
        set = function(v)
            if not dragging then apply(v) end
        end,
        get = function() return value end,
    }
end

local function mkSegment(card, label, options, default, cb)
    local wrap = newInst("Frame", { Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1 }, card)
    txt(wrap, { Size = UDim2.new(1, 0, 0, 16), Text = label, TextSize = 11, TextColor3 = T.sub })
    local bar = newInst("Frame", { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 20), BackgroundColor3 = T.card2, BorderSizePixel = 0 }, wrap)
    corner(bar, 6)
    local btns = {}
    local cur = default
    local n = #options
    local function render()
        for _, o in ipairs(options) do
            local b = btns[o.value]
            if o.value == cur then
                b.BackgroundColor3 = T.accent
                b.TextColor3 = Color3.new(1, 1, 1)
            else
                b.BackgroundColor3 = T.card2
                b.TextColor3 = T.sub
            end
        end
    end
    for i, o in ipairs(options) do
        local b = newInst("TextButton", {
            Size = UDim2.new(1 / n, -4, 1, -4), Position = UDim2.new((i - 1) / n, 2, 0, 2), BackgroundColor3 = T.card2,
            AutoButtonColor = false, Text = o.label, Font = Enum.Font.GothamMedium, TextSize = 11, TextColor3 = T.sub, BorderSizePixel = 0,
        }, bar)
        corner(b, 5)
        btns[o.value] = b
        b.MouseButton1Click:Connect(function()
            cur = o.value
            render()
            cb(o.value)
        end)
    end
    render()
    return {
        set = function(v)
            if btns[v] then
                cur = v
                render()
            end
        end,
        get = function() return cur end,
    }
end

local function mkButton(card, text, cb, primary)
    local base = primary and T.accent or T.card2
    local hover = base:Lerp(Color3.new(1, 1, 1), 0.12)
    local b = newInst("TextButton", {
        Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = base, AutoButtonColor = false, Text = text,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text, BorderSizePixel = 0,
    }, card)
    corner(b, 6)
    b.MouseEnter:Connect(function() tween(b, { BackgroundColor3 = hover }, 0.1) end)
    b.MouseLeave:Connect(function() tween(b, { BackgroundColor3 = base }, 0.1) end)
    b.MouseButton1Click:Connect(function() cb(b) end)
    return b
end

local function mkLegend(card, items)
    local row = newInst("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1 }, card)
    newInst("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Center,
    }, row)
    for _, it in ipairs(items) do
        local chip = newInst("Frame", { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, row)
        newInst("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Center,
        }, chip)
        local dot = newInst("Frame", { Size = UDim2.new(0, 10, 0, 10), BackgroundColor3 = it.color, BorderSizePixel = 0 }, chip)
        corner(dot, 5)
        txt(chip, { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = it.text, TextSize = 11, TextColor3 = T.sub })
    end
end

-- toast
local toastHolder = newInst("Frame", {
    Size = UDim2.new(0, 280, 1, 0), Position = UDim2.new(1, -292, 0, 0), BackgroundTransparency = 1,
}, gui)
newInst("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, toastHolder)
newInst("UIPadding", { PaddingBottom = UDim.new(0, 18) }, toastHolder)

notify = function(text, color)
    if not alive then return end
    local f = newInst("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.card, BackgroundTransparency = 1, BorderSizePixel = 0 }, toastHolder)
    corner(f, 6)
    local s = stroke(f, color or T.accent, 1)
    s.Transparency = 1
    local l = txt(f, { Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 10, 0, 0), Text = text, TextTransparency = 1 })
    tween(f, { BackgroundTransparency = 0 }, 0.15)
    tween(s, { Transparency = 0 }, 0.15)
    tween(l, { TextTransparency = 0 }, 0.15)
    task.delay(2.6, function()
        if f.Parent then
            tween(f, { BackgroundTransparency = 1 }, 0.2)
            tween(s, { Transparency = 1 }, 0.2)
            tween(l, { TextTransparency = 1 }, 0.2)
            task.delay(0.25, function() pcall(function() f:Destroy() end) end)
        end
    end)
end

------------------------------------------------------------------
-- GUI: isi halaman
------------------------------------------------------------------
local function fmtInt(v) return string.format("%.0f", v) end
local function fmtDist(v) return (v <= 0) and "semua" or (string.format("%.0f", v) .. " st") end

-- ===== ESP =====
local pE = pages["ESP"]
local cTarget = mkCard(pE, "Target ESP")
local espToggles = {}
espToggles[#espToggles + 1] = { key = "killer",   t = mkToggle(cTarget, "1. Killer (Merah + Highlight)", S.esp.killer, function(v) S.esp.killer = v; markDirty() end) }
espToggles[#espToggles + 1] = { key = "survivor", t = mkToggle(cTarget, "2. Survivor (Hijau + Highlight)", S.esp.survivor, function(v) S.esp.survivor = v; markDirty() end) }
espToggles[#espToggles + 1] = { key = "pallets",  t = mkToggle(cTarget, "3. Pallet (Ungu + Highlight)", S.esp.pallets, function(v) S.esp.pallets = v; markDirty() end) }
espToggles[#espToggles + 1] = { key = "gens",     t = mkToggle(cTarget, "4. Generator (Kuning + Highlight + Progress)", S.esp.gens, function(v) S.esp.gens = v; markDirty() end) }
espToggles[#espToggles + 1] = { key = "pumpkins", t = mkToggle(cTarget, "5. Labu / Pumpkin (Cyan + Highlight)", S.esp.pumpkins, function(v) S.esp.pumpkins = v; markDirty() end) }

do
    local allOn = true
    mkButton(cTarget, "Nyalakan / matikan semua ESP", function()
        allOn = not allOn
        for _, it in ipairs(espToggles) do
            S.esp[it.key] = allOn
            it.t.set(allOn)
        end
        markDirty()
    end, true)
end
mkLegend(cTarget, {
    { color = COL.killer,   text = "Killer" },
    { color = COL.survivor, text = "Survivor" },
    { color = COL.pallet,   text = "Pallet" },
    { color = COL.gen,      text = "Generator" },
    { color = COL.pumpkin,  text = "Labu" },
})

local cShow = mkCard(pE, "Tampilan ESP")
mkToggle(cShow, "Sembunyikan generator selesai (100%)", S.esp.hideDone, function(v) S.esp.hideDone = v; markDirty() end)
mkToggle(cShow, "Isi warna Highlight (Fill Color)", S.esp.fill, function(v) S.esp.fill = v; markDirty() end)
mkSlider(cShow, "Jarak maks Pemain, Gen & Labu", 0, 500, S.esp.maxDist, 10, fmtDist, function(v) S.esp.maxDist = v; markDirty() end)
mkSlider(cShow, "Jarak maks Pallet", 0, 400, S.esp.palletDist, 10, fmtDist, function(v) S.esp.palletDist = v; markDirty() end)

-- ===== CROSSHAIR =====
local pCr = pages["Crosshair"]
local cCr = mkCard(pCr, "Pengaturan Crosshair")
mkToggle(cCr, "Tampilkan Crosshair", S.cross.on, function(v) S.cross.on = v; updateCrosshair(); markDirty() end)
mkToggle(cCr, "Titik tengah (Center Dot)", S.cross.dot, function(v) S.cross.dot = v; updateCrosshair(); markDirty() end)
mkSegment(cCr, "Warna Crosshair", {
    { label = "Hijau", value = "Green" },
    { label = "Cyan",  value = "Cyan" },
    { label = "Merah", value = "Red" },
    { label = "Kuning", value = "Yellow" },
    { label = "Putih", value = "White" },
}, S.cross.color, function(v) S.cross.color = v; updateCrosshair(); markDirty() end)
mkSlider(cCr, "Panjang garis (Size)", 2, 25, S.cross.size, 1, fmtInt, function(v) S.cross.size = v; updateCrosshair(); markDirty() end)
mkSlider(cCr, "Celah tengah (Gap)", 0, 20, S.cross.gap, 1, fmtInt, function(v) S.cross.gap = v; updateCrosshair(); markDirty() end)
mkSlider(cCr, "Ketebalan (Thickness)", 1, 6, S.cross.thick, 1, fmtInt, function(v) S.cross.thick = v; updateCrosshair(); markDirty() end)

-- ===== SKILL =====
local pS = pages["Skill"]
local cSk = mkCard(pS, "Auto skill check")
mkToggle(cSk, "Auto skill check", SKC.on, function(v) SKC.on = v; markDirty() end)
mkToggle(cSk, "Belajar tombol & offset dari klik manual", SKC.learn, function(v) SKC.learn = v; markDirty() end)
local inputSeg = mkSegment(cSk, "Tombol yang ditekan", {
    { label = "Space", value = "Space" }, { label = "Klik", value = "Mouse" },
    { label = "E", value = "E" }, { label = "F", value = "F" },
}, SKC.input, function(v) SKC.input = v; markDirty() end)

local cAdj = mkCard(pS, "Penyesuaian")
local offsetSlider = mkSlider(cAdj, "Offset (Line - Goal)", 60, 170, SKC.offset, 0.5, function(v) return string.format("%.1f", v) end, function(v)
    SKC.offset = v
    st.samples = {}
    markDirty()
end)
local leadSlider = mkSlider(cAdj, "Lead (kompensasi lag)", 0, 0.15, SKC.lead, 0.005, function(v) return string.format("%.3f dtk", v) end, function(v)
    SKC.lead = v
    markDirty()
end)
mkButton(cAdj, "Reset offset ke 115", function()
    SKC.offset = 115
    st.samples = {}
    offsetSlider.set(115)
    markDirty()
    notify("Offset dikembalikan ke 115", T.warn)
end)

local cStat = mkCard(pS, "Status")
local skStatus = txt(cStat, {
    Size = UDim2.new(1, 0, 0, 74), RichText = true, TextWrapped = true, Font = Enum.Font.Code, TextSize = 11,
    TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = T.text, Text = "...",
})

-- ===== MOVE =====
local pMv = pages["Move"]
local cMv = mkCard(pMv, "Speed boost")
mkToggle(cMv, "Speed boost", S.move.on, function(v) S.move.on = v end)
mkSegment(cMv, "Mode", { { label = "WalkSpeed", value = "WalkSpeed" }, { label = "CFrame", value = "CFrame" } }, S.move.mode, function(v)
    S.move.mode = v
    markDirty()
end)
mkSlider(cMv, "WalkSpeed (mode WalkSpeed)", 8, 120, S.move.ws, 1, fmtInt, function(v) S.move.ws = v; markDirty() end)
mkSlider(cMv, "Tambahan studs/dtk (mode CFrame)", 0, 60, S.move.cf, 1, fmtInt, function(v) S.move.cf = v; markDirty() end)

-- ===== VISUAL =====
local pV = pages["Visual"]
local cVis = mkCard(pV, "Fullbright")
mkToggle(cVis, "Fullbright (terang & bersih)", S.vis.full, function(v)
    S.vis.full = v
    if not v then lightRestore() end
end)
mkSlider(cVis, "Brightness", 0, 6, S.vis.bright, 0.1, function(v) return string.format("%.1f", v) end, function(v) S.vis.bright = v; markDirty() end)
mkToggle(cVis, "Hilangkan layar gelap (Darkness GUI)", S.vis.noDark, function(v)
    S.vis.noDark = v
    if not v then darkRestore() end
    markDirty()
end)

-- ===== AIM =====
local pA = pages["Aim"]
local cAim = mkCard(pA, "Auto aim")
mkToggle(cAim, "Auto aim (tahan klik kanan)", S.aim.on, function(v) S.aim.on = v end)
mkSegment(cAim, "Bagian target", {
    { label = "Badan", value = "HumanoidRootPart" }, { label = "Kepala", value = "Head" }, { label = "Torso", value = "Torso" },
}, S.aim.part, function(v) S.aim.part = v; markDirty() end)
mkSlider(cAim, "Radius FOV", 50, 800, S.aim.fov, 10, function(v) return string.format("%.0f px", v) end, function(v) S.aim.fov = v; markDirty() end)
mkSlider(cAim, "Jarak maks", 20, 500, S.aim.dist, 10, function(v) return string.format("%.0f st", v) end, function(v) S.aim.dist = v; markDirty() end)
mkSlider(cAim, "Kehalusan (1 = snap)", 0.05, 1, S.aim.smooth, 0.05, function(v) return string.format("%.2f", v) end, function(v) S.aim.smooth = v; markDirty() end)
mkToggle(cAim, "Abaikan target di balik tembok", S.aim.wall, function(v) S.aim.wall = v; markDirty() end)

-- ===== CONFIG =====
local pC = pages["Config"]
local cCfg = mkCard(pC, "Pengaturan")
mkButton(cCfg, "Simpan config sekarang", function()
    notify(cfgSave() and "Config disimpan" or "Gagal menyimpan", T.on)
end, true)
local cDbg = mkCard(pC, "Debug")
mkButton(cDbg, "Dump generator, pallet & labu -> VD_Debug.txt", function()
    task.spawn(function()
        notify(dumpDebug() and "Dump ditulis ke VD_Debug.txt" or "Gagal menulis file", T.warn)
    end)
end)

------------------------------------------------------------------
-- LOOP UI & ESP
------------------------------------------------------------------
task.spawn(function()
    while alive do
        task.wait(0.25)
        pcall(updatePlayersESP)
        pcall(updateObjESP)

        offsetSlider.set(SKC.offset)
        leadSlider.set(SKC.lead)
        inputSeg.set(SKC.input)

        local l1 = string.format("Tombol: %s   Offset: %.1f (%d sampel)", SKC.input, SKC.offset, #st.samples)
        local l2 = string.format("Speed jarum: %.0f/dtk   Auto klik: %d", st.speed, st.presses)
        local l3
        if st.active then
            l3 = string.format('<font color="#46C878">AKTIF</font>  goal=%.0f line=%.0f target=%.0f', st.goal, st.line, st.goal + SKC.offset)
        else
            l3 = '<font color="#969BAF">menunggu skill check...</font>'
            if st.note ~= "" then l3 = l3 .. "\n" .. st.note end
        end
        skStatus.Text = l1 .. "\n" .. l2 .. "\n" .. l3

        footLbl.Text = string.format(
            "Role: %s   |   Gen: %d   |   Pallet: %d   |   Labu: %d%s",
            tostring(roleOf(LP) or "-"), countObjs("gen"), countObjs("pallet"), countObjs("pumpkin"),
            scanDone and "" or "   (scanning...)"
        )
    end
end)

task.spawn(function()
    while alive do
        task.wait(2)
        if cfgDirty then
            cfgDirty = false
            cfgSave()
        end
    end
end)

track(UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == CFG.UI_KEY then win.Visible = not win.Visible end
end))

genv.MAG_VD = hub
selectTab("ESP")
print("[VD Hub v3.1] Siap. RightShift = sembunyikan/tampilkan window.")

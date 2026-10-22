--==============================================================================
--  SMPWORK  ·  MinimaHub  ·  Xeno Executor Build
--  A compact, draggable overlay ("small screen") UI in the style of Delta.
--
--  Credits : Akram Abbaoui  &  Amjad Nejjari
--  Project : SMPWORK (a clean-room build of MinimaHub)
--  Target  : Xeno (Luau) executor
--  Needs   : Drawing API, writefile/readfile, queue_on_teleport (optional)
--
--  Hosting : publish this file to GitHub and point SELF_URL at the raw URL.
--            The loader (loader.lua) fetches and runs this exact file.
--
--  Disclaimer: educational / testing only. Modifying the game client breaks
--  the Roblox Terms of Service and can get your account banned.
--==============================================================================

--------------------------------------------------------------------------------
-- 0. SOURCE / METADATA
--------------------------------------------------------------------------------

local AUTHOR_A   = "Akram Abbaoui"
local AUTHOR_B   = "Amjad Nejjari"
local PROJECT    = "SMPWORK"
local VERSION    = "1.3.0"
local CONFIG_FILE = "SMPWORK.json"

-- Raw URL of THIS file on GitHub (used by "AUTO REATTACH" and "CHECK FOR
-- UPDATES"). You normally do not have to edit it: loader.lua downloads this
-- file and hands over the URL it used in getgenv().SMPWORK_URL. If you paste
-- this file directly into the executor, replace YOUR_USER with your GitHub
-- username (repo "Fortoo").
local SELF_URL   = "https://raw.githubusercontent.com/YOUR_USER/Fortoo/main/SMPWORK.lua"
do
    -- take the URL the loader used, when there is one
    local ok, env = pcall(function()
        if type(getgenv) == "function" then return getgenv() end
        return _G
    end)
    local injected = ok and type(env) == "table" and (env.SMPWORK_URL or env.SMPWORK_SELF_URL)
    if type(injected) == "string" and #injected > 0 then
        SELF_URL = injected
    end
end

-- Photo shown inside the circular "bubble" mode.
-- Put an rbxassetid://... (or rbxthumb://...) URL of the team photo here.
-- Left empty, the bubble shows the local player's Roblox avatar instead.
local TEAM_PHOTO = ""

--------------------------------------------------------------------------------
-- 1. SERVICES / ENVIRONMENT
--------------------------------------------------------------------------------

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local Http       = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer

-- Forward declarations so the closures below can reference them.
local Page    = nil
local Window  = nil
local Cleanup = nil

local function getCamera()
    return workspace.CurrentCamera
end

-- The image used by the round bubble: the team photo when one is configured,
-- otherwise the player's own avatar headshot (always available, no upload).
local function teamPhotoUrl()
    if TEAM_PHOTO ~= "" then return TEAM_PHOTO end
    local id = LocalPlayer and LocalPlayer.UserId
    if id and id > 0 then
        return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(id) .. "&w=150&h=150"
    end
    return ""
end

-- Where do we parent our GUI? Prefer the executor's own HUD, fall back to CoreGui.
local function resolveGuiParent()
    if type(gethui) == "function" then
        local ok, gui = pcall(gethui)
        if ok and gui then return gui end
    end
    local ok, core = pcall(function() return game:GetService("CoreGui") end)
    if ok and core then return core end
    return LocalPlayer:WaitForChild("PlayerGui")
end

-- HTTP helper: executors expose different globals *and* different calling
-- conventions. Most take a table (syn/request style), a few take a bare URL.
local function httpGet(url)
    local function extract(res)
        if type(res) == "string" and #res > 0 then return res end
        if type(res) == "table" then
            local body = res.Body or res.body
            if type(body) == "string" and #body > 0 then return body end
        end
        return nil
    end

    local candidates = {}
    for _, name in ipairs({ "request", "http_request", "syn_request" }) do
        local fn = rawget(_G, name)
        if type(fn) == "function" then candidates[#candidates + 1] = fn end
    end
    if type(syn) == "table" and type(syn.request) == "function" then
        candidates[#candidates + 1] = syn.request
    end
    candidates[#candidates + 1] = function(target) return game:HttpGet(target) end

    for _, fn in ipairs(candidates) do
        -- 1. table form: the common executor signature
        local ok, res = pcall(fn, { Url = url, Method = "GET" })
        local body = ok and extract(res)
        if body then return body end

        -- 2. bare URL form
        ok, res = pcall(fn, url)
        body = ok and extract(res)
        if body then return body end
    end
    return nil
end

-- Mouse position in *viewport* space (matches Camera:WorldToViewportPoint).
local function mouseViewport()
    local m = UIS:GetMouseLocation()
    local ok, inset = pcall(function() return GuiService:GetGuiInset() end)
    if ok and inset then return m - inset end
    return m
end

-- Mouse position in *screen* space (matches the Drawing API).
local function mouseScreen()
    return UIS:GetMouseLocation()
end

--------------------------------------------------------------------------------
-- 2. THEME
--------------------------------------------------------------------------------

local Theme = {
    bg        = Color3.fromRGB(16, 17, 22),
    bgAlt     = Color3.fromRGB(22, 24, 31),
    panel     = Color3.fromRGB(27, 29, 37),
    hover     = Color3.fromRGB(35, 38, 48),
    stroke    = Color3.fromRGB(46, 50, 62),
    text      = Color3.fromRGB(228, 231, 240),
    textDim   = Color3.fromRGB(138, 144, 160),
    accent    = Color3.fromRGB(96, 165, 250),
    accentDim = Color3.fromRGB(52, 110, 190),
    onAccent  = Color3.fromRGB(10, 12, 18),
    good      = Color3.fromRGB(74, 222, 128),
    bad       = Color3.fromRGB(248, 113, 113),
}

-- Colour presets used by the ESP colour pickers.
local PALETTE = {
    Blue   = Color3.fromRGB(96, 165, 250),
    Red    = Color3.fromRGB(248, 113, 113),
    Green  = Color3.fromRGB(74, 222, 128),
    Yellow = Color3.fromRGB(250, 204, 21),
    Purple = Color3.fromRGB(167, 139, 250),
    Orange = Color3.fromRGB(251, 146, 60),
    Cyan   = Color3.fromRGB(34, 211, 238),
    White  = Color3.fromRGB(255, 255, 255),
    Black  = Color3.fromRGB(30, 32, 40),
}

local PALETTE_ORDER = { "Blue", "Red", "Green", "Yellow", "Purple", "Cyan", "White", "Black" }

local function palette(name)
    return PALETTE[name] or PALETTE.White
end

local Font     = Enum.Font.Gotham
local FontBold = Enum.Font.GothamBold
local FontMono = Enum.Font.Code

--------------------------------------------------------------------------------
-- 3. TINY GUI HELPERS
--------------------------------------------------------------------------------

-- create(class, props) -> instance
--   props.Parent is applied last so children are wired up before the parent
--   is attached to the tree.
local function create(class, props)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" and k ~= "Children" then
            pcall(function() inst[k] = v end)
        end
    end
    if props and props.Parent then
        inst.Parent = props.Parent
    end
    return inst
end

local function round(inst, radius)
    create("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = inst })
end

local function stroke(inst, color, thickness)
    return create("UIStroke", {
        Color = color or Theme.stroke,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = inst,
    })
end

-- Readable text colour for an arbitrary background.
local function readableOn(color)
    local lum = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
    return lum > 0.55 and Theme.onAccent or Theme.text
end

local function toHex(c)
    return string.format("%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local function fromHex(h)
    h = tostring(h):gsub("#", "")
    return Color3.fromRGB(
        tonumber(h:sub(1, 2), 16) or 255,
        tonumber(h:sub(3, 4), 16) or 255,
        tonumber(h:sub(5, 6), 16) or 255
    )
end

-- typeof() only exists in Luau; this keeps the code portable to plain Lua.
local function typeOf(value)
    if type(value) == "userdata" and type(typeof) == "function" then
        local ok, name = pcall(typeof, value)
        if ok then return name end
    end
    return type(value)
end

-- math.clamp is Luau only
local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- Every runtime connection goes in here so DESTROY can cut all of them,
-- including the mouse handlers the sliders and the window drag register.
local Connections = {}

local function connect(signal, handler)
    local c = signal:Connect(handler)
    Connections[#Connections + 1] = c
    return c
end

-- Run a feature step without letting one broken feature take down the rest.
-- Each label only reports its first failure, so a per-frame error cannot flood
-- the console.
local reportedErrors = {}

local function safe(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not reportedErrors[label] then
        reportedErrors[label] = true
        print("[" .. PROJECT .. "] " .. label .. " disabled: " .. tostring(err))
    end
    return ok
end

--------------------------------------------------------------------------------
-- 4. STATE
--------------------------------------------------------------------------------

local DEFAULTS = {
    visuals = {
        espBox            = false,
        espGlow           = false,
        espSkeleton       = false,
        espNametag        = false,
        espTracer         = false,
        wallcheck         = true,
        boxColorName      = "Blue",
        hiddenColorName   = "Red",
        skeletonColorName = "White",
        tracerColorName   = "Blue",
    },
    aim = {
        enabled  = false,
        always   = false, -- aim without holding the right mouse button
        target   = "Head",
        fov      = 150,   -- pixel radius around the mouse
        range    = 600,   -- maximum distance in studs
        smooth   = 6,
        wall     = true,
        showRing = true,
    },
    movement = {
        walkspeed    = 16,
        jumppower   = 50,
        fly          = false,
        flyspeed     = 70,
        noclip       = false,
        infiniteJump = false,
        safewalk     = false,
    },
    combat = {
        hitbox    = false,
        hitboxSz  = 8,
        spinbot   = false,
        spinSpeed = 20,
        fov       = false,
        fovValue  = 90,
    },
    utils = {
        clickTP  = false,
        reattach = true,
        bubble   = false, -- collapse the hub to the round team bubble
    },
}

-- live copy of DEFAULTS that the widgets read from / write to
local function copyTable(src)
    local out = {}
    for k, v in pairs(src) do out[k] = v end
    return out
end

local state = {
    visuals  = copyTable(DEFAULTS.visuals),
    aim      = copyTable(DEFAULTS.aim),
    movement = copyTable(DEFAULTS.movement),
    combat   = copyTable(DEFAULTS.combat),
    utils    = copyTable(DEFAULTS.utils),
}

-- path helpers ("visuals.espBox" -> value)
local function getPath(root, path)
    local node = root
    for part in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return node
end

local function setPath(root, path, value)
    local parts = {}
    for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
    local node = root
    for i = 1, #parts - 1 do
        node[parts[i]] = node[parts[i]] or {}
        node = node[parts[i]]
    end
    node[parts[#parts]] = value
end

-- registry so loading a config can repaint every widget
local refreshers = {}
local function refresh(path)
    if refreshers[path] then refreshers[path]() end
end

--------------------------------------------------------------------------------
-- 5. PAGE + WIDGETS
--------------------------------------------------------------------------------

Page = {}
Page.__index = Page

function Page.new(container, name)
    local self = setmetatable({}, Page)
    self.name = name

    self.frame = create("ScrollingFrame", {
        Name                      = name,
        Size                      = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency    = 1,
        BorderSizePixel           = 0,
        ScrollBarThickness        = 3,
        ScrollBarImageColor3      = Theme.accent,
        ScrollBarImageTransparency = 0.6,
        AutomaticCanvasSize       = Enum.AutomaticSize.Y,
        CanvasSize                = UDim2.new(),
        ClipsDescendants           = true,
        Visible                   = false,
        Parent                    = container,
    })

    create("UIListLayout", {
        Padding   = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent    = self.frame,
    })
    create("UIPadding", {
        PaddingLeft   = UDim.new(0, 9),
        PaddingRight  = UDim.new(0, 11),
        PaddingTop    = UDim.new(0, 7),
        PaddingBottom = UDim.new(0, 8),
        Parent        = self.frame,
    })

    return self
end

-- small uppercase header
function Page:section(text)
    local holder = create("Frame", {
        Size                  = UDim2.new(1, -4, 0, 18),
        BackgroundTransparency = 1,
        Parent                = self.frame,
    })
    create("TextLabel", {
        Size                  = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text                  = string.upper(text),
        Font                  = FontBold,
        TextSize              = 10,
        TextColor3            = Theme.accent,
        TextXAlignment        = Enum.TextXAlignment.Left,
        Parent                = holder,
    })
    return holder
end

-- dim explanatory line
function Page:hint(text)
    create("TextLabel", {
        Size                  = UDim2.new(1, -4, 0, 16),
        AutomaticSize         = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Text                  = text,
        Font                  = Font,
        TextSize              = 10,
        TextColor3            = Theme.textDim,
        TextXAlignment        = Enum.TextXAlignment.Left,
        TextYAlignment        = Enum.TextYAlignment.Top,
        TextWrapped           = true,
        Parent                = self.frame,
    })
end

-- ---- toggle -----------------------------------------------------------------
function Page:toggle(text, path, default, onChange)
    if getPath(state, path) == nil then
        setPath(state, path, default)
    end

    local row = create("Frame", {
        Size                  = UDim2.new(1, -4, 0, 22),
        BackgroundTransparency = 1,
        Parent                = self.frame,
    })

    create("TextLabel", {
        Size                  = UDim2.new(1, -44, 1, 0),
        BackgroundTransparency = 1,
        Text                  = text,
        Font                  = Font,
        TextSize              = 12,
        TextColor3            = Theme.text,
        TextXAlignment        = Enum.TextXAlignment.Left,
        Parent                = row,
    })

    local sw = create("Frame", {
        Size             = UDim2.fromOffset(32, 16),
        Position         = UDim2.new(1, -32, 0, 3),
        BackgroundColor3 = Theme.stroke,
        BorderSizePixel  = 0,
        Active           = true,
        Parent           = row,
    })
    round(sw, 8)

    local knob = create("Frame", {
        Size             = UDim2.fromOffset(12, 12),
        Position         = UDim2.fromOffset(2, 2),
        BackgroundColor3 = Theme.textDim,
        BorderSizePixel  = 0,
        Parent           = sw,
    })
    round(knob, 6)

    local function paint(value)
        if value then
            sw.BackgroundColor3 = Theme.accentDim
            knob.BackgroundColor3 = Theme.accent
            knob.Position = UDim2.fromOffset(18, 2)
        else
            sw.BackgroundColor3 = Theme.stroke
            knob.BackgroundColor3 = Theme.textDim
            knob.Position = UDim2.fromOffset(2, 2)
        end
    end

    local function apply(value)
        setPath(state, path, value)
        paint(value)
        if onChange then onChange(value) end
    end

    local function flip()
        apply(not getPath(state, path))
    end

    -- clickable switch
    sw.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then flip() end
    end)

    -- clickable label
    local hit = create("TextButton", {
        Size                  = UDim2.new(1, -40, 1, 0),
        BackgroundTransparency = 1,
        Text                  = "",
        AutoButtonColor       = false,
        Parent                = row,
    })
    hit.MouseButton1Click:Connect(flip)

    paint(getPath(state, path))
    refreshers[path] = function() paint(getPath(state, path)) end
    return row
end

-- ---- slider -----------------------------------------------------------------
function Page:slider(text, path, min, max, step, default, onChange)
    if getPath(state, path) == nil then
        setPath(state, path, default)
    end

    local row = create("Frame", {
        Size                  = UDim2.new(1, -4, 0, 38),
        BackgroundTransparency = 1,
        Parent                = self.frame,
    })

    create("TextLabel", {
        Size                  = UDim2.new(1, -60, 0, 16),
        BackgroundTransparency = 1,
        Text                  = text,
        Font                  = Font,
        TextSize              = 12,
        TextColor3            = Theme.text,
        TextXAlignment        = Enum.TextXAlignment.Left,
        Parent                = row,
    })

    local numberLabel = create("TextLabel", {
        Size                  = UDim2.fromOffset(56, 16),
        Position              = UDim2.new(1, -56, 0, 0),
        BackgroundTransparency = 1,
        Text                  = "",
        Font                  = FontMono,
        TextSize              = 11,
        TextColor3            = Theme.accent,
        TextXAlignment        = Enum.TextXAlignment.Right,
        Parent                = row,
    })

    local track = create("Frame", {
        Size             = UDim2.new(1, -4, 0, 6),
        Position         = UDim2.fromOffset(2, 26),
        BackgroundColor3 = Theme.panel,
        BorderSizePixel  = 0,
        Active           = true,
        Parent           = row,
    })
    round(track, 3)

    local fill = create("Frame", {
        Size             = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Theme.accent,
        BorderSizePixel  = 0,
        Parent           = track,
    })
    round(fill, 3)

    local knob = create("Frame", {
        Size             = UDim2.fromOffset(12, 12),
        Position         = UDim2.fromOffset(0, -3),
        BackgroundColor3 = Theme.text,
        BorderSizePixel  = 0,
        Active           = true,
        ZIndex           = 2,
        Parent           = track,
    })
    round(knob, 6)

    local function paint(value)
        local span = max - min
        local rel = span > 0 and ((value - min) / span) or 0
        rel = math.max(0, math.min(1, rel))
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, 0, 0, -3)
        numberLabel.Text = tostring(value)
    end

    local function apply(value)
        if step and step > 0 then
            value = math.floor(value / step + 0.5) * step
        end
        value = math.max(min, math.min(max, value))
        setPath(state, path, value)
        paint(value)
        if onChange then onChange(value) end
    end

    local dragging = false
    local function fromX(x)
        local span = math.max(track.AbsoluteSize.X, 1)
        local rel = math.max(0, math.min(1, (x - track.AbsolutePosition.X) / span))
        apply(min + rel * (max - min))
    end

    local function beginDrag(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            fromX(input.Position.X)
        end
    end

    track.InputBegan:Connect(beginDrag)
    knob.InputBegan:Connect(beginDrag)
    -- these live on UserInputService, so they must be tracked: without this they
    -- would outlive the GUI and error on every mouse move after DESTROY
    connect(UIS.InputChanged, function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            fromX(input.Position.X)
        end
    end)
    connect(UIS.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    paint(getPath(state, path))
    refreshers[path] = function() paint(getPath(state, path)) end
    return row
end

-- ---- button -----------------------------------------------------------------
function Page:button(text, onClick, color)
    local bg = color or Theme.accent
    local b = create("TextButton", {
        Size             = UDim2.new(1, -4, 0, 24),
        BackgroundColor3 = bg,
        BorderSizePixel  = 0,
        Text             = text,
        Font             = FontBold,
        TextSize         = 11,
        TextColor3       = readableOn(bg),
        AutoButtonColor  = false,
        Parent           = self.frame,
    })
    round(b, 6)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = bg:Lerp(Color3.new(1, 1, 1), 0.12) end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = bg end)
    b.MouseButton1Click:Connect(function()
        local ok, err = pcall(onClick)
        if not ok then
            print("[" .. PROJECT .. "] button '" .. text .. "' failed: " .. tostring(err))
            local w = Window and Window.instance
            if w then pcall(function() w:toast(text .. " failed", Theme.bad) end) end
        end
    end)
    return b
end

-- ---- cycling dropdown -------------------------------------------------------
function Page:cycle(text, path, options, default, onChange)
    if getPath(state, path) == nil then
        setPath(state, path, default)
    end

    local row = create("Frame", {
        Size                  = UDim2.new(1, -4, 0, 22),
        BackgroundTransparency = 1,
        Parent                = self.frame,
    })

    create("TextLabel", {
        Size                  = UDim2.new(1, -110, 1, 0),
        BackgroundTransparency = 1,
        Text                  = text,
        Font                  = Font,
        TextSize              = 12,
        TextColor3            = Theme.text,
        TextXAlignment        = Enum.TextXAlignment.Left,
        Parent                = row,
    })

    local valueLabel = create("TextButton", {
        Size             = UDim2.fromOffset(104, 18),
        Position         = UDim2.new(1, -104, 0, 2),
        BackgroundColor3 = Theme.panel,
        BorderSizePixel  = 0,
        Text             = "",
        Font             = FontMono,
        TextSize         = 11,
        TextColor3       = Theme.accent,
        AutoButtonColor  = false,
        Parent           = row,
    })
    round(valueLabel, 5)

    local function paint()
        valueLabel.Text = tostring(getPath(state, path))
    end

    valueLabel.MouseButton1Click:Connect(function()
        local current = getPath(state, path)
        local index = 1
        for i, opt in ipairs(options) do
            if opt == current then
                index = i
                break
            end
        end
        local nextValue = options[(index % #options) + 1]
        setPath(state, path, nextValue)
        paint()
        if onChange then onChange(nextValue) end
    end)

    paint()
    refreshers[path] = paint
    return row
end

--------------------------------------------------------------------------------
-- 6. WINDOW (the "small screen")
--------------------------------------------------------------------------------

Window = {}
Window.__index = Window
local TABS = {
    { id = "visuals",  label = "Visuals" },
    { id = "aim",      label = "Aim"     },
    { id = "movement", label = "Move"    },
    { id = "combat",   label = "Combat"  },
    { id = "utils",    label = "Utils"   },
    { id = "config",   label = "Config"  },
}

function Window.new()
    local self = setmetatable({}, Window)
    self.destroyed = false

    self.gui = create("ScreenGui", {
        Name           = "MinimaHubScreen",
        ResetOnSpawn   = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder   = 999,
        Parent         = resolveGuiParent(),
    })

    self.frame = create("Frame", {
        Name              = "Window",
        Size              = UDim2.fromOffset(412, 300),
        Position          = UDim2.fromOffset(60, 70),
        BackgroundColor3  = Theme.bg,
        BorderSizePixel   = 0,
        Active            = true,
        Parent            = self.gui,
    })
    round(self.frame, 8)
    stroke(self.frame, Theme.stroke, 1)

    ------------------------------------------------------------------ title bar
    local title = create("Frame", {
        Name             = "Title",
        Size             = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = Theme.bgAlt,
        BorderSizePixel  = 0,
        Active           = true,
        Parent           = self.frame,
    })
    round(title, 8)
    -- square off the bottom corners of the title bar
    create("Frame", {
        Size             = UDim2.new(1, 0, 0, 10),
        Position         = UDim2.new(0, 0, 1, -10),
        BackgroundColor3 = Theme.bgAlt,
        BorderSizePixel  = 0,
        ZIndex           = 1,
        Parent           = title,
    })

    -- logo chip
    local logo = create("Frame", {
        Size             = UDim2.fromOffset(16, 16),
        Position         = UDim2.fromOffset(10, 7),
        BackgroundColor3 = Theme.accent,
        BorderSizePixel  = 0,
        Parent           = title,
    })
    round(logo, 4)
    create("TextLabel", {
        Size                  = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text                  = "M",
        Font                  = FontBold,
        TextSize              = 10,
        TextColor3            = Theme.onAccent,
        Parent                = logo,
    })

    create("TextLabel", {
        Size                  = UDim2.fromOffset(90, 30),
        Position              = UDim2.fromOffset(33, 0),
        BackgroundTransparency = 1,
        Text                  = "MINIMAHUB",
        Font                  = FontBold,
        TextSize              = 13,
        TextColor3            = Theme.text,
        TextXAlignment        = Enum.TextXAlignment.Left,
        Parent                = title,
    })

    create("TextLabel", {
        Size                  = UDim2.fromOffset(90, 30),
        Position              = UDim2.fromOffset(120, 0),
        BackgroundTransparency = 1,
        Text                  = PROJECT,
        Font                  = Font,
        TextSize              = 11,
        TextColor3            = Theme.textDim,
        TextXAlignment        = Enum.TextXAlignment.Left,
        Parent                = title,
    })

    -- window buttons: bubble / minimise / close
    local function titleButton(text, x, circular)
        local b = create("TextButton", {
            Size             = UDim2.fromOffset(22, 22),
            Position         = UDim2.fromOffset(x, 4),
            BackgroundColor3 = Theme.panel,
            BorderSizePixel  = 0,
            Text             = text,
            Font             = FontBold,
            TextSize         = 13,
            TextColor3       = Theme.textDim,
            AutoButtonColor  = false,
            Parent           = title,
        })
        round(b, circular and 11 or 5)
        b.MouseEnter:Connect(function() b.BackgroundColor3 = Theme.hover end)
        b.MouseLeave:Connect(function() b.BackgroundColor3 = Theme.panel end)
        return b
    end

    local btnBubble = titleButton("", 326, true)
    local bubbleIcon = create("Frame", {
        Size             = UDim2.fromOffset(8, 8),
        Position         = UDim2.fromOffset(7, 7),
        BackgroundColor3 = Theme.accent,
        BorderSizePixel  = 0,
        Parent           = btnBubble,
    })
    round(bubbleIcon, 4)
    btnBubble.MouseEnter:Connect(function() bubbleIcon.BackgroundColor3 = Theme.text end)
    btnBubble.MouseLeave:Connect(function() bubbleIcon.BackgroundColor3 = Theme.accent end)

    local btnMin   = titleButton("-", 352)
    local btnClose = titleButton("x", 378)
    btnClose.MouseEnter:Connect(function() btnClose.TextColor3 = Theme.bad end)
    btnClose.MouseLeave:Connect(function() btnClose.TextColor3 = Theme.textDim end)

    --------------------------------------------------------------------- body
    local body = create("Frame", {
        Name             = "Body",
        Size             = UDim2.new(1, 0, 1, -50),
        Position         = UDim2.new(0, 0, 0, 30),
        BackgroundColor3 = Theme.bg,
        BorderSizePixel  = 0,
        Parent           = self.frame,
    })
    self.body = body

    local rail = create("Frame", {
        Size             = UDim2.new(0, 84, 1, 0),
        BackgroundColor3 = Theme.bgAlt,
        BorderSizePixel  = 0,
        Parent           = body,
    })

    self.pageHost = create("Frame", {
        Size             = UDim2.new(1, -84, 1, 0),
        Position         = UDim2.fromOffset(84, 0),
        BackgroundColor3 = Theme.bg,
        BorderSizePixel  = 0,
        ClipsDescendants = true,
        Parent           = body,
    })

    ------------------------------------------------------------------- footer
    local footer = create("Frame", {
        Size             = UDim2.new(1, 0, 0, 20),
        Position         = UDim2.new(0, 0, 1, -20),
        BackgroundColor3 = Theme.bgAlt,
        BorderSizePixel  = 0,
        Parent           = self.frame,
    })
    self.footer = footer
    create("TextLabel", {
        Size                  = UDim2.new(1, -110, 1, 0),
        Position              = UDim2.fromOffset(12, 0),
        BackgroundTransparency = 1,
        Text                  = "by " .. AUTHOR_A .. " & " .. AUTHOR_B,
        Font                  = Font,
        TextSize              = 11,
        TextColor3            = Theme.textDim,
        TextXAlignment        = Enum.TextXAlignment.Left,
        Parent                = footer,
    })
    create("TextLabel", {
        Size                  = UDim2.fromOffset(90, 20),
        Position              = UDim2.new(1, -98, 0, 0),
        BackgroundTransparency = 1,
        Text                  = "v" .. VERSION,
        Font                  = FontMono,
        TextSize              = 10,
        TextColor3            = Theme.textDim,
        TextXAlignment        = Enum.TextXAlignment.Right,
        Parent                = footer,
    })

    -------------------------------------------------------------------- toast
    -- transient message strip shown above the footer.
    -- NB: the instance field is "toastLabel" so it does not shadow the
    -- Window:toast() method below.
    self.toastLabel = create("TextLabel", {
        Size                  = UDim2.new(1, -24, 0, 24),
        Position              = UDim2.new(0, 12, 1, -50),
        BackgroundColor3      = Theme.panel,
        BackgroundTransparency = 1,
        Text                  = "",
        Font                  = Font,
        TextSize              = 11,
        TextColor3            = Theme.text,
        TextXAlignment        = Enum.TextXAlignment.Center,
        TextYAlignment        = Enum.TextYAlignment.Center,
        TextTruncate          = Enum.TextTruncate.AtEnd,
        Visible               = false,
        ZIndex                = 20,
        Parent                = self.frame,
    })
    round(self.toastLabel, 6)
    self.toastRemaining = 0

    ------------------------------------------------------------------ bubble
    -- Round "team bubble": a compact version of the hub that keeps the photo of
    -- the team on screen. Click it to bring the full panel back, drag it to move.
    self.bubble = create("Frame", {
        Name             = "TeamBubble",
        Size             = UDim2.fromOffset(58, 58),
        Position         = UDim2.fromOffset(60, 70),
        BackgroundColor3 = Theme.bg,
        BorderSizePixel  = 0,
        Active           = true,
        Visible          = false,
        ZIndex           = 10,
        Parent           = self.gui,
    })
    round(self.bubble, 29)
    self.bubbleStroke = stroke(self.bubble, Theme.accent, 1.5)

    -- monogram underneath the photo: still readable if the thumbnail fails
    create("TextLabel", {
        Size                  = UDim2.fromOffset(58, 58),
        BackgroundTransparency = 1,
        Text                  = "AA",
        Font                  = FontBold,
        TextSize              = 18,
        TextColor3            = Theme.accent,
        ZIndex                = 11,
        Parent                = self.bubble,
    })

    self.bubblePhoto = create("ImageLabel", {
        Name                  = "Photo",
        Size                  = UDim2.fromOffset(52, 52),
        Position              = UDim2.fromOffset(3, 3),
        BackgroundTransparency = 1,
        BorderSizePixel       = 0,
        Image                 = teamPhotoUrl(),
        ImageTransparency     = 0,
        ScaleType             = Enum.ScaleType.Crop,
        ZIndex                = 12,
        Parent                = self.bubble,
    })
    round(self.bubblePhoto, 26)

    -- small status dot: green as soon as at least one feature is armed
    self.bubbleDot = create("Frame", {
        Size             = UDim2.fromOffset(11, 11),
        Position         = UDim2.new(1, -10, 1, -10),
        BackgroundColor3 = Theme.good,
        BorderSizePixel  = 0,
        Visible          = false,
        ZIndex           = 13,
        Parent           = self.bubble,
    })
    round(self.bubbleDot, 5)
    stroke(self.bubbleDot, Theme.bg, 2)

    self.bubbleTip = create("TextLabel", {
        Size                  = UDim2.new(0, 170, 0, 16),
        Position              = UDim2.fromOffset(-56, 64),
        BackgroundTransparency = 1,
        Text                  = AUTHOR_A .. " & " .. AUTHOR_B,
        Font                  = Font,
        TextSize              = 10,
        TextColor3            = Theme.textDim,
        TextXAlignment        = Enum.TextXAlignment.Center,
        Visible               = false,
        ZIndex                = 10,
        Parent                = self.bubble,
    })

    self.bubble.MouseEnter:Connect(function()
        if self.bubbleStroke then self.bubbleStroke.Thickness = 2.2 end
        if self.bubbleTip then self.bubbleTip.Visible = true end
    end)
    self.bubble.MouseLeave:Connect(function()
        if self.bubbleStroke then self.bubbleStroke.Thickness = 1.5 end
        if self.bubbleTip then self.bubbleTip.Visible = false end
    end)

    ------------------------------------------------------------------- pages
    self.pages       = {}
    self.railButtons = {}

    for index, tab in ipairs(TABS) do
        local page = Page.new(self.pageHost, tab.id)
        self.pages[tab.id] = page

        local btn = create("TextButton", {
            Size             = UDim2.new(1, -12, 0, 26),
            Position         = UDim2.fromOffset(6, 6 + (index - 1) * 29),
            BackgroundColor3 = Theme.bgAlt,
            BorderSizePixel  = 0,
            Text             = tab.label,
            Font             = Font,
            TextSize         = 12,
            TextColor3       = Theme.textDim,
            TextXAlignment   = Enum.TextXAlignment.Left,
            AutoButtonColor  = false,
            Parent           = rail,
        })
        round(btn, 6)

        -- selection pill on the left of the active tab
        local pill = create("Frame", {
            Size             = UDim2.fromOffset(3, 14),
            Position         = UDim2.fromOffset(-3, 6),
            BackgroundColor3 = Theme.accent,
            BorderSizePixel  = 0,
            Visible          = false,
            ZIndex           = 2,
            Parent           = btn,
        })
        round(pill, 2)

        btn.MouseEnter:Connect(function()
            btn.TextColor3 = Theme.text
            btn.BackgroundColor3 = Theme.hover
        end)
        btn.MouseLeave:Connect(function()
            btn.TextColor3 = Theme.textDim
            btn.BackgroundColor3 = Theme.bgAlt
        end)
        btn.MouseButton1Click:Connect(function()
            self:select(tab.id)
        end)

        self.railButtons[tab.id] = { button = btn, pill = pill }
    end

    ------------------------------------------------------------------- drag
    self:makeDraggable(title, { btnBubble, btnMin, btnClose })

    ----------------------------------------------------------------- buttons
    btnBubble.MouseButton1Click:Connect(function() self:setBubble(true) end)
    btnMin.MouseButton1Click:Connect(function() self:toggleMinimise() end)
    btnClose.MouseButton1Click:Connect(function()
        if Cleanup then Cleanup.destroy() end
    end)

    self.minimised = false
    self.frameSize = self.frame.Size
    self.visible = true
    self.bubbleMode = false
    self.bubblePlaced = false
    self:makeBubbleDraggable()

    self:select(TABS[1].id)
    return self
end

-- Drags the window by its title bar. `exclude` lists buttons that must not
-- start a drag (otherwise clicking - / x would nudge the window around).
function Window:makeDraggable(handle, exclude)
    local dragging = false
    local dragStart, startPos = nil, nil

    local function blocked(x, y)
        for _, button in ipairs(exclude or {}) do
            local p = button.AbsolutePosition
            local s = button.AbsoluteSize
            if x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y then
                return true
            end
        end
        return false
    end

    handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if blocked(input.Position.X, input.Position.Y) then return end
        dragging  = true
        dragStart = input.Position
        startPos  = self.frame.Position
    end)

    -- Follow the mouse on UserInputService (delta based), so the drag keeps
    -- working when the cursor leaves the title bar and so DESTROY can cut it.
    connect(UIS.InputChanged, function(input)
        if not dragging or self.destroyed then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = input.Position - dragStart
        self.frame.Position = UDim2.fromOffset(
            math.max(-self.frameSize.X.Offset + 60, startPos.X.Offset + delta.X),
            math.max(0, startPos.Y.Offset + delta.Y)
        )
    end)

    connect(UIS.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

-- Drags the bubble. A short press (under 4 px) opens the full window back; a
-- longer move only repositions the bubble.
function Window:makeBubbleDraggable()
    local bubble = self.bubble
    if not bubble then return end
    local dragging, moved = false, false
    local dragStart, startPos = nil, nil

    bubble.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        dragging  = true
        moved     = false
        dragStart = input.Position
        startPos  = bubble.Position
    end)

    connect(UIS.InputChanged, function(input)
        if not dragging or self.destroyed then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = input.Position - dragStart
        if math.abs(delta.X) > 4 or math.abs(delta.Y) > 4 then moved = true end
        local camera = getCamera()
        local maxX = math.max(0, (camera and camera.ViewportSize.X or 1920) - 58)
        local maxY = math.max(0, (camera and camera.ViewportSize.Y or 1080) - 58)
        bubble.Position = UDim2.fromOffset(
            clamp(startPos.X.Offset + delta.X, 0, maxX),
            clamp(startPos.Y.Offset + delta.Y, 0, maxY)
        )
        self.bubblePlaced = true
    end)

    connect(UIS.InputEnded, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not dragging then return end
        dragging = false
        if not moved then self:setBubble(false) end
    end)
end

function Window:select(id)
    for key, page in pairs(self.pages) do
        page.frame.Visible = (key == id)
    end
    for key, entry in pairs(self.railButtons) do
        local active = (key == id)
        entry.pill.Visible = active
        entry.button.TextColor3 = active and Theme.text or Theme.textDim
        entry.button.BackgroundColor3 = active and Theme.hover or Theme.bgAlt
    end
    self.active = id
end

-- Show a short-lived message strip above the footer.
function Window:toast(text, colour, duration)
    if not self.toastLabel then return end
    self.toastLabel.Text = text
    self.toastLabel.TextColor3 = colour or Theme.text
    self.toastLabel.BackgroundTransparency = 0.15
    self.toastLabel.Visible = true
    self.toastRemaining = duration or 2.5
end

-- Collapse the window down to just the title bar.
function Window:toggleMinimise()
    self.minimised = not self.minimised
    if self.body then self.body.Visible = not self.minimised end
    if self.footer then self.footer.Visible = not self.minimised end
    self.frame.Size = self.minimised
        and UDim2.fromOffset(self.frameSize.X.Offset, 30)
        or UDim2.fromOffset(self.frameSize.X.Offset, self.frameSize.Y.Offset)
end

-- Shows the window or the bubble depending on the mode and the visibility flag.
function Window:applyVisibility()
    local shown = self.visible ~= false
    if self.frame then self.frame.Visible = shown and not self.bubbleMode end
    if self.bubble then self.bubble.Visible = shown and self.bubbleMode == true end
end

-- true  -> collapse the hub to the round team bubble
-- false -> bring the full panel back
function Window:setBubble(value)
    if self.destroyed then return end
    value = value and true or false
    self.bubbleMode = value

    -- first time: appear where the window is (the user can drag it after that)
    if value and not self.bubblePlaced and self.frame and self.bubble then
        local p = self.frame.Position
        local camera = getCamera()
        local maxX = math.max(0, (camera and camera.ViewportSize.X or 1920) - 58)
        local maxY = math.max(0, (camera and camera.ViewportSize.Y or 1080) - 58)
        self.bubble.Position = UDim2.fromOffset(
            clamp(p.X.Offset, 0, maxX),
            clamp(p.Y.Offset, 0, maxY)
        )
        self.bubblePlaced = true
    end

    self:applyVisibility()

    -- keep the Config toggle in sync: clicking the bubble can reopen the panel
    state.utils.bubble = value
    refresh("utils.bubble")
end

function Window:toggleVisible()
    self.visible = not (self.visible ~= false)
    self:applyVisibility()
end

--------------------------------------------------------------------------------
-- 7. FEATURES
--------------------------------------------------------------------------------

-- ---- character helpers ------------------------------------------------------
local function localCharacter()
    return LocalPlayer and LocalPlayer.Character
end

local function localHumanoid()
    local c = localCharacter()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function localRoot()
    local c = localCharacter()
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- saved values so DESTROY can restore them
local saved = {
    walkspeed = nil,
    jumppower = nil,
    useJumpPower = nil,
    platformStand = nil,
    fov = nil,
    hitboxes = {},
}

-- ---- ESP ---------------------------------------------------------------------
local espCache = {}   -- [player] = { box, glow, tag, tracer, lines = {} }

-- Drawing objects are removed with :Remove() in every executor, but a couple
-- only expose :Destroy(). Try both so nothing is ever left on screen.
local function removeDrawing(drawing)
    if not drawing then return end
    pcall(function() drawing:Remove() end)
    pcall(function() drawing:Destroy() end)
end

local function clearESP(player)
    local entry = espCache[player]
    if not entry then return end
    removeDrawing(entry.box)
    for _, line in pairs(entry.boxLines or {}) do removeDrawing(line) end
    removeDrawing(entry.tag)
    removeDrawing(entry.tracer)
    if entry.glow then pcall(function() entry.glow:Destroy() end) end
    for _, line in pairs(entry.lines or {}) do removeDrawing(line) end
    espCache[player] = nil
end

local function clearAllESP()
    for player in pairs(espCache) do clearESP(player) end
    espCache = {}
end

local BONES_R6 = {
    { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}

local BONES_R15 = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}

local function getBones(character)
    if character:FindFirstChild("UpperTorso") then return BONES_R15 end
    if character:FindFirstChild("Torso") then return BONES_R6 end
    return {}
end

-- Raycast filter: our own character + (optionally) the character we are testing.
local function losFilter(extra)
    local list = {}
    local c = localCharacter()
    if c then list[#list + 1] = c end
    if extra then list[#list + 1] = extra end
    return list
end

-- True when nothing solid sits between the camera and the target.
local function hasLineOfSight(origin, target, targetCharacter)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = losFilter(targetCharacter)
    local direction = target - origin
    if direction.Magnitude < 0.001 then return true end
    local result = workspace:Raycast(origin, direction, params)
    return result == nil
end

-- One bad Drawing property must never take the whole ESP down: every write is
-- isolated, and every primitive is created on its own. An executor without
-- "Square" still gets a box, drawn with four lines.
local function safeSet(drawing, key, value)
    if not drawing then return false end
    local ok = pcall(function() drawing[key] = value end)
    return ok
end

local function newDrawing(kind)
    if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then return nil end
    local ok, drawing = pcall(function() return Drawing.new(kind) end)
    if ok then return drawing end
    return nil
end

local function ensureESP(player)
    if espCache[player] then return espCache[player] end

    local entry = { lines = {}, boxLines = {} }

    entry.box = newDrawing("Square")
    if entry.box then
        safeSet(entry.box, "Thickness", 1)
        safeSet(entry.box, "Filled", false)
        safeSet(entry.box, "Visible", false)
    else
        for i = 1, 4 do
            local line = newDrawing("Line")
            if line then
                safeSet(line, "Thickness", 1)
                safeSet(line, "Visible", false)
                entry.boxLines[i] = line
            end
        end
    end

    entry.tag = newDrawing("Text")
    if entry.tag then
        safeSet(entry.tag, "Visible", false)
        safeSet(entry.tag, "Outline", true)
        safeSet(entry.tag, "Center", true)
        safeSet(entry.tag, "Size", 12)
        -- executors disagree on the type of Text.Font: some want an Enum, the
        -- rest want the numeric id. Try both and keep whatever the executor takes.
        if not safeSet(entry.tag, "Font", FontBold) then
            safeSet(entry.tag, "Font", 2)
        end
    end

    entry.tracer = newDrawing("Line")
    if entry.tracer then
        safeSet(entry.tracer, "Thickness", 1)
        safeSet(entry.tracer, "Visible", false)
    end

    -- nothing could be created at all (Drawing missing or disabled)
    if not entry.box and #entry.boxLines == 0 and not entry.tag and not entry.tracer then
        return nil
    end

    espCache[player] = entry
    return entry
end

-- Project a character's bounding box to the screen.
-- Returns x, y, width, height (top-left corner, pixels) or nil when the
-- character is behind the camera.
local function screenBox(character, camera)
    local ok, cf, size = pcall(character.GetBoundingBox, character)
    if not ok or not cf or not size then return nil end

    local half = size * 0.5
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local inFront = false

    for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
            for _, sz in ipairs({ -1, 1 }) do
                local corner = cf * CFrame.new(sx * half.X, sy * half.Y, sz * half.Z)
                local pos = camera:WorldToViewportPoint(corner.Position)
                if pos.Z > 0 then
                    inFront = true
                    if pos.X < minX then minX = pos.X end
                    if pos.X > maxX then maxX = pos.X end
                    if pos.Y < minY then minY = pos.Y end
                    if pos.Y > maxY then maxY = pos.Y end
                end
            end
        end
    end

    if not inFront then return nil end
    return minX, minY, math.max(maxX - minX, 2), math.max(maxY - minY, 2)
end

local function hideBox(entry)
    if entry.box then safeSet(entry.box, "Visible", false) end
    for _, line in pairs(entry.boxLines or {}) do safeSet(line, "Visible", false) end
end

local function drawBox(entry, x, y, w, h, color)
    if entry.box then
        safeSet(entry.box, "Visible", true)
        safeSet(entry.box, "Position", Vector2.new(x, y))
        safeSet(entry.box, "Size", Vector2.new(w, h))
        safeSet(entry.box, "Color", color)
        safeSet(entry.box, "Transparency", 0.85)
        safeSet(entry.box, "ZIndex", 1)
        return
    end

    -- no Square on this executor: four lines draw the same rectangle
    local corners = {
        { Vector2.new(x, y),         Vector2.new(x + w, y) },
        { Vector2.new(x + w, y),     Vector2.new(x + w, y + h) },
        { Vector2.new(x + w, y + h), Vector2.new(x, y + h) },
        { Vector2.new(x, y + h),     Vector2.new(x, y) },
    }
    for i, line in pairs(entry.boxLines or {}) do
        local seg = corners[i]
        if seg then
            safeSet(line, "Visible", true)
            safeSet(line, "From", seg[1])
            safeSet(line, "To", seg[2])
            safeSet(line, "Color", color)
            safeSet(line, "Transparency", 0.85)
            safeSet(line, "ZIndex", 1)
        end
    end
end

local function hideESPEntry(entry)
    hideBox(entry)
    if entry.tag then safeSet(entry.tag, "Visible", false) end
    if entry.tracer then safeSet(entry.tracer, "Visible", false) end
    if entry.glow then pcall(function() entry.glow.Enabled = false end) end
    for _, line in pairs(entry.lines or {}) do safeSet(line, "Visible", false) end
end

local function drawSkeleton(entry, character, camera, color)
    local bones = getBones(character)
    for i, pair in ipairs(bones) do
        local a = character:FindFirstChild(pair[1])
        local b = character:FindFirstChild(pair[2])
        local line = entry.lines[i]

        if a and b then
            local pa, oa = camera:WorldToViewportPoint(a.Position)
            local pb, ob = camera:WorldToViewportPoint(b.Position)
            if oa and ob then
                if not line then
                    line = newDrawing("Line")
                    if line then
                        safeSet(line, "Thickness", 1.4)
                        safeSet(line, "ZIndex", 1)
                        entry.lines[i] = line
                    end
                end
                if line then
                    safeSet(line, "Visible", true)
                    safeSet(line, "From", Vector2.new(pa.X, pa.Y))
                    safeSet(line, "To", Vector2.new(pb.X, pb.Y))
                    safeSet(line, "Color", color)
                    safeSet(line, "Transparency", 0.9)
                end
            elseif line then
                safeSet(line, "Visible", false)
            end
        elseif line then
            safeSet(line, "Visible", false)
        end
    end
end

-- One player, fully isolated: a broken character cannot stop the other players'
-- ESP. Before this, a single bad Drawing took the whole ESP function down.
local function updatePlayerESP(entry, player, vis, camera, viewport, colors)
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local alive = humanoid and humanoid.Health > 0

    if not alive then
        hideESPEntry(entry)
        return
    end

    local root = character:FindFirstChild("HumanoidRootPart")
    local head = character:FindFirstChild("Head")
    if not root or not head then
        hideESPEntry(entry)
        return
    end

    local origin = camera.CFrame.Position
    local color = colors.visible
    if vis.wallcheck and not hasLineOfSight(origin, head.Position, character) then
        color = colors.hidden
    end

    -- glow (Highlight): rebuilt after a respawn, and never allowed to break the
    -- rest of this player's ESP
    if vis.espGlow then
        if not entry.glow or entry.glow.Parent ~= character then
            if entry.glow then pcall(function() entry.glow:Destroy() end) end
            local ok, glow = pcall(function()
                local h = Instance.new("Highlight")
                h.Name = "MinimaGlow"
                h.FillTransparency = 0.55
                h.OutlineTransparency = 1
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.Parent = character
                return h
            end)
            entry.glow = ok and glow or nil
        end
        if entry.glow then
            entry.glow.Enabled = true
            entry.glow.Adornee = character
            entry.glow.FillColor = color
            entry.glow.OutlineColor = color
        end
    elseif entry.glow then
        entry.glow.Enabled = false
    end

    -- box
    if vis.espBox then
        local bx, by, bw, bh = screenBox(character, camera)
        if bx then drawBox(entry, bx, by, bw, bh, color) else hideBox(entry) end
    else
        hideBox(entry)
    end

    -- nametag
    if vis.espNametag and entry.tag then
        local pos, onScreen = camera:WorldToViewportPoint(head.Position)
        if onScreen then
            local dist = (root.Position - origin).Magnitude
            safeSet(entry.tag, "Visible", true)
            safeSet(entry.tag, "Position", Vector2.new(pos.X, pos.Y - 16))
            safeSet(entry.tag, "Text", string.format("%s  %d  %dm",
                player.DisplayName or player.Name, math.ceil(humanoid.Health), math.floor(dist)))
            safeSet(entry.tag, "Color", color)
            safeSet(entry.tag, "ZIndex", 2)
        else
            safeSet(entry.tag, "Visible", false)
        end
    elseif entry.tag then
        safeSet(entry.tag, "Visible", false)
    end

    -- tracer
    if vis.espTracer and entry.tracer then
        local pos, onScreen = camera:WorldToViewportPoint(root.Position)
        if onScreen then
            safeSet(entry.tracer, "Visible", true)
            safeSet(entry.tracer, "From", Vector2.new(viewport.X / 2, viewport.Y))
            safeSet(entry.tracer, "To", Vector2.new(pos.X, pos.Y))
            safeSet(entry.tracer, "Color", colors.tracer)
            safeSet(entry.tracer, "Transparency", 0.9)
            safeSet(entry.tracer, "ZIndex", 0)
        else
            safeSet(entry.tracer, "Visible", false)
        end
    elseif entry.tracer then
        safeSet(entry.tracer, "Visible", false)
    end

    -- skeleton
    if vis.espSkeleton then
        drawSkeleton(entry, character, camera, colors.bone)
    else
        for _, line in pairs(entry.lines) do safeSet(line, "Visible", false) end
    end
end

local function renderESP()
    local vis = state.visuals
    local camera = getCamera()
    if not camera then return end
    local viewport = camera.ViewportSize

    local colors = {
        visible = palette(vis.boxColorName),
        hidden  = palette(vis.hiddenColorName),
        bone    = palette(vis.skeletonColorName),
        tracer  = palette(vis.tracerColorName),
    }

    for player, entry in pairs(espCache) do
        local ok, err = pcall(updatePlayerESP, entry, player, vis, camera, viewport, colors)
        if not ok and not reportedErrors.espPlayer then
            reportedErrors.espPlayer = true
            print("[" .. PROJECT .. "] ESP skipped a player: " .. tostring(err))
        end
    end
end

-- ---- FOV ring ----------------------------------------------------------------
local fovRing = nil

local function ensureFOVRing()
    if fovRing then return fovRing end
    if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then return nil end

    local ok, ring = pcall(function()
        local r = Drawing.new("Circle")
        r.Thickness = 1
        r.Filled = false
        r.NumSides = 60
        r.Visible = false
        r.ZIndex = 0
        return r
    end)

    if not ok or not ring then return nil end
    fovRing = ring
    return fovRing
end

-- ---- aimbot ------------------------------------------------------------------
local function getAimTarget()
    local camera = getCamera()
    if not camera then return nil end
    local mouse = mouseViewport()
    local best, bestScore = nil, math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                local part = player.Character:FindFirstChild(state.aim.target)
                    or player.Character:FindFirstChild("Head")
                if part then
                    local pos, onScreen = camera:WorldToViewportPoint(part.Position)
                    if onScreen then
                        local screenDist = (Vector2.new(pos.X, pos.Y) - mouse).Magnitude
                        local worldDist = (part.Position - camera.CFrame.Position).Magnitude
                        if screenDist <= state.aim.fov and worldDist <= state.aim.range then
                            if screenDist < bestScore then
                                bestScore = screenDist
                                best = {
                                    part = part,
                                    player = player,
                                    humanoid = humanoid,
                                    character = player.Character,
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function runAimbot(dt)
    if not state.aim.enabled then return end
    if not state.aim.always and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        return
    end

    local camera = getCamera()
    if not camera then return end
    local target = getAimTarget()
    if not target then return end

    if state.aim.wall and not hasLineOfSight(camera.CFrame.Position, target.part.Position, target.character) then
        return
    end

    local goal    = target.part.Position
    local current = camera.CFrame
    local alpha   = clamp(1 - math.exp(-state.aim.smooth * dt), 0, 1)

    -- rotate towards the target but keep the camera where it is: lerping the
    -- position would drag the player forward into the enemy
    if (goal - current.Position).Magnitude < 0.01 then return end
    local targetCF = CFrame.lookAt(current.Position, goal)
    camera.CFrame = current:Lerp(targetCF, alpha)
end

-- The default CameraModule rewrites Camera.CFrame every frame at
-- Enum.RenderPriority.Camera (200). Writing the camera from RenderStepped
-- (priority 0) is therefore overwritten a split second later - the classic
-- "the aimbot does nothing" bug. Bind the aim loop *after* the camera instead.
local AIM_BIND = "SMPWORK_Aim"
local aimBound = false

local function bindAim()
    if aimBound then return true end
    if type(RunService.BindToRenderStep) ~= "function" then return false end
    local ok = pcall(function()
        -- a previous chunk (RELOAD FROM GITHUB) may still hold the name
        pcall(function() RunService:UnbindFromRenderStep(AIM_BIND) end)
        RunService:BindToRenderStep(AIM_BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
            safe("aimbot", runAimbot, dt)
        end)
    end)
    aimBound = ok
    return ok
end

local function unbindAim()
    if not aimBound then return end
    pcall(function() RunService:UnbindFromRenderStep(AIM_BIND) end)
    aimBound = false
end

-- ---- movement ----------------------------------------------------------------
local function applyWalkSpeed(value)
    local hum = localHumanoid()
    if not hum then return end
    if saved.walkspeed == nil then saved.walkspeed = hum.WalkSpeed end
    hum.WalkSpeed = value
end

local function applyJumpPower(value)
    local hum = localHumanoid()
    if not hum then return end
    if saved.jumppower == nil then
        saved.jumppower = hum.JumpPower
        saved.useJumpPower = hum.UseJumpPower
    end
    hum.JumpPower = value
    hum.UseJumpPower = true
end

-- Many games (and their anti-cheat) reset Humanoid.WalkSpeed / JumpPower every
-- frame, which makes the sliders look broken. Re-apply the wanted values in the
-- physics step; this is a no-op when the humanoid already matches.
local function enforceMovement()
    local hum = localHumanoid()
    if not hum then return end

    local speed = state.movement.walkspeed
    if type(speed) == "number" and hum.WalkSpeed ~= speed then
        hum.WalkSpeed = speed
    end

    local jump = state.movement.jumppower
    if type(jump) == "number" then
        if not hum.UseJumpPower then hum.UseJumpPower = true end
        if hum.JumpPower ~= jump then hum.JumpPower = jump end
    end
end

--------------------------------------------------------------------------------
-- FLY  (classic style: BodyGyro tilt + BodyVelocity thrust)
--
-- Same maths as the well known "Fly" scripts, but re-implemented so that it
--  * works on R6 and R15 (HumanoidRootPart, Torso or UpperTorso)
--  * uses the executor's own render loop instead of a busy "wait()" loop
--  * always cleans up its forces and restores PlatformStand
--------------------------------------------------------------------------------

local flyGyro    = nil   -- BodyGyro that tilts the character
local flyThrust  = nil   -- BodyVelocity that pushes the character
local flySpeed   = 0     -- current throttle, ramps up to the "Fly speed" slider
local flyLastDir = { f = 0, b = 0, l = 0, r = 0 }
local flyLastUp  = 0     -- last vertical input (+1 up, -1 down)

-- The part the flight forces are attached to.
-- R15 uses HumanoidRootPart, R6 uses Torso / UpperTorso.
local function flyPart()
    local character = localCharacter()
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("UpperTorso")
end

-- Remove the two forces, leaving the humanoid alone.
local function destroyFlyForces()
    if flyGyro then pcall(function() flyGyro:Destroy() end) end
    if flyThrust then pcall(function() flyThrust:Destroy() end) end
    flyGyro = nil
    flyThrust = nil
end

-- BodyMovers answer to the legacy lowercase names (maxForce / velocity / cframe)
-- and to the modern capitalised ones, depending on the client build. Write
-- whichever the client actually exposes.
local function setForce(inst, lowerName, upperName, value)
    local ok = pcall(function() inst[lowerName] = value end)
    if not ok then pcall(function() inst[upperName] = value end) end
end

-- Hand the character back to the game: remove the forces, restore PlatformStand.
local function stopFly()
    destroyFlyForces()
    flySpeed = 0
    flyLastDir = { f = 0, b = 0, l = 0, r = 0 }
    flyLastUp = 0

    local hum = localHumanoid()
    if hum then
        pcall(function()
            -- if the game had already put us in PlatformStand, put it back
            hum.PlatformStand = saved.platformStand == true
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end)
    end
    saved.platformStand = nil
end

-- Attach the flight forces. Returns true when the character is flying.
local function startFly()
    local part = flyPart()
    local hum  = localHumanoid()
    if not part or not hum then return false end

    -- only drop the forces: stopFly() would also clear PlatformStand and make
    -- the character flicker on every (re)start
    destroyFlyForces()

    flyGyro = Instance.new("BodyGyro")
    flyGyro.P = 9e4
    setForce(flyGyro, "maxTorque", "MaxTorque", Vector3.new(9e9, 9e9, 9e9))
    setForce(flyGyro, "cframe", "CFrame", part.CFrame)
    flyGyro.Parent = part

    flyThrust = Instance.new("BodyVelocity")
    setForce(flyThrust, "maxForce", "MaxForce", Vector3.new(9e9, 9e9, 9e9))
    setForce(flyThrust, "velocity", "Velocity", Vector3.new(0, 0.1, 0))
    flyThrust.Parent = part

    if saved.platformStand == nil then saved.platformStand = hum.PlatformStand end
    hum.PlatformStand = true
    return true
end

-- Camera relative velocity, exactly like the classic fly script:
--   lookVector * forward  +  (side offset - camera position) * speed
local function flyVelocity(camera, d, vertical, speed)
    local look = camera.CFrame.LookVector
    local side = camera.CFrame * CFrame.new(d.l + d.r, (d.f + d.b) * 0.2, 0)
    local velocity = (look * (d.f + d.b)) + (side.Position - camera.CFrame.Position)
    velocity = velocity * speed
    if vertical ~= 0 then
        velocity = velocity + Vector3.new(0, vertical * speed * 0.8, 0)
    end
    return velocity
end

local function runFly(dt)
    -- switched off: tear the flight down again
    if not state.movement.fly then
        if flyGyro or flyThrust then stopFly() end
        return
    end

    local part    = flyPart()
    local camera  = getCamera()
    if not part or not camera then return end

    -- create the forces on demand (and again after a respawn)
    if not flyGyro or not flyThrust or flyThrust.Parent ~= part then
        if not startFly() then return end
        part = flyPart()
        camera = getCamera()
        if not part or not camera then return end
    end

    -- ---- input -------------------------------------------------------------
    local dir = { f = 0, b = 0, l = 0, r = 0 }
    if UIS:IsKeyDown(Enum.KeyCode.W) then dir.f = 1 end
    if UIS:IsKeyDown(Enum.KeyCode.S) then dir.b = -1 end
    if UIS:IsKeyDown(Enum.KeyCode.A) then dir.l = -1 end
    if UIS:IsKeyDown(Enum.KeyCode.D) then dir.r = 1 end

    local up = 0
    if UIS:IsKeyDown(Enum.KeyCode.Space) then up = 1 end
    if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then up = -1 end

    local maxSpeed = state.movement.flyspeed
    if not maxSpeed or maxSpeed <= 0 then maxSpeed = 50 end
    local moving = (dir.l + dir.r) ~= 0 or (dir.f + dir.b) ~= 0 or up ~= 0

    -- ---- throttle ----------------------------------------------------------
    -- the ramp is scaled with the top speed so it always takes about a second
    -- to reach full speed, no matter which speed is selected
    local ramp = maxSpeed / 50
    if moving then
        flySpeed = flySpeed + (0.5 * ramp) + (flySpeed / maxSpeed)
        if flySpeed > maxSpeed then flySpeed = maxSpeed end
        flyLastDir = dir
        flyLastUp = up
    elseif flySpeed > 0 then
        flySpeed = flySpeed - ramp
        if flySpeed < 0 then flySpeed = 0 end
    end

    -- ---- velocity ----------------------------------------------------------
    if moving then
        setForce(flyThrust, "velocity", "Velocity", flyVelocity(camera, dir, up, flySpeed))
    elseif flySpeed > 0 then
        -- keep gliding the way we were going while the throttle decays
        setForce(flyThrust, "velocity", "Velocity", flyVelocity(camera, flyLastDir, flyLastUp, flySpeed))
    else
        setForce(flyThrust, "velocity", "Velocity", Vector3.new(0, 0.1, 0))
    end

    -- ---- tilt --------------------------------------------------------------
    -- lean the character into the direction of travel
    local tilt = -math.rad((dir.f + dir.b) * 50 * flySpeed / maxSpeed)
    setForce(flyGyro, "cframe", "CFrame", camera.CFrame * CFrame.Angles(tilt, 0, 0))
end

-- Original CanCollide per part, so switching noclip off gives the floor back.
local savedCollide = {}

local function restoreCollide()
    for part, entry in pairs(savedCollide) do
        if part.Parent then
            pcall(function() part.CanCollide = entry.value end)
        end
    end
    savedCollide = {}
end

local function runNoclip()
    if not state.movement.noclip then
        if next(savedCollide) ~= nil then restoreCollide() end
        return
    end
    local c = localCharacter()
    if not c then return end
    for _, part in pairs(c:GetDescendants()) do
        if part:IsA("BasePart") then
            if savedCollide[part] == nil then
                savedCollide[part] = { value = part.CanCollide }
            end
            part.CanCollide = false
        end
    end
end

local function runSafewalk()
    if not state.movement.safewalk then return end
    -- fly already drives the vertical movement: safewalk would pull the
    -- character back to the floor and fight the BodyVelocity
    if state.movement.fly then return end
    local root = localRoot()
    local hum  = localHumanoid()
    if not root or not hum then return end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = losFilter()

    local result = workspace:Raycast(root.Position, Vector3.new(0, -6, 0), params)
    if result then
        local s = hum:GetState()
        if s == Enum.HumanoidStateType.Freefall or s == Enum.HumanoidStateType.FallingDown then
            local v = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end
    end
end

-- ---- combat ------------------------------------------------------------------
local function applyHitbox(size)
    local c = localCharacter()
    if not c then return end
    local parts = { "Head", "HumanoidRootPart", "UpperTorso", "Torso" }
    for _, name in ipairs(parts) do
        local part = c:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            if saved.hitboxes[name] == nil then
                saved.hitboxes[name] = part.Size
            end
            part.Size = Vector3.new(size, size, size)
        end
    end
end

local function restoreHitbox()
    local c = localCharacter()
    for name, size in pairs(saved.hitboxes) do
        local part = c and c:FindFirstChild(name)
        if part then
            part.Size = size
        end
    end
    saved.hitboxes = {}
end

local function runSpinbot(dt)
    if not state.combat.spinbot then return end
    -- while flying the BodyGyro owns the character's orientation: writing the
    -- root here would make the two fight each other
    if state.movement.fly then return end
    local root = localRoot()
    if not root then return end
    root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(state.combat.spinSpeed * 12 * dt), 0)
end

local function applyCameraFOV(value)
    local camera = getCamera()
    if not camera then return end
    if saved.fov == nil then saved.fov = camera.FieldOfView end
    camera.FieldOfView = value
end

local function restoreCameraFOV()
    local camera = getCamera()
    if camera and saved.fov ~= nil then camera.FieldOfView = saved.fov end
    saved.fov = nil
end

-- ---- utilities ---------------------------------------------------------------
-- True while the player is typing in a TextBox (Roblox chat), so hotkeys do not
-- fire in the middle of a message.
local function isTyping()
    local ok, box = pcall(function() return UIS:GetFocusedTextBox() end)
    return ok and box ~= nil
end

local function mouseOverUI()
    local window = Window.instance
    if not window then return false end
    local m = mouseScreen()

    local function inside(frame)
        if not frame or not frame.Visible then return false end
        local p = frame.AbsolutePosition
        local s = frame.AbsoluteSize
        return m.X >= p.X and m.X <= p.X + s.X and m.Y >= p.Y and m.Y <= p.Y + s.Y
    end

    -- the bubble counts too, otherwise Click Teleport fires while reopening it
    return inside(window.frame) or inside(window.bubble)
end

local function clickTeleport()
    local camera = getCamera()
    local root = localRoot()
    if not camera or not root then return end
    local mouse = mouseViewport()
    local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = losFilter()

    local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
    if result then
        -- step out of the surface along its normal, then lift a little, otherwise
        -- the character ends up inside the wall / under the floor
        local spot = result.Position + result.Normal * 3 + Vector3.new(0, 3, 0)
        root.CFrame = CFrame.new(spot)
        root.AssemblyLinearVelocity = Vector3.zero
    end
end

-- Returns true when a teleport was started, otherwise false + a reason.
local function teleportTo(placeId, serverId)
    local ok, ts = pcall(function() return game:GetService("TeleportService") end)
    if not ok or not ts then return false, "no TeleportService" end

    if serverId then
        local done = pcall(function()
            ts:TeleportToPlaceInstance(placeId, serverId, LocalPlayer)
        end)
        if done then return true end
    end

    local done, err = pcall(function() ts:Teleport(placeId, LocalPlayer) end)
    if done then return true end
    return false, err
end

-- Returns true when a hop was started, otherwise false + a reason.
local function serverHop()
    local placeId = game.PlaceId
    if not placeId or placeId == 0 then return false, "no place id" end

    local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=2&limit=100"
    local body = httpGet(url)
    if not body then
        return false, "no HTTP access (request/http_request missing)"
    end

    local ok, decoded = pcall(function() return Http:JSONDecode(body) end)
    if not ok or type(decoded) ~= "table" then return false, "bad server list" end

    local list = decoded.data
    if type(list) ~= "table" or not list[1] then return false, "no public servers found" end

    -- pick a server we are not currently on
    local here = game.JobId
    for _, server in ipairs(list) do
        if type(server) == "table" and server.id and server.id ~= here then
            return teleportTo(placeId, server.id)
        end
    end
    return false, "every server is full"
end

-- Names we look for on disk when re-queueing ourselves after a teleport.
local SOURCE_CACHE_NAME = PROJECT .. ".src"
local LOCAL_SOURCE_NAMES = {
    SOURCE_CACHE_NAME,      -- "SMPWORK.src"  (written by cacheSelfSource)
    PROJECT .. ".lua",      -- "SMPWORK.lua"
    "SMPWORK.lua",
    "MinimaHub-Xeno.lua",
}

-- Cache our own source next to the config so reattach keeps working even
-- when the script was pasted in rather than loaded from disk.
local function cacheSelfSource()
    if type(writefile) ~= "function" then return false end
    if type(readfile) ~= "function" then return false end
    local source = nil
    for _, name in ipairs(LOCAL_SOURCE_NAMES) do
        local chunk = nil
        pcall(function() chunk = readfile(name) end)
        if type(chunk) == "string" and #chunk > 0 then
            source = chunk
            break
        end
    end
    if not source then return false end
    pcall(writefile, SOURCE_CACHE_NAME, source)
    return true
end

-- Returns true when a reattach was queued, otherwise false + a reason.
local function autoReattach()
    if type(queue_on_teleport) ~= "function" then
        return false, "executor has no queue_on_teleport"
    end

    -- 1. a copy we cached earlier
    if type(readfile) == "function" then
        for _, name in ipairs(LOCAL_SOURCE_NAMES) do
            local source = nil
            pcall(function() source = readfile(name) end)
            if type(source) == "string" and #source > 0 then
                queue_on_teleport(source)
                return true
            end
        end
    end

    -- 2. the GitHub copy of this exact script
    if SELF_URL ~= "" and not SELF_URL:find("YOUR_USER", 1, true) then
        queue_on_teleport('loadstring(game:HttpGet("' .. SELF_URL .. '"))()')
        return true
    end
    return false, "no local source and SELF_URL is not configured"
end

-- Compare the version published on GitHub with the running one.
local function checkForUpdates()
    if SELF_URL == "" or SELF_URL:find("YOUR_USER", 1, true) then
        return nil, "SELF_URL is not configured yet"
    end
    local body = httpGet(SELF_URL)
    if not body then return nil, "could not reach GitHub" end

    local remote = body:match('VERSION%s*=%s*"([^"]+)"')
    if not remote then return nil, "remote version not found" end
    if remote == VERSION then return false, "up to date" end
    return true, remote
end

--------------------------------------------------------------------------------
-- 8. CONFIG
--------------------------------------------------------------------------------

local function serialise(value)
    if typeOf(value) == "Color3" then
        return { __c = toHex(value) }
    elseif type(value) == "table" then
        local out = {}
        for k, v in pairs(value) do out[k] = serialise(v) end
        return out
    end
    return value
end

local function deserialise(value)
    if type(value) ~= "table" then return value end
    if value.__c then return fromHex(value.__c) end
    local out = {}
    for k, v in pairs(value) do out[k] = deserialise(v) end
    return out
end

local function deepMerge(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" and not v.__c and type(target[k]) == "table" then
            deepMerge(target[k], v)
        elseif target[k] ~= nil then
            target[k] = v
        end
    end
end

local function copyState()
    local out = {}
    for group, values in pairs(DEFAULTS) do
        out[group] = copyTable(values)
    end
    return out
end

local function saveConfig()
    if type(writefile) ~= "function" then return false end
    local ok, encoded = pcall(function() return Http:JSONEncode(serialise(state)) end)
    if not ok then return false end
    return pcall(writefile, CONFIG_FILE, encoded)
end

local function loadConfig()
    if type(readfile) ~= "function" then return false end
    local ok, content = pcall(readfile, CONFIG_FILE)
    if not ok or type(content) ~= "string" or #content == 0 then return false end
    local ok2, decoded = pcall(function() return Http:JSONDecode(content) end)
    if not ok2 or type(decoded) ~= "table" then return false end
    deepMerge(state, deserialise(decoded))
    for path in pairs(refreshers) do refresh(path) end
    return true
end

local function resetConfig()
    local defaults = copyState()
    deepMerge(state, defaults)
    for path in pairs(refreshers) do refresh(path) end
    applyWalkSpeed(state.movement.walkspeed)
    applyJumpPower(state.movement.jumppower)
    if state.combat.fov then applyCameraFOV(state.combat.fovValue) end
    if state.combat.hitbox then applyHitbox(state.combat.hitboxSz) else restoreHitbox() end
end

--------------------------------------------------------------------------------
-- 9. BUILD THE UI
--------------------------------------------------------------------------------

-- One-click third-party scripts. Every URL below was checked and resolves to
-- a real Lua file (Aug 2026). If one goes stale, paste a new raw URL here.
local EXTERNAL = {
    { name = "Dex Explorer",   url = "https://raw.githubusercontent.com/peyton2465/Dex/master/out.lua" },
    { name = "Infinite Yield", url = "https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source" },
    { name = "SimpleSpy",      url = "https://raw.githubusercontent.com/exxtremestuffs/SimpleSpySource/master/SimpleSpy.lua" },
    { name = "UNC Checker",    url = "https://raw.githubusercontent.com/unified-naming-convention/NamingStandard/main/UNCCheckEnv.lua" },
}

local function buildUI()
    local window = Window.new()
    Window.instance = window

    ------------------------------------------------------------------- visuals
    local vis = window.pages.visuals
    vis:section("ESP")
    vis:toggle("Box", "visuals.espBox", false)
    vis:toggle("Glow", "visuals.espGlow", false)
    vis:toggle("Skeleton", "visuals.espSkeleton", false)
    vis:toggle("Nametag", "visuals.espNametag", false)
    vis:toggle("Tracers", "visuals.espTracer", false)
    vis:toggle("Wall check", "visuals.wallcheck", true)
    vis:hint("Wall check recolours the ESP when the target is behind geometry.")

    vis:section("Colours")
    vis:cycle("Visible", "visuals.boxColorName", PALETTE_ORDER, "Blue")
    vis:cycle("Hidden", "visuals.hiddenColorName", PALETTE_ORDER, "Red")
    vis:cycle("Skeleton", "visuals.skeletonColorName", PALETTE_ORDER, "White")
    vis:cycle("Tracers", "visuals.tracerColorName", PALETTE_ORDER, "Blue")

    ------------------------------------------------------------------------ aim
    local aim = window.pages.aim
    aim:section("Aimbot")
    aim:toggle("Enable aimbot", "aim.enabled", false)
    aim:toggle("Aim without RMB", "aim.always", false)
    aim:toggle("Show FOV ring", "aim.showRing", true)
    aim:toggle("Wall check", "aim.wall", true)
    aim:cycle("Target", "aim.target", { "Head", "UpperTorso", "HumanoidRootPart" }, "Head")
    aim:slider("FOV radius", "aim.fov", 30, 600, 10, 150)
    aim:slider("Max range", "aim.range", 50, 2000, 10, 600)
    aim:slider("Smoothing", "aim.smooth", 1, 40, 1, 6)
    aim:hint("Hold RIGHT MOUSE to aim, or turn on Aim without RMB.")
    aim:hint("Lower smoothing = snappier lock.")

    ------------------------------------------------------------------- movement
    local move = window.pages.movement
    move:section("Movement")
    move:slider("Walk speed", "movement.walkspeed", 0, 200, 1, 16, applyWalkSpeed)
    move:slider("Jump power", "movement.jumppower", 0, 300, 1, 50, applyJumpPower)
    move:section("Toggles")
    move:toggle("Fly", "movement.fly", false)
    move:slider("Fly speed", "movement.flyspeed", 10, 400, 5, 70)
    move:toggle("Noclip", "movement.noclip", false)
    move:toggle("Infinite jump", "movement.infiniteJump", false)
    move:toggle("Safewalk", "movement.safewalk", false)
    move:hint("Fly: WASD to move, Space / LeftControl up and down, E to toggle fly.")
    move:hint("Infinite jump re-jumps while airborne.")

    -------------------------------------------------------------------- combat
    local combat = window.pages.combat
    combat:section("Combat")
    combat:toggle("Hitbox expander", "combat.hitbox", false, function(value)
        if value then
            applyHitbox(state.combat.hitboxSz)
        else
            restoreHitbox()
        end
    end)
    combat:slider("Hitbox size", "combat.hitboxSz", 1, 30, 1, 8, function(value)
        if state.combat.hitbox then applyHitbox(value) end
    end)
    combat:toggle("Spinbot", "combat.spinbot", false)
    combat:slider("Spin speed", "combat.spinSpeed", 1, 60, 1, 20)
    combat:toggle("Custom FOV", "combat.fov", false, function(value)
        if value then
            applyCameraFOV(state.combat.fovValue)
        else
            restoreCameraFOV()
        end
    end)
    combat:slider("FOV value", "combat.fovValue", 50, 120, 1, 90, function(value)
        if state.combat.fov then applyCameraFOV(value) end
    end)

    --------------------------------------------------------------------- utils
    local utils = window.pages.utils
    utils:section("Movement")
    utils:toggle("Click teleport", "utils.clickTP", false)
    utils:hint("With Click teleport on, a left click in the world teleports you there.")
    utils:section("Actions")
    utils:button("TELEPORT TO CURSOR", function()
        clickTeleport()
        window:toast("Teleported to cursor", Theme.good)
    end)
    utils:button("SERVER HOPPER", function()
        window:toast("Finding a server...", Theme.text)
        local ok, why = serverHop()
        if not ok then
            window:toast("Server hop failed: " .. tostring(why), Theme.bad)
        end
    end)
    utils:toggle("Auto reattach", "utils.reattach", true)
    utils:button("QUEUE REATTACH", function()
        local queued, why = autoReattach()
        if queued then
            window:toast("Reattach queued for next teleport", Theme.good)
        else
            window:toast("Reattach not queued: " .. tostring(why), Theme.bad)
        end
    end)
    utils:section("External")
    for _, item in ipairs(EXTERNAL) do
        utils:button("LOAD: " .. item.name, function()
            window:toast("Fetching " .. item.name .. "...", Theme.text)
            local src = httpGet(item.url)
            if type(src) ~= "string" or #src == 0 then
                window:toast("Could not reach " .. item.name, Theme.bad)
                return
            end

            local chunk, err = loadstring(src)
            if type(chunk) ~= "function" then
                window:toast(item.name .. ": " .. tostring(err or "not a script"), Theme.bad)
                return
            end

            local ok, runErr = pcall(chunk)
            if ok then
                window:toast(item.name .. " loaded", Theme.good)
            else
                window:toast(item.name .. " failed: " .. tostring(runErr), Theme.bad)
            end
        end, Theme.panel)
    end
    utils:section("Danger zone")
    utils:button("DESTROY SCRIPT", function()
        if Cleanup then Cleanup.destroy() end
    end, Theme.bad)
    utils:hint("DESTROY removes the GUI, restores hitboxes / speed / FOV and stops every loop.")

    -------------------------------------------------------------------- config
    local cfg = window.pages.config
    cfg:section("Interface")
    cfg:toggle("Bubble mode", "utils.bubble", false, function(value)
        window:setBubble(value)
    end)
    cfg:hint("Collapses the hub to a round bubble with the team photo. Click the bubble to reopen it.")

    cfg:section("Configuration")
    cfg:button("SAVE CONFIG", function()
        if saveConfig() then
            window:toast("Config saved to " .. CONFIG_FILE, Theme.good)
        else
            window:toast("Save failed - no writefile()", Theme.bad)
        end
    end)
    cfg:button("LOAD CONFIG", function()
        if loadConfig() then
            window:setBubble(state.utils.bubble == true)
            window:toast("Config loaded", Theme.good)
        else
            window:toast("No config found", Theme.bad)
        end
    end)
    cfg:button("RESET TO DEFAULTS", function()
        resetConfig()
        window:setBubble(state.utils.bubble == true)
        window:toast("Defaults restored", Theme.text)
    end, Theme.panel)

    cfg:section("GitHub")
    cfg:button("CHECK FOR UPDATES", function()
        window:toast("Checking GitHub...", Theme.text)
        local newer, info = checkForUpdates()
        if newer == nil then
            window:toast("Update check failed: " .. tostring(info), Theme.bad)
        elseif newer then
            window:toast("Update available: v" .. tostring(info), Theme.accent)
        else
            window:toast("You are on the latest version", Theme.good)
        end
    end)
    cfg:button("RELOAD FROM GITHUB", function()
        if SELF_URL == "" or SELF_URL:find("YOUR_USER", 1, true) then
            window:toast("Set SELF_URL first", Theme.bad)
            return
        end
        window:toast("Reloading from GitHub...", Theme.text)
        local src = httpGet(SELF_URL)
        if not src then
            window:toast("Could not reach GitHub", Theme.bad)
            return
        end
        if Cleanup then Cleanup.destroy() end
        local chunk = loadstring(src)
        if chunk then
            chunk()
            window:toast("Reloaded", Theme.good)
        else
            window:toast("Bad source from GitHub", Theme.bad)
        end
    end, Theme.panel)

    cfg:section("Info")
    cfg:hint(PROJECT .. " v" .. VERSION)
    cfg:hint("Config file: " .. CONFIG_FILE)
    cfg:hint("RightControl toggles the overlay.")
    cfg:hint("Made by " .. AUTHOR_A .. " & " .. AUTHOR_B .. ".")

    return window
end

--------------------------------------------------------------------------------
-- 10. RUNTIME LOOPS
--------------------------------------------------------------------------------

local function countOn(...)
    local n = 0
    for i = 1, select("#", ...) do
        if (select(i, ...)) then n = n + 1 end
    end
    return n
end

-- How many features are armed right now (drives the bubble status dot).
local function activeFeatureCount()
    local v, a, m, c = state.visuals, state.aim, state.movement, state.combat
    return countOn(
        v.espBox, v.espGlow, v.espSkeleton, v.espNametag, v.espTracer,
        a.enabled, m.fly, m.noclip, m.infiniteJump, m.safewalk,
        c.hitbox, c.spinbot, c.fov, state.utils.clickTP
    )
end

local function startLoops()
    -- the aimbot runs after the camera module when the executor allows it;
    -- RenderStepped is only the fallback
    local aimInRenderStep = not bindAim()

    connect(Players.PlayerRemoving, function(player)
        clearESP(player)
    end)

    connect(LocalPlayer.CharacterAdded, function(character)
        character:WaitForChild("Humanoid")
        character:WaitForChild("HumanoidRootPart")
        applyWalkSpeed(state.movement.walkspeed)
        applyJumpPower(state.movement.jumppower)
        if state.combat.hitbox then applyHitbox(state.combat.hitboxSz) end
    end)

    connect(RunService.RenderStepped, function(dt)
        -- fade the toast strip back out
        local window = Window.instance
        if window and window.toastLabel and window.toastLabel.Visible then
            window.toastRemaining = window.toastRemaining - dt
            if window.toastRemaining <= 0 then
                window.toastLabel.Visible = false
            elseif window.toastRemaining < 0.5 then
                window.toastLabel.BackgroundTransparency = 0.15 + (0.5 - window.toastRemaining)
            end
        end

        -- keep the ESP cache in sync with the player list
        local anyESP = state.visuals.espBox or state.visuals.espGlow or state.visuals.espSkeleton
            or state.visuals.espNametag or state.visuals.espTracer
        if anyESP then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then ensureESP(player) end
            end
        elseif next(espCache) ~= nil then
            clearAllESP()
        end

        -- each feature is isolated: a broken ESP must not stop fly / aim
        safe("ESP", renderESP)
        if aimInRenderStep then safe("aimbot", runAimbot, dt) end
        safe("fly", runFly, dt)
        safe("spinbot", runSpinbot, dt)

        -- FOV ring
        safe("fov ring", function()
            local ring = ensureFOVRing()
            if not ring then return end
            local camera = getCamera()
            if state.aim.showRing and state.aim.enabled and camera then
                local m = mouseScreen()
                ring.Visible = true
                ring.Position = Vector2.new(m.X, m.Y)
                ring.Radius = state.aim.fov
                ring.Color = Theme.accent
                ring.Transparency = 0.75
            else
                ring.Visible = false
            end
        end)

        -- bubble status: green ring + dot as soon as a feature is armed
        safe("bubble", function()
            local w = Window.instance
            if not w or not w.bubble or not w.bubble.Visible then return end
            local armed = activeFeatureCount() > 0
            if w.bubbleDot then w.bubbleDot.Visible = armed end
            if w.bubbleStroke then
                w.bubbleStroke.Color = armed and Theme.good or Theme.accent
            end
        end)
    end)

    -- physics loop for noclip / safewalk / movement values
    connect(RunService.Stepped, function()
        safe("noclip", runNoclip)
        safe("safewalk", runSafewalk)
        safe("movement", enforceMovement)
    end)

    -- infinite jump
    connect(UIS.JumpRequest, function()
        if not state.movement.infiniteJump then return end
        -- while flying the humanoid is in PlatformStand: jumping would only
        -- fight the BodyVelocity
        if state.movement.fly then return end
        local hum = localHumanoid()
        if hum and hum.FloorMaterial ~= Enum.Material.Air then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)

    -- click teleport
    connect(UIS.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if state.utils.clickTP and not mouseOverUI() then
                clickTeleport()
            end
        end
    end)

    -- UI toggle
    connect(UIS.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.KeyCode
            and input.KeyCode == Enum.KeyCode.RightControl then
            if isTyping() then return end
            if Window.instance then Window.instance:toggleVisible() end
        end
    end)

    -- fly hotkey (E) - the same key the classic fly scripts use
    connect(UIS.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.KeyCode then return end
        if input.KeyCode ~= Enum.KeyCode.E then return end
        if isTyping() then return end

        local enabled = not state.movement.fly
        if enabled and not startFly() then
            if Window.instance then
                Window.instance:toast("Fly needs a character", Theme.bad)
            end
            return
        end
        if not enabled then stopFly() end

        state.movement.fly = enabled
        refresh("movement.fly")
        if Window.instance then
            Window.instance:toast(
                enabled and "Fly enabled (WASD, Space / Ctrl)" or "Fly disabled",
                enabled and Theme.good or Theme.text)
        end
    end)
end

--------------------------------------------------------------------------------
-- 11. CLEANUP
--------------------------------------------------------------------------------

Cleanup = {}

function Cleanup.destroy()
    -- stop loops
    for _, c in ipairs(Connections) do
        pcall(function() c:Disconnect() end)
    end
    Connections = {}

    -- stop the post-camera aim loop
    unbindAim()

    -- remove the fly forces and give the character back to the game
    stopFly()
    state.movement.fly = false

    -- kill drawings
    clearAllESP()
    if fovRing then
        removeDrawing(fovRing)
        fovRing = nil
    end

    -- restore the character
    restoreHitbox()
    restoreCollide()
    local hum = localHumanoid()
    if hum then
        if saved.walkspeed ~= nil then hum.WalkSpeed = saved.walkspeed end
        if saved.jumppower ~= nil then hum.JumpPower = saved.jumppower end
        if saved.useJumpPower ~= nil then hum.UseJumpPower = saved.useJumpPower end
    end
    restoreCameraFOV()
    saved.walkspeed = nil
    saved.jumppower = nil
    saved.useJumpPower = nil

    -- remove the GUI
    if Window.instance then
        Window.instance.destroyed = true
        if Window.instance.gui then
            pcall(function() Window.instance.gui:Destroy() end)
        end
    end
    Window.instance = nil
end

--------------------------------------------------------------------------------
-- 12. BOOT
--------------------------------------------------------------------------------

local function boot()
    -- build the UI first so the widgets exist, then overlay the saved config
    local window = buildUI()
    startLoops()

    loadConfig()

    -- the saved config may ask for the compact bubble instead of the panel
    if state.utils.bubble and Window.instance then
        Window.instance:setBubble(true)
    end

    -- keep a copy of ourselves on disk so a teleport can re-run us
    cacheSelfSource()

    -- apply the loaded / default values once
    applyWalkSpeed(state.movement.walkspeed)
    applyJumpPower(state.movement.jumppower)
    if state.combat.fov then applyCameraFOV(state.combat.fovValue) end
    if state.combat.hitbox then applyHitbox(state.combat.hitboxSz) end
    if state.utils.reattach then autoReattach() end

    print("[" .. PROJECT .. "] " .. AUTHOR_A .. " & " .. AUTHOR_B .. " - v" .. VERSION
        .. " loaded. RightControl toggles the UI.")
    return window
end

local ok, err = pcall(boot)
if not ok then
    print("[" .. PROJECT .. "] boot failed: " .. tostring(err))
    -- never fail silently: show something on screen so the user knows why
    pcall(function()
        local holder = Instance.new("ScreenGui")
        holder.Name = "SMPWORKError"
        holder.DisplayOrder = 2147483647
        holder.ResetOnSpawn = false
        holder.Parent = resolveGuiParent()

        local box = Instance.new("TextLabel")
        box.Size = UDim2.new(0, 460, 0, 96)
        box.Position = UDim2.new(0, 40, 0, 40)
        box.BackgroundColor3 = Color3.fromRGB(28, 12, 12)
        box.BackgroundTransparency = 0.1
        box.BorderSizePixel = 0
        box.TextColor3 = Color3.fromRGB(255, 140, 140)
        box.TextSize = 13
        box.TextWrapped = true
        box.TextXAlignment = Enum.TextXAlignment.Left
        box.TextYAlignment = Enum.TextYAlignment.Top
        box.Font = Enum.Font.Code
        box.Text = "SMPWORK v" .. VERSION .. " failed to start\n\n" .. tostring(err)
            .. "\n\nCopy this text to the developer."
        box.Parent = holder

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 10)
        pad.PaddingBottom = UDim.new(0, 10)
        pad.PaddingLeft = UDim.new(0, 12)
        pad.PaddingRight = UDim.new(0, 12)
        pad.Parent = box
    end)
end

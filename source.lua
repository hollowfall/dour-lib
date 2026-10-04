--[[
	Dour Interface Suite
	A single-file Luau UI library for Roblox executors.
	https://github.com/dlyrr/dour-lib

	local Dour = loadstring(game:HttpGet("https://raw.githubusercontent.com/dlyrr/dour-lib/main/source.lua"))()

	local Window = Dour:CreateWindow({ Name = "my hub" })
	local Tab = Window:CreateTab("main", "home")
	Tab:CreateToggle({ Name = "godmode", Flag = "god", Callback = function(on) end })

	print(Dour:GetFlag("god"))   -- read any flagged element from anywhere

	Docs: docs/api.md, docs/theming.md, docs/configuration.md, docs/migrating.md
	Restyling: every colour, radius, font and duration lives in the Theme table
	below, and Dour:SetTheme applies changes to elements that already exist.
--]]

--============================== Services ==============================

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local CoreGui           = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

--============================== Theme ==============================

local Theme = {
	Accent            = Color3.fromRGB(94, 132, 255),
	AccentDim         = Color3.fromRGB(64, 90, 180),

	Base              = Color3.fromRGB(16, 16, 18),
	BaseTransparency  = 0.15,

	Panel             = Color3.fromRGB(30, 30, 35),
	PanelTransparency = 0.45,

	Element           = Color3.fromRGB(44, 44, 52),
	ElementIdle       = 0.45,
	ElementHover      = 0.28,
	ElementPress      = 0.18,

	Input             = Color3.fromRGB(24, 24, 28),
	InputTransparency = 0.25,

	Stroke            = Color3.fromRGB(255, 255, 255),
	StrokeTransparency = 0.85,

	Text              = Color3.fromRGB(238, 238, 245),
	SubText           = Color3.fromRGB(155, 155, 168),
	Shadow            = Color3.fromRGB(0, 0, 0),

	Radius = { Window = 16, Element = 10, Input = 8, Pill = 10 },

	-- Inter is not bundled with the Roblox client. If the static TTFs are in the
	-- executor workspace they are wired up on load (see interFamily below);
	-- otherwise this falls back to Builder Sans, Roblox's own Inter-alike.
	Font = {
		Family = "rbxasset://fonts/families/BuilderSans.json",
		Weights = {
			Title = Enum.FontWeight.Bold,
			Label = Enum.FontWeight.Medium,
			Body  = Enum.FontWeight.Regular,
		},
	},
	TextSize = { Title = 15, Label = 14, Body = 13 },

	Tween = { Fast = 0.15, Normal = 0.25, Slow = 0.35 },

	ShadowAsset = "rbxassetid://6014261993",
	ShadowSlice = Rect.new(49, 49, 450, 450),
}

--============================== Library root ==============================

local Lib = {
	Version = "1.0.0",
	Animations = true,
	NotifyErrors = false, -- set true to surface callback errors as notifications
	Flags = {},
	Theme = Theme,
	Windows = {},
}

-- Real Inter, if its faces are sitting in the executor workspace. Roblox ignores
-- a variable font's weight axis, so three static files are required rather than
-- one variable one. Returns a family content id, or nil to keep the fallback.
local INTER_DIR = "dour_fonts"
local INTER_FACES = {
	{ name = "Regular", weight = 400, file = "Inter-Regular.ttf" },
	{ name = "Medium", weight = 500, file = "Inter-Medium.ttf" },
	{ name = "Bold", weight = 700, file = "Inter-Bold.ttf" },
}

local function interFamily(dir)
	dir = dir or INTER_DIR
	if not (getcustomasset and isfile and writefile) then return nil end

	local faces = {}
	for _, face in ipairs(INTER_FACES) do
		local path = dir .. "/" .. face.file
		local ok, present = pcall(isfile, path)
		if not (ok and present) then return nil end
		local gotAsset, asset = pcall(getcustomasset, path)
		if not gotAsset then return nil end
		table.insert(faces, { name = face.name, weight = face.weight, style = "normal", assetId = asset })
	end

	local jsonPath = dir .. "/Dour-Inter.json"
	local wrote = pcall(function()
		writefile(jsonPath, HttpService:JSONEncode({ name = "Inter", faces = faces }))
	end)
	if not wrote then return nil end

	local gotFamily, family = pcall(getcustomasset, jsonPath)
	return gotFamily and family or nil
end

Theme.Font.Family = interFamily() or Theme.Font.Family

-- Font objects are rebuilt whenever the family changes; every text instance is
-- created with FontFace, never the legacy Font enum.
local function buildFaces()
	for role, weight in pairs(Theme.Font.Weights) do
		Theme.Font[role] = Font.new(Theme.Font.Family, weight)
	end
end
buildFaces()

local Mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local ELEMENT_H = Mobile and 42 or 34
local ROW_PAD   = 8

--============================== Utilities ==============================

local Connections = {}
local function track(connection)
	table.insert(Connections, connection)
	return connection
end

local function create(class, props, children)
	local inst = Instance.new(class)
	local parent
	if props then
		parent = props.Parent
		for key, value in pairs(props) do
			if key ~= "Parent" then
				-- Theme.Font.* are Font objects, which belong on FontFace
				if key == "Font" and typeof(value) == "Font" then
					inst.FontFace = value
				else
					inst[key] = value
				end
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- Every animation in the library funnels through here so Lib.Animations can kill them all.
local function tween(inst, props, dur, style, dir)
	if not Lib.Animations then
		for key, value in pairs(props) do
			inst[key] = value
		end
		return nil
	end
	local info = TweenInfo.new(
		dur or Theme.Tween.Normal,
		style or Enum.EasingStyle.Quint,
		dir or Enum.EasingDirection.Out
	)
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

local function corner(inst, radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius.Element), Parent = inst })
end

local function stroke(inst, transparency, color)
	return create("UIStroke", {
		Color = color or Theme.Stroke,
		Transparency = transparency or Theme.StrokeTransparency,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
end

local function padding(inst, top, bottom, left, right)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, top or 0),
		PaddingBottom = UDim.new(0, bottom or top or 0),
		PaddingLeft = UDim.new(0, left or 0),
		PaddingRight = UDim.new(0, right or left or 0),
		Parent = inst,
	})
end

-- Diagonal highlight that reads as a glass sheen.
-- It has to be its own layer: a UIGradient parented straight to the panel would
-- modulate the panel's own BackgroundTransparency and wash the whole thing out.
local function glass(inst, strength, radius)
	strength = strength or 0.06
	local sheen = create("Frame", {
		Name = "Glass",
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		ZIndex = inst.ZIndex,
		Parent = inst,
	})
	create("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius.Element), Parent = sheen })
	create("UIGradient", {
		Rotation = 45,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0.00, 1 - strength),
			NumberSequenceKeypoint.new(0.45, 1),
			NumberSequenceKeypoint.new(1.00, 1 - strength * 0.4),
		}),
		Parent = sheen,
	})
	return sheen
end

-- 9-slice drop/inner shadow, sits behind whatever it is attached to.
local function shadow(inst, spread, transparency)
	spread = spread or 26
	return create("ImageLabel", {
		Name = "Shadow",
		BackgroundTransparency = 1,
		Image = Theme.ShadowAsset,
		ImageColor3 = Theme.Shadow,
		ImageTransparency = transparency or 0.55,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Theme.ShadowSlice,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, spread * 2, 1, spread * 2),
		ZIndex = 0,
		Parent = inst,
	})
end

-- CanvasGroup gives us one-property fades; degrade to a Frame on older clients.
local function group(props)
	local ok, inst = pcall(function()
		return create("CanvasGroup", props)
	end)
	if ok and inst then
		return inst, true
	end
	return create("Frame", props), false
end

local function setGroupTransparency(inst, isGroup, alpha, dur, style, dir)
	if isGroup then
		tween(inst, { GroupTransparency = alpha }, dur, style, dir)
	else
		inst.Visible = alpha < 1
	end
end

local function ripple(parent, x, y)
	if not Lib.Animations then return end
	local abs = parent.AbsolutePosition
	local size = parent.AbsoluteSize
	local px = (x or (abs.X + size.X / 2)) - abs.X
	local py = (y or (abs.Y + size.Y / 2)) - abs.Y
	local reach = math.max(size.X, size.Y) * 1.6

	local circle = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.82,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(px, py),
		Size = UDim2.fromOffset(0, 0),
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = parent,
	})
	create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = circle })

	tween(circle, { Size = UDim2.fromOffset(reach, reach), BackgroundTransparency = 1 }, 0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	task.delay(0.5, function()
		circle:Destroy()
	end)
end

local function hoverable(inst, idle, hover)
	idle = idle or Theme.ElementIdle
	hover = hover or Theme.ElementHover
	track(inst.MouseEnter:Connect(function()
		tween(inst, { BackgroundTransparency = hover }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
	end))
	track(inst.MouseLeave:Connect(function()
		tween(inst, { BackgroundTransparency = idle }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
	end))
end

-- Every user callback goes through here: an error in one is reported instead of
-- vanishing into a pcall, and never takes the library down with it.
function Lib.OnError(context, message)
	warn("[Dour] " .. context .. ": " .. message)
end

local function safeCall(context, fn, ...)
	if type(fn) ~= "function" then return end
	local packed = table.pack(...)
	local ok, err = pcall(function()
		return fn(table.unpack(packed, 1, packed.n))
	end)
	if ok then return end

	local message = tostring(err)
	if type(Lib.OnError) == "function" then
		pcall(Lib.OnError, context, message)
	end
	if Lib.NotifyErrors then
		Lib:Notify({ Title = "Script Error", Content = context .. " - " .. message, Duration = 8, Image = "alert" })
	end
end

local function warnOnce(message)
	warn("[Dour] " .. message)
end

-- Keys arrive as "RightShift" or Enum.KeyCode.RightShift depending on the script.
local function toKeyCode(key)
	if typeof(key) == "EnumItem" then return key end
	if type(key) == "string" then
		local ok, code = pcall(function() return Enum.KeyCode[key] end)
		if ok then return code end
		warnOnce("'" .. key .. "' is not a KeyCode name")
	end
	return nil
end

local function round(value, increment)
	if not increment or increment <= 0 then return value end
	return math.floor(value / increment + 0.5) * increment
end

--============================== Icons ==============================
-- Lucide-style names mapped to assets. Unknown names simply render no icon.

local Icons = {
	home     = "rbxassetid://10723407389",
	settings = "rbxassetid://10734950309",
	user     = "rbxassetid://10747373176",
	sparkles = "rbxassetid://10734898355",
	check    = "rbxassetid://10709790644",
	plus     = "rbxassetid://10734896206",
	alert    = "rbxassetid://10734924532",
	folder   = "rbxassetid://10723387563",
	info     = "rbxassetid://10723415903",
	chevron  = "rbxassetid://10709790948",
	expand   = "rbxassetid://10734886735",
	cursor   = "rbxasset://textures/ArrowFarCursor.png",
	target   = "rbxassetid://10709818534",
}

-- Drawn rather than fetched: there is no verified lucide asset id for an eye, so
-- it is built to lucide's own geometry (24x24 viewBox) - two circle arcs of
-- r=10.75 centred +-3.945 off the middle form the lids, plus an r=3 pupil. Each
-- arc is a stroked circle clipped to its half. The drawing is inset by half the
-- stroke width so nothing is shaved off at the edges.
local function drawEye(parent, size, color, props)
	local thickness = math.max(1, size / 12)
	local u = (size - thickness) / 24
	local pad = thickness / 2
	local R = 10.75 * u
	local lidOffset = 3.945 * u
	local cx, cy = pad + 12 * u, pad + 12 * u

	local holder = create("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	})
	for key, value in pairs(props or {}) do
		holder[key] = value
	end

	local strokes = {}

	local function ring(parentFrame, diameter, x, y)
		local circle = create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(diameter, diameter),
			Parent = parentFrame,
		})
		create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = circle })
		table.insert(strokes, create("UIStroke", {
			Color = color,
			Thickness = thickness,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = circle,
		}))
		return circle
	end

	-- each lid is the half of a big circle that falls on its side of the centre line
	local function lid(top, circleCentreY)
		local clip = create("Frame", {
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(0, top),
			Size = UDim2.fromOffset(size, cy - top > 0 and cy - top or size - top),
			Parent = holder,
		})
		ring(clip, R * 2, cx - R, circleCentreY - R - top)
	end

	lid(0, cy + lidOffset)                     -- upper
	local lower = create("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(0, cy),
		Size = UDim2.fromOffset(size, size - cy),
		Parent = holder,
	})
	ring(lower, R * 2, cx - R, (cy - lidOffset) - R - cy)

	ring(holder, 6 * u, cx - 3 * u, cy - 3 * u) -- pupil, concentric with the lids

	return holder, function(newColor)
		for _, stroke in ipairs(strokes) do
			tween(stroke, { Color = newColor }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
		end
	end
end

-- The lucide minus asset does not reliably load at small sizes, and a missing
-- icon on the minimise button reads as a broken window, so it is drawn too.
local function drawMinus(parent, size, color, props)
	local holder = create("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	})
	for key, value in pairs(props or {}) do
		holder[key] = value
	end

	local bar = create("Frame", {
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size * 0.8, math.max(1, size / 8)),
		BorderSizePixel = 0,
		Parent = holder,
	})
	create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = bar })

	return holder, function(newColor)
		tween(bar, { BackgroundColor3 = newColor }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
	end
end

local function drawCross(parent, size, color, props)
	local holder = create("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	})
	for key, value in pairs(props or {}) do
		holder[key] = value
	end

	local bars = {}
	for _, rotation in ipairs({ 45, -45 }) do
		local bar = create("Frame", {
			BackgroundColor3 = color,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size * 0.82, math.max(1, size / 8)),
			Rotation = rotation,
			BorderSizePixel = 0,
			Parent = holder,
		})
		create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = bar })
		table.insert(bars, bar)
	end

	return holder, function(newColor)
		for _, bar in ipairs(bars) do
			tween(bar, { BackgroundColor3 = newColor }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
		end
	end
end

local Drawn = { eye = drawEye, minus = drawMinus, x = drawCross }

-- Returns an image asset, or a glyph string for entries that are plain text.
local function iconAsset(name)
	if type(name) ~= "string" or name == "" then return nil end
	if name:match("^rbxassetid://") or name:match("^rbxasset://") then return name end
	if tonumber(name) then return "rbxassetid://" .. name end
	local key = name:lower()
	if Drawn[key] then return key end
	local mapped = Icons[key]
	if mapped then return mapped end
	-- anything else short (an emoji, a single character) is used verbatim as a glyph
	local len = utf8.len(name)
	if len and len <= 2 then return name end
	return nil
end

local function isGlyph(spec)
	return type(spec) == "string" and not spec:match("^rbxasset")
end

-- One icon slot: a drawn icon, an image, or a glyph. Returns the instance and a
-- tint function, because each kind recolours through a different property.
local function makeIcon(parent, spec, size, color, props)
	if not spec then return nil end
	if Drawn[spec] then
		return Drawn[spec](parent, size, color, props)
	end

	local base = {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	}
	for key, value in pairs(props or {}) do
		base[key] = value
	end

	if isGlyph(spec) then
		base.Text = spec
		base.Font = Theme.Font.Body
		base.TextSize = size
		base.TextColor3 = color
		local label = create("TextLabel", base)
		return label, function(newColor)
			tween(label, { TextColor3 = newColor }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
		end
	end

	base.Image = spec
	base.ImageColor3 = color
	local image = create("ImageLabel", base)
	return image, function(newColor)
		tween(image, { ImageColor3 = newColor }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
	end
end

--============================== GUI parenting ==============================

local function guiParent()
	local ok, hidden = pcall(function()
		return gethui and gethui() or nil
	end)
	if ok and hidden then return hidden end

	local ok2 = pcall(function()
		return CoreGui.Name
	end)
	if ok2 then return CoreGui end

	return LocalPlayer:WaitForChild("PlayerGui")
end

local ScreenGui = create("ScreenGui", {
	Name = "Dour Lib",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 9999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
pcall(function()
	ScreenGui.Parent = guiParent()
end)
pcall(function()
	if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end
end)

--============================== Tooltips ==============================
-- Rows truncate rather than wrap, which keeps their height predictable but
-- hides the tail of a long description. Hovering a clipped label shows all of
-- it. TextBounds reports the truncated width, so TextFits is what answers
-- "is this actually cut off".

local Tooltip = { card = nil, label = nil, owner = nil }

local function buildTooltip()
	if Tooltip.card then return end

	Tooltip.card = create("Frame", {
		Name = "Tooltip",
		BackgroundColor3 = Theme.Element,
		BackgroundTransparency = 0.05,
		Visible = false,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 500,
		BorderSizePixel = 0,
		Parent = ScreenGui,
	})
	corner(Tooltip.card, 8)
	stroke(Tooltip.card)
	padding(Tooltip.card, 7, 8, 11, 11)

	Tooltip.label = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		Text = "",
		TextColor3 = Theme.Text,
		TextSize = Theme.TextSize.Body - 1,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 501,
		Parent = Tooltip.card,
	})
	create("UISizeConstraint", { MaxSize = Vector2.new(280, math.huge), Parent = Tooltip.label })
end

local function isClipped(label)
	if not (label:IsA("TextLabel") or label:IsA("TextButton") or label:IsA("TextBox")) then return false end
	local ok, fits = pcall(function() return label.TextFits end)
	if ok then return not fits end
	return label.TextBounds.X > label.AbsoluteSize.X + 1
end

local function attachTooltip(hover, label, resolve)
	buildTooltip()

	track(hover.MouseEnter:Connect(function()
		local body = resolve and resolve() or label.Text
		if body == "" or not isClipped(label) then return end
		Tooltip.owner = hover
		Tooltip.label.Text = body
		Tooltip.card.Visible = true
		local mouse = UserInputService:GetMouseLocation()
		Tooltip.card.Position = UDim2.fromOffset(mouse.X + 14, mouse.Y - 6)
	end))

	track(hover.MouseMoved:Connect(function()
		if Tooltip.owner ~= hover then return end
		local mouse = UserInputService:GetMouseLocation()
		Tooltip.card.Position = UDim2.fromOffset(mouse.X + 14, mouse.Y - 6)
	end))

	track(hover.MouseLeave:Connect(function()
		if Tooltip.owner ~= hover then return end
		Tooltip.owner = nil
		Tooltip.card.Visible = false
	end))
end

--============================== Configuration saving ==============================

local FileSystemReady = (writefile and readfile and isfolder and makefolder) and true or false

local function encodeValue(value)
	if typeof(value) == "Color3" then
		return { __t = "Color3", math.floor(value.R * 255), math.floor(value.G * 255), math.floor(value.B * 255) }
	elseif typeof(value) == "EnumItem" then
		return { __t = "Enum", tostring(value.EnumType), value.Name }
	end
	return value
end

local function decodeValue(value)
	if type(value) == "table" and value.__t == "Color3" then
		return Color3.fromRGB(value[1], value[2], value[3])
	elseif type(value) == "table" and value.__t == "Enum" then
		local ok, item = pcall(function()
			return Enum[value[2]:gsub("^Enum%.", "")][value[3]]
		end)
		return ok and item or nil
	end
	return value
end

-- Configs live as <FolderName>/<FileName>.json for the automatic one and
-- <FolderName>/configs/<name>.json for named profiles the user manages.
local function configFolder(window)
	return window.Config.FolderName .. "/configs"
end

local function configPath(window, name)
	if name then
		return configFolder(window) .. "/" .. name .. ".json"
	end
	return window.Config.FolderName .. "/" .. window.Config.FileName .. ".json"
end

local function collectFlags(window)
	local payload = {}
	for flag, element in pairs(window.FlagElements) do
		if element.ExcludeFromConfig then continue end
		local value = Lib.Flags[flag] and Lib.Flags[flag].CurrentValue
		if value == nil and element.Get then
			value = element:Get()
		end
		payload[flag] = encodeValue(value)
	end
	return payload
end

local function applyFlags(window, data)
	for flag, value in pairs(data) do
		local element = window.FlagElements[flag]
		if element and element.Set then
			local ok, err = pcall(function()
				element:Set(decodeValue(value))
			end)
			if not ok then
				warnOnce("flag '" .. tostring(flag) .. "' could not be restored: " .. tostring(err))
			end
		end
	end
end

local function saveConfig(window)
	if not FileSystemReady then return end
	local cfg = window.Config
	if not (cfg and cfg.Enabled) then return end

	local ok, err = pcall(function()
		if not isfolder(cfg.FolderName) then
			makefolder(cfg.FolderName)
		end
		local payload = collectFlags(window)
		writefile(cfg.FolderName .. "/" .. cfg.FileName .. ".json", HttpService:JSONEncode(payload))
	end)
	if not ok then
		warnOnce("could not save configuration: " .. tostring(err))
	end
end

local function loadConfig(window)
	if not FileSystemReady then return end
	local cfg = window.Config
	if not (cfg and cfg.Enabled) then return end

	local ok, err = pcall(function()
		local path = cfg.FolderName .. "/" .. cfg.FileName .. ".json"
		if not isfile or not isfile(path) then
			if not readfile then return end
		end
		local raw = readfile(path)
		if not raw or raw == "" then return end
		local data = HttpService:JSONDecode(raw)
		for flag, value in pairs(data) do
			local element = window.FlagElements[flag]
			if element and element.Set then
				local setOk, setErr = pcall(function()
					element:Set(decodeValue(value))
				end)
				if not setOk then
					warnOnce("flag '" .. tostring(flag) .. "' could not be restored: " .. tostring(setErr))
				end
			end
		end
	end)
	if not ok then
		warnOnce("could not load configuration: " .. tostring(err))
	end
end

--============================== Notifications ==============================

local NotifyHolder = create("Frame", {
	Name = "Notifications",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -18, 1, -18),
	Size = UDim2.fromOffset(300, 600),
	Parent = ScreenGui,
})

local ActiveNotifications = {}
local NotifyDir = 1 -- 1 = slides in from the right edge, -1 = from the left

function Lib:SetNotifySide(side)
	local left = tostring(side):lower() == "left"
	NotifyDir = left and -1 or 1
	NotifyHolder.AnchorPoint = Vector2.new(left and 0 or 1, 1)
	NotifyHolder.Position = UDim2.new(left and 0 or 1, left and 18 or -18, 1, -18)
end

local function restackNotifications()
	local y = 0
	for i = #ActiveNotifications, 1, -1 do
		local card = ActiveNotifications[i]
		y = y + card.AbsoluteSize.Y + 10
		tween(card, { Position = UDim2.new(0, 0, 1, -y) }, Theme.Tween.Normal)
	end
end

function Lib:Notify(options)
	options = options or {}
	local duration = options.Duration or 5

	local card, isGroup = group({
		Name = "Notification",
		BackgroundColor3 = Theme.Base,
		BackgroundTransparency = Theme.BaseTransparency,
		Position = UDim2.new(0, 340 * NotifyDir, 1, 0),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		Parent = NotifyHolder,
	})
	corner(card, Theme.Radius.Element + 2)
	stroke(card)
	glass(card, 0.08, Theme.Radius.Element + 2)
	shadow(card, 22, 0.6)
	padding(card, 12, 12, 14, 14)

	local iconSpec = iconAsset(options.Image)
	local hasIcon = iconSpec ~= nil
	if hasIcon then
		makeIcon(card, iconSpec, 18, Theme.Accent, { Position = UDim2.fromOffset(0, 1) })
	end

	local textX = hasIcon and 26 or 0
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font.Title,
		Text = tostring(options.Title or "Notification"),
		TextColor3 = Theme.Text,
		TextSize = Theme.TextSize.Label,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(textX, 0),
		Size = UDim2.new(1, -textX, 0, 18),
		Parent = card,
	})

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		Text = tostring(options.Content or ""),
		TextColor3 = Theme.SubText,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Position = UDim2.fromOffset(textX, 20),
		Size = UDim2.new(1, -textX, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	})

	-- Actions render as buttons under the content. Accepts an array or a keyed
	-- table, matching how Rayfield scripts write them.
	local actions = options.Actions
	if type(actions) == "table" then
		local ordered = {}
		if #actions > 0 then
			ordered = actions
		else
			for key, action in pairs(actions) do
				action.Name = action.Name or key
				table.insert(ordered, action)
			end
		end

		if #ordered > 0 then
			local strip = create("Frame", {
				Name = "Actions",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 26),
				Parent = card,
			})
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = strip,
			})

			for index, action in ipairs(ordered) do
				local button = create("TextButton", {
					AutoButtonColor = false,
					BackgroundColor3 = index == 1 and Theme.Accent or Theme.Element,
					BackgroundTransparency = index == 1 and 0.05 or 0.4,
					Font = Theme.Font.Label,
					Text = tostring(action.Name or action.Text or "OK"),
					TextColor3 = Theme.Text,
					TextSize = Theme.TextSize.Body,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.new(0, 0, 0, 22),
					LayoutOrder = index,
					BorderSizePixel = 0,
					Parent = strip,
				})
				corner(button, Theme.Radius.Input)
				padding(button, 0, 0, 12, 12)
				hoverable(button, index == 1 and 0.05 or 0.4, index == 1 and 0 or 0.2)
				track(button.MouseButton1Click:Connect(function()
					safeCall("notification action '" .. button.Text .. "'", action.Callback)
					if card:FindFirstChild("Actions") then
						card.Actions:Destroy()
					end
					if options.__dismiss then options.__dismiss() end
				end))
			end
		end
	end

	table.insert(ActiveNotifications, card)
	task.defer(restackNotifications)
	if isGroup then card.GroupTransparency = 1 end
	setGroupTransparency(card, isGroup, 0, Theme.Tween.Slow)

	local function dismiss()
		local index = table.find(ActiveNotifications, card)
		if not index then return end
		table.remove(ActiveNotifications, index)
		tween(card, { Position = UDim2.new(0, 340 * NotifyDir, card.Position.Y.Scale, card.Position.Y.Offset) }, Theme.Tween.Normal, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		setGroupTransparency(card, isGroup, 1, Theme.Tween.Normal)
		restackNotifications()
		task.delay(Theme.Tween.Normal + 0.05, function()
			card:Destroy()
		end)
	end

	options.__dismiss = dismiss
	task.delay(duration, dismiss)

	return { Dismiss = dismiss, Destroy = dismiss, Instance = card }
end

--============================== Element constructors ==============================
-- Each returns a table exposing :Set(value) and :Destroy().

-- Rows grow for a Description line; Height overrides both.
local function rowHeight(opts, base)
	base = base or ELEMENT_H
	if type(opts) ~= "table" then return base end
	if opts.Height then return opts.Height end
	if opts.Description and opts.Description ~= "" then return base + 16 end
	return base
end

local function baseRow(tab, height, class)
	local row = create(class or "Frame", {
		Name = "Row",
		BackgroundColor3 = Theme.Element,
		BackgroundTransparency = Theme.ElementIdle,
		Size = UDim2.new(1, 0, 0, height or ELEMENT_H),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = tab.Page,
	})
	if class == "TextButton" then
		row.Text = ""
		row.AutoButtonColor = false
	end
	corner(row, Theme.Radius.Element)
	stroke(row)
	glass(row, 0.04)
	padding(row, 0, 0, 12, 12)
	return row
end

-- opts may be a plain string or an element options table (Name / Description / Icon).
local function rowLabel(row, opts, width, fallback)
	local name, desc, icon
	if type(opts) == "table" then
		name, desc, icon = opts.Name, opts.Description, iconAsset(opts.Icon)
	else
		name = opts
	end
	name = tostring(name or fallback or "")
	local hasDesc = desc ~= nil and desc ~= ""
	local x = 0

	if icon then
		makeIcon(row, icon, 16, Theme.SubText, {
			Name = "RowIcon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
		})
		x = 24
	end

	local titleText, bodyText = name, hasDesc and tostring(desc) or nil

	local title = create("TextLabel", {
		Name = "RowTitle",
		BackgroundTransparency = 1,
		Font = Theme.Font.Label,
		Text = name,
		TextColor3 = Theme.Text,
		TextSize = Theme.TextSize.Label,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = hasDesc and Enum.TextYAlignment.Bottom or Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(x, 0),
		Size = hasDesc and UDim2.new(width or 0.6, -x, 0.5, -1) or UDim2.new(width or 0.6, -x, 1, 0),
		Parent = row,
	})

	attachTooltip(row, title, function()
		return bodyText and (titleText .. "\n" .. bodyText) or titleText
	end)

	if hasDesc then
		local description = create("TextLabel", {
			Name = "RowDescription",
			BackgroundTransparency = 1,
			Font = Theme.Font.Body,
			Text = tostring(desc),
			TextColor3 = Theme.SubText,
			TextSize = Theme.TextSize.Body - 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.new(0, x, 0.5, 1),
			Size = UDim2.new(width or 0.6, -x, 0.5, -1),
			Parent = row,
		})
		attachTooltip(row, description, function() return bodyText end)
	end

	return title
end

-- Locking dims the row and disables its interactive instances.
local function lockable(element, row, interactive)
	element.Locked = false
	function element:SetLocked(state)
		element.Locked = state and true or false
		for _, inst in ipairs(interactive) do
			if inst:IsA("GuiButton") then
				pcall(function() inst.Interactable = not element.Locked end)
			elseif inst:IsA("TextBox") then
				inst.TextEditable = not element.Locked
				inst.Selectable = not element.Locked
			end
		end
		for _, child in ipairs(row:GetDescendants()) do
			if child:IsA("TextLabel") then
				tween(child, { TextTransparency = element.Locked and 0.6 or 0 }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
			end
		end
	end
end

local function registerFlag(tab, flag, element, options)
	if options and options.Ext then
		element.ExcludeFromConfig = true
	end
	if not flag then return end
	Lib.Flags[flag] = element
	tab.Window.FlagElements[flag] = element
end

--========== Button ==========

local function CreateButton(tab, options)
	options = options or {}
	local row = baseRow(tab, rowHeight(options), "TextButton")
	local label = rowLabel(row, options, 1, "Button")

	create("ImageLabel", {
		Name = "Affordance",
		BackgroundTransparency = 1,
		Image = Icons.sparkles,
		ImageColor3 = Theme.Accent,
		ImageTransparency = 0.1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(15, 15),
		Parent = row,
	})

	hoverable(row)
	track(row.MouseButton1Down:Connect(function()
		local mouse = UserInputService:GetMouseLocation()
		ripple(row, mouse.X, mouse.Y - 36)
	end))
	track(row.MouseButton1Click:Connect(function()
		task.spawn(function()
			safeCall(tostring(options.Name or "element") .. " callback", options.Callback)
		end)
	end))

	local element = { Type = "Button", Instance = row }
	lockable(element, row, { row })
	function element:Set(text)
		label.Text = tostring(text)
	end
	function element:Destroy()
		row:Destroy()
	end
	return element
end

--========== Button group ==========
-- Several related actions on one row, so three buttons do not become three cards.

local function CreateButtonGroup(tab, options)
	options = options or {}
	local specs = options.Buttons or {}
	local row = baseRow(tab, rowHeight(options))
	local labelled = options.Name ~= nil and options.Name ~= ""
	if labelled then
		rowLabel(row, options, 0.42, "Actions")
	end

	local holder = create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(labelled and 0.58 or 1, 0, 0, ELEMENT_H - 12),
		Parent = row,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = labelled and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = holder,
	})

	local made = {}
	for index, spec in ipairs(specs) do
		local button = create("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = spec.Primary and Theme.Accent or Theme.Input,
			BackgroundTransparency = spec.Primary and 0.05 or Theme.InputTransparency,
			Font = Theme.Font.Label,
			Text = tostring(spec.Text or "..."),
			TextColor3 = Theme.Text,
			TextSize = Theme.TextSize.Body,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			LayoutOrder = index,
			BorderSizePixel = 0,
			Parent = holder,
		})
		corner(button, Theme.Radius.Input)
		stroke(button)
		padding(button, 0, 0, 14, 14)
		hoverable(button, spec.Primary and 0.05 or Theme.InputTransparency, spec.Primary and 0 or 0.1)

		track(button.MouseButton1Down:Connect(function()
			local mouse = UserInputService:GetMouseLocation()
			ripple(button, mouse.X, mouse.Y - 36)
		end))
		track(button.MouseButton1Click:Connect(function()
			safeCall(tostring(spec.Text or "button") .. " callback", spec.Callback)
		end))
		table.insert(made, button)
	end

	local element = { Type = "ButtonGroup", Instance = row, Buttons = made }
	lockable(element, row, made)
	function element:Set(index, text)
		if made[index] then made[index].Text = tostring(text) end
	end
	function element:Destroy()
		row:Destroy()
	end
	return element
end

--========== Toggle ==========

local function CreateToggle(tab, options)
	options = options or {}
	local value = options.CurrentValue and true or false

	local row = baseRow(tab, rowHeight(options), "TextButton")
	rowLabel(row, options, 0.6, "Toggle")

	local track_ = create("Frame", {
		BackgroundColor3 = Theme.Input,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(42, 22),
		BorderSizePixel = 0,
		Parent = row,
	})
	create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track_ })
	stroke(track_)

	local knob = create("Frame", {
		BackgroundColor3 = Theme.Text,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BorderSizePixel = 0,
		Parent = track_,
	})
	create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })

	local element = { Type = "Toggle", Instance = row, CurrentValue = value }
	lockable(element, row, { row })

	local function render(animate)
		local dur = animate and 0.3 or 0
		tween(knob, { Position = UDim2.new(0, element.CurrentValue and 23 or 3, 0.5, 0) }, dur, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tween(track_, {
			BackgroundColor3 = element.CurrentValue and Theme.Accent or Theme.Input,
			BackgroundTransparency = element.CurrentValue and 0 or 0.1,
		}, dur, Enum.EasingStyle.Quad)
	end
	render(false)

	local function apply(newValue, fire)
		element.CurrentValue = newValue and true or false
		render(true)
		if fire ~= false then
			task.spawn(function()
				safeCall(tostring(options.Name or "element") .. " callback", options.Callback, element.CurrentValue)
			end)
		end
		saveConfig(tab.Window)
	end

	hoverable(row)
	track(row.MouseButton1Click:Connect(function()
		apply(not element.CurrentValue)
	end))

	function element:Set(newValue)
		apply(newValue, true)
	end
	function element:Get()
		return element.CurrentValue
	end
	function element:Destroy()
		row:Destroy()
	end

	registerFlag(tab, options.Flag, element, options)
	return element
end

--========== Slider ==========

local function CreateSlider(tab, options)
	options = options or {}
	local range = options.Range or { 0, 100 }
	local minValue, maxValue = tonumber(range[1]), tonumber(range[2])
	if not minValue or not maxValue then
		warnOnce("slider '" .. tostring(options.Name) .. "' has an invalid Range, falling back to 0-100")
		minValue, maxValue = 0, 100
	end
	if maxValue < minValue then
		warnOnce("slider '" .. tostring(options.Name) .. "' has Range reversed, swapping")
		minValue, maxValue = maxValue, minValue
	end
	local increment = tonumber(options.Increment) or 1
	local suffix = options.Suffix and (" " .. options.Suffix) or ""

	local row = baseRow(tab, rowHeight(options, ELEMENT_H + 16))
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font.Label,
		Text = tostring(options.Name or "Slider"),
		TextColor3 = Theme.Text,
		TextSize = Theme.TextSize.Label,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(0.6, 0, 0, 16),
		Parent = row,
	})

	local valueLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		Text = "",
		TextColor3 = Theme.SubText,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 8),
		Size = UDim2.new(0.4, 0, 0, 16),
		Parent = row,
	})

	local bar = create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Input,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -10),
		Size = UDim2.new(1, 0, 0, Mobile and 10 or 6),
		BorderSizePixel = 0,
		Parent = row,
	})
	create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = bar })
	stroke(bar)

	local fill = create("Frame", {
		BackgroundColor3 = Theme.Accent,
		Size = UDim2.new(0, 0, 1, 0),
		BorderSizePixel = 0,
		Parent = bar,
	})
	create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fill })

	local element = { Type = "Slider", Instance = row, CurrentValue = options.CurrentValue or minValue }
	lockable(element, row, { bar })

	local function alphaFor(value)
		if maxValue == minValue then return 0 end
		return math.clamp((value - minValue) / (maxValue - minValue), 0, 1)
	end

	local function render(value, animate)
		valueLabel.Text = tostring(value) .. suffix
		if animate then
			tween(fill, { Size = UDim2.new(alphaFor(value), 0, 1, 0) }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
		else
			fill.Size = UDim2.new(alphaFor(value), 0, 1, 0)
		end
	end

	local function apply(value, animate, fire)
		value = math.clamp(value, minValue, maxValue)
		element.CurrentValue = value
		render(value, animate)
		if fire ~= false then
			task.spawn(function()
				safeCall(tostring(options.Name or "element") .. " callback", options.Callback, value)
			end)
		end
	end

	apply(element.CurrentValue, false, false)

	-- Dragging is 1:1 (raw), the snap on release is the only tweened part.
	local dragging = false
	local function rawFromInput(input)
		local alpha = math.clamp((input.Position.X - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
		return minValue + alpha * (maxValue - minValue)
	end

	track(bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			local raw = rawFromInput(input)
			element.CurrentValue = raw
			fill.Size = UDim2.new(alphaFor(raw), 0, 1, 0)
			valueLabel.Text = tostring(round(raw, increment)) .. suffix
		end
	end))

	track(UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local raw = rawFromInput(input)
		element.CurrentValue = raw
		fill.Size = UDim2.new(alphaFor(raw), 0, 1, 0)
		valueLabel.Text = tostring(round(raw, increment)) .. suffix
	end))

	track(UserInputService.InputEnded:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		dragging = false
		apply(round(element.CurrentValue, increment), true, true)
		saveConfig(tab.Window)
	end))

	function element:Set(value)
		apply(round(tonumber(value) or minValue, increment), true, true)
	end
	function element:Get()
		return element.CurrentValue
	end
	function element:Destroy()
		row:Destroy()
	end

	registerFlag(tab, options.Flag, element, options)
	return element
end

--========== Dropdown ==========

local function CreateDropdown(tab, options)
	options = options or {}
	local multi = options.MultipleOptions and true or false
	local list = options.Options or {}
	if type(list) ~= "table" then
		warnOnce("dropdown '" .. tostring(options.Name) .. "' Options must be a table")
		list = {}
	end
	local selected = {}

	for _, value in ipairs(options.CurrentOption or {}) do
		selected[value] = true
	end

	local headerH = rowHeight(options)

	local holder = create("Frame", {
		Name = "Dropdown",
		BackgroundColor3 = Theme.Element,
		BackgroundTransparency = Theme.ElementIdle,
		Size = UDim2.new(1, 0, 0, headerH),
		ClipsDescendants = true,
		BorderSizePixel = 0,
		Parent = tab.Page,
	})
	corner(holder, Theme.Radius.Element)
	stroke(holder)
	glass(holder, 0.04)

	local header = create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, headerH),
		Parent = holder,
	})
	padding(header, 0, 0, 12, 12)
	rowLabel(header, options, 0.5, "Dropdown")

	local valueLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		Text = "",
		TextColor3 = Theme.SubText,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.new(0.5, -24, 1, 0),
		Parent = header,
	})

	local arrow = create("ImageLabel", {
		BackgroundTransparency = 1,
		Image = Icons.chevron,
		ImageColor3 = Theme.SubText,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		Rotation = 0,
		Parent = header,
	})

	local listHolder = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, headerH),
		Size = UDim2.new(1, 0, 1, -headerH),
		Visible = false,
		Parent = holder,
	})
	padding(listHolder, 0, 8, 12, 12)

	local scroller = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.Accent,
		ScrollBarImageTransparency = 0.5,
		Parent = listHolder,
	})
	create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroller })

	local element = { Type = "Dropdown", Instance = holder, CurrentOption = options.CurrentOption or {} }
	lockable(element, holder, { header })
	local optionRows = {}
	local open = false

	local function refreshValueLabel()
		local picked = {}
		for _, value in ipairs(list) do
			if selected[value] then table.insert(picked, tostring(value)) end
		end
		valueLabel.Text = #picked > 0 and table.concat(picked, ", ") or "None"
		element.CurrentOption = picked
	end

	local function expandedHeight()
		local rows = math.max(#list, 1)
		return math.min(rows * (ELEMENT_H - 6) + (rows - 1) * 4 + 8, 168)
	end

	local function setOpen(state)
		open = state
		-- keep the option list hidden while collapsed, otherwise its scrollbar
		-- peeks along the bottom edge of the row
		-- hidden the moment it closes: leaving it up for the collapse tween lets
		-- the selected row bleed out past the bottom edge
		listHolder.Visible = state
		local target = state and (headerH + expandedHeight()) or headerH
		tween(holder, { Size = UDim2.new(1, 0, 0, target) }, Theme.Tween.Normal)
		tween(arrow, { Rotation = state and 180 or 0 }, Theme.Tween.Normal)
		if state then
			-- staggered fade so the list unrolls instead of popping
			for index, entry in ipairs(optionRows) do
				entry.Button.BackgroundTransparency = 1
				entry.Label.TextTransparency = 1
				task.delay(index * 0.02, function()
					if not open then return end
					tween(entry.Button, { BackgroundTransparency = selected[entry.Value] and 0.15 or 0.6 }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
					tween(entry.Label, { TextTransparency = 0 }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
				end)
			end
		end
	end

	local function paintRow(entry)
		local on = selected[entry.Value] and true or false
		tween(entry.Button, {
			BackgroundColor3 = on and Theme.Accent or Theme.Input,
			BackgroundTransparency = on and 0.15 or 0.6,
		}, Theme.Tween.Fast, Enum.EasingStyle.Quad)
		tween(entry.Label, { TextColor3 = on and Theme.Text or Theme.SubText }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
	end

	local function fire()
		task.spawn(function()
			safeCall(tostring(options.Name or "element") .. " callback", options.Callback, element.CurrentOption)
		end)
		saveConfig(tab.Window)
	end

	local function buildRows()
		for _, entry in ipairs(optionRows) do
			entry.Button:Destroy()
		end
		optionRows = {}

		for index, value in ipairs(list) do
			local row = create("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = Theme.Input,
				BackgroundTransparency = 0.6,
				Size = UDim2.new(1, -4, 0, ELEMENT_H - 6),
				LayoutOrder = index,
				BorderSizePixel = 0,
				Parent = scroller,
			})
			corner(row, Theme.Radius.Input)
			padding(row, 0, 0, 10, 10)

			local label = create("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Font.Body,
				Text = tostring(value),
				TextColor3 = Theme.SubText,
				TextSize = Theme.TextSize.Body,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.fromScale(1, 1),
				Parent = row,
			})

			local entry = { Button = row, Label = label, Value = value }
			paintRow(entry)

			track(row.MouseButton1Click:Connect(function()
				if multi then
					selected[value] = (not selected[value]) or nil
				else
					selected = { [value] = true }
					for _, other in ipairs(optionRows) do
						paintRow(other)
					end
					setOpen(false)
				end
				paintRow(entry)
				refreshValueLabel()
				fire()
			end))

			table.insert(optionRows, entry)
		end
		refreshValueLabel()
	end

	buildRows()
	hoverable(holder)
	track(header.MouseButton1Click:Connect(function()
		setOpen(not open)
	end))

	function element:Set(value)
		selected = {}
		if type(value) == "table" then
			for _, v in ipairs(value) do selected[v] = true end
		elseif value ~= nil then
			selected[value] = true
		end
		for _, row in ipairs(optionRows) do
			paintRow(row)
		end
		refreshValueLabel()
		fire()
	end
	function element:Refresh(newList)
		list = newList or {}
		buildRows()
	end
	function element:Get()
		return element.CurrentOption
	end
	function element:Destroy()
		holder:Destroy()
	end

	registerFlag(tab, options.Flag, element, options)
	return element
end

--========== Input ==========

local function CreateInput(tab, options)
	options = options or {}
	local row = baseRow(tab, rowHeight(options))
	rowLabel(row, options, 0.45, "Input")

	local box = create("TextBox", {
		BackgroundColor3 = Theme.Input,
		BackgroundTransparency = Theme.InputTransparency,
		Font = Theme.Font.Body,
		PlaceholderText = tostring(options.PlaceholderText or ""),
		PlaceholderColor3 = Theme.SubText,
		Text = tostring(options.CurrentValue or ""),
		TextColor3 = Theme.Text,
		TextSize = Theme.TextSize.Body,
		ClearTextOnFocus = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0.5, 0, 0, ELEMENT_H - 12),
		BorderSizePixel = 0,
		Parent = row,
	})
	corner(box, Theme.Radius.Input)
	stroke(box)
	padding(box, 0, 0, 10, 10)

	local element = { Type = "Input", Instance = row, CurrentValue = box.Text }
	lockable(element, row, { box })

	track(box.Focused:Connect(function()
		tween(box, { BackgroundTransparency = 0.1 }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
	end))
	track(box.FocusLost:Connect(function()
		tween(box, { BackgroundTransparency = Theme.InputTransparency }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
		element.CurrentValue = box.Text
		task.spawn(function()
			safeCall(tostring(options.Name or "element") .. " callback", options.Callback, box.Text)
		end)
		if options.RemoveTextAfterFocusLost then
			box.Text = ""
		end
		saveConfig(tab.Window)
	end))

	function element:Set(text)
		box.Text = tostring(text or "")
		element.CurrentValue = box.Text
	end
	function element:Get()
		return element.CurrentValue
	end
	function element:Destroy()
		row:Destroy()
	end

	registerFlag(tab, options.Flag, element, options)
	return element
end

--========== Keybind ==========

local function CreateKeybind(tab, options)
	options = options or {}
	local row = baseRow(tab, rowHeight(options))
	rowLabel(row, options, 0.6, "Keybind")

	local button = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Input,
		BackgroundTransparency = Theme.InputTransparency,
		Font = Theme.Font.Label,
		Text = tostring(options.CurrentKeybind or "None"),
		TextColor3 = Theme.Text,
		TextSize = Theme.TextSize.Body,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(Mobile and 90 or 74, ELEMENT_H - 12),
		BorderSizePixel = 0,
		Parent = row,
	})
	corner(button, Theme.Radius.Input)
	stroke(button)

	local element = { Type = "Keybind", Instance = row, CurrentKeybind = options.CurrentKeybind or "None" }
	lockable(element, row, { button })
	local listening = false
	local held = false

	track(button.MouseButton1Click:Connect(function()
		listening = true
		button.Text = "Press a key"
		tween(button, { BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.2 }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
	end))

	track(UserInputService.InputBegan:Connect(function(input, processed)
		if listening and input.UserInputType == Enum.UserInputType.Keyboard then
			listening = false
			element.CurrentKeybind = input.KeyCode.Name
			button.Text = element.CurrentKeybind
			tween(button, { BackgroundColor3 = Theme.Input, BackgroundTransparency = Theme.InputTransparency }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
			if options.ChangedCallback then
				task.spawn(function() safeCall(tostring(options.Name or "element") .. " rebind", options.ChangedCallback, element.CurrentKeybind) end)
			end
			-- Rayfield fires the main callback on rebind when CallOnChange is set
			if options.CallOnChange then
				task.spawn(function() safeCall(tostring(options.Name or "element") .. " callback", options.Callback, element.CurrentKeybind) end)
			end
			saveConfig(tab.Window)
			return
		end
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode.Name ~= element.CurrentKeybind then return end

		if options.HoldToInteract then
			held = true
			task.spawn(function()
				safeCall(tostring(options.Name or "element") .. " callback", options.Callback, true)
			end)
		else
			task.spawn(function()
				safeCall(tostring(options.Name or "element") .. " callback", options.Callback)
			end)
		end
	end))

	track(UserInputService.InputEnded:Connect(function(input)
		if not (options.HoldToInteract and held) then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode.Name ~= element.CurrentKeybind then return end
		held = false
		task.spawn(function()
			safeCall(tostring(options.Name or "element") .. " callback", options.Callback, false)
		end)
	end))

	hoverable(row)

	function element:Set(key)
		element.CurrentKeybind = tostring(key or "None")
		button.Text = element.CurrentKeybind
	end
	function element:Get()
		return element.CurrentKeybind
	end
	function element:Destroy()
		row:Destroy()
	end

	registerFlag(tab, options.Flag, element, options)
	return element
end

--========== Colour picker ==========

local function CreateColorPicker(tab, options)
	options = options or {}
	local color = options.Color
	if color ~= nil and typeof(color) ~= "Color3" then
		warnOnce("colour picker '" .. tostring(options.Name) .. "' Color must be a Color3")
		color = nil
	end
	color = color or Color3.fromRGB(255, 255, 255)
	local hue, sat, val = color:ToHSV()

	local headerH = rowHeight(options)

	local holder = create("Frame", {
		Name = "ColorPicker",
		BackgroundColor3 = Theme.Element,
		BackgroundTransparency = Theme.ElementIdle,
		Size = UDim2.new(1, 0, 0, headerH),
		ClipsDescendants = true,
		BorderSizePixel = 0,
		Parent = tab.Page,
	})
	corner(holder, Theme.Radius.Element)
	stroke(holder)
	glass(holder, 0.04)

	local header = create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, headerH),
		Parent = holder,
	})
	padding(header, 0, 0, 12, 12)
	rowLabel(header, options, 0.7, "Color")

	local swatch = create("Frame", {
		BackgroundColor3 = color,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(34, ELEMENT_H - 14),
		BorderSizePixel = 0,
		Parent = header,
	})
	corner(swatch, Theme.Radius.Input)
	stroke(swatch)

	local body = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, headerH),
		Size = UDim2.new(1, 0, 0, 128),
		Visible = false,
		Parent = holder,
	})
	padding(body, 0, 10, 12, 12)

	local field = create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
		Size = UDim2.new(1, 0, 0, 92),
		BorderSizePixel = 0,
		Parent = body,
	})
	corner(field, Theme.Radius.Input)
	stroke(field)
	create("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new(0, 1),
		Parent = create("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromScale(1, 1),
			BorderSizePixel = 0,
			Name = "SatLayer",
			Parent = field,
		}),
	})
	local satLayer = field:FindFirstChild("SatLayer")
	corner(satLayer, Theme.Radius.Input)

	local valLayer = create("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		Parent = field,
	})
	corner(valLayer, Theme.Radius.Input)
	create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(1, 0),
		Parent = valLayer,
	})

	local cursor = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		ZIndex = 3,
		Parent = field,
	})
	create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = cursor })
	stroke(cursor, 0, Color3.new(1, 1, 1))

	local hueBar = create("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(0, 100),
		Size = UDim2.new(1, 0, 0, 10),
		BorderSizePixel = 0,
		Parent = body,
	})
	create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = hueBar })
	create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
			ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
		}),
		Parent = hueBar,
	})

	local hueKnob = create("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(hue, 0, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = hueBar,
	})
	create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = hueKnob })

	local element = { Type = "ColorPicker", Instance = holder, CurrentValue = color }
	lockable(element, holder, { header, field, hueBar })
	local open = false

	local function render(fire)
		local result = Color3.fromHSV(hue, sat, val)
		element.CurrentValue = result
		swatch.BackgroundColor3 = result
		field.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
		cursor.Position = UDim2.new(sat, 0, 1 - val, 0)
		hueKnob.Position = UDim2.new(hue, 0, 0.5, 0)
		if fire then
			task.spawn(function()
				safeCall(tostring(options.Name or "element") .. " callback", options.Callback, result)
			end)
		end
	end
	render(false)

	local draggingField, draggingHue = false, false

	local function updateField(input)
		local x = math.clamp((input.Position.X - field.AbsolutePosition.X) / math.max(field.AbsoluteSize.X, 1), 0, 1)
		local y = math.clamp((input.Position.Y - field.AbsolutePosition.Y) / math.max(field.AbsoluteSize.Y, 1), 0, 1)
		sat, val = x, 1 - y
		render(true)
	end

	local function updateHue(input)
		hue = math.clamp((input.Position.X - hueBar.AbsolutePosition.X) / math.max(hueBar.AbsoluteSize.X, 1), 0, 1)
		render(true)
	end

	track(field.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingField = true
			updateField(input)
		end
	end))
	track(hueBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingHue = true
			updateHue(input)
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if draggingField then updateField(input) end
		if draggingHue then updateHue(input) end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if draggingField or draggingHue then
			draggingField, draggingHue = false, false
			saveConfig(tab.Window)
		end
	end))

	hoverable(holder)
	track(header.MouseButton1Click:Connect(function()
		open = not open
		-- hide the body while collapsed, or the field cursor peeks past the row edge
		body.Visible = open
		tween(holder, { Size = UDim2.new(1, 0, 0, open and (headerH + 128) or headerH) }, Theme.Tween.Normal)
	end))

	function element:Set(newColor)
		if typeof(newColor) ~= "Color3" then return end
		hue, sat, val = newColor:ToHSV()
		render(true)
	end
	function element:Get()
		return element.CurrentValue
	end
	function element:Destroy()
		holder:Destroy()
	end

	registerFlag(tab, options.Flag, element, options)
	return element
end

--========== Static elements ==========

-- CreateLabel(text) or CreateLabel(text, icon, color), matching Rayfield.
local function CreateLabel(tab, text, icon, color)
	local holder = create("Frame", {
		Name = "Label",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = tab.Page,
	})
	padding(holder, 0, 0, 4, 4)

	local asset = iconAsset(icon)
	local inset = asset and 22 or 0
	local iconTint
	if asset then
		local _, tint = makeIcon(holder, asset, 14, color or Theme.SubText, {
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromOffset(0, 1),
		})
		iconTint = tint
	end

	local label = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		Text = tostring(text or ""),
		TextColor3 = color or Theme.SubText,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Position = UDim2.fromOffset(inset, 0),
		Size = UDim2.new(1, -inset, 0, 18),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = holder,
	})

	local element = { Type = "Label", Instance = holder }
	function element:Set(newText, newIcon, newColor)
		label.Text = tostring(newText or "")
		if newColor then
			label.TextColor3 = newColor
			if iconTint then iconTint(newColor) end
		end
	end
	function element:Destroy()
		holder:Destroy()
	end
	return element
end

local function CreateParagraph(tab, options)
	options = options or {}
	local holder = create("Frame", {
		BackgroundColor3 = Theme.Element,
		BackgroundTransparency = Theme.ElementIdle,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
		Parent = tab.Page,
	})
	corner(holder, Theme.Radius.Element)
	stroke(holder)
	glass(holder, 0.04)
	padding(holder, 10, 12, 12, 12)
	-- laid out by hand: a UIListLayout here would treat the glass sheen as a row

	local title = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font.Title,
		Text = tostring(options.Title or ""),
		TextColor3 = Theme.Text,
		TextSize = Theme.TextSize.Label,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = holder,
	})

	local content = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		Text = tostring(options.Content or ""),
		TextColor3 = Theme.SubText,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(0, 20),
		Parent = holder,
	})

	local element = { Type = "Paragraph", Instance = holder }
	function element:Set(newOptions)
		newOptions = newOptions or {}
		if newOptions.Title then title.Text = tostring(newOptions.Title) end
		if newOptions.Content then content.Text = tostring(newOptions.Content) end
	end
	function element:Destroy()
		holder:Destroy()
	end
	return element
end

local function CreateDivider(tab)
	local line = create("Frame", {
		BackgroundColor3 = Theme.Stroke,
		BackgroundTransparency = 0.9,
		Size = UDim2.new(1, 0, 0, 1),
		BorderSizePixel = 0,
		Parent = tab.Page,
	})
	local element = { Type = "Divider", Instance = line }
	function element:Set(visible)
		line.Visible = visible ~= false
	end
	function element:Destroy()
		line:Destroy()
	end
	return element
end

local function CreateSection(tab, name)
	local label = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font.Title,
		Text = string.upper(tostring(name or "")),
		TextColor3 = Theme.SubText,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = tab.Page,
	})
	padding(label, 6, 0, 4, 4)

	local element = { Type = "Section", Instance = label }
	function element:Set(newName)
		label.Text = string.upper(tostring(newName or ""))
	end
	function element:Destroy()
		label:Destroy()
	end
	return element
end

--============================== Window ==============================

function Lib:CreateWindow(options)
	options = options or {}
	if type(options) ~= "table" then
		error("[Dour] CreateWindow expects a table of options", 2)
	end
	if options.Size and typeof(options.Size) ~= "Vector2" then
		warnOnce("CreateWindow Size must be a Vector2, ignoring it")
		options.Size = nil
	end
	if options.ToggleKey and typeof(options.ToggleKey) ~= "EnumItem" then
		warnOnce("CreateWindow ToggleKey must be an Enum.KeyCode, falling back to RightShift")
		options.ToggleKey = nil
	end

	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local defaultSize = options.Size or (Mobile
		and Vector2.new(math.min(viewport.X * 0.92, 560), math.min(viewport.Y * 0.8, 420))
		or Vector2.new(660, 440))
	local startPosition = options.Position or UDim2.fromOffset(viewport.X / 2, viewport.Y / 2)

	local Window = {
		Tabs = {},
		FlagElements = {},
		Config = {
			Enabled = options.ConfigurationSaving and options.ConfigurationSaving.Enabled or false,
			FolderName = (options.ConfigurationSaving and options.ConfigurationSaving.FolderName) or "Dour Lib",
			FileName = (options.ConfigurationSaving and options.ConfigurationSaving.FileName) or "config",
		},
		ToggleKey = toKeyCode(options.ToggleKey or options.ToggleUIKeybind) or Enum.KeyCode.RightShift,
		Minimized = false,
		Visible = true,
		UserScale = options.Scale or 1,
	}
	table.insert(Lib.Windows, Window)

	if options.Preset then Lib:SetPreset(options.Preset) end
	if options.Theme then Lib:SetTheme(options.Theme) end  -- name or table
	if options.Accent then Lib:SetTheme({ Accent = options.Accent }) end
	if options.NotifySide then Lib:SetNotifySide(options.NotifySide) end

	--------- Root ---------

	local root, rootIsGroup = group({
		Name = "Window",
		BackgroundColor3 = Theme.Base,
		BackgroundTransparency = Theme.BaseTransparency,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = startPosition,
		Size = UDim2.fromOffset(defaultSize.X, defaultSize.Y),
		BorderSizePixel = 0,
		Visible = false,
		Parent = ScreenGui,
	})
	corner(root, Theme.Radius.Window)
	stroke(root)
	glass(root, 0.07, Theme.Radius.Window)
	shadow(root, 34, 0.5)

	local scale = create("UIScale", { Scale = 0.92, Parent = root })

	--------- Sidebar ---------

	-- "Top" swaps the left tab rail for a horizontal bar across the window head.
	local topMode = tostring(options.TabPosition or "Left"):lower() == "top"
	local SIDEBAR_W = options.SidebarWidth or (Mobile and 150 or 168)
	local TOPBAR_H = Mobile and 62 or 54
	local BRAND_W = 150

	local sidebar = create("Frame", {
		Name = "Sidebar",
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = Theme.PanelTransparency,
		Size = topMode and UDim2.new(1, 0, 0, TOPBAR_H) or UDim2.new(0, SIDEBAR_W, 1, 0),
		BorderSizePixel = 0,
		Parent = root,
	})
	corner(sidebar, Theme.Radius.Window)
	glass(sidebar, 0.05, Theme.Radius.Window)
	if topMode then
		padding(sidebar, 8, 8, 14, 12)
	else
		padding(sidebar, 14, 12, 12, 10)
	end

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font.Title,
		Text = tostring(options.Name or "Dour Lib"),
		TextColor3 = Theme.Text,
		TextSize = Theme.TextSize.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = topMode and UDim2.fromOffset(0, 8) or UDim2.new(),
		Size = topMode and UDim2.fromOffset(BRAND_W, 18) or UDim2.new(1, 0, 0, 18),
		Parent = sidebar,
	})

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		Text = tostring(options.LoadingSubtitle or ""),
		TextColor3 = Theme.SubText,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(0, topMode and 27 or 19),
		Size = topMode and UDim2.fromOffset(BRAND_W, 14) or UDim2.new(1, 0, 0, 14),
		Parent = sidebar,
	})

	local TAB_H = Mobile and 42 or 36
	local TAB_GAP = 6

	local tabHolder = create("Frame", {
		Name = "TabHolder",
		BackgroundTransparency = 1,
		Position = topMode and UDim2.new(0, BRAND_W + 14, 0.5, -TAB_H / 2) or UDim2.fromOffset(0, 48),
		Size = topMode and UDim2.new(1, -(BRAND_W + 14 + 104), 0, TAB_H) or UDim2.new(1, 0, 1, -48),
		ClipsDescendants = topMode,
		Parent = sidebar,
	})

	-- The pill lives behind the buttons and slides between them.
	local pill = create("Frame", {
		Name = "Pill",
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0.78,
		Size = topMode and UDim2.fromOffset(0, TAB_H) or UDim2.new(1, 0, 0, TAB_H),
		Position = UDim2.fromOffset(0, 0),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 1,
		Parent = tabHolder,
	})
	corner(pill, Theme.Radius.Pill)
	stroke(pill, 0.8, Theme.Accent)

	local tabList = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = tabHolder,
	})
	create("UIListLayout", {
		Padding = UDim.new(0, TAB_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = topMode and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		VerticalAlignment = topMode and Enum.VerticalAlignment.Center or Enum.VerticalAlignment.Top,
		Parent = tabList,
	})

	--------- Content ---------

	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = topMode and UDim2.fromOffset(0, TOPBAR_H) or UDim2.fromOffset(SIDEBAR_W, 0),
		Size = topMode and UDim2.new(1, 0, 1, -TOPBAR_H) or UDim2.new(1, -SIDEBAR_W, 1, 0),
		ClipsDescendants = true,
		Parent = root,
	})

	-- In top mode the window buttons live in the bar itself, so the content
	-- header collapses away entirely.
	local HEADER_H = topMode and 0 or 40

	local topbar = create("Frame", {
		Name = "Topbar",
		BackgroundTransparency = 1,
		AnchorPoint = topMode and Vector2.new(1, 0.5) or Vector2.new(0, 0),
		Position = topMode and UDim2.new(1, 0, 0.5, 0) or UDim2.new(),
		Size = topMode and UDim2.fromOffset(96, TAB_H) or UDim2.new(1, 0, 0, 40),
		Parent = topMode and sidebar or content,
	})
	if not topMode then
		padding(topbar, 0, 0, 14, 12)
	end

	local pageTitle = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Theme.Font.Title,
		Text = "",
		TextColor3 = Theme.Text,
		TextSize = Theme.TextSize.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -70, 1, 0),
		Visible = not topMode,
		Parent = topbar,
	})

	local function topbarButton(iconName, offset, callback)
		local button = create("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Element,
			BackgroundTransparency = 0.6,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, offset, 0.5, 0),
			Size = UDim2.fromOffset(24, 24),
			BorderSizePixel = 0,
			Parent = topbar,
		})
		corner(button, 8)
		makeIcon(button, iconAsset(iconName), 12, Theme.SubText, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
		hoverable(button, 0.6, 0.35)
		track(button.MouseButton1Click:Connect(callback))
		return button
	end

	local pageHolder = create("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, HEADER_H),
		Size = UDim2.new(1, 0, 1, -HEADER_H),
		Parent = content,
	})

	--------- Search ---------

	local searchBox = create("TextBox", {
		Name = "Search",
		BackgroundColor3 = Theme.Input,
		BackgroundTransparency = Theme.InputTransparency,
		Font = Theme.Font.Body,
		PlaceholderText = "search",
		PlaceholderColor3 = Theme.SubText,
		Text = "",
		TextColor3 = Theme.Text,
		TextSize = Theme.TextSize.Body,
		ClearTextOnFocus = false,
		Visible = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, topMode and -70 or -62, 0.5, 0),
		Size = UDim2.fromOffset(150, 24),
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = topMode and sidebar or topbar,
	})
	corner(searchBox, Theme.Radius.Input)
	stroke(searchBox)
	padding(searchBox, 0, 0, 10, 10)

	-- Rows carry their own title, so filtering is a name match per row.
	local function rowTitleText(row)
		local title = row:FindFirstChild("RowTitle")
		if not title then
			local header = row:FindFirstChildOfClass("TextButton")
			title = header and header:FindFirstChild("RowTitle")
		end
		if not title and row:IsA("TextLabel") then return row.Text end
		return title and title.Text or nil
	end

	local function applySearch(term)
		term = tostring(term or ""):lower()
		local active = Window.ActiveTab
		if not active then return end
		for _, row in ipairs(active.Page:GetChildren()) do
			if row:IsA("GuiObject") and not row:IsA("UIListLayout") then
				if term == "" then
					row.Visible = true
				else
					local title = rowTitleText(row)
					row.Visible = title ~= nil and title:lower():find(term, 1, true) ~= nil
				end
			end
		end
	end

	track(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		applySearch(searchBox.Text)
	end))

	function Window:Search(term)
		searchBox.Text = tostring(term or "")
		applySearch(searchBox.Text)
	end

	function Window:ToggleSearch()
		searchBox.Visible = not searchBox.Visible
		if searchBox.Visible then
			searchBox:CaptureFocus()
		else
			searchBox.Text = ""
			applySearch("")
		end
	end

	--------- Resize handle ---------

	local MIN_SIZE = options.MinSize or Vector2.new(480, 320)
	local resizeHandle = create("TextButton", {
		Name = "Resize",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(Mobile and 30 or 18, Mobile and 30 or 18),
		ZIndex = 5,
		Parent = root,
	})
	create("ImageLabel", {
		BackgroundTransparency = 1,
		Image = Icons.expand,
		ImageColor3 = Theme.SubText,
		ImageTransparency = 0.5,
		Rotation = 90,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(12, 12),
		Parent = resizeHandle,
	})

	--------- Minimised pill ---------

	local miniPill = create("TextButton", {
		Name = "MiniPill",
		Text = tostring(options.Name or "Dour Lib"),
		AutoButtonColor = false,
		Font = Theme.Font.Label,
		TextColor3 = Theme.Text,
		TextSize = Theme.TextSize.Body,
		BackgroundColor3 = Theme.Base,
		BackgroundTransparency = Theme.BaseTransparency,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(150, 34),
		Visible = false,
		BorderSizePixel = 0,
		Parent = ScreenGui,
	})
	create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = miniPill })
	stroke(miniPill)
	glass(miniPill, 0.06, 999)
	shadow(miniPill, 20, 0.6)

	--------- Show / hide ---------

	-- The pill is the only way back once the window is gone, so it shows for every
	-- hide (keybind, X-equivalent, Minimize), not just Minimize.
	local destroying = false

	local function showPill()
		if destroying then return end
		miniPill.Visible = true
		miniPill.Size = UDim2.fromOffset(0, 34)
		tween(miniPill, { Size = UDim2.fromOffset(150, 34) }, Theme.Tween.Normal)
	end

	local function show()
		Window.Visible = true
		Window.Minimized = false
		miniPill.Visible = false
		root.Visible = true
		scale.Scale = Window.UserScale * 0.92
		if rootIsGroup then root.GroupTransparency = 1 end
		tween(scale, { Scale = Window.UserScale }, Theme.Tween.Slow, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		setGroupTransparency(root, rootIsGroup, 0, Theme.Tween.Slow)
	end

	local function hide()
		Window.Visible = false
		tween(scale, { Scale = Window.UserScale * 0.92 }, Theme.Tween.Slow, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		setGroupTransparency(root, rootIsGroup, 1, Theme.Tween.Slow, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.delay(Lib.Animations and Theme.Tween.Slow or 0, function()
			if not Window.Visible then
				root.Visible = false
				showPill()
			end
		end)
	end

	--------- Dragging (weighted follow) ---------

	local dragging = false
	local dragStart, startPos
	local targetPos = root.Position

	local function clampTarget(pos)
		local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or viewport
		local halfX, halfY = root.AbsoluteSize.X / 2, root.AbsoluteSize.Y / 2
		return UDim2.fromOffset(
			math.clamp(pos.X.Offset, halfX, math.max(view.X - halfX, halfX)),
			math.clamp(pos.Y.Offset, halfY, math.max(view.Y - halfY, halfY))
		)
	end

	local canDrag = options.Draggable ~= false

	track(sidebar.InputBegan:Connect(function(input)
		if not canDrag then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = root.Position
		end
	end))
	track(topbar.InputBegan:Connect(function(input)
		if not canDrag then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = root.Position
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local delta = input.Position - dragStart
		targetPos = clampTarget(UDim2.fromOffset(startPos.X.Offset + delta.X, startPos.Y.Offset + delta.Y))
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	-- Lerped follow gives the window weight instead of sticking to the cursor.
	track(RunService.RenderStepped:Connect(function(dt)
		if not Lib.Animations then
			root.Position = targetPos
			return
		end
		local alpha = math.clamp(dt * 14, 0, 1)
		local current = root.Position
		root.Position = UDim2.fromOffset(
			current.X.Offset + (targetPos.X.Offset - current.X.Offset) * alpha,
			current.Y.Offset + (targetPos.Y.Offset - current.Y.Offset) * alpha
		)
	end))

	--------- Resizing ---------

	local resizing = false
	local resizeStart, sizeStart, posStart

	resizeHandle.Visible = options.Resizable ~= false

	track(resizeHandle.InputBegan:Connect(function(input)
		if not resizeHandle.Visible then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			resizing = true
			resizeStart = input.Position
			sizeStart = root.AbsoluteSize
			posStart = targetPos
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if not resizing then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local delta = input.Position - resizeStart
		local width = math.max(sizeStart.X + delta.X, MIN_SIZE.X)
		local height = math.max(sizeStart.Y + delta.Y, MIN_SIZE.Y)
		root.Size = UDim2.fromOffset(width, height)
		-- anchor is centred, so shift by half the growth to keep the top-left put
		targetPos = UDim2.fromOffset(
			posStart.X.Offset + (width - sizeStart.X) / 2,
			posStart.Y.Offset + (height - sizeStart.Y) / 2
		)
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			resizing = false
		end
	end))

	--------- Tabs ---------

	local activeTab

	local function selectTab(tab)
		if activeTab == tab then return end
		local previous = activeTab
		activeTab = tab
		Window.ActiveTab = tab

		pill.Visible = true
		if topMode then
			local function slide()
				local x = tab.Button.AbsolutePosition.X - tabList.AbsolutePosition.X
				local w = tab.Button.AbsoluteSize.X
				if w <= 0 then return false end
				tween(pill, {
					Position = UDim2.fromOffset(x, 0),
					Size = UDim2.fromOffset(w, TAB_H),
				}, Theme.Tween.Normal, Enum.EasingStyle.Quint)
				return true
			end
			-- AutomaticSize needs a frame to settle before the button can be measured
			if not slide() then
				task.defer(slide)
			end
		else
			tween(pill, { Position = UDim2.fromOffset(0, (tab.Index - 1) * (TAB_H + TAB_GAP)) }, Theme.Tween.Normal, Enum.EasingStyle.Quint)
		end
		pageTitle.Text = tab.Name

		for _, other in ipairs(Window.Tabs) do
			tween(other.Label, { TextColor3 = other == tab and Theme.Text or Theme.SubText }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
			if other.TintIcon then
				other.TintIcon(other == tab and Theme.Accent or Theme.SubText)
			end
		end

		-- Fade the old page fully out before the new one starts, so they never overlap.
		local function reveal()
			tab.Wrapper.Visible = true
			tab.Wrapper.Position = UDim2.fromOffset(0, 8)
			if tab.IsGroup then tab.Wrapper.GroupTransparency = 1 end
			tween(tab.Wrapper, { Position = UDim2.fromOffset(0, 0) }, Theme.Tween.Normal, Enum.EasingStyle.Quint)
			setGroupTransparency(tab.Wrapper, tab.IsGroup, 0, Theme.Tween.Normal)
		end

		if previous then
			setGroupTransparency(previous.Wrapper, previous.IsGroup, 1, Theme.Tween.Fast, Enum.EasingStyle.Quad)
			task.delay(Lib.Animations and Theme.Tween.Fast or 0, function()
				previous.Wrapper.Visible = false
				reveal()
			end)
		else
			reveal()
		end
	end

	function Window:CreateTab(name, icon)
		local tab = { Name = tostring(name or "Tab"), Window = Window, Index = #Window.Tabs + 1 }

		local button = create("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			AutomaticSize = topMode and Enum.AutomaticSize.X or Enum.AutomaticSize.None,
			Size = topMode and UDim2.fromOffset(0, TAB_H) or UDim2.new(1, 0, 0, TAB_H),
			LayoutOrder = tab.Index,
			Parent = tabList,
		})
		padding(button, 0, 0, topMode and 14 or 10, topMode and 14 or 8)
		tab.Button = button

		local asset = iconAsset(icon)
		if asset then
			tab.Icon, tab.TintIcon = makeIcon(button, asset, 16, Theme.SubText, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
			})
		end

		tab.Label = create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Font.Label,
			Text = tab.Name,
			TextColor3 = Theme.SubText,
			TextSize = Theme.TextSize.Label,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AutomaticSize = topMode and Enum.AutomaticSize.X or Enum.AutomaticSize.None,
			Position = UDim2.fromOffset(asset and 24 or 0, 0),
			Size = topMode and UDim2.new(0, 0, 1, 0) or UDim2.new(1, asset and -24 or 0, 1, 0),
			Parent = button,
		})

		local page, isGroup = group({
			Name = tab.Name,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = pageHolder,
		})
		tab.Page = create("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Theme.Accent,
			ScrollBarImageTransparency = 0.4,
			Parent = page,
		})
		create("UIListLayout", { Padding = UDim.new(0, ROW_PAD), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tab.Page })
		padding(tab.Page, 2, 16, 14, 14)

		-- tab.Page is where elements go; tab.Wrapper is the fadeable CanvasGroup around it
		tab.Wrapper = page
		tab.IsGroup = isGroup

		track(button.MouseButton1Click:Connect(function()
			selectTab(tab)
		end))
		track(button.MouseEnter:Connect(function()
			if activeTab ~= tab then
				tween(tab.Label, { TextColor3 = Theme.Text }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
			end
		end))
		track(button.MouseLeave:Connect(function()
			if activeTab ~= tab then
				tween(tab.Label, { TextColor3 = Theme.SubText }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
			end
		end))

		function tab:CreateSection(sectionName) return CreateSection(self, sectionName) end
		function tab:CreateButton(opts) return CreateButton(self, opts) end
		function tab:CreateButtonGroup(opts) return CreateButtonGroup(self, opts) end
		function tab:CreateToggle(opts) return CreateToggle(self, opts) end
		function tab:CreateSlider(opts) return CreateSlider(self, opts) end
		function tab:CreateDropdown(opts) return CreateDropdown(self, opts) end
		function tab:CreateInput(opts) return CreateInput(self, opts) end
		function tab:CreateKeybind(opts) return CreateKeybind(self, opts) end
		function tab:CreateColorPicker(opts) return CreateColorPicker(self, opts) end
		function tab:CreateLabel(text, icon, color) return CreateLabel(self, text, icon, color) end
		function tab:CreateParagraph(opts) return CreateParagraph(self, opts) end
		function tab:CreateDivider() return CreateDivider(self) end
		function tab:Select() selectTab(self) end
		function tab:Destroy()
			page:Destroy()
			button:Destroy()
			local index = table.find(Window.Tabs, self)
			if index then table.remove(Window.Tabs, index) end
		end

		table.insert(Window.Tabs, tab)
		if #Window.Tabs == 1 then
			task.defer(function()
				selectTab(tab)
			end)
		end
		return tab
	end

	--------- Built-in settings tab ---------
	-- End-user facing only: look, motion, scale, keybind, config. Element-level
	-- and theme-table customisation stays a developer API on purpose.

	function Window:CreateSettingsTab(opts)
		opts = opts or {}
		local tab = Window:CreateTab(opts.Name or "Settings", opts.Icon or "settings")

		if opts.Appearance ~= false then
			tab:CreateSection("Appearance")

			local presetNames = {}
			for name in pairs(Lib.Presets) do
				table.insert(presetNames, name)
			end
			table.sort(presetNames)

			tab:CreateDropdown({
				Name = "Theme",
				Description = "Recolour the entire interface.",
				Options = presetNames,
				CurrentOption = { Lib.CurrentPreset or "Dour Lib" },
				Flag = opts.PresetFlag or "dour_preset",
				Callback = function(chosen)
					if chosen[1] then Lib:SetPreset(chosen[1]) end
				end,
			})

			tab:CreateColorPicker({
				Name = "Accent Colour",
				Color = Theme.Accent,
				Flag = opts.AccentFlag or "dour_accent",
				Callback = function(color)
					Lib:SetTheme({ Accent = color })
				end,
			})
		end

		if opts.Interface ~= false then
			tab:CreateSection("Interface")

			tab:CreateToggle({
				Name = "Animations",
				Description = "Turn off for instant transitions.",
				CurrentValue = Lib.Animations,
				Flag = opts.AnimationsFlag or "dour_animations",
				Callback = function(value)
					Lib.Animations = value
				end,
			})

			tab:CreateSlider({
				Name = "Interface Scale",
				Range = { 75, 150 },
				Increment = 5,
				Suffix = "%",
				CurrentValue = math.floor(Window.UserScale * 100),
				Flag = opts.ScaleFlag or "dour_scale",
				Callback = function(value)
					Window.UserScale = value / 100
					tween(scale, { Scale = Window.UserScale }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
				end,
			})

			tab:CreateDropdown({
				Name = "Notifications",
				Options = { "Right", "Left" },
				CurrentOption = { "Right" },
				Flag = opts.NotifyFlag or "dour_notify_side",
				Callback = function(chosen)
					Lib:SetNotifySide(chosen[1] or "Right")
				end,
			})
		end

		if opts.Controls ~= false then
			tab:CreateSection("Controls")

			tab:CreateKeybind({
				Name = "Toggle Menu",
				CurrentKeybind = Window.ToggleKey.Name,
				Flag = opts.ToggleKeyFlag or "dour_toggle_key",
				ChangedCallback = function(keyName)
					local key = Enum.KeyCode[keyName]
					if key then Window.ToggleKey = key end
				end,
				Callback = function() end,
			})
		end

		if opts.Configuration ~= false and Window.Config.Enabled then
			tab:CreateSection("Configuration")

			local nameBox, profileList

			profileList = tab:CreateDropdown({
				Name = "Saved Configuration",
				Options = Window:ListConfigurations(),
				CurrentOption = {},
				Flag = opts.ProfileFlag or "dour_profile",
				Callback = function() end,
			})
			-- the manager's own selection must not travel inside the configs it writes
			profileList.ExcludeFromConfig = true

			nameBox = tab:CreateInput({
				Name = "Name",
				PlaceholderText = "My Setup",
				RemoveTextAfterFocusLost = false,
				Callback = function() end,
			})
			nameBox.ExcludeFromConfig = true

			local function refresh()
				profileList:Refresh(Window:ListConfigurations())
			end

			local function selected()
				return profileList.CurrentOption[1]
			end

			tab:CreateButtonGroup({
				Buttons = {
					{
						Text = "Save",
						Primary = true,
						Callback = function()
							local name = nameBox.CurrentValue
							if Window:SaveConfigurationAs(name) then
								refresh()
								profileList:Set(name)   -- so Load/Delete act on what was just saved
								Lib:Notify({ Title = "Configuration Saved", Content = "Stored as '" .. tostring(name) .. "'.", Duration = 3, Image = "check" })
							else
								Lib:Notify({ Title = "Nothing Saved", Content = "Give the configuration a name first.", Duration = 4, Image = "alert" })
							end
						end,
					},
					{
						Text = "Load",
						Callback = function()
							local name = selected()
							if name and Window:LoadConfigurationFrom(name) then
								Lib:Notify({ Title = "Configuration Loaded", Content = "Applied '" .. name .. "'.", Duration = 3, Image = "check" })
							else
								Lib:Notify({ Title = "Nothing Loaded", Content = "Select a configuration first.", Duration = 4, Image = "alert" })
							end
						end,
					},
					{
						Text = "Delete",
						Callback = function()
							local name = selected()
							if name and Window:DeleteConfiguration(name) then
								refresh()
								Lib:Notify({ Title = "Configuration Deleted", Content = "Removed '" .. name .. "'.", Duration = 3, Image = "minus" })
							end
						end,
					},
				},
			})
		end

		return tab
	end

	--------- Topbar buttons ---------

	function Window:Minimize()
		Window.Minimized = true
		hide()
	end

	function Window:Restore()
		show()
	end

	topbarButton("target", topMode and -68 or -68, function()
		Window:ToggleSearch()
	end)
	topbarButton("minus", -34, function()
		Window:Minimize()
	end)
	topbarButton("x", 0, function()
		Window:Destroy()
	end)

	track(miniPill.MouseButton1Click:Connect(function()
		Window:Restore()
	end))
	hoverable(miniPill, Theme.BaseTransparency, Theme.BaseTransparency - 0.08)

	--------- Visibility toggle ---------

	function Window:Toggle()
		if Window.Minimized then
			Window:Restore()
		elseif Window.Visible then
			hide()
		else
			show()
		end
	end

	track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode == Window.ToggleKey then
			Window:Toggle()
		end
	end))

	if Mobile then
		local floating = create("TextButton", {
			Name = "MobileToggle",
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Base,
			BackgroundTransparency = Theme.BaseTransparency,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 14, 0.25, 0),
			Size = UDim2.fromOffset(46, 46),
			BorderSizePixel = 0,
			Parent = ScreenGui,
		})
		create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = floating })
		stroke(floating)
		shadow(floating, 18, 0.6)
		create("ImageLabel", {
			BackgroundTransparency = 1,
			Image = Icons.sparkles,
			ImageColor3 = Theme.Accent,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(20, 20),
			Parent = floating,
		})
		track(floating.MouseButton1Click:Connect(function()
			Window:Toggle()
		end))
		Window.MobileToggle = floating
	end

	--------- Destroy ---------

	function Window:Destroy()
		destroying = true
		miniPill.Visible = false
		hide()
		task.delay(Lib.Animations and Theme.Tween.Slow or 0, function()
			root:Destroy()
			miniPill:Destroy()
			if Window.MobileToggle then Window.MobileToggle:Destroy() end
			local index = table.find(Lib.Windows, Window)
			if index then table.remove(Lib.Windows, index) end
			if #Lib.Windows == 0 then
				for _, connection in ipairs(Connections) do
					pcall(function() connection:Disconnect() end)
				end
				table.clear(Connections)
				ScreenGui:Destroy()
			end
		end)
	end

	function Window.ModifyTheme(theme)
		return Lib:SetTheme(theme)
	end

	function Window:GetTab(nameOrIndex)
		if type(nameOrIndex) == "number" then return Window.Tabs[nameOrIndex] end
		for _, tab in ipairs(Window.Tabs) do
			if tab.Name == nameOrIndex then return tab end
		end
		return nil
	end

	function Window:SelectTab(nameOrIndex)
		local tab = Window:GetTab(nameOrIndex)
		if tab then tab:Select() end
		return tab ~= nil
	end

	function Window:SaveConfiguration() saveConfig(Window) end
	function Window:LoadConfiguration() loadConfig(Window) end

	--------- Named config profiles ---------

	local function sanitize(name)
		name = tostring(name or ""):gsub("[^%w%-_ ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
		return name
	end

	function Window:ListConfigurations()
		local names = {}
		if not (FileSystemReady and listfiles) then return names end
		pcall(function()
			if not isfolder(configFolder(Window)) then return end
			for _, file in ipairs(listfiles(configFolder(Window))) do
				local name = tostring(file):match("([^\\/]+)%.json$")
				if name then table.insert(names, name) end
			end
		end)
		table.sort(names)
		return names
	end

	function Window:SaveConfigurationAs(name)
		name = sanitize(name)
		if name == "" then
			warnOnce("configuration needs a name")
			return false
		end
		if not FileSystemReady then
			warnOnce("this executor has no file functions, cannot save configurations")
			return false
		end
		local ok, err = pcall(function()
			if not isfolder(Window.Config.FolderName) then makefolder(Window.Config.FolderName) end
			if not isfolder(configFolder(Window)) then makefolder(configFolder(Window)) end
			writefile(configPath(Window, name), HttpService:JSONEncode(collectFlags(Window)))
		end)
		if not ok then
			warnOnce("could not save '" .. name .. "': " .. tostring(err))
		end
		return ok
	end

	function Window:LoadConfigurationFrom(name)
		name = sanitize(name)
		if name == "" or not FileSystemReady then return false end
		local ok, err = pcall(function()
			local path = configPath(Window, name)
			if isfile and not isfile(path) then error("no such configuration", 0) end
			applyFlags(Window, HttpService:JSONDecode(readfile(path)))
		end)
		if not ok then
			warnOnce("could not load '" .. name .. "': " .. tostring(err))
		end
		return ok
	end

	function Window:DeleteConfiguration(name)
		name = sanitize(name)
		if name == "" or not (FileSystemReady and delfile) then return false end
		local ok = pcall(function() delfile(configPath(Window, name)) end)
		return ok
	end

	--------- Key system (disabled unless asked for) ---------

	--------- Discord invite ---------
	-- Rayfield joins the server for the user; this only offers the link, which is
	-- the part a script author actually needs and the part a user would consent to.

	local function discordPrompt()
		local discord = options.Discord
		if not (discord and discord.Enabled and discord.Invite) then return end

		local seenPath = Window.Config.FolderName .. "/discord-" .. tostring(discord.Invite) .. ".txt"
		if discord.RememberJoins ~= false and FileSystemReady then
			local ok, seen = pcall(function() return isfile(seenPath) end)
			if ok and seen then return end
		end

		local link = "https://discord.gg/" .. tostring(discord.Invite)
		Lib:Notify({
			Title = tostring(options.Name or "Dour Lib"),
			Content = "Join the Discord for updates and keys.",
			Duration = 12,
			Image = "info",
			Actions = {
				{
					Name = "Copy Invite",
					Callback = function()
						if setclipboard then
							pcall(setclipboard, link)
						end
						if discord.RememberJoins ~= false and FileSystemReady then
							pcall(function()
								if not isfolder(Window.Config.FolderName) then makefolder(Window.Config.FolderName) end
								writefile(seenPath, link)
							end)
						end
					end,
				},
				{ Name = "Dismiss", Callback = function() end },
			},
		})
	end

	local function launch()
		targetPos = root.Position
		show()
		if Window.Config.Enabled then
			task.delay(1.2, function()
				loadConfig(Window)
			end)
		end
		task.delay(1.5, discordPrompt)
	end

	local function keySettings()
		local settings = options.KeySettings or {}
		local keys = settings.Key or {}
		if type(keys) == "string" then keys = { keys } end

		-- Rayfield's GrabKeyFromSite: the URL serves the valid keys, one per line
		if settings.GrabKeyFromSite then
			local ok, body = pcall(function()
				return game:HttpGet(tostring(settings.Key and settings.Key[1] or settings.KeyLink or ""))
			end)
			if ok and type(body) == "string" then
				local fetched = {}
				for line in body:gmatch("[^\r\n]+") do
					line = line:gsub("^%s+", ""):gsub("%s+$", "")
					if line ~= "" then table.insert(fetched, line) end
				end
				if #fetched > 0 then keys = fetched end
			else
				warnOnce("could not fetch the key list: " .. tostring(body))
			end
		end

		return settings, keys
	end

	local function keyPath()
		local settings = keySettings()
		local folder = settings.FolderName or Window.Config.FolderName
		return folder .. "/" .. (settings.FileName or "key") .. ".txt"
	end

	local function rememberedKey()
		local settings, keys = keySettings()
		if settings.SaveKey == false or not FileSystemReady then return false end
		local ok, saved = pcall(function()
			return isfile(keyPath()) and readfile(keyPath()) or nil
		end)
		return ok and saved ~= nil and table.find(keys, saved) ~= nil
	end

	local function rememberKey(key)
		local settings = keySettings()
		if settings.SaveKey == false or not FileSystemReady then return end
		pcall(function()
			if not isfolder(settings.FolderName or Window.Config.FolderName) then
				makefolder(settings.FolderName or Window.Config.FolderName)
			end
			writefile(keyPath(), key)
		end)
	end

	local function keyPrompt(onPass)
		local settings, keys = keySettings()
		local box_offset = 0

		if rememberedKey() then
			onPass()
			return
		end

		local prompt, promptIsGroup = group({
			BackgroundColor3 = Theme.Base,
			BackgroundTransparency = Theme.BaseTransparency,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(340, 172),
			BorderSizePixel = 0,
			Parent = ScreenGui,
		})
		corner(prompt, Theme.Radius.Window)
		stroke(prompt)
		glass(prompt, 0.07, Theme.Radius.Window)
		shadow(prompt, 28, 0.5)
		padding(prompt, 18, 16, 18, 18)

		-- same entrance as the window: scale up out of 0.92 while fading in
		local promptScale = create("UIScale", { Scale = 0.92, Parent = prompt })
		if promptIsGroup then prompt.GroupTransparency = 1 end
		tween(promptScale, { Scale = 1 }, Theme.Tween.Slow, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		setGroupTransparency(prompt, promptIsGroup, 0, Theme.Tween.Slow)

		-- closing the prompt gives up on loading entirely
		local closeKey = create("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Element,
			BackgroundTransparency = 0.6,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(24, 24),
			ZIndex = 3,
			Parent = prompt,
		})
		corner(closeKey, 8)
		makeIcon(closeKey, iconAsset("x"), 12, Theme.SubText, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
		hoverable(closeKey, 0.6, 0.35)
		track(closeKey.MouseButton1Click:Connect(function()
			tween(promptScale, { Scale = 0.92 }, Theme.Tween.Normal, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			setGroupTransparency(prompt, promptIsGroup, 1, Theme.Tween.Normal)
			task.delay(Theme.Tween.Normal, function()
				prompt:Destroy()
			end)
			Window:Destroy()
		end))

		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Font.Title,
			Text = tostring(settings.Title or "Key required"),
			TextColor3 = Theme.Text,
			TextSize = Theme.TextSize.Title,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 20),
			Parent = prompt,
		})
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Font.Body,
			Text = tostring(settings.Subtitle or "Enter your key to continue"),
			TextColor3 = Theme.SubText,
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, 0, 0, 32),
			Parent = prompt,
		})

		if settings.Note and settings.Note ~= "" then
			prompt.Size = UDim2.fromOffset(340, 192)
			create("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Font.Body,
				Text = tostring(settings.Note),
				TextColor3 = Theme.SubText,
				TextSize = Theme.TextSize.Body - 1,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = true,
				Position = UDim2.fromOffset(0, 52),
				Size = UDim2.new(1, 0, 0, 16),
				Parent = prompt,
			})
			box_offset = 20
		end

		local box = create("TextBox", {
			BackgroundColor3 = Theme.Input,
			BackgroundTransparency = Theme.InputTransparency,
			Font = Theme.Font.Body,
			PlaceholderText = "Registration key",
			PlaceholderColor3 = Theme.SubText,
			Text = "",
			TextColor3 = Theme.Text,
			TextSize = Theme.TextSize.Body,
			Position = UDim2.fromOffset(0, 62 + box_offset),
			Size = UDim2.new(1, 0, 0, 32),
			BorderSizePixel = 0,
			Parent = prompt,
		})
		corner(box, Theme.Radius.Input)
		stroke(box)
		padding(box, 0, 0, 10, 34)

		-- The box shows bullets; the typed key lives here. Roblox has no native
		-- masked input, so the text is rewritten as it changes.
		local realKey = ""
		local revealed = false
		local rewriting = false

		local function render()
			rewriting = true
			box.Text = revealed and realKey or string.rep("\u{25CF}", utf8.len(realKey) or #realKey)
			rewriting = false
		end

		track(box:GetPropertyChangedSignal("Text"):Connect(function()
			if rewriting then return end
			local shown = box.Text
			if revealed then
				realKey = shown
				return
			end
			local shownLen = utf8.len(shown) or #shown
			local realLen = utf8.len(realKey) or #realKey
			if shownLen > realLen then
				realKey = realKey .. string.sub(shown, utf8.offset(shown, realLen + 1) or (realLen + 1))
			elseif shownLen < realLen then
				local cut = utf8.offset(realKey, shownLen + 1)
				realKey = cut and string.sub(realKey, 1, cut - 1) or ""
			end
			render()
		end))

		local revealButton = create("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -3, 0, 65 + box_offset),
			Size = UDim2.fromOffset(26, 26),
			ZIndex = 3,
			Parent = prompt,
		})

		local _, tintEye = makeIcon(revealButton, "eye", 16, Theme.SubText, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})

		track(revealButton.MouseButton1Click:Connect(function()
			revealed = not revealed
			if tintEye then tintEye(revealed and Theme.Accent or Theme.SubText) end
			render()
		end))

		local submit = create("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Accent,
			BackgroundTransparency = 0.1,
			Font = Theme.Font.Label,
			Text = "Continue",
			TextColor3 = Theme.Text,
			TextSize = Theme.TextSize.Body,
			Position = UDim2.fromOffset(0, 102 + box_offset),
			Size = UDim2.new(1, 0, 0, 32),
			BorderSizePixel = 0,
			Parent = prompt,
		})
		corner(submit, Theme.Radius.Input)
		hoverable(submit, 0.1, 0)

		local function attempt()
			if #keys == 0 or table.find(keys, realKey) then
				rememberKey(realKey)
				tween(promptScale, { Scale = 0.92 }, Theme.Tween.Normal, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
				setGroupTransparency(prompt, promptIsGroup, 1, Theme.Tween.Normal)
				task.delay(Theme.Tween.Normal, function()
					prompt:Destroy()
				end)
				onPass()
			else
				Lib:Notify({ Title = "Invalid Key", Content = "That key was not accepted.", Duration = 4, Image = "x" })
				local base = prompt.Position
				for i, offset in ipairs({ -8, 7, -5, 3, 0 }) do
					task.delay(i * 0.045, function()
						tween(prompt, { Position = base + UDim2.fromOffset(offset, 0) }, 0.045, Enum.EasingStyle.Quad)
					end)
				end
				tween(box, { BackgroundColor3 = Color3.fromRGB(120, 40, 40) }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
				task.delay(0.4, function()
					tween(box, { BackgroundColor3 = Theme.Input }, Theme.Tween.Fast, Enum.EasingStyle.Quad)
				end)
			end
		end

		track(submit.MouseButton1Click:Connect(attempt))
		track(box.FocusLost:Connect(function(enterPressed)
			if enterPressed then attempt() end
		end))

		Window.SubmitKey = attempt
		Window.KeyBox = box
		function Window.SetKeyText(text)
			realKey = tostring(text or "")
			render()
		end
	end

	function Window:ForgetKey()
		if not FileSystemReady then return end
		pcall(function() delfile(keyPath()) end)
	end

	--------- Loading splash ---------

	local function splash(done)
		local card, cardIsGroup = group({
			BackgroundColor3 = Theme.Base,
			BackgroundTransparency = Theme.BaseTransparency,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(260, 92),
			BorderSizePixel = 0,
			Parent = ScreenGui,
		})
		corner(card, Theme.Radius.Window)
		stroke(card)
		glass(card, 0.07, Theme.Radius.Window)
		shadow(card, 28, 0.5)
		padding(card, 20, 18, 20, 20)

		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Font.Title,
			Text = tostring(options.LoadingTitle or options.Name or "Loading"),
			TextColor3 = Theme.Text,
			TextSize = Theme.TextSize.Title,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 20),
			Parent = card,
		})
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Font.Body,
			Text = tostring(options.LoadingSubtitle or ""),
			TextColor3 = Theme.SubText,
			TextSize = Theme.TextSize.Body,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, 0, 0, 16),
			Parent = card,
		})

		local barBack = create("Frame", {
			BackgroundColor3 = Theme.Input,
			BackgroundTransparency = 0.2,
			Position = UDim2.fromOffset(0, 48),
			Size = UDim2.new(1, 0, 0, 4),
			BorderSizePixel = 0,
			Parent = card,
		})
		create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = barBack })
		local bar = create("Frame", {
			BackgroundColor3 = Theme.Accent,
			Size = UDim2.new(0, 0, 1, 0),
			BorderSizePixel = 0,
			Parent = barBack,
		})
		create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = bar })

		if cardIsGroup then card.GroupTransparency = 1 end
		setGroupTransparency(card, cardIsGroup, 0, Theme.Tween.Normal)
		tween(bar, { Size = UDim2.fromScale(1, 1) }, 0.9, Enum.EasingStyle.Quint)

		task.delay(Lib.Animations and 1.1 or 0, function()
			setGroupTransparency(card, cardIsGroup, 1, Theme.Tween.Normal)
			task.delay(Theme.Tween.Normal, function()
				card:Destroy()
				done()
			end)
		end)
	end

	local function afterSplash()
		if options.KeySystem then
			keyPrompt(launch)
		else
			launch()
		end
	end

	if options.ShowSplash == false then
		afterSplash()
	else
		splash(afterSplash)
	end

	Window.Instance = root
	return Window
end

--============================== Public helpers ==============================

--============================== Live theming ==============================
-- Restyling walks the live tree and swaps any property still holding an old
-- theme value for its replacement. That means no per-instance registration and
-- it picks up state colours (an enabled toggle track, a slider fill) too.

Lib.Presets = {
	Dour = {
		Accent = Color3.fromRGB(94, 132, 255),
		Base = Color3.fromRGB(16, 16, 18),
		Panel = Color3.fromRGB(30, 30, 35),
		Element = Color3.fromRGB(44, 44, 52),
		Input = Color3.fromRGB(24, 24, 28),
		Text = Color3.fromRGB(238, 238, 245),
		SubText = Color3.fromRGB(155, 155, 168),
		Stroke = Color3.fromRGB(255, 255, 255),
		StrokeTransparency = 0.85,
	},
	Midnight = {
		Accent = Color3.fromRGB(120, 108, 255),
		Base = Color3.fromRGB(12, 12, 20),
		Panel = Color3.fromRGB(24, 24, 38),
		Element = Color3.fromRGB(36, 36, 56),
		Input = Color3.fromRGB(18, 18, 30),
	},
	Slate = {
		Accent = Color3.fromRGB(120, 190, 170),
		Base = Color3.fromRGB(22, 24, 24),
		Panel = Color3.fromRGB(36, 40, 40),
		Element = Color3.fromRGB(52, 58, 58),
		Input = Color3.fromRGB(28, 32, 32),
	},
	Ember = {
		Accent = Color3.fromRGB(255, 138, 92),
		Base = Color3.fromRGB(22, 17, 16),
		Panel = Color3.fromRGB(40, 31, 28),
		Element = Color3.fromRGB(58, 45, 41),
		Input = Color3.fromRGB(28, 22, 20),
	},
	-- Rayfield ships these names, so a ported script's Theme = "Ocean" just works.
	Ocean = {
		Accent = Color3.fromRGB(86, 173, 199),
		Base = Color3.fromRGB(20, 30, 34),
		Panel = Color3.fromRGB(30, 44, 50),
		Element = Color3.fromRGB(42, 60, 68),
		Input = Color3.fromRGB(24, 36, 41),
	},
	AmberGlow = {
		Accent = Color3.fromRGB(245, 178, 90),
		Base = Color3.fromRGB(30, 24, 18),
		Panel = Color3.fromRGB(48, 38, 28),
		Element = Color3.fromRGB(64, 51, 38),
		Input = Color3.fromRGB(34, 27, 20),
	},
	Amethyst = {
		Accent = Color3.fromRGB(178, 130, 235),
		Base = Color3.fromRGB(24, 20, 32),
		Panel = Color3.fromRGB(38, 32, 50),
		Element = Color3.fromRGB(52, 44, 68),
		Input = Color3.fromRGB(28, 23, 37),
	},
	Green = {
		Accent = Color3.fromRGB(126, 200, 130),
		Base = Color3.fromRGB(18, 26, 20),
		Panel = Color3.fromRGB(28, 40, 31),
		Element = Color3.fromRGB(40, 55, 44),
		Input = Color3.fromRGB(21, 31, 24),
	},
	Bloom = {
		Accent = Color3.fromRGB(240, 140, 175),
		Base = Color3.fromRGB(32, 22, 27),
		Panel = Color3.fromRGB(50, 35, 43),
		Element = Color3.fromRGB(66, 47, 57),
		Input = Color3.fromRGB(36, 25, 31),
	},
	DarkBlue = {
		Accent = Color3.fromRGB(92, 140, 229),
		Base = Color3.fromRGB(14, 18, 28),
		Panel = Color3.fromRGB(24, 30, 45),
		Element = Color3.fromRGB(34, 42, 62),
		Input = Color3.fromRGB(17, 22, 34),
	},
	Serenity = {
		Accent = Color3.fromRGB(140, 165, 205),
		Base = Color3.fromRGB(26, 28, 34),
		Panel = Color3.fromRGB(40, 43, 52),
		Element = Color3.fromRGB(55, 59, 70),
		Input = Color3.fromRGB(30, 32, 39),
	},
	Light = {
		Accent = Color3.fromRGB(70, 100, 230),
		Base = Color3.fromRGB(238, 238, 240),
		Panel = Color3.fromRGB(250, 250, 252),
		Element = Color3.fromRGB(224, 224, 230),
		Input = Color3.fromRGB(246, 246, 248),
	},
	Paper = {
		Accent = Color3.fromRGB(70, 100, 230),
		Base = Color3.fromRGB(238, 238, 240),
		Panel = Color3.fromRGB(250, 250, 252),
		Element = Color3.fromRGB(224, 224, 230),
		Input = Color3.fromRGB(246, 246, 248),
		Text = Color3.fromRGB(26, 26, 30),
		SubText = Color3.fromRGB(110, 110, 122),
		Stroke = Color3.fromRGB(0, 0, 0),
		StrokeTransparency = 0.9,
	},
}

local COLOR_PROPS = { "BackgroundColor3", "TextColor3", "ImageColor3", "PlaceholderColor3", "ScrollBarImageColor3", "Color" }

-- Text follows the background: a preset that changes Base without naming its own
-- Text would otherwise keep the previous one, which is how you end up with dark
-- text on a dark panel after switching away from a light preset.
local function luminance(color)
	return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
end

function Lib:SetTheme(overrides)
	-- a string is a preset name, which is how Rayfield's Theme option is written
	if type(overrides) == "string" then
		return Lib:SetPreset(overrides)
	end

	overrides = overrides or {}

	if overrides.Base and not overrides.Text then
		local dark = luminance(overrides.Base) < 0.5
		overrides.Text = dark and Color3.fromRGB(238, 238, 245) or Color3.fromRGB(26, 26, 30)
		overrides.SubText = overrides.SubText or (dark and Color3.fromRGB(155, 155, 168) or Color3.fromRGB(110, 110, 122))
		overrides.Stroke = overrides.Stroke or (dark and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0))
	end

	-- snapshot what is about to change so the walk knows old -> new
	local colorSwaps, radiusSwaps, fontSwaps, sizeSwaps = {}, {}, {}, {}

	for key, value in pairs(overrides) do
		local current = Theme[key]
		if typeof(value) == "Color3" and typeof(current) == "Color3" and value ~= current then
			table.insert(colorSwaps, { current, value })
		elseif key == "Radius" or key == "TextSize" or key == "Tween" then
			for sub, subValue in pairs(value) do
				local old = current[sub]
				if old ~= subValue then
					local bucket = (key == "Radius" and radiusSwaps) or (key == "Font" and fontSwaps) or (key == "TextSize" and sizeSwaps)
					if bucket then table.insert(bucket, { old, subValue }) end
				end
				current[sub] = subValue
			end
		end
		if key ~= "Radius" and key ~= "TextSize" and key ~= "Tween" and key ~= "Font" then
			Theme[key] = value
		end
	end

	local function swapped(list, value)
		for _, pair in ipairs(list) do
			if pair[1] == value then return pair[2] end
		end
		return nil
	end

	-- Tweened colours land a hair off their goal, so an exact match would strand
	-- those instances on the previous palette at the next switch.
	local function swappedColor(list, value)
		for _, pair in ipairs(list) do
			local old = pair[1]
			if math.abs(old.R - value.R) < 0.004
				and math.abs(old.G - value.G) < 0.004
				and math.abs(old.B - value.B) < 0.004 then
				return pair[2]
			end
		end
		return nil
	end

	local targets = ScreenGui:GetDescendants()
	table.insert(targets, ScreenGui)
	for _, inst in ipairs(targets) do
		for _, prop in ipairs(COLOR_PROPS) do
			local ok, value = pcall(function() return inst[prop] end)
			if ok and typeof(value) == "Color3" then
				local replacement = swappedColor(colorSwaps, value)
				if replacement then
					tween(inst, { [prop] = replacement }, Theme.Tween.Normal, Enum.EasingStyle.Quad)
				end
			end
		end
		if inst:IsA("UICorner") and inst.CornerRadius.Scale == 0 then
			local replacement = swapped(radiusSwaps, inst.CornerRadius.Offset)
			if replacement then inst.CornerRadius = UDim.new(0, replacement) end
		elseif inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			local face = swapped(fontSwaps, inst.FontFace)
			if face then inst.FontFace = face end
			local size = swapped(sizeSwaps, inst.TextSize)
			if size then inst.TextSize = size end
		end
	end
	return true
end

-- family may be a stock "rbxasset://fonts/families/<Name>.json" path or the
-- asset id of an uploaded font family, e.g. "rbxassetid://1234567890".
-- Read or write any flagged element without keeping a reference to it.
function Lib:GetFlag(flag, default)
	local element = Lib.Flags[flag]
	if not element then return default end
	if element.CurrentValue ~= nil then return element.CurrentValue end
	if element.CurrentOption ~= nil then return element.CurrentOption end
	if element.CurrentKeybind ~= nil then return element.CurrentKeybind end
	return default
end

function Lib:SetFlag(flag, value)
	local element = Lib.Flags[flag]
	if not (element and element.Set) then return false end
	local ok = pcall(function() element:Set(value) end)
	return ok
end

-- Every flag as a plain table, handy for debugging or sending to a webhook.
function Lib:GetFlags()
	local out = {}
	for flag in pairs(Lib.Flags) do
		out[flag] = Lib:GetFlag(flag)
	end
	return out
end

function Lib:SetFont(family, weights)
	if type(family) == "string" and family ~= "" then
		Theme.Font.Family = family
	end
	for role, weight in pairs(weights or {}) do
		if Theme.Font.Weights[role] then
			Theme.Font.Weights[role] = weight
		end
	end

	local old = {}
	for role in pairs(Theme.Font.Weights) do
		old[role] = Theme.Font[role]
	end
	buildFaces()

	for _, inst in ipairs(ScreenGui:GetDescendants()) do
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			for role, face in pairs(old) do
				if inst.FontFace == face then
					inst.FontFace = Theme.Font[role]
					break
				end
			end
		end
	end
end

-- Point the UI at Inter from a workspace folder holding Inter-Regular/Medium/
-- Bold.ttf. Returns false when the files are not there.
function Lib:UseInter(dir)
	local family = interFamily(dir)
	if not family then
		warnOnce("Inter faces not found in '" .. (dir or INTER_DIR) .. "', keeping the current font")
		return false
	end
	Lib:SetFont(family)
	return true
end

Lib.ModifyTheme = function(theme)
	return Lib:SetTheme(theme)
end

function Lib:SetPreset(name)
	if name == "Default" then name = "Dour Lib" end
	local preset = Lib.Presets[name]
	if not preset then return false end
	Lib:SetTheme(preset)
	Lib.CurrentPreset = name
	return true
end

-- Rayfield parity: act on every open window at once.
function Lib:SetVisibility(visible)
	for _, window in ipairs(Lib.Windows) do
		if visible and not window.Visible then
			window:Toggle()
		elseif not visible and window.Visible then
			window:Toggle()
		end
	end
end

function Lib:IsVisible()
	for _, window in ipairs(Lib.Windows) do
		if window.Visible then return true end
	end
	return false
end

function Lib:Destroy()
	for index = #Lib.Windows, 1, -1 do
		Lib.Windows[index]:Destroy()
	end
end

function Lib:LoadConfiguration()
	for _, window in ipairs(Lib.Windows) do
		loadConfig(window)
	end
end

function Lib:SaveConfiguration()
	for _, window in ipairs(Lib.Windows) do
		saveConfig(window)
	end
end

return Lib

--[[ Dour Interface Suite — full element demo ]]

local Dour = loadstring(game:HttpGet("https://raw.githubusercontent.com/dlyrr/dour-lib/main/source.lua"))()

local Window = Dour:CreateWindow({
	Name = "My Hub",
	LoadingTitle = "Loading",
	LoadingSubtitle = "by santi",
	ConfigurationSaving = { Enabled = true, FolderName = "myhub", FileName = "config" },
	KeySystem = false,
	-- TabPosition = "Top",             -- Left (sidebar rail) or Top (tab bar)
	-- Preset = "Midnight",              -- Dour | Midnight | Slate | Ember | Paper
	-- Theme = { Accent = Color3.fromRGB(255, 138, 92), Radius = { Window = 8 } },
	-- Size = Vector2.new(720, 470), Position = UDim2.fromOffset(400, 300),
	-- SidebarWidth = 190, MinSize = Vector2.new(520, 340), Scale = 1.1,
	-- Draggable = true, Resizable = true, ShowSplash = true, NotifySide = "Right",
	-- KeySettings = { Title = "Key required", Subtitle = "grab one from the discord", Key = { "hello" } },
	-- Accent = Color3.fromRGB(94, 132, 255),
	-- ToggleKey = Enum.KeyCode.RightShift,
})

--============================== Main ==============================

local Main = Window:CreateTab("Main", "home")

Main:CreateSection("Combat")

local KillAll = Main:CreateButton({
	Name = "Kill All",
	Description = "Eliminates everyone on the opposing team.",
	Icon = "alert",
	Callback = function()
		Dour:Notify({ Title = "Done", Content = "Kill All has finished.", Duration = 4, Image = "sparkles" })
	end,
})

local AimToggle = Main:CreateToggle({
	Name = "Aim Assistance",
	Description = "Snaps your aim to the nearest visible target.",
	Icon = "check",
	CurrentValue = false,
	Flag = "aim",
	Callback = function(value)
		print("aim assist:", value)
	end,
})

Main:CreateSlider({
	Name = "Maximum Reach",
	Range = { 0, 100 },
	Increment = 5,
	Suffix = "studs",
	CurrentValue = 50,
	Flag = "reach",
	Callback = function(value)
		print("reach:", value)
	end,
})

Main:CreateDivider()

Main:CreateSection("Targeting")

Main:CreateDropdown({
	Name = "Target Part",
	Options = { "Head", "HumanoidRootPart", "Torso" },
	CurrentOption = { "Head" },
	MultipleOptions = false,
	Flag = "part",
	Callback = function(option)
		print("target:", table.concat(option, ", "))
	end,
})

Main:CreateDropdown({
	Name = "Ignored Teams",
	Options = { "Red", "Blue", "Green" },
	CurrentOption = { "Red", "Blue" },
	MultipleOptions = true,
	Flag = "teams",
	Callback = function(options)
		print("ignoring:", table.concat(options, ", "))
	end,
})

--============================== Visuals ==============================

local Visuals = Window:CreateTab("Visuals", "eye")

Visuals:CreateSection("Highlights")

Visuals:CreateToggle({
	Name = "Player Boxes",
	CurrentValue = true,
	Flag = "box",
	Callback = function(value)
		print("box esp:", value)
	end,
})

Visuals:CreateColorPicker({
	Name = "Highlight Colour",
	Color = Color3.fromRGB(94, 132, 255),
	Flag = "espcolor",
	Callback = function(color)
		print("colour:", color)
	end,
})

Visuals:CreateKeybind({
	Name = "Toggle Highlights",
	CurrentKeybind = "F",
	HoldToInteract = false,
	Flag = "espkey",
	Callback = function()
		print("esp keybind fired")
	end,
})

Visuals:CreateKeybind({
	Name = "Peek (Hold)",
	CurrentKeybind = "V",
	HoldToInteract = true,
	Flag = "peek",
	Callback = function(held)
		print("peek held:", held)
	end,
})

--============================== Settings ==============================
-- The built-in end-user settings tab: theme preset, accent, animations,
-- ui scale, notification side, toggle keybind, config save/reload.

local Settings = Window:CreateSettingsTab()

-- ...and anything else you want alongside it
Settings:CreateSection("Hub")

Settings:CreateInput({
	Name = "Webhook URL",
	PlaceholderText = "https://discord.com/api/webhooks/...",
	RemoveTextAfterFocusLost = false,
	Flag = "webhook",
	Callback = function(text)
		print("webhook:", text)
	end,
})

local Locked = Settings:CreateButton({
	Name = "Premium Only",
	Description = "Unlocked once a valid key is entered.",
	Callback = function()
		print("never fires while locked")
	end,
})
Locked:SetLocked(true)

Settings:CreateParagraph({
	Title = "About",
	Content = "Dour Interface Suite. Glass panels, weighted dragging, and a Rayfield-shaped API so existing scripts drop straight in.",
})

Settings:CreateDivider()

Settings:CreateButton({
	Name = "Minimise",
	Callback = function()
		Window:Minimize()
	end,
})

Settings:CreateButton({
	Name = "Close",
	Callback = function()
		Window:Destroy()
	end,
})

--============================== Runtime access ==============================

task.delay(2, function()
	AimToggle:Set(true)
	print("aim flag is now", Dour.Flags.aim.CurrentValue)
end)

Dour:Notify({ Title = "Dour Loaded", Content = "The interface is ready.", Duration = 5, Image = "sparkles" })

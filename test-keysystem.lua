--[[
	Key system self-test.

	Run it, then watch the notifications. It drives the key prompt
	programmatically: a wrong key must be rejected, the right key must be
	accepted and the window must appear.

	Replace the loadstring with your host, or paste source.lua above it.
--]]

local Dour = loadstring(game:HttpGet("https://raw.githubusercontent.com/dlyrr/dour-lib/main/source.lua"))()

local PASS = "dour-2026"
local FAIL = "not-the-key"

local results = {}
local function check(name, ok)
	table.insert(results, (ok and "PASS  " or "FAIL  ") .. name)
	print((ok and "[PASS] " or "[FAIL] ") .. name)
end

local Window = Dour:CreateWindow({
	Name = "key test",
	LoadingTitle = "key test",
	LoadingSubtitle = "checking the gate",
	ShowSplash = false,
	ConfigurationSaving = { Enabled = false },
	KeySystem = true,
	KeySettings = {
		Title = "Key required",
		Subtitle = "the test types this for you",
		Key = { PASS },
		FolderName = "dour_keytest",
		SaveKey = true,
	},
})

getgenv().DourKeyTest = { Dour = Dour, Window = Window, Results = results }

Window:ForgetKey() -- always start from a cold prompt

local Tab = Window:CreateTab("main", "home")
Tab:CreateLabel("you only see this after the key passes.")

task.spawn(function()
	-- the prompt is built on the frame after CreateWindow returns
	local deadline = os.clock() + 5
	repeat task.wait(0.1) until Window.SubmitKey or os.clock() > deadline

	check("prompt appeared", Window.SubmitKey ~= nil)
	if not Window.SubmitKey then return end

	check("window hidden while locked", Window.Instance.Visible == false)

	Window.SetKeyText(FAIL)
	Window.SubmitKey()
	task.wait(0.6)
	check("wrong key rejected", Window.Instance.Visible == false)

	Window.SetKeyText(PASS)
	Window.SubmitKey()
	task.wait(1.2)
	check("correct key accepted", Window.Instance.Visible == true)

	local saved = isfile and isfile("dour_keytest/key.txt") and readfile("dour_keytest/key.txt")
	check("key remembered on disk", saved == PASS)

	Dour:Notify({
		Title = "key system test",
		Content = table.concat(results, "\n"),
		Duration = 12,
		Image = "info",
	})
end)

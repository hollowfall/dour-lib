# Dour Lib

A single-file Luau UI library for Roblox executors. Glassmorphic, animated, and shaped like Rayfield's API so existing scripts port over with one line changed.

```lua
-- language: luau, file: example.lua, runtime: roblox-executor
local Dour = loadstring(readfile("dour-lib/source.lua"))()

local Window = Dour:CreateWindow({
    Name = "Dour Hub",
    LoadingTitle = "Dour Lib",
    LoadingSubtitle = "by santi",
    ConfigurationSaving = { Enabled = true, FolderName = "dourhub", FileName = "config" },
})

local Main = Window:CreateTab("main", "home")
Main:CreateSection("combat")

Main:CreateToggle({
    Name = "aim assist",
    Description = "snaps to the nearest visible target",
    CurrentValue = false,
    Flag = "aim",
    Callback = function(value) print("aim:", value) end,
})

Main:CreateSlider({
    Name = "reach", Range = { 0, 100 }, Increment = 5, Suffix = "studs",
    CurrentValue = 50, Flag = "reach",
    Callback = function(value) print("reach:", value) end,
})

Window:CreateSettingsTab()   -- theme, scale, keybind, config management
```

Read UI state from anywhere in your script, without passing element handles around:

```lua
if Dour:GetFlag("aim") then ... end
```

## What's in it

**Elements** — button, button group, toggle, slider, dropdown (single and multi), input, keybind, colour picker, label, paragraph, divider, section. Each returns `:Set()`, `:SetLocked()` and `:Destroy()`, and accepts `Description`, `Icon` and `Height`.

**Live theming** — presets and a `Theme` table holding every colour, radius, font and duration. `SetTheme` walks the live tree and updates elements that already exist, state colours included. Text contrast follows the background's luminance, so a dark palette always lands on white text.

**Two layouts** — a left tab rail, or `TabPosition = "Top"` for a horizontal tab bar.

**Real Inter** — every text instance uses `FontFace`. Drop Inter's static faces in the executor workspace and the library wires them up through `getcustomasset`; otherwise it falls back to Builder Sans.

**Key system** — masked field with a reveal toggle, Enter to submit, a shake on rejection, and remembered keys.

**Configs** — an automatic config file plus named profiles the end user can save, load and delete from the settings tab.

**Tooltips** — a row whose title or description is too long to fit shows the full text on hover, and stays quiet when it fits.

**Errors that surface** — every callback runs through one funnel with `Dour.OnError`, instead of vanishing into a `pcall`.

## Behaviour notes

- Dragging is a lerped follow from the sidebar or topbar, clamped to the viewport, so the window feels weighted rather than glued to the cursor.
- Sliders track the drag 1:1; only the increment snap on release is tweened.
- Hiding the window — keybind, `Toggle()` or `Minimize()` — leaves a pill at the top of the screen to bring it back. The X destroys it.
- `Dour.Animations = false` turns every tween into an instant property set.
- Mobile is auto-detected: bigger touch targets and a floating toggle button.
- Parenting tries `gethui()`, then `CoreGui`, then `PlayerGui`, all pcall-guarded.
- Config saving needs `writefile` / `readfile` / `isfolder` / `makefolder`; without them it no-ops with a warning.

## Requirements

An executor with `loadstring`, and — for persistence — standard file primitives (`writefile`, `readfile`, `isfolder`, `makefolder`). Named profiles additionally use `listfiles` and `delfile`; real Inter uses `getcustomasset`.

## License

MIT — see [LICENSE](LICENSE).

#!/usr/bin/lua
-- @file: ./scripts/rofi-exit-menu

-- --- LOAD UTILITY MODULE ---
local HOME = os.getenv("HOME")
package.path = package.path .. ";" .. HOME .. "/.local/share/lua/?.lua"

local util = require("utility")

-- --- CONFIGURATION ---
local ROFI_STYLE = [[
    window { width: 300px; height: 240px; padding: 1em; }
    mainbox { children: [listview]; }
    listview { lines: 3; columns: 1; spacing: 4; }
    element { padding: 0.5em; margin: 2px; border-radius: 6px; border: 1px; border-color: @blue; cursor: pointer; }
    element-text { font: "NotoSans Nerd Font Bold 14"; horizontal-align: 0.5; vertical-align: 0.5; text-color: inherit; background-color: inherit; }
]]

-- --- OPTIONS ---
local OPT_LOGOUT   = "<span color='#89b4fa' weight='bold'>󰗼 Logout</span>"
local OPT_REBOOT   = "<span color='#f9e2af' weight='bold'> Reboot</span>"
local OPT_SHUTDOWN = "<span color='#f38ba8' weight='bold'> Shutdown</span>"

-- --- MAIN LOGIC ---

-- 1. Flatten CSS (Hapus newline)
local theme_str = ROFI_STYLE:gsub("\n", " "):gsub("%s+", " ")

-- 2. Bangun Command Pipeline
local input_str = string.format("%s\n%s\n%s", OPT_LOGOUT, OPT_REBOOT, OPT_SHUTDOWN)

local cmd = string.format(
    'echo -e "%s" | rofi -dmenu -i -markup-rows -theme-str \'%s\' -p "System"',
    input_str, theme_str
)

-- 3. Eksekusi & Baca Pilihan (Menggunakan Utility)
-- util.exec otomatis melakukan popen, read, close, dan trim whitespace
local choice = util.exec(cmd)

-- 4. Action
if choice ~= "" then
    if choice:find("Logout")   then os.execute("i3-msg exit")
    elseif choice:find("Reboot")   then os.execute("systemctl reboot")
    elseif choice:find("Shutdown") then os.execute("systemctl poweroff")
    end
end
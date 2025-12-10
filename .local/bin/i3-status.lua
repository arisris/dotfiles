#!/usr/bin/lua
-- @file: ./scripts/i3-status

-- --- LOAD UTILITY MODULE ---
local HOME = os.getenv("HOME")
package.path = package.path .. ";" .. HOME .. "/.local/share/lua/?.lua"

local util = require("utility")

-- --- CONFIGURATION ---
local HOME = os.getenv("HOME")
local MUSIC_UI_CMD = "rofi-music-ui.lua"
local EXIT_MENU_CMD = "rofi-exit-menu.lua"
local INTERNET_CHECK_IP = "1.1.1.1"

-- --- STATE TRACKING ---
local state = {
    active_iface = "",
    prev_rx = 0, prev_tx = 0, prev_time = 0,
    prev_total_cpu = 0, prev_idle_cpu = 0,
    iface_check_counter = 0,
    last_update = 0
}

-- Timers & Constants
local UPDATE_INTERVAL = 1
local IFACE_CHECK_INT = 10 

-- Cache Variables
local cache = {
    net_down = "▼ 0 B/s (0 B)",
    net_up = "▲ 0 B/s (0 B)",
    sys_stats = "Initializing...",
    music_json = "",
    date = "",
    vol_json = ""
}

-- --- HELPER FUNCTIONS (SPECIFIC TO LOGIC) ---

-- Get Active Interface
local function get_active_interface()
    local iface = util.exec("ip route get " .. INTERNET_CHECK_IP .. " 2>/dev/null | awk '{print $5; exit}'")
    if iface == "" then
        iface = util.exec("ip link | awk -F: '$0 !~ \"lo|vir|wl\" && $2 ~ \"UP\" {print $2; exit}' | xargs")
    end
    return iface
end

-- Get Network Bytes
local function get_net_bytes(iface)
    if not iface or iface == "" then return 0, 0 end
    local content = util.read_file("/proc/net/dev")
    if not content then return 0, 0 end
    
    for line in content:gmatch("[^\r\n]+") do
        if line:find(iface .. ":") then
            local clean = line:gsub(":", " "):gsub("%s+", " ")
            local parts = {}
            for part in clean:gmatch("%S+") do table.insert(parts, part) end
            local rx = tonumber(parts[2]) or 0
            local tx = tonumber(parts[10]) or 0
            return rx, tx
        end
    end
    return 0, 0
end

-- Get CPU Stats
local function get_cpu_stats()
    local content = util.read_file("/proc/stat")
    if not content then return 0, 0 end
    local line = content:match("^[^\r\n]*") -- get first line
    
    local user, nice, system, idle, iowait, irq, softirq, steal = 
        line:match("cpu%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
    
    user = tonumber(user) or 0; nice = tonumber(nice) or 0; system = tonumber(system) or 0;
    idle = tonumber(idle) or 0; iowait = tonumber(iowait) or 0; irq = tonumber(irq) or 0;
    softirq = tonumber(softirq) or 0; steal = tonumber(steal) or 0;

    local total = user + nice + system + idle + iowait + irq + softirq + steal
    local idle_total = idle + iowait
    return total, idle_total
end

-- Get RAM Stats
local function get_ram_stats()
    local content = util.read_file("/proc/meminfo")
    if not content then return 0, 0 end
    local total = tonumber(content:match("MemTotal:%s+(%d+)")) or 0
    local avail = tonumber(content:match("MemAvailable:%s+(%d+)")) or 0
    return total, avail
end

-- --- INITIALIZATION ---
print('{"version": 1, "click_events": true}')
print('[')
print('[],')

state.active_iface = get_active_interface()
state.prev_rx, state.prev_tx = get_net_bytes(state.active_iface)
state.prev_time = os.clock()

-- --- MAIN LOOP ---
while true do
    local now = os.time()
    
    -- --- HEAVY TASKS ---
    if (now - state.last_update) >= UPDATE_INTERVAL then
        
        -- 1. NETWORK LOGIC
        state.iface_check_counter = state.iface_check_counter + 1
        if state.iface_check_counter >= IFACE_CHECK_INT or state.active_iface == "" then
            local new_iface = get_active_interface()
            if new_iface ~= state.active_iface then
                state.active_iface = new_iface
                state.prev_rx = 0
                state.prev_tx = 0
            end
            state.iface_check_counter = 0
        end

        local curr_rx, curr_tx = get_net_bytes(state.active_iface)
        local curr_time = os.clock()
        
        -- 2. SYSTEM STATS
        local total_cpu, idle_cpu = get_cpu_stats()
        local mem_total, mem_avail = get_ram_stats()

        -- 3. CALCULATIONS
        local delta_time = curr_time - state.prev_time
        local rx_spd = 0; local tx_spd = 0
        
        if delta_time > 0 then
            rx_spd = (curr_rx - state.prev_rx) / delta_time
            tx_spd = (curr_tx - state.prev_tx) / delta_time
        end
        if rx_spd < 0 then rx_spd = 0 end
        if tx_spd < 0 then tx_spd = 0 end

        local diff_total = total_cpu - state.prev_total_cpu
        local diff_idle = idle_cpu - state.prev_idle_cpu
        local cpu_perc = 0
        if diff_total > 0 then
            cpu_perc = (1 - (diff_idle / diff_total)) * 100
        end

        local ram_used = mem_total - mem_avail
        local ram_gb = ram_used / 1048576
        local tot_gb = mem_total / 1048576

        -- Update Cache (Menggunakan util.human_bytes)
        cache.net_down = string.format("▼ %s/s (%s)", util.human_bytes(rx_spd), util.human_bytes(curr_rx))
        cache.net_up = string.format("▲ %s/s (%s)", util.human_bytes(tx_spd), util.human_bytes(curr_tx))
        cache.sys_stats = string.format("<span color='#8BE9FD'>󰍛</span> %.0f%%  ~  <span color='#FFB86C'></span> %.1f/%.0fG", cpu_perc, ram_gb, tot_gb)

        -- Update History
        state.prev_rx = curr_rx
        state.prev_tx = curr_tx
        state.prev_time = curr_time
        state.prev_total_cpu = total_cpu
        state.prev_idle_cpu = idle_cpu

        -- 4. MUSIC MODULE (Menggunakan util.exec & util.sanitize_json)
        local meta = util.exec("playerctl metadata -p mpv --format '{{ status }}::{{ artist }} - {{ title }}' 2>/dev/null")
        if meta ~= "" then
            local status, info = meta:match("^(.-)::(.*)$")
            if not status then status = ""; info = meta end
            
            local safe_info = util.sanitize_json(info)
            if #safe_info > 30 then safe_info = safe_info:sub(1, 30) .. "..." end
            
            if status:lower() == "playing" then
                cache.music_json = string.format('{"full_text":"", "name":"music_prev", "separator":false, "separator_block_width":5},{"full_text":" %s", "name":"music_play_pause", "separator":false, "separator_block_width":5, "color":"#50FA7B"},{"full_text":"", "name":"music_next", "separator":true, "separator_block_width":20}', safe_info)
            else
                cache.music_json = string.format('{"full_text":"", "name":"music_prev", "separator":false, "separator_block_width":5},{"full_text":" %s", "name":"music_play_pause", "separator":false, "separator_block_width":5, "color":"#FFB86C"},{"full_text":"", "name":"music_next", "separator":true, "separator_block_width":20}', safe_info)
            end
        else
            cache.music_json = '{"full_text":"Select Music", "name":"music_select", "separator":true, "separator_block_width":20, "color":"#6272A4"}'
        end

        cache.date = os.date("%a %d %b ~ %H:%M")
        state.last_update = now
    end

    -- --- LIGHT TASKS ---
    local vol_data = util.exec("pactl get-sink-volume @DEFAULT_SINK@ | head -n1")
    local vol_raw = vol_data:match("(%d+)%%") or "0"
    vol_raw = tonumber(vol_raw) or 0
    local mute_raw = util.exec("pactl get-sink-mute @DEFAULT_SINK@")
    
    if mute_raw:find("yes") then
        cache.vol_json = '{"full_text":"󰝟 Muted", "name":"pactl_mute", "separator":true, "separator_block_width":20}'
    else
        local icon = ""
        if vol_raw >= 50 then icon = ""
        elseif vol_raw > 0 then icon = ""
        end
        cache.vol_json = string.format('{"full_text":"", "name":"pactl_vol_down", "separator":false, "separator_block_width":8},{"full_text":"%s %d%%", "name":"volume_text", "separator":false, "separator_block_width":8},{"full_text":"", "name":"pactl_vol_up", "separator":true, "separator_block_width":20}', icon, vol_raw)
    end

    -- --- OUTPUT ---
    io.write("[")
    io.write(string.format('{"full_text":"%s", "name":"net_speed", "separator":false, "separator_block_width":0, "min_width": 90, "align": "center"},', cache.net_down))
    io.write(string.format('{"full_text":"%s", "name":"net_speed", "separator":true, "separator_block_width":20, "min_width": 90, "align": "center"},', cache.net_up))
    io.write(string.format('{"full_text":"%s", "name":"sys_stats", "markup":"pango", "separator":true, "separator_block_width":20, "min_width": 100, "align": "center"},', cache.sys_stats))
    io.write('{"full_text":"󰎆", "name":"music_select", "color":"#BD93F9", "separator":false, "separator_block_width":5},')
    io.write(cache.music_json .. ",")
    io.write(cache.vol_json .. ",")
    io.write(string.format('{"full_text":" %s", "name":"datetime", "separator":true, "separator_block_width":20},', cache.date))
    io.write('{"full_text":"<span color=\'#FFFFFF\' size=\'x-large\'></span>", "name":"power_menu", "markup":"pango", "separator":false}')
    io.write("],\n")
    io.flush()

    -- --- INPUT HANDLING ---
    -- Using pcall wrapper for LuaJIT stability during interrupts
    -- Bagian ini tetap menggunakan io.popen spesifik karena membutuhkan perilaku 'read -t 1' (timeout) dari bash
    local status, line = pcall(function()
        local h = io.popen("bash -c 'read -t 1 line; echo \"$line\"'")
        if not h then return nil end
        local out = h:read("*a")
        h:close()
        return out
    end)

    if status and line and #line > 0 then
        local clean = line:gsub("^%s*,", ""):gsub("^%s*%[", ""):gsub("%s*%]%s*$", "")
        local button = clean:match('"button"%s*:%s*(%d+)')
        
        if button == "1" then
            local name = clean:match('"name"%s*:%s*"([^"]+)"')
            if name == "pactl_mute" then os.execute("pactl set-sink-mute @DEFAULT_SINK@ toggle")
            elseif name == "pactl_vol_down" then os.execute("pactl set-sink-volume @DEFAULT_SINK@ -5%")
            elseif name == "pactl_vol_up" then os.execute("pactl set-sink-volume @DEFAULT_SINK@ +5%")
            elseif name == "music_select" then os.execute(MUSIC_UI_CMD .. " &")
            elseif name == "music_prev" then os.execute("playerctl -p mpv previous")
            elseif name == "music_play_pause" then os.execute("playerctl -p mpv play-pause")
            elseif name == "music_next" then os.execute("playerctl -p mpv next")
            elseif name == "power_menu" then os.execute(EXIT_MENU_CMD .. " &")
            end
        end
    end
end
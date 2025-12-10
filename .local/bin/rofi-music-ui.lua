#!/usr/bin/lua
-- @file: ./scripts/rofi-music-ui

-- --- LOAD UTILITY MODULE ---
local HOME = os.getenv("HOME")
package.path = package.path .. ";" .. HOME .. "/.local/share/lua/?.lua"

local util = require("utility")

-- --- CONFIGURATION ---
local HOME = os.getenv("HOME")
local MUSIC_DIR = HOME .. "/Music"
local SOCKET_PATH = "/tmp/mpv_music_socket"

-- --- VISUALS ---
local ACTIVE_COLOR = "#2ec27e"
local ACTIVE_ICON = "<b>󰎆</b>"
local ADWAITA_THEME = "listview { columns: 1; }"

-- --- MAIN LOGIC ---

-- 1. Scan File
-- Menggunakan util.exec untuk mengambil output find
local find_cmd = string.format("find -L '%s' -type f | grep -iE '\\.(mp3|flac|wav|m4a|ogg|opus)$' | sort", MUSIC_DIR)
local find_output = util.exec(find_cmd)

local files = {}
for line in find_output:gmatch("[^\r\n]+") do
    table.insert(files, line)
end

if #files == 0 then
    os.execute(string.format("rofi -e 'No music found in %s'", MUSIC_DIR))
    os.exit(1)
end

-- 2. Cek Lagu yang Sedang Putar
local current_index = -1
local raw_url = util.exec("playerctl metadata xesam:url 2>/dev/null")

if raw_url ~= "" then
    local clean_url = raw_url:gsub("^file://", "")
    -- Menggunakan util.url_decode
    local current_path = util.url_decode(clean_url)

    for i, file_path in ipairs(files) do
        if file_path == current_path then
            current_index = i - 1 -- Rofi index 0-based
            break
        end
    end
end

-- 3. Buat File List
-- Kita tampung output string dalam table dulu (Buffer) agar efisien
local list_buffer = {}
for i, file_path in ipairs(files) do
    local display_name = file_path:sub(#MUSIC_DIR + 2)
    -- Menggunakan util.escape_pango
    local safe_name = util.escape_pango(display_name)
    
    if (i - 1) == current_index then
        -- Menandai lagu aktif
        table.insert(list_buffer, string.format("<span weight='bold' color='%s'>%s  %s</span>", ACTIVE_COLOR, ACTIVE_ICON, safe_name))
    else
        table.insert(list_buffer, safe_name)
    end
end

local list_file = "/tmp/rofi_music_list.tmp"
-- Menggunakan util.write_file (menggabungkan buffer dengan newline)
if not util.write_file(list_file, table.concat(list_buffer, "\n")) then
    print("Error: Cannot write to /tmp")
    os.exit(1)
end

-- 4. Jalankan Rofi
local rofi_cmd_str = string.format(
    "cat '%s' | rofi -dmenu -i -markup-rows -theme-str '%s' -p '󰎆 Music Library' -format i", 
    list_file, ADWAITA_THEME
)

if current_index >= 0 then
    rofi_cmd_str = rofi_cmd_str .. " -selected-row " .. current_index
end

-- Eksekusi Rofi menggunakan util.exec
local output = util.exec(rofi_cmd_str)

-- 5. Proses Pilihan
if output ~= "" then
    local selected_index = tonumber(output)
    
    if selected_index then
        -- Lua index 1-based, Rofi index 0-based
        local file_to_play = files[selected_index + 1]
        
        -- Reset Playlist & Play
        os.execute(string.format("pkill -f 'mpv .*--input-ipc-server=%s'", SOCKET_PATH))
        
        -- Tulis playlist m3u menggunakan util.write_file
        local playlist_file = "/tmp/rofi_lua_playlist.m3u"
        util.write_file(playlist_file, table.concat(files, "\n"))
        
        -- Jalankan MPV (nohup agar tidak mati saat script exit)
        local mpv_cmd = string.format(
            "nohup mpv --no-video --idle --input-ipc-server='%s' --playlist-start=%d --playlist='%s' >/dev/null 2>&1 &",
            SOCKET_PATH, selected_index, playlist_file
        )
        os.execute(mpv_cmd)
        
        -- Notifikasi
        local song_title = file_to_play:match("^.+/(.+)$") or file_to_play
        -- Escape single quote manual disini karena ini untuk shell argument (bash), bukan Pango/XML
        song_title = song_title:gsub("'", "'\\''")
        os.execute(string.format("notify-send 'Playing Music' '%s' -i audio-x-generic &", song_title))
    end
end

-- Cleanup
os.remove(list_file)
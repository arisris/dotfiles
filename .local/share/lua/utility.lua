-- @file: ./scripts/utility.lua
local M = {}

-- ===========================
-- SYSTEM & FILESYSTEM
-- ===========================

-- Membaca isi file secara aman
-- [diambil dari i3-status, source: 2]
function M.read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

-- Menulis isi ke file (Replaces content)
-- [diadaptasi dari logika rofi-music-ui, source: 40, 43]
function M.write_file(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

-- Eksekusi command shell dan ambil outputnya (dengan trim whitespace)
-- [diambil dari i3-status, source: 2, 3]
function M.exec(cmd)
    local handle = io.popen(cmd)
    if not handle then return "" end
    local output = handle:read("*a")
    handle:close()
    if not output then return "" end
    return output:gsub("^%s*(.-)%s*$", "%1") -- trim otomatis
end

-- ===========================
-- STRING FORMATTING & LOGIC
-- ===========================

-- Konversi byte ke format human readable (B, K, M, G)
-- [diambil dari i3-status, source: 3]
function M.human_bytes(b)
    if b < 1024 then return string.format("%.0f B", b)
    elseif b < 1048576 then return string.format("%.1f K", b/1024)
    elseif b < 1073741824 then return string.format("%.1f M", b/1048576)
    else return string.format("%.2f G", b/1073741824)
    end
end

-- Decode URL encoded string (misal: %20 jadi spasi)
-- [diambil dari rofi-music-ui, source: 36]
function M.url_decode(str)
    return str:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end):gsub("+", " ")
end

-- ===========================
-- SANITIZATION & ESCAPING
-- ===========================

-- Membersihkan string agar aman untuk JSON (i3bar)
-- [diambil dari i3-status, source: 10]
function M.sanitize_json(str)
    if not str then return "" end
    -- 1. Ganti backslash (\) menjadi double backslash (\\) - HARUS PERTAMA
    str = str:gsub("\\", "\\\\")
    -- 2. Ganti double quote (") menjadi escaped quote (\")
    str = str:gsub('"', '\\"')
    -- 3. Hapus karakter newline/enter
    str = str:gsub("[\n\r]", " ")
    -- 4. Hapus karakter kontrol
    str = str:gsub("%c", "") 
    return str
end

-- Escape string untuk Pango Markup (XML entities)
-- Menggabungkan logika dari i3-status dan rofi-music-ui
-- [diambil dari i3-status source: 11 dan rofi-music-ui source: 37]
function M.escape_pango(str)
    if not str then return "" end
    str = str:gsub("&", "&amp;")
    str = str:gsub("<", "&lt;")
    str = str:gsub(">", "&gt;")
    -- Tambahan dari rofi-music-ui untuk keamanan shell jika string dipakai di command
    str = str:gsub("'", "'\\''") 
    return str
end

return M
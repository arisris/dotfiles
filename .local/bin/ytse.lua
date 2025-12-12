#!/usr/bin/lua
local lgi = require('lgi')
local Gtk = lgi.require('Gtk', '3.0')
local Gdk = lgi.require('Gdk', '3.0')
local GdkPixbuf = lgi.require('GdkPixbuf', '2.0')
local GLib = lgi.GLib

GLib.set_prgname("ytse")
Gdk.set_program_class("Ytse")

-- === DEPENDENCY CHECK ===
local function check_dep(cmd)
  local h = io.popen("which " .. cmd)
  local r = h:read("*a")
  h:close()
  return r ~= ""
end

if not check_dep("curl") then print("Error: 'curl' diperlukan."); os.exit(1) end
if not check_dep("yt-dlp") then print("Error: 'yt-dlp' tidak ditemukan."); os.exit(1) end

-- === ARGUMENT PARSING ===
local cli_limit = 10
local cli_query_parts = {}
local skip_next = false

for i = 1, #arg do
  if skip_next then
    skip_next = false
  elseif arg[i] == "-n" then
    cli_limit = tonumber(arg[i+1]) or 10
    skip_next = true
  else
    table.insert(cli_query_parts, arg[i])
  end
end
local cli_query = table.concat(cli_query_parts, " ")

-- === GLOBAL VARS & WIDGET REFS ===
local stack
local ui = {
    -- Detail Page Widgets
    det_img = nil, det_title = nil, det_chan = nil, det_dur = nil,
    det_bbox = nil, 
    
    -- Download Page Widgets
    dl_title = nil, dl_status = nil, dl_progress = nil,
    dl_btn_cancel = nil, dl_btn_back = nil,
    
    -- State
    current_pid = nil
}

-- === HELPERS ===

local function ensure_thumbnail(video_id)
  if not video_id then return nil end
  local url = "https://i.ytimg.com/vi/" .. video_id .. "/hqdefault.jpg"
  local tmp_path = "/tmp/ytse_" .. video_id .. ".jpg"

  local f = io.open(tmp_path, "r")
  if f then
    local size = f:seek("end")
    f:close()
    if size > 100 then return tmp_path end
  end

  local cmd = string.format("curl -sL '%s' -o '%s'", url, tmp_path)
  os.execute(cmd)
  return tmp_path
end

local function set_image(gtk_img, path, w)
  local status, pb = pcall(function() 
       return GdkPixbuf.Pixbuf.new_from_file_at_scale(path, w, -1, true) 
  end)
  if status and pb then
    gtk_img:set_from_pixbuf(pb)
  else
    gtk_img:set_from_icon_name("image-missing", Gtk.IconSize.DIALOG)
    gtk_img:set_pixel_size(w)
  end
end

-- === LOGIC: DOWNLOAD PROCESS ===

local function stop_download()
  if ui.current_pid then
    local pid_int = math.floor(ui.current_pid)
    os.execute("kill -9 " .. pid_int)
    ui.current_pid = nil
    ui.dl_status.label = "Dibatalkan oleh user."
    ui.dl_btn_back.sensitive = true
    ui.dl_btn_cancel.sensitive = false
  end
end

local function start_download_page(video_url, format_type, title)
  ui.dl_title.label = "<b>" .. title .. "</b>"
  ui.dl_status.label = "Menghubungkan ke server..."
  ui.dl_progress:set_fraction(0.0)
  ui.dl_progress:set_text("0%")
  ui.dl_btn_cancel.sensitive = true
  ui.dl_btn_back.sensitive = false 
  
  stack:set_visible_child_name("page_download")

  local dl_path = os.getenv("HOME") .. "/Downloads/%(title)s.%(ext)s"
  
  -- Force unbuffered output
  local args = { "/usr/bin/env", "PYTHONUNBUFFERED=1", "yt-dlp", "--newline" }

  if format_type == "audio" then
    table.insert(args, "-x")
    table.insert(args, "--audio-format")
    table.insert(args, "mp3")
  else
    table.insert(args, "-f")
    table.insert(args, "bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4")
  end
  
  table.insert(args, "-o")
  table.insert(args, dl_path)
  table.insert(args, video_url)

  local pid, stdin, stdout, stderr, err = GLib.spawn_async_with_pipes(
    nil, args, nil, 
    GLib.SpawnFlags.SEARCH_PATH + GLib.SpawnFlags.DO_NOT_REAP_CHILD, 
    nil
  )

  if not pid then
    local err_msg = tostring(err or "Unknown Error")
    ui.dl_status.label = "Gagal: " .. err_msg
    ui.dl_btn_back.sensitive = true
    return
  end
  
  ui.current_pid = pid

  local out_io = GLib.IOChannel.unix_new(stdout)
  out_io:set_flags(GLib.IOFlags.NONBLOCK)

  GLib.io_add_watch(out_io, GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN, function(channel, condition)
    local status, line
    while true do
        status, line = channel:read_line()
        if status == GLib.IOStatus.EOF then return false
        elseif status == GLib.IOStatus.AGAIN then break
        elseif status == GLib.IOStatus.NORMAL and line then
            local clean = line:match("^%s*(.-)%s*$")
            local percent_str = clean:match("(%d+%.?%d*)%%")
            
            if percent_str then
                local frac = tonumber(percent_str) / 100
                ui.dl_progress:set_fraction(frac)
                ui.dl_progress:set_text(percent_str .. "%")
                local status_txt = clean:gsub("%[download%]%s*", "")
                if #status_txt > 60 then status_txt = status_txt:sub(1, 57).."..." end
                ui.dl_status.label = status_txt
            else
                if clean ~= "" and not clean:find("Destination:") then
                   local info_txt = clean:gsub("%[.-%]%s*", "")
                   ui.dl_status.label = "Proses: " .. info_txt
                end
            end
        else break end
    end
    return true
  end)

  GLib.child_watch_add(GLib.PRIORITY_DEFAULT, pid, function(p, status)
    ui.dl_progress:set_fraction(1.0)
    ui.dl_progress:set_text("100%")
    ui.dl_status.label = "Selesai! Disimpan di ~/Downloads"
    ui.dl_btn_cancel.sensitive = false
    ui.dl_btn_back.sensitive = true
    ui.current_pid = nil
    GLib.spawn_close_pid(p)
  end)
end

-- === LOGIC: SEARCH ===

local function search_youtube(query, limit)
  limit = limit or 10
  local cmd = string.format('yt-dlp --flat-playlist --dump-json --no-warnings "ytsearch%d:%s"', limit, query:gsub('"', '\\"'))
  local handle = io.popen(cmd)
  local res = {}
  if not handle then return res end
  
  for line in handle:lines() do
    local id = line:match('"id"%s*:%s*"(.-)"')
    local title = line:match('"title"%s*:%s*"(.-)"')
    local uploader = line:match('"uploader"%s*:%s*"(.-)"') or "?"
    local duration = line:match('"duration_string"%s*:%s*"(.-)"') or ""
    
    if id and title then
      table.insert(res, { id=id, title=title, uploader=uploader, duration=duration, url="https://www.youtube.com/watch?v="..id })
    end
  end
  handle:close()
  return res
end

-- === UI BUILDERS ===

local function create_search_page(initial_query, initial_limit)
  local vbox = Gtk.Box { orientation = 'VERTICAL', spacing = 10, margin = 10 }
  
  local hbox = Gtk.Box { spacing = 5 }
  local entry = Gtk.Entry { placeholder_text = "Cari di YouTube... (Enter untuk cari)" }
  local btn = Gtk.Button { label = "Cari" }
  hbox:pack_start(entry, true, true, 0)
  hbox:pack_start(btn, false, false, 0)
  
  local scroll = Gtk.ScrolledWindow { shadow_type = 'ETCHED_IN' }
  local listbox = Gtk.ListBox {}
  listbox:set_can_focus(true)
  scroll:add(listbox)
  
  vbox:pack_start(hbox, false, false, 0)
  vbox:pack_start(scroll, true, true, 0)
  
  -- Key Navigation
  entry.on_key_press_event = function(widget, event)
    if event.keyval == 65364 then -- Down
      local row = listbox:get_row_at_index(0)
      if row then
         listbox:select_row(row)
         row:grab_focus()
         return true
      end
    end
    return false
  end

  listbox.on_key_press_event = function(widget, event)
    if event.keyval == 65362 then -- Up
      local row = listbox:get_selected_row()
      if row and row:get_index() == 0 then
        listbox:unselect_all()
        entry:grab_focus()
        entry:set_position(-1)
        return true
      end
    end
    return false
  end

  local results_map = {}
  local function do_search()
    local q = entry.text
    if q == "" then return end
    btn.sensitive = false
    btn.label = "..."
    
    local kids = listbox:get_children()
    if kids then for i=1,#kids do listbox:remove(kids[i]) end end
    results_map = {}
    while Gtk.events_pending() do Gtk.main_iteration() end
    
    local search_limit = (q == initial_query) and initial_limit or 10
    local videos = search_youtube(q, search_limit)
    
    if #videos == 0 then
        listbox:add(Gtk.Label{label="\nTidak ditemukan.", margin=20})
    else
        for _, v in ipairs(videos) do
            local row = Gtk.ListBoxRow {}
            row:set_can_focus(true)
            results_map[row] = v
            local rb = Gtk.Box{orientation='HORIZONTAL', spacing=10, margin=5}
            
            local img = Gtk.Image(); img:set_pixel_size(60)
            local p = ensure_thumbnail(v.id)
            if p then set_image(img, p, 80) else img:set_from_icon_name("image-missing", Gtk.IconSize.DND) end
            
            local txt = Gtk.Box{orientation='VERTICAL', spacing=2}
            txt:set_valign(Gtk.Align.CENTER)
            txt:add(Gtk.Label{label="<b>"..v.title.."</b>", use_markup=true, xalign=0, ellipsize='END', max_width_chars=40})
            txt:add(Gtk.Label{label="<small>"..v.uploader.." ("..v.duration..")</small>", use_markup=true, xalign=0, opacity=0.7})
            
            rb:pack_start(img, false, false, 0)
            rb:pack_start(txt, true, true, 0)
            row:add(rb)
            listbox:add(row)
            while Gtk.events_pending() do Gtk.main_iteration() end
        end
    end
    listbox:show_all()
    btn.sensitive = true
    btn.label = "Cari"
    
    if q == initial_query then
        local first = listbox:get_row_at_index(0)
        if first then
            listbox:select_row(first)
            first:grab_focus()
        end
    end
  end
  
  entry.on_activate = do_search
  btn.on_clicked = do_search
  
  listbox.on_row_activated = function(_, row)
    local v = results_map[row]
    if v then
        ui.det_title.label = "<span size='x-large' weight='bold'>" .. v.title .. "</span>"
        ui.det_chan.label = v.uploader
        ui.det_dur.label = v.duration
        local p = ensure_thumbnail(v.id)
        if p then set_image(ui.det_img, p, 400) end
        
        local children = ui.det_bbox:get_children()
        if children then for i = 1, #children do ui.det_bbox:remove(children[i]) end end
        
        local btn_mp4 = Gtk.Button { label = "Download MP4" }
        local btn_mp3 = Gtk.Button { label = "Download MP3" }
        local btn_play = Gtk.Button { label = "Putar (mpv)" }
        
        btn_mp4.on_clicked = function() start_download_page(v.url, "video", v.title) end
        btn_mp3.on_clicked = function() start_download_page(v.url, "audio", v.title) end
        btn_play.on_clicked = function() os.execute(string.format("mpv '%s' &", v.url)) end
        
        ui.det_bbox:add(btn_mp4)
        ui.det_bbox:add(btn_mp3)
        ui.det_bbox:add(btn_play)
        ui.det_bbox:show_all()
        
        stack:set_visible_child_name("page_detail")
    end
  end

  if initial_query and initial_query ~= "" then
    entry.text = initial_query
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, function()
        do_search()
        return false 
    end)
  end

  return vbox
end

local function create_detail_page()
  local vbox = Gtk.Box { orientation = 'VERTICAL', spacing = 15, margin = 20 }
  
  local head_box = Gtk.Box { orientation = 'HORIZONTAL' }
  local btn_back = Gtk.Button.new_from_icon_name("go-previous", Gtk.IconSize.BUTTON)
  btn_back.label = " Kembali"
  btn_back.always_show_image = true
  btn_back.on_clicked = function() stack:set_visible_child_name("page_search") end
  head_box:pack_start(btn_back, false, false, 0)
  
  ui.det_img = Gtk.Image()
  ui.det_title = Gtk.Label { use_markup=true, wrap=true, xalign=0 }
  ui.det_chan = Gtk.Label { xalign=0 }
  ui.det_dur = Gtk.Label { xalign=0 }
  
  ui.det_bbox = Gtk.Box { orientation = 'HORIZONTAL', spacing = 10, homogeneous = true, margin_top=20 }
  
  vbox:pack_start(head_box, false, false, 0)
  vbox:pack_start(ui.det_img, false, false, 0)
  vbox:pack_start(ui.det_title, false, false, 0)
  vbox:pack_start(ui.det_chan, false, false, 0)
  vbox:pack_start(ui.det_dur, false, false, 0)
  vbox:pack_start(ui.det_bbox, false, false, 0)
  return vbox
end

local function create_download_page()
  local vbox = Gtk.Box { orientation = 'VERTICAL', spacing = 20, margin = 40 }
  vbox:set_valign(Gtk.Align.CENTER)
  
  ui.dl_title = Gtk.Label { use_markup=true, wrap=true }
  ui.dl_progress = Gtk.ProgressBar { show_text = true }
  ui.dl_status = Gtk.Label { label = "Waiting..." }
  
  local bbox = Gtk.Box { orientation = 'HORIZONTAL', spacing = 10, homogeneous = true }
  ui.dl_btn_cancel = Gtk.Button { label = "Batalkan" }
  ui.dl_btn_back = Gtk.Button { label = "Kembali ke Detail" }
  
  ui.dl_btn_cancel.on_clicked = stop_download
  ui.dl_btn_back.on_clicked = function() stack:set_visible_child_name("page_detail") end
  
  bbox:add(ui.dl_btn_cancel)
  bbox:add(ui.dl_btn_back)
  
  vbox:pack_start(ui.dl_title, false, false, 0)
  vbox:pack_start(ui.dl_progress, false, false, 0)
  vbox:pack_start(ui.dl_status, false, false, 0)
  vbox:pack_start(bbox, false, false, 0)
  return vbox
end

-- === MAIN ===

local window = Gtk.Window { title = "YouTube Browser", default_width=500, default_height=700, window_position=Gtk.WindowPosition.CENTER }
window.on_destroy = Gtk.main_quit

stack = Gtk.Stack()
stack:set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
stack:set_transition_duration(300)

stack:add_named(create_search_page(cli_query, cli_limit), "page_search")
stack:add_named(create_detail_page(), "page_detail")
stack:add_named(create_download_page(), "page_download")

stack:set_visible_child_name("page_search")

window:add(stack)
window:show_all()
Gtk.main()
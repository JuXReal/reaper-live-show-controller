-- ============================================================
--  Setlist_Manager_Regions_ImGui_Styled.lua  (SAFE MODE + REMOTE)
--  Setlist-Manager für REAPER-Regions mit hübscher GUI,
--  Light/Dark, Fullscreen, Hilfe, UI-Scale, A/B-Datei-Sync
--  Version: 1.6.1-safe (About unter Help)
-- ============================================================


-- ============================================================
-- KAPITEL 1 — REQUIREMENTS, CONFIG & GLOBAL STATE
-- ============================================================

if not reaper or not reaper.ImGui_CreateContext then
  reaper.MB("ReaImGui ist nicht installiert.\nExtensions → ReaPack → Browse → 'ReaImGui' installieren, dann REAPER neu starten.", "Setlist Manager", 0)
  return
end

local APP = "Setlist Manager (Regions) – Styled"
local VER = "1.6.1-safe"
local DIR_SET = reaper.GetResourcePath() .. "/Setlists"
local PATH_STATUS = reaper.GetResourcePath() .. "/Setlists/status.json"
local WRITE_IVL, POLL_IVL = 0.12, 0.12
local TIME_EPS = 0.03
local UI_SCALE = 1.20

-- Safe Mode: nur Default-Font, keine StyleColor-Pushes
local USE_ONLY_DEFAULT_FONT = true

-- *** Neues Setting: Start-Warnung anzeigen? ***
local SHOW_WARNING = true

local ctx = reaper.ImGui_CreateContext(APP)
local FONT_UI, FONT_BIG, FONT_HUGE  -- bleiben im Safe Mode nil
local theme = "Dark"          -- "Dark" | "Light"
local mode  = "EDIT"          -- "EDIT" | "SHOW"
local role  = "LEADER"        -- "LEADER" | "FOLLOWER"
local last_write, last_poll = 0, 0
local is_playing, fullscreen = false, false
local prev_mode = mode

local regions = {}
local setlist = { name = "My Set", entries = {} }
local files = {}
local current = 1
local selected_set_file = 1

local show_help_quick = false
local show_help_keys  = false
local show_help_about = false   -- <<< NEU: About & Support Popup

-- Popups/Info: Start-Haftungshinweis (Footer ist entfernt)
local show_warning_pending = SHOW_WARNING
local show_info_footer = false  -- <<< Kein Footer mehr

-- Remote/MIDI via ExtState
local REMOTE_KEY = "SetlistMgrRemote"



-- ============================================================
-- KAPITEL 2 — HILFSFUNKTIONEN (I/O, UI, UTILS)
-- ============================================================

local function ensure_dir(p) reaper.RecursiveCreateDirectory(p, 0) end
local function readf(p) local f=io.open(p,"rb") if not f then return nil end local c=f:read("*a") f:close() return c end
local function writef(p,s) ensure_dir(DIR_SET) local f=io.open(p,"wb") if not f then return false end f:write(s) f:close() return true end
local function now() return reaper.time_precise() end
local function get_play_state() local st=reaper.GetPlayState(); return (st&1)==1,(st&2)==2 end
local function display_size()
  if reaper.ImGui_GetDisplaySize then local w,h=reaper.ImGui_GetDisplaySize(ctx) return w,h end
  if reaper.ImGui_GetIO then local io=reaper.ImGui_GetIO(ctx) return io.DisplaySize_x, io.DisplaySize_y end
  return 1280,720
end
local function SliderNumber(label, value, minv, maxv)
  if reaper.ImGui_SliderDouble then
    return reaper.ImGui_SliderDouble(ctx, label, value, minv, maxv, "%.2f")
  else
    return reaper.ImGui_SliderFloat(ctx, label, value, minv, maxv, "%.2f")
  end
end



-- ============================================================
-- KAPITEL 3 — REGIONS & SETLIST I/O
-- ============================================================

local function scan_regions()
  regions = {}
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local total = (num_markers or 0) + (num_regions or 0)
  for i=0, total-1 do
    local ok, isrgn, pos, rgnend, name, idx = reaper.EnumProjectMarkers3(0, i)
    if ok and isrgn then
      regions[#regions+1] = { idx=idx, name=(name~="" and name or ("Region "..idx)), start=pos, fin=rgnend }
    end
  end
  table.sort(regions, function(a,b) return a.start < b.start end)
end

local function R(id)
  for _,r in ipairs(regions) do
    if r.idx==id then return r end
  end
end

-- Fallback: Region per Name suchen
local function R_by_name(name)
  if not name or name == "" then return nil end
  for _, r in ipairs(regions) do
    if r.name == name then return r end
  end
  return nil
end

local function refresh_files()
  files = {}
  ensure_dir(DIR_SET)
  local i=0
  while true do
    local fn = reaper.EnumerateFiles(DIR_SET, i); if not fn then break end
    if fn:match("%.reaplaylist%.txt$") then files[#files+1]=fn end
    i=i+1
  end
  table.sort(files)
  if selected_set_file > #files then selected_set_file = #files end
  if selected_set_file < 1 then selected_set_file = (#files>0) and 1 or 0 end
end

local function save_set()
  if #setlist.entries==0 then reaper.MB("Setlist ist leer.","Save",0) return end
  local ok, nm = reaper.GetUserInputs("Save Setlist",1,"Name:", setlist.name or "Set")
  if not ok or nm=="" then return end
  setlist.name = nm
  local path = DIR_SET.."/"..nm:gsub("[^%w%-%._ ]","_")..".reaplaylist.txt"
  local t = {"# "..nm}
  -- Abwärtskompatibel, aber mit optionalem Namen (3. Feld)
  for _,e in ipairs(setlist.entries) do
    local rr = R(e.region_idx) or R_by_name(e.name)
    local nm_safe = (e.name or (rr and rr.name) or ""):gsub("[\r\n]", " "):gsub(";", ",")
    t[#t+1] = string.format("%d;%d;%s", e.region_idx or -1, (e.continue~=false) and 1 or 0, nm_safe)
  end
  if writef(path, table.concat(t,"\n")) then refresh_files() end
end

local function load_set_by_index(i)
  if i<1 or i>#files then return end
  local fn = files[i]
  local txt = readf(DIR_SET.."/"..fn); if not txt then return end
  local nm = fn:gsub("%.reaplaylist%.txt$","")
  local entries = {}
  for line in txt:gmatch("[^\r\n]+") do
    if not line:match("^#") and line:find(";") then
      -- 2- oder 3-spaltig: idx;cont[;name]
      local a,b,c = line:match("([^;]+);([^;]+);?(.*)")
      local ridx = tonumber(a or "")
      local cont = (b=="1" or b=="true")
      local name = (c and c ~= "") and c or nil
      if ridx then entries[#entries+1] = {region_idx=ridx, continue=cont, name=name} end
    end
  end
  if #entries>0 then setlist = {name=nm, entries=entries}; current=1 end
end

local function delete_set_by_index(i)
  if i<1 or i>#files then return end
  os.remove(DIR_SET.."/"..files[i]); refresh_files()
end



-- ============================================================
-- KAPITEL 4 — PLAYBACK, ENGINE & A/B-SYNC
-- ============================================================

local function play_entry(e)
  local r = e and (R(e.region_idx) or R_by_name(e.name)); if not r then return end
  reaper.SetEditCurPos(r.start, true, true)
  reaper.CSurf_OnPlay(); is_playing = true
end
local function stop_play() reaper.CSurf_OnStop(); is_playing=false end
local function goto_i(i,autoplay) if i<1 then i=1 elseif i>#setlist.entries then i=#setlist.entries end current=i if autoplay then play_entry(setlist.entries[current]) end end
local function next_song(a) goto_i(current+1,a) end
local function prev_song(a) goto_i(current-1,a) end

local function status_build()
  local e = setlist.entries[current]
  local playing, paused = get_play_state()
  local r = e and (R(e.region_idx) or R_by_name(e.name))
  return {
    role=role, set=setlist.name or "", index=current, total=#setlist.entries,
    playing=playing, paused=paused,
    region_name=r and r.name or "", region_idx=r and r.idx or -1,
    status=(playing and "play") or (paused and "pause") or "stop"
  }
end
local function json_of(t)
  local function esc(s) return (s or ""):gsub('\\','\\\\'):gsub('"','\\"') end
  local parts={}
  for k,v in pairs(t) do
    local vv = (type(v)=="string") and ('"'..esc(v)..'"')
             or (type(v)=="boolean") and (v and "true" or "false")
             or tostring(v)
    parts[#parts+1] = '"'..k..'":'..vv
  end
  return "{"..table.concat(parts,",").."}"
end
local function json_parse_flat(s)
  local t={}
  for k,v in s:gmatch('"(.-)"%s*:%s*([^,}]+)') do
    v=v:gsub('^"%s*',''):gsub('%s*"$','')
    if v=="true" then t[k]=true elseif v=="false" then t[k]=false
    elseif v:match("^%-?%d+%.?%d*$") then t[k]=tonumber(v) else t[k]=v end
  end
  return t
end
local function status_write()
  if role~="LEADER" then return end
  local t=now(); if t-last_write<WRITE_IVL then return end; last_write=t
  writef(PATH_STATUS, json_of(status_build()))
end
local function status_poll()
  if role~="FOLLOWER" then return end
  local t=now(); if t-last_poll<POLL_IVL then return end; last_poll=t
  local txt = readf(PATH_STATUS); if not txt then return end
  local d = json_parse_flat(txt); if not d then return end
  if d.index and d.index~=current then goto_i(math.max(1, math.min(#setlist.entries, d.index)), d.status=="play") end
  if d.status=="stop" and is_playing then stop_play() end
  if d.status=="play" and not is_playing then play_entry(setlist.entries[current]) end
end
local function engine()
  local e = setlist.entries[current]
  local playing = select(1, get_play_state())
  if e and playing then
    local r = R(e.region_idx) or R_by_name(e.name)
    if r and (r.fin - reaper.GetPlayPosition()) <= TIME_EPS then
      if e.continue~=false and current < #setlist.entries then next_song(true) else stop_play() end
    end
  end
end



-- ============================================================
-- KAPITEL 5 — REMOTE/MIDI (ExtState)
-- ============================================================

local function handle_remote()
  local cmd = reaper.GetExtState(REMOTE_KEY, "cmd")
  if not cmd or cmd == "" then return end
  if cmd == "play_toggle" then
    if is_playing then stop_play() else play_entry(setlist.entries[current]) end
  elseif cmd == "next" then
    next_song(mode=="SHOW")
  elseif cmd == "prev" then
    prev_song(false)
  elseif cmd == "stop" then
    stop_play()
  elseif cmd == "fullscreen_toggle" then
    fullscreen = not fullscreen
  else
    local n = cmd:match("^goto:(%d+)$")
    if n then goto_i(tonumber(n), mode=="SHOW") end
  end
  reaper.DeleteExtState(REMOTE_KEY, "cmd", true)
end



-- ============================================================
-- KAPITEL 6 — THEME & FONTS (SAFE MODE)
-- ============================================================

local function apply_theme()
  if theme == "Dark" then
    if reaper.ImGui_StyleColorsDark then
      local ok = pcall(reaper.ImGui_StyleColorsDark, ctx)
      if not ok then pcall(reaper.ImGui_StyleColorsDark) end
    end
  else
    if reaper.ImGui_StyleColorsLight then
      local ok = pcall(reaper.ImGui_StyleColorsLight, ctx)
      if not ok then pcall(reaper.ImGui_StyleColorsLight) end
    end
  end
  if reaper.ImGui_SetNextWindowBgAlpha then
    reaper.ImGui_SetNextWindowBgAlpha(ctx, 1.0)
  end
end
local function pop_theme() end

local function rebuild_fonts()
  if not USE_ONLY_DEFAULT_FONT then
    local sz_ui   = math.max(12, math.floor(18 * UI_SCALE))
    local sz_big  = math.max(16, math.floor(28 * UI_SCALE))
    local sz_huge = math.max(28, math.floor(54 * UI_SCALE))
    FONT_UI   = reaper.ImGui_CreateFont("sans-serif", sz_ui)
    FONT_BIG  = reaper.ImGui_CreateFont("sans-serif", sz_big)
    FONT_HUGE = reaper.ImGui_CreateFont("sans-serif", sz_huge)
    if FONT_UI   then reaper.ImGui_Attach(ctx, FONT_UI)   end
    if FONT_BIG  then reaper.ImGui_Attach(ctx, FONT_BIG)  end
    if FONT_HUGE then reaper.ImGui_Attach(ctx, FONT_HUGE) end
  end
  pcall(reaper.ImGui_BuildFontAtlas, ctx)
end



-- ============================================================
-- KAPITEL 7 — GUI: TOOLBAR, EDIT-PANEL, SHOW-PANEL
-- ============================================================

-- ---------- Toolbar ----------
local function toolbar()
  if reaper.ImGui_BeginChild(ctx, "toolbar", 0, math.floor(42*UI_SCALE), 0) then
    -- Mode
    if reaper.ImGui_Button(ctx, (mode=="EDIT" and "● " or "○ ").."Edit") then mode="EDIT" end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, (mode=="SHOW" and "● " or "○ ").."Show") then mode="SHOW" end
    reaper.ImGui_SameLine(ctx, 0, math.floor(16*UI_SCALE))

    -- Role
    if reaper.ImGui_Button(ctx, (role=="LEADER" and "★ " or "☆ ").."Leader") then role="LEADER" end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, (role=="FOLLOWER" and "★ " or "☆ ").."Follower") then role="FOLLOWER" end
    reaper.ImGui_SameLine(ctx, 0, math.floor(16*UI_SCALE))

    -- Theme
    if reaper.ImGui_Button(ctx, (theme=="Dark" and "🌙 Dark" or "🌞 Light")) then
      theme = (theme=="Dark") and "Light" or "Dark"
    end
    reaper.ImGui_SameLine(ctx, 0, math.floor(16*UI_SCALE))

    -- Fullscreen (nur Show)
    if mode=="SHOW" then
      if reaper.ImGui_Button(ctx, fullscreen and "⤢ Windowed (F)" or "⤢ Fullscreen (F)") then
        fullscreen = not fullscreen
      end
      reaper.ImGui_SameLine(ctx, 0, math.floor(16*UI_SCALE))
    end

    -- Transport
    if reaper.ImGui_Button(ctx, "⏮ Prev") then prev_song(false) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, is_playing and "⏸ Pause" or "▶ Play") then
      if is_playing then stop_play() else play_entry(setlist.entries[current]) end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "⏭ Next") then next_song(mode=="SHOW") end

    reaper.ImGui_EndChild(ctx)
  end
end

-- ---------- Edit-Panel ----------
local function panel_edit()
  local avail_w = (reaper.ImGui_GetContentRegionAvail and select(1, reaper.ImGui_GetContentRegionAvail(ctx))) or 0
  local left_w  = math.floor(avail_w * 0.50)

  -- Regions (links)
  if reaper.ImGui_BeginChild(ctx, "regions", left_w, 0, 0) then
    reaper.ImGui_Text(ctx, "Regions")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Reload") then scan_regions() end
    reaper.ImGui_Separator(ctx)

    if reaper.ImGui_BeginTable(ctx, "tbl_regions", 3,
        reaper.ImGui_TableFlags_RowBg() | reaper.ImGui_TableFlags_Resizable()) then
      reaper.ImGui_TableSetupColumn(ctx, "Idx",  reaper.ImGui_TableColumnFlags_WidthFixed(), 40)
      reaper.ImGui_TableSetupColumn(ctx, "Name")
      reaper.ImGui_TableSetupColumn(ctx, "",     reaper.ImGui_TableColumnFlags_WidthFixed(), 80)
      reaper.ImGui_TableHeadersRow(ctx)

      for i, r in ipairs(regions) do
        reaper.ImGui_TableNextRow(ctx)
        reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, tostring(r.idx))
        reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, r.name)
        reaper.ImGui_TableNextColumn(ctx)
        if reaper.ImGui_Button(ctx, "Add##"..i) then
          setlist.entries[#setlist.entries+1] = { region_idx = r.idx, continue = true, name = r.name }
          current = #setlist.entries
        end
      end
      reaper.ImGui_EndTable(ctx)
    end
    reaper.ImGui_EndChild(ctx)
  end

  reaper.ImGui_SameLine(ctx, 0, math.floor(10*UI_SCALE))

  -- Setlist (rechts)
  if reaper.ImGui_BeginChild(ctx, "setlist", 0, 0, 0) then
    reaper.ImGui_Text(ctx, "Setlist")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Save") then save_set() end
    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_BeginCombo(ctx, "Load", files[selected_set_file] or "(keine)") then
      for i, fn in ipairs(files) do
        local sel = (i == selected_set_file)
        if reaper.ImGui_Selectable(ctx, fn, sel) then
          selected_set_file = i
          load_set_by_index(i)
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Delete") and files[selected_set_file] then
      local ret = reaper.MB("Delete "..files[selected_set_file].." ?", "Delete", 4)
      if ret == 6 then delete_set_by_index(selected_set_file) end
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, " Name:")
    local changed, nm = reaper.ImGui_InputText(ctx, "##setname", setlist.name or "", 256)
    if changed then setlist.name = nm end

    reaper.ImGui_Separator(ctx)

    if reaper.ImGui_BeginTable(ctx, "tbl_setlist", 6,
        reaper.ImGui_TableFlags_RowBg() | reaper.ImGui_TableFlags_Resizable()) then
      reaper.ImGui_TableSetupColumn(ctx, "#",     reaper.ImGui_TableColumnFlags_WidthFixed(), 28)
      reaper.ImGui_TableSetupColumn(ctx, "Song")
      reaper.ImGui_TableSetupColumn(ctx, "Continue", reaper.ImGui_TableColumnFlags_WidthFixed(), 90)
      reaper.ImGui_TableSetupColumn(ctx, "Up",       reaper.ImGui_TableColumnFlags_WidthFixed(), 40)
      reaper.ImGui_TableSetupColumn(ctx, "Down",     reaper.ImGui_TableColumnFlags_WidthFixed(), 50)
      reaper.ImGui_TableSetupColumn(ctx, "Del",      reaper.ImGui_TableColumnFlags_WidthFixed(), 40)
      reaper.ImGui_TableHeadersRow(ctx)

      for i, e in ipairs(setlist.entries) do
        local r = R(e.region_idx) or R_by_name(e.name)
        if r and not e.name then e.name = r.name end

        reaper.ImGui_TableNextRow(ctx)

        reaper.ImGui_TableNextColumn(ctx)
        if reaper.ImGui_Selectable(ctx, string.format("%02d", i), i == current) then
          current = i
        end

        reaper.ImGui_TableNextColumn(ctx)
        reaper.ImGui_Text(ctx, (r and r.name) or (e.name or "<missing>"))

        reaper.ImGui_TableNextColumn(ctx)
        local cont = (e.continue ~= false)
        local _, new = reaper.ImGui_Checkbox(ctx, "##cont"..i, cont)
        if new ~= cont then e.continue = new end

        reaper.ImGui_TableNextColumn(ctx)
        if reaper.ImGui_Button(ctx, "▲##"..i) and i > 1 then
          setlist.entries[i], setlist.entries[i-1] = setlist.entries[i-1], setlist.entries[i]
          if current == i then current = i-1 elseif current == i-1 then current = i end
        end

        reaper.ImGui_TableNextColumn(ctx)
        if reaper.ImGui_Button(ctx, "▼##"..i) and i < #setlist.entries then
          setlist.entries[i], setlist.entries[i+1] = setlist.entries[i+1], setlist.entries[i]
          if current == i then current = i+1 elseif current == i+1 then current = i end
        end

        reaper.ImGui_TableNextColumn(ctx)
        if reaper.ImGui_Button(ctx, "X##"..i) then
          table.remove(setlist.entries, i)
          if current > #setlist.entries then current = #setlist.entries end
          if current < 1 then current = 1 end
        end
      end

      reaper.ImGui_EndTable(ctx)
    end

    reaper.ImGui_EndChild(ctx)
  end
end

-- ---------- Show-Panel (technisch wie Edit-Setlist, gleiche Schrift/Größe) ----------
local function panel_show()
  -- Kopf + Transport
  reaper.ImGui_Text(ctx, "Setlist: "..(setlist.name or ""))
  reaper.ImGui_Separator(ctx)

  if reaper.ImGui_Button(ctx, "⏮ Prev") then prev_song(false) end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, is_playing and "⏸ Pause" or "▶ Play") then
    if is_playing then stop_play() else play_entry(setlist.entries[current]) end
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "⏭ Next") then next_song(true) end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, fullscreen and "⤢ Windowed (F)" or "⤢ Fullscreen (F)") then
    fullscreen = not fullscreen
  end

  reaper.ImGui_Separator(ctx)

  -- **Exakt dieselbe Tabelle wie im Edit-Setlist-Panel**
  if reaper.ImGui_BeginTable(ctx, "tbl_showlist", 6,
      reaper.ImGui_TableFlags_RowBg() | reaper.ImGui_TableFlags_Resizable()) then
    reaper.ImGui_TableSetupColumn(ctx, "#",     reaper.ImGui_TableColumnFlags_WidthFixed(), 28)
    reaper.ImGui_TableSetupColumn(ctx, "Song")
    reaper.ImGui_TableSetupColumn(ctx, "Continue", reaper.ImGui_TableColumnFlags_WidthFixed(), 90)
    reaper.ImGui_TableSetupColumn(ctx, "Up",       reaper.ImGui_TableColumnFlags_WidthFixed(), 40)
    reaper.ImGui_TableSetupColumn(ctx, "Down",     reaper.ImGui_TableColumnFlags_WidthFixed(), 50)
    reaper.ImGui_TableSetupColumn(ctx, "Del",      reaper.ImGui_TableColumnFlags_WidthFixed(), 40)
    reaper.ImGui_TableHeadersRow(ctx)

    for i, e in ipairs(setlist.entries) do
      local r = R(e.region_idx) or R_by_name(e.name)
      if r and not e.name then e.name = r.name end

      reaper.ImGui_TableNextRow(ctx)

      reaper.ImGui_TableNextColumn(ctx)
      if reaper.ImGui_Selectable(ctx, string.format("%02d", i), i == current) then
        current = i
      end

      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_Text(ctx, (r and r.name) or (e.name or "<missing>"))

      reaper.ImGui_TableNextColumn(ctx)
      local cont = (e.continue ~= false)
      local _, new = reaper.ImGui_Checkbox(ctx, "##cont_show"..i, cont)
      if new ~= cont then e.continue = new end

      reaper.ImGui_TableNextColumn(ctx)
      if reaper.ImGui_Button(ctx, "▲##show"..i) and i > 1 then
        setlist.entries[i], setlist.entries[i-1] = setlist.entries[i-1], setlist.entries[i]
        if current == i then current = i-1 elseif current == i-1 then current = i end
      end

      reaper.ImGui_TableNextColumn(ctx)
      if reaper.ImGui_Button(ctx, "▼##show"..i) and i < #setlist.entries then
        setlist.entries[i], setlist.entries[i+1] = setlist.entries[i+1], setlist.entries[i]
        if current == i then current = i+1 elseif current == i+1 then current = i end
      end

      reaper.ImGui_TableNextColumn(ctx)
      if reaper.ImGui_Button(ctx, "X##show"..i) then
        table.remove(setlist.entries, i)
        if current > #setlist.entries then current = #setlist.entries end
        if current < 1 then current = 1 end
      end
    end

    reaper.ImGui_EndTable(ctx)
  end
end


-- ============================================================
-- KAPITEL 8 — HILFE- & INFO-POPUPS (inkl. ABOUT)
-- ============================================================

local function draw_help_popups()
  -- *** Start-Warnung (Haftungsausschluss) ***
  if show_warning_pending then
    local w,h = display_size()
    reaper.ImGui_SetNextWindowPos(ctx, w*0.5, h*0.5, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
    reaper.ImGui_SetNextWindowSize(ctx, math.floor(560*UI_SCALE), 0, reaper.ImGui_Cond_Appearing())
    reaper.ImGui_OpenPopup(ctx, "Live Show Warning")
    show_warning_pending = false
  end
  if reaper.ImGui_BeginPopupModal(ctx, "Live Show Warning", true) then
    reaper.ImGui_TextWrapped(ctx,
      "Haftungsausschluss:\n\n" ..
      "Dieses Script wird ohne Gewähr bereitgestellt. " ..
      "Die Nutzung in Live-Situationen erfolgt ausdrücklich auf eigene Gefahr. " ..
      "Bitte vor dem Einsatz live ausführlich testen, um unerwartetes Verhalten zu vermeiden.")
    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_Button(ctx, "OK") then reaper.ImGui_CloseCurrentPopup(ctx) end
    reaper.ImGui_EndPopup(ctx)
  end

  -- Quick Start
  if show_help_quick then
    local w,h = display_size()
    reaper.ImGui_SetNextWindowPos(ctx, w*0.5, h*0.5, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
    reaper.ImGui_SetNextWindowSize(ctx, math.floor(640*UI_SCALE), 0, reaper.ImGui_Cond_Appearing())
    reaper.ImGui_OpenPopup(ctx, "Quick Start"); show_help_quick=false
  end
  if reaper.ImGui_BeginPopupModal(ctx, "Quick Start", true) then
    reaper.ImGui_TextWrapped(ctx,
      "1) Edit-Mode: Links Regions mit 'Add' in die Setlist.\n"..
      "2) In der Setlist pro Song 'Continue' an/aus.\n"..
      "3) Show-Mode: ▶ Play startet den markierten Song. N/Next springt weiter.\n"..
      "4) Fullscreen mit F. A/B-Sync: Role Leader/Follower + gleicher Status-Pfad.")
    if reaper.ImGui_Button(ctx, "OK") then reaper.ImGui_CloseCurrentPopup(ctx) end
    reaper.ImGui_EndPopup(ctx)
  end

  -- Shortcuts
  if show_help_keys then
    local w,h = display_size()
    reaper.ImGui_SetNextWindowPos(ctx, w*0.5, h*0.5, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
    reaper.ImGui_SetNextWindowSize(ctx, math.floor(520*UI_SCALE), 0, reaper.ImGui_Cond_Appearing())
    reaper.ImGui_OpenPopup(ctx, "Shortcuts"); show_help_keys=false
  end
  if reaper.ImGui_BeginPopupModal(ctx, "Shortcuts", true) then
    reaper.ImGui_Text(ctx, "Tastatur:")
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextWrapped(ctx,
      "Space = Play/Pause\nN = Next   |  P = Prev\nE = Edit   |  H = Show\nF = Fullscreen (Show)\n1 = Leader | 2 = Follower\nS = Save   |  R = Regions neu laden")
    if reaper.ImGui_Button(ctx, "OK") then reaper.ImGui_CloseCurrentPopup(ctx) end
    reaper.ImGui_EndPopup(ctx)
  end

  -- <<< NEU: About & Support-Popup >>>
  if show_help_about then
    local w,h = display_size()
    reaper.ImGui_SetNextWindowPos(ctx, w*0.5, h*0.5, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
    reaper.ImGui_SetNextWindowSize(ctx, math.floor(640*UI_SCALE), 0, reaper.ImGui_Cond_Appearing())
    reaper.ImGui_OpenPopup(ctx, "About & Support"); show_help_about=false
  end
  if reaper.ImGui_BeginPopupModal(ctx, "About & Support", true) then
    reaper.ImGui_TextWrapped(ctx, "Setlist Manager (Regions) – Styled")
    reaper.ImGui_Text(ctx, "Version: "..VER)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextWrapped(ctx, "By Sascha Flach")
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextWrapped(ctx, "Support my Work:")
    reaper.ImGui_TextWrapped(ctx, "  Patreon: https://www.patreon.com/profile/creators?u=108528455")
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextWrapped(ctx, "Follow my Band:")
    reaper.ImGui_TextWrapped(ctx, "  Instagram: https://www.instagram.com/neonyzerband/")
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextWrapped(ctx, "Hinweis: Links können aus diesem Fenster kopiert werden (STRG+C).")
    if reaper.ImGui_Button(ctx, "OK") then reaper.ImGui_CloseCurrentPopup(ctx) end
    reaper.ImGui_EndPopup(ctx)
  end
end

-- (ENTFÄLLT) *** Info-Footer ***
-- Der Footer mit About/Support ist entfernt, damit nichts im Show-Panel „drunterhängt“.



-- ============================================================
-- KAPITEL 9 — HOTKEYS (IM FRAME)  — FIX: block while typing
-- ============================================================

local function hotkeys_in_frame()
  -- Wenn irgendein Eingabeelement aktiv ist ODER ImGui Keyboard-Capture will,
  -- dann KEINE Shortcuts verarbeiten (sonst stören sie beim Tippen).
  local io = reaper.ImGui_GetIO and reaper.ImGui_GetIO(ctx) or {}
  local wantKeyboard = (io and (io.WantCaptureKeyboard or io.WantTextInput)) and true or false
  local anyItemActive = reaper.ImGui_IsAnyItemActive and reaper.ImGui_IsAnyItemActive(ctx) or false

  -- Optional (robuster): Nur reagieren, wenn unser Fenster fokussiert ist
  local windowFocused = true
  if reaper.ImGui_IsWindowFocused then
    local flags = reaper.ImGui_FocusedFlags_RootAndChildWindows and reaper.ImGui_FocusedFlags_RootAndChildWindows() or 0
    windowFocused = reaper.ImGui_IsWindowFocused(ctx, flags)
  end

  if wantKeyboard or anyItemActive or not windowFocused then
    return
  end

  -- Shortcuts nur noch, wenn NICHT getippt wird
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then
    if is_playing then stop_play() else play_entry(setlist.entries[current]) end
  end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_N()) then next_song(mode=="SHOW") end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_P()) then prev_song(false) end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_E()) then mode="EDIT" end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_H()) then mode="SHOW" end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_F()) and mode=="SHOW" then fullscreen = not fullscreen end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_1()) then role="LEADER" end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_2()) then role="FOLLOWER" end
end




-- ============================================================
-- KAPITEL 10 — MAIN LOOP
-- ============================================================

local function main()
  local playing,_ = get_play_state()
  is_playing = playing

  -- Auto-Fullscreen beim Wechsel in SHOW
  if mode ~= prev_mode then
    if mode == "SHOW" then fullscreen = true end
    prev_mode = mode
  end

  handle_remote()

  local flags = reaper.ImGui_WindowFlags_MenuBar()
  if fullscreen and mode=="SHOW" then
    local w,h = display_size()
    reaper.ImGui_SetNextWindowPos(ctx, 0, 0, reaper.ImGui_Cond_Always())
    reaper.ImGui_SetNextWindowSize(ctx, w, h, reaper.ImGui_Cond_Always())
    flags = flags
      | reaper.ImGui_WindowFlags_NoDecoration()
      | reaper.ImGui_WindowFlags_NoMove()
      | reaper.ImGui_WindowFlags_NoResize()
  else
    reaper.ImGui_SetNextWindowSize(ctx, math.floor(1080*UI_SCALE), math.floor(720*UI_SCALE), reaper.ImGui_Cond_FirstUseEver())
  end

  apply_theme()
  local visible, open = reaper.ImGui_Begin(ctx, APP.."  "..VER.."  ["..mode.."]  Role: "..role, true, flags)
  if visible then
    -- Menubar
    if reaper.ImGui_BeginMenuBar(ctx) then
      if reaper.ImGui_BeginMenu(ctx, "File") then
        if reaper.ImGui_MenuItem(ctx, "Save") then save_set() end
        if reaper.ImGui_MenuItem(ctx, "Reload regions") then scan_regions() end
        if reaper.ImGui_MenuItem(ctx, "Refresh setlists") then refresh_files() end
        if reaper.ImGui_MenuItem(ctx, "Exit") then open=false end
        reaper.ImGui_EndMenu(ctx)
      end
      if reaper.ImGui_BeginMenu(ctx, "Settings") then
        local changed, nm = reaper.ImGui_InputText(ctx, "Setlist name", setlist.name or "", 256)
        if changed then setlist.name = nm end
        local _, sp = reaper.ImGui_InputText(ctx, "Status path (shared)", PATH_STATUS, 512)
        if sp and sp ~= PATH_STATUS then PATH_STATUS = sp end
        local _, newscale = SliderNumber("UI scale", UI_SCALE, 0.8, 2.0)
        if newscale and math.abs(newscale-UI_SCALE) > 1e-3 then
          UI_SCALE = newscale
          rebuild_fonts()
        end

        -- Repair-Button: mappt fehlende IDs anhand gespeicherter Namen
        if reaper.ImGui_Button(ctx, "Repair missing entries by name") then
          scan_regions()
          for _, e in ipairs(setlist.entries) do
            if (not R(e.region_idx)) and e.name then
              local rr = R_by_name(e.name)
              if rr then e.region_idx = rr.idx end
            end
          end
        end
        reaper.ImGui_Text(ctx, "Tipp: Pfad auf Netzwerkfreigabe setzen für A/B Sync")
        reaper.ImGui_EndMenu(ctx)
      end
      if reaper.ImGui_BeginMenu(ctx, "Help") then
        if reaper.ImGui_MenuItem(ctx, "Quick Start") then show_help_quick = true end
        if reaper.ImGui_MenuItem(ctx, "Shortcuts")  then show_help_keys  = true end
        if reaper.ImGui_MenuItem(ctx, "About & Support") then show_help_about = true end -- <<< NEU
        if reaper.ImGui_MenuItem(ctx, "Show disclaimer now") then
          -- manuell jederzeit öffnen
          show_warning_pending = true
        end
        reaper.ImGui_EndMenu(ctx)
      end
      reaper.ImGui_EndMenuBar(ctx)
    end

    -- Toolbar + Panels
    toolbar()
    if mode=="EDIT" then panel_edit() else panel_show() end
    draw_help_popups()
    hotkeys_in_frame()

    -- (Kein Info-Footer mehr)

    reaper.ImGui_End(ctx)
  end
  pop_theme()

  if not open then return end

  -- Engine + Sync
  engine()
  status_write()
  status_poll()

  reaper.defer(main)
end



-- ============================================================
-- KAPITEL 11 — INIT
-- ============================================================

ensure_dir(DIR_SET)
refresh_files()
scan_regions()
rebuild_fonts()
reaper.defer(main)

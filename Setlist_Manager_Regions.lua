-- ============================================================
--  Setlist_Manager_Regions_ImGui_Styled.lua  (SAFE MODE + REMOTE)
--  Setlist-Manager für REAPER-Regions mit hübscher GUI,
--  Light/Dark, Fullscreen, Hilfe, UI-Scale, A/B-Datei-Sync
--  Version: 2.3 (Fixes: Persistenz, Pfade, JSON, SHOW-Readonly,
--                 robustes Region-Ende, Sync-Toleranzen, UX)
-- ============================================================


--- ============================================================
-- KAPITEL 1 — REQUIREMENTS, CONFIG & GLOBAL STATE
-- ============================================================

if not reaper or not reaper.ImGui_CreateContext then
  reaper.MB("ReaImGui ist nicht installiert.\nExtensions → ReaPack → Browse → 'ReaImGui' installieren, dann REAPER neu starten.", "Setlist Manager", 0)
  return
end

local APP = "Setlist Manager (Regions) – Styled"
local VER = "2.3"  -- ↑ Version angehoben

-- Persistenz-Namespace für Settings
local EXT_NS = "SetlistMgrStyled"

-- Default-Verzeichnisse (werden nach load_settings ggf. überschrieben)
local DIR_SET_DEFAULT = reaper.GetResourcePath() .. "/Setlists"
local DIR_SET = DIR_SET_DEFAULT
local PATH_STATUS = reaper.GetResourcePath() .. "/Setlists/status.json"

-- Sync-Intervalle & Toleranzen (leicht erhöht für Netzfreigaben/AV)
local WRITE_IVL, POLL_IVL = 0.15, 0.15
local TIME_EPS = 0.08  -- ↑ stabiler bei größeren Buffern (vorher 0.03)
local UI_SCALE = 1.20

-- Safe Mode: nur Default-Font, keine StyleColor-Pushes
local USE_ONLY_DEFAULT_FONT = true

-- *** Setting: Start-Warnung anzeigen? (persistiert) ***
local SHOW_WARNING = true

local ctx = reaper.ImGui_CreateContext(APP)
local FONT_UI, FONT_BIG, FONT_HUGE  -- bleiben im Safe Mode nil
local theme = "Dark"          -- "Dark" | "Light"  (persistiert)
local mode  = "EDIT"          -- "EDIT" | "SHOW"   (Session, nicht persistiert)
local role  = "LEADER"        -- "LEADER" | "FOLLOWER" (persistiert)
local fullscreen = false       -- (persistiert)
local last_write, last_poll = 0, 0
local is_playing = false
local prev_mode = mode

local regions = {}
local setlist = { name = "My Set", entries = {} }
local files = {}
local current = 1
local selected_set_file = 1

local show_help_quick = false
local show_help_keys  = false
local show_help_about = false   -- About & Support Popup
local show_help_diag  = false   -- Diagnostics Popup

-- Popups/Info: Start-Haftungshinweis
local show_warning_pending = SHOW_WARNING
local show_info_footer = false  -- Kein Footer mehr

-- Remote/MIDI via ExtState
local REMOTE_KEY = "SetlistMgrRemote"

-- Sync/Netzwerk Diagnose
local last_remote = nil
local last_remote_received = 0
local last_read_ok = false

-- Settings-Persistenz (V2)
local SETTINGS_KEY = "SETTINGS_V2"
local settings_dirty = false
local settings_last_save = 0
local SETTINGS_SAVE_IVL = 0.5  -- mind. alle 0.5 s schreiben, wenn dirty

-- ===== NEU: Edit-Buffer für Settings-Eingaben =====
-- (Damit Eingaben nicht „zurückspringen“ und sauber übernommen werden können)
local INPUT = {
  status_path = "",   -- Bearbeitungspuffer für PATH_STATUS
  dir_set     = "",   -- Bearbeitungspuffer für DIR_SET
  set_name    = "",   -- Bearbeitungspuffer für Setlist-Namen im Settings-Menü
}
local settings_needs_apply = false  -- zeigt an, dass es ungespeicherte Änderungen gibt

-- Kleiner Helfer: UI-Fokus von Tasten nicht „wegfressen“
local function want_text_input()
  local io = reaper.ImGui_GetIO and reaper.ImGui_GetIO(ctx) or {}
  return (io and (io.WantCaptureKeyboard or io.WantTextInput)) and true or false
end

-- OS/Path Utils
local function is_windows() return reaper.GetOS():match("Win") ~= nil end
local function path_sep() return is_windows() and "\\" or "/" end
local function normalize_path(p)
  if not p or p=="" then return "" end
  if p == "/" then return "/" end
  if p:match("^%a:[/\\]$") then return p end -- "C:\" bzw. "C:/"
  -- UNC \\server\share
  if p:match("^[/\\][/\\][^/\\]+[/\\][^/\\]+[/\\]?$") then
    return (p:gsub("[/\\]+$", ""))
  end
  -- Normal: trailing Slashes entfernen, Slashes normalisieren nicht übertreiben
  return (p:gsub("[/\\]+$", ""))
end
local function path_join(a,b)
  if not a or a=="" then return b or "" end
  if not b or b=="" then return a end
  local sep = path_sep()
  a = a:gsub("[/\\]+$", "")
  b = b:gsub("^[/\\]+", "")
  return a .. sep .. b
end

-- ============================================================
-- KAPITEL 2 — HILFSFUNKTIONEN (I/O, UI, UTILS)
-- ============================================================

local function ensure_dir(p) reaper.RecursiveCreateDirectory(p, 0) end
local function readf(p) local f=io.open(p,"rb") if not f then return nil end local c=f:read("*a") f:close() return c end
local function writef(p,s)
  -- Für Status-Datei: Ordner anlegen, falls nötig
  local dir = p:match("^(.*)[/\\].-$")
  if dir and dir ~= "" then ensure_dir(dir) end
  local f=io.open(p,"wb") if not f then return false end f:write(s) f:close() return true
end
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

-- Duration-Utils
local function region_duration_sec(r)
  if not r then return 0 end
  local d = (r.fin or 0) - (r.start or 0)
  if d < 0 then d = 0 end
  return d
end

local function entry_duration_sec(e)
  if not e then return 0 end
  local r = (e.region_idx and (function() for _,rr in ipairs(regions) do if rr.idx==e.region_idx then return rr end end end)()) or nil
  r = r or ((e.name and (function()
      for _,rr in ipairs(regions) do if rr.name==e.name then return rr end end
    end)()) or nil)
  return region_duration_sec(r)
end

local function setlist_total_minutes()
  local sum = 0
  for _, e in ipairs(setlist.entries) do
    sum = sum + entry_duration_sec(e)
  end
  return (sum / 60.0), sum
end

-- ===== Robustes JSON (flat) =====
-- Encoder: escapt Komma zusätzlich als \u002C, damit Parser/Transports sicher bleiben
local function json_escape_string(s)
  s = (s or "")
      :gsub('\\','\\\\')
      :gsub('"','\\"')
      :gsub('\r','\\r')
      :gsub('\n','\\n')
      :gsub('\t','\\t')
      :gsub(',', '\\u002C') -- <— wichtig: Kommata neutralisieren
  return s
end

local function json_unescape_string(s)
  s = (s or "")
      :gsub('\\u002C', ',')
      :gsub('\\r','\r')
      :gsub('\\n','\n')
      :gsub('\\t','\t')
      :gsub('\\"','"')
      :gsub('\\\\','\\')
  return s
end

local function json_of(t)
  local parts={}
  for k,v in pairs(t) do
    if type(v)=="string" then
      parts[#parts+1] = '"'..k..'":"'..json_escape_string(v)..'"'
    elseif type(v)=="boolean" then
      parts[#parts+1] = '"'..k..'":'..(v and "true" or "false")
    elseif type(v)=="number" then
      parts[#parts+1] = '"'..k..'":'..tostring(v)
    else
      -- nil/sonst: als "null"
      parts[#parts+1] = '"'..k..'":null'
    end
  end
  return "{"..table.concat(parts,",").."}"
end

-- Einfache, aber robuste Flat-JSON-Parsing-Funktion
-- Unterstützt { "key":"value", "num":1.2, "bool":true } ohne Arrays/Nesting.
local function json_parse_flat(s)
  local i, n = 1, #s
  local function skip_ws()
    while i<=n do
      local c=s:sub(i,i)
      if c==" " or c=="\t" or c=="\r" or c=="\n" then i=i+1 else break end
    end
  end
  local function parse_string()
    -- vorausgesetzt s:sub(i,i) == '"'
    i=i+1
    local start=i
    local buf={}
    while i<=n do
      local c=s:sub(i,i)
      if c=='\\' then
        -- Escape
        buf[#buf+1]=s:sub(start,i-1)
        local nextc = s:sub(i+1,i+1)
        if nextc=="" then break end
        buf[#buf+1] = "\\"..nextc
        i = i + 2
        start = i
      elseif c=='"' then
        buf[#buf+1]=s:sub(start,i-1)
        i=i+1
        return json_unescape_string(table.concat(buf))
      else
        i=i+1
      end
    end
    return json_unescape_string(table.concat(buf))
  end
  local function parse_value()
    skip_ws()
    local c = s:sub(i,i)
    if c=='"' then
      return parse_string()
    end
    local start=i
    while i<=n do
      c = s:sub(i,i)
      if c=="," or c=="}" then break end
      i=i+1
    end
    local tok = s:sub(start,i-1):match("^%s*(.-)%s*$")
    if tok=="true" then return true end
    if tok=="false" then return false end
    if tok=="null" or tok=="" then return nil end
    local num = tonumber(tok)
    if num ~= nil then return num end
    return tok
  end

  local t={}
  skip_ws()
  if s:sub(i,i) ~= "{" then return t end
  i=i+1
  while true do
    skip_ws()
    if s:sub(i,i)=="}" then i=i+1 break end
    if s:sub(i,i)~='"' then break end
    local key = parse_string()
    skip_ws()
    if s:sub(i,i) ~= ":" then break end
    i=i+1
    local val = parse_value()
    t[key]=val
    skip_ws()
    local c=s:sub(i,i)
    if c=="," then i=i+1; goto continue end
    if c=="}" then i=i+1; break end
    ::continue::
  end
  return t
end

-- ===== Settings-Persistenz V2 =====
local function mark_settings_dirty() settings_dirty = true end

local function save_settings(force)
  local t = {
    theme = theme,
    ui_scale = UI_SCALE,
    dir_set = DIR_SET,
    path_status = PATH_STATUS,
    show_warning = SHOW_WARNING,
    role = role,
    use_only_default_font = USE_ONLY_DEFAULT_FONT,
    fullscreen = fullscreen,           -- <— persistieren
    ver = VER
  }
  local now_t = now()
  if not force and (now_t - settings_last_save) < SETTINGS_SAVE_IVL and not settings_dirty then
    return
  end
  reaper.SetExtState(EXT_NS, SETTINGS_KEY, json_of(t), true)
  -- Rückwärtskompatibel: altes Feld (nur dir) weiterpflegen
  reaper.SetExtState(EXT_NS, "SETLIST_DIR", DIR_SET or "", true)
  settings_last_save = now_t
  settings_dirty = false
end

local function load_settings()
  local raw = reaper.GetExtState(EXT_NS, SETTINGS_KEY)
  if raw and raw ~= "" then
    local t = json_parse_flat(raw)
    if t and next(t) ~= nil then
      theme = (t.theme=="Light") and "Light" or "Dark"
      UI_SCALE = tonumber(t.ui_scale or UI_SCALE) or UI_SCALE
      DIR_SET = normalize_path(t.dir_set or DIR_SET_DEFAULT)
      PATH_STATUS = t.path_status or PATH_STATUS
      SHOW_WARNING = (t.show_warning ~= false)
      role = (t.role=="FOLLOWER") and "FOLLOWER" or "LEADER"
      USE_ONLY_DEFAULT_FONT = (t.use_only_default_font ~= false)
      fullscreen = (t.fullscreen == true) -- <— laden
    end
  else
    local dir = reaper.GetExtState(EXT_NS, "SETLIST_DIR")
    if dir and dir ~= "" then DIR_SET = normalize_path(dir) else DIR_SET = DIR_SET_DEFAULT end
  end
  -- einmalig sichergehen, dass V2 geschrieben ist
  settings_dirty = true
  save_settings(true)

  -- NEU: Edit-Buffer aus Settings initialisieren
  INPUT.status_path = PATH_STATUS or ""
  INPUT.dir_set     = DIR_SET or ""
  INPUT.set_name    = setlist.name or "My Set"
  settings_needs_apply = false
end

-- Legacy-Helfer (beibehalten)
local function save_prefs()
  reaper.SetExtState(EXT_NS, "SETLIST_DIR", DIR_SET or "", true)
  mark_settings_dirty()
end

-- ===== NEU: Datei-/Ordner-Dialoge (wenn JS-ReaScript-API vorhanden) =====
local function has_js_api()
  return reaper.JS_Dialog_BrowseForSaveFile ~= nil
end

-- Wähle eine Datei (z.B. status.json); gibt Pfad oder nil zurück
local function browse_for_status_path()
  local initial = INPUT.status_path ~= "" and INPUT.status_path or (reaper.GetResourcePath() .. "/Setlists/status.json")
  local dir = initial:match("^(.*)[/\\].-$") or reaper.GetResourcePath()
  local fn  = initial:match("^.*[/\\](.-)$") or "status.json"
  if has_js_api() then
    local ok, out = reaper.JS_Dialog_BrowseForSaveFile("Choose status.json", dir, fn, "JSON (*.json)\0*.json\0All files (*.*)\0*.*\0")
    if ok and out and out ~= "" then
      if not out:lower():match("%.json$") then
        -- OS-sicher "status.json" anhängen
        out = path_join(out, "status.json")
      end
      return normalize_path(out)
    end
  else
    local ok, out = reaper.GetUserFileNameForSave(dir..path_sep()..fn, "Choose status.json", ".json")
    if ok and out and out ~= "" then return normalize_path(out) end
  end
  return nil
end

-- Wähle ein Verzeichnis (Setlists-Ordner); gibt Pfad oder nil zurück
local function browse_for_dir()
  local initial = (INPUT.dir_set ~= "" and INPUT.dir_set or (reaper.GetResourcePath().."/Setlists"))
  local dir = initial
  if has_js_api() then
    local ok, out = reaper.JS_Dialog_BrowseForSaveFile("Choose Setlists folder", dir, "", "Folder\0*\0")
    if ok and out and out ~= "" then
      local only_dir = out:match("^(.*)[/\\].-$") or out
      return normalize_path(only_dir)
    end
  else
    -- Fallback: Text-Input
    local ok, out = reaper.GetUserInputs("Setlists folder", 1, "Path:", initial)
    if ok and out and out ~= "" then return normalize_path(out) end
  end
  return nil
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

-- Case/Whitespace-toleranter Lookup
local function normalize_name(nm)
  nm = nm or ""
  nm = nm:gsub("^%s+",""):gsub("%s+$","")
  nm = nm:gsub("%s+"," ")
  return nm:lower()
end
local function R_by_name(name)
  if not name or name == "" then return nil end
  local key = normalize_name(name)
  for _, r in ipairs(regions) do
    if normalize_name(r.name) == key then return r end
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
  local path = path_join(DIR_SET, (nm:gsub("[^%w%-%._ ]","_")..".reaplaylist.txt"))
  local t = {"# "..nm}
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
  local txt = readf(path_join(DIR_SET, fn)); if not txt then return end
  local nm = fn:gsub("%.reaplaylist%.txt$","")
  local entries = {}
  for line in txt:gmatch("[^\r\n]+") do
    if not line:match("^#") and line:find(";") then
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
  os.remove(path_join(DIR_SET, files[i])); refresh_files()
end


-- ============================================================
-- KAPITEL 4 — PLAYBACK, ENGINE & A/B-SYNC
-- ============================================================

local function play_entry(e)
  if not e then return end
  local r = (R(e.region_idx) or R_by_name(e.name)); if not r then return end
  -- Cursor setzen (seekplay=true, springt live)
  reaper.SetEditCurPos(r.start, true, true)
  -- Nur starten, wenn aktuell NICHT gespielt wird (verhindert Stop/Restart-Glitches)
  local playing = select(1, get_play_state())
  if not playing then
    reaper.CSurf_OnPlay()
  end
  is_playing = true
end

local function stop_play()
  reaper.CSurf_OnStop()
  is_playing = false
end

local function goto_i(i,autoplay)
  if #setlist.entries==0 then current=1 return end
  if i<1 then i=1 elseif i>#setlist.entries then i=#setlist.entries end
  current=i
  if autoplay then play_entry(setlist.entries[current]) end
end

local function next_song(a) if #setlist.entries>0 then goto_i(current+1,a) end end
local function prev_song(a) if #setlist.entries>0 then goto_i(current-1,a) end end

-- >>> PATCH: status_build() schreibt HUD-Werte in die JSON
local function status_build()
  local e = setlist.entries[current]
  local playing, paused = get_play_state()
  local r = e and (R(e.region_idx) or R_by_name(e.name))

  -- Total / elapsed / remaining
  local total, elapsed = 0, 0
  local pos = reaper.GetPlayPosition() or 0
  for i, entry in ipairs(setlist.entries) do
    local rr = R(entry.region_idx) or R_by_name(entry.name)
    if rr then
      local dur = math.max(0, (rr.fin or 0) - (rr.start or 0))
      total = total + dur
      if i < current then
        elapsed = elapsed + dur
      elseif i == current then
        local part = math.max(0, math.min(dur, pos - (rr.start or 0)))
        elapsed = elapsed + part
      end
    end
  end
  local remaining = math.max(0, total - elapsed)
  local eta_epoch = os.time() + math.floor(remaining + 0.5)

  return {
    role=role, set=setlist.name or "", index=current, total=#setlist.entries,
    playing=playing, paused=paused,
    region_name=r and r.name or "", region_idx=r and r.idx or -1,
    status=(playing and "play") or (paused and "pause") or "stop",
    ts=now(),
    playpos = pos,

    -- >>> HUD-Felder für separates Uhr/HUD-Script:
    total_sec = total,
    remaining_sec = remaining,
    eta_epoch = eta_epoch
  }
end

local function status_write()
  if role~="LEADER" then return end
  local t=now(); if t-last_write<WRITE_IVL then return end; last_write=t
  writef(PATH_STATUS, json_of(status_build()))
end

local function status_poll()
  if role~="FOLLOWER" then return end
  local t=now(); if t-last_poll<POLL_IVL then return end; last_poll=t

  local txt = readf(PATH_STATUS)
  if not txt then last_read_ok=false; return end

  local d = json_parse_flat(txt)
  if not d then last_read_ok=false; return end

  last_read_ok = true
  last_remote = d
  last_remote_received = t

  if d.index and d.index~=current then
    goto_i(math.max(1, math.min(#setlist.entries, d.index)), d.status=="play")
  end
  if d.status=="stop" and is_playing then stop_play() end
  if d.status=="play" and not is_playing then play_entry(setlist.entries[current]) end
end

-- Stabilere End-Erkennung + Continue-Logik
local function engine()
  local e = setlist.entries[current]
  local playing = select(1, get_play_state())
  if e and playing then
    local r = R(e.region_idx) or R_by_name(e.name)
    if r then
      local pos = reaper.GetPlayPosition() or 0
      if pos >= (r.fin - TIME_EPS) then
        if e.continue ~= false then
          -- Continue EIN: direkt den nächsten Eintrag starten (falls vorhanden)
          if current < #setlist.entries then
            next_song(true)
            return
          else
            stop_play()
            return
          end
        else
          -- Continue AUS: auf den nächsten Eintrag springen, aber NICHT starten
          if current < #setlist.entries then
            goto_i(current + 1, false) -- nur selektieren
          end
          stop_play()
          return
        end
      end
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
    mark_settings_dirty()
    save_settings(true)
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

local function compute_sync_state()
  local state = { color="gray", emoji="⚪", label="No data", detail="Warte auf Leader...", latency_ms=nil, file_age=nil, ok=false }
  if role == "LEADER" then
    local age = now() - (last_write or 0)
    state.file_age = age
    state.ok = age < 2.0 -- großzügiger für Netzfreigaben
    if state.ok then
      state.color="green"; state.emoji="🟢"; state.label="Leader active"
      state.detail=string.format("Schreibe regelmäßig (%.0f ms)", (age*1000))
    else
      state.color="yellow"; state.emoji="🟡"; state.label="Leader idle"
      state.detail="Keine jüngste Änderung – ok, wenn gerade nichts passiert."
    end
    return state
  end
  if not last_read_ok or not last_remote then
    state.color="red"; state.emoji="🔴"; state.label="No signal"
    state.detail = "Kann status.json nicht lesen oder parsen"
    return state
  end
  local now_t = now()
  local age = now_t - (last_remote.ts or last_remote_received or now_t)
  state.file_age = age
  local latency = (last_remote.ts and (now_t - last_remote.ts)) or nil
  state.latency_ms = latency and (latency*1000) or nil
  local index_match = (last_remote.index == current)
  local status_match = ((last_remote.status=="play") == is_playing) or (last_remote.status=="stop" and not is_playing)
  if index_match and status_match and age < 0.9 then
    state.color="green"; state.emoji="🟢"; state.label="In Sync"; state.ok=true
    state.detail=string.format("Index=%d ok, age=%.0f ms%s", current, age*1000, latency and string.format(", ~lat=%.0f ms", state.latency_ms) or "")
  elseif age < 3.0 then
    state.color="yellow"; state.emoji="🟡"; state.label="Catching up"
    local miss = {}
    if not index_match then miss[#miss+1]="Index" end
    if not status_match then miss[#miss+1]="Status" end
    state.detail=string.format("Age=%.0f ms, Mismatch: %s%s", age*1000, (#miss>0 and table.concat(miss,"+") or "klein"), latency and string.format(", ~lat=%.0f ms", state.latency_ms) or "")
  else
    state.color="red"; state.emoji="🔴"; state.label="Stale/No signal"
    state.detail=string.format("Zu alt (%.1fs). Prüfe Netzwerk/Pfad.", age)
  end
  return state
end

local function toolbar()
  if reaper.ImGui_BeginChild(ctx, "toolbar", 0, math.floor(42*UI_SCALE), 0) then
    if reaper.ImGui_Button(ctx, (mode=="EDIT" and "● " or "○ ").."Edit") then mode="EDIT" end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, (mode=="SHOW" and "● " or "○ ").."Show") then mode="SHOW" end
    reaper.ImGui_SameLine(ctx, 0, math.floor(16*UI_SCALE))

    if reaper.ImGui_Button(ctx, (role=="LEADER" and "★ " or "☆ ").."Leader") then role="LEADER"; mark_settings_dirty(); save_settings(true) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, (role=="FOLLOWER" and "★ " or "☆ ").."Follower") then role="FOLLOWER"; mark_settings_dirty(); save_settings(true) end
    reaper.ImGui_SameLine(ctx, 0, math.floor(16*UI_SCALE))

    if reaper.ImGui_Button(ctx, (theme=="Dark" and "🌙 Dark" or "🌞 Light")) then
      theme = (theme=="Dark") and "Light" or "Dark"
      mark_settings_dirty(); save_settings(true)
    end
    reaper.ImGui_SameLine(ctx, 0, math.floor(16*UI_SCALE))

    if mode=="SHOW" then
      if reaper.ImGui_Button(ctx, fullscreen and "⤢ Windowed (F)" or "⤢ Fullscreen (F)") then
        fullscreen = not fullscreen
        mark_settings_dirty(); save_settings(true)
      end
      reaper.ImGui_SameLine(ctx, 0, math.floor(16*UI_SCALE))
    end

    if reaper.ImGui_Button(ctx, "⏮ Prev") then prev_song(false) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, is_playing and "⏸ Pause" or "▶ Play") then
      if is_playing then stop_play() else play_entry(setlist.entries[current]) end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "⏭ Next") then next_song(mode=="SHOW") end

    -- Sync-Status + breiter Tooltip
    if reaper.ImGui_GetContentRegionAvail then
      local avail_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx)) or 0
      if avail_w > 60 then
        reaper.ImGui_SameLine(ctx, 0, math.floor(16*UI_SCALE))
      end
    end
    local st = compute_sync_state()
    reaper.ImGui_Text(ctx, st.emoji.." "..st.label)

    if reaper.ImGui_IsItemHovered(ctx) then
      -- <<< Fix: Tooltip breiter & sauber umbrechend >>>
      local wrap_w = math.floor(520 * UI_SCALE)         -- Zielbreite
      if reaper.ImGui_SetNextWindowSize then
        reaper.ImGui_SetNextWindowSize(ctx, wrap_w, 0, reaper.ImGui_Cond_Appearing())
      end
      reaper.ImGui_BeginTooltip(ctx)
      if reaper.ImGui_PushTextWrapPos then
        reaper.ImGui_PushTextWrapPos(ctx, wrap_w - math.floor(24 * UI_SCALE))
      end

      reaper.ImGui_TextWrapped(ctx, st.detail)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_TextWrapped(ctx, "Rolle: "..role)
      reaper.ImGui_TextWrapped(ctx, "Pfad: "..(PATH_STATUS or "?"))

      if role=="FOLLOWER" and last_remote then
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_TextWrapped(ctx, string.format(
          "Leader:\n  Set: %s\n  Index: %s\n  Status: %s",
          tostring(last_remote.set or "?"),
          tostring(last_remote.index or "?"),
          tostring(last_remote.status or "?")
        ))
      end

      if reaper.ImGui_PopTextWrapPos then reaper.ImGui_PopTextWrapPos(ctx) end
      reaper.ImGui_EndTooltip(ctx)
    end

    reaper.ImGui_EndChild(ctx)
  end
end

-- SHOW-Mode: schreibgeschützt (Buttons/Checkboxen disabled)
local function begin_disabled_if_show()
  if mode=="SHOW" and reaper.ImGui_BeginDisabled then
    reaper.ImGui_BeginDisabled(ctx, true)
    return true
  end
  return false
end
local function end_disabled_if_show(active)
  if active and reaper.ImGui_EndDisabled then
    reaper.ImGui_EndDisabled(ctx)
  end
end

local function panel_edit()
  local avail_w = (reaper.ImGui_GetContentRegionAvail and select(1, reaper.ImGui_GetContentRegionAvail(ctx))) or 0
  local left_w  = math.floor(avail_w * 0.50)

  if reaper.ImGui_BeginChild(ctx, "regions", left_w, 0, 0) then
    reaper.ImGui_Text(ctx, "Regions")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Reload") then scan_regions() end
    reaper.ImGui_Separator(ctx)

    if reaper.ImGui_BeginTable(ctx, "tbl_regions", 4,
        reaper.ImGui_TableFlags_RowBg() | reaper.ImGui_TableFlags_Resizable()) then
      reaper.ImGui_TableSetupColumn(ctx, "Idx",  reaper.ImGui_TableColumnFlags_WidthFixed(), 40)
      reaper.ImGui_TableSetupColumn(ctx, "Name")
      reaper.ImGui_TableSetupColumn(ctx, "Len (min)", reaper.ImGui_TableColumnFlags_WidthFixed(), 90)
      reaper.ImGui_TableSetupColumn(ctx, "",     reaper.ImGui_TableColumnFlags_WidthFixed(), 80)
      reaper.ImGui_TableHeadersRow(ctx)

      for i, r in ipairs(regions) do
        local dur_min = region_duration_sec(r) / 60.0
        reaper.ImGui_TableNextRow(ctx)
        reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, tostring(r.idx))
        reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, r.name or "")
        reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, string.format("%.1f", dur_min))
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

    local total_min = setlist_total_minutes()
    reaper.ImGui_SameLine(ctx, 0, math.floor(16*UI_SCALE))
    reaper.ImGui_Text(ctx, string.format("Net playtime: %.1f min", total_min))

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

local function panel_show()
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
    mark_settings_dirty(); save_settings(true)
  end

  reaper.ImGui_Separator(ctx)

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

      -- SHOW-Mode schreibgeschützt
      local dis = begin_disabled_if_show()

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

      end_disabled_if_show(dis)
    end

    reaper.ImGui_EndTable(ctx)
  end
end


-- ============================================================
-- KAPITEL 8 — HILFE- & INFO-POPUPS
-- ============================================================

local function draw_help_popups()
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
end


-- ============================================================
-- KAPITEL 9 — HOTKEYS (IM FRAME)
-- ============================================================

local function hotkeys_in_frame()
  local io = reaper.ImGui_GetIO and reaper.ImGui_GetIO(ctx) or {}
  local wantKeyboard = (io and (io.WantCaptureKeyboard or io.WantTextInput)) and true or false
  local anyItemActive = reaper.ImGui_IsAnyItemActive and reaper.ImGui_IsAnyItemActive(ctx) or false

  local windowFocused = true
  if reaper.ImGui_IsWindowFocused then
    local flags = reaper.ImGui_FocusedFlags_RootAndChildWindows and reaper.ImGui_FocusedFlags_RootAndChildWindows() or 0
    windowFocused = reaper.ImGui_IsWindowFocused(ctx, flags)
  end

  if wantKeyboard or anyItemActive or not windowFocused then
    return
  end

  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space()) then
    if is_playing then stop_play() else play_entry(setlist.entries[current]) end
  end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_N()) then next_song(mode=="SHOW") end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_P()) then prev_song(false) end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_E()) then mode="EDIT" end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_H()) then mode="SHOW" end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_F()) and mode=="SHOW" then fullscreen = not fullscreen; mark_settings_dirty(); save_settings(true) end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_1()) then role="LEADER"; mark_settings_dirty(); save_settings(true) end
  if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_2()) then role="FOLLOWER"; mark_settings_dirty(); save_settings(true) end
end


-- ============================================================
-- KAPITEL 10 — MAIN LOOP
-- ============================================================

local function main()
  local playing,_ = get_play_state()
  is_playing = playing

  if mode ~= prev_mode then
    if mode == "SHOW" then fullscreen = true; mark_settings_dirty(); save_settings(true) end
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
    if reaper.ImGui_BeginMenuBar(ctx) then
      if reaper.ImGui_BeginMenu(ctx, "File") then
        if reaper.ImGui_MenuItem(ctx, "Save") then save_set() end
        if reaper.ImGui_MenuItem(ctx, "Reload regions") then scan_regions() end
        if reaper.ImGui_MenuItem(ctx, "Refresh setlists") then refresh_files() end
        if reaper.ImGui_MenuItem(ctx, "Exit") then open=false end
        reaper.ImGui_EndMenu(ctx)
      end
      if reaper.ImGui_BeginMenu(ctx, "Settings") then
        -- ===== Setlist-Name (Puffer, nicht sofort live) =====
        local changed_name, nm = reaper.ImGui_InputText(ctx, "Setlist name", INPUT.set_name or "", 256)
        if changed_name then INPUT.set_name = nm; settings_needs_apply = true end

        -- ===== Status-Pfad (Leader/Follower) =====
        if reaper.ImGui_InputText ~= nil then
          local changed_sp, sp = reaper.ImGui_InputText(ctx, "Status path (shared)", INPUT.status_path or "", 512)
          if changed_sp then INPUT.status_path = sp; settings_needs_apply = true end
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Browse…##status") then
          local p = browse_for_status_path()
          if p then INPUT.status_path = normalize_path(p); settings_needs_apply = true end
        end

        -- ===== Startup-Disclaimer =====
        local _, new_warn = reaper.ImGui_Checkbox(ctx, "Show startup disclaimer", SHOW_WARNING)
        if new_warn ~= SHOW_WARNING then
          SHOW_WARNING = new_warn
          mark_settings_dirty()
        end

        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Text(ctx, "Setlist storage")

        -- ===== Setlist-Ordner (Puffer) =====
        if reaper.ImGui_InputText ~= nil then
          local changed_dir, nd = reaper.ImGui_InputText(ctx, "Setlist folder", INPUT.dir_set or "", 512)
          if changed_dir then INPUT.dir_set = nd; settings_needs_apply = true end
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Browse…##dir") then
          local d = browse_for_dir()
          if d then INPUT.dir_set = normalize_path(d); settings_needs_apply = true end
        end

        if reaper.ImGui_Button(ctx, "Use default") then
          INPUT.dir_set = DIR_SET_DEFAULT
          settings_needs_apply = true
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Open in Explorer/Finder") then
          local to_open = DIR_SET or DIR_SET_DEFAULT
          if reaper.CF_ShellExecute then
            reaper.CF_ShellExecute(to_open)
          else
            local cmd = is_windows() and ('start "" "'..to_open..'"') or ('open "'..to_open..'"')
            os.execute(cmd)
          end
        end

        -- ===== UI-Scale =====
        local _, newscale = SliderNumber("UI scale", UI_SCALE, 0.8, 2.0)
        if newscale and math.abs(newscale-UI_SCALE) > 1e-3 then
          UI_SCALE = newscale
          mark_settings_dirty()
          rebuild_fonts()
        end

        -- ===== Repair-Helper =====
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

        -- ===== Apply & Save =====
        reaper.ImGui_Separator(ctx)
        if settings_needs_apply then
          reaper.ImGui_Text(ctx, "Pending changes: not applied")
        else
          reaper.ImGui_Text(ctx, "Settings are up to date")
        end

        if reaper.ImGui_Button(ctx, "Apply") then
          -- Übernehme Puffer → Live-Variablen
          if INPUT.set_name and INPUT.set_name ~= "" then
            setlist.name = INPUT.set_name
          end

          if INPUT.status_path and INPUT.status_path ~= "" and INPUT.status_path ~= PATH_STATUS then
            PATH_STATUS = INPUT.status_path
          end

          if INPUT.dir_set and INPUT.dir_set ~= "" and INPUT.dir_set ~= DIR_SET then
            DIR_SET = normalize_path(INPUT.dir_set)
            ensure_dir(DIR_SET)
            save_prefs()
            refresh_files()
          end

          mark_settings_dirty()
          save_settings(true) -- sofort sichern
          settings_needs_apply = false
        end

        reaper.ImGui_SameLine(ctx, 0, math.floor(12*UI_SCALE))
        if reaper.ImGui_Button(ctx, "Save Settings") then
          save_settings(true)
          reaper.MB("Settings saved.", "Setlist Manager", 0)
        end

        reaper.ImGui_EndMenu(ctx)
      end
      if reaper.ImGui_BeginMenu(ctx, "Help") then
        if reaper.ImGui_MenuItem(ctx, "Quick Start") then show_help_quick = true end
        if reaper.ImGui_MenuItem(ctx, "Shortcuts")  then show_help_keys  = true end
        if reaper.ImGui_MenuItem(ctx, "About & Support") then show_help_about = true end
        if reaper.ImGui_MenuItem(ctx, "Diagnostics") then show_help_diag = true end
        if reaper.ImGui_MenuItem(ctx, "Show disclaimer now") then show_warning_pending = true end
        reaper.ImGui_EndMenu(ctx)
      end
      reaper.ImGui_EndMenuBar(ctx)
    end

    toolbar()
    if mode=="EDIT" then panel_edit() else panel_show() end
    draw_help_popups()
    hotkeys_in_frame()

    reaper.ImGui_End(ctx)
  end
  pop_theme()

  if not open then
    save_settings(true)
    return
  end

  engine()
  status_write()
  status_poll()

  if settings_dirty then save_settings(false) end
  reaper.defer(main)
end



-- ============================================================
-- KAPITEL 11 — INIT
-- ============================================================

load_settings()
ensure_dir(DIR_SET)
refresh_files()
scan_regions()
rebuild_fonts()
show_warning_pending = SHOW_WARNING

-- NEU: sicherstellen, dass die Edit-Puffer aus den aktuellen Werten gefüllt sind
INPUT.status_path = PATH_STATUS or (reaper.GetResourcePath() .. "/Setlists/status.json")
INPUT.dir_set     = DIR_SET or DIR_SET_DEFAULT
INPUT.set_name    = setlist.name or "My Set"
settings_needs_apply = false

reaper.defer(main)

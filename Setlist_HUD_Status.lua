-- ============================================================
-- Setlist_HUD_Status.lua  (Auto-Fit, groß, robust, skalierbar)
-- Zeigt Gesamtspielzeit, verbleibende Zeit, ETA (Uhrzeit)
-- Liest numerische Felder: total_sec, remaining_sec, eta_epoch
-- ============================================================

if not reaper or not reaper.ImGui_CreateContext then
  reaper.MB("ReaImGui fehlt.\nReaPack → ReaImGui installieren und REAPER neu starten.", "Setlist HUD", 0)
  return
end

local APP = "Setlist HUD"
local ctx = reaper.ImGui_CreateContext(APP)

-- Persistenz
local HUD_NS = "SetlistHUD"
local HUD_SCALE = tonumber(reaper.GetExtState(HUD_NS, "scale") or "") or 2.6
local HUD_AUTOFIT = (reaper.GetExtState(HUD_NS, "autofit") == "1")
local function save_scale()  reaper.SetExtState(HUD_NS, "scale",   tostring(HUD_SCALE),  true) end
local function save_autofit()reaper.SetExtState(HUD_NS, "autofit", HUD_AUTOFIT and "1" or "0", true) end

-- Theme & Pfad aus Hauptscript-Settings
local EXT_NS, SETTINGS_KEY = "SetlistMgrStyled", "SETTINGS_V2"
local RAW = reaper.GetExtState(EXT_NS, SETTINGS_KEY) or ""
local theme = (RAW:match('%"theme"%s*:%s*%"(.-)%"') == "Light") and "Light" or "Dark"
local PATH_STATUS = (function()
  local p = RAW:match('%"path_status"%s*:%s*%"(.-)%"')
  if p and p ~= "" then return (p:gsub('\\u002C', ','):gsub('\\"','"'):gsub('\\\\','\\')) end
  return reaper.GetResourcePath() .. "/Setlists/status.json"
end)()

-- Theme anwenden (kompatibel alt/neu)
local function apply_theme()
  if theme == "Light" then
    if reaper.ImGui_StyleColorsLight then
      local ok = pcall(reaper.ImGui_StyleColorsLight, ctx); if not ok then pcall(reaper.ImGui_StyleColorsLight) end
    end
  else
    if reaper.ImGui_StyleColorsDark then
      local ok = pcall(reaper.ImGui_StyleColorsDark, ctx); if not ok then pcall(reaper.ImGui_StyleColorsDark) end
    end
  end
end

local function pretty_path(p)
  if not p or p=="" then return "" end
  return (p:gsub("\\+", "\\"):gsub("/+", "/"))
end

-- I/O + Parsing
local function readf(p) local f=io.open(p, "rb"); if not f then return nil end local c=f:read("*a"); f:close(); return c end
local function parse_fields(s)
  if not s or s=="" then return nil end
  local tot = tonumber(s:match('%"total_sec"%s*:%s*([%d%.%-]+)') or "")
  local rem = tonumber(s:match('%"remaining_sec"%s*:%s*([%d%.%-]+)') or "")
  local eta = tonumber(s:match('%"eta_epoch"%s*:%s*([%d%.%-]+)') or "")
  if tot and rem and eta then return tot, rem, eta end
  return nil
end
local function fmt_mmss(sec)
  sec = math.max(0, math.floor((sec or 0) + 0.5))
  local m = math.floor(sec / 60); local s = sec % 60
  return string.format("%d:%02d", m, s)
end

-- State
local POLL_IVL, last_poll = 0.25, 0
local total_sec, remaining_sec, eta_epoch = 0, 0, os.time()
local last_ok, show_settings = false, false

local function poll()
  local t = reaper.time_precise(); if (t - last_poll) < POLL_IVL then return end
  last_poll = t
  local s = readf(PATH_STATUS)
  if not s then last_ok=false; return end
  local tot, rem, eta = parse_fields(s)
  if tot then total_sec, remaining_sec, eta_epoch = tot, rem, eta; last_ok=true else last_ok=false end
end

-- Auto-Fit: skaliert Text an Fenstergröße (Breite + Höhe)
local function auto_fit_scale(label_w, value_w, base_line_h, lines)
  -- verfügbare Größe im Fenster
  local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
  local pad_w = 48 -- Puffer für Ränder/Spacing
  local pad_h = 80

  -- Zielbreite = Labels + Gap + Values
  local gap = 16
  local need_w = label_w + gap + value_w
  local need_h = base_line_h * lines + (lines - 1) * 6

  -- Faktor ermitteln (erst Breite, dann Höhe limitieren)
  local f_w = (win_w - pad_w) / math.max(1, need_w)
  local f_h = (win_h - pad_h) / math.max(1, need_h)
  local f = math.max(1.0, math.min(f_w, f_h))     -- nie kleiner als 1.0
  f = math.min(f, 5.0)                             -- obere Kappe
  return f
end

local function draw_settings_popup()
  if show_settings then reaper.ImGui_OpenPopup(ctx, "HUD Settings"); show_settings=false end
  if reaper.ImGui_BeginPopupModal(ctx, "HUD Settings", true) then
    local changed, newp = reaper.ImGui_InputText(ctx, "status.json path", PATH_STATUS or "", 512)
    if changed then PATH_STATUS = newp end
    if reaper.JS_Dialog_BrowseForSaveFile and reaper.ImGui_Button(ctx, "Browse…") then
      local dir = PATH_STATUS:match("^(.*)[/\\].-$") or reaper.GetResourcePath()
      local fn  = PATH_STATUS:match("^.*[/\\](.-)$") or "status.json"
      local ok, out = reaper.JS_Dialog_BrowseForSaveFile("Choose status.json", dir, fn, "JSON (*.json)\0*.json\0All files (*.*)\0*.*\0")
      if ok and out and out ~= "" then
        if not out:lower():match("%.json$") then out = out .. "/status.json" end
        PATH_STATUS = out
      end
    end
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextDisabled(ctx, "Pfad muss mit dem im Setlist-Manager übereinstimmen.")
    if reaper.ImGui_Button(ctx, "OK") then reaper.ImGui_CloseCurrentPopup(ctx) end
    reaper.ImGui_EndPopup(ctx)
  end
end

local function main()
  apply_theme()
  poll()

  -- großes Startfenster
  reaper.ImGui_SetNextWindowSize(ctx, 900, 300, reaper.ImGui_Cond_FirstUseEver())
  local flags = (reaper.ImGui_WindowFlags_MenuBar and reaper.ImGui_WindowFlags_MenuBar() or 0)
              | reaper.ImGui_WindowFlags_NoSavedSettings()
  local visible, open = reaper.ImGui_Begin(ctx, APP, true, flags)
  if visible then
    -- Menü
    if reaper.ImGui_BeginMenuBar and reaper.ImGui_BeginMenuBar(ctx) then
      if reaper.ImGui_BeginMenu(ctx, "Options") then
        if reaper.ImGui_MenuItem(ctx, "Settings…") then show_settings = true end

        local isLight = (theme=="Light"); local toggled
        toggled, isLight = reaper.ImGui_MenuItem(ctx, "Light Theme", nil, isLight)
        if toggled then theme = isLight and "Light" or "Dark" end

        reaper.ImGui_Separator(ctx)
        local _, newAutofit = reaper.ImGui_MenuItem(ctx, "Auto-Fit to window", nil, HUD_AUTOFIT)
        if newAutofit ~= HUD_AUTOFIT then HUD_AUTOFIT = newAutofit; save_autofit() end

        if not HUD_AUTOFIT then
          -- nur wenn Auto-Fit aus ist: manueller Slider
          local changed, newScale
          if reaper.ImGui_SliderDouble then
            changed, newScale = reaper.ImGui_SliderDouble(ctx, "Scale", HUD_SCALE, 1.0, 4.0, "%.2f")
          else
            changed, newScale = reaper.ImGui_SliderFloat(ctx, "Scale", HUD_SCALE, 1.0, 4.0, "%.2f")
          end
          if changed then HUD_SCALE = newScale; save_scale() end
        end
        reaper.ImGui_EndMenu(ctx)
      end
      reaper.ImGui_EndMenuBar(ctx)
    end

    -- ===== Auto-Fit berechnen =====
    local scale = HUD_SCALE
    if HUD_AUTOFIT and reaper.ImGui_SetWindowFontScale and reaper.ImGui_CalcTextSize then
      -- 1) Messung in Scale 1.0
      reaper.ImGui_SetWindowFontScale(ctx, 1.0)
      local l1 = "Gesamtspielzeit Set:"
      local l2 = "Verbleibende Spielzeit Set:"
      local l3 = "ETA Endzeit:"
      local v1 = fmt_mmss(total_sec or 0)
      local v2 = fmt_mmss(remaining_sec or 0)
      local v3 = os.date("%H:%M", (eta_epoch or os.time()))

      local lw1 = select(1, reaper.ImGui_CalcTextSize(ctx, l1))
      local lw2 = select(1, reaper.ImGui_CalcTextSize(ctx, l2))
      local lw3 = select(1, reaper.ImGui_CalcTextSize(ctx, l3))
      local vw1 = select(1, reaper.ImGui_CalcTextSize(ctx, v1))
      local vw2 = select(1, reaper.ImGui_CalcTextSize(ctx, v2))
      local vw3 = select(1, reaper.ImGui_CalcTextSize(ctx, v3))
      local label_w = math.max(lw1, math.max(lw2, lw3))
      local value_w = math.max(vw1, math.max(vw2, vw3))
      local line_h  = select(2, reaper.ImGui_CalcTextSize(ctx, "A")) + 6

      scale = auto_fit_scale(label_w, value_w, line_h, 3)
      -- 2) Scale setzen
      reaper.ImGui_SetWindowFontScale(ctx, scale)
    else
      -- manueller Scale
      if reaper.ImGui_SetWindowFontScale then reaper.ImGui_SetWindowFontScale(ctx, scale) end
    end

    -- ===== Anzeige =====
    if reaper.ImGui_BeginTable and reaper.ImGui_BeginTable(ctx, "hudtbl", 2) then
      reaper.ImGui_TableSetupColumn(ctx, "L", reaper.ImGui_TableColumnFlags_WidthFixed(), 320)
      reaper.ImGui_TableSetupColumn(ctx, "R")
      local function row(label, value)
        reaper.ImGui_TableNextRow(ctx)
        reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, label)
        reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, value)
      end
      row("Gesamtspielzeit Set:",       fmt_mmss(total_sec or 0))
      row("Verbleibende Spielzeit Set:",fmt_mmss(remaining_sec or 0))
      row("ETA Endzeit:",               os.date("%H:%M", (eta_epoch or os.time())))
      reaper.ImGui_EndTable(ctx)
    else
      -- Fallback ohne Table
      reaper.ImGui_Text(ctx, "Gesamtspielzeit Set:"); reaper.ImGui_SameLine(ctx, 0, 16); reaper.ImGui_Text(ctx, fmt_mmss(total_sec or 0))
      reaper.ImGui_Text(ctx, "Verbleibende Spielzeit Set:"); reaper.ImGui_SameLine(ctx, 0, 16); reaper.ImGui_Text(ctx, fmt_mmss(remaining_sec or 0))
      reaper.ImGui_Text(ctx, "ETA Endzeit:"); reaper.ImGui_SameLine(ctx, 0, 16); reaper.ImGui_Text(ctx, os.date("%H:%M", (eta_epoch or os.time())))
    end

    reaper.ImGui_Separator(ctx)
    if last_ok then
      reaper.ImGui_TextDisabled(ctx, pretty_path(PATH_STATUS or ""))
    else
      reaper.ImGui_TextColored(ctx, 1,0.3,0.3,1, "status.json nicht gefunden/ungültig")
      reaper.ImGui_SameLine(ctx, 0, 10)
      if reaper.ImGui_Button(ctx, "Settings…") then show_settings = true end
    end

    draw_settings_popup()
    reaper.ImGui_End(ctx)
  end

  -- Hotkeys für manuellen Modus
  if not HUD_AUTOFIT and reaper.ImGui_IsKeyDown and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl and reaper.ImGui_Mod_Ctrl() or 0) then
    if reaper.ImGui_IsKeyPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Equal and reaper.ImGui_Key_Equal() or 0) then
      HUD_SCALE = math.min(4.0, (HUD_SCALE or 2.6) + 0.1); save_scale()
    elseif reaper.ImGui_IsKeyPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Minus and reaper.ImGui_Key_Minus() or 0) then
      HUD_SCALE = math.max(1.0, (HUD_SCALE or 2.6) - 0.1); save_scale()
    end
  end

  if open then reaper.defer(main) end
end

reaper.defer(main)

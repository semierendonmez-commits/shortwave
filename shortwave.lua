-- shortwave.lua v3
-- ─────────────────────────────────────────────────────
-- all-sample shortwave radio
-- 8 granular stations loaded from a folder
-- cross-mod noise oscillators between stations
-- procedural station names
--
-- E1: fine tune
-- E2: coarse tune (sweep)
-- E3: per-page control
-- K1 hold: guide
-- K2: auto-scan / hold: stop on signal
-- K3: bookmark / K2+K3: page / K1+K3: reshuffle
--
-- v1.0.0 @semi
-- ─────────────────────────────────────────────────────

engine.name = "Shortwave"

local Names = include("shortwave/lib/names")
local fileselect = require("fileselect")

local NUM_SLOTS = 8

-- ── station state ───────────────────────────────────────
local stations = {}
for i = 1, NUM_SLOTS do
  stations[i] = {
    freq = 0,
    name = "",
    file = "",
    loaded = false,
  }
end

local tuner = 50
local sig_strength = 0
local scanning = false
local scan_dir = 1
local scan_speed = 0.12
local bookmarks = {}
local guide_held = false
local k2_held = false
local page = 1  -- 1=DIAL 2=ATMO 3=STATIONS
local sample_dir = _path.audio
local clocks = {}
local anim_t = 0

-- ── folder scanning ─────────────────────────────────────
local function scan_audio(dir)
  local files = {}
  local entries = util.scandir(dir)
  if not entries then return files end
  for _, f in ipairs(entries) do
    local ext = f:match("%.(%w+)$")
    if ext then ext = ext:lower() end
    if ext == "wav" or ext == "aif" or ext == "aiff" or ext == "flac" or ext == "ogg" then
      table.insert(files, dir .. f)
    end
  end
  return files
end

-- ── assign random files + frequencies to stations ───────
local function shuffle_stations()
  local files = scan_audio(sample_dir)
  if #files == 0 then
    print("shortwave: no audio files in " .. sample_dir)
    return
  end

  -- shuffle files
  for i = #files, 2, -1 do
    local j = math.random(i)
    files[i], files[j] = files[j], files[i]
  end

  -- assign random frequencies (can be close!)
  local freqs = {}
  for i = 1, NUM_SLOTS do
    local f = math.random(3, 97) + math.random() * 0.9
    -- allow close stations (no minimum spacing)
    table.insert(freqs, f)
  end
  table.sort(freqs)

  for i = 1, NUM_SLOTS do
    local file = files[((i - 1) % #files) + 1]
    stations[i].freq = freqs[i]
    stations[i].name = Names.generate()
    stations[i].file = file
    stations[i].loaded = false

    -- send to engine
    engine["sf" .. i](freqs[i])
    engine["load_" .. i](file)
    stations[i].loaded = true
  end
end

-- ── init ─────────────────────────────────────────────────
function init()
  params:add_separator("sw_h", "s h o r t w a v e")

  -- source folder
  params:add_separator("sw_src", "source")
  params:add_text("audio_dir", "sample folder", "audio/")

  -- tuner
  params:add_separator("sw_tune", "tuner")
  params:add_control("tuner", "frequency",
    controlspec.new(0, 100, 'lin', 0.01, 50, 'MHz'))
  params:set_action("tuner", function(v) tuner = v; engine.tuner(v) end)
  params:add_control("bw", "sharpness",
    controlspec.new(0.2, 5, 'lin', 0.05, 1.0, ''))
  params:set_action("bw", function(v) engine.bw(v) end)
  params:add_control("quality", "quality",
    controlspec.new(0, 1, 'lin', 0, 0.75, ''))
  params:set_action("quality", function(v) engine.quality(v) end)

  -- granular
  params:add_separator("sw_grain", "granular")
  params:add_control("grain_rate", "grain density",
    controlspec.new(0.1, 3, 'lin', 0, 0.7, 'x'))
  params:set_action("grain_rate", function(v) engine.grain_rate(v) end)
  params:add_control("grain_size", "grain size",
    controlspec.new(0.02, 1, 'exp', 0, 0.15, 'x'))
  params:set_action("grain_size", function(v) engine.grain_size(v) end)

  -- atmosphere
  params:add_separator("sw_atmo", "atmosphere")
  params:add_control("noise_floor", "static",
    controlspec.new(0, 0.5, 'lin', 0, 0.2, ''))
  params:set_action("noise_floor", function(v) engine.noise_floor(v) end)
  params:add_control("interf", "interference",
    controlspec.new(0, 1, 'lin', 0, 0.5, ''))
  params:set_action("interf", function(v) engine.interf(v) end)
  params:add_control("crackle_dens", "crackle rate",
    controlspec.new(0.5, 40, 'exp', 0, 8, 'Hz'))
  params:set_action("crackle_dens", function(v) engine.crackle_dens(v) end)
  params:add_control("crackle_amp", "crackle level",
    controlspec.new(0, 0.3, 'lin', 0, 0.12, ''))
  params:set_action("crackle_amp", function(v) engine.crackle_amp(v) end)

  -- cross-mod noise
  params:add_separator("sw_noise", "noise oscillators")
  params:add_control("noise_osc_a", "osc A freq",
    controlspec.new(20, 2000, 'exp', 0, 80, 'Hz'))
  params:set_action("noise_osc_a", function(v) engine.noise_osc_a(v) end)
  params:add_control("noise_osc_b", "osc B freq",
    controlspec.new(0.1, 50, 'exp', 0, 3, 'Hz'))
  params:set_action("noise_osc_b", function(v) engine.noise_osc_b(v) end)
  params:add_control("noise_xmod", "cross-mod",
    controlspec.new(0, 1, 'lin', 0, 0.5, ''))
  params:set_action("noise_xmod", function(v) engine.noise_xmod(v) end)

  -- ionosphere
  params:add_separator("sw_ion", "ionosphere")
  params:add_control("drift_rate", "drift speed",
    controlspec.new(0.001, 0.3, 'exp', 0, 0.03, 'Hz'))
  params:set_action("drift_rate", function(v) engine.drift_rate(v) end)
  params:add_control("drift_amt", "drift amount",
    controlspec.new(0, 8, 'lin', 0, 2, 'MHz'))
  params:set_action("drift_amt", function(v) engine.drift_amt(v) end)

  -- station volumes
  params:add_separator("sw_vol", "station volumes")
  for i = 1, NUM_SLOTS do
    params:add_control("sv" .. i, "station " .. i,
      controlspec.new(0, 1, 'lin', 0, 0.8, ''))
    params:set_action("sv" .. i, function(v) engine["sv" .. i](v) end)
  end

  -- hidden: station freqs (for engine sync)
  for i = 1, NUM_SLOTS do
    params:add_control("sf" .. i, "stn " .. i .. " freq",
      controlspec.new(1, 99, 'lin', 0.1, stations[i].freq or (i * 12), 'MHz'))
    params:set_action("sf" .. i, function(v)
      stations[i].freq = v; engine["sf" .. i](v)
    end)
    params:hide("sf" .. i)
  end

  params:add_control("amp", "volume",
    controlspec.new(0, 1, 'lin', 0, 0.7, ''))
  params:set_action("amp", function(v) engine.amp(v) end)

  -- polls
  local ps = poll.set("poll_sig")
  ps.callback = function(v) sig_strength = v end
  ps.time = 1/20; ps:start()
  clocks.polls = {ps}

  -- main clock
  clocks[1] = clock.run(function()
    while true do
      clock.sleep(1/15)
      anim_t = anim_t + 1
      if scanning then
        local new = tuner + scan_dir * scan_speed
        if new > 99 then new = 99; scan_dir = -1
        elseif new < 1 then new = 1; scan_dir = 1 end
        params:set("tuner", new)
      end
      redraw()
    end
  end)

  params:bang()

  -- load samples after engine is ready
  clock.run(function()
    clock.sleep(1)
    sample_dir = _path.audio .. params:get("audio_dir")
    shuffle_stations()
  end)
end

-- ── controls ─────────────────────────────────────────────
function enc(n, d)
  if n == 1 then
    params:delta("tuner", d * 0.1)
  elseif n == 2 then
    params:delta("tuner", d * 1.2)
  elseif n == 3 then
    if page == 1 then params:delta("bw", d)
    elseif page == 2 then params:delta("noise_floor", d)
    elseif page == 3 then
      local ni = find_nearest()
      if ni then params:delta("sv" .. ni, d) end
    end
  end
end

function key(n, z)
  if n == 1 then guide_held = (z == 1)
  elseif n == 2 then
    k2_held = (z == 1)
    if z == 1 then scanning = not scanning end
  elseif n == 3 and z == 1 then
    if guide_held then
      -- K1+K3: reshuffle all stations (new files + freqs + names)
      shuffle_stations()
    elseif k2_held then
      -- K2+K3: cycle page
      page = (page % 3) + 1
    else
      -- K3: select sample folder
      fileselect.enter(_path.audio, function(path)
        if path and path ~= "cancel" then
          local split = path:match("^.*()/")
          if split then
            sample_dir = path:sub(1, split)
            params:set("audio_dir", sample_dir:sub(#_path.audio + 1))
            shuffle_stations()
          end
        end
      end)
    end
  end
end

-- ── helpers ─────────────────────────────────────────────
function find_nearest()
  local min_d, ni = 999, nil
  for i = 1, NUM_SLOTS do
    local d = math.abs(tuner - stations[i].freq)
    if d < min_d then min_d = d; ni = i end
  end
  return ni, min_d
end

function get_tuned()
  local bw = params:get("bw")
  local ni, d = find_nearest()
  if ni and d < bw * 1.5 then return ni end
  return nil
end

-- ── draw ─────────────────────────────────────────────────
function redraw()
  screen.clear(); screen.aa(1)
  if guide_held then draw_guide()
  elseif page == 1 then draw_dial()
  elseif page == 2 then draw_atmo()
  elseif page == 3 then draw_stations()
  end
  screen.update()
end

function draw_dial()
  -- freq display (big)
  screen.font_size(14); screen.level(15)
  screen.move(2, 15)
  screen.text(string.format("%.2f", tuner))
  screen.font_size(8); screen.level(4)
  screen.move(62, 15); screen.text("MHz")

  if scanning then
    screen.level(math.floor(7 + math.sin(anim_t * 0.3) * 7))
    screen.move(86, 15); screen.text("SCAN")
  end

  -- dial bar
  local dy, dx, dw = 22, 4, 120
  screen.level(2); screen.rect(dx, dy, dw, 6); screen.stroke()

  -- station markers
  for i = 1, NUM_SLOTS do
    local sf = stations[i].freq
    local sx = dx + (sf / 100) * dw
    local dist = math.abs(tuner - sf)
    local bw = params:get("bw")
    local bright = math.max(1, math.floor(15 * math.exp(-(dist * dist) / (bw * bw * 2))))
    screen.level(bright)
    screen.move(sx, dy - 1); screen.line(sx, dy + 7); screen.stroke()
  end

  -- bookmarks
  for _, bm in ipairs(bookmarks) do
    screen.level(3)
    local bx = dx + (bm / 100) * dw
    screen.move(bx, dy + 8); screen.line(bx, dy + 10); screen.stroke()
  end

  -- needle
  local nx = dx + (tuner / 100) * dw
  screen.level(15); screen.rect(nx - 1, dy - 2, 3, 10); screen.fill()

  -- signal meter (14 bars)
  local my = 34
  for i = 1, 14 do
    local on = sig_strength >= (i / 14)
    screen.level(on and (i <= 5 and 5 or (i <= 10 and 10 or 15)) or 1)
    screen.rect(4 + (i - 1) * 8, my, 6, 4)
    if on then screen.fill() else screen.stroke() end
  end

  -- tuned station info (or noise visualization)
  local ti = get_tuned()
  screen.font_size(8)
  if ti then
    screen.level(12); screen.move(4, 48)
    screen.text(stations[ti].name)
    screen.level(4); screen.move(4, 56)
    screen.text(string.format("%.1f MHz", stations[ti].freq))
    -- file name hint
    local fname = stations[ti].file:match("[^/]+$") or ""
    screen.level(2); screen.move(4, 62)
    screen.text(fname:sub(1, 24))
  else
    -- static noise visualization
    screen.level(1)
    local ng = 1 - sig_strength
    for i = 1, math.floor(ng * 40 + 5) do
      screen.level(math.random(1, math.floor(ng * 8 + 2)))
      screen.pixel(math.random(4, 124), math.random(44, 60))
    end
    screen.fill()
    -- cross-mod osc hint
    if ng > 0.5 then
      screen.level(2); screen.font_size(8)
      screen.move(4, 62)
      screen.text(string.format("%.0fHz x %.1fHz", params:get("noise_osc_a"), params:get("noise_osc_b")))
    end
  end

  draw_page_dots(1)
end

function draw_atmo()
  screen.font_size(8); screen.level(8)
  screen.move(4, 12); screen.text("ATMOSPHERE")

  -- noise field animation
  local nf = params:get("noise_floor")
  local ng = 1 - sig_strength
  for i = 1, math.floor((nf * 200 + 15) * ng) do
    screen.level(math.random(1, 7))
    screen.pixel(math.random(4, 124), math.random(16, 42))
  end
  screen.fill()

  -- cross-mod osc visualization
  screen.level(4)
  local oa = params:get("noise_osc_a")
  local ob = params:get("noise_osc_b")
  local xm = params:get("noise_xmod")
  for i = 0, 40 do
    local x = 44 + i
    local ph = (anim_t * 0.03 + i * 0.08) * (oa / 200)
    local v = math.sin(ph + math.sin(ph * ob / oa * 2) * xm)
    screen.level(math.floor(3 + ng * 6))
    if i > 0 then screen.line(x, 30 + v * 6) else screen.move(x, 30 + v * 6) end
  end
  screen.stroke()

  screen.level(5); screen.font_size(8)
  screen.move(4, 50); screen.text("static:" .. string.format("%.0f%%", nf * 200))
  screen.move(56, 50); screen.text("interf:" .. string.format("%.0f%%", params:get("interf") * 100))
  screen.move(4, 58); screen.text("crackle:" .. string.format("%.1f", params:get("crackle_dens")))
  screen.move(56, 58); screen.text("quality:" .. string.format("%.0f%%", params:get("quality") * 100))
  screen.move(4, 64); screen.text("drift:" .. string.format("%.1f", params:get("drift_amt")) .. "MHz")
  screen.move(56, 64); screen.text("xmod:" .. string.format("%.0f%%", xm * 100))

  draw_page_dots(2)
end

function draw_stations()
  screen.font_size(8); screen.level(8)
  screen.move(4, 10); screen.text("STATIONS")
  screen.level(3); screen.move(60, 10); screen.text("K3:folder K1+K3:shuffle")

  for i = 1, NUM_SLOTS do
    local y = 11 + i * 6
    local dist = math.abs(tuner - stations[i].freq)
    local bw = params:get("bw")
    local tuned = dist < bw * 1.5

    screen.level(tuned and 12 or 3)
    screen.move(4, y); screen.text(string.format("%.1f", stations[i].freq))

    screen.level(tuned and 10 or 2)
    screen.move(24, y)
    screen.text(stations[i].name:sub(1, 10))

    -- vol bar
    local sv = params:get("sv" .. i)
    screen.level(1); screen.rect(72, y - 4, 38, 3); screen.stroke()
    screen.level(tuned and 10 or 3)
    screen.rect(72, y - 4, math.floor(sv * 38), 3); screen.fill()

    if tuned then
      screen.level(15); screen.circle(116, y - 2, 1.5); screen.fill()
    end
  end

  draw_page_dots(3)
end

function draw_page_dots(current)
  for i = 1, 3 do
    screen.level(i == current and 12 or 3)
    screen.rect(56 + (i - 1) * 6, 62, 3, 2); screen.fill()
  end
end

function draw_guide()
  screen.level(1); screen.rect(0, 0, 128, 64); screen.fill()
  screen.font_size(8); screen.level(15)
  screen.move(4, 10); screen.text("s h o r t w a v e")
  screen.level(7)
  screen.move(4, 22); screen.text("E1: fine tune")
  screen.move(4, 28); screen.text("E2: coarse sweep")
  screen.move(4, 34); screen.text("E3: sharpness / static / vol")
  screen.move(4, 42); screen.text("K2: auto-scan")
  screen.move(4, 48); screen.text("K3: choose folder")
  screen.move(4, 54); screen.text("K2+K3: cycle page")
  screen.move(4, 60); screen.text("K1+K3: reshuffle stations")
end

function cleanup()
  for _, id in ipairs(clocks) do if id then clock.cancel(id) end end
  if clocks.polls then for _, p in ipairs(clocks.polls) do p:stop() end end
end

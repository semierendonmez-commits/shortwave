-- shortwave.lua
-- ─────────────────────────────────────────────────────
-- a shortwave radio simulator for norns
--
-- tune through a frequency band. between stations:
-- static, crackle, heterodyne whistles.
-- each station is a different generative world.
--
-- E1: fine tune
-- E2: coarse tune (sweep the dial)
-- E3: bandwidth / volume (per page)
-- K1: hold for station guide
-- K2: auto-scan on/off
-- K3: bookmark frequency
--
-- v1.0.0 @semi
-- ─────────────────────────────────────────────────────

engine.name = "Shortwave"

-- ── stations ────────────────────────────────────────────
local STATIONS = {
  {freq = 15, name = "DRONE",   desc = "filtered noise pad"},
  {freq = 28, name = "NUMBERS", desc = "sine tone patterns"},
  {freq = 42, name = "PULSE",   desc = "rhythmic time signal"},
  {freq = 58, name = "VOICE",   desc = "formant textures"},
  {freq = 72, name = "MORSE",   desc = "keyed sine patterns"},
  {freq = 88, name = "MUSIC",   desc = "harmonic fragments"},
}

-- ── state ────────────────────────────────────────────────
local tuner       = 50    -- 0-100 MHz
local sig_strength = 0
local scanning    = false
local scan_dir    = 1
local scan_speed  = 0.3
local bookmarks   = {}
local guide_held  = false
local page        = 1     -- 1=DIAL, 2=ATMO, 3=STATIONS

local clocks = {}

-- ── init ─────────────────────────────────────────────────
function init()
  params:add_separator("sw_h", "s h o r t w a v e")

  params:add_separator("sw_tune", "tuner")
  params:add_control("tuner", "frequency",
    controlspec.new(0, 100, 'lin', 0.01, 50, 'MHz'))
  params:set_action("tuner", function(v) tuner = v; engine.tuner(v) end)

  params:add_control("bandwidth", "bandwidth",
    controlspec.new(0.5, 10, 'lin', 0.1, 3, ''))
  params:set_action("bandwidth", function(v) engine.bandwidth(v) end)

  params:add_control("quality", "signal quality",
    controlspec.new(0, 1, 'lin', 0, 0.8, ''))
  params:set_action("quality", function(v) engine.quality(v) end)

  params:add_separator("sw_atmo", "atmosphere")
  params:add_control("noise_floor", "static level",
    controlspec.new(0, 0.5, 'lin', 0, 0.15, ''))
  params:set_action("noise_floor", function(v) engine.noise_floor(v) end)

  params:add_control("interference", "interference",
    controlspec.new(0, 1, 'lin', 0, 0.3, ''))
  params:set_action("interference", function(v) engine.interference(v) end)

  params:add_control("crackle_rate", "crackle rate",
    controlspec.new(0.5, 30, 'exp', 0, 5, 'Hz'))
  params:set_action("crackle_rate", function(v) engine.crackle_rate(v) end)

  params:add_control("crackle_level", "crackle level",
    controlspec.new(0, 0.3, 'lin', 0, 0.1, ''))
  params:set_action("crackle_level", function(v) engine.crackle_level(v) end)

  params:add_separator("sw_drift", "ionosphere")
  params:add_control("drift_rate", "drift speed",
    controlspec.new(0.001, 0.2, 'exp', 0, 0.02, 'Hz'))
  params:set_action("drift_rate", function(v) engine.drift_rate(v) end)

  params:add_control("drift_amt", "drift amount",
    controlspec.new(0, 5, 'lin', 0, 1.5, 'MHz'))
  params:set_action("drift_amt", function(v) engine.drift_amt(v) end)

  params:add_separator("sw_vol", "station volumes")
  for i = 1, 6 do
    params:add_control("vol_" .. i, STATIONS[i].name .. " vol",
      controlspec.new(0, 1, 'lin', 0, 0.8, ''))
    params:set_action("vol_" .. i, function(v) engine["vol_" .. i](v) end)
  end

  params:add_separator("sw_out", "output")
  params:add_control("amp", "volume",
    controlspec.new(0, 1, 'lin', 0, 0.7, ''))
  params:set_action("amp", function(v) engine.amp(v) end)

  -- polls
  local pt = poll.set("poll_tune")
  pt.callback = function(v) end  -- tuner value comes from Lua
  pt.time = 1/15; pt:start()

  local ps = poll.set("poll_sig")
  ps.callback = function(v) sig_strength = v end
  ps.time = 1/15; ps:start()
  clocks.polls = {pt, ps}

  -- redraw
  clocks[1] = clock.run(function()
    while true do
      clock.sleep(1/15)
      -- auto-scan
      if scanning then
        local new = tuner + scan_dir * scan_speed
        if new > 100 then new = 100; scan_dir = -1
        elseif new < 0 then new = 0; scan_dir = 1 end
        params:set("tuner", new)
      end
      redraw()
    end
  end)

  params:bang()
end

-- ── controls ─────────────────────────────────────────────
function enc(n, d)
  if n == 1 then
    -- fine tune (0.05 MHz steps)
    params:delta("tuner", d * 0.2)
  elseif n == 2 then
    -- coarse tune (1 MHz steps)
    params:delta("tuner", d * 2)
  elseif n == 3 then
    if page == 1 then
      params:delta("bandwidth", d)
    elseif page == 2 then
      params:delta("noise_floor", d)
    elseif page == 3 then
      -- adjust nearest station volume
      local nearest = find_nearest_station()
      if nearest then
        params:delta("vol_" .. nearest, d)
      end
    end
  end
end

function key(n, z)
  if n == 1 then
    guide_held = (z == 1)
  elseif n == 2 and z == 1 then
    scanning = not scanning
    if scanning then scan_dir = 1 end
  elseif n == 3 and z == 1 then
    if guide_held then
      -- K1+K3: cycle pages
      page = (page % 3) + 1
    else
      -- bookmark current frequency
      table.insert(bookmarks, tuner)
      if #bookmarks > 8 then table.remove(bookmarks, 1) end
    end
  end
end

-- ── helpers ─────────────────────────────────────────────
function find_nearest_station()
  local min_dist = 999
  local nearest = nil
  for i, s in ipairs(STATIONS) do
    local d = math.abs(tuner - s.freq)
    if d < min_dist then min_dist = d; nearest = i end
  end
  return nearest, min_dist
end

function get_tuned_station()
  local bw = params:get("bandwidth")
  for i, s in ipairs(STATIONS) do
    if math.abs(tuner - s.freq) < bw then return i end
  end
  return nil
end

-- ── draw ─────────────────────────────────────────────────
function redraw()
  screen.clear()
  screen.aa(1)

  if guide_held then
    draw_guide()
  elseif page == 1 then
    draw_dial()
  elseif page == 2 then
    draw_atmo()
  elseif page == 3 then
    draw_stations()
  end

  screen.update()
end

-- ── DIAL page ───────────────────────────────────────────
function draw_dial()
  -- frequency display (big)
  screen.font_size(16)
  screen.level(15)
  screen.move(2, 16)
  screen.text(string.format("%.2f", tuner))
  screen.font_size(8)
  screen.level(6)
  screen.move(70, 16); screen.text("MHz")

  -- scanning indicator
  if scanning then
    screen.level(math.floor(8 + math.sin(os.clock() * 4) * 7))
    screen.move(90, 16); screen.text("SCAN")
  end

  -- ── dial bar ──────────────────────────────────────────
  local dy = 24
  local dx1, dx2 = 4, 124
  local dw = dx2 - dx1

  -- background
  screen.level(2)
  screen.rect(dx1, dy, dw, 8); screen.stroke()

  -- station markers on dial
  for i, s in ipairs(STATIONS) do
    local sx = dx1 + (s.freq / 100) * dw
    local tuned = math.abs(tuner - s.freq) < params:get("bandwidth")
    screen.level(tuned and 15 or 5)
    screen.move(sx, dy - 1); screen.line(sx, dy + 9); screen.stroke()
    -- station letter
    screen.level(tuned and 12 or 3)
    screen.move(sx - 1, dy - 3); screen.text(s.name:sub(1, 1))
  end

  -- bookmark markers
  for _, bm in ipairs(bookmarks) do
    local bx = dx1 + (bm / 100) * dw
    screen.level(4)
    screen.move(bx, dy + 10); screen.line(bx, dy + 12); screen.stroke()
  end

  -- tuner needle
  local nx = dx1 + (tuner / 100) * dw
  screen.level(15)
  screen.rect(nx - 1, dy - 2, 3, 12); screen.fill()

  -- ── signal strength meter ─────────────────────────────
  local my = 38
  screen.level(4); screen.font_size(8)
  screen.move(4, my + 5); screen.text("SIG")

  -- meter bars
  local num_bars = 12
  local bar_w = 8
  for i = 1, num_bars do
    local thresh = i / num_bars
    local on = sig_strength >= thresh
    if on then
      screen.level(i <= 4 and 6 or (i <= 8 and 10 or 15))
    else
      screen.level(1)
    end
    screen.rect(20 + (i - 1) * (bar_w + 1), my, bar_w, 5)
    if on then screen.fill() else screen.stroke() end
  end

  -- ── station info ──────────────────────────────────────
  local tuned = get_tuned_station()
  screen.font_size(8)
  if tuned then
    screen.level(12)
    screen.move(4, 52); screen.text(STATIONS[tuned].name)
    screen.level(5)
    screen.move(4, 60); screen.text(STATIONS[tuned].desc)
  else
    screen.level(3)
    screen.move(4, 56); screen.text("... static ...")
  end

  -- page dots
  screen.level(page == 1 and 12 or 3)
  screen.rect(58, 62, 3, 2); screen.fill()
  screen.level(3); screen.rect(63, 62, 3, 2); screen.fill()
  screen.rect(68, 62, 3, 2); screen.fill()
end

-- ── ATMOSPHERE page ─────────────────────────────────────
function draw_atmo()
  screen.font_size(8)
  screen.level(10); screen.move(4, 12); screen.text("ATMOSPHERE")

  -- noise viz (random dots)
  local noise_lvl = params:get("noise_floor")
  for i = 1, math.floor(noise_lvl * 200) do
    screen.level(math.random(1, 8))
    screen.pixel(math.random(4, 124), math.random(16, 40))
  end
  screen.fill()

  -- params display
  screen.level(6); screen.move(4, 48)
  screen.text("static: " .. string.format("%.0f%%", params:get("noise_floor") * 200))
  screen.move(4, 56)
  screen.text("crackle: " .. string.format("%.1fHz", params:get("crackle_rate")))
  screen.move(60, 56)
  screen.text("interf: " .. string.format("%.0f%%", params:get("interference") * 100))
  screen.move(4, 64)
  screen.text("drift: " .. string.format("%.1f", params:get("drift_amt")) .. "MHz")
  screen.move(50, 64)
  screen.text("quality: " .. string.format("%.0f%%", params:get("quality") * 100))

  -- page dots
  screen.level(3); screen.rect(58, 62, 3, 2); screen.fill()
  screen.level(12); screen.rect(63, 62, 3, 2); screen.fill()
  screen.level(3); screen.rect(68, 62, 3, 2); screen.fill()
end

-- ── STATIONS page ───────────────────────────────────────
function draw_stations()
  screen.font_size(8)
  screen.level(10); screen.move(4, 12); screen.text("STATIONS")

  for i, s in ipairs(STATIONS) do
    local y = 16 + i * 8
    local tuned = math.abs(tuner - s.freq) < params:get("bandwidth")
    local vol = params:get("vol_" .. i)

    screen.level(tuned and 15 or 5)
    screen.move(4, y)
    screen.text(string.format("%2d", s.freq))

    screen.level(tuned and 12 or 4)
    screen.move(20, y)
    screen.text(s.name)

    -- volume bar
    screen.level(2)
    screen.rect(60, y - 5, 40, 4); screen.stroke()
    screen.level(tuned and 10 or 5)
    screen.rect(60, y - 5, math.floor(vol * 40), 4); screen.fill()

    -- signal dot
    if tuned then
      screen.level(15)
      screen.circle(110, y - 3, 2); screen.fill()
    end
  end

  -- page dots
  screen.level(3); screen.rect(58, 62, 3, 2); screen.fill()
  screen.rect(63, 62, 3, 2); screen.fill()
  screen.level(12); screen.rect(68, 62, 3, 2); screen.fill()
end

-- ── GUIDE overlay ───────────────────────────────────────
function draw_guide()
  screen.level(2)
  screen.rect(0, 0, 128, 64); screen.fill()

  screen.font_size(8)
  screen.level(15); screen.move(4, 10)
  screen.text("s h o r t w a v e")

  screen.level(8); screen.move(4, 22)
  screen.text("E1: fine tune")
  screen.move(4, 30)
  screen.text("E2: coarse tune (sweep)")
  screen.move(4, 38)
  screen.text("E3: bandwidth / static / vol")
  screen.move(4, 46)
  screen.text("K2: auto-scan")
  screen.move(4, 54)
  screen.text("K3: bookmark")
  screen.move(4, 62)
  screen.text("K1+K3: cycle pages")
end

-- ── cleanup ─────────────────────────────────────────────
function cleanup()
  for _, id in ipairs(clocks) do if id then clock.cancel(id) end end
  if clocks.polls then for _, p in ipairs(clocks.polls) do p:stop() end end
end

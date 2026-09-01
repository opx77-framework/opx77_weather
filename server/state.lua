--- The authority: the clock, the weather schedule, and every mutation of them.

OpxWeather = OpxWeather or {}

local Config = OPX_WEATHER_CONFIG
local Clock = OpxWeather.Clock

local Authority = {}
OpxWeather.Authority = Authority

--- Server to client, broadcast or addressed. Carries a whole snapshot.
local EVENT_SYNC = "opx77:weather:sync"

--- Raised for another file in THIS resource; TriggerEvent is per-VM on the server.
local EVENT_STATE = "opx77:weather:state"

--- `Open77.time.monotonic()` answers SECONDS on both sides, whatever the API reference says.
local function nowMs()
  return math.floor(Open77.time.monotonic() * 1000)
end

local order, index = {}, {}

local function number(value, fallback)
  value = tonumber(value)
  if value == nil or value ~= value then return fallback end
  return value
end

local configured = Config.WEATHER
for position = 1, type(configured) == "table" and #configured or 0 do
  local row = configured[position]
  local name = type(row.NAME) == "string" and row.NAME or nil
  local preset = type(row.PRESET) == "string" and row.PRESET or nil
  if name == nil or preset == nil then
    Open77.log.warn(("weather row %d ignored: NAME and PRESET must be strings")
      :format(position))
  else
    local minimum = math.max(1, math.floor(number(row.MIN_SECONDS, 300)))
    local maximum = math.max(minimum, math.floor(number(row.MAX_SECONDS, minimum)))
    local definition = {
      NAME = name,
      PRESET = preset,
      WEIGHT = math.max(0, number(row.WEIGHT, 0)),
      MIN_SECONDS = minimum,
      MAX_SECONDS = maximum,
      TRANSITION_SECONDS = math.max(0, number(row.TRANSITION_SECONDS, 20)),
    }
    order[#order + 1] = definition
    index[name:lower()] = definition
    index[preset:lower()] = definition
  end
end

--- Whether the authority has anything to work with. False disables every mutation.
Authority.ready = #order > 0

--- Resolve a NAME or an engine PRESET to its row, without case.
---@param value any
---@return table|nil
function Authority.preset(value)
  if type(value) ~= "string" then return nil end
  return index[value:lower()]
end

--- The catalogue, in config order. Read-only by convention.
---@return table[]
function Authority.presets()
  return order
end

local bootSeconds = Clock.fromHms(
  (Config.START_TIME or {}).HOUR, (Config.START_TIME or {}).MINUTE,
  (Config.START_TIME or {}).SECOND) or Clock.fromHms(12, 0, 0)

local bootRate = Clock.rateFromDayLength(Config.DAY_LENGTH_MINUTES) or 8.0

local bootWeather = Authority.preset(Config.INITIAL_WEATHER) or order[1]
if Authority.ready and Authority.preset(Config.INITIAL_WEATHER) == nil then
  Open77.log.warn(("INITIAL_WEATHER '%s' is not in the table; starting on '%s'")
    :format(tostring(Config.INITIAL_WEATHER), bootWeather.NAME))
end

local state = {
  revision = 1,
  --- Bumped only when the PRESET changes, so a client can skip a redundant setWeather.
  weatherRevision = 1,
  baseSeconds = bootSeconds,
  anchorMs = 0,
  rate = bootRate,
  timeFrozen = Config.TIME_FROZEN == true,
  weather = bootWeather and bootWeather.NAME or "",
  weatherFrozen = Config.WEATHER_FROZEN == true,
  weatherChangedAtMs = 0,
  transitionSeconds = 0,
  nextRollAtMs = 0,
}
Authority.state = state

--- Which incarnation of the authority this is; a client adopts a NEW epoch outright.
local authorityEpoch = 0
local anchored = false

--- Carried fields that must be finite numbers on the way back in.
local CARRIED_NUMBERS = {
  "revision", "weatherRevision", "baseSeconds", "anchorMs", "rate",
  "weatherChangedAtMs", "transitionSeconds", "nextRollAtMs",
}

--- Hand the live state to the host: a reload keeps the sky, a restart returns it to config.
local function saveState()
  -- carrying a zero anchorMs would restart the day at the anchor on the next reload
  if not anchored then return end
  local carried = {
    PROTOCOL = OpxWeather.PROTOCOL,
    authorityEpoch = authorityEpoch,
    timeFrozen = state.timeFrozen,
    weatherFrozen = state.weatherFrozen,
    weather = state.weather,
  }
  for index = 1, #CARRIED_NUMBERS do
    local field = CARRIED_NUMBERS[index]
    carried[field] = state[field]
  end
  Open77.state.save(carried)
end

--- Adopt the previous generation's snapshot, or refuse it whole -- it is untrusted input.
---@return boolean adopted
local function restoreState()
  local carried = Open77.state.load()
  if type(carried) ~= "table" then return false end

  if carried.PROTOCOL ~= OpxWeather.PROTOCOL then
    Open77.log.warn(("carried state ignored: protocol %s is not %s")
      :format(tostring(carried.PROTOCOL), tostring(OpxWeather.PROTOCOL)))
    return false
  end

  local weather = Authority.preset(carried.weather)
  if weather == nil then
    Open77.log.warn(("carried state ignored: preset '%s' is no longer configured")
      :format(tostring(carried.weather)))
    return false
  end

  for index = 1, #CARRIED_NUMBERS do
    local field = CARRIED_NUMBERS[index]
    local value = carried[field]
    -- `value ~= value` is the NaN test: a NaN anchor freezes the clock silently
    if type(value) ~= "number" or value ~= value then
      Open77.log.warn(("carried state ignored: field '%s' is not a number"):format(field))
      return false
    end
  end
  if type(carried.authorityEpoch) ~= "number" or carried.authorityEpoch < 0 then return false end
  if carried.revision < 1 or carried.weatherRevision < 1 then return false end
  -- same ceiling as the wire: a bag outlives the build whose bound was wider
  if carried.rate <= 0 or carried.rate > Clock.MAX_RATE then return false end

  for index = 1, #CARRIED_NUMBERS do
    local field = CARRIED_NUMBERS[index]
    state[field] = carried[field]
  end
  state.baseSeconds = Clock.normalize(state.baseSeconds)
  state.weather = weather.NAME
  state.timeFrozen = carried.timeFrozen == true
  state.weatherFrozen = carried.weatherFrozen == true
  authorityEpoch = carried.authorityEpoch
  -- anchorMs is host-monotonic and process-wide, so a carried anchor is still anchored
  anchored = true
  return true
end

--- Anchor on the first real tick, never at file scope: monotonic still reads zero there.
local function ensureAnchored()
  if anchored then return end
  local atMs = nowMs()
  state.anchorMs = atMs
  state.weatherChangedAtMs = atMs
  state.nextRollAtMs = atMs + math.max(0, number(OpxWeather.INITIAL_WEATHER_SECONDS, 180)) * 1000
  authorityEpoch = math.floor(Open77.time.monotonic() * 1000000)
  anchored = true
  -- without this, a reload before the first mutation still sends the day back to noon
  saveState()
end

--- True when this generation adopted the previous one's state. Read by the boot banner.
Authority.restored = restoreState()

--- Second of day the authority is on.
---@param atMs number|nil
---@return number
function Authority.secondsNow(atMs)
  ensureAnchored()
  return Clock.at(state.baseSeconds, state.anchorMs, state.rate, state.timeFrozen, atMs or nowMs())
end

--- The whole authoritative state, as it goes on the wire.
---@param atMs number|nil
---@param reason string|nil
---@return WeatherSnapshot
function Authority.snapshot(atMs, reason)
  atMs = atMs or nowMs()
  local definition = Authority.preset(state.weather)
  local elapsedMs = math.max(0, atMs - state.weatherChangedAtMs)
  return {
    protocol = OpxWeather.PROTOCOL,
    authorityEpoch = authorityEpoch,
    revision = state.revision,
    weatherRevision = state.weatherRevision,
    secondsOfDay = Authority.secondsNow(atMs),
    rate = state.rate,
    timeFrozen = state.timeFrozen,
    weather = state.weather,
    weatherPreset = definition and definition.PRESET or "",
    weatherPriority = math.max(0, math.floor(number(OpxWeather.WEATHER_PRIORITY, 5))),
    weatherFrozen = state.weatherFrozen,
    transitionSeconds = state.transitionSeconds,
    weatherTransitionRemainingMs = math.max(0, state.transitionSeconds * 1000 - elapsedMs),
    nextRollInMs = (not state.weatherFrozen) and math.max(0, state.nextRollAtMs - atMs) or nil,
    reason = reason or "sync",
  }
end

--- Send a snapshot. `target` nil is every client.
---@param reason string|nil
---@param target integer|nil
---@param requestId integer|nil
---@return WeatherSnapshot snapshot
function Authority.publish(reason, target, requestId)
  local value = Authority.snapshot(nowMs(), reason)
  TriggerClientEvent(EVENT_SYNC, target or -1, value, requestId)
  TriggerEvent(EVENT_STATE, value)
  return value
end

--- Move the anchor to now without moving the clock, before anything changes the rate.
local function rebase(atMs)
  state.baseSeconds = Authority.secondsNow(atMs)
  state.anchorMs = atMs
end

local function commit(reason)
  state.revision = state.revision + 1
  saveState()
  return Authority.publish(reason)
end

--- Set the authoritative time of day.
---@param hour any
---@param minute any
---@param second any|nil
---@param reason string|nil
---@return WeatherTimeResult
function Authority.setTime(hour, minute, second, reason)
  local seconds = Clock.fromHms(hour, minute, second)
  if seconds == nil then return { ok = false, error = "invalid_time" } end
  ensureAnchored()
  state.baseSeconds = seconds
  state.anchorMs = nowMs()
  commit(reason or "time_set")
  local h, m, s = Clock.toHms(seconds)
  return { ok = true, hour = h, minute = m, second = s }
end

--- Hold or release the clock.
---@param frozen any  truthy freezes
---@param reason string|nil
---@return WeatherFrozenResult
function Authority.setTimeFrozen(frozen, reason)
  ensureAnchored()
  rebase(nowMs())
  state.timeFrozen = frozen == true
  commit(reason or (state.timeFrozen and "time_frozen" or "time_resumed"))
  return { ok = true, frozen = state.timeFrozen }
end

--- Change how long a day takes, in real minutes.
---@param minutes any
---@param reason string|nil
---@return WeatherDayLengthResult
function Authority.setDayLength(minutes, reason)
  local rate, failure = Clock.rateFromDayLength(minutes)
  if rate == nil then return { ok = false, error = failure } end
  ensureAnchored()
  rebase(nowMs())
  state.rate = rate
  commit(reason or "day_length_changed")
  return { ok = true, minutes = tonumber(minutes), rate = rate }
end

--- Draw this preset's next duration, at the moment it starts.
local function scheduleRoll(definition, atMs)
  state.nextRollAtMs = atMs + math.random(definition.MIN_SECONDS, definition.MAX_SECONDS) * 1000
end

--- Cross to a preset.
---@param value any                   a NAME or an engine PRESET, without case
---@param transitionSeconds any|nil   nil takes the preset's own
---@param reason string|nil
---@return WeatherSetResult
function Authority.setWeather(value, transitionSeconds, reason)
  if not Authority.ready then return { ok = false, error = "no_presets" } end
  local definition = Authority.preset(value)
  if definition == nil then return { ok = false, error = "unknown_preset" } end

  local transition = definition.TRANSITION_SECONDS
  if transitionSeconds ~= nil then
    transition = tonumber(transitionSeconds)
    if transition == nil or transition ~= transition then
      return { ok = false, error = "invalid_transition" }
    end
    if transition < 0 or transition > 300 then
      return { ok = false, error = "invalid_transition" }
    end
  end

  ensureAnchored()
  local atMs = nowMs()
  state.weather = definition.NAME
  state.weatherChangedAtMs = atMs
  state.transitionSeconds = transition
  scheduleRoll(definition, atMs)
  state.weatherRevision = state.weatherRevision + 1
  commit(reason or "weather_set")
  return {
    ok = true,
    weather = definition.NAME,
    preset = definition.PRESET,
    transitionSeconds = transition,
  }
end

--- Hold or release the SCHEDULE, not the engine's weather lock.
---@param frozen any
---@param reason string|nil
---@return WeatherFrozenResult
function Authority.setWeatherFrozen(frozen, reason)
  ensureAnchored()
  state.weatherFrozen = frozen == true
  -- releasing re-arms the countdown: an expired timer would make "resume" mean "next"
  if not state.weatherFrozen then
    local definition = Authority.preset(state.weather)
    if definition then scheduleRoll(definition, nowMs()) end
  end
  commit(reason or (state.weatherFrozen and "weather_frozen" or "weather_resumed"))
  return { ok = true, frozen = state.weatherFrozen }
end

--- Pick the next preset by weight, excluding the one already showing.
---@param roll number|nil  0..1, so a test can name a band; live callers pass nothing
---@return table|nil definition
function Authority.chooseNext(roll)
  local candidates, total, count = {}, 0, 0
  for index = 1, #order do
    local definition = order[index]
    if definition.NAME ~= state.weather and definition.WEIGHT > 0 then
      total = total + definition.WEIGHT
      count = count + 1
      candidates[count] = { definition = definition, ceiling = total }
    end
  end
  -- nothing left to roll and the last preset already showing: staying put is the answer
  if total <= 0 then return Authority.preset(state.weather) end

  roll = tonumber(roll)
  if roll == nil or roll ~= roll or roll < 0 or roll >= 1 then roll = math.random() end
  local point = roll * total
  for index = 1, count do
    local candidate = candidates[index]
    if point < candidate.ceiling then return candidate.definition end
  end
  -- floating-point tail: `point` landed exactly on the last ceiling
  return candidates[#candidates].definition
end

--- Roll now, whatever the schedule says. What the NEXT command calls.
---@param reason string|nil
---@return WeatherSetResult
function Authority.roll(reason)
  if not Authority.ready then return { ok = false, error = "no_presets" } end
  local definition = Authority.chooseNext()
  if definition == nil then return { ok = false, error = "no_presets" } end
  return Authority.setWeather(definition.NAME, nil, reason or "weather_rolled")
end

--- One scheduler slice. Answers whether it published, so the caller can skip a heartbeat.
---@param atMs number|nil
---@return boolean published
function Authority.tick(atMs)
  if not Authority.ready then return false end
  ensureAnchored()
  atMs = atMs or nowMs()
  if state.weatherFrozen or atMs < state.nextRollAtMs then return false end
  return Authority.roll("weather_scheduled").ok == true
end

--- Everything a status line needs, resolved in one place.
---@return WeatherStatus
function Authority.status()
  local hour, minute, second = Clock.toHms(Authority.secondsNow())
  local definition = Authority.preset(state.weather)
  return {
    ok = true,
    hour = hour,
    minute = minute,
    second = second,
    dayLengthMinutes = Clock.DAY_SECONDS / state.rate / 60,
    rate = state.rate,
    timeFrozen = state.timeFrozen,
    weather = state.weather,
    preset = definition and definition.PRESET or "",
    weatherFrozen = state.weatherFrozen,
    nextRollInSeconds = state.weatherFrozen and nil
      or math.max(0, math.floor((state.nextRollAtMs - nowMs()) / 1000)),
    revision = state.revision,
  }
end

--- One line of it, for a console and for a chat answer. The boot banner prints it too.
---@return string
function Authority.statusText()
  local status = Authority.status()
  return ("weather: %02d:%02d:%02d  day=%dmin%s  preset=%s%s  rev=%d%s"):format(
    status.hour, status.minute, status.second,
    math.floor(status.dayLengthMinutes + 0.5),
    status.timeFrozen and " (clock held)" or "",
    status.weather,
    status.weatherFrozen and " (schedule held)"
      or (" (next roll in %ds)"):format(status.nextRollInSeconds or 0),
    status.revision,
    Authority.ready and "" or "  DEGRADED: no usable preset in OPX_WEATHER_CONFIG.WEATHER")
end

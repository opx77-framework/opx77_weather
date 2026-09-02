--- The projection: it accepts snapshots and applies them, and decides nothing.

OpxWeather = OpxWeather or {}

local Config = OPX_WEATHER_CONFIG
local Clock = OpxWeather.Clock

local Projection = {}
OpxWeather.Projection = Projection

--- Whether the environment natives are installed in this client.
Projection.available = false

--- The last accepted snapshot, plus the local clock it was anchored against.
---@type table|nil
Projection.state = nil

--- When the last snapshot was applied, for the floor on the sync handler.
---@type integer|nil
local lastApplyMs

-- load nothing else: every function below would be a call into nil
local NATIVES = { "setWeather", "setTime", "getTime", "setWeatherFrozen", "isWeatherFrozen",
  "setTimeFrozen" }
local installed = type(Open77.environment) == "table"
for index = 1, installed and #NATIVES or 0 do
  installed = type(Open77.environment[NATIVES[index]]) == "function"
  if not installed then break end
end
if not installed then
  Open77.log.warn("environment natives unavailable; restart Cyberpunk to activate them")
  return
end
Projection.available = true

local EVENT_REQUEST = "opx77:weather:request"
local EVENT_SYNC = "opx77:weather:sync"

--- Raised locally after a snapshot is accepted; client-side events cross resources.
local EVENT_UPDATED = "opx77:weather:updated"

local SYNC = OpxWeather.SYNC
local DRIFT_TOLERANCE = SYNC.DRIFT_TOLERANCE_SECONDS or 120

local requestSequence = 0
--- id -> local ms the request left. Half of a reply's round trip is the compensation.
local requests = {}

local lastAppliedSecond = nil
local lastWeatherRevision = nil
local stopped = false

--- The scheduler clock in milliseconds; `monotonic` answers SECONDS. A non-finite reading is
--- dropped rather than propagated: a NaN would expire nothing, an infinity everything.
---@return integer
local lastMs = 0
local function nowMs()
  local read, seconds = pcall(Open77.time.monotonic)
  if read and type(seconds) == "number" and seconds == seconds and
    seconds >= 0 and seconds < math.huge then
    lastMs = math.floor(seconds * 1000)
  end
  return lastMs
end

--- Ask the authority for a snapshot.
---@return table  -- { ok = true } | { ok = false, error = "request_failed" }
function Projection.requestSync()
  local atMs = nowMs()
  for id, sentAt in pairs(requests) do
    if atMs - sentAt > (SYNC.CLIENT_SYNC_MS or 15000) * 4 then requests[id] = nil end
  end

  requestSequence = requestSequence + 1
  requests[requestSequence] = atMs
  local ok, reason = TriggerServerEvent(EVENT_REQUEST, requestSequence)
  if not ok then
    requests[requestSequence] = nil
    Open77.log.warn("sync request failed: " .. tostring(reason))
    return { ok = false, error = "request_failed" }
  end
  return { ok = true }
end

--- Everything a snapshot must carry to be worth acting on.
---@param value any
---@return boolean
local function valid(value)
  if type(value) ~= "table" then return false end
  if value.protocol ~= OpxWeather.PROTOCOL then return false end
  -- `Clock.finite` is the one magnitude test: NaN sits inside every bound, an infinity outside
  -- them, and `% 1 ~= 0` cannot see a non-integer past 2^53
  if not Clock.finite(value.authorityEpoch) or value.authorityEpoch < 0
    or value.authorityEpoch % 1 ~= 0 then
    return false
  end
  if not Clock.finite(value.revision) or value.revision < 1
    or value.revision % 1 ~= 0 then
    return false
  end
  if not Clock.finite(value.weatherRevision) or value.weatherRevision < 1
    or value.weatherRevision % 1 ~= 0 then
    return false
  end
  if not Clock.finite(value.secondsOfDay) or value.secondsOfDay < 0
    or value.secondsOfDay >= Clock.DAY_SECONDS then
    return false
  end
  -- bounded, not merely positive: past MAX_RATE every drift correction is a world jump
  if not Clock.finite(value.rate) or value.rate <= 0 or value.rate > Clock.MAX_RATE then
    return false
  end
  if type(value.timeFrozen) ~= "boolean" then return false end
  if type(value.weatherFrozen) ~= "boolean" then return false end
  if type(value.weather) ~= "string" or value.weather == "" then return false end
  if type(value.weatherPreset) ~= "string" or value.weatherPreset == "" then return false end
  if not Clock.finite(value.weatherPriority) or value.weatherPriority < 0
    or value.weatherPriority % 1 ~= 0 then
    return false
  end
  if not Clock.finite(value.transitionSeconds) or value.transitionSeconds < 0
    or value.transitionSeconds > OpxWeather.MAX_TRANSITION_SECONDS then
    return false
  end
  if not Clock.finite(value.weatherTransitionRemainingMs)
    or value.weatherTransitionRemainingMs < 0
    or value.weatherTransitionRemainingMs > OpxWeather.MAX_TRANSITION_SECONDS * 1000 then
    return false
  end
  -- nil is the answer rather than a missing field: it is absent while the schedule is frozen
  if value.nextRollInMs ~= nil
    and (not Clock.finite(value.nextRollInMs) or value.nextRollInMs < 0) then
    return false
  end
  if type(value.reason) ~= "string" then return false end
  return true
end

--- Where the clock should stand locally, projected from the accepted snapshot.
---@param atMs number|nil
---@return number|nil
local function projectedSeconds(atMs)
  local state = Projection.state
  if state == nil then return nil end
  return Clock.at(state.secondsOfDay, state.anchorLocalMs, state.rate,
    state.timeFrozen, atMs or nowMs())
end

--- Put the game clock where the authority says it is, but only past the drift tolerance.
---@param allowRewind boolean|nil  true when a mutation moved the authority
local function applyTime(allowRewind)
  local expected = projectedSeconds()
  if expected == nil then return end
  local whole = math.floor(expected)
  if lastAppliedSecond ~= nil and whole == lastAppliedSecond then return end

  -- setTime picks the NEXT occurrence: a stale packet one second behind is a full-day jump
  if lastAppliedSecond ~= nil and not allowRewind then
    if Clock.forwardDelta(whole, lastAppliedSecond) > Clock.DAY_SECONDS / 2 then return end
  end

  local live = Open77.environment.getTime()
  if type(live) == "table" then
    local liveSeconds = Clock.normalize(
      (tonumber(live.hour) or 0) * 3600 + (tonumber(live.minute) or 0) * 60
      + (tonumber(live.second) or 0))
    local target = Clock.normalize(whole)
    local drift = math.min(Clock.forwardDelta(target, liveSeconds),
      Clock.forwardDelta(liveSeconds, target))
    if drift <= DRIFT_TOLERANCE then
      -- recorded though nothing was applied: the next pass compares against this decision
      lastAppliedSecond = whole
      return
    end
  end

  local hour, minute, second = Clock.toHms(whole)
  local ok, reason = Open77.environment.setTime(hour, minute, second)
  if ok then
    lastAppliedSecond = whole
  else
    Open77.log.warn("time apply failed: " .. tostring(reason))
  end
end

--- How much of the shared transition is still to run, locally.
---@param atMs number|nil
---@return number seconds
local function remainingTransition(atMs)
  local state = Projection.state
  if state == nil then return 0 end
  return math.max(0, state.weatherTransitionEndLocalMs - (atMs or nowMs())) / 1000
end

--- Submit the accepted preset to the engine; unforced it retries while an apply is failing.
---@param force boolean|nil
---@param transitionSeconds number|nil
local function applyWeather(force, transitionSeconds)
  local state = Projection.state
  if state == nil then return end
  if not force and lastWeatherRevision == state.weatherRevision then return end

  local ok, appliedOrReason = Open77.environment.setWeather(
    state.weatherPreset,
    transitionSeconds ~= nil and transitionSeconds or remainingTransition(),
    state.weatherPriority)
  if not ok then
    Open77.log.warn("weather apply failed: " .. tostring(appliedOrReason))
    return
  end
  lastWeatherRevision = state.weatherRevision
end

--- Accept a snapshot and project it, ordered by authority epoch first and then revision.
---@param value table
---@param requestId any
---@return table  -- { ok = true } | { ok = false, error = "invalid_snapshot"|"stale" }
function Projection.apply(value, requestId)
  if not valid(value) then
    Open77.log.warn("invalid snapshot rejected")
    return { ok = false, error = "invalid_snapshot" }
  end

  local held = Projection.state
  if held ~= nil then
    if value.authorityEpoch < held.authorityEpoch then return { ok = false, error = "stale" } end
    if value.authorityEpoch == held.authorityEpoch and value.revision < held.revision then
      return { ok = false, error = "stale" }
    end
  end

  local receivedAt = nowMs()
  -- converted once: a NaN id would raise on the way back out as a table key
  local id = tonumber(requestId)
  if not Clock.finite(id) then id = nil end
  local sentAt = id ~= nil and requests[id] or nil
  local compensationMs = 0
  if sentAt ~= nil then
    compensationMs = math.min(SYNC.MAX_LATENCY_MS or 2000,
      math.max(0, receivedAt - sentAt) / 2)
    requests[id] = nil
  end

  local previousEpoch = held and held.authorityEpoch or nil
  local previousRevision = held and held.revision or nil
  local previousWeatherRevision = held and held.weatherRevision or nil

  local seconds = value.secondsOfDay
  if not value.timeFrozen then seconds = seconds + value.rate * compensationMs / 1000 end
  local transitionRemainingMs = math.max(0, value.weatherTransitionRemainingMs - compensationMs)

  Projection.state = {
    authorityEpoch = value.authorityEpoch,
    revision = value.revision,
    weatherRevision = value.weatherRevision,
    secondsOfDay = Clock.normalize(seconds),
    anchorLocalMs = receivedAt,
    rate = value.rate,
    timeFrozen = value.timeFrozen,
    weather = value.weather,
    weatherPreset = value.weatherPreset,
    weatherPriority = value.weatherPriority,
    weatherFrozen = value.weatherFrozen,
    transitionSeconds = value.transitionSeconds,
    weatherTransitionEndLocalMs = receivedAt + transitionRemainingMs,
    nextRollInMs = value.nextRollInMs,
    latencyCompensationMs = compensationMs,
    reason = value.reason,
  }

  -- taken on every apply: it stops REDengine running its vanilla cycle underneath ours
  Open77.environment.setWeatherFrozen(true)

  local epochChanged = previousEpoch ~= nil and previousEpoch ~= value.authorityEpoch
  local timeMoved = epochChanged or (previousRevision ~= nil and previousRevision ~= value.revision)
  local weatherMoved = epochChanged or previousWeatherRevision == nil
    or previousWeatherRevision ~= value.weatherRevision

  applyTime(timeMoved)
  applyWeather(weatherMoved, transitionRemainingMs / 1000)
  TriggerEvent(EVENT_UPDATED, Projection.state)

  if previousRevision == nil then
    local hour, minute, second = Clock.toHms(projectedSeconds())
    Open77.log.info(("synchronized at %02d:%02d:%02d on %s (rtt/2 %.0fms)")
      :format(hour, minute, second, tostring(value.weather), compensationMs))
  elseif epochChanged then
    Open77.log.info(("authority changed; adopted revision %d"):format(value.revision))
  end
  return { ok = true }
end

--- The authority's snapshot. Any client-side resource can raise this name, so the floor
--- below keeps a forged snapshot from latching this client off the real authority.
RegisterNetEvent(EVENT_SYNC, function(value, requestId)
  local atMs = nowMs()
  if lastApplyMs ~= nil and atMs - lastApplyMs < 100 then return end
  lastApplyMs = atMs
  Projection.apply(value, requestId)
end)

--- The command names this resource configured, lowercased. `raw` is what the player typed, so
--- matching on these follows a rename in config.lua; matching on the word "weather" would not.
local COMMAND_NAMES = {}
for _, entry in pairs(type(Config.COMMANDS) == "table" and Config.COMMANDS or {}) do
  local name = type(entry) == "table" and entry.NAME or nil
  if type(name) == "string" and name ~= "" then
    COMMAND_NAMES[#COMMAND_NAMES + 1] = name:lower()
  end
end

--- Whether an answer on the shared channel is to one of this resource's own commands.
---@param raw string
---@return boolean
local function ours(raw)
  local typed = raw:lower()
  for index = 1, #COMMAND_NAMES do
    if typed:find(COMMAND_NAMES[index], 1, true) then return true end
  end
  return false
end

--- The server's answer to a command this player typed; other resources share the event. Its
--- `message` is the player's catalogue text, so the log takes the fact instead, in English.
RegisterNetEvent("open77:command:result", function(raw, accepted)
  if type(raw) ~= "string" then return end
  if not ours(raw) then return end
  local line = ("command answered: %s (%s)")
    :format(raw, accepted and "accepted" or "refused")
  if accepted then Open77.log.info(line) else Open77.log.warn(line) end
end)

AddEventHandler("onClientResourceStart", function(name)
  if name ~= GetCurrentResourceName() then return end
  -- released first: a client reconnecting into a lock an older generation left never thaws
  Open77.environment.setTimeFrozen(false)
  Projection.requestSync()
end)

AddEventHandler("onClientResourceStop", function(name)
  if name ~= GetCurrentResourceName() then return end
  stopped = true
  -- fail OPEN: hand the world back rather than leave the player under a sky nothing drives
  Open77.environment.setTimeFrozen(false)
  Open77.environment.setWeatherFrozen(false)
end)

--- Keep the engine's own weather lock on, and re-submit the accepted preset under it.
local function enforce()
  if Projection.state == nil then return end
  -- a lock gone false means something else took the sky
  local frozen = Open77.environment.isWeatherFrozen()
  if frozen ~= true then
    local ok, reason = Open77.environment.setWeatherFrozen(true)
    if not ok then Open77.log.warn("weather lock restore failed: " .. tostring(reason)) end
    if remainingTransition() <= 0 then applyWeather(true, 0) end
  end
  -- unforced: a no-op once the revision has been applied, a retry while it has not
  applyWeather(false)
end

local guarded = OpxWeather.guarded

CreateThread(function()
  while not stopped do
    Wait(SYNC.APPLY_MS or 500)
    guarded("time", applyTime, false)
  end
end)

CreateThread(function()
  while not stopped do
    Wait(SYNC.CLIENT_SYNC_MS or 15000)
    guarded("sync", Projection.requestSync)
  end
end)

CreateThread(function()
  while not stopped do
    Wait(SYNC.ENFORCE_MS or 5000)
    guarded("enforce", enforce)
  end
end)

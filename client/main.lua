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
if type(Open77.environment) ~= "table"
  or type(Open77.environment.setWeather) ~= "function"
  or type(Open77.environment.setTime) ~= "function" then
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

local function nowMs()
  return math.floor(Open77.time.monotonic() * 1000)
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
  if type(value.authorityEpoch) ~= "number" or value.authorityEpoch < 0 then return false end
  -- `% 1 ~= 0` does not bite past 2^53: 1e300 % 1 is exactly 0, and such a
  -- revision reaches a `%d` further down, which raises. A counter never gets
  -- near this, so an upper bound is the honest test.
  if type(value.revision) ~= "number" or value.revision < 1 or
    value.revision > 2 ^ 53 or value.revision % 1 ~= 0 then
    return false
  end
  if type(value.weatherRevision) ~= "number" or value.weatherRevision < 1 or
    value.weatherRevision > 2 ^ 53 then
    return false
  end
  if type(value.secondsOfDay) ~= "number" or value.secondsOfDay ~= value.secondsOfDay then
    return false
  end
  -- bounded, not merely positive: past MAX_RATE every drift correction is a world jump
  if type(value.rate) ~= "number" or value.rate ~= value.rate then return false end
  if value.rate <= 0 or value.rate > Clock.MAX_RATE then return false end
  if type(value.timeFrozen) ~= "boolean" then return false end
  if type(value.weatherPreset) ~= "string" or value.weatherPreset == "" then return false end
  if type(value.weatherPriority) ~= "number" or value.weatherPriority < 0 then return false end
  if type(value.transitionSeconds) ~= "number" or value.transitionSeconds < 0
    or value.transitionSeconds > 300 then
    return false
  end
  if type(value.weatherTransitionRemainingMs) ~= "number"
    or value.weatherTransitionRemainingMs < 0
    or value.weatherTransitionRemainingMs > 300000 then
    return false
  end
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
  local sentAt = requests[tonumber(requestId) or -1]
  local compensationMs = 0
  if sentAt ~= nil then
    compensationMs = math.min(SYNC.MAX_LATENCY_MS or 2000,
      math.max(0, receivedAt - sentAt) / 2)
    requests[tonumber(requestId)] = nil
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
    weatherFrozen = value.weatherFrozen == true,
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

--- The authority's snapshot.
---
--- The client runtime has a cross-resource event bus, so any resource on the
--- player's machine can raise this name. It cannot forge the weather for anyone
--- else -- the server tells every client directly -- but it CAN latch this one
--- off the real authority by claiming a higher epoch, after which the genuine
--- snapshots are refused as stale. Floored so a forgery has to win a race
--- against the server's own message rather than run in a loop nobody outruns.
RegisterNetEvent(EVENT_SYNC, function(value, requestId)
  local atMs = math.floor(Open77.time.monotonic() * 1000)
  if lastApplyMs ~= nil and atMs - lastApplyMs < 100 then return end
  lastApplyMs = atMs
  Projection.apply(value, requestId)
end)

--- The server's answer to a command this player typed; other resources share the event.
RegisterNetEvent("open77:command:result", function(raw, accepted, message)
  if type(raw) ~= "string" then return end
  if not raw:lower():find("weather", 1, true) then return end
  if accepted then Open77.log.info(tostring(message)) else Open77.log.warn(tostring(message)) end
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

CreateThread(function()
  while not stopped do
    Wait(SYNC.APPLY_MS or 500)
    applyTime(false)
  end
end)

CreateThread(function()
  while not stopped do
    Wait(SYNC.CLIENT_SYNC_MS or 15000)
    Projection.requestSync()
  end
end)

CreateThread(function()
  while not stopped do
    Wait(SYNC.ENFORCE_MS or 5000)
    if Projection.state ~= nil then
      -- a lock gone false is evidence something took the sky; re-submitting blind costs props
      local frozen = Open77.environment.isWeatherFrozen()
      if frozen ~= true then
        local ok, reason = Open77.environment.setWeatherFrozen(true)
        if not ok then Open77.log.warn("weather lock restore failed: " .. tostring(reason)) end
        if remainingTransition() <= 0 then applyWeather(true, 0) end
      end
      -- unforced: a no-op once the revision has been applied, a retry while it has not
      applyWeather(false)
    end
  end
end)

--- The shared surface: the wire constants, clock arithmetic and the loop guard, so both
--- halves run the same code.

OpxWeather = OpxWeather or {}

--- Wire version and cadence, shared so the two halves cannot disagree. Not operator dials.
OpxWeather.PROTOCOL = 1
OpxWeather.SYNC = {
  HEARTBEAT_MS = 5000, -- how often the authority republishes even when nothing changed
  CLIENT_SYNC_MS = 15000, -- how often a client asks for a fresh timestamp
  APPLY_MS = 500, -- how often the client re-derives the time of day it should be showing
  ENFORCE_MS = 5000, -- how often the client checks that nothing local stole the weather
  SCHEDULER_MS = 1000, -- how often the authority looks at whether a roll is due
  DRIFT_TOLERANCE_SECONDS = 120, -- game seconds of drift before the client corrects
  MAX_LATENCY_MS = 2000, -- ceiling on the half-round-trip added to a received timestamp
  MIN_REQUEST_MS = 1000, -- floor between two sync requests from the same player
}

--- How long the boot preset holds before the first roll, and the priority setWeather uses.
OpxWeather.INITIAL_WEATHER_SECONDS = 180
OpxWeather.WEATHER_PRIORITY = 5

--- The longest crossfade either half accepts, so a configured row cannot be refused on the wire.
OpxWeather.MAX_TRANSITION_SECONDS = 300

--- Run one loop slice. A raise from a host call in a bare `CreateThread` ends that loop for
--- the session, so every slice in this resource runs inside this.
---@param label string  what the log calls the loop
---@param fn fun(...)
---@param ... any  passed on to `fn`
function OpxWeather.guarded(label, fn, ...)
  local ok, failure = pcall(fn, ...)
  if not ok then
    Open77.log.warn(("%s slice failed: %s"):format(label, tostring(failure)))
  end
end

--- Host-monotonic milliseconds; `Open77.time.monotonic` answers SECONDS. A failed or
--- non-finite reading holds the last one: a NaN would expire nothing, an infinity everything.
---@return integer
local lastMs = 0
function OpxWeather.nowMs()
  local read, seconds = pcall(Open77.time.monotonic)
  if read and type(seconds) == "number" and seconds == seconds and
    seconds >= 0 and seconds < math.huge then
    lastMs = math.floor(seconds * 1000)
  end
  return lastMs
end


local Clock = {}
OpxWeather.Clock = Clock

local DAY_SECONDS = 24 * 60 * 60
Clock.DAY_SECONDS = DAY_SECONDS

--- The widest magnitude a carried or wire number may hold: past it `%d` has no integer form.
Clock.MAX_MAGNITUDE = 2 ^ 53

--- True for a real number within `Clock.MAX_MAGNITUDE`. NaN and an infinity are both false.
---@param value any
---@return boolean
function Clock.finite(value)
  return type(value) == "number" and value == value
    and value >= -Clock.MAX_MAGNITUDE and value <= Clock.MAX_MAGNITUDE
end

--- Fold any second-of-day onto 0..86399, negatives included.
---@param seconds any
---@return number
function Clock.normalize(seconds)
  seconds = tonumber(seconds)
  -- NaN and an infinity both fold to NaN, which raises the moment a `%d` reaches it
  if not Clock.finite(seconds) then return 0 end
  return ((seconds % DAY_SECONDS) + DAY_SECONDS) % DAY_SECONDS
end

--- Whole seconds since midnight, or nil for a time that does not exist.
---@param hour any
---@param minute any
---@param second any|nil
---@return number|nil, string|nil  -- nil, "invalid_time"
function Clock.fromHms(hour, minute, second)
  hour, minute, second = tonumber(hour), tonumber(minute), tonumber(second or 0)
  if hour == nil or minute == nil or second == nil then return nil, "invalid_time" end
  if hour % 1 ~= 0 or minute % 1 ~= 0 or second % 1 ~= 0 then return nil, "invalid_time" end
  if hour < 0 or hour > 23 then return nil, "invalid_time" end
  if minute < 0 or minute > 59 then return nil, "invalid_time" end
  if second < 0 or second > 59 then return nil, "invalid_time" end
  return hour * 3600 + minute * 60 + second
end

---@param seconds number
---@return integer hour, integer minute, integer second
function Clock.toHms(seconds)
  local whole = math.floor(Clock.normalize(seconds))
  return math.floor(whole / 3600), math.floor((whole % 3600) / 60), whole % 60
end

--- Parse "HH:MM" or "HH:MM:SS"; a trailing suffix such as `12:30pm` is refused.
---@param text any
---@return number|nil, string|nil  -- nil, "invalid_time"
function Clock.parse(text)
  if type(text) ~= "string" then return nil, "invalid_time" end
  local hour, minute, second = string.match(text, "^(%d%d?):(%d%d):?(%d*)$")
  if hour == nil then return nil, "invalid_time" end
  return Clock.fromHms(hour, minute, second ~= "" and second or 0)
end

--- Where the clock stands now, given where it stood at `anchorMs`.
---@param baseSeconds number  second-of-day at the anchor
---@param anchorMs number     host-monotonic milliseconds
---@param rate number         game seconds per real second
---@param frozen boolean      a frozen clock does not advance
---@param nowMs number
---@return number
function Clock.at(baseSeconds, anchorMs, rate, frozen, nowMs)
  local elapsed = frozen and 0 or math.max(0, (nowMs - anchorMs) / 1000)
  return Clock.normalize(baseSeconds + elapsed * rate)
end

--- Forward distance from `origin` to `target` on a 24-hour dial, so midnight is one step.
---@param target number
---@param origin number
---@return number
function Clock.forwardDelta(target, origin)
  return Clock.normalize(target - origin)
end

--- The fastest clock a client can be asked to follow, in game seconds per real second.
Clock.MAX_RATE = 120.0

--- Game seconds per real second, from a day length in real minutes.
---@param minutes any
---@return number|nil, string|nil  -- nil, "invalid_day_length"|"day_too_short"
function Clock.rateFromDayLength(minutes)
  minutes = tonumber(minutes)
  if not Clock.finite(minutes) then return nil, "invalid_day_length" end
  if minutes < 1 or minutes > 10080 then return nil, "invalid_day_length" end
  local rate = DAY_SECONDS / (minutes * 60)
  -- bounded: past MAX_RATE a client corrects for drift continuously and the world jumps
  if rate > Clock.MAX_RATE then return nil, "day_too_short" end
  return rate
end

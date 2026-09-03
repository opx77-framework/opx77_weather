--- The resource's public exports. Read-only.

local Clock = OpxWeather.Clock
local Projection = OpxWeather.Projection

--- The synchronized time and weather, projected to the instant of the call.
---@return WeatherStateResponse  -- ok = false before the first snapshot, or without natives
exports("state", function()
  if not Projection.available then
    return { ok = false, error = "environment_unavailable" }
  end
  local state = Projection.state
  if state == nil then return { ok = false, error = "not_synchronized" } end

  local seconds = Clock.at(state.secondsOfDay, state.anchorLocalMs, state.rate,
    state.timeFrozen, OpxWeather.nowMs())
  local hour, minute, second = Clock.toHms(seconds)
  return {
    ok = true,
    hour = hour,
    minute = minute,
    second = second,
    secondsOfDay = seconds,
    weather = state.weather,
    weatherPreset = state.weatherPreset,
    timeFrozen = state.timeFrozen,
    weatherFrozen = state.weatherFrozen,
    revision = state.revision,
    weatherRevision = state.weatherRevision,
    latencyCompensationMs = state.latencyCompensationMs,
  }
end)

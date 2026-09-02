--- The wiring: the one inbound event, the scheduler loop, and the boot banner.

local Authority = OpxWeather.Authority
local Clock = OpxWeather.Clock

--- The only inbound event; clients can ask for a snapshot but never mutate.
local EVENT_REQUEST = "opx77:weather:request"

local SYNC = OpxWeather.SYNC

local function nowMs()
  return math.floor(Open77.time.monotonic() * 1000)
end

--- Last request per player, for the floor between two of them. Keyed by session playerId.
local lastRequestMs = {}

RegisterNetEvent(EVENT_REQUEST, function(requestId)
  -- `source` comes from the authenticated connection, never the payload
  local player = tonumber(source) or 0
  if player <= 0 then return end

  requestId = tonumber(requestId)
  if requestId == nil or requestId ~= requestId or requestId < 1 or requestId % 1 ~= 0 then
    return
  end

  local atMs = nowMs()
  local previous = lastRequestMs[player]
  if previous ~= nil and atMs - previous < (SYNC.MIN_REQUEST_MS or 1000) then return end
  lastRequestMs[player] = atMs

  Authority.publish("request", player, requestId)
end)

--- The only departure event the host raises, so the only place `lastRequestMs` is pruned.
AddEventHandler("onPlayerDisconnected", function(playerId)
  lastRequestMs[tonumber(playerId) or 0] = nil
end)

CreateThread(function()
  -- seeded on the first slice: at file scope the monotonic clock still reads zero
  math.randomseed(math.floor(Open77.time.monotonic() * 1000000) % 2147483647)

  local nextHeartbeatMs = nowMs() + (SYNC.HEARTBEAT_MS or 5000)
  while true do
    Wait(SYNC.SCHEDULER_MS or 1000)
    local atMs = nowMs()
    local published = Authority.tick(atMs)
    if atMs >= nextHeartbeatMs then
      if not published then Authority.publish("heartbeat") end
      nextHeartbeatMs = atMs + (SYNC.HEARTBEAT_MS or 5000)
    end
  end
end)

if Authority.restored then
  Open77.log.info("authority resumed across a reload -- " .. Authority.statusText())
else
  local hour, minute, second = Clock.toHms(Authority.state.baseSeconds)
  Open77.log.info(("authority ready at %02d:%02d:%02d on %s -- reload keeps the sky, " ..
    "restart returns it to configuration"):format(
    hour, minute, second, Authority.state.weather))
end

--- Warns once if the package this one replaces is running too. In a thread, not at file
--- scope: a resource loaded after this one still reads `discovered` at that point.
CreateThread(function()
  local official = tostring(GetResourceState("open77_weather") or ""):lower()
  if official ~= "running" and official ~= "starting" then return end
  Open77.log.warn("open77_weather is running and is the package this one replaces")
  Open77.log.warn("  two authorities both hold world.environment: the clock is corrected twice")
  Open77.log.warn("  a second toward two different times, and the sky is whichever authority")
  Open77.log.warn("  rolled last. Drop one from resources.load in server.jsonc.")
end)

--- The wiring: the one inbound event, the scheduler loop, and the boot banner.

local Config = OPX_WEATHER_CONFIG
local Authority = OpxWeather.Authority
local Clock = OpxWeather.Clock

--- Client to server, and the only inbound event: there is deliberately no mutation event.
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

AddEventHandler("onPlayerDisconnected", function(playerId)
  lastRequestMs[tonumber(playerId) or 0] = nil
end)

--- The platform raises two disconnection events and documents neither; the core takes both.
AddEventHandler("playerDropped", function()
  lastRequestMs[tonumber(source) or 0] = nil
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

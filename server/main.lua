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

--- The one departure event this platform raises, and the only thing keeping `lastRequestMs`
--- from growing for the life of the process. There used to be a second handler on
--- `playerDropped` here, on the assumption that the host raises both: it does not. The name
--- occurs in the shipped server binary only inside the platform's own embedded Lua bootstrap,
--- which registers a handler for it that nothing ever fires; no assembly emits it. A second
--- handler would therefore have been dead code that made this cleanup look doubly covered.
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

--- Warns once if the official package this one replaces is also running. `GetResourceState`
--- is the only way to ask: server resources cannot call each other. Deferred to a thread
--- rather than run at file scope, because at load time a conflicting resource listed after
--- this one in `resources.load` is still `discovered` and the warning would silently not
--- fire -- which would make it depend on load order, the one thing an operator did not
--- choose. The host answers lowercase; `:lower()` costs nothing and survives it changing.
CreateThread(function()
  local official = tostring(GetResourceState("open77_weather") or ""):lower()
  if official ~= "running" and official ~= "starting" then return end
  Open77.log.warn("open77_weather is running and is the package this one replaces")
  Open77.log.warn("  two authorities both hold world.environment: the clock is corrected twice")
  Open77.log.warn("  a second toward two different times, and the sky is whichever authority")
  Open77.log.warn("  rolled last. Drop one from resources.load in server.jsonc.")
end)

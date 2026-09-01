--- The staff desk. The HOST resolves command.<name> against the ACL before a handler runs,
--- so there is no permission check in this file and there must not be one.

local Config = OPX_WEATHER_CONFIG
local Authority = OpxWeather.Authority

--- What a player sees while typing, and what the boot log lists.
local HELP = {
  STATUS = { text = "Show the synchronized time and weather.", params = {} },
  PRESETS = { text = "List the configured weather presets.", params = {} },
  SET = { text = "Cross to a weather preset.", params = {
    { name = "preset", help = "sunny, rain, fog, sandstorm..." },
    { name = "seconds", help = "transition length; omit for the preset's own" },
  } },
  NEXT = { text = "Roll the weighted weather table now.", params = {} },
  FREEZE = { text = "Hold or release the weather schedule.", params = {
    { name = "on|off" },
  } },
  TIME = { text = "Set the authoritative clock.", params = {
    { name = "HH:MM[:SS]", help = "24-hour, for example 21:30" },
  } },
  TIME_FREEZE = { text = "Hold or release the clock.", params = {
    { name = "on|off" },
  } },
  DAY_LENGTH = { text = "Set how many real minutes a day takes.", params = {
    { name = "minutes", help = "180 matches the engine's own rate" },
  } },
}

--- The names actually registered, for the chat suggestions and the boot banner.
local registered = {}

--- Answer whoever ran it: a line back to the player, the platform log otherwise.
---@param source integer|nil
---@param raw string|nil
---@param ok boolean
---@param message string
local function answer(source, raw, ok, message)
  local player = tonumber(source) or 0
  if player > 0 then
    TriggerClientEvent("open77:command:result", player, raw or "", ok == true, message)
    return
  end
  if ok then Open77.log.info(message) else Open77.log.warn(message) end
end

--- How many arguments were typed; `n` is authoritative, `#args` reads 1 for a single nil.
---@param args table|nil
---@return integer
local function count(args)
  if type(args) ~= "table" then return 0 end
  return tonumber(args.n) or #args
end

--- `on` / `off`, and nothing else -- a bare toggle would have to be run twice to be read.
---@param value any
---@return boolean|nil
local function onOff(value)
  if value == "on" or value == "true" or value == "1" then return true end
  if value == "off" or value == "false" or value == "0" then return false end
  return nil
end

--- Last run per player, per open command. Keyed by session playerId, which the host recycles.
local lastCommandMs = {}

---@param source integer|nil
---@param key string
---@return boolean  true when this one should be dropped
local function cooled(source, key)
  local player = tonumber(source) or 0
  -- the console is never cooled: an operator's own terminal is not a rate to limit
  if player <= 0 then return false end
  local slot = player .. ":" .. key
  local atMs = math.floor(Open77.time.monotonic() * 1000)
  local previous = lastCommandMs[slot]
  if previous ~= nil and atMs - previous < 2000 then return true end
  lastCommandMs[slot] = atMs
  return false
end

AddEventHandler("onPlayerDisconnected", function(playerId)
  local player = tonumber(playerId) or 0
  for slot in pairs(lastCommandMs) do
    if slot:match("^(%d+):") == tostring(player) then lastCommandMs[slot] = nil end
  end
end)

--- Register one configured command, or say once why it does not exist.
---@param key string
---@param handler fun(source: integer, args: table, raw: string)
---@param floor boolean|nil  true for a mutation: only an explicit RESTRICTED = false opens it
local function register(key, handler, floor)
  local entry = Config.COMMANDS and Config.COMMANDS[key] or nil
  local name = type(entry) == "table" and entry.NAME or nil
  if type(name) ~= "string" or name == "" then
    Open77.log.info(("command %s is off (COMMANDS.%s.NAME)"):format(key, key))
    return
  end

  local restricted
  if floor then
    -- `~= false` on purpose: a missing, misspelled or quoted flag must not open a mutation
    restricted = entry.RESTRICTED ~= false
    if not restricted then
      Open77.log.warn(("command %s is OPEN to every player (COMMANDS.%s.RESTRICTED = false)")
        :format(name, key))
    end
  else
    restricted = entry.RESTRICTED == true
  end

  -- two entries under one name bind one ACL key, and the loser's RESTRICTED flag with it
  for index = 1, #registered do
    local existing = registered[index]
    if existing.name == name then
      Open77.log.error(("command %s is declared twice (COMMANDS.%s and COMMANDS.%s); " ..
        "%s is NOT registered"):format(name, existing.key, key, key))
      return
    end
  end

  RegisterCommand(name, handler, restricted)
  registered[#registered + 1] = { key = key, name = name, restricted = restricted }
end

register("STATUS", function(source, _, raw)
  if cooled(source, "status") then return end
  answer(source, raw, true, Authority.statusText())
end)

register("PRESETS", function(source, _, raw)
  if cooled(source, "presets") then return end
  local lines = { "weather presets (name / engine preset / weight / seconds):" }
  local presets = Authority.presets()
  for index = 1, #presets do
    local definition = presets[index]
    -- `%g` on the two the loader does not floor: `%d` on a number with no integer form raises
    lines[#lines + 1] = ("  %-12s %-26s w=%-3s %d..%ds  transition %ss"):format(
      definition.NAME, definition.PRESET, ("%g"):format(definition.WEIGHT),
      definition.MIN_SECONDS, definition.MAX_SECONDS,
      ("%g"):format(definition.TRANSITION_SECONDS))
  end
  answer(source, raw, true, table.concat(lines, "\n"))
end)

register("SET", function(source, args, raw)
  local given = count(args)
  if given < 1 or given > 2 then
    return answer(source, raw, false, "usage: <preset> [transitionSeconds]")
  end
  local result = Authority.setWeather(args[1], args[2], "command_set")
  if not result.ok then
    local hint = result.error == "unknown_preset"
      and ("  -- run %s"):format(
        (Config.COMMANDS.PRESETS or {}).NAME or "the presets command")
      or ""
    return answer(source, raw, false, result.error .. hint)
  end
  answer(source, raw, true, Authority.statusText())
end, true)

register("NEXT", function(source, args, raw)
  if count(args) ~= 0 then return answer(source, raw, false, "usage: no arguments") end
  local result = Authority.roll("command_next")
  if not result.ok then return answer(source, raw, false, result.error) end
  answer(source, raw, true, Authority.statusText())
end, true)

register("FREEZE", function(source, args, raw)
  local wanted = onOff(args and args[1])
  if count(args) ~= 1 or wanted == nil then
    return answer(source, raw, false, "usage: <on|off>")
  end
  Authority.setWeatherFrozen(wanted, "command_freeze")
  answer(source, raw, true, Authority.statusText())
end, true)

register("TIME", function(source, args, raw)
  if count(args) ~= 1 then return answer(source, raw, false, "usage: <HH:MM[:SS]>") end
  local seconds = OpxWeather.Clock.parse(args[1])
  if seconds == nil then return answer(source, raw, false, "invalid_time") end
  local hour, minute, second = OpxWeather.Clock.toHms(seconds)
  local result = Authority.setTime(hour, minute, second, "command_time")
  if not result.ok then return answer(source, raw, false, result.error) end
  answer(source, raw, true, Authority.statusText())
end, true)

register("TIME_FREEZE", function(source, args, raw)
  local wanted = onOff(args and args[1])
  if count(args) ~= 1 or wanted == nil then
    return answer(source, raw, false, "usage: <on|off>")
  end
  Authority.setTimeFrozen(wanted, "command_time_freeze")
  answer(source, raw, true, Authority.statusText())
end, true)

register("DAY_LENGTH", function(source, args, raw)
  if count(args) ~= 1 then return answer(source, raw, false, "usage: <realMinutes>") end
  local result = Authority.setDayLength(args[1], "command_day_length")
  if not result.ok then return answer(source, raw, false, result.error) end
  answer(source, raw, true, Authority.statusText())
end, true)

RegisterNetEvent("chat:ready", function()
  local player = tonumber(source) or 0
  if player <= 0 then return end
  if cooled(player, "chat_suggestions") then return end

  local suggestions = {}
  for index = 1, #registered do
    local command = registered[index]
    local help = HELP[command.key] or { text = "", params = {} }
    suggestions[index] =
      { command = "/" .. command.name, help = help.text, parameters = help.params }
  end
  TriggerClientEvent("chat:addSuggestions", player, suggestions)
end)

local names = {}
for index = 1, #registered do
  local command = registered[index]
  names[index] = command.name .. (command.restricted and " [acl]" or " [open]")
end
Open77.log.info(("commands: %s"):format(#names > 0 and table.concat(names, ", ") or "none"))

--- The staff commands. The host resolves `command.<name>` against the ACL before a handler
--- runs, so no handler here checks a permission.

local Config = OPX_WEATHER_CONFIG
local Authority = OpxWeather.Authority

--- What a player sees while typing. Catalogue keys, rendered when the suggestions go out.
local HELP = {
  STATUS = { text = "weather.help.status", params = {} },
  PRESETS = { text = "weather.help.presets", params = {} },
  SET = { text = "weather.help.set", params = {
    { name = "preset", help = "weather.help.set.preset" },
    { name = "seconds", help = "weather.help.set.seconds" },
  } },
  NEXT = { text = "weather.help.next", params = {} },
  FREEZE = { text = "weather.help.freeze", params = {
    { name = "on|off" },
  } },
  TIME = { text = "weather.help.time", params = {
    { name = "HH:MM[:SS]", help = "weather.help.time.value" },
  } },
  TIME_FREEZE = { text = "weather.help.timeFreeze", params = {
    { name = "on|off" },
  } },
  DAY_LENGTH = { text = "weather.help.dayLength", params = {
    { name = "minutes", help = "weather.help.dayLength.minutes" },
  } },
}

--- Error CODES stay codes on the wire; a player reads them through the catalogue.
local ERROR_KEYS = {
  invalid_time = "weather.error.invalidTime",
  invalid_day_length = "weather.error.invalidDayLength",
  day_too_short = "weather.error.dayTooShort",
  unknown_preset = "weather.error.unknownPreset",
  invalid_transition = "weather.error.invalidTransition",
  no_presets = "weather.error.noPresets",
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

--- Whether the answer goes to a player, who reads the catalogue, or to the log, which does not.
---@param source integer|nil
---@return boolean
local function toPlayer(source)
  return (tonumber(source) or 0) > 0
end

--- The status composed for a player. `Authority.statusText()` is the operator's own form.
---@return string
local function statusLine()
  local status = Authority.status()
  local parts = {
    locale("weather.status", {
      time = ("%02d:%02d:%02d"):format(status.hour, status.minute, status.second),
      minutes = math.floor(status.dayLengthMinutes + 0.5),
      weather = status.weather,
    }),
  }
  if status.timeFrozen then parts[#parts + 1] = locale("weather.status.clockHeld") end
  if status.weatherFrozen then
    parts[#parts + 1] = locale("weather.status.scheduleHeld")
  else
    parts[#parts + 1] = locale("weather.status.nextRoll",
      { seconds = status.nextRollInSeconds or 0 })
  end
  parts[#parts + 1] = locale("weather.status.revision", { revision = status.revision })
  if not Authority.ready then parts[#parts + 1] = locale("weather.status.degraded") end
  return table.concat(parts, " ")
end

--- It worked: the player reads the status, the log keeps the operator's English line.
---@param source integer|nil
---@param raw string|nil
local function accept(source, raw)
  answer(source, raw, true, toPlayer(source) and statusLine() or Authority.statusText())
end

--- It did not: catalogue text to the player, `console` to the log, which stays English.
---@param source integer|nil
---@param raw string|nil
---@param key string
---@param params table|nil
---@param console string
local function refuse(source, raw, key, params, console)
  answer(source, raw, false, toPlayer(source) and locale(key, params) or console)
end

--- Refuse with the code a mutator answered, without renaming it for the log.
---@param source integer|nil
---@param raw string|nil
---@param code string|nil
local function refuseCode(source, raw, code)
  refuse(source, raw, ERROR_KEYS[code] or "weather.error.unknown", nil, tostring(code))
end

--- How many arguments were typed; `n` is authoritative, `#args` reads 1 for a single nil.
---@param args table|nil
---@return integer
local function count(args)
  if type(args) ~= "table" then return 0 end
  local given = tonumber(args.n)
  -- a NaN `n` sits inside every range test below, so `#args` answers instead
  if not OpxWeather.Clock.finite(given) or given < 0 or given % 1 ~= 0 then return #args end
  return given
end

--- `on` / `off` and their synonyms; nil for anything else.
---@param value any
---@return boolean|nil
local function onOff(value)
  if value == "on" or value == "true" or value == "1" then return true end
  if value == "off" or value == "false" or value == "0" then return false end
  return nil
end

--- Last run per player, per command, for the two-second cooldown.
local lastCommandMs = {}

---@param source integer|nil
---@param key string
---@return boolean  true when this one should be dropped
local function cooled(source, key)
  local player = tonumber(source) or 0
  -- the console is never cooled
  if player <= 0 then return false end
  local slot = player .. ":" .. key
  local atMs = OpxWeather.nowMs()
  local previous = lastCommandMs[slot]
  if previous ~= nil and atMs - previous < 2000 then return true end
  lastCommandMs[slot] = atMs
  return false
end

-- the only departure event this platform raises
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
  accept(source, raw)
end)

register("PRESETS", function(source, _, raw)
  if cooled(source, "presets") then return end
  local player = toPlayer(source)
  local lines = { player and locale("weather.presets.header")
    or "weather presets (name / engine preset / weight / seconds):" }
  local presets = Authority.presets()
  for index = 1, #presets do
    local definition = presets[index]
    local row = {
      name = ("%-12s"):format(definition.NAME),
      preset = ("%-26s"):format(definition.PRESET),
      -- `%g` on the two the loader does not floor: `%d` on a number with no integer form raises
      weight = ("%-3s"):format(("%g"):format(definition.WEIGHT)),
      min = definition.MIN_SECONDS,
      max = definition.MAX_SECONDS,
      transition = ("%g"):format(definition.TRANSITION_SECONDS),
    }
    lines[#lines + 1] = player and locale("weather.presets.row", row)
      or ("  %s %s w=%s %d..%ds  transition %ss"):format(
        row.name, row.preset, row.weight, row.min, row.max, row.transition)
  end
  answer(source, raw, true, table.concat(lines, "\n"))
end)

register("SET", function(source, args, raw)
  local given = count(args)
  if given < 1 or given > 2 then
    return refuse(source, raw, "weather.usage.set", nil,
      "usage: <preset> [transitionSeconds]")
  end
  local result = Authority.setWeather(args[1], args[2], "command_set")
  if not result.ok then
    local presets = Config.COMMANDS and (Config.COMMANDS.PRESETS or {}).NAME or nil
    if result.error == "unknown_preset" and type(presets) == "string" and presets ~= "" then
      return refuse(source, raw, "weather.error.presetHint", { command = presets },
        ("unknown_preset -- run %s"):format(presets))
    end
    return refuseCode(source, raw, result.error)
  end
  accept(source, raw)
end, true)

register("NEXT", function(source, args, raw)
  if count(args) ~= 0 then
    return refuse(source, raw, "weather.usage.next", nil, "usage: no arguments")
  end
  local result = Authority.roll("command_next")
  if not result.ok then return refuseCode(source, raw, result.error) end
  accept(source, raw)
end, true)

register("FREEZE", function(source, args, raw)
  local wanted = onOff(args and args[1])
  if count(args) ~= 1 or wanted == nil then
    return refuse(source, raw, "weather.usage.freeze", nil, "usage: <on|off>")
  end
  Authority.setWeatherFrozen(wanted, "command_freeze")
  accept(source, raw)
end, true)

register("TIME", function(source, args, raw)
  if count(args) ~= 1 then
    return refuse(source, raw, "weather.usage.time", nil, "usage: <HH:MM[:SS]>")
  end
  local seconds = OpxWeather.Clock.parse(args[1])
  if seconds == nil then return refuseCode(source, raw, "invalid_time") end
  local hour, minute, second = OpxWeather.Clock.toHms(seconds)
  local result = Authority.setTime(hour, minute, second, "command_time")
  if not result.ok then return refuseCode(source, raw, result.error) end
  accept(source, raw)
end, true)

register("TIME_FREEZE", function(source, args, raw)
  local wanted = onOff(args and args[1])
  if count(args) ~= 1 or wanted == nil then
    return refuse(source, raw, "weather.usage.timeFreeze", nil, "usage: <on|off>")
  end
  Authority.setTimeFrozen(wanted, "command_time_freeze")
  accept(source, raw)
end, true)

register("DAY_LENGTH", function(source, args, raw)
  if count(args) ~= 1 then
    return refuse(source, raw, "weather.usage.dayLength", nil, "usage: <realMinutes>")
  end
  local result = Authority.setDayLength(args[1], "command_day_length")
  if not result.ok then return refuseCode(source, raw, result.error) end
  accept(source, raw)
end, true)

RegisterNetEvent("chat:ready", function()
  local player = tonumber(source) or 0
  if player <= 0 then return end
  if cooled(player, "chat_suggestions") then return end

  local suggestions = {}
  for index = 1, #registered do
    local command = registered[index]
    local help = HELP[command.key]
    local parameters = {}
    for position = 1, help and #help.params or 0 do
      local parameter = help.params[position]
      parameters[position] = {
        name = parameter.name,
        help = parameter.help and locale(parameter.help) or nil,
      }
    end
    suggestions[index] = {
      command = "/" .. command.name,
      help = help and locale(help.text) or "",
      parameters = parameters,
    }
  end
  TriggerClientEvent("chat:addSuggestions", player, suggestions)
end)

local names = {}
for index = 1, #registered do
  local command = registered[index]
  names[index] = command.name .. (command.restricted and " [acl]" or " [open]")
end
Open77.log.info(("commands: %s"):format(#names > 0 and table.concat(names, ", ") or "none"))

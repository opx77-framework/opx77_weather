OpxWeather.Locale.register("en", {
  ["weather.status"]                = "It is {time}. A day lasts {minutes} real minutes. " ..
                                      "The sky is {weather}.",
  ["weather.status.clockHeld"]      = "The clock is held.",
  ["weather.status.scheduleHeld"]   = "The weather schedule is held.",
  ["weather.status.nextRoll"]       = "Next roll in {seconds}s.",
  ["weather.status.revision"]       = "Revision {revision}.",
  ["weather.status.degraded"]       = "No usable weather preset is configured.",

  ["weather.presets.header"]        = "weather presets (name / engine preset / weight / " ..
                                      "seconds):",
  ["weather.presets.row"]           = "  {name} {preset} w={weight} {min}..{max}s  " ..
                                      "transition {transition}s",

  ["weather.usage.set"]             = "usage: <preset> [transitionSeconds]",
  ["weather.usage.next"]            = "usage: no arguments",
  ["weather.usage.freeze"]          = "usage: <on|off>",
  ["weather.usage.time"]            = "usage: <HH:MM[:SS]>",
  ["weather.usage.timeFreeze"]      = "usage: <on|off>",
  ["weather.usage.dayLength"]       = "usage: <realMinutes>",

  ["weather.error.invalidTime"]     = "That is not a time of day. Use HH:MM or HH:MM:SS.",
  ["weather.error.invalidDayLength"] = "A day lasts between 1 minute and 7 days.",
  ["weather.error.dayTooShort"]     = "That day is too short for a client to follow.",
  ["weather.error.unknownPreset"]   = "No such weather preset.",
  ["weather.error.presetHint"]      = "No such weather preset. Run {command} to see the list.",
  ["weather.error.invalidTransition"] = "A transition lasts between 0 and 300 seconds.",
  ["weather.error.noPresets"]       = "No weather preset is configured.",
  ["weather.error.unknown"]         = "That could not be done.",

  ["weather.help.status"]           = "Show the synchronized time and weather.",
  ["weather.help.presets"]          = "List the configured weather presets.",
  ["weather.help.set"]              = "Cross to a weather preset.",
  ["weather.help.set.preset"]       = "sunny, rain, fog, sandstorm...",
  ["weather.help.set.seconds"]      = "transition length; omit for the preset's own",
  ["weather.help.next"]             = "Roll the weighted weather table now.",
  ["weather.help.freeze"]           = "Hold or release the weather schedule.",
  ["weather.help.time"]             = "Set the authoritative clock.",
  ["weather.help.time.value"]       = "24-hour, for example 21:30",
  ["weather.help.timeFreeze"]       = "Hold or release the clock.",
  ["weather.help.dayLength"]        = "Set how many real minutes a day takes.",
  ["weather.help.dayLength.minutes"] = "180 matches the engine's own rate",
})

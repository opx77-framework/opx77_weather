-- Operator configuration. Shared, so a client downloads it: no secrets, no ACL grants.

OPX_WEATHER_CONFIG = {
  LOCALE = "en", -- which locales/<code>.lua player-facing text is read from
  DAY_LENGTH_MINUTES = 180, -- real minutes per day; only 180 matches the engine's own rate
  START_TIME = { HOUR = 12, MINUTE = 0, SECOND = 0 }, -- boot only; a reload keeps the time
  TIME_FROZEN = false, -- start with the clock held at START_TIME
  WEATHER_FROZEN = false, -- start with OUR schedule held; not the engine's own weather lock
  INITIAL_WEATHER = "sunny", -- a NAME or PRESET below; unknown falls back to the first row

  -- name / engine preset / weight, relative and 0 never rolls / min..max seconds / crossfade
  WEATHER = {
    { NAME = "sunny", PRESET = "24h_weather_sunny", WEIGHT = 28,
      MIN_SECONDS = 480, MAX_SECONDS = 900, TRANSITION_SECONDS = 18 },
    { NAME = "lightclouds", PRESET = "24h_weather_light_clouds", WEIGHT = 24,
      MIN_SECONDS = 360, MAX_SECONDS = 720, TRANSITION_SECONDS = 20 },
    { NAME = "cloudy", PRESET = "24h_weather_cloudy", WEIGHT = 18,
      MIN_SECONDS = 300, MAX_SECONDS = 600, TRANSITION_SECONDS = 24 },
    { NAME = "rain", PRESET = "24h_weather_rain", WEIGHT = 12,
      MIN_SECONDS = 180, MAX_SECONDS = 420, TRANSITION_SECONDS = 30 },
    { NAME = "heavyclouds", PRESET = "24h_weather_heavy_clouds", WEIGHT = 8,
      MIN_SECONDS = 240, MAX_SECONDS = 480, TRANSITION_SECONDS = 26 },
    { NAME = "fog", PRESET = "24h_weather_fog", WEIGHT = 5,
      MIN_SECONDS = 180, MAX_SECONDS = 360, TRANSITION_SECONDS = 28 },
    { NAME = "pollution", PRESET = "24h_weather_pollution", WEIGHT = 3,
      MIN_SECONDS = 180, MAX_SECONDS = 360, TRANSITION_SECONDS = 28 },
    { NAME = "sandstorm", PRESET = "24h_weather_sandstorm", WEIGHT = 2,
      MIN_SECONDS = 120, MAX_SECONDS = 300, TRANSITION_SECONDS = 35 },
  },

  COMMANDS = { -- RESTRICTED gates on command.<NAME> in acl.jsonc; NAME = false registers none
    STATUS = { NAME = "opx77.weather", RESTRICTED = false }, -- time, weather, freezes, roll
    PRESETS = { NAME = "opx77.weather.presets", RESTRICTED = false }, -- what .set accepts
    SET = { NAME = "opx77.weather.set", RESTRICTED = true }, -- <name|preset> [seconds]
    NEXT = { NAME = "opx77.weather.next", RESTRICTED = true }, -- roll now, even if frozen
    FREEZE = { NAME = "opx77.weather.freeze", RESTRICTED = true }, -- <on|off>, the SCHEDULE
    TIME = { NAME = "opx77.weather.time", RESTRICTED = true }, -- <HH:MM[:SS]>
    TIME_FREEZE = { NAME = "opx77.weather.time.freeze", RESTRICTED = true }, -- <on|off>
    DAY_LENGTH = { NAME = "opx77.weather.daylength", RESTRICTED = true }, -- <realMinutes>
  },
}

---@meta
--- Type annotations for opx77_weather. Never loaded at runtime; keep it in step with the code.

--- A snake_case code, meant for branching rather than for a player to read.
---@alias WeatherError
---| "invalid_time"           an hour that does not exist, or an unparsable one
---| "invalid_day_length"     outside 1 minute .. 7 days
---| "day_too_short"          a day length past Clock.MAX_RATE
---| "unknown_preset"         not a NAME or a PRESET in OPX_WEATHER_CONFIG.WEATHER
---| "invalid_transition"     not a number, or outside 0..300 seconds
---| "no_presets"             the weather table has no usable row
---| "invalid_snapshot"       failed validation on the way in
---| "stale"                  older than the snapshot already held
---| "request_failed"         the sync request never left the client
---| "not_synchronized"       no snapshot accepted yet
---| "environment_unavailable"  the client has no environment natives

--- Why a snapshot was published. Diagnostic only; a new value is not a protocol change.
---@alias WeatherReason string

--- One row of `OPX_WEATHER_CONFIG.WEATHER`.
---@class WeatherPreset
---@field NAME string                the stable name staff type and the state stores
---@field PRESET string              the REDengine preset handed to setWeather
---@field WEIGHT number              relative, only against the other rows. 0 never rolls
---@field MIN_SECONDS integer        real seconds; drawn when the preset starts
---@field MAX_SECONDS integer
---@field TRANSITION_SECONDS number  how long the sky takes to cross into it

--- One entry of `OPX_WEATHER_CONFIG.COMMANDS`.
---@class WeatherCommand
---@field NAME string|false   false registers nothing at all
---@field RESTRICTED boolean  true gates command.<NAME> against the ACL before the handler

--- What the authority broadcasts, and the only thing a client acts on.
---@class WeatherSnapshot
---@field protocol integer            must equal OpxWeather.PROTOCOL
---@field authorityEpoch number       which server incarnation; a new one wins outright
---@field revision integer            bumped by every mutation
---@field weatherRevision integer     bumped only when the preset changes
---@field secondsOfDay number
---@field rate number                 game seconds per real second
---@field timeFrozen boolean
---@field weather string              a WeatherPreset NAME
---@field weatherPreset string        its REDengine PRESET
---@field weatherPriority integer
---@field weatherFrozen boolean       the SCHEDULE is held; not the engine's lock
---@field transitionSeconds number
---@field weatherTransitionRemainingMs number  remaining, because the clocks are not shared
---@field nextRollInMs number|nil     absent while the schedule is frozen
---@field reason WeatherReason

--- What the client holds after accepting a snapshot, re-based onto its own monotonic clock.
---@class WeatherProjection : WeatherSnapshot
---@field anchorLocalMs number             local ms the snapshot was accepted at
---@field weatherTransitionEndLocalMs number
---@field latencyCompensationMs number     half the round trip, bounded

--- Every mutator in server/state.lua answers one of these and never raises.
---@class WeatherResult
---@field ok boolean
---@field error WeatherError|nil

---@class WeatherTimeResult : WeatherResult
---@field hour integer|nil
---@field minute integer|nil
---@field second integer|nil

---@class WeatherSetResult : WeatherResult
---@field weather string|nil
---@field preset string|nil
---@field transitionSeconds number|nil

---@class WeatherFrozenResult : WeatherResult
---@field frozen boolean|nil

---@class WeatherDayLengthResult : WeatherResult
---@field minutes number|nil
---@field rate number|nil

--- What `Authority.status()` answers: everything a status line needs, already resolved.
--- Rendered by `Authority.statusText()` and by `statusLine()` in server/commands.lua.
---@class WeatherStatus : WeatherResult
---@field hour integer
---@field minute integer
---@field second integer
---@field dayLengthMinutes number
---@field timeFrozen boolean
---@field weather string
---@field weatherFrozen boolean
---@field nextRollInSeconds integer|nil  absent while the schedule is frozen
---@field revision integer

--- What the `getState` export answers, projected to the instant of the call.
---@class WeatherStateResponse : WeatherResult
---@field hour integer|nil
---@field minute integer|nil
---@field second integer|nil
---@field secondsOfDay number|nil
---@field weather string|nil
---@field weatherPreset string|nil
---@field timeFrozen boolean|nil
---@field weatherFrozen boolean|nil
---@field revision integer|nil
---@field weatherRevision integer|nil
---@field latencyCompensationMs number|nil

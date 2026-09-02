resource "opx77_weather"
version "0.2.0"
open77_version ">=0.0.1"
auto_start true

-- reload hands the live state to the host and keeps the sky; restart returns it to config
reload_policy "local"

shared_script "config.lua"
shared_script "shared/locale.lua"
shared_script "locales/en.lua" -- registered right after the catalogue, so no file
shared_script "locales/fr.lua" -- below calls locale() against an empty one
shared_script "shared/clock.lua"

server_script "server/state.lua"
server_script "server/commands.lua"
server_script "server/main.lua"

client_script "client/main.lua"
client_script "client/exports.lua"

permissions {
  "network.events",     -- snapshots out, sync requests in
  "world.environment",  -- Open77.environment.*; client-side only, and only this resource
}

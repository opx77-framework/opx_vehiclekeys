resource "opx_vehiclekeys"
version "1.0.0"
open77_version ">=0.0.1"
auto_start true

-- OPX//77 vehicle keys: the owner locks and unlocks his car for everybody, lends keys, stops the engine and
-- opens the trunk. Provider of opx_core's `vehiclekeys` slot. Shared keys live in the MySQL table
-- opx_vehicle_keys (created at start); temporary keys (rentals, test drives) live in memory only.
-- Optional, never required: opx_target (eye options), the inventory provider (trunk = OpenStash), opx_chat.
-- opx_menu is a dependency because require('@opx_menu') only loads a declared, running one.
dependencies {
    "opx_core",
    "opx_menu",
}

permissions {
    "database.access",   -- server: opx_vehicle_keys (schema, load, inserts, deletes)
    "network.events",    -- both: requests to the server, answers to the client
    "world.vehicles",    -- server: Open77.vehicles setLocked, isLocked, isLockedForPlayer, setEngine, isEngineOn, nearby, getPlayerSeat
    "players.life.read", -- server: Open77.players.isDead (no action while dead)
    "acl.read",          -- server: Open77.acl.isAllowed (Config.staffRight)
    "input.actions",     -- client: RegisterKeyMapping (lock key, optional menu key)
}

shared_script "config.lua"

-- No `require` on the server: the files share globals, loaded in this order.
server_scripts {
    "server/db.lua",
    "server/keys.lua",
    "server/actions.lua",
    "server/main.lua",
}

client_script "client/main.lua"

files {
    "client/modules/*.lua",
    "locales/*.json",
}

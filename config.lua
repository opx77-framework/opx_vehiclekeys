Config = {}

-- Default keys (players rebind them: Settings > Key bindings). lock: toggles the lock of the car you sit in,
-- else of the nearest car you hold a key for. menu: opens the vehicle menu; false = no key (use the command).
Config.keys = { lock = 'U', menu = false }

-- Command that opens the vehicle menu (lock, engine, trunk, keys), for every player. false = no command.
Config.command = 'vehicle'

-- Metres within which the lock key and the eye's "Lock / Unlock" reach a car (server check).
Config.lockDistance = 6.0

-- Shared keys per owned car, the owner not counted.
Config.maxHolders = 5

-- Metres between the owner and the player who receives a key (same routing bucket).
Config.giveDistance = 3.0

-- Engine on / off from the driver seat. needsKey: only a key holder may switch it.
Config.engine = { enabled = true, needsKey = true }

-- Trunk = an inventory stash per plate (inventory provider's OpenStash). distance: metres to the car.
-- capacityG / slots: size of the trunk. ownedOnly: only owned cars (opx_core opx_vehicles) have a trunk.
-- label: the stash title, %s = the plate.
Config.trunk = { enabled = true, distance = 3.5, capacityG = 50000, slots = 20, ownedOnly = true, label = 'Trunk %s' }

-- ACL right whose holders have a key to every car (staff). false = nobody.
Config.staffRight = 'command.opx_vehiclekeys'

-- Minimum milliseconds between two requests of one player (anything faster is ignored).
Config.rateLimitMs = 500

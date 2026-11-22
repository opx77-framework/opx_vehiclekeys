---@meta

-- opx_vehiclekeys server exports and host events: the `vehiclekeys` provider contract of opx_core
-- (Config.providers.vehiclekeys). Not loaded by the manifest (LuaLS annotations only).
-- A replacement keys resource keeps these names and shapes.
-- Every export is SYNCHRONOUS and answers from memory (the table is written in callback form). Call them through
-- the provider, never by name:
--   local name = exports.opx_core:GetProvider('vehiclekeys')
--   local ok, has = pcall(Open77.exports.callSync, name, 'HasKey', source, vehicleId)
-- A vehicle id is a live Open77 vehicle id (integer); a plate is the opx_core plate (string, A-Z 0-9 space -).

---@alias OpxVehicleKeysError
---| 'invalid_player' not a player id / citizen id
---| 'not_loaded' the player has no character loaded
---| 'unknown_vehicle' no live vehicle with this id, or an invalid plate (a temporary key needs a live car)
---| 'not_owned' a stored key was asked for a car that is not in opx_vehicles
---| 'too_many' the plate already has Config.maxHolders key holders
---| 'not_ready' the keys table is not loaded yet
---| 'no_key' (RemoveKey) the character held no key to that vehicle
---| 'invalid_vehicle' (SetLocked) not a vehicle id
---| 'invalid_argument' (SetLocked) locked is not a boolean
---| string a refusal of Open77.vehicles.setLocked (vehicle_not_found...)

---@class OpxVehicleKeysGiveOptions
---@field temporary? boolean memory-only key on a live vehicle id (rental, test drive), dropped with the car

---@class OpxVehicleKeysExports
local opx_vehiclekeys = {}

--- SYNC. Whether the player's character owns the car, holds a stored or temporary key to it, or the player has
--- Config.staffRight.
---@param source integer
---@param vehicleId integer
---@return boolean
function opx_vehiclekeys.HasKey(source, vehicleId) end

--- SYNC. Gives a key to the character of `source`. A number is a live vehicle id, a string a plate.
--- Without options.temporary the key is stored (table opx_vehicle_keys) on the car's plate: owned cars only.
--- With options.temporary the key lives in memory on the live vehicle id (a plate is resolved to its live car).
--- The holder gets the lock exception at once when the car is out. Already holding it (or owning it) = true.
---@param source integer
---@param vehicleIdOrPlate integer|string
---@param options? OpxVehicleKeysGiveOptions
---@return boolean ok
---@return OpxVehicleKeysError|nil reason
function opx_vehiclekeys.GiveKey(source, vehicleIdOrPlate, options) end

--- SYNC. Removes the stored and / or temporary key a character holds (a number = player id, a string = citizen
--- id, offline allowed). A loaded holder loses the lock exception at once.
---@param sourceOrCitizenId integer|string
---@param vehicleIdOrPlate integer|string
---@return boolean ok
---@return OpxVehicleKeysError|nil reason
function opx_vehiclekeys.RemoveKey(sourceOrCitizenId, vehicleIdOrPlate) end

--- SYNC. Citizen ids holding a stored key to the plate, sorted (the owner not included; temporary keys not listed).
---@param plate string
---@return string[]
function opx_vehiclekeys.GetKeyHolders(plate) end

--- SYNC. Moves the canonical lock bit only: key holders' exceptions stay (Open77.vehicles.setLocked).
--- Raises opx:vehiclekeys:lockChanged with bySource nil.
---@param vehicleId integer
---@param locked boolean
---@return boolean ok
---@return OpxVehicleKeysError|nil reason
function opx_vehiclekeys.SetLocked(vehicleId, locked) end

--- SYNC. The canonical lock bit, or nil for an unknown vehicle.
---@param vehicleId integer
---@return boolean|nil
function opx_vehiclekeys.IsLocked(vehicleId) end

-- Server host events (AddEventHandler). bySource is the player who acted, nil when an export did it.
-- TriggerEvent('opx:vehiclekeys:lockChanged', vehicleId, locked, bySource)
---@alias OpxVehicleKeysLockChangedEvent fun(vehicleId: integer, locked: boolean, bySource: integer|nil)
-- TriggerEvent('opx:vehiclekeys:keyGiven', plateOrVehicleId, citizenId, bySource, temporary)
-- (a stored key carries the plate, a temporary key the vehicle id)
---@alias OpxVehicleKeysKeyGivenEvent fun(plateOrVehicleId: string|integer, citizenId: string, bySource: integer|nil, temporary: boolean)
-- TriggerEvent('opx:vehiclekeys:keyRemoved', plateOrVehicleId, citizenId, bySource)
-- Not raised when keys go with a removed car or a deleted character.
---@alias OpxVehicleKeysKeyRemovedEvent fun(plateOrVehicleId: string|integer, citizenId: string, bySource: integer|nil)

-- Access: every loaded key holder gets opx_core SetVehicleOwnerAccess(vehicleId, source, true) when the key is
-- given, on opx:vehicleSpawned, on opx:playerLoaded and 5 s after opx_core restarts; false when the key is taken
-- back or the character unloads. The lock toggle never uses setLockedForAll (it would wipe those exceptions).
-- Table opx_vehicle_keys (plate, citizen_id, created_at; PK plate+citizen_id), loaded whole at start. Rows go on
-- opx:ownedVehicleRemoved (plate) and opx:characterDeleted (keys held and cars owned).
-- Trunk = inventory provider OpenStash(source, 'trunk_<plate>', { label, capacityG, slots }), plate lower-cased,
-- spaces as '_'. Opens on foot, within Config.trunk.distance, when the car is not locked for that player.
-- Limits: temporary keys are forgotten on restart (exceptions already given stay until disconnect or the car
-- goes); when the resource stops for good, given exceptions stay until the holders disconnect; trunk contents
-- are never deleted (a plate generated again could find an old trunk); Open77.vehicles.setEngine with a driver
-- seated is not yet checked in game (fallback: Config.engine.enabled = false).
-- Internal net events (not a contract): opx_vehiclekeys:lock|engine|trunk|menu|keys|players|give|take
-- (client -> server) and opx_vehiclekeys:notify|menu|keys|players (server -> client). Client exports targetLock,
-- targetTrunk, targetGiveKey are the eye callbacks.

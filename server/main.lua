-- Entry: client requests (validated, rate-limited, one at a time), the `vehiclekeys` provider exports, the
-- command, and the opx_core lifecycle events that keep the lock exceptions right.

local uint = Keys.toSource

-- Every client request: a valid source, under the rate limit, one at a time. Nothing waits.
local function onRequest(name, handler)
	RegisterNetEvent(name, function(...)
		local src = uint(source)
		if not src or not Actions.allow(src) then return end
		Actions.run(src, handler, ...)
	end)
end

onRequest('opx_vehiclekeys:lock', function(src, vehicleId) Actions.lock(src, vehicleId) end)
onRequest('opx_vehiclekeys:engine', function(src) Actions.engine(src) end)
onRequest('opx_vehiclekeys:trunk', function(src, vehicleId) Actions.trunk(src, vehicleId) end)
onRequest('opx_vehiclekeys:menu', function(src) Actions.menu(src) end)
onRequest('opx_vehiclekeys:keys', function(src, target) Actions.keys(src, target) end)
onRequest('opx_vehiclekeys:players', function(src, plate) Actions.nearbyPlayers(src, plate) end)
onRequest('opx_vehiclekeys:give', function(src, plate, target) Actions.give(src, plate, target) end)
onRequest('opx_vehiclekeys:take', function(src, plate, citizenId) Actions.take(src, plate, citizenId) end)

-- Exports (the `vehiclekeys` provider contract, all synchronous, answered from memory) ---------------

exports('HasKey', function(source, vehicleId)
	return Keys.has(source, vehicleId)
end)

-- GiveKey(source, vehicleIdOrPlate, options?): a number is a live vehicle id, a string a plate.
-- options.temporary = true: memory-only key on the live vehicle; otherwise a stored key on an owned plate.
exports('GiveKey', function(source, vehicle, options)
	local src = uint(source)
	if not src then return false, 'invalid_player' end
	local character = Keys.character(src)
	if not character then return false, 'not_loaded' end
	local temporary = type(options) == 'table' and options.temporary == true
	local id, plate
	if type(vehicle) == 'number' then
		id = Keys.toVehicleId(vehicle)
		if not id or Open77.vehicles.isLocked(id) == nil then return false, 'unknown_vehicle' end
		if not temporary then
			local _, livePlate = Keys.owner(id)
			if not livePlate then return false, 'not_owned' end
			plate = livePlate
		end
	elseif type(vehicle) == 'string' then
		plate = Keys.toPlate(vehicle)
		if not plate then return false, 'unknown_vehicle' end
		if temporary then
			id = Keys.liveId(plate)
			if not id then return false, 'unknown_vehicle' end
		end
	else
		return false, 'unknown_vehicle'
	end
	if temporary then return Keys.giveTemporary(character.citizenId, id, nil) end
	return Keys.giveStored(character.citizenId, plate, nil)
end)

-- RemoveKey(sourceOrCitizenId, vehicleIdOrPlate): removes both the stored and the temporary key it finds.
exports('RemoveKey', function(holder, vehicle)
	local citizenId
	if type(holder) == 'number' then
		local src = uint(holder)
		if not src then return false, 'invalid_player' end
		local character = Keys.character(src)
		if not character then return false, 'not_loaded' end
		citizenId = character.citizenId
	elseif Keys.isCitizenId(holder) then
		citizenId = holder
	else
		return false, 'invalid_player'
	end
	local removed = false
	if type(vehicle) == 'number' then
		local id = Keys.toVehicleId(vehicle)
		if not id then return false, 'unknown_vehicle' end
		removed = Keys.removeTemporary(citizenId, id, nil) or removed
		local _, plate = Keys.owner(id)
		if plate then removed = Keys.removeStored(citizenId, plate, nil) or removed end
	elseif type(vehicle) == 'string' then
		local plate = Keys.toPlate(vehicle)
		if not plate then return false, 'unknown_vehicle' end
		removed = Keys.removeStored(citizenId, plate, nil) or removed
		local id = Keys.liveId(plate)
		if id then removed = Keys.removeTemporary(citizenId, id, nil) or removed end
	else
		return false, 'unknown_vehicle'
	end
	if not removed then return false, 'no_key' end
	return true
end)

exports('GetKeyHolders', function(plate)
	plate = Keys.toPlate(plate)
	return plate and Keys.holders(plate) or {}
end)

exports('SetLocked', function(vehicleId, locked)
	local id = Keys.toVehicleId(vehicleId)
	if not id then return false, 'invalid_vehicle' end
	if type(locked) ~= 'boolean' then return false, 'invalid_argument' end
	return Actions.setLocked(id, locked, nil)
end)

exports('IsLocked', function(vehicleId)
	local id = Keys.toVehicleId(vehicleId)
	if not id then return nil end
	local locked = Open77.vehicles.isLocked(id)
	if type(locked) ~= 'boolean' then return nil end
	return locked
end)

-- Command ------------------------------------------------------------------------------------------

if type(Config.command) == 'string' and Config.command ~= '' then
	RegisterCommand(Config.command, function(src)
		src = uint(src)
		if not src then return print('[opx_vehiclekeys] use this command in game') end
		if Actions.allow(src) then Actions.run(src, Actions.menu) end
	end, false)
end

-- Command help shown in opx_chat when it runs (optional). Chat is not a provider slot, so opx_chat is named.
local function publishCommandHelp()
	if type(Config.command) ~= 'string' or Config.command == '' or GetResourceState('opx_chat') ~= 'running' then return end
	pcall(Open77.exports.callSync, 'opx_chat', 'SetCommandHelp', Config.command,
		{ en = 'Vehicle menu: lock, engine, trunk, keys.', fr = 'Menu du véhicule : verrou, moteur, coffre, clés.' })
end

-- Lifecycle -----------------------------------------------------------------------------------------

AddEventHandler('onResourceStart', function(name)
	if name == GetCurrentResourceName() or name == 'opx_chat' then publishCommandHelp() end
	-- opx_core restarted: once its cars are linked again, the key holders get their exceptions back.
	if name == 'opx_core' then
		SetTimeout(5000, function() if Db.ready then Keys.grantAll() end end)
	end
end)

-- A car came out (garage, staff, reconnect): its stored key holders who are loaded get their exception.
AddEventHandler('opx:vehicleSpawned', function(vehicleId, plate)
	local id = Keys.toVehicleId(vehicleId)
	plate = Keys.toPlate(plate)
	if id and plate then Keys.grantVehicle(id, plate) end
end)

AddEventHandler('opx:playerLoaded', function(playerId, data)
	local src = uint(playerId)
	local citizenId = type(data) == 'table' and data.citizenId or nil
	if src and Keys.isCitizenId(citizenId) then Keys.grantCitizen(src, citizenId) end
end)

-- Character switch: the session loses the exceptions of the previous character's keys.
AddEventHandler('opx:playerUnloaded', function(playerId, citizenId)
	local src = uint(playerId)
	if not src then return end
	Actions.forget(src)
	if Keys.isCitizenId(citizenId) then Keys.revokeCitizen(src, citizenId) end
end)

-- The platform drops a disconnected player's exceptions itself.
AddEventHandler('onPlayerDisconnected', function(playerId)
	local src = uint(playerId)
	if src then Actions.forget(src) end
end)

AddEventHandler('opx:ownedVehicleRemoved', function(plate)
	plate = Keys.toPlate(plate)
	if plate then Keys.dropPlate(plate) end
end)

-- A deleted character: the keys he held, and the keys of his cars (opx_core deletes them without raising
-- opx:ownedVehicleRemoved; the handler order is unknown, so his plates are read now and checked again later).
AddEventHandler('opx:characterDeleted', function(_, citizenId)
	if not Keys.isCitizenId(citizenId) then return end
	Keys.dropCitizen(citizenId)
	local owned = Keys.core('GetOwnedVehicles', citizenId)
	for _, row in ipairs(type(owned) == 'table' and owned or {}) do
		local plate = type(row) == 'table' and Keys.toPlate(row.plate)
		if plate then Keys.dropPlate(plate) end
	end
	SetTimeout(3000, Keys.dropOrphans)
end)

-- Temporary keys end with their car.
AddEventHandler('onVehicleRemoved', function(vehicleId)
	local id = Keys.toVehicleId(vehicleId)
	if id then Keys.vehicleGone(id) end
end)

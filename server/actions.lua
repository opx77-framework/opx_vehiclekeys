-- Player actions: lock, engine, trunk, the vehicle menu and the keys menu. The client only asks; everything
-- is decided here from the server's own seat, distance, bucket, life state and key data.

Actions = {}

local uint = Keys.toSource
local lastCall = {} -- [source] = GetGameTimer() of his last accepted request
local busy = {}     -- [source] = true while one of his requests runs

-- Feedback ----------------------------------------------------------------------------------------

-- A locale key + params for the player's client, which translates it and shows it through opx_core Notify.
function Actions.notify(source, key, kind, params)
	pcall(TriggerClientEvent, 'opx_vehiclekeys:notify', source, key, kind or 'info', params or {})
end

-- Guards -----------------------------------------------------------------------------------------

-- Rate limit: false when the player asked again too soon.
function Actions.allow(source)
	local now = GetGameTimer()
	local last = lastCall[source]
	if last and now - last < (tonumber(Config.rateLimitMs) or 500) then return false end
	lastCall[source] = now
	return true
end

-- Runs one request of a player at a time (a re-entry from an event handler is dropped).
function Actions.run(source, fn, ...)
	if busy[source] then return end
	busy[source] = true
	local ok, err = pcall(fn, source, ...)
	busy[source] = nil
	if not ok then print(('[opx_vehiclekeys] request of player %d raised: %s'):format(source, tostring(err))) end
end

function Actions.forget(source)
	lastCall[source], busy[source] = nil, nil
end

local function alive(source)
	return Open77.players.isDead(source) ~= true
end

-- The player's seat: vehicleId, canonical seat name; nil when on foot.
local function seatOf(source)
	local seat = Open77.vehicles.getPlayerSeat(source)
	if type(seat) ~= 'table' then return nil end
	return Keys.toVehicleId(seat.vehicleId), seat.seat
end

-- Live vehicles within `radius` of the player, in his bucket, nearest first: { id = distance }, ordered ids.
local function nearby(source, radius)
	local list = Open77.vehicles.nearby(source, radius, { limit = 8 })
	local ids = {}
	for _, entry in ipairs(type(list) == 'table' and list or {}) do
		local id = type(entry) == 'table' and Keys.toVehicleId(entry.id)
		if id then ids[#ids + 1] = id end
	end
	return ids
end

local function contains(list, value)
	for _, v in ipairs(list) do if v == value then return true end end
	return false
end

-- What the player reads for a car: its plate, else its id.
local function plateText(vehicleId)
	local _, plate = Keys.owner(vehicleId)
	return plate or ('#' .. vehicleId)
end

-- Lock --------------------------------------------------------------------------------------------

-- The car to lock: `wanted` (eye) when he sits in it or it stands within Config.lockDistance; without
-- `wanted`, the car he sits in, else the nearest he holds a key for. id | nil, reason.
local function lockTarget(source, wanted)
	local seated = seatOf(source)
	if seated and (not wanted or wanted == seated) then
		if Keys.has(source, seated) then return seated end
		return nil, 'no_key'
	end
	local ids = nearby(source, tonumber(Config.lockDistance) or 6.0)
	if wanted then
		if not contains(ids, wanted) then return nil, 'no_vehicle' end
		if Keys.has(source, wanted) then return wanted end
		return nil, 'no_key'
	end
	for _, id in ipairs(ids) do
		if Keys.has(source, id) then return id end
	end
	return nil, #ids > 0 and 'no_key' or 'no_vehicle'
end

-- Canonical bit only (exceptions stay, so key holders keep their access). NEVER setLockedForAll here.
function Actions.setLocked(vehicleId, locked, bySource)
	local ok, reason = Open77.vehicles.setLocked(vehicleId, locked == true)
	if not ok then return false, reason or 'failed' end
	TriggerEvent('opx:vehiclekeys:lockChanged', vehicleId, locked == true, bySource)
	return true
end

function Actions.lock(source, wanted)
	if wanted ~= nil then
		wanted = Keys.toVehicleId(wanted)
		if not wanted then return end
	end
	if not Keys.character(source) then return end
	if not alive(source) then return Actions.notify(source, 'dead', 'error') end
	local id, reason = lockTarget(source, wanted)
	if not id then return Actions.notify(source, reason, 'error') end
	local current = Open77.vehicles.isLocked(id)
	if type(current) ~= 'boolean' then return Actions.notify(source, 'no_vehicle', 'error') end
	local ok, why = Actions.setLocked(id, not current, source)
	if not ok then return Actions.notify(source, 'failed', 'error', { reason = tostring(why) }) end
	Actions.notify(source, current and 'unlocked' or 'locked', 'success', { plate = plateText(id) })
end

-- Engine ------------------------------------------------------------------------------------------

function Actions.engine(source)
	if not Config.engine or Config.engine.enabled == false then return Actions.notify(source, 'engine_disabled', 'error') end
	if not Keys.character(source) then return end
	if not alive(source) then return Actions.notify(source, 'dead', 'error') end
	local id, seat = seatOf(source)
	if not id or seat ~= 'seat_front_left' then return Actions.notify(source, 'not_driver', 'error') end
	if Config.engine.needsKey ~= false and not Keys.has(source, id) then return Actions.notify(source, 'no_key', 'error') end
	local on = Open77.vehicles.isEngineOn(id)
	if type(on) ~= 'boolean' then return Actions.notify(source, 'no_vehicle', 'error') end
	local ok, why = Open77.vehicles.setEngine(id, not on)
	if not ok then return Actions.notify(source, 'failed', 'error', { reason = tostring(why) }) end
	Actions.notify(source, on and 'engine_off' or 'engine_on', 'success')
end

-- Trunk -------------------------------------------------------------------------------------------

-- 'trunk_' .. the plate lower-cased, spaces as '_' (fits the stash name rule ^[a-z0-9_.-]+$, 48 bytes).
local function stashName(plate)
	return 'trunk_' .. (plate:lower():gsub(' ', '_'))
end

function Actions.trunk(source, wanted)
	local trunk = Config.trunk
	if type(trunk) ~= 'table' or trunk.enabled == false then return Actions.notify(source, 'trunk_disabled', 'error') end
	if wanted ~= nil then
		wanted = Keys.toVehicleId(wanted)
		if not wanted then return end
	end
	if not Keys.character(source) then return end
	if not alive(source) then return Actions.notify(source, 'dead', 'error') end
	if seatOf(source) then return Actions.notify(source, 'in_vehicle', 'error') end
	-- Within reach and in his bucket (nearby defaults to the player's bucket).
	local ids = nearby(source, tonumber(trunk.distance) or 3.5)
	local id = wanted
	if id then
		if not contains(ids, id) then return Actions.notify(source, 'no_vehicle', 'error') end
	else
		id = ids[1]
		if not id then return Actions.notify(source, 'no_vehicle', 'error') end
	end
	if Open77.vehicles.isLockedForPlayer(id, source) ~= false then return Actions.notify(source, 'trunk_locked', 'error') end
	local _, plate = Keys.owner(id)
	if not plate or (trunk.ownedOnly ~= false and not Keys.plateOwner(plate)) then
		return Actions.notify(source, 'no_trunk', 'error')
	end
	local provider = Keys.core('GetProvider', 'inventory')
	if type(provider) ~= 'string' then return Actions.notify(source, 'inventory_unavailable', 'error') end
	local label = type(trunk.label) == 'string' and trunk.label:gsub('%%s', plate) or plate
	local called, ok, why = pcall(Open77.exports.callSync, provider, 'OpenStash', source, stashName(plate), {
		label = label, capacityG = trunk.capacityG, slots = trunk.slots,
	})
	if not called then return Actions.notify(source, 'inventory_unavailable', 'error') end
	if ok ~= true then Actions.notify(source, 'failed', 'error', { reason = tostring(why) }) end
end

-- Vehicle menu ------------------------------------------------------------------------------------

-- What the menu shows: engine row only for the driver, trunk row only on foot.
function Actions.menu(source)
	if not Keys.character(source) then return end
	local id, seat = seatOf(source)
	pcall(TriggerClientEvent, 'opx_vehiclekeys:menu', source, {
		seated = id ~= nil,
		driver = id ~= nil and seat == 'seat_front_left',
		engine = type(Config.engine) == 'table' and Config.engine.enabled ~= false,
		trunk = type(Config.trunk) == 'table' and Config.trunk.enabled ~= false,
	})
end

-- Keys menu ---------------------------------------------------------------------------------------

local MAX_CARS = 50

-- A holder's display name: the character's name, else his citizen id.
local function holderName(citizenId)
	local info = Keys.core('GetCharacterInfo', citizenId)
	if type(info) == 'table' and type(info.firstname) == 'string' then
		return ('%s %s'):format(info.firstname, tostring(info.lastname or '')):sub(1, 64)
	end
	return citizenId
end

-- The cars the character owns, each with its holders. `target` (eye on a player) is sent back as is, so
-- the client opens the "give to this player" list instead of the full menu.
-- `refresh` (after a give / take back): the client only updates a keys menu that is still open.
function Actions.keys(source, target, refresh)
	local character = Keys.character(source)
	if not character then return end
	if target ~= nil then target = uint(target) end
	local owned = Keys.core('GetOwnedVehicles', character.citizenId)
	local cars = {}
	for _, row in ipairs(type(owned) == 'table' and owned or {}) do
		if #cars >= MAX_CARS then break end
		local plate = type(row) == 'table' and Keys.toPlate(row.plate)
		if plate then
			local holders = {}
			for i, citizenId in ipairs(Keys.holders(plate)) do
				holders[i] = { citizenId = citizenId, name = holderName(citizenId) }
			end
			cars[#cars + 1] = { plate = plate, out = row.vehicleId ~= nil, holders = holders }
		end
	end
	pcall(TriggerClientEvent, 'opx_vehiclekeys:keys', source, cars, target,
		math.tointeger(Config.maxHolders) or 5, refresh == true)
end

-- Is `target` a player within Config.giveDistance of `source`, in the same bucket?
local function isNear(source, target)
	local list = Open77.players.nearby(source, tonumber(Config.giveDistance) or 3.0, { limit = 8 })
	for _, entry in ipairs(type(list) == 'table' and list or {}) do
		if type(entry) == 'table' and uint(entry.playerId) == target then return true end
	end
	return false
end

-- Players the owner may give a key to: id and distance in decimetres. Names are not sent (no metagaming).
function Actions.nearbyPlayers(source, plate)
	if not Keys.character(source) then return end
	plate = Keys.toPlate(plate)
	if not plate then return end
	local list = Open77.players.nearby(source, tonumber(Config.giveDistance) or 3.0, { limit = 8 })
	local out = {}
	for _, entry in ipairs(type(list) == 'table' and list or {}) do
		local id = type(entry) == 'table' and uint(entry.playerId)
		local distance = type(entry) == 'table' and tonumber(entry.distance)
		if id and id ~= source and distance and distance == distance and distance < 1000 and Keys.character(id) then
			out[#out + 1] = { id = id, dm = math.floor(distance * 10 + 0.5) }
		end
	end
	pcall(TriggerClientEvent, 'opx_vehiclekeys:players', source, plate, out)
end

-- The owner gives a stored key on his plate to a player standing next to him.
function Actions.give(source, plate, target)
	plate, target = Keys.toPlate(plate), uint(target)
	if not plate then return end
	if not target or target == source then return Actions.notify(source, 'invalid_target', 'error') end
	local owner = Keys.character(source)
	if not owner then return end
	if not alive(source) then return Actions.notify(source, 'dead', 'error') end
	if Keys.plateOwner(plate) ~= owner.citizenId then return Actions.notify(source, 'not_owner', 'error') end
	local receiver = Keys.character(target)
	if not receiver then return Actions.notify(source, 'target_not_loaded', 'error') end
	if receiver.citizenId == owner.citizenId then return Actions.notify(source, 'invalid_target', 'error') end
	if not isNear(source, target) then return Actions.notify(source, 'too_far', 'error') end
	local ok, why = Keys.giveStored(receiver.citizenId, plate, source)
	if not ok then
		local known = why == 'too_many' or why == 'not_ready' or why == 'not_owned'
		return Actions.notify(source, known and why or 'failed', 'error', { reason = tostring(why), max = Config.maxHolders })
	end
	Actions.notify(source, 'key_given', 'success', { plate = plate, id = target })
	Actions.notify(target, 'key_received', 'success', { plate = plate })
	Actions.keys(source, nil, true)
end

-- The owner takes a stored key back (the holder may be offline).
function Actions.take(source, plate, citizenId)
	plate = Keys.toPlate(plate)
	if not plate or not Keys.isCitizenId(citizenId) then return end
	local owner = Keys.character(source)
	if not owner then return end
	if Keys.plateOwner(plate) ~= owner.citizenId then return Actions.notify(source, 'not_owner', 'error') end
	if not Db.ready then return Actions.notify(source, 'not_ready', 'error') end
	if not Keys.removeStored(citizenId, plate, source) then return Actions.notify(source, 'no_holder', 'error') end
	Actions.notify(source, 'key_taken', 'success', { plate = plate })
	local holder = Keys.sourceOf(citizenId)
	if holder then Actions.notify(holder, 'key_lost', 'warning', { plate = plate }) end
	Actions.keys(source, nil, true)
end

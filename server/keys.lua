-- The key model. A character holds a key to a live vehicle when he owns it (opx_core GetVehicleOwner), when
-- opx_vehicle_keys holds (plate, citizenId), when he holds a temporary key (memory only, by vehicle id), or
-- when the player has Config.staffRight. Every loaded key holder gets the per-player lock exception through
-- opx_core SetVehicleOwnerAccess (opx_core does it for the owner itself).

Keys = {}

local CORE = 'opx_core'
local stored = {}    -- [plate] = { [citizenId] = createdAt }
local byCitizen = {} -- [citizenId] = { [plate] = true }
local temporary = {} -- [vehicleId] = { [citizenId] = true }

-- Helpers ----------------------------------------------------------------------------------------

-- A player id: an integer in 1..2^32-1 from anything, or nil. Natives abort the server on anything else.
local function uint(value)
	local id = tonumber(value)
	if not id or id ~= id or id < 1 or id > 0xFFFFFFFF or id % 1 ~= 0 then return nil end
	return math.tointeger(id)
end
Keys.toSource = uint

-- Open77 vehicle ids are 64-bit positive integers (generation in the high bits, e.g. 4294967297); 0 or negative aborts the server.
-- Accepted: an integer (or integral float, JSON) 1..2^53-1, exact in JSON and in Lua numbers, or a string of digits
-- (host events: tostring(seat.vehicleId)). nil for anything else (0, negative, 1.5, NaN, inf, larger).
local MAX_VEHICLE_ID = 9007199254740991
local function vehicleId(value)
	if type(value) == 'string' then
		if not value:match('^%d+$') then return nil end
		value = tonumber(value) -- a float when the digits do not fit an integer: refused below
		if math.type(value) ~= 'integer' then return nil end
	end
	if math.type(value) == 'float' then value = math.tointeger(value) end
	if math.type(value) ~= 'integer' or value < 1 or value > MAX_VEHICLE_ID then return nil end
	return value
end
Keys.toVehicleId = vehicleId

-- The platform's plate rule (same as opx_core): trimmed, upper-case, A-Z 0-9 space -, 1..10, no double space.
function Keys.toPlate(value)
	if type(value) ~= 'string' then return nil end
	local plate = value:gsub('^%s+', ''):gsub('%s+$', ''):upper()
	if #plate < 1 or #plate > 10 or plate:find('  ', 1, true) or not plate:match('^[A-Z0-9 %-]+$') then return nil end
	return plate
end

function Keys.isCitizenId(value)
	return type(value) == 'string' and #value >= 1 and #value <= 32 and value:match('^[%w_%-]+$') ~= nil
end

-- An export of opx_core: a, b, or nil when it raised (opx_core stopped, export missing).
local function core(name, ...)
	local ok, a, b = pcall(Open77.exports.callSync, CORE, name, ...)
	if not ok then return nil end
	return a, b
end
Keys.core = core

-- The loaded character of a player: { citizenId, name }, or nil.
function Keys.character(source)
	local data = core('GetPlayer', source)
	if type(data) ~= 'table' or not Keys.isCitizenId(data.citizenId) then return nil end
	local name = ('%s %s'):format(tostring(data.firstname or ''), tostring(data.lastname or ''))
	return { citizenId = data.citizenId, name = name:sub(1, 64) }
end

-- The session of a loaded character, or nil.
function Keys.sourceOf(citizenId)
	local data = core('GetPlayerByCitizenId', citizenId)
	return type(data) == 'table' and uint(data.source) or nil
end

-- citizenId (or nil), plate (or nil) of a live vehicle opx_core knows.
function Keys.owner(vehicleId)
	local citizenId, plate = core('GetVehicleOwner', vehicleId)
	return type(citizenId) == 'string' and citizenId or nil, type(plate) == 'string' and plate or nil
end

-- The owner's citizen id of an owned plate (opx_vehicles), or nil.
function Keys.plateOwner(plate)
	local row = core('GetOwnedVehicle', plate)
	return type(row) == 'table' and type(row.citizenId) == 'string' and row.citizenId or nil
end

function Keys.liveId(plate)
	return vehicleId(core('GetVehicleByPlate', plate))
end

function Keys.isStaff(source)
	if type(Config.staffRight) ~= 'string' or Config.staffRight == '' then return false end
	local ok, allowed = pcall(Open77.acl.isAllowed, source, Config.staffRight)
	return ok and allowed == true
end

-- allowed = true: this player sees the car unlocked; false: back to the car's own lock.
function Keys.access(id, source, allowed)
	if not vehicleId(id) or not uint(source) then return end
	core('SetVehicleOwnerAccess', id, source, allowed == true)
end

-- Memory -------------------------------------------------------------------------------------------

local function index(plate, citizenId, createdAt)
	stored[plate] = stored[plate] or {}
	stored[plate][citizenId] = createdAt or 0
	byCitizen[citizenId] = byCitizen[citizenId] or {}
	byCitizen[citizenId][plate] = true
end

local function unindex(plate, citizenId)
	local holders = stored[plate]
	if holders then
		holders[citizenId] = nil
		if next(holders) == nil then stored[plate] = nil end
	end
	local plates = byCitizen[citizenId]
	if plates then
		plates[plate] = nil
		if next(plates) == nil then byCitizen[citizenId] = nil end
	end
end

-- Rows read at start (db.lua). Returns how many were kept.
function Keys.load(rows)
	local count = 0
	for _, row in ipairs(rows) do
		local plate = Keys.toPlate(row.plate)
		if plate and plate == row.plate and Keys.isCitizenId(row.citizen_id) then
			index(plate, row.citizen_id, math.tointeger(tonumber(row.created_at) or 0) or 0)
			count = count + 1
		end
	end
	return count
end

-- Questions -------------------------------------------------------------------------------------

-- Whether a character holds a key to a live vehicle (staff right not included).
function Keys.citizenHas(citizenId, vehicleId)
	if not citizenId then return false end
	local owner, plate = Keys.owner(vehicleId)
	if owner == citizenId then return true end
	if plate and stored[plate] and stored[plate][citizenId] then return true end
	local temp = temporary[vehicleId]
	return temp ~= nil and temp[citizenId] == true
end

function Keys.has(source, vehicleId)
	local src, id = uint(source), Keys.toVehicleId(vehicleId)
	if not src or not id then return false end
	local character = Keys.character(src)
	if character and Keys.citizenHas(character.citizenId, id) then return true end
	return Keys.isStaff(src)
end

-- Citizen ids holding a stored key to the plate (the owner not included), sorted.
function Keys.holders(plate)
	local list = {}
	for citizenId in pairs(stored[plate] or {}) do list[#list + 1] = citizenId end
	table.sort(list)
	return list
end

function Keys.holderCount(plate)
	local n = 0
	for _ in pairs(stored[plate] or {}) do n = n + 1 end
	return n
end

-- Changes ---------------------------------------------------------------------------------------

-- Stored key on an owned plate. true | false, reason. bySource: the player who gave it (nil: an export).
function Keys.giveStored(citizenId, plate, bySource)
	if not Db.ready then return false, 'not_ready' end
	local owner = Keys.plateOwner(plate)
	if not owner then return false, 'not_owned' end
	if owner == citizenId or (stored[plate] and stored[plate][citizenId]) then return true end
	if Keys.holderCount(plate) >= (math.tointeger(Config.maxHolders) or 5) then return false, 'too_many' end
	local at = Db.now()
	index(plate, citizenId, at)
	Db.insert(plate, citizenId, at)
	local holder = Keys.sourceOf(citizenId)
	local id = Keys.liveId(plate)
	if holder and id then Keys.access(id, holder, true) end
	TriggerEvent('opx:vehiclekeys:keyGiven', plate, citizenId, bySource, false)
	return true
end

-- Temporary key on a live vehicle id (memory only).
function Keys.giveTemporary(citizenId, vehicleId, bySource)
	local temp = temporary[vehicleId]
	if temp and temp[citizenId] then return true end
	temporary[vehicleId] = temp or {}
	temporary[vehicleId][citizenId] = true
	local holder = Keys.sourceOf(citizenId)
	if holder then Keys.access(vehicleId, holder, true) end
	TriggerEvent('opx:vehiclekeys:keyGiven', vehicleId, citizenId, bySource, true)
	return true
end

-- The holder still loaded loses his exception unless he keeps a key another way.
local function revokeAccess(citizenId, vehicleId)
	if not vehicleId then return end
	local holder = Keys.sourceOf(citizenId)
	if holder and not Keys.citizenHas(citizenId, vehicleId) then Keys.access(vehicleId, holder, false) end
end

function Keys.removeStored(citizenId, plate, bySource)
	if not (stored[plate] and stored[plate][citizenId]) then return false end
	unindex(plate, citizenId)
	Db.delete(plate, citizenId)
	revokeAccess(citizenId, Keys.liveId(plate))
	TriggerEvent('opx:vehiclekeys:keyRemoved', plate, citizenId, bySource)
	return true
end

function Keys.removeTemporary(citizenId, vehicleId, bySource)
	local temp = temporary[vehicleId]
	if not (temp and temp[citizenId]) then return false end
	temp[citizenId] = nil
	if next(temp) == nil then temporary[vehicleId] = nil end
	revokeAccess(citizenId, vehicleId)
	TriggerEvent('opx:vehiclekeys:keyRemoved', vehicleId, citizenId, bySource)
	return true
end

-- Every stored key of a plate (the car was removed from opx_vehicles).
function Keys.dropPlate(plate)
	for citizenId in pairs(stored[plate] or {}) do unindex(plate, citizenId) end
	Db.deletePlate(plate)
end

-- Every stored key a character held (character deleted).
function Keys.dropCitizen(citizenId)
	for plate in pairs(byCitizen[citizenId] or {}) do unindex(plate, citizenId) end
	Db.deleteCitizen(citizenId)
	for id, temp in pairs(temporary) do
		temp[citizenId] = nil
		if next(temp) == nil then temporary[id] = nil end
	end
end

-- Plates whose car is no longer owned (opx_core removed it with its character): their keys go.
function Keys.dropOrphans()
	if GetResourceState(CORE) ~= 'running' then return end
	for plate in pairs(stored) do
		local ok, row = pcall(Open77.exports.callSync, CORE, 'GetOwnedVehicle', plate)
		if ok and row == nil then Keys.dropPlate(plate) end
	end
end

function Keys.vehicleGone(vehicleId)
	temporary[vehicleId] = nil
end

-- Exceptions ------------------------------------------------------------------------------------

-- A loaded character: the exception on every live car he holds a key to.
function Keys.grantCitizen(source, citizenId)
	for plate in pairs(byCitizen[citizenId] or {}) do
		local id = Keys.liveId(plate)
		if id then Keys.access(id, source, true) end
	end
	for id, temp in pairs(temporary) do
		if temp[citizenId] then Keys.access(id, source, true) end
	end
end

-- A character unloads (character switch): the session loses the exceptions his keys gave.
function Keys.revokeCitizen(source, citizenId)
	for plate in pairs(byCitizen[citizenId] or {}) do
		local id = Keys.liveId(plate)
		if id then Keys.access(id, source, false) end
	end
	for id, temp in pairs(temporary) do
		if temp[citizenId] then Keys.access(id, source, false) end
	end
end

-- A car came out (opx:vehicleSpawned): its stored key holders who are loaded get their exception.
function Keys.grantVehicle(vehicleId, plate)
	for citizenId in pairs(plate and stored[plate] or {}) do
		local holder = Keys.sourceOf(citizenId)
		if holder then Keys.access(vehicleId, holder, true) end
	end
end

-- Every loaded character (start, opx_core restarted).
function Keys.grantAll()
	-- Sources first, then one character at a time (a whole GetLoadedPlayers could pass the export size limit).
	local list = core('GetPlayers')
	for _, value in ipairs(type(list) == 'table' and list or {}) do
		local src = uint(value)
		local character = src and Keys.character(src)
		if character then Keys.grantCitizen(src, character.citizenId) end
	end
end

function Keys.onReady()
	Keys.grantAll()
end

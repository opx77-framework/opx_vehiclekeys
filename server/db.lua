-- Shared keys in opx_vehiclekeys' own MySQL table. Loaded whole at start; after that memory is the authority
-- and every change is written right away in callback form (never yields, so the exports stay synchronous).
-- Nothing is pending at stop: each give / take back is one INSERT / DELETE sent when it happens.

Db = { ready = false }

local SCHEMA = [[CREATE TABLE IF NOT EXISTS opx_vehicle_keys (
	plate VARCHAR(10) NOT NULL,
	citizen_id VARCHAR(32) NOT NULL,
	created_at BIGINT NOT NULL,
	PRIMARY KEY (plate, citizen_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]

-- Unix seconds as an integer (0 when the clock cannot answer).
function Db.now()
	local ok, t = pcall(Open77.time.unix)
	t = ok and tonumber(t) or nil
	if not t or t ~= t or t == math.huge or t == -math.huge or t < 0 then return 0 end
	return math.tointeger(math.floor(t)) or 0
end

-- One statement in callback form; a failure is printed.
local function execute(sql, params, label)
	if type(Open77.database) ~= 'table' then return end
	local ok, queued, reason = pcall(Open77.database.update, sql, params, function(_, failure)
		if failure then print(('[opx_vehiclekeys] %s failed: %s'):format(label, tostring(failure))) end
	end)
	-- A refusal (false, reason) also reaches the callback above; only a raise needs its own line.
	if not ok then print(('[opx_vehiclekeys] %s refused: %s'):format(label, tostring(queued or reason))) end
end

function Db.insert(plate, citizenId, createdAt)
	execute('INSERT IGNORE INTO opx_vehicle_keys (plate, citizen_id, created_at) VALUES (?, ?, ?)',
		{ plate, citizenId, createdAt }, 'key insert ' .. plate)
end

function Db.delete(plate, citizenId)
	execute('DELETE FROM opx_vehicle_keys WHERE plate = ? AND citizen_id = ?', { plate, citizenId },
		'key delete ' .. plate)
end

function Db.deletePlate(plate)
	execute('DELETE FROM opx_vehicle_keys WHERE plate = ?', { plate }, 'keys of plate ' .. plate)
end

function Db.deleteCitizen(citizenId)
	execute('DELETE FROM opx_vehicle_keys WHERE citizen_id = ?', { citizenId }, 'keys of ' .. citizenId)
end

-- Schema, then every row into memory (Keys.load), then Keys.onReady. All in callback form.
CreateThread(function()
	if type(Open77.database) ~= 'table' then
		return print('[opx_vehiclekeys] no database bridge: shared keys disabled (enable the database, database.access)')
	end
	local queued, reason = Open77.database.ready(function()
		Open77.database.update(SCHEMA, {}, function(_, failure)
			if failure then return print(('[opx_vehiclekeys] schema failed: %s'):format(tostring(failure))) end
			Open77.database.query('SELECT plate, citizen_id, created_at FROM opx_vehicle_keys', {}, function(rows, why)
				if why or type(rows) ~= 'table' then
					return print(('[opx_vehiclekeys] loading keys failed: %s'):format(tostring(why or 'query_failed')))
				end
				local count = Keys.load(rows)
				Db.ready = true
				print(('[opx_vehiclekeys] %d shared keys loaded'):format(count))
				Keys.onReady()
			end)
		end)
	end)
	if not queued then print(('[opx_vehiclekeys] database unavailable: %s'):format(tostring(reason))) end
end)

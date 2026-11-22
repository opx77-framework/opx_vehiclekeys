-- Optional eye options through the target provider's client exports (opx_core Config.providers.target, no
-- manifest dependency): "Lock / Unlock" and "Trunk" on vehicles, "Give a vehicle key" on players. When no
-- target provider runs, nothing happens; client/main.lua registers again when it starts.
-- Predicates are UX only: the server checks key, distance, bucket and life state.

local OPX = assert(require('@opx_core'))
local T = OPX.Locale()

local Target = {}

local function add(provider, kind, options)
	local pending, err = Open77.exports.call(provider, kind, options)
	if not pending then return print(('[opx_vehiclekeys] %s %s: %s'):format(provider, kind, tostring(err))) end
	local id, reason = pending:await()
	if not id then print(('[opx_vehiclekeys] %s refused the %s options: %s'):format(provider, kind, tostring(reason))) end
end

function Target.register()
	local provider = OPX.GetProvider('target')
	if not provider then return end
	local vehicle = {
		{ name = 'opx_vehiclekeys_lock', label = T('lock_toggle'), icon = 'lock',
			distance = tonumber(Config.lockDistance) or 6.0, onSelect = 'targetLock' },
	}
	if type(Config.trunk) == 'table' and Config.trunk.enabled ~= false then
		vehicle[#vehicle + 1] = { name = 'opx_vehiclekeys_trunk', label = T('trunk'), icon = 'box',
			distance = tonumber(Config.trunk.distance) or 3.5, onSelect = 'targetTrunk' }
	end
	add(provider, 'addVehicle', vehicle)
	add(provider, 'addPlayer', {
		{ name = 'opx_vehiclekeys_give', label = T('give_key'), icon = 'key',
			distance = tonumber(Config.giveDistance) or 3.0, onSelect = 'targetGiveKey' },
	})
end

return Target

-- opx_vehiclekeys client: the lock key, the optional menu key, the menus and the eye options. It only asks;
-- the server decides everything (seat, distance, bucket, keys).

local OPX = assert(require('@opx_core'))
local Ui = assert(require('client.modules.ui'))
local Target = assert(require('client.modules.target'))

CreateThread(function()
	local keys = type(Config.keys) == 'table' and Config.keys or {}
	if type(keys.lock) == 'string' and keys.lock ~= '' then
		local ok, reason = RegisterKeyMapping('opx_vehiclekeys.lock', Ui.text('key_lock'), keys.lock, function()
			if OPX.IsLoaded() then TriggerServerEvent('opx_vehiclekeys:lock') end
		end)
		if not ok then print(('[opx_vehiclekeys] lock key refused: %s'):format(tostring(reason))) end
	end
	if type(keys.menu) == 'string' and keys.menu ~= '' then
		local ok, reason = RegisterKeyMapping('opx_vehiclekeys.menu', Ui.text('key_menu'), keys.menu, function()
			if OPX.IsLoaded() and not Ui.isOpen() then TriggerServerEvent('opx_vehiclekeys:menu') end
		end)
		if not ok then print(('[opx_vehiclekeys] menu key refused: %s'):format(tostring(reason))) end
	end
	Target.register()
end)

OPX.OnPlayerUnloaded(function() Ui.close() end)

RegisterNetEvent('opx_vehiclekeys:notify', function(key, kind, params) Ui.notify(key, kind, params) end)
RegisterNetEvent('opx_vehiclekeys:menu', function(state) Ui.open(state) end)
RegisterNetEvent('opx_vehiclekeys:keys', function(cars, target, max, refresh) Ui.keys(cars, target, max, refresh) end)
RegisterNetEvent('opx_vehiclekeys:players', function(plate, list) Ui.players(plate, list) end)

-- opx_target calls these exports of ours (exports-only path: no manifest dependency on it).
local function vehicleOf(ctx)
	local target = type(ctx) == 'table' and type(ctx.target) == 'table' and ctx.target or nil
	local id = target and math.tointeger(tonumber(target.vehicleId))
	return id and id > 0 and id or nil
end

exports('targetLock', function(ctx)
	local id = vehicleOf(ctx)
	if id then TriggerServerEvent('opx_vehiclekeys:lock', id) end
	return true
end)

exports('targetTrunk', function(ctx)
	local id = vehicleOf(ctx)
	if id then TriggerServerEvent('opx_vehiclekeys:trunk', id) end
	return true
end)

exports('targetGiveKey', function(ctx)
	local target = type(ctx) == 'table' and type(ctx.target) == 'table' and math.tointeger(tonumber(ctx.target.playerId))
	if target and target > 0 then TriggerServerEvent('opx_vehiclekeys:keys', target) end
	return true
end)

-- The target provider (re)started: its registry is empty, register again.
AddEventHandler('onClientResourceStart', function(name)
	if name == OPX.GetProvider('target') then CreateThread(Target.register) end
end)

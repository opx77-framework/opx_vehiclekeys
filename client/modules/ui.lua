-- The vehicle menu and the keys menus (opx_menu). Shows and asks; the server decides.

local OPX = assert(require('@opx_core'))
local Menu = assert(require('@opx_menu'))

local Ui = {}

local T = OPX.Locale()
local main = nil     -- the open vehicle menu, or nil
local keysMenu = nil -- the open "Keys" menu (list of owned cars), or nil
local carMenu = nil  -- the open menu of one car, or nil
local carPlate = nil -- its plate
local keysCars = {}  -- the cars listed in keysMenu

function Ui.text(key, params) return T(key, type(params) == 'table' and params or {}) end

-- A server answer: locale key + kind + params. An unknown key reads as a generic failure.
function Ui.notify(key, kind, params)
	if type(key) ~= 'string' then return end
	local text = Ui.text(key, params)
	if text == key then text = Ui.text('failed', { reason = key }) end
	OPX.Notify(text, kind, nil, Ui.text('title'))
end

local function isOpen(menu) return menu ~= nil and menu:isOpen() end

function Ui.isOpen() return isOpen(main) or isOpen(keysMenu) or isOpen(carMenu) end

function Ui.close()
	if main then main:close() end
	if keysMenu then keysMenu:close() end
	if carMenu then carMenu:close() end
	main, keysMenu, carMenu, carPlate = nil, nil, nil, nil
end

-- Vehicle menu ------------------------------------------------------------------------------------

function Ui.open(state)
	if type(state) ~= 'table' then return end
	local elements = {
		{ label = Ui.text('lock_toggle'), value = 'lock', icon = 'lock', description = Ui.text('lock_desc') },
	}
	if state.engine and state.driver then
		elements[#elements + 1] = { label = Ui.text('engine'), value = 'engine', icon = 'power', description = Ui.text('engine_desc') }
	end
	if state.trunk and not state.seated then
		elements[#elements + 1] = { label = Ui.text('trunk'), value = 'trunk', icon = 'box', description = Ui.text('trunk_desc') }
	end
	elements[#elements + 1] = { label = Ui.text('keys'), value = 'keys', icon = 'key', description = Ui.text('keys_desc'), rightLabel = '>' }
	elements[#elements + 1] = { label = Ui.text('close'), value = 'close', icon = 'close' }
	main = Menu.open({
		id = 'opx_vehiclekeys', title = Ui.text('title'), elements = elements,
		onSelect = function(element, menu)
			local action = element.value
			if action == 'lock' then TriggerServerEvent('opx_vehiclekeys:lock')
			elseif action == 'engine' then TriggerServerEvent('opx_vehiclekeys:engine')
			elseif action == 'trunk' then
				menu:close() -- the trunk opens in the inventory's own menu
				TriggerServerEvent('opx_vehiclekeys:trunk')
			elseif action == 'keys' then TriggerServerEvent('opx_vehiclekeys:keys')
			else menu:close() end
		end,
		onClose = function(menu)
			if main == menu then main = nil end
		end,
	})
end

-- Keys menus --------------------------------------------------------------------------------------

local function holderCount(car) return type(car.holders) == 'table' and #car.holders or 0 end

-- One car: its holders ("take back" each) and "give a key".
local function carElements(car, max)
	local elements = {}
	local count = holderCount(car)
	elements[1] = {
		label = Ui.text('give_key'), value = 'give', icon = 'plus', disabled = count >= max,
		description = count >= max and Ui.text('too_many', { max = max }) or Ui.text('give_desc'),
	}
	elements[2] = { type = 'separator', label = Ui.text('holders') }
	for i, holder in ipairs(type(car.holders) == 'table' and car.holders or {}) do
		if type(holder) == 'table' and type(holder.citizenId) == 'string' then
			elements[#elements + 1] = {
				label = tostring(holder.name or holder.citizenId), value = 'h' .. i, icon = 'person',
				rightLabel = Ui.text('take_back'), description = Ui.text('take_desc'), citizenId = holder.citizenId,
			}
		end
	end
	if #elements == 2 then elements[3] = { label = Ui.text('no_holders'), value = 'none', disabled = true } end
	return elements
end

local function openCar(car, max, parent)
	carPlate = car.plate
	carMenu = Menu.open({
		id = 'opx_vehiclekeys_car', title = Ui.text('car_title', { plate = car.plate }), parent = parent,
		elements = carElements(car, max),
		onSelect = function(element)
			if element.value == 'give' then
				TriggerServerEvent('opx_vehiclekeys:players', carPlate)
			elseif element.citizenId then
				CreateThread(function()
					local yes = Menu.confirm({
						title = Ui.text('take_back'),
						message = Ui.text('take_confirm', { name = element.label, plate = carPlate }),
						confirmLabel = Ui.text('take_back'), cancelLabel = Ui.text('cancel'),
					})
					if yes then TriggerServerEvent('opx_vehiclekeys:take', carPlate, element.citizenId) end
				end)
			end
		end,
		onClose = function(menu)
			if carMenu == menu then carMenu, carPlate = nil, nil end
		end,
	})
end

local function carRows(cars, max)
	local elements = {}
	for i, car in ipairs(cars) do
		elements[i] = {
			label = car.plate, value = i, icon = 'vehicle',
			rightLabel = ('%d/%d'):format(holderCount(car), max),
			description = Ui.text(car.out and 'car_out' or 'car_stored'),
		}
	end
	if #elements == 0 then elements[1] = { label = Ui.text('no_cars'), value = 'none', disabled = true } end
	return elements
end

-- Eye on a player: pick one of the owned cars, the key goes to that player.
local function giveTo(cars, max, target)
	local elements = carRows(cars, max)
	Menu.open({
		id = 'opx_vehiclekeys_give', title = Ui.text('give_key'), subtitle = Ui.text('player_entry', { id = target }),
		elements = elements,
		onSelect = function(element, menu)
			local car = cars[element.value]
			menu:close()
			if car then TriggerServerEvent('opx_vehiclekeys:give', car.plate, target) end
		end,
	})
end

-- The owned cars with their holders. refresh: an answer to a give / take back, only updates open menus.
function Ui.keys(cars, target, max, refresh)
	if type(cars) ~= 'table' then return end
	local list = {}
	for _, car in ipairs(cars) do
		if type(car) == 'table' and type(car.plate) == 'string' then list[#list + 1] = car end
	end
	max = math.tointeger(tonumber(max)) or 5
	target = math.tointeger(tonumber(target))
	if target and target > 0 and not refresh then return giveTo(list, max, target) end

	if isOpen(carMenu) then
		for _, car in ipairs(list) do
			if car.plate == carPlate then carMenu:setElements(carElements(car, max), true) end
		end
	end
	if refresh then
		if isOpen(keysMenu) then
			keysCars = list
			keysMenu:setElements(carRows(list, max), true)
		end
		return
	end
	keysCars = list
	keysMenu = Menu.open({
		id = 'opx_vehiclekeys_keys', title = Ui.text('keys'), parent = isOpen(main) and main or nil,
		elements = carRows(list, max),
		onSelect = function(element, menu)
			local car = keysCars[element.value]
			if car then openCar(car, max, menu) end
		end,
		onClose = function(menu)
			if keysMenu == menu then keysMenu = nil end
		end,
	})
end

-- Players next to the owner (ids only): the key goes to the one he picks.
function Ui.players(plate, list)
	if type(plate) ~= 'string' or type(list) ~= 'table' then return end
	local elements = {}
	for _, entry in ipairs(list) do
		local id = type(entry) == 'table' and math.tointeger(tonumber(entry.id))
		if id then
			elements[#elements + 1] = {
				label = Ui.text('player_entry', { id = id }), value = id, icon = 'person',
				rightLabel = ('%.1f m'):format((tonumber(entry.dm) or 0) / 10),
			}
		end
	end
	if #elements == 0 then elements[1] = { label = Ui.text('no_players'), value = 'none', disabled = true } end
	Menu.open({
		id = 'opx_vehiclekeys_players', title = Ui.text('give_key'), subtitle = plate,
		parent = isOpen(carMenu) and carMenu or nil, elements = elements,
		onSelect = function(element, menu)
			if type(element.value) ~= 'number' then return end
			menu:close()
			TriggerServerEvent('opx_vehiclekeys:give', plate, element.value)
		end,
	})
end

return Ui

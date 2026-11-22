# opx_vehiclekeys

Vehicle keys: the owner locks and unlocks his car, lends keys to other characters and takes them back, switches the engine and opens the trunk. Key holders and staff find the car open; everybody else is kept out.

## Install
- Needs: `opx_core`, `opx_menu`. Load after them (and after the inventory provider and `opx_target` if used: trunk and eye options).
- Creates its table at start (MySQL, same database as opx_core).
- opx_core `config.lua`: `Config.providers.vehiclekeys = 'opx_vehiclekeys'` (shipped default).
- ACL: grant `command.opx_vehiclekeys` to staff who should hold a key to every car.
- Temporary keys (rentals, test drives) are lost when opx_vehiclekeys restarts.

## In game
- `U` (rebindable): lock / unlock the car you sit in, else the nearest car you hold a key for.
- `/vehicle`: vehicle menu: lock, engine (driver seat), trunk (on foot), keys (give to a nearby player, take back).
- Eye (with a target provider): Lock / Unlock and Trunk on vehicles, Give a vehicle key on a person.

## Config
`config.lua`: `keys`, `maxHolders`, `engine`, `trunk` (size, `ownedOnly`). Everything else is commented in the file.

## For developers
Provider of the `vehiclekeys` slot: a replacement implements the exports in `types.lua`.
- `HasKey(source, vehicleId)` → boolean
- `GiveKey(source, vehicleIdOrPlate, { temporary? })` → `true` | `false, reason`
- `RemoveKey(sourceOrCitizenId, vehicleIdOrPlate)` → `true` | `false, reason`
- `GetKeyHolders(plate)` → citizen ids
- `SetLocked(vehicleId, locked)` / `IsLocked(vehicleId)`
- Events: `opx:vehiclekeys:lockChanged`, `opx:vehiclekeys:keyGiven`, `opx:vehiclekeys:keyRemoved`.
- Full contract: `types.lua`.

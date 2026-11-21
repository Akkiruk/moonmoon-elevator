# Hub <-> cab protocol (rednet, protocol name "mmlift")

Cars are named "A" (Moon-Moon's original position) and "B" (the mirror, on the left from inside the cab looking out). Every message is a table with `type` and `car`.

## Cab -> hub
- `{type="pos", car, y, t}`, about 10 times a second: y is the cab computer's `gps.locate()` height. `t` is `os.epoch("utc")`. If GPS fails, send `{type="pos", car, y=nil, err="nogps"}`. The hub treats a car with no fresh position (more than 0.5 s old) as faulted and brakes it.
- `{type="hello", car}` at boot. The hub answers with a full `state`.

## Panel computer -> hub (the cab's touchscreen button panel; design change 2026-11-20)
Each car has a small panel computer behind a tall touch monitor on the cab's side wall, in place of the old blank circuit boards. The keycard reader is right next to it, read as a redstone input.
- `{type="call", car, floor}`: a floor button was pressed. The hub decides whether it is accepted (keycard window, lockdown, fire, inspection) and answers with `panel`.
- `{type="door", car, cmd}`: "open" or "close" pressed.
- `{type="alarm_button", car}`: the alarm button was pressed.
- `{type="keycard", car}`: a valid card was swiped (rising edge of the reader's redstone). The hub then allows L1/L2 for 10 seconds, unless lockdown is on.
- `{type="hello", car, role="panel"}` at boot.

## Hub -> panel computer
- `{type="panel", car, lit={floor=true,...}, keycard_window=bool, locked={floor=true,...}, mode}`: which buttons glow (registered stops), whether L1/L2 are temporarily allowed, which buttons are dead (lockdown, fire, inspection), and the mode, for the panel's banner. Sent on every change and at least once a second.

Door sensors (an AP block reader beside the car door, on the cab computer's network), the car door drive and the inspection controls on the cab top: see HARDWARE.md. The cab computer reports the door state as `{type="door_state", car, open=bool, ok=bool}` (ok=false means the reader failed or returned nonsense, which the hub treats as a sensor fault).

## Landing computers (one per landing, design change 2026-11-20)
Each landing has its own computer with two monitors: the indicator above the door and a touch call panel (up/down). The hub doesn't draw any landing monitor and doesn't read hall buttons from relays anymore. The landing doors themselves still open from the hub: a relay output per floor feeds a Redstone Link transmitter in the machine room, the receiver sits under the landing door.

Landing -> hub:
- `{type="hall", floor, dir}`: up or down touched. `floor` is the floor name. The hub ignores calls it won't take (fire service, L1/L2 in lockdown, up at the top, down at the bottom).
- `{type="hello", role="landing", floor}` at boot. The hub answers with that floor's `landing` messages.

Hub -> landing, one message per car per floor, on every change and at least every 2 s (broadcast):
- `{type="landing", floor, car, carFloor, dir, doors, lantern, up, down, mode, outOfOrder}`
  - `carFloor`: the floor the car is at or passing; `dir`: its travel direction while moving, else nil
  - `doors`: the car's doors, as in `state`
  - `lantern`: "up" or "down" while the car is stopped (or arriving) at this floor and will leave that way, else nil
  - `up`, `down`: hall calls registered at this floor, to light the buttons
  - `mode`: the car's mode, as in `state` (fire modes show Fire Service, inspection shows Maintenance)
  - `outOfOrder`: show "Out of Order" instead of the car. In lockdown L1 and L2 keep showing the trapped car (false hope) and the other floors show Out of Order; an emergency or a fault shows it everywhere.

## Hub -> cab
- `{type="state", car, ...}` on every change, and at least once a second:
  - `floor`: the floor name ("L1", "L2", "P3", "P2", "P1", "G", "2"-"6") the car is at or passing
  - `dir`: "up", "down" or nil
  - `doors`: "open", "opening", "closing" or "closed"
  - `mode`: "normal", "inspection", "fire_recall", "fire_hold", "firefighter", "lockdown_trapped", "out_of_order", "emergency" (cable failure or governor trip, on emergency power)
  - `message`: an optional short line for the cab display ("Doors closing", "Out of Order", "Fire - exit at G")
  - `next`: the next stop, if any
- `{type="chime", car, count}`: 1 = going up, 2 = going down. Play it on arrival, before the doors open.
- `{type="alarm", car, on}`: the cab alarm sounds while on.
- `{type="music", car, cmd}`: "play", "duck" (pause while chiming or alarming), "resume" or "stop". Music stops in fire, emergency and lockdown modes.

## Floors
Bottom to top: L1, L2, P3, P2, P1, G, 2, 3, 4, 5, 6 (indexes 1-11). L1 and L2 are the keycard and lab floors. G is the fire recall floor. A car is level at a floor when its GPS height = that floor's threshold top + 3.00. The table of threshold tops lives in the hub's config (66, 72, 86, 91, 96, 105, 109, 113, 117, 121, 125 in the test build).

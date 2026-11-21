# Requirements (from Moon-Moon, collected 2026-11-19 and 2026-11-20)

Goal: work as much like a real elevator as possible. Creative parts are fine, but hide creative motors and power so it still looks good.

## Layout
- Two elevators side by side: the second is directly to the left of the first when standing in the cab looking out. Only the first is in the test world, so the second is built as a mirror of it.
- 11 landings per shaft, as built (the "13" was a mistake). Floor names, bottom to top: L1, L2, P3, P2, P1, G, 2, 3, 4, 5, 6. L1 and L2 are the keycard floors, P3-P1 are parking, G is the ground floor and 2-6 are offices.
- The cab already has a button panel with indicator lights; wire that rather than adding a touch screen.
- Hall calls: an up button and a down button at each landing, like a real elevator (one only at the top and bottom landings).
- Fire reset key position: our choice. Chosen: a key switch at the G lobby (where Phase I recall sends the cars), as on real elevators.
- The two floors with white terracotta are access-controlled (keycard). Above them are parking floors. Sandstone and up are above-ground offices. The ground floor is "G".

## Computers
- Hub: the machine-room computer at the top of the hoistway, with the monitor there, runs both cars (queue, dispatch, motors, doors).
- Cab-top computer on each car: monitoring, the cab monitor display, chimes, and elevator music (the red_exp "Sins" disc; built in cab/music.lua).
- A small plaque monitor in each cab, above the control panel: capacity, brand, model and the other things you would see on a real elevator plaque.
- The player detector and keycard reader stay where they are in the cab and connect through modems (space and balance).

## Behaviour
- Hall calls go to the closer car. A car serves stops in its direction of travel, then reverses.
- Chime once going up and twice going down (the bottom floor always once, the top floor always twice).
- Doors stay open for a minute. A hall call at that floor extends that. Door-open reopens them and restarts the minute.
- Interlock: the hub refuses to move a car unless its doors read closed. If door detection fails or can't tell, it counts as open and the car does not move.
- Blocked doors (player detector) reopen and retry. 3 failed closes in a row, or 3 door-open presses, set off the cab alarm.
- With no stops left, a car closes its doors and waits at its floor.
- The basement (access-controlled) floors need a SecurityCraft keycard: swipe in the cab, then press the floor.
- Speed governor: brake if the car goes too fast. Cutting the motor is acceptable, and a physical brake as well would be appreciated.
- Maintenance (inspection) mode: controls on top of the cab. When switched on, they give manual up and down to the console and the car stops answering calls.
- Fire service:
  - Phase I: when the fire alarm goes off, clear the queue, send all cars to G and lock them out there.
  - Reset: a way to return to normal once the alarm is off.
  - Phase II: a locked firefighter override switch in the cab lets firefighters run the car during the fire shutdown.
  - The fire alarm reaches the hub as a redstone signal over Create Redstone Links (wireless redstone). Make it realistic: recall on the first signal, and stay locked out until the alarm clears and someone resets it at the hub.

## Delivery
- The finished world goes back to Moon-Moon, and they copy the computer files into their main world themselves.

## Hardware facts found in game (2026-11-20, their Flat Test World)
- The creative motor is a CC peripheral (Create_CreativeMotor: setGeneratedSpeed and getGeneratedSpeed). Their directional gearshift needs the lever at 0,132,-6 on to pass drive. With that, the motor speed sign picks the direction, and 0 holds the car.
- The car (Sable sub-level 1351c4d8, mass 65.5) and the counterweight (47f51214, mass 76) hang on simulated rope winches on one gearbox network, turning in opposite directions.
- In the world as sent, the counterweight had dropped to the bottom with a slack rope. It was fixed by locking it at y=125, reeling its winch in, and unlocking it.
- A computer on the car keeps running while the car moves. The car computer only sees the monitor, wireless modem and speaker.
- Use `sable info <uuid>` for live positions. `find_all_sub_levels` reads stored positions, which are stale. `sable paused` with no argument toggles.

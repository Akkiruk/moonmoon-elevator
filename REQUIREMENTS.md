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
- A small plaque monitor in each cab, above the control panel: capacity, brand, model and the other things you would see on a real elevator plaque. The text is ours to choose (sensible defaults), e.g. "MOONLIFT ELEVATOR CO.", model ML-11 Traction, Car A or B, rated load 1600 kg / 21 persons, rated speed, serial number, last inspection and next due, and "In case of fire, use stairs".
- The player detector and keycard reader stay where they are in the cab and connect through modems (space and balance).

## Behaviour
- Hall calls go to the closer car. A car serves stops in its direction of travel, then reverses.
- Chime once going up and twice going down (the bottom floor always once, the top floor always twice).
- Doors stay open for a minute. A hall call at that floor extends that. Door-open reopens them and restarts the minute.
- Interlock: the hub refuses to move a car unless its doors read closed. If door detection fails or can't tell, it counts as open and the car does not move.
- Blocked doors (player detector) reopen and retry. 3 failed closes in a row, or 3 door-open presses, set off the cab alarm.
- With no stops left, a car closes its doors and waits at its floor.
- The basement (access-controlled) floors need a SecurityCraft keycard: swipe in the cab, then press the floor.
- Lab lockdown: a second Create Redstone Link input. While it is on, L1 and L2 (the lab floors) cannot be reached: keycard plus floor button does nothing, and the hall calls on L1 and L2 do nothing. All other floors work normally. When the signal goes off, it returns to normal. Pending L1/L2 stops are cancelled when lockdown starts. A car that is at L1/L2 when lockdown starts is trapped there (Moon-Moon, 2026-11-20). That car's floor indicator panels on the unaffected floors show "Out of Order", while on L1 and L2 they keep showing it at its floor, giving false hope. A car that is departing L1/L2, or anywhere between L2 and P3, when lockdown starts clears its queue and stops where it is. In his words, lockdown means the whole lab complex is sealed: the security doors close, the elevators refuse those floors, and everyone below is written off. Note: L1 and L2 have no stairwell, by design.
- Cab floor indicator: the floor number, plus whatever else we choose (our call).
- Cable failure: the monitoring computer on top of the car (or a dedicated one) detects a winch cable failure, applies emergency brakes, and switches the elevator to emergency power.
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
- The jam: the car door's two piston extension poles stuck out into the shaft's east wall (the floor-contact column) for the full height. tools/fix-schematic.py removes them. With the fixed schematic printed at anchor 45,63,-11 (car 7ccf5c6e, counterweight e1ea62ed, ropes attached with create_submarine:steel_cable), the car runs the full shaft, the counterweight moves opposite, it holds anywhere at 0 RPM, and the floor contacts light as the car passes.
- Travel math: about 2.5 blocks per winch revolution (blocks/s = 2.5 x RPM / 60), measured at 16, 32 and 64 RPM. Level stop: car position (sable "Position" y) = top of the block in front of that floor's door + 1.25. Confirmed flush by eye at L1, L2 and P3 (2026-11-20). Don't assume a fixed spacing between floors; read each floor's threshold block. Threshold tops in this build: L1 66, L2 72, P3 86, P2 91, P1 96, G 105, 2 109, 3 113, 4 117, 5 121, 6 125, so the stops are 67.25, 73.25, 87.25, 92.25, 97.25, 106.25, 110.25, 114.25, 118.25, 122.25 and 126.25.
- Shaft B's landing doors were removed during testing (for access) and must be put back from the schematic.
- Live car position in game: CC GPS works from the moving car. The car computer's gps.locate() height is Sable position + 1.75, accurate to about 0.005 block (gps rounds to 0.01). So a car is level at a floor when its GPS height = threshold top + 3.00. This needs 4 GPS host computers with wireless modems near each shaft (test set: ids 5-8 at 38,140,-22 / 62,140,-22 / 50,150,6 / 50,100,-30). Modems on top of a computer need facing=down.
- Create Redstone Links: place with the frequency in the block data (setblock ...{FrequencyFirst:{id,count},FrequencyLast:{id,count}}); `data merge` afterwards changes the saved data but not the live frequency. A link is a transmitter until wrenched (or sneak-right-clicked) into receive mode; setblock with receiver=true leaves it broken. A link with empty slots seems to hear every channel. Tested: transmitter -> receiver on the hub relay -> computer reads it (relay.getInput).
- Brake: create_connected:brake in place of the shaft between the car winch and its gearbox (test: 48,132,-7). Powered, it holds the car even with the motor driving (tested at -32 RPM); unpowered, drive passes through. Wire it fail-safe: a redstone torch keeps it on unless the hub sends "release".
- Redstone Links work from the moving car: a transmitter inside car B (plot space) reached the hub receiver.
- Fresh copycat sliding doors open on redstone; the ones from the save don't respond (stale state), so replace them.
- Never leave a motor running unattended: with the car or counterweight at an end stop, the winch pays out slack rope. Timed moves must stop the motor inside the computer.
- Use `sable info <uuid>` for live positions (`sable info @e` lists all). `find_all_sub_levels` reads stored positions, which are stale. `sable paused` with no argument toggles.

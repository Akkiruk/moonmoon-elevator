# Hardware interface (design v2, 2026-11-20)

How the software sees the build. Everything here was proven in game unless it says "untested". The controller is built in the emulator against exactly these names and signals.

## Per car
| Thing | Block | Who reads or drives it | How |
|---|---|---|---|
| Winch motor | create:creative_motor (Create_CreativeMotor) on the gearshift input; gearshift lever locked on | hub | `setGeneratedSpeed(rpm)`: + is up for this build, 0 stops. About 2.5 blocks per revolution |
| Brake | create_connected:brake on the car winch line, held on by a redstone torch | hub | relay output "release" (on = brake off). Fail-safe: no signal means braked |
| Live height | the cab computer's gps.locate() | cab, then hub | rednet `{car, y, t}` about 10 times a second. Level when y = threshold top + 3.00 |
| Floor contacts | create:redstone_contact at each landing, at threshold height | hub | relay inputs. Used as checkpoints and as a cross-check on GPS |
| Car door | a double copycat sliding door in the 2x2 doorway at the front of the cab (car-local x1-2, y1-2, z0), stone-pillar look. Tested: power under one half opens both, removing it closes both. Replaces Moon-Moon's piston door, whose extension poles jammed the car against the shaft wall | hub | a Redstone Link receiver on the car powering the floor block under the door (untested link part). On = open; no signal = closed |
| Car door sensors | OPEN QUESTION: a sliding door can't report its own state. Options: (a) an AP block reader next to the door, on a short cable to the cab computer, which reports over rednet; (b) trust the commanded state and use the hub's player detector for obstruction, which can't detect a stuck door | hub | to decide |
| Landing doors | fresh copycat sliding doors (the saved ones are stale) | hub | relay output per landing, on = open |
| Cab button panel | a tall advanced touch monitor on the cab's right wall (in place of the blank circuit boards), run by a small panel computer hidden in the wall behind it (shaft side) with a wireless modem | panel computer, then hub | rednet (PROTOCOL.md): call, door, alarm_button; the hub answers with lit and locked buttons |
| Inspection controls | switch plus up/down buttons on the cab top, and the firefighter key switch in the cab | hub | Redstone Links from the car |
| Keycard reader | securitycraft:keycard_reader, already in the wall next to the panel computer | panel computer | redstone input on the rising edge, sent to the hub as keycard |
| Doorway detector | one advancedperipherals:player_detector at the hub | hub | `getPlayersInCoords` over the doorway box of the floor the car is at. No wiring to the car |
| Cab display | the existing 2x1 advanced monitor under the cab computer | cab | floor, direction, door state, messages ("Out of Order", fire, inspection) |
| Plaque | a small monitor in the cab above the panel, on its own tiny computer | plaque computer | static text, drawn once |
| Speaker | the speaker on the cab computer (audibility untested) | cab | chimes and music (cab/music.lua) |

## Hub-wide
- Hall buttons: an up and a down button at each landing (only one at the ends), relay inputs.
- Landing indicators: the 2x1 monitors above each landing door (7 exist, 4 to add per shaft), on the hub's wired network with a cable hidden in the shaft wall. They show the car's floor and arrow, the arrival lantern, and Out of Order / Fire Service / Maintenance.
- Fire alarm and lab lockdown: Create Redstone Link receivers on the hub relays. Frequencies: fire = red dye + redstone torch; lockdown = (to pick).
- Fire service reset: a key switch at the G lobby, as a relay input.
- Hub control panel: the monitor at the top of the hoistway.
- GPS hosts: 4 computers with wireless modems, out of sight around the top of the shafts.

## Link frequency plan
Every link signal gets its own pair of frequency items, one table per car. Place each link with its frequency in the block data, then wrench the receivers. See REQUIREMENTS.md, "Hardware facts".

## Still untested
- The door drive on the car: a creative motor plus a gearshift switched by link.
- The car door's closed and open contact pairs.
- Whether the cab speaker can be heard from the moving car.
- Whether the AP player detector's getPlayersInCoords is fast enough for the door-close check.

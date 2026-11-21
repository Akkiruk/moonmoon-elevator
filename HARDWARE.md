# Hardware interface (design v2, 2026-11-20)

How the software sees the build. Everything here was proven in game unless it says "untested". The controller is built in the emulator against exactly these names and signals.

## Per car
| Thing | Block | Who reads or drives it | How |
|---|---|---|---|
| Winch motor | create:creative_motor (Create_CreativeMotor) on the gearshift input; gearshift lever locked on | hub | `setGeneratedSpeed(rpm)`: + is up for this build, 0 stops. About 2.5 blocks per revolution |
| Brake | create_connected:brake on the car winch line, held on by a redstone torch | hub | relay output "release" (on = brake off). Fail-safe: no signal means braked |
| Live height | the cab computer's gps.locate() | cab, then hub | rednet `{car, y, t}` about 10 times a second. Level when y = threshold top + 3.00 |
| Floor contacts | create:redstone_contact at each landing, at threshold height | hub | relay inputs. Used as checkpoints and as a cross-check on GPS |
| Car door drive | hidden creative motor -> gearshift -> piston on the car (untested) | hub | Redstone Links to the car: "door open" and "door close" |
| Car door sensors | two contact pairs on the car: closed, fully open (untested) | hub | Redstone Links from the car. Neither or both for too long = sensor fault, so the car does not move |
| Landing doors | fresh copycat sliding doors (the saved ones are stale) | hub | relay output per landing, on = open |
| Cab buttons | floor buttons (11), open, close, alarm, firefighter key switch; inspection switch and up/down on the cab top | hub | Redstone Links from the car, one frequency each |
| Button lights | lamps behind the panel, one per floor button | hub | Redstone Links to the car |
| Keycard reader | securitycraft:keycard_reader (outputs redstone on a valid card) | hub | Redstone Link from the car |
| Doorway detector | one advancedperipherals:player_detector at the hub | hub | `getPlayersInCoords` over the doorway box of the floor the car is at. No wiring to the car |
| Cab display | the existing 2x1 advanced monitor under the cab computer | cab | floor, direction, door state, messages ("Out of Order", fire, inspection) |
| Plaque | a small monitor in the cab above the panel, on its own tiny computer | plaque computer | static text, drawn once |
| Speaker | the speaker on the cab computer (audibility untested) | cab | chimes and music (cab/music.lua) |

## Hub-wide
- Hall buttons: an up and a down button at each landing (only one at the ends), relay inputs.
- Hall lanterns and indicators: the landing monitors (already in the build), relay outputs or monitors over a wired network.
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

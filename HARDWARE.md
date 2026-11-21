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

## Shaft physics (learned the hard way, 2026-11-21)
- **Rope length.** A rope winch stops paying out once its rope adds up to more than `max_rope_range` in `config/simulated-server.toml` (default 40); it can still reel in. Slack rope bunches up and hardly counts, so a rope that has gone slack can end up longer than that, which is how the car reached L1 before the setting changed. The rope seen stopping at 40 was the counterweight's. L1 is about 60 blocks under the winches, so a taut rope probably needs `max_rope_range = 80.0` to get there; not yet tested with a fresh rope on 40. The test instance has 80.
- **Rails must be slippery.** Sable gives ice, packed ice and blue ice zero friction. Lapis or stone posts sitting in the car's notches held it so hard that it climbed at 0.1 blocks/s and rose on its own while braked. The guide posts at x 45 and 49 (z -5), the east wall the car touches (x 51, z -9 and -8) and the counterweight slot are packed ice now.
- **Counterweight slot.** The counterweight is 3x1. It hangs in a 3x1 packed-ice slot (x 46-48, z -3). In the old 2-deep, open-sided slot it tipped, swung out under the ground line and jammed. Both ropes are independent: the counterweight doesn't help lift the car, it only moves opposite it because both winches share the drive.
- **Hang the car under its rope.** The car's centre of mass sat 0.4 blocks off the rope, so it leaned on the landing wall. Four lead blocks under the floor (back and back-left) bring it to within 0.05.
- **Top clearance.** Nothing on the car roof may stick up past the rope connector layer: the inspection station's modem on top of its computer stopped the car 3/16 short of floor 6. It's on the computer's side now.
- **Ice behind the landing face too.** The car is exactly as deep as the shaft, so it rubs the front wall (the landing side). With quartz, lapis and stone there, climbs were stick-slip: the car sat still for up to 5 s, then surged at 10-25 blocks/s. Fix, tested 2026-11-21: move the whole front wall (doors, monitors, landing computers, links) back one block and line the old front wall layer with packed ice, leaving the 2x2 doorway open with an ice floor block under it. Climbs then run at the commanded 2.5 blocks/s with no surges (L1 to 6 in 23 s instead of 40). The hub's doorway box has to cover the extra block (config.lua, doorways z -11 to -9 in the test shaft).
- **Or skip the ice with the datapack.** Friction is a per-block Sable property, so `datapacks/elevator-slide` (copy it into the world's `datapacks` folder) sets it to 0 for every block in the front wall and on the car: quartz, terracotta, lapis, diorite, the lamps, computers, monitors, modems, copycats, links, contacts and so on. That lets the front wall go back to its own blocks with no ice layer. It only changes physics contacts, walking is normal, but it's world-wide: any ship touching those blocks slides too. Plain stone, dirt and grass are left out on purpose. Add a block by copying one of the files and changing `selector`. Check a block in game with Sable's `PhysicsBlockPropertyHelper.getFriction`.

## Link frequency plan
Every link signal gets its own pair of frequency items, one table per car. Place each link with its frequency in the block data, then wrench the receivers. See REQUIREMENTS.md, "Hardware facts".

## Still untested
- The door drive on the car: a creative motor plus a gearshift switched by link.
- The car door's closed and open contact pairs.
- Whether the cab speaker can be heard from the moving car.
- Whether the AP player detector's getPlayersInCoords is fast enough for the door-close check.

# Elevator project: status and plan (2026-11-20)

The full requirement list is in REQUIREMENTS.md. This file covers what is done, what is broken, the design, and the order of work.

## Done
- Test copy of the pack: `curseforge\minecraft\Instances\Create Industrial Espionage`, matched to Moon-Moon's mod list:
  - CC:Tweaked 1.120.2, Advanced Peripherals 0.7.62b, ccgraphics, cc-audio-expand, the CEE add-on and Unicode Support added.
  - World-Wide Power Grid, PMWeather and two mods that need PMWeather set aside.
  - DebugBridge on port 9876. The game launches through PortableMC.
- The emulator supports CC:Tweaked 1.120.2 (craftos-agent 06b6e5d). The full suite passes. Not yet in the public release.
- Music player (cab/music.lua) with the Sins track converted to DFPWM; 7 emulator tests pass.
- Proven in game:
  - A computer on the moving car keeps running.
  - The creative motor is a CC peripheral: the computer sets its speed and direction, and 0 holds.
  - The counterweight winch works once its rope is taut.

## Broken in the world as sent
- The car will not lift, even with its rope taut and the motor at 256 RPM. Something holds it, probably a wedge in the shaft or at the bottom landing.
- Both ropes were badly slack. The counterweight lay at the bottom; it should always be opposite the cab. The counterweight is fixed in the current test copy.
- Power Grid wires hang into the air with nothing attached, and there are missing blocks around the machine room.
- The creative battery is not needed (Moon-Moon added it for a computer that no longer needs it).
- Two landings have no floor contact: the ones at doors y=91 and y=121. Contacts sit one block below each door, except at y=86.
- Only one hall call button in the whole shaft (the bottom landing). No cab buttons yet; the control panel is not wired.
- The second elevator is not in this world.

Decision (owner, 2026-11-20): rebuild the mechanical parts in our test world. Keep it as close to the original look as we can, without depending on what came through the save.

## Design
- Hub computer (machine room, with the top monitor):
  - Runs both cars: queue, dispatch and doors.
  - Drives each car's creative motor directly (speed sign = direction, 0 = stop), with the gearshift locked in drive or replaced by a plain shaft.
  - Reads the floor contacts, the hall buttons and the fire alarm through Redstone Relays on a wired modem network, hidden behind the walls.
  - The top monitor is the control panel: where each car is, the call queue, fire and maintenance state, and the reset.
- Cab computer (top of each car):
  - Reads the cab buttons, door sensors, player detector and keycard reader through wired modems on the car.
  - Shows floor and direction on the cab monitor, plays the chimes and runs the music.
  - Talks to the hub over wireless rednet.
- Plaque: a small monitor in each cab above the control panel, run by the cab computer, with static text (brand, capacity, and so on).
- Doors:
  - Landing doors open on redstone from the hub's relays.
  - The car door is the mechanical piston on the car.
  - Door state comes from two contact pairs: closed and fully open. Neither lit for too long, or both lit at once, means the sensor has failed.
- Interlock: the hub only moves a car when its door reads closed. A failed or unknown sensor counts as open.
- Speed governor: time the car between floor contacts. Too fast means stop the motor, brake, alarm, and park at the next floor. A physical brake (a Create clutch or brake on the winch shaft, locked whenever the car should be still) is extra.
- Fire service: the alarm signal arrives over a Create Redstone Link receiver at the hub.
  - Phase I: clear calls, send all cars to G, open the doors and lock out.
  - Reset at the hub only after the alarm signal is off.
  - Phase II: the firefighter key switch in the cab.
- Maintenance: a switch plus up and down buttons on the cab top. While it is on, the car ignores the queue and moves only while a button is held, slowly.
- Creative motors and power stay hidden in the machine room or behind walls.

## Still to verify in game (before the controller is final)
1. A wired modem network on the physics car reaches the player detector and keycard reader.
2. What drives the car door: the Electro Energetics motor on the car, and how a computer controls it.
3. The landing doors open and close on redstone, and what signal they want.
4. The car's contact lights the shaft contact at each landing, with the car level.
5. A Redstone Link receiver feeds a relay for the fire alarm.
6. A brake or clutch on the winch shaft holds the car.

## Plan
1. Rebuild elevator A mechanically:
   - Re-seat the car and counterweight, check full travel bottom to top, and get floor contacts at all 11 landings.
   - Tidy the wiring, remove the battery, and hide the creative parts.
   - Done when: the computer can send the car to every floor and it stops level.
2. Run the in-game checks above and write down the hardware interface: every relay side, peripheral name and signal.
3. Build the controller in the emulator against a simulated shaft:
   - hub: queue, dispatch, doors, interlock, governor, fire, maintenance
   - cab: display, plaque, chimes, music, keycard, buttons, firefighter switch
   - tests for every behaviour in REQUIREMENTS.md
   Agents can split the hub and the cab once the interface is fixed.
4. Wire elevator A in the world, install, and test end to end in game.
5. Build elevator B as a mirror on the left. Test both cars together, including dispatch.
6. Setup wizard: it learns the wiring in Moon-Moon's main world by walking him through presses and rides.
7. Handoff: send the world back with a short guide on copying the computer files and running setup.

## Decisions
- Settled 2026-11-20:
  - Floors are L1, L2, P3, P2, P1, G, 2, 3, 4, 5, 6.
  - Use his existing cab button panel with indicator lights.
  - Up and down hall buttons.
  - Fire reset is a key switch at the G lobby (our choice).
- Still open:
  - Plaque text (brand, capacity, model). If he doesn't say, use sensible defaults.
  - Music delivery: the full track (1.03 MB) is over the 1 MB computer disk. Raise the disk limit in the world's config (simplest) or host it at a URL.
  - Whether the cab speaker is heard from a physics sub-level. Test it once the car moves; fall back to landing speakers if not.

## Housekeeping
- Test leftovers in the current test world: a creative motor at 1,132,-7 and a probe computer (id 2) at 1,133,-7, with the lever at 0,132,-6 on.
- The older copy "Flat Test World (motor tests)" can be deleted.
- Release the emulator's 1.120.2 support in the public export with the next update.

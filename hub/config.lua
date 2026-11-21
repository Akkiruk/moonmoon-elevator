-- Hub configuration: floors, timing, motion, and where every signal is wired.
--
-- A signal is { "<peripheral name>", "<side>" }, for example { "redstone_relay_3", "left" }.
--   * Sides are the relay's own: "top", "bottom", "left", "right", "front", "back".
--   * Use "computer" as the peripheral name for the hub computer's own sides.
--   * Add a third field to read or drive one colour of a bundled cable: { "redstone_relay_3", "left", colors.red }.
--   * Add invert = true for a signal that is on when the block reads off: { "redstone_relay_3", "left", invert = true }.
--   * nil (or leaving the entry out) means "not wired": inputs read off, outputs go nowhere. The control panel lists
--     how many signals are unwired, so a typo shows up at once.
--
-- The names below are placeholders laid out in order (redstone_relay_0, _1, ...). When the world is wired, place the
-- relays, read each one's network name (right-click the wired modem next to it) and fill in the names and sides here.
-- Floors are numbered 1-11 bottom to top in every list: L1, L2, P3, P2, P1, G, 2, 3, 4, 5, 6.

local function S(name, side, colour) return { name, side, colour } end

local C = {}

C.protocol = "mmlift"
C.floors = { "L1", "L2", "P3", "P2", "P1", "G", "2", "3", "4", "5", "6" }
-- Top of the block in front of each landing door (the threshold). A car is level when its GPS height is that + levelOffset.
C.thresholds = { 66, 72, 86, 91, 96, 105, 109, 113, 117, 121, 125 }
C.levelOffset = 3.00
C.recallFloor = "G"            -- fire Phase I recall floor
C.keycardFloors = { "L1", "L2" } -- need a keycard swipe in the cab first
C.labFloors = { "L1", "L2" }     -- sealed during lab lockdown
C.lockdownBoundary = "P3"        -- a car below this floor's stop when lockdown starts stops where it is

C.carOrder = { "A" } -- add "B" once the second shaft is built; its entry below is ready

-- Hub peripherals.
C.modem = nil                    -- wireless modem side or name; nil = the first wireless modem found
C.monitor = "front"              -- the control panel at the top of the hoistway
C.monitorScale = 0.5
C.detector = "left"              -- AP player detector for the doorway check (getPlayersInCoords)

-- Hub-wide inputs (Create Redstone Link receivers and the G lobby key switch, on relays).
C.fireAlarm = S("redstone_relay_1", "top")      -- link: red dye + redstone torch
C.lockdown  = S("redstone_relay_1", "front")    -- link
C.fireReset = S("redstone_relay_1", "back")     -- key switch at the G lobby

-- Hall calls come from the landing computers over rednet (PROTOCOL.md), so there are no hall buttons here.

-- Per car. A is Moon-Moon's original shaft; B is the mirror on its left (seen from inside the cab).
C.cars = {
  A = {
    motor = "Create_CreativeMotor_1",
    motorSign = 1,                                -- +RPM moves the car up; -1 if a shaft is built the other way
    brakeRelease = S("redstone_relay_2", "left"), -- on = brake off (a torch holds the brake when this is off)
    doorOpen     = S("redstone_relay_2", "right"), -- link to the car door: on = open
    -- Inspection and the firefighter key come over rednet from the roof station and the cab panel. These relay
    -- inputs still work if someone wires a physical switch instead: inspect, inspectUp, inspectDown, firefighter.
    -- Floor contacts are optional: GPS is the position. Any contact listed here is checked against GPS (passing
    -- its floor without it lighting, or it lighting with the car far away, is a fault); floors left out are not.
    -- e.g. contacts = { [1] = S("redstone_relay_6", "top"), [6] = S("redstone_relay_6", "back") },
    contacts = {},
    -- Decorative counterweight on its own winch and motor (not on the car's drive), with a computer riding on it
    -- (counterweight/cw.lua) that reports its height. top / bottom: its GPS height with the car at the bottom stop /
    -- the top stop. nil = no counterweight control.
    counterweight = nil, -- e.g. { motor = "Create_CreativeMotor_2", motorSign = 1, top = 128, bottom = 69 },
    -- Steadying rope from a winch on the pit floor up to the car's underside, on its own motor. It pays out as the
    -- car climbs and reels in as it comes down, plus `reelRpm` of steady reel-in; the winch stops reeling in once
    -- its rope is stretched (simulated's max_rope_winch_stretch_allowed), which keeps it taut without a tug of war.
    -- motorSign: the sign that pays out. nil = no bottom rope.
    tension = nil, -- e.g. { motor = "Create_CreativeMotor_3", motorSign = 1, reelRpm = 4 },
    landingDoors = { -- feeds the Redstone Link transmitter for each landing door, on = open
      S("redstone_relay_3", "top"),   -- L1
      S("redstone_relay_3", "right"), -- L2
      S("redstone_relay_3", "left"),  -- P3
      S("redstone_relay_3", "front"), -- P2
      S("redstone_relay_4", "top"),   -- P1
      S("redstone_relay_4", "right"), -- G
      S("redstone_relay_4", "left"),  -- 2
      S("redstone_relay_5", "top"),   -- 3
      S("redstone_relay_5", "right"), -- 4
      S("redstone_relay_5", "left"),  -- 5
      S("redstone_relay_5", "back"),  -- 6
    },
    -- The doorway box at each landing for the player detector: { x1, y1, z1, x2, y2, z2 } in world coordinates,
    -- filled in below from the thresholds (the door's bottom block). nil = no obstruction check there.
    doorways = {},
  },
  B = {
    motor = "Create_CreativeMotor_2",
    motorSign = 1,
    brakeRelease = S("redstone_relay_10", "top"),
    doorOpen     = S("redstone_relay_10", "bottom"),
    contacts = {},
    landingDoors = {
      S("redstone_relay_13", "top"), S("redstone_relay_13", "bottom"), S("redstone_relay_13", "left"),
      S("redstone_relay_13", "right"), S("redstone_relay_13", "front"), S("redstone_relay_13", "back"),
      S("redstone_relay_14", "top"), S("redstone_relay_14", "bottom"), S("redstone_relay_14", "left"),
      S("redstone_relay_14", "right"), S("redstone_relay_14", "front"),
    },
    doorways = {},
    -- thresholds = { ... } -- only if shaft B's landings differ from C.thresholds
  },
}

-- Timing, in seconds.
C.timing = {
  doorDwell = 60,          -- doors stay open this long (a hall call at the floor or door-open restarts it)
  reopenDwell = 4,         -- after a blocked close: wait this long, then try again
  stopDwell = 15,          -- with other floors still to serve, a stop lasts this long
  carCallDwell = 3,        -- a floor button pressed in the cab closes the doors this soon, but not before stopDwell
  doorTravel = 1.5,        -- how long the sliding doors take to move after the door reports its new state
  doorTimeout = 6,         -- a door that does not report the commanded state in this long has failed
  doorStateMaxAge = 2.5,   -- door_state from the cab older than this counts as unknown (the cab sends 1/s)
  doorFaultAfter = 1.0,    -- unknown door state for this long = sensor fault
  posMaxAge = 0.5,         -- a car position older than this counts as lost (PROTOCOL.md)
  brakeLift = 0.3,         -- time between releasing the brake and driving the motor
  keycardWindow = 10,      -- L1/L2 (and the firefighter key) allowed this long after a swipe
  jogTimeout = 0.8,        -- inspection jog stops if the roof station goes quiet this long
  strikes = 3,             -- failed closes, or door-open presses at one stop, before the alarm
  alarmSeconds = 10,       -- the strike alarm sounds this long
  alarmButtonSeconds = 3,  -- one press of the cab alarm button sounds it this long
  messageSeconds = 4,      -- short cab messages ("Swipe keycard first") last this long
  chimeDuck = 2,           -- music ducks this long for a chime
  tick = 0.05,             -- control loop period
  stateEvery = 1,          -- state and panel messages at least this often
}

-- Motion. Speeds in RPM of the winch motor (blocks/s = blocksPerRev x RPM / 60). The motor only takes whole RPM.
C.motion = {
  blocksPerRev = 2.5,
  cruiseRpm = 64,          -- 2.67 blocks/s
  levelRpm = 4,            -- 0.17 blocks/s for the last stretch
  inspectRpm = 8,          -- 0.33 blocks/s while an inspection button is held
  maxRpm = 256,
  accel = 1.5,             -- blocks/s^2 speeding up
  decel = 1.5,             -- blocks/s^2 slowing down
  levelZone = 0.35,        -- blocks from the stop where the car creeps at levelRpm
  stopTol = 0.03,          -- stop when the (lag-corrected) height is this close
  levelTol = 0.0625,       -- level = within 1/16 of a block
}

-- Safety checks.
-- The rope stretches and bounces, so readings must stay out of line for a while before anything trips. The holds and
-- margins come from logged trips in the test shaft: back-bounces up to 0.8 s, downward spikes 0.1 s, and the car
-- sitting still for up to 5.4 s while the rope takes up its stretch leaving L1.
C.safety = {
  governorFactor = 1.6,    -- going down faster than cruise speed x this...
  governorHold = 0.5,      -- ...for this long is an overspeed
  speedMargin = 1.5,       -- blocks/s: falling faster than commanded by this...
  fallHold = 1.0,          -- ...for this long is a cable failure
  parkedMargin = 0.5,      -- the same with the brake on (a braked car that drifts either way)
  stallSpeed = 0.5,        -- blocks/s commanded or more...
  stallDistance = 0.5,     -- ...without moving this far...
  stallTime = 8,           -- ...in this many seconds is a stall (jammed car, frozen GPS, rope paying out into slack)
  speedWindow = 0.3,       -- seconds of GPS history to measure speed over
  cmdWindow = 0.6,         -- seconds of commanded speed history to compare against
  contactWindow = 1.0,     -- blocks: GPS within this of a stop while a contact should light
  contactMustLight = 0.25, -- passing within this of a stop without its contact lighting is a fault
  contactFar = 2.0,        -- a contact lit with GPS further than this from its stop is a fault
}

-- How the counterweight motor chases its spot: rpm per block off, top speed, how close is close enough, and how
-- old a position may be before the motor stops.
C.counterweightControl = { gain = 16, maxRpm = 96, deadband = 0.3, maxAge = 1 }

-- An emergency stop clears itself (then the car levels at the nearest floor) once the car has stood still with a
-- good position for `still` seconds, no sooner than `after` seconds from the stop. More than `max` of those in
-- `window` seconds and it stays stopped until someone presses RESET on the hub panel. nil = always by hand.
C.autoReset = { after = 20, still = 5, stillSpeed = 0.1, max = 3, window = 600 }

-- car A's doorways: two blocks wide (x 46-47), z -10 to -9, from the door's bottom block up two
for i, t in ipairs(C.thresholds) do C.cars.A.doorways[i] = { 46, t, -10, 47, t + 1, -9 } end

return C

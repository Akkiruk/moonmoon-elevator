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
C.monitor = "monitor_0"          -- the control panel at the top of the hoistway
C.monitorScale = 0.5
C.detector = "player_detector"   -- AP player detector for the doorway check (getPlayersInCoords)

-- Hub-wide inputs (Create Redstone Link receivers and the G lobby key switch, on relays).
C.fireAlarm = S("redstone_relay_0", "top")      -- link: red dye + redstone torch
C.lockdown  = S("redstone_relay_0", "bottom")   -- link: frequency to pick
C.fireReset = S("redstone_relay_0", "left")     -- key switch at the G lobby

-- Hall calls come from the landing computers over rednet (PROTOCOL.md), so there are no hall buttons here.

-- Per car. A is Moon-Moon's original shaft; B is the mirror on its left (seen from inside the cab).
C.cars = {
  A = {
    motor = "Create_CreativeMotor_0",
    motorSign = 1,                               -- +RPM moves the car up; -1 if a shaft is built the other way
    brakeRelease = S("redstone_relay_5", "top"), -- on = brake off (a torch holds the brake when this is off)
    doorOpen     = S("redstone_relay_5", "bottom"), -- link to the car door: on = open
    inspect      = S("redstone_relay_5", "left"),   -- cab-top inspection switch (link)
    inspectUp    = S("redstone_relay_5", "right"),  -- cab-top up button (link)
    inspectDown  = S("redstone_relay_5", "front"),  -- cab-top down button (link)
    firefighter  = S("redstone_relay_5", "back"),   -- firefighter key switch in the cab (link)
    -- Floor contacts are optional: GPS is the position. Any contact listed here is checked against GPS (passing
    -- its floor without it lighting, or it lighting with the car far away, is a fault); floors left out are not.
    -- e.g. contacts = { [1] = S("redstone_relay_6", "top"), [6] = S("redstone_relay_6", "back") },
    contacts = {},
    landingDoors = { -- feeds the Redstone Link transmitter for each landing door, on = open
      S("redstone_relay_8", "top"), S("redstone_relay_8", "bottom"), S("redstone_relay_8", "left"),
      S("redstone_relay_8", "right"), S("redstone_relay_8", "front"), S("redstone_relay_8", "back"),
      S("redstone_relay_9", "top"), S("redstone_relay_9", "bottom"), S("redstone_relay_9", "left"),
      S("redstone_relay_9", "right"), S("redstone_relay_9", "front"),
    },
    -- The doorway box at each landing for the player detector: { x1, y1, z1, x2, y2, z2 } in world coordinates.
    -- nil = no obstruction check at that landing.
    doorways = {},
  },
  B = {
    motor = "Create_CreativeMotor_1",
    motorSign = 1,
    brakeRelease = S("redstone_relay_10", "top"),
    doorOpen     = S("redstone_relay_10", "bottom"),
    inspect      = S("redstone_relay_10", "left"),
    inspectUp    = S("redstone_relay_10", "right"),
    inspectDown  = S("redstone_relay_10", "front"),
    firefighter  = S("redstone_relay_10", "back"),
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
  carCallDwell = nil,      -- set (e.g. 5) to shorten the dwell when a floor button is pressed; nil = keep the minute
  doorTravel = 1.5,        -- how long the sliding doors take to move after the door reports its new state
  doorTimeout = 6,         -- a door that does not report the commanded state in this long has failed
  doorStateMaxAge = 2.5,   -- door_state from the cab older than this counts as unknown (the cab sends 1/s)
  doorFaultAfter = 1.0,    -- unknown door state for this long = sensor fault
  posMaxAge = 0.5,         -- a car position older than this counts as lost (PROTOCOL.md)
  brakeLift = 0.3,         -- time between releasing the brake and driving the motor
  keycardWindow = 10,      -- L1/L2 allowed this long after a swipe
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
C.safety = {
  governorFactor = 1.25,   -- trip above cruise speed x this
  speedMargin = 0.5,       -- blocks/s: faster than commanded by this = overspeed; falling faster = cable failure
  speedWindow = 0.3,       -- seconds of GPS history to measure speed over
  cmdWindow = 0.6,         -- seconds of commanded speed history to compare against
  contactWindow = 1.0,     -- blocks: GPS within this of a stop while a contact should light
  contactMustLight = 0.25, -- passing within this of a stop without its contact lighting is a fault
  contactFar = 2.0,        -- a contact lit with GPS further than this from its stop is a fault
}

return C

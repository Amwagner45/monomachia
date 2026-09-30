// Global tuning for the Monomachia simulation.
// All time values are in simulation frames (60 per second) unless noted.

export const FPS = 60;
export const DT = 1 / FPS;

export const HP_MAX = 100;
export const POSTURE_MAX = 100;
export const ULT_HP_THRESHOLD = 25; // % HP at or below which the ultimate unlocks
export const ROUNDS_TO_WIN = 3;

export const ARENA_RADIUS = 11.5; // inner wall radius (m)
export const FIGHTER_RADIUS = 0.42;
export const GRAVITY = 30; // m/s^2 (snappy, game-like)
export const JUMP_CLEAR = 0.3; // feet height above which low attacks miss

// --- Defence ---------------------------------------------------------------
export const PARRY_POSTURE = 16; // "each parry does a consistent amount of posture damage"
/** undefended hits hurt posture more than blocked ones */
export const HIT_POSTURE_MULT = 1.5;
export const PARRY_SPAM_WINDOW = 30; // presses closer together than this are "spam"
export const PARRY_SPAM_PENALTY = 3; // frames removed from the window per spam press
export const PARRY_MIN_WINDOW = 2;
export const GUARD_HALF_ANGLE = 100; // degrees: must roughly face the attacker to block/parry

export const PARRY_RECOIL = 26; // attacker can't act
export const PARRY_RECOIL_GUARD_AFTER = 14; // attacker may block/parry again after this
export const PARRIER_RECOVERY = 7; // parrier is free after this

// --- Posture ---------------------------------------------------------------
export const POSTURE_RECOVER_DELAY = 45; // frames without posture damage before draining
export const POSTURE_RECOVER_STAND = 14; // points / second (full HP, standing, blocking)
export const POSTURE_RECOVER_MOVE = 5; // points / second (full HP, moving, blocking)
export const POSTURE_RECOVER_HP_FLOOR = 0.35; // multiplier at 0 HP
export const DISARMED_POSTURE_RECOVER = 6; // passive drain while disarmed
export const DISARMED_POSTURE_DELAY = 60;
export const DISARMED_STAGGER = 60; // dazed when a disarmed fighter's meter fills
export const DISARMED_STAGGER_RESET = 50; // posture after the daze

// --- Counters --------------------------------------------------------------
export const STOMP_POSTURE = 30;
export const STOMP_STUN = 70;
export const LEAP_POSTURE = 30;
export const LEAP_STUN = 42;
export const EVADE_POSTURE = 15;
export const EVADE_EXTRA_RECOVERY = 40;
export const COUNTER_LUNGE_WINDOW = 45;
export const REDIRECT_POSTURE = 35;
export const REDIRECT_STUN = 50;
export const FLASH_STUN = 60;

// --- Disarm ----------------------------------------------------------------
export const DISARM_STAGGER = 26; // the disarmed fighter reels back
export const PICKUP_RANGE = 1.25;
export const PICKUP_FRAMES = 24;
export const PICKUP_ATTACH_FRAME = 14;

// --- Input -----------------------------------------------------------------
export const INPUT_BUFFER = 8;
export const CHORD_FRAMES = 4; // light+heavy within this = ultimate
export const DOUBLE_TAP_FRAMES = 16;
export const TAP_MAX_FRAMES = 14; // first press of a double-tap must be at most this long
export const DIR_DEADZONE = 0.4;

// --- Charged heavy ---------------------------------------------------------
export const CHARGE_MAX = 150; // 2.5 s: auto-release as a power attack
export const CHARGE_MIN = 18; // below this a released charge is a normal heavy

// --- Movement --------------------------------------------------------------
export const MOVE = {
  runForward: 3.9,
  runStrafe: 3.5,
  runBack: 3.0,
  sprint: 7.2,
  blockSpeedMult: 0.45,
  accel: 38, // m/s^2 toward desired velocity
  decel: 30,
  stepDist: 0.55,
  stepFrames: 8,
  dodgeDist: 2.8,
  dodgeFrames: 16,
  dodgeIFrames: 12,
  dodgeRecovery: 9,
  backstepDist: 2.1,
  backstepFrames: 14,
  backstepIFrames: 10,
  backstepRecovery: 9,
  jumpHeight: 0.95,
  landRecovery: 5,
  turnRate: 14, // rad/s when free
  followWindow: 12, // frames after a dodge/backstep that count for follow-up attacks
  sprintAttackMinFrames: 8,
};

export const DISARMED_MULT = { speed: 1.2, dodge: 1.5, jump: 1.35 };

// --- Ultimates ------------------------------------------------------------
export const ULT_CHOICE_FRAMES = 40;

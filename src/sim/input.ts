// Device-agnostic input as the simulation sees it.
// Keyboards, gamepads and the AI all produce a RawInput each frame; the
// InputTracker turns that into edges, buffered presses, taps and double-taps.

import {
  DIR_DEADZONE,
  DOUBLE_TAP_FRAMES,
  INPUT_BUFFER,
  TAP_MAX_FRAMES,
} from './constants';

export enum B {
  Light = 0,
  Heavy = 1,
  Block = 2,
  Dodge = 3,
  Jump = 4,
  Interact = 5,
  Ultimate = 6,
  Sprint = 7,
}
export const NUM_BUTTONS = 8;

export interface RawInput {
  /** strafe axis: +1 = right */
  mx: number;
  /** forward axis: +1 = toward the opponent */
  my: number;
  /** bitmask of held buttons (1 << B.x) */
  buttons: number;
}

export const emptyInput = (): RawInput => ({ mx: 0, my: 0, buttons: 0 });

export const bit = (b: B) => 1 << b;

/** 8-way direction index: 0 = forward, 1 = forward-right, 2 = right ... 7 = forward-left. -1 = neutral. */
export function dirIndex(mx: number, my: number): number {
  const m = Math.hypot(mx, my);
  if (m < DIR_DEADZONE) return -1;
  const a = Math.atan2(mx, my); // 0 = forward, +pi/2 = right
  return ((Math.round(a / (Math.PI / 4)) % 8) + 8) % 8;
}

export function dirVector(d: number): { mx: number; my: number } {
  if (d < 0) return { mx: 0, my: 0 };
  const a = d * (Math.PI / 4);
  return { mx: Math.sin(a), my: Math.cos(a) };
}

function sameSector(a: number, b: number) {
  if (a < 0 || b < 0) return false;
  const d = Math.abs(a - b) % 8;
  return d <= 1 || d >= 7;
}

export class InputTracker {
  held = 0;
  prevHeld = 0;
  mx = 0;
  my = 0;
  dir = -1;
  prevDir = -1;

  pressFrame: number[] = new Array(NUM_BUTTONS).fill(-99999);
  releaseFrame: number[] = new Array(NUM_BUTTONS).fill(-99999);
  consumed: boolean[] = new Array(NUM_BUTTONS).fill(true);
  heldSince: number[] = new Array(NUM_BUTTONS).fill(-99999);

  // direction tap / double-tap bookkeeping
  dirActivatedFrame = -99999;
  dirReleasedFrame = -99999;
  lastReleasedDir = -1;
  lastPressDuration = 999;
  /** true on the frame a direction is freshly pushed from neutral (a "step") */
  stepRequest = false;
  /** latched by double-tap-and-hold; cleared when the stick returns to neutral */
  sprintLatched = false;

  frame = 0;

  update(raw: RawInput, frame: number) {
    this.frame = frame;
    this.prevHeld = this.held;
    this.held = raw.buttons;
    this.mx = raw.mx;
    this.my = raw.my;

    for (let b = 0; b < NUM_BUTTONS; b++) {
      const m = 1 << b;
      const now = (this.held & m) !== 0;
      const before = (this.prevHeld & m) !== 0;
      if (now && !before) {
        this.pressFrame[b] = frame;
        this.consumed[b] = false;
        this.heldSince[b] = frame;
      } else if (!now && before) {
        this.releaseFrame[b] = frame;
      }
    }

    this.prevDir = this.dir;
    this.dir = dirIndex(raw.mx, raw.my);
    this.stepRequest = false;
    if (this.prevDir === -1 && this.dir !== -1) {
      // fresh push from neutral
      const sinceRelease = frame - this.dirReleasedFrame;
      if (
        sinceRelease <= DOUBLE_TAP_FRAMES &&
        this.lastPressDuration <= TAP_MAX_FRAMES &&
        sameSector(this.dir, this.lastReleasedDir)
      ) {
        this.sprintLatched = true;
      }
      this.dirActivatedFrame = frame;
      this.stepRequest = true;
    } else if (this.prevDir !== -1 && this.dir === -1) {
      this.dirReleasedFrame = frame;
      this.lastReleasedDir = this.prevDir;
      this.lastPressDuration = frame - this.dirActivatedFrame;
      this.sprintLatched = false;
    }
  }

  isHeld(b: B) {
    return (this.held & (1 << b)) !== 0;
  }

  /** Pressed this exact frame (rising edge). */
  pressedNow(b: B) {
    return (this.held & (1 << b)) !== 0 && (this.prevHeld & (1 << b)) === 0;
  }

  /** An unconsumed press within the buffer window. */
  buffered(b: B, window = INPUT_BUFFER) {
    return !this.consumed[b] && this.frame - this.pressFrame[b] <= window;
  }

  consume(b: B) {
    this.consumed[b] = true;
  }

  heldFrames(b: B) {
    return this.isHeld(b) ? this.frame - this.heldSince[b] : 0;
  }

  get sprinting() {
    return this.dir !== -1 && (this.sprintLatched || this.isHeld(B.Sprint));
  }

  get moving() {
    return this.dir !== -1;
  }
}

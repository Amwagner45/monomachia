// Training dummy: repeats one chosen behaviour so the player can practise
// parry timing and the three unblockable counters.

import type { Fighter } from '../fighter';
import { B, RawInput } from '../input';
import { dist2 } from '../math';
import { CounterKind } from '../moves/types';
import { AIBrain, DIFFICULTY } from './brain';

export type TrainingBehaviour = 'idle' | 'block' | 'lights' | 'heavies' | 'thrust' | 'sweep' | 'slam' | 'random' | 'fight';

export function abilityFor(f: Fighter, kind: CounterKind): string | null {
  return f.weapon.abilities.find((id) => f.weapon.moves[id]?.counter === kind) ?? null;
}

export class TrainingBrain {
  behaviour: TrainingBehaviour = 'idle';
  private spar: AIBrain;
  private next = 0;
  private taps: { btn: B; from: number; to: number }[] = [];
  private hold = 0;
  private pattern = 0;

  constructor(public me: Fighter) {
    this.spar = new AIBrain(me, DIFFICULTY.normal, 5);
  }

  setBehaviour(b: TrainingBehaviour) {
    this.behaviour = b;
    this.next = 0;
    this.taps = [];
    this.hold = 0;
    // put the practised unblockable on the light slot
    if (b === 'thrust' || b === 'sweep' || b === 'slam') {
      const id = abilityFor(this.me, b);
      if (id) {
        const other = this.me.weapon.abilities.find((x) => x !== id) ?? id;
        this.me.abilities = [id, other];
      }
    } else {
      this.me.abilities = [...this.me.weapon.defaultAbilities] as [string, string];
    }
  }

  private tap(btn: B, at: number, len = 2) {
    this.taps.push({ btn, from: at, to: at + len - 1 });
  }

  think(): RawInput {
    const me = this.me;
    if (this.behaviour === 'fight') return this.spar.think();
    const frame = me.world.frame + 1;
    let mx = 0;
    let my = 0;
    let buttons = this.hold;
    const d = dist2(me.pos, me.opp.pos);
    const want = me.weapon.id === 'greatsword' ? 2.6 : me.weapon.id === 'daggers' ? 1.8 : 2.2;
    const free = me.state === 'free' || me.state === 'step';

    if (this.behaviour === 'block') {
      buttons |= 1 << B.Block;
    } else if (this.behaviour !== 'idle') {
      // keep a practice distance
      if (free) {
        if (d > want + 0.6) my = 1;
        else if (d < want - 0.7) my = -0.7;
      }
      if (free && frame >= this.next && Math.abs(d - want) < 0.9) {
        let b: TrainingBehaviour = this.behaviour;
        if (b === 'random') {
          const opts: TrainingBehaviour[] = ['lights', 'heavies'];
          for (const k of ['thrust', 'sweep', 'slam'] as const) if (abilityFor(me, k)) opts.push(k);
          b = opts[this.pattern++ % opts.length];
          if (b === 'thrust' || b === 'sweep' || b === 'slam') this.setBehaviourKeepRandom(b);
        }
        switch (b) {
          case 'lights':
            this.tap(B.Light, frame);
            this.tap(B.Light, frame + 9);
            this.tap(B.Light, frame + 18);
            this.next = frame + 110;
            break;
          case 'heavies':
            this.tap(B.Heavy, frame);
            if (this.pattern++ % 2 === 0) this.tap(B.Heavy, frame + 34);
            this.next = frame + 120;
            break;
          case 'thrust':
          case 'sweep':
          case 'slam':
            this.tap(B.Block, frame, 3);
            this.tap(B.Light, frame + 1, 2);
            this.next = frame + 130;
            break;
        }
      }
    }
    for (const t of this.taps) if (frame >= t.from && frame <= t.to) buttons |= 1 << t.btn;
    this.taps = this.taps.filter((t) => t.to >= frame);
    return { mx, my, buttons };
  }

  private setBehaviourKeepRandom(kind: 'thrust' | 'sweep' | 'slam') {
    const id = abilityFor(this.me, kind);
    if (!id) return;
    const other = this.me.weapon.abilities.find((x) => x !== id) ?? id;
    this.me.abilities = [id, other];
  }
}

// Targeted experiment: a dummy repeating one unblockable vs an AI that always tries the counter.
import { World } from '../src/sim/world';
import { AIBrain, DIFFICULTY } from '../src/sim/ai/brain';
import { TrainingBrain } from '../src/sim/ai/training';
import { WEAPONS } from '../src/sim/moves';

for (const [kind, weapon] of [['slam', 'greatsword'], ['thrust', 'katana'], ['sweep', 'greatsword']] as const) {
  const W = new World({ weapon: WEAPONS[weapon] }, { weapon: WEAPONS.katana }, 5);
  for (const f of W.fighters) f.setState('free');
  const dummy = new TrainingBrain(W.fighters[0]);
  dummy.setBehaviour(kind);
  const ai = new AIBrain(W.fighters[1], { ...DIFFICULTY.hard, counter: 1, parry: 0, dodge: 0, block: 0, aggression: 0, guard: 0 }, 3);
  const tally: Record<string, number> = {};
  for (let i = 0; i < 60 * 60; i++) {
    W.step([dummy.think(), ai.think()]);
    for (const e of W.drainEvents()) {
      if (e.t === 'counter') tally['counter:' + e.kind] = (tally['counter:' + e.kind] ?? 0) + 1;
      if (e.t === 'hit' && e.attacker === 0) tally.hit = (tally.hit ?? 0) + 1;
      if (e.t === 'telegraph' && e.f === 0) tally.attempts = (tally.attempts ?? 0) + 1;
      if (e.t === 'whiff' && e.f === 0) tally.whiff = (tally.whiff ?? 0) + 1;
    }
    for (const f of W.fighters) { f.hp = 100; f.posture = 0; if (f.state === 'ko') f.setState('free'); }
  }
  console.log(kind, tally);
}

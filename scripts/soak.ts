// Headless robot matches: computer vs computer at full speed.
// Verifies matches finish without errors and reports how often each mechanic occurs.
import { World } from '../src/sim/world';
import { Match } from '../src/sim/match';
import { AIBrain, DIFFICULTY, Difficulty } from '../src/sim/ai/brain';
import { WEAPONS, PLAYABLE_WEAPONS } from '../src/sim/moves';
import { Rng } from '../src/sim/rng';

const N = Number(process.argv[2] ?? 30);
const rng = new Rng(2026);
const diffs: Difficulty[] = ['easy', 'normal', 'hard'];
const totals: Record<string, number> = {};
const add = (k: string, v = 1) => (totals[k] = (totals[k] ?? 0) + v);
let totalRounds = 0;
let totalRoundFrames = 0;
let longest = 0;
const winsByWeapon: Record<string, [number, number]> = {};
let failures = 0;

for (let m = 0; m < N; m++) {
  const w0 = rng.pick(PLAYABLE_WEAPONS);
  const w1 = rng.pick(PLAYABLE_WEAPONS);
  const d0 = rng.pick(diffs);
  const d1 = rng.pick(diffs);
  const W = new World({ weapon: WEAPONS[w0] }, { weapon: WEAPONS[w1] }, 1000 + m);
  const M = new Match(W);
  const ai = [new AIBrain(W.fighters[0], DIFFICULTY[d0], 11 + m), new AIBrain(W.fighters[1], DIFFICULTY[d1], 77 + m)];
  let frames = 0;
  let roundStart = 0;
  const LIMIT = 60 * 60 * 12; // 12 minutes of game time
  try {
    while (M.phase !== 'matchEnd' && frames < LIMIT) {
      M.step([ai[0].think(), ai[1].think()]);
      frames++;
      for (const e of W.drainEvents()) {
        switch (e.t) {
          case 'fight':
            roundStart = frames;
            break;
          case 'roundOver': {
            const len = frames - roundStart;
            totalRounds++;
            totalRoundFrames += len;
            longest = Math.max(longest, len);
            break;
          }
          case 'parry':
            add('parry:' + e.kind);
            break;
          case 'counter':
            add('counter:' + e.kind);
            break;
          case 'hit':
            add('hits');
            break;
          case 'block':
            add('blocks');
            break;
          case 'disarm':
            add('disarm:' + e.reason);
            break;
          case 'ultStart':
            add('ult:' + e.ult);
            break;
          case 'ultChoice':
            add('ult:disarmedChoice');
            break;
          case 'recall':
            add('recall');
            break;
          case 'pickup':
            add('rearm');
            break;
          case 'stagger':
            add('stagger');
            break;
          case 'evade':
            add('evade');
            break;
          case 'ko':
            if (e.winner < 0) add('doubleKO');
            break;
        }
      }
      // sanity checks
      for (const f of W.fighters) {
        if (M.phase === 'fight' && f.postureFull) add('framesAtFullPosture');
        if (!Number.isFinite(f.pos.x) || !Number.isFinite(f.pos.z) || !Number.isFinite(f.hp)) throw new Error('NaN state');
        if (Math.hypot(f.pos.x, f.pos.z) > 12) throw new Error('left the arena');
        if (f.posture < -1e-6 || f.posture > 100.0001) throw new Error('posture out of range ' + f.posture);
      }
    }
    if (M.phase !== 'matchEnd') {
      failures++;
      console.log(`match ${m} (${w0}/${d0} vs ${w1}/${d1}) did not finish: wins ${M.wins}`);
    } else {
      const key = `${w0} vs ${w1}`;
      winsByWeapon[w0] ??= [0, 0];
      winsByWeapon[w1] ??= [0, 0];
      winsByWeapon[M.matchWinner === 0 ? w0 : w1][0]++;
      winsByWeapon[M.matchWinner === 0 ? w1 : w0][1]++;
      void key;
    }
  } catch (err) {
    failures++;
    console.log(`match ${m} crashed at frame ${frames}:`, err);
  }
}

console.log(`\n${N} matches, ${failures} failures`);
console.log(`rounds: ${totalRounds}, avg round ${(totalRoundFrames / Math.max(1, totalRounds) / 60).toFixed(1)} s, longest ${(longest / 60).toFixed(1)} s`);
console.log('per round:');
for (const [k, v] of Object.entries(totals).sort()) console.log(`  ${k.padEnd(22)} ${(v / Math.max(1, totalRounds)).toFixed(2)}`);
console.log('match wins/losses by weapon:', winsByWeapon);
process.exit(failures ? 1 : 0);

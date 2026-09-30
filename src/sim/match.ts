// Round and match flow: intro -> fight -> KO -> next round, first to 3 wins.

import { HP_MAX, ROUNDS_TO_WIN } from './constants';
import { RawInput, emptyInput } from './input';
import { World } from './world';

export type MatchPhase = 'roundIntro' | 'fight' | 'roundEnd' | 'matchEnd';

export const INTRO_FRAMES = 100; // "Round N" then "Fight!"
export const FIGHT_CALL_FRAME = 62;
export const ROUND_END_FRAMES = 170;

export class Match {
  wins: [number, number] = [0, 0];
  round = 1;
  phase: MatchPhase = 'roundIntro';
  phaseFrames = 0;
  roundWinner = -1;
  matchWinner = -1;
  /** Training mode: rounds never end, health refills. */
  endless = false;
  private neutral: RawInput[] = [emptyInput(), emptyInput()];

  constructor(public world: World) {
    this.startRound();
  }

  startRound() {
    this.world.resetRound();
    this.phase = 'roundIntro';
    this.phaseFrames = 0;
    this.roundWinner = -1;
    this.world.emit({ t: 'roundStart', round: this.round });
  }

  get fighting() {
    return this.phase === 'fight';
  }

  step(inputs: RawInput[]) {
    const W = this.world;
    this.phaseFrames++;
    switch (this.phase) {
      case 'roundIntro':
        // keep reading inputs so nothing is "stuck" when the fight starts
        W.step(this.neutral);
        if (this.phaseFrames === FIGHT_CALL_FRAME) W.emit({ t: 'fight', round: this.round });
        if (this.phaseFrames >= INTRO_FRAMES) {
          for (const f of W.fighters) f.setState('free');
          this.phase = 'fight';
          this.phaseFrames = 0;
        }
        break;
      case 'fight': {
        const before = W.events.length;
        W.step(inputs);
        for (let i = before; i < W.events.length; i++) {
          const e = W.events[i];
          if (e.t === 'ko') this.onKO(e.winner);
        }
        break;
      }
      case 'roundEnd':
        W.step(this.neutral);
        if (this.phaseFrames === 70 && this.roundWinner >= 0) {
          const w = W.fighters[this.roundWinner];
          if (w.state !== 'ko') w.setState('victory');
        }
        if (this.phaseFrames >= ROUND_END_FRAMES) {
          if (this.matchWinner >= 0) {
            this.phase = 'matchEnd';
            this.phaseFrames = 0;
            W.emit({ t: 'matchOver', winner: this.matchWinner });
          } else {
            this.round++;
            this.startRound();
          }
        }
        break;
      case 'matchEnd':
        W.step(this.neutral);
        break;
    }
  }

  private onKO(winner: number) {
    if (this.endless) return;
    this.phase = 'roundEnd';
    this.phaseFrames = 0;
    this.roundWinner = winner;
    if (winner >= 0) this.wins[winner]++;
    const perfect = winner >= 0 && this.world.fighters[winner].hp >= HP_MAX;
    this.world.emit({ t: 'roundOver', winner, wins: [this.wins[0], this.wins[1]], perfect });
    if (winner >= 0 && this.wins[winner] >= ROUNDS_TO_WIN) this.matchWinner = winner;
  }
}

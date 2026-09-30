// Title screen, menus, fighter select, controls (rebinding + profiles),
// how-to-play, settings, pause and results. Mouse, keyboard and controller
// navigation all work.

import type { AudioEngine } from '../audio/audio';
import { ACTIONS, Action, FIGHTSTICK_PAD, DEFAULT_KB, DEFAULT_PAD, ProfileStore, bindingLabel, defaultProfile, saveProfiles } from '../input/bindings';
import type { DeviceId, InputDevices, MenuNav } from '../input/devices';
import type { Difficulty } from '../sim/ai/brain';
import { WEAPONS, PLAYABLE_WEAPONS, FISTS } from '../sim/moves';
import type { WeaponId } from '../sim/moves/types';
import { h, clear } from './dom';
import { ABILITY_INFO, WEAPON_INFO } from './data';

export type Mode = 'duel' | 'training' | 'watch' | 'versus';

export interface SideConfig {
  weapon: WeaponId;
  abilities: [string, string];
  ai: Difficulty | null;
  random?: boolean;
}

export interface MatchConfig {
  mode: Mode;
  p1: SideConfig;
  p2: SideConfig;
  /** versus only: which device and saved profile each player uses */
  devices?: [DeviceId, DeviceId];
  profiles?: [number, number];
}

export interface Settings {
  quality: 'high' | 'low';
  reduceFlashes: boolean;
  showHints: boolean;
}

export interface MatchSummary {
  winner: number;
  mode: Mode;
  names: [string, string];
  wins: [number, number];
  stats: { hitsLanded: number; damageDealt: number; parries: number; counters: number; disarms: number; ultimates: number; blocks: number }[];
}

export interface MenuCallbacks {
  start(cfg: MatchConfig): void;
  resume(): void;
  restart(): void;
  quitToMenu(): void;
  settingsChanged(): void;
  enteredMenus(): void;
}

interface ScreenState {
  name: string;
  onBack: (() => void) | null;
  anyKey?: () => void;
}

const DIFFS: { id: Difficulty; label: string }[] = [
  { id: 'easy', label: 'Easy' },
  { id: 'normal', label: 'Normal' },
  { id: 'hard', label: 'Hard' },
];

function loadLast(): Record<Mode, MatchConfig> | null {
  try {
    const raw = localStorage.getItem('monomachia.lastSelect');
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function saveLast(v: Record<Mode, MatchConfig>) {
  try {
    localStorage.setItem('monomachia.lastSelect', JSON.stringify(v));
  } catch {
    /* ignore */
  }
}

const defaultSide = (w: WeaponId, ai: Difficulty | null): SideConfig => ({
  weapon: w,
  abilities: [...WEAPONS[w].defaultAbilities] as [string, string],
  ai,
});

export class Menus {
  private state: ScreenState | null = null;
  private last: Record<Mode, MatchConfig>;
  open = false;

  constructor(
    public el: HTMLElement,
    private devices: InputDevices,
    private audio: AudioEngine,
    private profiles: ProfileStore,
    public settings: Settings,
    private cb: MenuCallbacks,
  ) {
    this.last = loadLast() ?? {
      duel: { mode: 'duel', p1: defaultSide('katana', null), p2: defaultSide('greatsword', 'normal') },
      training: { mode: 'training', p1: defaultSide('katana', null), p2: defaultSide('greatsword', null) },
      watch: { mode: 'watch', p1: defaultSide('katana', 'normal'), p2: defaultSide('daggers', 'normal') },
      versus: { mode: 'versus', p1: defaultSide('katana', null), p2: defaultSide('greatsword', null), devices: ['kbm', 'pad0'], profiles: [0, 0] },
    };
    this.last.versus ??= { mode: 'versus', p1: defaultSide('katana', null), p2: defaultSide('greatsword', null), devices: ['kbm', 'pad0'], profiles: [0, 0] };
  }

  private mount(name: string, content: HTMLElement, onBack: (() => void) | null, dim = true) {
    clear(this.el);
    this.el.hidden = false;
    this.el.classList.toggle('dim', dim);
    this.el.appendChild(content);
    this.state = { name, onBack };
    this.open = true;
    const first = this.focusables()[0];
    if (first && this.devices.lastDevice === 'pad') first.focus();
  }

  hide() {
    clear(this.el);
    this.el.hidden = true;
    this.state = null;
    this.open = false;
  }

  get screen() {
    return this.state?.name ?? null;
  }

  private focusables(): HTMLElement[] {
    return Array.from(this.el.querySelectorAll<HTMLElement>('[data-nav]')).filter((e) => !e.hasAttribute('disabled') && e.offsetParent !== null);
  }

  nav(ev: MenuNav) {
    if (!this.state) return;
    if (this.state.anyKey) {
      this.state.anyKey();
      return;
    }
    if (this.devices.capturing) return;
    const items = this.focusables();
    const cur = items.indexOf(document.activeElement as HTMLElement);
    if (ev === 'up' || ev === 'left' || ev === 'down' || ev === 'right') {
      // sliders consume left/right
      const active = document.activeElement as HTMLInputElement | null;
      if (active && active.type === 'range' && (ev === 'left' || ev === 'right')) {
        active.value = String(Number(active.value) + (ev === 'left' ? -5 : 5));
        active.dispatchEvent(new Event('input'));
        return;
      }
      const d = ev === 'up' || ev === 'left' ? -1 : 1;
      const next = items[(cur + d + items.length) % items.length] ?? items[0];
      next?.focus();
      this.audio.uiMove();
    } else if (ev === 'ok') {
      const t = (cur >= 0 ? items[cur] : items[0]) as HTMLElement | undefined;
      if (t && cur < 0) t.focus();
      else t?.click();
    } else if (ev === 'back' || ev === 'pause') {
      if (this.state.onBack) {
        this.audio.uiMove();
        this.state.onBack();
      }
    }
  }

  private btn(label: string, onClick: () => void, cls = 'mbtn', small?: string) {
    return h(
      'button',
      {
        class: cls,
        'data-nav': true,
        onclick: () => {
          this.audio.uiSelect();
          onClick();
        },
      },
      h('span', null, label),
      small ? h('small', null, small) : null,
    );
  }

  // ------------------------------------------------------------------ title

  showTitle() {
    const touchOnly = matchMedia('(pointer: coarse)').matches && !matchMedia('(pointer: fine)').matches;
    const content = h(
      'div',
      { class: 'screen title-screen', style: { textAlign: 'center' } },
      h(
        'div',
        { class: 'title-wrap' },
        h('div', { class: 'vertical' }, '一騎討ち'),
        h(
          'div',
          { class: 'title-main' },
          h('div', { class: 'hanko', 'aria-hidden': 'true' }, '一騎'),
          h('h1', { class: 'logo' }, 'MONOMACHIA'),
          h('div', { class: 'tagline' }, 'Single combat · MVP demo'),
        ),
      ),
      h('div', { class: 'press' }, touchOnly ? 'Tap to begin' : 'Press any key or click to begin'),
      h(
        'div',
        { class: 'device-note' },
        touchOnly
          ? 'This demo is played with a keyboard and mouse or a game controller.'
          : 'Keyboard and mouse, or any controller. Sound on.',
      ),
    );
    this.mount('title', content, null, false);
    const go = () => {
      this.audio.init();
      this.cb.enteredMenus();
      this.showMain();
    };
    this.state!.anyKey = go;
    content.addEventListener('click', go);
  }

  // ------------------------------------------------------------------ main menu

  showMain() {
    const menu = h(
      'div',
      { class: 'menu' },
      this.btn('Duel', () => this.showSelect('duel'), 'mbtn', 'vs computer'),
      this.btn('Training', () => this.showSelect('training'), 'mbtn', 'parries & counters'),
      this.btn('Versus', () => this.showSelect('versus'), 'mbtn', 'two players, one screen'),
      this.btn('Watch', () => this.showSelect('watch'), 'mbtn', 'computer vs computer'),
      this.btn('How to play', () => this.showHowTo(() => this.showMain())),
      this.btn('Controls', () => this.showControls(() => this.showMain())),
      this.btn('Settings', () => this.showSettings(() => this.showMain())),
    );
    const content = h(
      'div',
      { class: 'screen', style: { justifyItems: 'center' } },
      h('div', { class: 'title-main' }, h('div', { class: 'logo', style: { fontSize: 'clamp(2rem, 6vw, 3.6rem)' } }, 'MONOMACHIA'), h('div', { class: 'tagline' }, '一騎討ち · Single combat')),
      h('div', { class: 'panel', style: { width: 'min(100%, 420px)' } }, menu),
    );
    this.mount('main', content, () => this.showTitle());
    const first = this.focusables()[0];
    first?.focus();
  }

  // ------------------------------------------------------------------ fighter select

  showSelect(mode: Mode) {
    const cfg: MatchConfig = JSON.parse(JSON.stringify(this.last[mode]));
    cfg.mode = mode;
    const render = () => {
      const sides = h('div', { class: 'select-grid' });
      const titles: Record<Mode, [string, string]> = {
        duel: ['You', 'Opponent'],
        training: ['You', 'Training dummy'],
        watch: ['Red fighter', 'Blue fighter'],
        versus: ['Player 1', 'Player 2'],
      };
      if (mode === 'versus') {
        cfg.devices ??= ['kbm', this.devices.pads.length ? 'pad0' : 'kbArrows'];
        cfg.profiles ??= [this.profiles.active, this.profiles.active];
        cfg.profiles = cfg.profiles.map((p) => Math.min(p, this.profiles.profiles.length - 1)) as [number, number];
      }
      (['p1', 'p2'] as const).forEach((key, i) => {
        const side = cfg[key];
        const panel = h('div', { class: 'panel', style: { display: 'grid', gap: '14px', alignContent: 'start' } });
        panel.append(h('div', { class: 'eyebrow' }, i === 0 ? 'Red · 赤' : 'Blue · 青'), h('h2', null, titles[mode][i]));
        const cards = h('div', { class: 'cards' });
        for (const w of PLAYABLE_WEAPONS) {
          const info = WEAPON_INFO[w as Exclude<WeaponId, 'fists'>];
          const def = WEAPONS[w];
          const on = side.weapon === w && !side.random;
          const card = h(
            'button',
            {
              class: `card${on ? ' on' : ''}`,
              'data-nav': true,
              'aria-pressed': on ? 'true' : 'false',
              onclick: () => {
                this.audio.uiSelect();
                side.weapon = w;
                side.random = false;
                side.abilities = [...def.defaultAbilities] as [string, string];
                render();
              },
            },
            h('span', { class: 'cc' }, `${info.kanji} · ${info.cls}`),
            h('span', { class: 'cn' }, def.name),
            h(
              'span',
              { class: 'stats' },
              ...(['speed', 'power', 'posture', 'reach', 'parry'] as const).map((k) =>
                h('span', { class: 'stat', title: k === 'posture' ? 'Posture damage' : '' }, h('span', null, k[0].toUpperCase() + k.slice(1)), h('i', null)),
              ),
            ),
          );
          (card.querySelectorAll('i') as NodeListOf<HTMLElement>).forEach((el, idx) => {
            const k = (['speed', 'power', 'posture', 'reach', 'parry'] as const)[idx];
            el.style.setProperty('--v', `${info.stats[k] * 100}%`);
          });
          cards.append(card);
        }
        panel.append(cards);
        if (key === 'p2' && mode === 'duel') {
          panel.append(
            h(
              'div',
              { class: 'seg' },
              h(
                'button',
                {
                  class: `opt${side.random ? ' on' : ''}`,
                  'data-nav': true,
                  onclick: () => {
                    side.random = !side.random;
                    this.audio.uiSelect();
                    render();
                  },
                },
                'Random weapon',
              ),
            ),
          );
        }
        const wInfo = WEAPON_INFO[side.weapon as Exclude<WeaponId, 'fists'>];
        if (!side.random) {
          panel.append(h('p', { class: 'blurb' }, WEAPONS[side.weapon].blurb, ' ', h('b', null, `Ultimate: ${wInfo.ultimate}.`), ' ', wInfo.ultDesc));
          // block abilities
          if (!(mode === 'training' && key === 'p2')) {
            const abl = WEAPONS[side.weapon].abilities;
            const slotRow = (slot: 0 | 1) =>
              h(
                'div',
                { class: 'field' },
                h('span', { class: 'slot-badge' }, slot === 0 ? 'Hold block + light' : 'Hold block + heavy'),
                h(
                  'div',
                  { class: 'seg' },
                  ...abl.map((id) =>
                    h(
                      'button',
                      {
                        class: `opt${side.abilities[slot] === id ? ' on' : ''}`,
                        'data-nav': true,
                        title: ABILITY_INFO[id]?.desc ?? '',
                        onclick: () => {
                          this.audio.uiSelect();
                          const other = slot === 0 ? 1 : 0;
                          if (side.abilities[other] === id) side.abilities[other] = side.abilities[slot];
                          side.abilities[slot] = id;
                          render();
                        },
                      },
                      ABILITY_INFO[id]?.name ?? id,
                    ),
                  ),
                ),
                h('span', { class: 'blurb' }, ABILITY_INFO[side.abilities[slot]]?.desc ?? ''),
              );
            panel.append(h('div', { class: 'eyebrow' }, 'Block abilities · pick 2 of 3'), slotRow(0), slotRow(1));
          }
        }
        if (mode === 'versus') {
          const devOpts: { id: DeviceId; label: string }[] = [
            { id: 'kbm', label: 'Keyboard & mouse' },
            { id: 'kbArrows', label: 'Keyboard: arrows + J K L' },
            { id: 'pad0', label: this.devices.pads[0] ? 'Controller 1' : 'Controller 1 (not connected)' },
            { id: 'pad1', label: this.devices.pads[1] ? 'Controller 2' : 'Controller 2 (not connected)' },
          ];
          panel.append(
            h('div', { class: 'eyebrow' }, 'Plays with'),
            h(
              'div',
              { class: 'seg' },
              ...devOpts.map((d) =>
                h('button', {
                  class: `opt${cfg.devices![i] === d.id ? ' on' : ''}`,
                  'data-nav': true,
                  onclick: () => {
                    this.audio.uiSelect();
                    cfg.devices![i] = d.id;
                    render();
                  },
                }, d.label),
              ),
            ),
            h('div', { class: 'seg', style: { alignItems: 'center' } },
              h('span', { class: 'eyebrow' }, 'Controls profile'),
              h('select', {
                id: `profile-p${i + 1}`,
                'data-nav': true,
                onchange: (e: Event) => {
                  cfg.profiles![i] = Number((e.target as HTMLSelectElement).value);
                },
              }, ...this.profiles.profiles.map((p, pi) => {
                const o = h('option', { value: pi }, p.name);
                if (pi === cfg.profiles![i]) o.selected = true;
                return o;
              })),
            ),
          );
        }
        if (mode !== 'versus' && (side.ai !== null || (mode !== 'training' && key === 'p2') || mode === 'watch')) {
          if (side.ai === null) side.ai = 'normal';
          panel.append(
            h('div', { class: 'eyebrow' }, 'Computer skill'),
            h(
              'div',
              { class: 'seg' },
              ...DIFFS.map((d) =>
                h(
                  'button',
                  {
                    class: `opt${side.ai === d.id ? ' on' : ''}`,
                    'data-nav': true,
                    onclick: () => {
                      this.audio.uiSelect();
                      side.ai = d.id;
                      render();
                    },
                  },
                  d.label,
                ),
              ),
            ),
          );
        }
        if (mode === 'training' && key === 'p2') {
          panel.append(h('p', { class: 'blurb' }, 'In training you choose what the dummy does from a panel on screen (or number keys 1–9). Health refills automatically.'));
        }
        sides.append(panel);
      });
      const clash = mode === 'versus' && cfg.devices![0] === cfg.devices![1];
      const begin = this.btn(mode === 'duel' || mode === 'versus' ? 'Begin duel' : mode === 'training' ? 'Enter training' : 'Watch the duel', () => {
        if (clash) return;
        this.last[mode] = JSON.parse(JSON.stringify(cfg));
        saveLast(this.last);
        const final: MatchConfig = JSON.parse(JSON.stringify(cfg));
        if (final.mode === 'duel') final.p1.ai = null;
        if (final.mode === 'training' || final.mode === 'versus') {
          final.p1.ai = null;
          final.p2.ai = null;
        }
        if (final.p2.random) {
          const w = PLAYABLE_WEAPONS[Math.floor(Math.random() * PLAYABLE_WEAPONS.length)];
          final.p2.weapon = w;
          final.p2.abilities = [...WEAPONS[w].defaultAbilities] as [string, string];
        }
        this.cb.start(final);
      }, 'btn primary');
      const back = this.btn('Back', () => this.showMain(), 'btn');
      const content = h(
        'div',
        { class: 'screen' },
        h('div', null, h('div', { class: 'eyebrow' }, mode === 'duel' ? 'Duel · first to 3 rounds' : mode === 'versus' ? 'Versus · two players · first to 3 rounds' : mode === 'training' ? 'Training' : 'Watch'), h('h2', null, 'Choose your fighters')),
        sides,
        clash ? h('div', { class: 'status', style: { borderColor: 'var(--danger)', color: '#ffb0a0' } }, 'Both players are set to the same device. Pick a different one for Player 2.') : null,
        h('div', { class: 'btn-row sticky-actions' }, back, begin),
      );
      const focusedIdx = this.focusables().indexOf(document.activeElement as HTMLElement);
      this.mount('select', content, () => this.showMain());
      if (focusedIdx >= 0) this.focusables()[focusedIdx]?.focus();
    };
    render();
  }

  // ------------------------------------------------------------------ controls

  showControls(onBack: () => void) {
    let tab: 'kb' | 'pad' = this.devices.lastDevice === 'pad' ? 'pad' : 'kb';
    let listening: { action: Action; slot: number } | null = null;
    let renaming = false;
    const store = this.profiles;
    const render = () => {
      const prof = store.profiles[store.active];
      const style = this.devices.padStyle;
      const status = this.devices.padBlocked
        ? 'Controllers are blocked in this embedded view. Open the game in its own browser tab to use one.'
        : this.devices.pad
          ? `Controller connected: ${this.devices.pad.id} (${style === 'ps' ? 'PlayStation' : style === 'xbox' ? 'Xbox' : 'generic'} button names${this.devices.pad.mapping === 'standard' ? '' : ', unrecognised layout: set buttons below'})`
          : 'No controller detected. Connect one and press any button on it.';

      const profileRow = h(
        'div',
        { class: 'seg', style: { alignItems: 'center' } },
        h('span', { class: 'eyebrow' }, 'Profile'),
        renaming
          ? h('input', {
              type: 'text',
              id: 'profile-name',
              value: prof.name,
              maxlength: 24,
              onkeydown: (e: KeyboardEvent) => {
                if (e.key === 'Enter') {
                  prof.name = (e.target as HTMLInputElement).value.trim() || prof.name;
                  renaming = false;
                  saveProfiles(store);
                  render();
                }
              },
            })
          : h(
              'select',
              {
                id: 'profile-select',
                'data-nav': true,
                onchange: (e: Event) => {
                  store.active = Number((e.target as HTMLSelectElement).value);
                  saveProfiles(store);
                  render();
                },
              },
              ...store.profiles.map((p, i) => {
                const o = h('option', { value: i }, p.name);
                if (i === store.active) o.selected = true;
                return o;
              }),
            ),
        this.btn(renaming ? 'Save name' : 'Rename', () => {
          if (renaming) {
            const inp = this.el.querySelector<HTMLInputElement>('#profile-name');
            if (inp) prof.name = inp.value.trim() || prof.name;
            saveProfiles(store);
          }
          renaming = !renaming;
          render();
          this.el.querySelector<HTMLInputElement>('#profile-name')?.focus();
        }, 'opt'),
        this.btn('New profile', () => {
          store.profiles.push(defaultProfile(`Player ${store.profiles.length + 1}`));
          store.active = store.profiles.length - 1;
          saveProfiles(store);
          render();
        }, 'opt'),
        store.profiles.length > 1
          ? this.btn('Delete', () => {
              store.profiles.splice(store.active, 1);
              store.active = 0;
              saveProfiles(store);
              render();
            }, 'opt')
          : null,
      );

      const tabs = h(
        'div',
        { class: 'tabs' },
        h('button', { class: `opt${tab === 'kb' ? ' on' : ''}`, 'data-nav': true, onclick: () => { tab = 'kb'; render(); } }, 'Keyboard & mouse'),
        h('button', { class: `opt${tab === 'pad' ? ' on' : ''}`, 'data-nav': true, onclick: () => { tab = 'pad'; render(); } }, 'Controller'),
      );
      tabs.classList.add('seg');

      const set = tab === 'kb' ? prof.kb : prof.pad;
      const rows = ACTIONS.map((a) => {
        const slots = [0, 1].map((slot) => {
          const tok = set[a.id][slot];
          const isListening = listening && listening.action === a.id && listening.slot === slot;
          return h(
            'button',
            {
              class: isListening ? 'listening' : '',
              'data-nav': true,
              'aria-label': `${a.label} binding ${slot + 1}`,
              onclick: () => {
                if (listening) return;
                listening = { action: a.id, slot };
                render();
                this.devices.startCapture(tab, (t) => {
                  if (t && t !== 'k:Backspace' && t !== 'k:Delete') {
                    // one binding per input: remove it from other actions
                    for (const other of ACTIONS) set[other.id] = set[other.id].filter((x) => x !== t);
                    set[a.id][slot] = t;
                    set[a.id] = set[a.id].filter(Boolean);
                  } else if (t) {
                    set[a.id].splice(slot, 1);
                  }
                  listening = null;
                  saveProfiles(store);
                  render();
                });
              },
            },
            isListening ? (tab === 'kb' ? 'Press a key…' : 'Press a button…') : tok ? bindingLabel(tok, tab === 'pad' ? style : 'generic') : '—',
          );
        });
        return h('tr', null, h('td', null, a.label, a.hint ? h('div', { class: 'muted', style: { fontSize: '0.75rem' } }, a.hint) : null), h('td', null, h('div', { class: 'bind' }, slots)));
      });

      const presets = h(
        'div',
        { class: 'btn-row', style: { justifyContent: 'flex-start' } },
        this.btn('Reset to defaults', () => {
          if (tab === 'kb') prof.kb = JSON.parse(JSON.stringify(DEFAULT_KB));
          else prof.pad = JSON.parse(JSON.stringify(DEFAULT_PAD));
          saveProfiles(store);
          render();
        }, 'btn'),
        tab === 'pad'
          ? this.btn('Fight stick layout', () => {
              prof.pad = JSON.parse(JSON.stringify(FIGHTSTICK_PAD));
              saveProfiles(store);
              render();
            }, 'btn')
          : null,
      );

      const content = h(
        'div',
        { class: 'screen' },
        h('div', null, h('div', { class: 'eyebrow' }, 'Saved in this browser'), h('h2', null, 'Controls')),
        h(
          'div',
          { class: 'panel', style: { display: 'grid', gap: '14px' } },
          profileRow,
          tabs,
          tab === 'pad' ? h('div', { class: 'status' }, status) : h('div', { class: 'status' }, 'Click a slot, then press the key or mouse button. Esc cancels, Backspace clears. Sprint also works by double-tapping a direction.'),
          h('div', { class: 'table-wrap' }, h('table', null, h('thead', null, h('tr', null, h('th', null, 'Action'), h('th', null, 'Bindings'))), h('tbody', null, rows))),
          presets,
        ),
        h('div', { class: 'btn-row' }, this.btn('Back', () => {
          this.devices.cancelCapture();
          onBack();
        }, 'btn')),
      );
      this.mount('controls', content, () => {
        if (this.devices.capturing) return;
        onBack();
      });
    };
    render();
  }

  // ------------------------------------------------------------------ how to play

  showHowTo(onBack: () => void) {
    const block = (title: string, items: string[]) => h('div', { class: 'howto-block' }, h('h3', null, title), h('ul', null, items.map((t) => h('li', { html: t }))));
    const moveTable = (w: WeaponId) => {
      const def = w === 'fists' ? FISTS : WEAPONS[w];
      const row = (input: string, id: string) => {
        const m = def.moves[id];
        if (!m) return null;
        return h('tr', null, h('td', null, input), h('td', null, m.name, m.unblockable ? h('span', { style: { color: 'var(--danger)' } }, ' · unblockable') : null), h('td', { class: 'num' }, String(m.damage)), h('td', { class: 'num' }, String(m.posture)));
      };
      const chainNames = (start: string) => {
        const names: string[] = [];
        let id: string | undefined = start;
        const seen = new Set<string>();
        while (id && def.moves[id] && !seen.has(id)) {
          seen.add(id);
          names.push(def.moves[id].name);
          id = def.moves[id].chainLight;
        }
        return names.join(' → ');
      };
      return h(
        'div',
        { class: 'howto-block' },
        h('h3', null, def.name),
        h('p', { class: 'muted', style: { fontSize: '0.85rem' } }, `Light chain: ${chainNames(def.lightStart)}`),
        h(
          'div',
          { class: 'table-wrap' },
          h(
            'table',
            null,
            h('thead', null, h('tr', null, h('th', null, 'Input'), h('th', null, 'Move'), h('th', { class: 'num' }, 'HP'), h('th', { class: 'num' }, 'Posture'))),
            h(
              'tbody',
              null,
              row('Light', def.lightStart),
              row('Heavy (hold to charge)', def.heavyStart),
              row('Sprint + light', def.sprintLight),
              row('Sprint + heavy', def.sprintHeavy),
              row('Dodge + light', def.dodgeLight),
              row('Dodge + heavy', def.dodgeHeavy),
              row('Backstep + light', def.backLight),
              row('Backstep + heavy', def.backHeavy),
              row('Jump + light', def.jumpLight),
              row('Jump + heavy', def.jumpHeavy),
              ...def.abilities.map((id) => row('Block + light/heavy', id)),
            ),
          ),
        ),
      );
    };
    const content = h(
      'div',
      { class: 'screen' },
      h('div', null, h('div', { class: 'eyebrow' }, 'The rules of the duel'), h('h2', null, 'How to play')),
      h(
        'div',
        { class: 'panel two-col' },
        block('Win the duel', [
          'Empty the other fighter’s health to win a round. First to <b>3 rounds</b> wins.',
          'Your camera stays locked on: forward moves toward them, left and right circle around.',
          '<b>Tap</b> a direction to step, <b>double-tap and hold</b> to sprint.',
        ]),
        block('Defend', [
          '<b>Hold block</b> to stop health damage. Blocking still fills your posture a little.',
          '<b>Tap block just before a hit</b> to parry: their weapon bounces, their posture fills, you strike first.',
          '<b>Dodge</b> with a direction for a dash that passes through normal attacks. Dodge with no direction to backstep.',
        ]),
        block('Posture', [
          'The bar under your health. Hits, blocks, parries and counters you take fill it.',
          'It only drains while you <b>hold block and are not being hit</b>: fastest standing still, slower when moving or hurt.',
          'When it is full, a parried attack or blocking an unblockable, a full-charge heavy or an ultimate <b>disarms you</b>.',
        ]),
        block('Unblockables (red 危 mark)', [
          '<b>Thrust</b>: dodge <b>toward</b> it to stomp their blade. They are stunned.',
          '<b>Sweep</b>: <b>jump</b> over it to vault off them for big posture damage.',
          '<b>Slam</b>: <b>back-dash</b> as it lands, then press light for a counter lunge.',
          'All three can also be parried. Dodge invincibility does not work against them.',
        ]),
        block('Disarmed', [
          'Your weapon flies away. You fight with fists: faster, longer dodges, higher jumps.',
          'You cannot block. A timed block press becomes a <b>redirect</b> counter that stuns and hammers posture.',
          'Stand on your weapon and press <b>pick up</b> to re-arm.',
        ]),
        block('Ultimate', [
          'At 25% health or less you glow: press <b>light + heavy together</b> (or the ultimate button), once per round.',
          'Armed: your weapon’s signature technique. Disarmed: choose Recall (weapon returns) or Breaker Palm (a big posture blow).',
        ]),
        block('Modes', [
          '<b>Duel</b>: you against the computer, at three difficulty levels.',
          '<b>Versus</b>: two people on one screen, split down the middle. Each player picks a device and a controls profile. Keyboard + mouse and the arrow-key layout can share one keyboard.',
          '<b>Training</b>: a dummy you can tell what to do (keys 1–9), with health refill (key 0).',
          '<b>Watch</b>: two computer fighters duel while you watch.',
        ]),
      ),
      h('div', null, h('h2', null, 'Move lists')),
      h('div', { class: 'panel two-col' }, moveTable('katana'), moveTable('greatsword'), moveTable('daggers'), moveTable('fists')),
      h('div', { class: 'btn-row' }, this.btn('Back', onBack, 'btn')),
    );
    this.mount('howto', content, onBack);
  }

  // ------------------------------------------------------------------ settings

  showSettings(onBack: () => void) {
    const s = this.settings;
    const render = () => {
      const seg = (label: string, value: boolean | string, opts: [string, boolean | string][], set: (v: boolean | string) => void) =>
        h(
          'div',
          { class: 'field' },
          h('span', { class: 'eyebrow' }, label),
          h(
            'div',
            { class: 'seg' },
            ...opts.map(([l, v]) =>
              h('button', {
                class: `opt${value === v ? ' on' : ''}`,
                'data-nav': true,
                onclick: () => {
                  this.audio.uiSelect();
                  set(v);
                  this.cb.settingsChanged();
                  render();
                },
              }, l),
            ),
          ),
        );
      const slider = (label: string, key: 'master' | 'sfx' | 'music') => {
        const val = Math.round(this.audio.volumes[key] * 100);
        const out = h('span', { class: 'muted' }, String(val));
        const input = h('input', {
          type: 'range',
          id: `vol-${key}`,
          min: 0,
          max: 100,
          value: val,
          'data-nav': true,
          'aria-label': `${label} volume`,
          oninput: (e: Event) => {
            const v = Number((e.target as HTMLInputElement).value);
            this.audio.volumes[key] = v / 100;
            this.audio.applyVolumes();
            out.textContent = String(v);
          },
        });
        return h('label', { class: 'slider' }, h('span', null, label), input, out);
      };
      const content = h(
        'div',
        { class: 'screen', style: { width: 'min(100%, 560px)' } },
        h('div', null, h('div', { class: 'eyebrow' }, 'Saved in this browser'), h('h2', null, 'Settings')),
        h(
          'div',
          { class: 'panel', style: { display: 'grid', gap: '16px' } },
          seg('Graphics', s.quality, [['High', 'high'], ['Fast', 'low']], (v) => (s.quality = v as 'high' | 'low')),
          seg('Reduce flashes and shaking', s.reduceFlashes, [['Off', false], ['On', true]], (v) => (s.reduceFlashes = v as boolean)),
          seg('Button hints on screen', s.showHints, [['On', true], ['Off', false]], (v) => (s.showHints = v as boolean)),
          h('div', { class: 'eyebrow' }, 'Volume'),
          slider('Master', 'master'),
          slider('Effects', 'sfx'),
          slider('Music', 'music'),
        ),
        h('div', { class: 'btn-row' }, this.btn('Back', onBack, 'btn')),
      );
      this.mount('settings', content, onBack);
    };
    render();
  }

  // ------------------------------------------------------------------ pause & results

  showPause() {
    const menu = h(
      'div',
      { class: 'menu' },
      this.btn('Resume', () => this.cb.resume()),
      this.btn('Move list', () => this.showHowTo(() => this.showPause())),
      this.btn('Controls', () => this.showControls(() => this.showPause())),
      this.btn('Settings', () => this.showSettings(() => this.showPause())),
      this.btn('Restart', () => this.cb.restart()),
      this.btn('Quit to menu', () => this.cb.quitToMenu()),
    );
    const content = h(
      'div',
      { class: 'screen', style: { justifyItems: 'center' } },
      h('div', { class: 'result-title' }, h('div', { class: 'k', style: { fontSize: '1.6rem' } }, '休止'), h('div', { class: 'e', style: { fontSize: 'var(--step-3)' } }, 'Paused')),
      h('div', { class: 'panel', style: { width: 'min(100%, 420px)' } }, menu),
    );
    this.mount('pause', content, () => this.cb.resume());
    this.focusables()[0]?.focus();
  }

  showResults(sum: MatchSummary) {
    const watch = sum.mode === 'watch' || sum.mode === 'versus';
    const won = sum.winner === 0;
    const title = watch ? `${sum.names[sum.winner]} wins` : won ? 'Victory' : 'Defeat';
    const kanji = watch ? '決着' : won ? '勝利' : '敗北';
    const rows: [string, keyof MatchSummary['stats'][number]][] = [
      ['Hits landed', 'hitsLanded'],
      ['Damage dealt', 'damageDealt'],
      ['Blocks', 'blocks'],
      ['Parries', 'parries'],
      ['Counters', 'counters'],
      ['Disarms', 'disarms'],
      ['Ultimates', 'ultimates'],
    ];
    const table = h(
      'table',
      null,
      h('thead', null, h('tr', null, h('th', null, ''), h('th', { class: 'num' }, sum.names[0]), h('th', { class: 'num' }, sum.names[1]))),
      h(
        'tbody',
        null,
        h('tr', null, h('td', null, 'Rounds won'), h('td', { class: 'num' }, String(sum.wins[0])), h('td', { class: 'num' }, String(sum.wins[1]))),
        ...rows.map(([label, k]) => h('tr', null, h('td', null, label), h('td', { class: 'num' }, String(Math.round(sum.stats[0][k]))), h('td', { class: 'num' }, String(Math.round(sum.stats[1][k]))))),
      ),
    );
    const content = h(
      'div',
      { class: 'screen', style: { width: 'min(100%, 560px)' } },
      h('div', { class: 'result-title' }, h('div', { class: 'k' }, kanji), h('div', { class: 'e' }, title)),
      h('div', { class: 'panel' }, h('div', { class: 'table-wrap' }, table)),
      h('div', { class: 'btn-row', style: { justifyContent: 'center' } }, this.btn('Rematch', () => this.cb.restart(), 'btn primary'), this.btn('Change fighters', () => this.showSelect(sum.mode), 'btn'), this.btn('Main menu', () => this.cb.quitToMenu(), 'btn')),
    );
    this.mount('results', content, () => this.cb.quitToMenu());
    this.focusables()[0]?.focus();
  }
}

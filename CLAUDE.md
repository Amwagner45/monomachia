# Monomachia

A one-on-one weapon duel in the browser, built with three.js, TypeScript and Vite. See README.md for the game design, controls and folder layout.

## Design documents

Read these before changing gameplay or planning new features:

- `docs/design.md`: the full game design document, the vision for the finished game (all 9 weapons, arenas, progression, online play).
- `docs/mvp-spec.md`: the MVP plan and spec, what the current demo builds and how. Its "Decisions", "Scope" and "Gaps in the design doc" tables record the choices made so far, and its combat numbers match the code.

When building toward the full game, use `docs/design.md` for what to build and `docs/mvp-spec.md` for how the existing systems work. If a change contradicts either doc (for example, new tuning numbers or a different answer to a "Gaps" question), update the doc in the same branch.

## Publishing every change to GitHub

This repo is public at https://github.com/Arod231/monomachia. The main branch is `master`.

Every change goes on its own branch first and reaches `master` only after I approve it.

For each change I ask for:

1. Before editing, create a new branch from an up-to-date `master` with a short descriptive name (for example, `tune/greatsword-heavy-startup` or `docs/controls`). Never commit directly to `master`.
2. When the change is done, run `npm test` and `npm run typecheck`. If either fails, fix it before committing. If you can't fix it, tell me and don't push.
3. Stage the change and commit it on the branch with a clear message that says what changed and why (for example, "Shorten greatsword heavy startup by 4 frames").
4. Push the branch to `origin` and tell me in one line what's on it. Then ask me to approve the merge.
5. Only after I approve: update `master` (`git pull origin master`), merge the branch into it, rerun the tests, push `master` to `origin`, and delete the branch locally and on `origin`.
6. Tell me in one line what you merged.

Rules:
- Never commit secrets, API keys, tokens or passwords. Never commit anything that `.gitignore` excludes (node_modules, dist, shots, coverage, logs).
- Never force-push or rewrite history on `master`.
- Approval of one merge doesn't cover the next. Ask again for each branch.
- If `git push` to `master` is rejected because GitHub has newer commits, run `git pull --rebase origin master`, rerun the tests, then push again.
- If I say "don't push" or "just try something", commit locally on the branch or leave the change uncommitted, whichever I ask for, and don't push.

## Commands

- `npm install`: install dependencies (Node 22.12+)
- `npm run dev`: dev server at http://localhost:5173
- `npm test`: combat rule tests (Vitest, no graphics)
- `npm run typecheck`: TypeScript check
- `npm run build`: type-check, then build the single-file game
- `npm run soak -- 40`: 40 computer-vs-computer matches, prints balance numbers

## Code notes

- `src/sim` holds the rules with no graphics, stepped at a fixed 60 per second. Keep rendering, input and audio code out of it.
- Weapon frame data lives in `src/sim/moves`. Global tuning lives in `src/sim/constants.ts`.
- When you change combat rules or tuning, add or update a test in `tests/`.

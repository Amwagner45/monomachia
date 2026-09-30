# Monomachia

A one-on-one weapon duel in the browser, built with three.js, TypeScript and Vite. See README.md for the game design, controls and folder layout.

## Publishing every change to GitHub

This repo is public at https://github.com/Arod231/monomachia. The branch is `master`.

After you finish each change I ask for:

1. Run `npm test` and `npm run typecheck`. If either fails, fix it before committing. If you can't fix it, tell me and don't push.
2. Stage the change and commit it with a clear message that says what changed and why (for example, "Shorten greatsword heavy startup by 4 frames").
3. Push to `origin master`.
4. Tell me in one line what you pushed.

Rules:
- Never commit secrets, API keys, tokens or passwords. Never commit anything that `.gitignore` excludes (node_modules, dist, shots, coverage, logs).
- Never force-push or rewrite history on `master`.
- If `git push` is rejected because GitHub has newer commits, run `git pull --rebase origin master`, rerun the tests, then push again.
- If I say "don't push" or "just try something", commit locally or leave the change uncommitted, whichever I ask for, and don't push.

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

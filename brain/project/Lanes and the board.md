---
tags: [project, process, tools]
---

# Lanes and the board

Work on the rebuild runs in parallel **lanes**: each is a git worktree on its own branch, taking one task at a time from a plan, merging back through a pull request. Lane branches are named for their plan and tasks (for example `godot/stage-7-swings` or `godot/menus-22.6-22.10`), and commit subjects name the tasks they finish, such as "(task 7.15)" or "(godot-rebuild 22.6, 22.8)". This vault reads those tags to link each code folder to the tasks that changed it ([[Code map]]).

A task names what blocks it ("Blocked by"), and some wait on the owner's OK, such as the animation review that gates the other weapons' swings. Each task note in this vault shows both directions: what it's blocked by, and what it blocks.

## The board

A local dashboard at http://localhost:5197 charts every plan and every worktree live: which lane works on which task, what's ready, what's blocked, and what waits on the owner. It reads git without fetching, so it never collides with the lanes. Its **Second brain** button opens this vault in a popup window.

Related: [[Rebuild plan]] (the stages and tasks) · [[Workflow]] · [[About this vault]]

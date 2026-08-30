# Task 14: Implement VecInvaders

Space Invaders: grid of alien invaders marching left-right + descending.
Player ship at bottom moves left-right, shoots up. Aliens shoot back randomly.

Aliens speed up as fewer remain. New wave spawns when all cleared. Lives system.
Vector score number, vector life icons. Pause and game-over overlays.

Uses vgame for: App, RenderContext (drawLines for aliens/player/bullets, drawCircle,
drawNumber), overlay (pause/game-over), audio (shoot/explode/march), particles.
~200 lines of game code.
# Task 15: Implement VecTetris

Vector-based Tetris with colored vector-drawn tetromino pieces.

Gameplay:
- 10x20 grid playfield (standard Tetris dimensions)
- 7 tetromino types (I, O, T, S, Z, L, J), each with a distinct color
- Pieces fall one cell at a time; player rotates (up) and moves left/right
- Down = soft drop, space = hard drop
- Completed lines clear and award points (1=100, 2=300, 3=500, 4=800)
- Level increases every 10 lines cleared, speed increases
- Next piece preview shown beside the playfield
- Game over when pieces stack to the top

Vector rendering:
- Each cell is drawn as a vector square outline with filled color
- Pieces use the standard Tetris color scheme:
  I = cyan, O = yellow, T = purple, S = green, Z = red, L = orange, J = blue
- Grid border drawn as vector lines
- Score, level, and lines cleared shown as vector numbers
- Next piece preview drawn as vector squares

Controls:
- Left/Right: move piece
- Up: rotate clockwise
- Down: soft drop
- Space: hard drop (instant drop + lock)
- P: pause
- R: restart after game over

Uses vgame for: App, RenderContext (drawRect for cells, drawLines for grid border,
drawNumber for score/level), overlay (pause + game over), audio (move/rotate/clear/crash).
~300 lines of game code.
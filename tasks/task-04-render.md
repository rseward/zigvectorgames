# Task 04: Implement render.zig and text.zig

Extract vector drawing primitives from zigsteroids.

text.zig: NUMBER_LINES digit definitions + drawNumber function (7-segment style).

render.zig: RenderContext struct with:
- drawLines(org, scale, rot, points, connect, color) -- the core vector primitive
- drawNumber(n, pos) -- vector digit rendering
- drawCircle, drawCircleLines, drawRect, drawRectLines
- drawText, measureText
- end() -- calls camera.end() + rl.endDrawing()

The RenderContext holds a *Screen pointer and a Camera2D for letterbox centering.
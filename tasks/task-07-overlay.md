# Task 07: Implement overlay.zig

Extract overlay panel rendering from zigsteroids drawHelpBox/drawGameOverBox.

OverlayOptions: title, title_color, lines, bg_color, border_color, font_size,
line_spacing, padding, gamepad_lines, stats_lines, show_gamepad, fullscreen_dim.

drawOverlay(ctx, field_size, opts) -- auto-sizes panel to fit content, draws
translucent background + border, centers all text. Optional fullscreen dim
overlay behind panel for game-over style.

centeredText(text, center_x, y, font_size, color) -- standalone helper.
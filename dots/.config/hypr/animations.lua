-- Short, non-bouncy animations, timed like niri's (cfg/animation.kdl):
-- 200 ms to open and close windows, 150 ms for everything else. Without
-- these, every animation inherits the built-in global of 800 ms.
-- Speeds are in deciseconds (1 = 100 ms).
hl.curve("easeOutQuad", { type = "bezier", points = { { 0.5, 1 }, { 0.89, 1 } } })
hl.curve("easeOutCubic", { type = "bezier", points = { { 0.33, 1 }, { 0.68, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 1.5, bezier = "easeOutCubic" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 2, bezier = "easeOutQuad", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2, bezier = "easeOutCubic", style = "popin 90%" })
hl.animation({ leaf = "layers", enabled = true, speed = 1.5, bezier = "easeOutCubic", style = "fade" })
-- Context switches on DP-1 slide vertically, as niri's workspaces did.
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.5, bezier = "easeOutCubic", style = "slidevert" })

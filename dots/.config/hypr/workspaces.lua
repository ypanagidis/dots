-- Workspaces are pinned to monitors and persistent, so Noctalia's indicator
-- always shows the full set. Numbers are what binds and rules target; the
-- names are only what the bar displays.

-- DP-1: one workspace per context, as on niri (Hyper+1..6).
local contexts = { "scratch", "Webroot", "UP", "Sealant", "Side", "Admin" }
for i, name in ipairs(contexts) do
    hl.workspace_rule({
        workspace = tostring(i),
        monitor = "DP-1",
        default = i == 1,
        default_name = name,
        persistent = true,
        layout = "monocle",
    })
end

-- HDMI-A-1: the tiled screen. Its windows stack in equal rows, like the
-- comms layout on Plasma; dwindle would halve the last split each time
-- (1/2, 1/4, 1/4). Known apps keep a fixed order, whatever order they
-- launched in; anything else goes after them.
local function ordered_layout(order, cell)
    local function rank(target)
        local class = target.window and target.window.class:lower() or ""
        return order[class] or math.huge
    end
    return {
        recalculate = function(ctx)
            local targets = {}
            for i, target in ipairs(ctx.targets) do
                targets[i] = { target = target, rank = rank(target), index = i }
            end
            table.sort(targets, function(a, b)
                if a.rank ~= b.rank then
                    return a.rank < b.rank
                end
                return a.index < b.index
            end)
            for i, entry in ipairs(targets) do
                entry.target:place(cell(ctx, i, #targets))
            end
        end,
    }
end

hl.layout.register("rows", ordered_layout(
    { slack = 1, ["org.telegram.desktop"] = 2, telegramdesktop = 2, spotify = 3 },
    function(ctx, i, n) return ctx:row(i, n) end
))

-- DP-2: Discord takes the left 65%, Grok Bot the rest. Any further windows
-- stack in rows on the right with Grok Bot.
local MAIN_RATIO = 0.65
hl.layout.register("main-left", ordered_layout(
    { discord = 1, ["grok-bot"] = 2 },
    function(ctx, i, n)
        if n == 1 then
            return ctx.area
        end
        if i == 1 then
            return ctx:split(ctx.area, "left", MAIN_RATIO)
        end
        local side = ctx:split(ctx.area, "right", 1 - MAIN_RATIO)
        local h = side.h / (n - 1)
        return { x = side.x, y = side.y + h * (i - 2), w = side.w, h = h }
    end
))

hl.workspace_rule({
    workspace = "7",
    monitor = "HDMI-A-1",
    default = true,
    default_name = "comms",
    persistent = true,
    layout = "lua:rows",
    gaps_out = 4,
    border_size = 2,
})

hl.workspace_rule({
    workspace = "8",
    monitor = "DP-2",
    default = true,
    default_name = "ambient",
    persistent = true,
    layout = "lua:main-left",
    gaps_out = 4,
    border_size = 2,
})

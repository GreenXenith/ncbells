local BELL_GAIN = 0.5
local BELL_HEAR = 64

local MODNAME = minetest.get_current_modname()

-- How tall is this bell and what note is it?
local function traverse_bell(pos, size, dir)
    if not size then
        local s, n = traverse_bell(pos, 0, 1) -- First go up, size 0
        return (traverse_bell({x = pos.x, y = pos.y - 1, z = pos.z}, s, -1)), n -- Then down, adding to size
    end

    local name = minetest.get_node(pos).name
    local note = name:match(MODNAME .. ":bell_") and tonumber(name:match("%d+$"))

    if size < 8 and note == 1 then -- Continue traversal along full bells within 8 nodes
        return traverse_bell({x = pos.x, y = pos.y + dir, z = pos.z}, size + 1, dir)
    else -- If partial bell or no bell, return current size (increment if top bell) and note (1 if no bell)
        return size + ((note and dir > 0) and 1 or 0), note or 1
    end
end

-- Play a note at a pos
local function play_note(pos)
    if not minetest.get_node(pos).name:match(MODNAME .. ":bell_") then return end

    local size, note = traverse_bell(pos)
    local step = (12 * (9 - math.min(size, 8) - 5)) - 1 + note -- ding.ogg is A5

    minetest.sound_play("ncbells_ding", {
        pos = pos,
        gain = BELL_GAIN,
        max_hear_distance = BELL_HEAR,
        pitch = (2 ^ (1 / 12)) ^ step, -- https://pages.mtu.edu/~suits/NoteFreqCalcs.html
    }, true)
end

-- 12 bells, 12 notes
for s = 1, 12 do
    local sounds = nodecore.sounds("nc_optics_glassy")
    sounds.dig = sounds.dig or {}
    sounds.dig.gain = 0.15 -- Dont overpower the bell sound

    local h = (17 - s - 8) / 16

    minetest.register_node(MODNAME .. ":bell_" .. s, {
        description = "Glass Bell",
        drawtype = "nodebox",
        tiles = {"nc_optics_glass_frost.png"},
        node_box = {
            type = "fixed",
            fixed = {
                {-2 / 16, -8 / 16, -2 / 16, -1 / 16, h,  2 / 16},
                { 2 / 16, -8 / 16, -2 / 16,  1 / 16, h,  2 / 16},
                {-1 / 16, -8 / 16, -2 / 16,  1 / 16, h, -1 / 16},
                {-1 / 16, -8 / 16,  2 / 16,  1 / 16, h,  1 / 16},
            }
        },
        selection_box = {
            type = "fixed",
            fixed = {-2 / 16, -8 / 16, -2 / 16, 2 / 16, h, 2 / 16},
        },
        collision_box = {
            type = "fixed",
            fixed = {-2 / 16, -8 / 16, -2 / 16, 2 / 16, h, 2 / 16},
        },
        groups = {
            cracky = 3,
            scaling_time = 250,
        },
        paramtype = "light",
        sunlight_propagates = true,
        sounds = sounds,
        on_punch = function(pos, node, puncher, pointed)
            -- Hit with metal shaft to ring
            if minetest.get_item_group(puncher:get_wielded_item():get_name(), "chisel") > 0 then
                play_note(pos)
                nodecore.player_discover(puncher, "ncbells:ring bell")
            end

            return minetest.node_punch(pos, node, puncher, pointed)
        end,
        after_place_node = function(pos, placer)
            -- Check for octave change to trigger hint
            local here = minetest.get_node(pos).name
            local above = minetest.get_node({x = pos.x, y = pos.y + 1, z = pos.z}).name
            local below = minetest.get_node({x = pos.x, y = pos.y - 1, z = pos.z}).name

            if (here == MODNAME .. ":bell_1" and above:match(MODNAME .. ":bell_")) or below == MODNAME .. ":bell_1" then
                nodecore.player_discover(placer, "ncbells:octave bell")
            end
        end,
    })
end

-- Split bells in (approximately) half
for i = 1, 11 do
    local height = 13 - i
    local half = math.ceil(height / 2)
    local rest = height - half
    half = 13 - half
    rest = 13 - rest
    nodecore.register_craft({
        label = "ncbells:tune bell",
        action = "pummel",
        toolgroups = {choppy = 5},
        check = function(_, data) return data.pointed.above.y == data.pointed.under.y end,
        rate_adjust = 5,
        nodes = {
            {match = MODNAME .. ":bell_" .. i, replace = "air"}
        },
        items = {
            {name = MODNAME .. ":bell_" .. half, scatter = 5},
            {name = MODNAME .. ":bell_" .. rest, scatter = 5}
        }
    })
end

-- Stack bells to recombine
for i = 1, 12 do
    for j = 1, (i == 12 and 11 or 12) do
        local total = i + j
        local lower = total >= 12 and 12 or total
        local upper = total - lower
        lower = MODNAME .. ":bell_" .. (13 - lower)
        upper = (upper <= 0) and "air" or MODNAME .. ":bell_" .. (13 - upper)
        nodecore.register_craft({
            label = "ncbells:join bell",
            nodes = {
                {match = MODNAME .. ":bell_" .. (13 - i), replace = upper},
                {y = -1, match = MODNAME .. ":bell_" .. (13 - j), replace = lower}
            }
        })
    end
end

-- Allow hinged panels to ring bells
nodecore.register_craft({
    label = "ncbells:door ring bell",
    action = "pummel",
    toolgroups = {thumpy = 1},
    check = function(_, data)
        data.bell_pos = vector.subtract(vector.multiply(data.pointed.under, 2), data.pointed.above)
        return not minetest.is_player(data.crafter) and minetest.get_node(data.bell_pos).name:match(MODNAME .. ":bell_")
    end,
    nodes = {
        {
            match = {
                groups = {chisel = true},
            }
        },
    },
    after = function(_, data)
        play_note(data.bell_pos)
    end,
})

nodecore.register_craft({
    label = "ncbells:chisel bells",
    action = "pummel",
    toolgroups = {thumpy = 3},
    normal = {y = 1},
    indexkeys = {"group:chisel"},
    nodes = {
        {
            match = {
                lode_temper_tempered = true,
                groups = {chisel = 2},
            },
            dig = true,
        },
        {
            y = -1,
            match = "nc_optics:glass_opaque",
            replace = "air",
        },
        {
            y = -2,
            match = "nc_lode:block_tempered",
        },
    },
    items = {
        {name = MODNAME .. ":bell_1 2", count = 4, scatter = 3},
    },
})

-- Hints
nodecore.register_hint("chisel some glass bells", "ncbells:chisel bells", {
    "nc_optics:glass_opaque",
    "anvil making lode rod",
})

nodecore.register_hint("ring a glass bell", "ncbells:ring bell", {
    "ncbells:chisel bells",
})

nodecore.register_hint("ring a glass bell with a hinged panel", "ncbells:door ring bell", {
    "ncbells:chisel bells",
    "group:door",
})

nodecore.register_hint("split a glass bell", "ncbells:tune bell", {
    "ncbells:chisel bells",
    "nc_lode:tool_hatchet_tempered",
})

nodecore.register_hint("join split glass bells", "ncbells:join bell", "ncbells:tune bell")

nodecore.register_hint("change a glass bell's octave", "ncbells:octave bell", {
    "ncbells:chisel bells",
})

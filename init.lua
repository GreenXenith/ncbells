local BELL_GAIN = 0.5
local BELL_HEAR = 64

local MODNAME = minetest.get_current_modname()

-- How tall is this bell and what note is it?
local function traverse_bell(pos, size, dir)
    if not size then
        local s, n, t = traverse_bell(pos, 0, 1) -- First go up, size 0
        return (traverse_bell({x = pos.x, y = pos.y - 1, z = pos.z}, s, -1)), n, t -- Then down, adding to size
    end

    local name = minetest.get_node(pos).name
    local note = name:match(MODNAME .. ":bell_") and tonumber(name:match("%d+$"))

    if size < 8 and note == 1 then -- Continue traversal along full bells within 8 nodes
        return traverse_bell({x = pos.x, y = pos.y + dir, z = pos.z}, size + 1, dir)
    else -- If partial bell or no bell, return current size (increment if top bell) and note (1 if no bell)
        return size + ((note and dir > 0) and 1 or 0), note or 1, pos
    end
end

local BOOSTEXP = 1.5
local function lodeat(pos, rx, ry, rz)
    local node = minetest.get_node({x = pos.x + rx, y = pos.y + ry, z = pos.z + rz})
    return minetest.get_item_group(node.name, "lode_cube") > 0
end
local function gainboost(pos)
    if not lodeat(pos, 0, -1, 0) then return 1 end
    local boost = 1
    for y = 0, 8 do
        local qty = (lodeat(pos, -1, y, 0) and 0.25 or 0)
            + (lodeat(pos, 1, y, 0) and 0.25 or 0)
            + (lodeat(pos, 0, y, -1) and 0.25 or 0)
            + (lodeat(pos, 0, y, 1) and 0.25 or 0)
        boost = boost + qty
        if qty <= 0 then return BOOSTEXP ^ boost end
    end
    return BOOSTEXP ^ boost
end

-- Play a note at a pos
local function play_note(pos)
    if not minetest.get_node(pos).name:match(MODNAME .. ":bell_") then return end

    local size, note, top = traverse_bell(pos)
    local step = (12 * (9 - math.min(size, 8) - 5)) - 1 + note -- ding.ogg is A5

    local bottom = {x = top.x, y = top.y - size, z = top.z}
    local boost = gainboost(bottom)
    local gain = BELL_GAIN * boost

    local function play_core(dist, subgain)
        return minetest.sound_play("ncbells_ding", {
            pos = {
                x = pos.x + (math.random() - 0.5) * dist,
                y = pos.y + (math.random() - 0.5) * dist,
                z = pos.z + (math.random() - 0.5) * dist,
            },
            gain = subgain,
            max_hear_distance = BELL_HEAR * (boost ^ 0.5),
            pitch = (2 ^ (1 / 12)) ^ step, -- https://pages.mtu.edu/~suits/NoteFreqCalcs.html
        }, true)
    end
    -- Minetest doesn't really like playing sounds with gain > 1,
    -- so if necessary, split it into multiple sounds.  Add a slight
    -- offset to give it more spatial volume.
    while gain > 1 do
        play_core(math.sqrt(gain), 1)
        gain = gain - 1
    end
    play_core(0, gain)
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

    -- Shave down bell to tune
    nodecore.register_craft({
        label = "ncbells:tune bell",
        action = "pummel",
        toolgroups = {choppy = 5},
        check = function(_, data) return data.pointed.above.y == data.pointed.under.y end,
        rate_adjust = 5,
        nodes = {
            {match = MODNAME .. ":bell_" .. s, replace = s == 12 and "air" or MODNAME .. ":bell_" .. s + 1}
        },
    })
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

nodecore.register_hint("tune a glass bell", "ncbells:tune bell", {
    "ncbells:chisel bells",
    "nc_lode:tool_hatchet_tempered",
})

nodecore.register_hint("change a glass bell's octave", "ncbells:octave bell", {
    "ncbells:chisel bells",
})

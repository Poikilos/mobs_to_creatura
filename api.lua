-- translation & mod checks

local S = core.get_translator("mobs")
local FS = function(...) return core.formspec_escape(S(...)) end

-- node check helper

local function has(nodename)
	return core.registered_nodes[nodename] and nodename
end

-- global table

mobs = {
	mod = "creatura", version = "20260310",
	spawning_mobs = {}, translate = S,
	node_snow = has(core.registered_aliases["mapgen_snow"])
			or has("mcl_core:snow") or has("default:snow") or "air",
	node_dirt = has(core.registered_aliases["mapgen_dirt"])
			or has("mcl_core:dirt") or has("default:dirt") or "mobs:fallback_node"
}
mobs.fallback_node = mobs.node_dirt

local difficulty = tonumber(core.settings:get("mob_difficulty")) or 1.0

-- https://grok.com/share/c2hhcmQtMg_0908bcdc-1699-482c-8c02-35f5656c70b4


-- Optional globals / fallbacks (define somewhere in your init)
local active_mobs = 0      -- you can increment/decrement on spawn/die if you want limits
local active_limit = 1000    -- example; make configurable
local function at_limit()
    return active_mobs >= active_limit
end

-- Fallback for creative check
local is_creative = minetest.is_creative_enabled or function(name)
    local privs = minetest.get_player_privs(name)
    return privs.creative or privs.give
end


--[[
Discarded mobs_redo attributes (not directly supported in creatura;
require custom implementation using creatura's utility/action system for
approximation):
- attack_type
- fly
- fly_in
- keep_flying
- owner
- order
- jump_height
- can_leap
- drawtype (deprecated in mobs_redo anyway; creatura assumes "mesh")
- rotate
- lifetimer
- base_mesh, base_colbox, base_selbox, base_size (backups; not needed in creatura)
- view_range (can be approximated with tracking_range if implemented)
- walk_velocity (map to max_speed or similar if available)
- run_velocity (similar to above)
- damage
- damage_group
- light_damage, light_damage_min, light_damage_max
- water_damage
- lava_damage
- fire_damage
- air_damage
- node_damage
- suffocation
- fall_damage
- fall_speed
- drops (can be handled in custom on_die)
- arrow
- arrow_override
- shoot_interval
- homing
- follow
- walk_chance
- stand_chance
- attack_chance
- attack_patience
- passive
- knock_back
- blood_amount
- blood_texture
- shoot_offset
- floats
- replace_rate
- replace_what
- replace_with
- replace_offset
- pick_up
- on_pick_up
- reach
- texture_mods
- child_texture
- docile_by_day
- fear_height
- runaway
- pathfinding (creatura has built-in A*/Theta* pathfinding)
- immune_to
- explosion_radius
- explosion_damage_radius
- explosion_timer
- allow_fuse_reset
- stop_to_explode
- dogshoot_switch
- dogshoot_count_max
- dogshoot_count2_max
- group_attack
- group_helper
- attack_monsters (or attacks_monsters)
- attack_animals
- attack_players
- attack_npcs
- attack_ignore
- specific_attack
- friendly_fire
- runaway_from
- owner_loyal
- pushable
- stay_near
- randomly_turn
- ignore_invisibility
- messages
- punch_interval
- on_flop
- do_custom
- on_replace
- custom_attack
- on_spawn
- on_blast
- do_punch
- on_breed
- on_grown
- on_sound

These attributes primarily relate to specific behaviors, attacks, or
custom logic in mobs_redo. To approximate them in creatura, implement a
def.logic function that registers utilities (scores) and actions based
on the attribute values (e.g., add a "flee" utility if runaway is true,
with score based on fear_height). Creatura's system selects and executes
the highest-utility action each step.
]]

function mobs:register_mob(name, def)
    -- Port initial_properties from mobs_redo
    local collisionbox = def.collisionbox or {-0.25, -0.25, -0.25, 0.25, 0.25, 0.25}

    -- Apply mobs_redo height fix if applicable (assume mob_height_fix is defined elsewhere or remove if not needed)
    if mob_height_fix and -collisionbox[2] + collisionbox[5] < 1.01 then
        collisionbox[5] = collisionbox[2] + 0.99
    end

    def.initial_properties = {
        hp_max = math.max(1, (def.hp_max or 10) * difficulty),  -- Assume 'difficulty' is defined globally as in mobs_redo
        physical = true,
        collisionbox = collisionbox,
        selectionbox = def.selectionbox or collisionbox,
        visual = def.visual,
        visual_size = def.visual_size or {x = 1, y = 1},
        mesh = def.mesh,
        textures = "",  -- mobs_redo sets empty; actual textures set in activate from texture_list
        makes_footstep_sound = def.makes_footstep_sound,
        stepheight = def.stepheight or 1.1,
        glow = def.glow,
        damage_texture_modifier = def.damage_texture_modifier or "^[colorize:#c9900070",
    }

    -- Preserve mobs_redo properties on def (they'll be available on self)
    def.name = name
    def.type = def.type
    def._nametag = def.nametag
    -- ... (copy other properties as needed; most will be accessible but behaviors need porting)

    -- Convert collisionbox to creatura hitbox if not provided
    if not def.hitbox then
        local box_width = math.max(math.abs(collisionbox[1]), math.abs(collisionbox[4]))
        local box_height = collisionbox[5] - collisionbox[2]
        def.hitbox = {width = box_width, height = box_height}
    end

    -- Map sounds.damage to sounds.hit if needed
    if def.sounds and def.sounds.damage and not def.sounds.hit then
        def.sounds.hit = def.sounds.damage
    end

    -- Set vitals using hp_max and armor
    def._vitals = def._vitals or {
        hp = def.hp_max or 10,
        armor = def.armor or 100
    }

    -- Handle textures: mobs_redo uses texture_list; set for random selection in custom activate if overridden
    def.texture_list = def.textures  -- Preserve for later use

    -- For hp_min: mobs_redo randomizes health on spawn; creatura may handle differently.
    -- Override activate to set self.health = math.random(def.hp_min, def.hp_max)

    -- Optional: Override on_activate to include mobs_redo logic (e.g., texture selection, health randomization)
    local creatura_activate = def.on_activate  -- Preserve if set
    def.on_activate = function(self, staticdata, dtime)
        -- mobs_redo-like init (port relevant parts from mobs_redo mob_activate)
        self.health = math.random(def.hp_min or 1, def.hp_max or 10)
        if def.texture_list then
            self.texture = math.random_choice(def.texture_list)  -- Assume random_choice defined
            self.object:set_properties({textures = self.texture})
        end
        -- ... (add other init logic as needed)

        -- Call creatura's activate
        if creatura_activate then
            return creatura_activate(self, staticdata, dtime)
        else
            return self:activate(staticdata, dtime)
        end
    end

    -- Optional: Set a basic logic function to approximate behaviors (expand based on creatura API)
    -- def.logic = function(self)
        -- Example: Use def.type to register utilities/actions
        -- This requires defining actions/utilities separately (e.g., in your mod)
        -- creatura.register_action(self, "wander", {func = wander_func, utility = def.walk_chance / 100})
        -- if def.runaway then creatura.register_utility("flee", flee_score) end
        -- self:execute_utilities()  -- Assuming this runs the system
    -- end

    -- Register with creatura
    creatura.register_mob(name, def)
end


-- Optional: Make these configurable via settings or per-mob
local SPAWN_INTERVAL   = 30     -- seconds
local SPAWN_CHANCE     = 5000   -- 1 in X chance per check
local MAX_SPAWN_LIGHT  = 15
local MIN_SPAWN_LIGHT  = 0
local MAX_ACTIVE_MOBS  = 1       -- per spawn attempt area
local DEFAULT_NODES    = {"group:soil", "group:stone"}
local DEFAULT_NEIGHBORS = {"air"}

-- Table to store spawn definitions (name → def)
mobs.spawning_mobs = mobs.spawning_mobs or {}   -- already exists in your code

-- Emulate mobs:spawn(def)
function mobs:spawn(spawn_def)
    local name = spawn_def.name
    -- if not name or not creatura.registered_mobs[name] then
    if not name or not core.registered_entities[name] then
        minetest.log("warning", "[mobs → creatura] Cannot register spawn for unknown mob: " .. (name or "?"))
        return
    end

    mobs.spawning_mobs[name] = {
        nodes     = spawn_def.nodes     or DEFAULT_NODES,
        neighbors = spawn_def.neighbors or DEFAULT_NEIGHBORS,
        min_light = spawn_def.min_light or MIN_SPAWN_LIGHT,
        max_light = spawn_def.max_light or MAX_SPAWN_LIGHT,
        interval  = spawn_def.interval  or SPAWN_INTERVAL,
        chance    = spawn_def.chance    or SPAWN_CHANCE,
        active_object_count = spawn_def.active_object_count or MAX_ACTIVE_MOBS,
        min_height = spawn_def.min_height or -31000,
        max_height = spawn_def.max_height or 31000,
        day_toggle = spawn_def.day_toggle,          -- nil = always, true = day only, false = night only
        on_spawn   = spawn_def.on_spawn,            -- function(self, pos)
        on_map_load = spawn_def.on_map_load,        -- rarely used, usually nil
    }

    minetest.log("action", "[mobs → creatura] Registered spawning for " .. name)
end

--[[
Creatura leaves spawning up to the mob mod.
So calling the emulated mobs:spawn function above won't actually do anything without:

-- The actual spawning ABM / globalstep loop
-- (You can use minetest.register_abm(...) instead of globalstep if you prefer)
minetest.register_globalstep(function(dtime)
    -- Optional: throttle to avoid running every single step
    static_spawn_timer = (static_spawn_timer or 0) + dtime
    if static_spawn_timer < 1 then return end   -- run ~once per second
    static_spawn_timer = 0

    for name, sdef in pairs(mobs.spawning_mobs) do
        -- Quick skip if chance is very low or interval not ready
        if math.random(1, sdef.chance or 8000) ~= 1 then goto continue end

        -- Find a suitable player to spawn near (like mobs_redo does)
        local players = minetest.get_connected_players()
        if #players == 0 then goto continue end

        local player = players[math.random(#players)]
        local ppos = player:get_pos()

        -- Only attempt spawn if player is active / loaded area
        if not ppos then goto continue end

        -- Random offset around player (mobs_redo typically uses ~30-50 node radius)
        local dx = math.random(-40, 40)
        local dz = math.random(-40, 40)
        local try_pos = vector.add(ppos, {x=dx, y=0, z=dz})
        try_pos.y = try_pos.y + math.random(-10, 30)  -- slight vertical variation

        local pos = minetest.find_node_near(try_pos, 8, sdef.nodes, true)  -- find matching node
        if not pos then goto continue end

        -- Check height range
        if pos.y < sdef.min_height or pos.y > sdef.max_height then goto continue end

        -- Check light
        local light = minetest.get_node_light(pos) or 0
        if light < sdef.min_light or light > sdef.max_light then goto continue end

        -- Day/night toggle
        local is_day = (minetest.get_timeofday() >= 0.25 and minetest.get_timeofday() <= 0.75)
        if sdef.day_toggle == true and not is_day then goto continue end
        if sdef.day_toggle == false and is_day then goto continue end

        -- Neighbors check (air above, etc.)
        local above = vector.add(pos, {x=0,y=1,z=0})
        local node_above = minetest.get_node(above).name
        if not table.contains(sdef.neighbors, node_above) and
           not minetest.registered_nodes[node_above].groups[sdef.neighbors[1]:gsub("group:", "")] then
            goto continue
        end

        -- Active object count check (simple version)
        local objs = minetest.get_objects_inside_radius(pos, 5)
        local count = 0
        for _, obj in ipairs(objs) do
            if obj:get_luaentity() and obj:get_luaentity().name == name then
                count = count + 1
            end
        end
        if count >= sdef.active_object_count then goto continue end

        -- Finally spawn!
        local obj = minetest.add_entity(pos, name)
        if obj and obj:get_luaentity() then
            local self = obj:get_luaentity()
            if sdef.on_spawn then
                sdef.on_spawn(self, pos)
            end
            minetest.log("verbose", "[mobs → creatura] Spawned " .. name .. " at " .. minetest.pos_to_string(pos))
        end

        ::continue::
    end
end)


]]


function mobs:register_egg(mob_name, desc, background_img, addegg, no_creative, can_spawn_protect)
    local grp_generic = {spawn_egg = 1}
    if no_creative then
        grp_generic.not_in_creative_inventory = 1
    end

    local invimg = background_img
    if addegg == 1 then
        invimg = "(mobs_chicken_egg.png^(" .. background_img
              .. "^[mask:mobs_chicken_egg_overlay.png))"
    end

    -- Check if mob exists
    if not core.registered_entities[mob_name] then
        minetest.log("warning", "[mobs → creatura] Cannot create spawn egg for unknown mob: " .. mob_name)
        return
    end

    -- Get y offset from collisionbox (bottom of box)
    local ent_def = core.registered_entities[mob_name]
    local props = ent_def.initial_properties or {}
    local colbox = props.collisionbox or {-0.5, 0, -0.5, 0.5, 1, 0.5}
    local y_offset = -colbox[2]  -- usually positive value to spawn above clicked node

    -- === Tamed / Set Egg (non-stackable, for captured/tamed mobs) ===
    -- Only register if mob is likely tamable (most Creatura animals are)
    core.register_craftitem(":" .. mob_name .. "_set", {
        description = S("@1 (Tamed)", desc),
        inventory_image = invimg,
        groups = {spawn_egg = 2, not_in_creative_inventory = 1},
        stack_max = 1,

        on_place = function(itemstack, placer, pointed_thing)
            if pointed_thing.type ~= "node" then return itemstack end

            local pos = pointed_thing.above
            if not pos then return itemstack end

            -- Handle node right-click passthrough
            local under = pointed_thing.under
            local node = minetest.get_node(under)
            local ndef = minetest.registered_nodes[node.name]
            if ndef and ndef.on_rightclick then
                return ndef.on_rightclick(under, node, placer, itemstack, pointed_thing)
            end

            -- Protection check
            if not can_spawn_protect and minetest.is_protected(pos, placer:get_player_name()) then
                return itemstack
            end

            -- Optional active limit (comment out if unwanted)
            if at_limit() then
                minetest.chat_send_player(placer:get_player_name(),
                    S("Active Mob Limit Reached!") .. " (" .. active_mobs .. " / " .. active_limit .. ")")
                return itemstack
            end

            pos.y = pos.y + y_offset

            local meta = itemstack:get_meta()
            local staticdata = meta:get_string("staticdata")  -- or whatever field you use

            local obj = minetest.add_entity(pos, mob_name, staticdata)
            if not obj then return itemstack end

            local self = obj:get_luaentity()
            if not self then return itemstack end

            -- Set owner/tamed (adapt to Creatura convention)
            self.owner = placer:get_player_name()
            self.tamed = true
            -- If Creatura uses different field names, adjust here (e.g. self:tame(placer))

            itemstack:take_item()  -- unique item
            return itemstack
        end,
    })

    -- === Generic Spawn Egg (stackable) ===
    core.register_craftitem(":" .. mob_name, {
        description = desc,
        inventory_image = invimg,
        groups = grp_generic,

        on_place = function(itemstack, placer, pointed_thing)
            if pointed_thing.type ~= "node" then return itemstack end

            local pos = pointed_thing.above
            if not pos then return itemstack end

            -- passthrough right-click
            local under = pointed_thing.under
            local node = minetest.get_node(under)
            local ndef = minetest.registered_nodes[node.name]
            if ndef and ndef.on_rightclick then
                return ndef.on_rightclick(under, node, placer, itemstack, pointed_thing)
            end

            if not can_spawn_protect and minetest.is_protected(pos, placer:get_player_name()) then
                return itemstack
            end

            if at_limit() then
                minetest.chat_send_player(placer:get_player_name(),
                    S("Active Mob Limit Reached!") .. " (" .. active_mobs .. " / " .. active_limit .. ")")
                return itemstack
            end

            pos.y = pos.y + y_offset

            local obj = minetest.add_entity(pos, mob_name)
            if not obj then return itemstack end

            local self = obj:get_luaentity()
            if not self then return itemstack end

            -- Only tame if not monster and not sneaking
            if self.type ~= "monster" and not placer:get_player_control().sneak then
                self.owner = placer:get_player_name()
                self.tamed = true
            end

            -- Take item unless in creative
            if not is_creative(placer:get_player_name()) then
                itemstack:take_item()
            end

            return itemstack
        end,
    })

    minetest.log("action", "[mobs → creatura] Registered spawn eggs for " .. mob_name)
end
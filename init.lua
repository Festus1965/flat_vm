-- Ruins init.lua
-- Copyright Duane Robertson (duane@duanerobertson.com), 2019
-- Distributed under the LGPLv2.1 (https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html)


flat_vm = {}
local mod = flat_vm
local mod_name = 'flat_vm'

mod.version = '20190530'
mod.path = minetest.get_modpath(minetest.get_current_modname())
mod.world = minetest.get_worldpath()


local DEBUG
local enable_roads = minetest.settings:get_bool('flat_vm_enable_houses')
local enable_houses = minetest.settings:get_bool('flat_vm_enable_houses')
local enable_layer_relighting = minetest.settings:get_bool('flat_vm_enable_layer_lighting')

if enable_roads == nil then
	enable_roads = true
end

if enable_houses == nil then
	enable_houses = true
end

if enable_layer_relighting == nil then
	enable_layer_relighting = false
end

local layer_depth = 6000
local chunk_offset = 32

local Geomorph = geomorph.Geomorph
local math_max = math.max
local math_floor = math.floor
local os_clock = os.clock


local VN = vector.new
local base_level = 8  -- get mgflat_ground_level


local ruin_time = 0
local time_all = 0
local chunk_count = 0


local ore_odds, total_ore_odds
local ores = {
	'default:stone_with_coal',
	'default:stone_with_iron',
	'default:stone_with_copper',
	'default:stone_with_tin',
	'default:stone_with_gold',
	'default:stone_with_diamond',
	'default:stone_with_mese',
}


-- This tables looks up nodes that aren't already stored.
mod.node = setmetatable({}, {
	__index = function(t, k)
		if not (t and k and type(t) == 'table') then
			return
		end

		t[k] = minetest.get_content_id(k)
		return t[k]
	end
})
local node = mod.node


minetest.register_on_shutdown(function()
  print('time ruins: '..math.floor(1000 * ruin_time / chunk_count))

  print('Total Time: '..math.floor(1000 * time_all / chunk_count))
  print('chunks: '..chunk_count)
end)


local function generate(minp, maxp, seed)
	if not (minp and maxp and seed) then
		return
	end

	local t_all = os_clock()

	local layer = math_floor((minp.y + (layer_depth / 2) + chunk_offset) / layer_depth)
	local y_level = layer * layer_depth - chunk_offset

	do
		local go
		if minp.y == y_level and (enable_roads or enable_houses) then
			go = true
		end
		if enable_layer_relighting and minp.y < -chunk_offset
		and minp.y >= y_level and minp.y < y_level + layer_depth / 2 then
			go = true
		end

		if not go then
			chunk_count = chunk_count + 1
			time_all = time_all + os_clock() - t_all
			return
		end
	end

	mod.minp = minp
	mod.maxp = maxp
	mod.seed = seed
	mod.gpr = PcgRandom(seed + 3107)

	if not mod.csize then
		mod.csize = vector.add(vector.subtract(maxp, minp), 1)

		if not mod.csize then
			return
		end
	end

	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	if not (vm and emin and emax) then
		return
	end
	mod.vm = vm

	if (enable_roads or enable_houses) and minp.y == y_level then
		mod.data = vm:get_data(mod.data)
		mod.p2data = vm:get_param2_data(mod.p2data)
		mod.area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})

		mod.puzzle_boxes = {}

		mod.heightmap = minetest.get_mapgen_object('heightmap')

		local t_ruin = os_clock()
		map_roads()
		if enable_houses then
			houses(y_level)
		end
		ruin_time = ruin_time + os_clock() - t_ruin

		mod.vm:set_data(mod.data)
		mod.vm:set_param2_data(mod.p2data)
	end

	--local lmin = table.copy(mod.minp)
	--local lmax = table.copy(mod.maxp)
	--lmin.y = base_level - 2
	--lmax.y = lmin.y + 25

	if DEBUG then
		mod.vm:set_lighting({day = 10, night = 10})
	else
		mod.vm:set_lighting({day = 0, night = 0}, mod.minp, mod.maxp)
		mod.vm:calc_lighting(nil, nil, false)
	end

	--mod.vm:update_liquids()
	mod.vm:write_to_map()

	chunk_count = chunk_count + 1

	local mem = math.floor(collectgarbage('count')/1024)
	if mem > 200 then
		print('Lua Memory: ' .. mem .. 'M')
	end

	time_all = time_all + os_clock() - t_all
end

minetest.register_on_generated(generate)


local house_materials = {'sandstonebrick', 'desert_stonebrick', 'stonebrick', 'brick', 'wood', 'junglewood'}
function houses(y_level)
	if not Geomorph then
		return
	end

	local csize, area = mod.csize, mod.area
	local boxes = mod.boxes
	local pr = mod.gpr
	local heightmap = mod.heightmap
	local stone = 'default:sandstone'
	for _, box in pairs(boxes) do
		box.pos.y = box.pos.y + 32

		local pos = vector.add(box.pos, -2)
		local sz = vector.add(box.sz, 4)
		local good = true

		for z = pos.z, pos.z + sz.z do
			for x = pos.x, pos.x + sz.x do
				local index = z * csize.x + x + 1
				if not heightmap[index] or heightmap[index] < base_level + y_level + 32 - 1 or heightmap[index] > base_level + y_level + 32 + 1 then
					good = false
					break
				end
			end
			if not good then
				break
			end
		end

		if good then
			local walls, roof
			while walls == roof do
				walls = (house_materials)[pr:next(1, #house_materials)]
				roof = (house_materials)[pr:next(1, #house_materials)]
			end
			local walls1 = 'default:'..walls
			local roof1 = 'default:'..roof
			local roof2 = 'stairs:stair_'..roof
			local geo = Geomorph.new()
			local lev = pr:next(1, 4) - 2
			if lev == 0 and #mod.puzzle_boxes == 0 and box.sz.x >= 7 and box.sz.z >= 7 then
				local width = 7
				mod.puzzle_boxes[#mod.puzzle_boxes+1] = {
					pos = table.copy(pos),
					size = VN(width, width, width),
				}
			else
				lev = math_max(1, lev)

				-- foundation
				pos = table.copy(box.pos)
				pos.y = pos.y - 1
				sz = table.copy(box.sz)
				sz.y = 1
				geo:add({
					action = 'cube',
					node = 'default:cobble',
					location = pos,
					size = sz,
				})

				pos = table.copy(box.pos)
				pos.y = pos.y + lev * 5
				sz = table.copy(box.sz)
				if pr:next(1, 3) == 1 then
					sz.y = 1
					geo:add({
						action = 'cube',
						node = roof1,
						location = pos,
						size = sz,
					})
				elseif box.sz.x <= box.sz.z then
					sz.x = math_floor(sz.x / 2)
					if false then
						geo:add({
							action = 'stair',
							depth_fill = roof1,
							node = roof2,
							location = pos,
							p2 = 1,
							size = VN(sz.x, sz.y, 1),
						})
						geo:add({
							action = 'stair',
							depth_fill = roof1,
							node = roof2,
							location = VN(pos.x, pos.y, pos.z + sz.z - 1),
							p2 = 1,
							size = VN(sz.x, sz.y, 1),
						})
						geo:add({
							action = 'stair',
							depth = 0,
							node = roof2,
							location = pos,
							p2 = 1,
							size = sz,
						})
					end

					local pos2 = table.copy(pos)
					pos2.x = pos2.x + sz.x
					pos2.y = pos2.y + sz.x - 1
					if false then
						geo:add({
							action = 'cube',
							node = roof1,
							location = pos2,
							size = VN(1, 1, sz.z),
						})
						geo:add({
							action = 'cube',
							node = roof1,
							location = VN(pos2.x, pos.y, pos2.z + box.sz.z - 1),
							size = VN(1, sz.x, 1),
						})
						geo:add({
							action = 'cube',
							node = roof1,
							location = VN(pos2.x, pos.y, pos2.z),
							size = VN(1, sz.x, 1),
						})
					end

					pos = table.copy(pos)
					pos.x = pos.x + box.sz.x - sz.x
					if false then
						geo:add({
							action = 'stair',
							depth = 0,
							node = roof2,
							location = pos,
							p2 = 3,
							size = sz,
						})
						geo:add({
							action = 'stair',
							depth_fill = roof1,
							node = roof2,
							location = pos,
							p2 = 3,
							size = VN(sz.x, sz.y, 1),
						})
						geo:add({
							action = 'stair',
							depth_fill = roof1,
							node = roof2,
							location = VN(pos.x, pos.y, pos.z + sz.z - 1),
							p2 = 3,
							size = VN(sz.x, sz.y, 1),
						})
					end
				else
					sz.z = math_floor(sz.z / 2)
					if false then
						geo:add({
							action = 'stair',
							depth_fill = roof1,
							node = roof2,
							location = pos,
							p2 = 0,
							size = VN(1, sz.y, sz.z),
						})
						geo:add({
							action = 'stair',
							depth_fill = roof1,
							node = roof2,
							location = VN(pos.x + sz.x - 1, pos.y, pos.z),
							p2 = 0,
							size = VN(1, sz.y, sz.z),
						})
						geo:add({
							action = 'stair',
							depth = 0,
							node = roof2,
							location = pos,
							p2 = 0,
							size = sz,
						})
					end

					local pos2 = table.copy(pos)
					pos2.z = pos2.z + sz.z
					pos2.y = pos2.y + sz.z - 1
					if false then
						geo:add({
							action = 'cube',
							node = roof1,
							location = pos2,
							size = VN(sz.x, 1, 1),
						})
						geo:add({
							action = 'cube',
							node = roof1,
							location = VN(pos2.x + box.sz.x - 1, pos.y, pos2.z),
							size = VN(1, sz.z, 1),
						})
						geo:add({
							action = 'cube',
							node = roof1,
							location = VN(pos2.x, pos.y, pos2.z),
							size = VN(1, sz.z, 1),
						})
					end

					pos = table.copy(pos)
					pos.z = pos.z + box.sz.z - sz.z
					if false then
						geo:add({
							action = 'stair',
							depth = 0,
							node = roof2,
							location = pos,
							p2 = 2,
							size = sz,
						})
						geo:add({
							action = 'stair',
							depth_fill = roof1,
							node = roof2,
							location = pos,
							p2 = 2,
							size = VN(1, sz.y, sz.z),
						})
						geo:add({
							action = 'stair',
							depth_fill = roof1,
							node = roof2,
							location = VN(pos.x + sz.x - 1, pos.y, pos.z),
							p2 = 2,
							size = VN(1, sz.y, sz.z),
						})
					end
				end
				pos = table.copy(box.pos)
				pos.y = box.pos.y
				sz = table.copy(box.sz)
				sz.y = lev * 5
				geo:add({
					action = 'cube',
					node = walls1,
					location = pos,
					size = sz,
				})
				for y = 0, lev - 1 do
					local pos2 = vector.add(pos, 1)
					local sz2 = vector.add(sz, -2)
					pos2.y = box.pos.y + y * 5 + 1
					sz2.y = 4
					geo:add({
						action = 'cube',
						node = 'air',
						location = pos2,
						size = sz2,
					})
				end

				pos = table.copy(box.pos)
				sz = table.copy(box.sz)
				for y = 0, lev - 1 do
					for z = box.pos.z + 2, box.pos.z + box.sz.z, 4 do
						geo:add({
							action = 'cube',
							node = 'air',
							location = VN(box.pos.x, box.pos.y + y * 5 + 2, z),
							size = VN(box.sz.x, 2, 2),
						})
					end
					for x = box.pos.x + 2, box.pos.x + box.sz.x, 4 do
						geo:add({
							action = 'cube',
							node = 'air',
							location = VN(x, box.pos.y + y * 5 + 2, box.pos.z),
							size = VN(2, 2, box.sz.z),
						})
					end
				end

				if true then
					local l = math_max(box.sz.x, box.sz.z)
					local f = pr:next(0, 2)
					pos = vector.round(vector.add(box.pos, vector.divide(box.sz, 2)))
					pos = vector.subtract(pos, math_floor(l / 2 + 0.5) - f)
					pos.y = pos.y + lev * 5
					geo:add({
						action = 'sphere',
						node = 'air',
						intersect = {walls1, roof1, roof2},
						location = pos,
						size = VN(l - 2 * f, 20, l - 2 * f),
					})

					for i = 1, 3 do
						local pos2 = table.copy(pos)
						pos2.x = pos2.x + pr:next(0, box.sz.x) - math_floor(box.sz.x / 2)
						pos2.z = pos2.z + pr:next(0, box.sz.z) - math_floor(box.sz.z / 2)

						geo:add({
							action = 'sphere',
							node = 'air',
							intersect = {walls1, roof1, roof2},
							location = pos2,
							size = VN(l, 20, l),
						})
					end
				end
			end

			do
				local ore
				pos = table.copy(box.pos)
				local size = table.copy(box.sz)
				if ore_odds then
					local orn = pr:next(1, total_ore_odds)
					local i = 0
					for _, od in pairs(ore_odds) do
						i = i + 1
						if orn <= od then
							orn = i
							break
						end
						orn = orn - od
					end
					ore = ores[orn]
				else
					ore = ores[1]
				end
				geo:add({
					action = 'cube',
					node = ore,
					intersect = {walls1, roof1, roof2},
					location = pos,
					size = size,
					random = 50,
				})
			end

			geo:write_to_map(mod, 0)
		end
	end
end


local road_w = 5
local potholes = 10
local moss = 3
local n_road = node['default:cobble']
local n_road_wet = node['default:mossycobble']
local road_noise
local default_terrain = {offset = 0, scale = 1, seed = 7244, spread = {x = 600, y = 600, z = 600}, octaves = 5, persist = 0.6, lacunarity = 2.0}
local road_noise_def = minetest.get_noiseparams('mgflat_np_terrain') or default_terrain
road_noise_def.offset = road_noise_def.offset + road_w
road_noise_def.scale = 50
road_noise_def.octaves = road_noise_def.octaves - 2

local road_replace_dry = {
	[node['default:stone']] = true,
	[node['default:sandstone']] = true,
	[node['default:desert_sandstone']] = true,
	[node['default:dirt']] = true,
	[node['default:snowblock']] = true,
	[node['default:sand']] = true,
	[node['default:silver_sand']] = true,
	[node['default:desert_sand']] = true,
	[node['default:dirt_with_dry_grass']] = true,
}
local road_replace_wet = {
	[node['default:dirt_with_grass']] = true,
	[node['default:dirt_with_coniferous_litter']] = true,
	[node['default:dirt_with_rainforest_litter']] = true,
	[node['default:dirt_with_snow']] = true,
}

function map_roads()
	local csize, area = mod.csize, mod.area
	local gpr = mod.gpr
	local data = mod.data
	local minp = mod.minp
	local maxp = mod.maxp
	local roads = {}
	local has_roads = false

	local index = 1
	if enable_roads and road_noise_def then
		road_noise = minetest.get_perlin_map(road_noise_def, {x=mod.csize.x + road_w * 2, y=mod.csize.z + road_w * 2}):get_2d_map_flat({x=mod.minp.x, y=mod.minp.z}, road_noise)

		local road_ws = road_w * road_w
		for x = -road_w, csize.x + road_w - 1 do
			index = x + road_w + 1
			local l_road = road_noise[index]
			for z = -road_w, csize.z + road_w - 1 do
				local road_1 = road_noise[index]
				if (l_road < 0) ~= (road_1 < 0) then
					local index2 = z * csize.x + x + 1
					for zo = -road_w, road_w do
						local zos = zo * zo
						for xo = -road_w, road_w do
							if x + xo >= 0 and x + xo < csize.x
							and z + zo >= 0 and z + zo < csize.z then
								if xo * xo + zos < road_ws then
									roads[index2 + zo * csize.x + xo] = true
									has_roads = true
								end
							end
						end
					end
				end
				l_road = road_1
				index = index + csize.x + road_w * 2
			end
		end

		-- Mark the road locations.
		index = 1
		for z = -road_w, csize.z + road_w - 1 do
			local l_road = road_noise[index]
			for x = -road_w, csize.x + road_w - 1 do
				local road_1 = road_noise[index]
				if (l_road < 0) ~= (road_1 < 0) then
					local index2 = z * csize.x + x + 1
					for zo = -road_w, road_w do
						local zos = zo * zo
						for xo = -road_w, road_w do
							if x + xo >= 0 and x + xo < csize.x and z + zo >= 0 and z + zo < csize.z then
								if xo * xo + zos < road_ws then
									roads[index2 + zo * csize.x + xo] = true
									has_roads = true
								end
							end
						end
					end
				end
				l_road = road_1
				index = index + 1
			end
		end
	end

	local boxes = {}

	-- Generate boxes for constructions.
	for ct = 1, 15 do
		local scale = gpr:next(1, 2) * 4
		local sz = VN(gpr:next(1, 2), 1, gpr:next(1, 2))
		sz.x = sz.x * scale + 9
		sz.y = sz.y * 8
		sz.z = sz.z * scale + 9

		for ct2 = 1, 10 do
			local pos = VN(gpr:next(2, csize.x - sz.x - 3), base_level, gpr:next(2, csize.z - sz.z - 3))
			local good = true
			for _, box in pairs(boxes) do
				if box.pos.x + box.sz.x < pos.x
				or pos.x + sz.x < box.pos.x
				or box.pos.z + box.sz.z < pos.z
				or pos.z + sz.z < box.pos.z then
					-- nop
				else
					good = false
					break
				end
			end
			for z = pos.z, pos.z + sz.z do
				for x = pos.x, pos.x + sz.x do
					local index = z * csize.x + x + 1
					if roads[index] then
						good = false
						break
					end
				end
				if not good then
					break
				end
			end
			if good then
				pos.y = pos.y - 2
				table.insert(boxes, {
					pos = vector.add(pos, 2),
					sz = vector.add(sz, -4)
				})
				break
			end
		end
	end

	if has_roads then
		index = 1
		for z = minp.z, maxp.z do
			local ivm = area:index(minp.x, minp.y + base_level + chunk_offset, z)
			for x = minp.x, maxp.x do
				if roads[index] then
					local ps = gpr:next(1, potholes)
					if ps > 1 then
						ps = gpr:next(1, moss)
						if road_replace_dry[data[ivm]] or (road_replace_wet[data[ivm]] and ps > 1) then
							data[ivm] = n_road
						elseif road_replace_wet[data[ivm]] then
							data[ivm] = n_road_wet
						end
					end
				end
				index = index + 1
				ivm = ivm + 1
			end
		end
	end

	mod.boxes = boxes
	mod.has_roads = has_roads
	mod.roads = roads
end

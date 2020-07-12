extends Node2D

var Room = preload("res://Room.tscn")
var Player = preload("res://Character.tscn")
var font = preload("res://assets/RobotoBold120.tres")
onready var Map = $TileMap

var tile_size = 16  # size of a tile in the TileMap
var num_rooms = 20  # number of rooms to generate
var min_size = 6  # minimum room size (in tiles)
var max_size = 15  # maximum room size (in tiles)
var hspread = 400  # horizontal spread (in pixels)
var cull = 0.5  # chance to cull room
var shape = 1 # chance of room being reshaped
var decorated = 0.3 # shape of the room having decorations like fountains, statues or pillars

var path  # AStar pathfinding object
var start_room = null
var end_room = null
var play_mode = false  
var player = null

func _ready():
	randomize()
	make_rooms()
	
func make_rooms():
	for i in range(num_rooms):
		var pos = Vector2(rand_range(-hspread, hspread), 0)
		var r = Room.instance()
		var w = min_size + randi() % (max_size - min_size)
		var h = min_size + randi() % (max_size - min_size)
		r.make_room(pos, Vector2(w, h) * tile_size)
		$Rooms.add_child(r)
	# wait for movement to stop
	yield(get_tree().create_timer(1.1), 'timeout')
	# cull rooms
	var room_positions = []
	for room in $Rooms.get_children():
		if randf() < cull:
			room.queue_free()
		else:
			room.mode = RigidBody2D.MODE_STATIC
			room_positions.append(Vector3(room.position.x,
										  room.position.y, 0))
	yield(get_tree(), 'idle_frame')
	# generate a minimum spanning tree connecting the rooms
	path = find_mst(room_positions)
			
func _draw():
	if start_room:
		draw_string(font, start_room.position-Vector2(125,0), "start", Color(1,1,1))
	if end_room:
		draw_string(font, end_room.position-Vector2(125,0), "end", Color(1,1,1))
	if play_mode:
		return
	for room in $Rooms.get_children():
		draw_rect(Rect2(room.position - room.size, room.size * 2),
				 Color(0, 1, 0), false)
	if path:
		for p in path.get_points():
			for c in path.get_point_connections(p):
				var pp = path.get_point_position(p)
				var cp = path.get_point_position(c)
				draw_line(Vector2(pp.x, pp.y), Vector2(cp.x, cp.y),
						  Color(1, 1, 0), 15, true)

func _process(_delta):
	update()
	
func _input(event):
	if event.is_action_pressed('ui_select'):
		if play_mode:
			player.queue_free()
			play_mode = false
		for n in $Rooms.get_children():
			n.queue_free()
		path = null
		start_room = null
		end_room = null
		make_rooms()
	if event.is_action_pressed('ui_focus_next'):
		make_map()
	if event.is_action_pressed('ui_cancel'):
		player = Player.instance()
		add_child(player)
		player.position = start_room.position
		play_mode = true

func find_mst(nodes):
	# Prim's algorithm
	# Given an array of positions (nodes), generates a minimum
	# spanning tree
	# Returns an AStar object
	
	# Initialize the AStar and add the first point
	var path = AStar.new()
	path.add_point(path.get_available_point_id(), nodes.pop_front())
	
	# Repeat until no more nodes remain
	while nodes:
		var min_dist = INF  # Minimum distance so far
		var min_p = null  # Position of that node
		var p = null  # Current position
		# Loop through points in path
		for p1 in path.get_points():
			p1 = path.get_point_position(p1)
			# Loop through the remaining nodes
			for p2 in nodes:
				# If the node is closer, make it the closest
				if p1.distance_to(p2) < min_dist:
					min_dist = p1.distance_to(p2)
					min_p = p2
					p = p1
		# Insert the resulting node into the path and add
		# its connection
		var n = path.get_available_point_id()
		path.add_point(n, min_p)
		path.connect_points(path.get_closest_point(p), n)
		# Remove the node from the array so it isn't visited again
		nodes.erase(min_p)
	return path
		
func make_map():
	# Create a TileMap from the generated rooms and path
	Map.clear()
	find_start_room()
	find_end_room()
	
	# Fill TileMap with walls, then carve empty rooms
	var full_rect = Rect2()
	for room in $Rooms.get_children():
		var r = Rect2(room.position-room.size,
					room.get_node("CollisionShape2D").shape.extents*2)
		full_rect = full_rect.merge(r)
	var topleft = Map.world_to_map(full_rect.position)
	var bottomright = Map.world_to_map(full_rect.end)
	for x in range(topleft.x, bottomright.x):
		for y in range(topleft.y, bottomright.y):
			Map.set_cell(x, y, 1)	
	
	# Carve rooms
	var corridors = []  # One corridor per connection
	for room in $Rooms.get_children():
		var s = (room.size / tile_size).floor()
		var pos = Map.world_to_map(room.position)
		var ul = (room.position / tile_size).floor() - s
		for x in range(2, s.x * 2 - 1):
			for y in range(2, s.y * 2 - 1):
				Map.set_cell(ul.x + x, ul.y + y, 0)
		
		if randf() < shape:
			round_room(room)
		
		if randf() < decorated:
			place_decor(room)
	
		# Carve connecting corridor
		var p = path.get_closest_point(Vector3(room.position.x, 
											room.position.y, 0))
		for conn in path.get_point_connections(p):
			if not conn in corridors:
				var start = Map.world_to_map(Vector2(path.get_point_position(p).x,
													path.get_point_position(p).y))
				var end = Map.world_to_map(Vector2(path.get_point_position(conn).x,
													path.get_point_position(conn).y))									
				carve_path(start, end)
		corridors.append(p)
				
				
func round_room(room):
	var s = room.get_room_size_in_tiles(tile_size)
	var room_center = room.get_room_pos_in_tiles(tile_size)
	var upperleft = room_center - s
	var bottomright = room_center + s
	var upperright = Vector2(room_center.x + s.x, room_center.y - s.y)
	var bottomleft = Vector2(room_center.x - s.x, room_center.y + s.y)
	var rx = floor((s.x*2) / 3)
	var ry = floor((s.y*2) / 3)
	var i = ry
	if rx <= ry: 
		i = rx
	var g = i
	for i in range(g,0,-1): 
		Map.set_cell(upperleft.x + (g-(i-1)), upperleft.y + i, 1)
		Map.set_cell(bottomright.x - (g-(i-1)), bottomright.y - i, 1)
		Map.set_cell(upperright.x - (g-(i-1)), upperleft.y + i, 1)
		Map.set_cell(bottomleft.x + (g-(i-1)), bottomright.y - i, 1)
		for j in range(i,0,-1):
			Map.set_cell(upperleft.x + j, upperleft.y + (i-(j-1)), 1)
			Map.set_cell(bottomright.x - j, bottomright.y - (i-(j-1)), 1)
			Map.set_cell(upperright.x - j, upperleft.y + (i-(j-1)), 1)
			Map.set_cell(bottomleft.x + j, bottomright.y - (i-(j-1)), 1)


func place_decor(room):
	var s = room.get_room_size_in_tiles(tile_size)
	var room_center = room.get_room_pos_in_tiles(tile_size)
	var upperleft = room_center - s
	var bottomright = room_center + s
	var upperright = Vector2(room_center.x + s.x, room_center.y - s.y)
	var bottomleft = Vector2(room_center.x - s.x, room_center.y + s.y)
	var rx = floor((s.x*2) / 4)
	var ry = floor((s.y*2) / 4)
	Map.set_cell(upperleft.x + (rx+2), upperleft.y + (ry+2), 1)
	Map.set_cell(bottomright.x - (rx+2), bottomright.y - (ry+2), 1)
	Map.set_cell(upperright.x - (rx+2), upperleft.y + (ry+2), 1)
	Map.set_cell(bottomleft.x + (rx+2), bottomright.y - (ry+2), 1)


func place_object(room):
	var s = room.get_room_size_in_tiles(tile_size)
	var room_center = room.get_room_pos_in_tiles(tile_size)
	var x_pos = rand_range(room_center.x - s.x+2, room_center.x + s.x-2)
	var y_pos = rand_range(room_center.y - s.y+2, room_center.y + s.y-2)
	
	Map.set_cell(x_pos, y_pos, 2)
	find_tile_locations(2)
	
func apply_autotile():
	Map.update_bitmask_region()
	
func find_tile_locations(id):
	var used_cells = Map.get_used_cells_by_id(id)
	print(used_cells)
				
func carve_path(pos1, pos2):
	# Carve a path between two points
	var x_diff = sign(pos2.x - pos1.x)
	var y_diff = sign(pos2.y - pos1.y)
	if x_diff == 0: x_diff = pow(-1.0, randi() % 2)
	if y_diff == 0: y_diff = pow(-1.0, randi() % 2)
	# choose either x/y or y/x
	var x_y = pos1
	var y_x = pos2
	if (randi() % 2) > 0:
		x_y = pos2
		y_x = pos1
	for x in range(pos1.x, pos2.x, x_diff):
		Map.set_cell(x, x_y.y, 0)
		Map.set_cell(x, x_y.y + y_diff, 0)  # widen the corridor
	for y in range(pos1.y, pos2.y, y_diff):
		Map.set_cell(y_x.x, y, 0)
		Map.set_cell(y_x.x + x_diff, y, 0)
	
func find_start_room():
	var min_x = INF
	for room in $Rooms.get_children():
		if room.position.x < min_x:
			start_room = room
			print(start_room)
			min_x = room.position.x

func find_end_room():
	var max_x = -INF
	for room in $Rooms.get_children():
		if room.position.x > max_x:
			end_room = room
			max_x = room.position.x

extends RigidBody2D

var size
var tile_position
var tile_size

func make_room(_pos, _size):
	position = _pos
	size = _size
	var s = RectangleShape2D.new()
	s.custom_solver_bias = 0.75
	s.extents = size
	$CollisionShape2D.shape = s
	
func get_room_pos_in_tiles(tile_size):
	return (position / tile_size).floor()

func get_room_size_in_tiles(tile_size):
	return (size / tile_size).floor()

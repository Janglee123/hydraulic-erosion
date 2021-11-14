extends Spatial

export(Vector3) var terrain_size := Vector3(256, 256, 256)
export(Curve) var height_distrobution: Curve
export(OpenSimplexNoise) var noise: OpenSimplexNoise

export(int) var water_drops := 50000
export(float) var gravity := 4.0
export(int) var max_iteration := 64
export(float, 0.0, 1.0) var droplet_inertia := 0.3
export(float) var droplet_sendiment_capacity := 2.0
export(float, 0.0, 1.0) var deposition_rate := 0.2
export(float, 0.0, 1.0) var erosion_rate := 0.2
export(float, 0.0, 1.0) var evaporation_rate := 0.01
export(float, 0.0, 1.0) var blur := 0.4

onready var terrain := $Terrain as MeshInstance
onready var width := int(terrain_size.x)
onready var height := int(terrain_size.z)

var _mesh_data: Array
var _height_map: PoolRealArray

func _ready() -> void:
	
	noise.seed = OS.get_system_time_msecs()
	
	_height_map = _create_hight_map()
	var original_height_map = _height_map
	
	var start := OS.get_system_time_msecs()
	_rain()
	var end := OS.get_system_time_msecs()
	print("Erosion time: " + str(end - start) + "ms")
	
	start = OS.get_system_time_msecs()
	for i in width:
		for j in height:
			var index = i + j * width
			_height_map[index] = (1.0 - blur) * _height_map[index] + blur * original_height_map[index]
	end = OS.get_system_time_msecs()
	print("Blur time: " + str(end - start) + "ms")
	
	start = OS.get_system_time_msecs()
	_mesh_data = _create_mesh_data()
	terrain.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _mesh_data)
	end = OS.get_system_time_msecs()
	print("Terrain generation time: " + str(end - start) + "ms")


func _rain() -> void:
	
	var size := Vector2(width - 1, height - 1)
	
	for j in water_drops:
		var sendiment := 0.0
		var dir := Vector2.ZERO
		var speed := 4.0
		var capacity := droplet_sendiment_capacity
		var cell := (Vector2(randf(), randf()) * size).floor()
		
		for i in max_iteration:
			
			var offset := int(cell.x) + int(cell.y) * width
			
			var gradient = Vector2(
					_height_map[offset + 1] + _height_map[offset + 1 + width] - _height_map[offset] - _height_map[offset + width],
					_height_map[offset + width] + _height_map[offset + 1 + width] - _height_map[offset] - _height_map[offset + 1]
				)
			
			dir = dir * droplet_inertia - gradient * (1.0 - droplet_inertia)
			dir = dir.normalized().snapped(Vector2.ONE)
			var new_cell := cell + dir
			var new_offset = int(new_cell.x) + int(new_cell.y) * width
			
			if new_cell.x < 1 or new_cell.x > width - 2 or new_cell.y < 1 or new_cell.y > height - 2:
				break
			
			if dir.x == 0 and dir.y == 0:
				break
			
			var height := 0.25 * (_height_map[offset] + _height_map[offset + 1] + _height_map[offset + width] + _height_map[offset + 1 + width])
			var new_height := 0.25 * (_height_map[new_offset] + _height_map[new_offset + 1] + _height_map[new_offset + width] + _height_map[new_offset + 1 + width])
			var height_diff = new_height - height
			
			var cap = max(- height_diff, 0.01) * capacity * speed
			var deposit := 0.0
			var erode := 0.0
			
			if height_diff > 0.0:
				deposit = min(height_diff, sendiment)
				sendiment -= deposit
			elif sendiment > cap:
				deposit = (sendiment - cap) * deposition_rate
				sendiment -= deposit
			else:
				erode = min(max(cap - sendiment, 0.0) * erosion_rate, - height_diff)
				sendiment += erode
			
			var delta = (deposit - erode) * 0.125
			_height_map[offset] += delta
			_height_map[offset + 1] += delta
			_height_map[offset + width] += delta
			_height_map[offset + 1 + width] += delta
			
			delta = (deposit - erode) * 0.04167
			if cell.y > 1:
				_height_map[offset - width - 1] += delta
				_height_map[offset - width] += delta
				_height_map[offset - width + 1] += delta
				_height_map[offset - width + 2] += delta
			
			if cell.y < height - 2:
				_height_map[offset + 2*width - 1] += delta
				_height_map[offset + 2*width] += delta
				_height_map[offset + 2*width + 1] += delta
				_height_map[offset + 2*width + 2] += delta
			
			if cell.x < width - 2:
				_height_map[offset - 1] += delta
				_height_map[offset + width - 1] += delta
				_height_map[offset + 2] += delta
				_height_map[offset + width + 2] += delta
			
			speed = sqrt(abs(speed * speed - height_diff * gravity))
			cell = new_cell
			capacity *= (1.0 - evaporation_rate)


func _create_hight_map() -> PoolRealArray:
	var height_map := PoolRealArray()
	height_map.resize(height * width)
	
	var center := Vector2(width, height) * 0.5
	var diagonal_lenght := center.length()
	
	for i in height:
		for j in width:
			var h := noise.get_noise_2d(i , j) * 0.5 + 0.5
			var center_multiplyer := 1.0 - Vector2(i, j).distance_to(center) / diagonal_lenght
			var center_height := center_multiplyer * 0.25
			height_map[i + j * width] = height_distrobution.interpolate(h * center_multiplyer + center_height) * terrain_size.y
			
	return height_map


func _create_mesh_data() -> Array:
	var index = 0
	
	var verts := PoolVector3Array()
	var uvs := PoolVector2Array()
	var normals := PoolVector3Array()
	var indices := PoolIntArray()
	
	verts.resize(width * height)
	uvs.resize(width * height)
	normals.resize(width * height)
	indices.resize((width - 1) * (height - 1) * 6)
	
	for y in height:
		for x in width:
			var offset: int = y * width + x
			verts[offset] = Vector3(x, _height_map[x + y * width], y)
			uvs[offset] = Vector2(x * 1.0 / width, y * 1.0 / height )
			normals[offset] = Vector3.UP
			
			if x < width - 1 and y < height - 1:
				indices[index] = offset
				indices[index + 1] = offset + 1
				indices[index + 2] = offset + width
				indices[index + 3] = offset + 1
				indices[index + 4] = offset + width + 1
				indices[index + 5] = offset + width
				index += 6
				
	for i in indices.size() / 3:
		var ai: int = indices[3 * i]
		var bi: int = indices[3 * i + 1]
		var ci: int = indices[3 * i + 2]
		
		var ca: Vector3 = verts[ci] - verts[ai]
		var ba: Vector3 = verts[bi] - verts[ai]
		var normal = ca.cross(ba)
		
		normals[ai] += normal
		normals[bi] += normal
		normals[ci] += normal
	
	for i in normals.size():
		normals[i] = normals[i].normalized()
	
	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = indices
	
	return arr

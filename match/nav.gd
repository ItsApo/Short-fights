class_name Nav
## Runtime navmesh for bots (host only). Baked once from the map's static colliders.


static func bake(map_root: Node3D) -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 35.0
	nm.cell_size = 0.25
	nm.cell_height = 0.2
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, source, map_root)
	NavigationServer3D.bake_from_source_geometry_data(nm, source)
	var region := NavigationRegion3D.new()
	region.name = "NavRegion"
	region.navigation_mesh = nm
	map_root.add_child(region)
	print("[match] navmesh polygons: %d" % nm.get_polygon_count())


static func path(world: World3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	if NavigationServer3D.map_get_iteration_id(world.navigation_map) == 0:
		return PackedVector3Array([from, to])  # map not synchronized yet
	var p := NavigationServer3D.map_get_path(world.navigation_map, from, to, true)
	if p.size() < 2:
		return PackedVector3Array([from, to])
	return p

@tool
extends EditorScenePostImport

# The "Dining Set.glb" ships with no NORMAL data (only POSITION + TEXCOORD_0),
# which makes lighting break up across surfaces (e.g. the tabletop only lit on
# part of its area, regardless of where the light is). This regenerates proper
# normals on every mesh in the imported scene so lighting works correctly.

func _post_import(scene: Node) -> Object:
	_fix_node(scene)
	return scene


func _fix_node(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		node.mesh = _rebuild_with_normals(node.mesh)
	for child in node.get_children():
		_fix_node(child)


func _rebuild_with_normals(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var st := SurfaceTool.new()
		st.create_from(src, s)
		st.deindex()           # split shared vertices -> flat, per-face normals (right for furniture)
		st.generate_normals()  # recompute normals from triangle winding (which is consistent)
		st.generate_tangents() # tangents need valid normals + UVs
		st.commit(out)
		out.surface_set_material(s, src.surface_get_material(s))
	return out

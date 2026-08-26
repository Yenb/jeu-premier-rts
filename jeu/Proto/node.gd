extends Node

func _process(_delta):
	var vp = get_viewport().get_viewport_rid()
	var prims = RenderingServer.viewport_get_render_info(vp,
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
		RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	print(prims)

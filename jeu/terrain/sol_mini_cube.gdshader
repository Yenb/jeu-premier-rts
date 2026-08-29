// Shader mini-cube : sol_minimal + teinte par instance (INSTANCE COLOR).
// La couleur d'instance vient de MultiMesh.set_instance_color() -- utilisee
// pour foncer les sous-cubes selon leurs PV (pv=0 -> COLOR blanc, pv=MAX_PV
// -> COLOR noir). ALBEDO = couleur uniforme du materiau * COLOR d'instance.
shader_type spatial;
render_mode specular_disabled, cull_disabled;

uniform vec4 couleur : source_color = vec4(0.45, 0.36, 0.27, 1.0);

void fragment() {
	ALBEDO = couleur.rgb * COLOR.rgb;
}

void light() {
	DIFFUSE_LIGHT += ALBEDO * ATTENUATION * LIGHT_COLOR * max(dot(LIGHT, NORMAL), 0.0);
}

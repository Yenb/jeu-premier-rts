// Shader MINIMAL pour surfaces mates : diffuse + ombres, zero PBR.
// Un dot product et une multiplication par pixel au lieu du pipeline
// PBR complet. ATTENUATION porte la shadow map : les ombres restent.
shader_type spatial;
render_mode specular_disabled, cull_disabled;

uniform vec4 couleur : source_color = vec4(0.45, 0.36, 0.27, 1.0);

void fragment() {
	ALBEDO = couleur.rgb;
}

void light() {
	DIFFUSE_LIGHT += ALBEDO * ATTENUATION * LIGHT_COLOR * max(dot(LIGHT, NORMAL), 0.0);
}

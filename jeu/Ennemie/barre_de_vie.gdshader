shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

// BANC "test_ennemi" -- LA TECHNIQUE STANDARD d'une barre de vie 3D : un
// SEUL quad, un SEUL parametre (fraction), la couleur du fragment bascule
// selon sa position U -- jamais deux maillages qu'on repositionne a la
// main. Rien ne bouge, rien ne se met a l'echelle : seule la couleur
// affichee change, donc rien ne peut jamais "deriver" a l'ecran.
//
// "billboard" N'EST PAS UN render_mode VALIDE SUR UN SHADER SPATIAL --
// c'est une proprete de StandardMaterial3D, absente ici (verifie contre
// la reference officielle apres coup : la premiere version ne compilait
// nulle part, pas seulement en headless, d'ou la barre invisible). Le
// visage tourne camera se refait a la main dans vertex(), patron standard
// de la communaute Godot (godotshaders.com, "3D Health Bar").

uniform vec4 couleur_vide : source_color = vec4(0.15, 0.15, 0.15, 1.0);
uniform vec4 couleur_pleine : source_color = vec4(0.15, 0.9, 0.2, 1.0);
// PART DE UN : une barre neuve doit se montrer pleine avant le premier
// appel depuis le script.
uniform float fraction : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec4 couleur = UV.x <= fraction ? couleur_pleine : couleur_vide;
	ALBEDO = couleur.rgb;
	ALPHA = couleur.a;
}

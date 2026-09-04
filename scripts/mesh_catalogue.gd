extends RefCounted

# CATALOGUE DE MESHES DECLARES EN DONNEE. Resoud une fiche de data/mesh.json en
# un Mesh Godot pret a etre pose sur un MultiMesh, une fois par forme (jamais
# par individu -- le meme Mesh est partage par toute la population qui pointe
# vers la meme cle).
#
# CE MODULE NE CONNAIT AUCUN NOM DE CONTENU. Il ne parle que de FAMILLES
# GEOMETRIQUES ('boite' aujourd'hui, d'autres a venir). Ajouter une nouvelle
# famille est un chantier framework -- un case de plus dans fabriquer_mesh, une
# entree de plus dans data/mesh.json, zero ligne a toucher dans les mecanismes
# qui consomment le Mesh resolu (peuplement.gd et autres).
#
# PAS DE class_name (doctrine CLAUDE.md) : preload("res://scripts/mesh_catalogue.gd").
#
# ---- CE QU'IL FAIT ----
# static charger() -> Dictionary : lit data/mesh.json, rend le Dictionary
#   { cle_forme -> fiche } ou {} si le fichier est absent/invalide (push_error
#   dans les deux cas, jamais un silence).
# static fabriquer_mesh(fiche) -> Mesh : rend un Mesh Godot depuis la fiche,
#   ou null (push_error) si le champ 'type' de la fiche est absent/inconnu.
#
# ---- CE QU'IL NE FAIT PAS ----
# Aucune allocation de MultiMesh, aucune instance RenderingServer, aucun ajout
# au SceneTree : le Mesh rendu est un pur asset, l'appelant en decide l'usage.
# Aucun cache interne : le catalogue est petit, un charger() coute une lecture
# JSON ; un cache aurait a se justifier par une mesure, pas par un reflexe.
#
# ---- FICHE ATTENDUE ----
# { "type": String, plus champs propres a la famille geometrique }
# - "boite" : { "taille": {x,y,z}, "couleur": {r,g,b,a} (a facultatif, defaut 1.0) }
#   Rend un BoxMesh de la taille demandee, muni d'un StandardMaterial3D dont
#   l'albedo est la couleur donnee. Un champ absent alarme (push_error) sans
#   retomber en silence : le catalogue est le contrat, pas un lieu de defauts
#   secrets.
#
# ECART AVEC LE DEPOT FRAMEWORK : ce fichier et son catalogue data/mesh.json
# sont NEUFS dans cette copie de scripts/ + data/ ; le depot orion ne les porte
# pas encore. Divergence assumee par Yael faute d'un catalogue mesh partage cote
# framework (voir CLAUDE.md § Frontiere pour la raison d'etre de l'ecart et sa
# portee ; meme geste que scripts/monde.gd:retirer, scripts/tick.gd et
# scripts/mouvement_kinematic.gd).

const CHEMIN_CATALOGUE := "res://data/mesh.json"

static func charger() -> Dictionary:
	if not FileAccess.file_exists(CHEMIN_CATALOGUE):
		push_error("mesh_catalogue.gd : catalogue introuvable a '%s'" % CHEMIN_CATALOGUE)
		return {}
	var texte := FileAccess.get_file_as_string(CHEMIN_CATALOGUE)
	if texte.is_empty():
		push_error("mesh_catalogue.gd : catalogue vide ou illisible a '%s'" % CHEMIN_CATALOGUE)
		return {}
	var donnees = JSON.parse_string(texte)
	if not (donnees is Dictionary):
		push_error("mesh_catalogue.gd : JSON invalide (pas un objet) a '%s'" % CHEMIN_CATALOGUE)
		return {}
	return donnees

static func fabriquer_mesh(fiche: Dictionary) -> Mesh:
	if not fiche.has("type"):
		push_error("mesh_catalogue.gd : fiche sans champ 'type' -- inresoluble")
		return null
	var type: String = String(fiche.get("type", ""))
	match type:
		"boite":
			return _fabriquer_boite(fiche)
		_:
			push_error("mesh_catalogue.gd : type de mesh inconnu : '%s'" % type)
			return null

static func _fabriquer_boite(fiche: Dictionary) -> Mesh:
	if not fiche.has("taille"):
		push_error("mesh_catalogue.gd : fiche 'boite' sans champ 'taille'")
		return null
	if not fiche.has("couleur"):
		push_error("mesh_catalogue.gd : fiche 'boite' sans champ 'couleur'")
		return null
	var t: Dictionary = fiche.taille
	var c: Dictionary = fiche.couleur
	var box := BoxMesh.new()
	box.size = Vector3(float(t.get("x", 1.0)), float(t.get("y", 1.0)), float(t.get("z", 1.0)))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(float(c.get("r", 1.0)), float(c.get("g", 1.0)), float(c.get("b", 1.0)), float(c.get("a", 1.0)))
	box.material = mat
	return box

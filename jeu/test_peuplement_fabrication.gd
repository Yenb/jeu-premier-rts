extends SceneTree

# Test headless de la fondation M1a (etape 1) : catalogue mesh + type mobile_test.
#
# Verifie, sans SceneTree ni rendu :
# 1. data/types.json est lisible et porte l'entree 'mobile_test'.
# 2. data/mesh.json est lisible via scripts/mesh_catalogue.gd et porte
#    l'entree 'boite_simple'.
# 3. scripts/objet.gd:fabriquer('mobile_test', ...) rend un objet complet,
#    avec id/position poses tels quels et proprietes fusionnees depuis les
#    paquets herites (objet_physique + dynamique) puis surchargees par la
#    fiche mobile_test.
# 4. Les cles propres a mobile_test survivent (vitesse, mesh_ref).
# 5. Les cles heritees survivent (reserves depuis dynamique, densite/masse/
#    volume depuis objet_physique -- au defaut neutre 1000/1/0.001 puisque
#    mobile_test ne porte PAS composition, chemin mort de _calculer_densite_
#    effective).
# 6. scripts/mesh_catalogue.gd:fabriquer_mesh(fiche_boite_simple) rend un
#    BoxMesh non nul, muni d'un StandardMaterial3D dont l'albedo est la
#    couleur declaree.
#
# Godot 4 headless : godot --headless --script jeu/test_peuplement_fabrication.gd
# (chemin de l'exe godot varie par machine, voir CLAUDE.md).
#
# Sortie : "OK: fondation M1a etape 1" + quit(0), ou "ECHEC: <cause>" +
# quit(1). Aucun retry, aucun defaut silencieux.

const Objet = preload("res://scripts/objet.gd")
const MeshCatalogue = preload("res://scripts/mesh_catalogue.gd")

var _echecs: Array = []

func _init() -> void:
	_lancer.call_deferred()

func _lancer() -> void:
	_verifier()
	if _echecs.is_empty():
		print("OK: fondation M1a etape 1 -- mobile_test fabricable, boite_simple resolue en BoxMesh")
		quit(0)
	else:
		for msg in _echecs:
			printerr("ECHEC: %s" % msg)
		quit(1)

func _verifier() -> void:
	# 1. Lire data/types.json
	if not FileAccess.file_exists("res://data/types.json"):
		_echec("data/types.json introuvable")
		return
	var types_texte := FileAccess.get_file_as_string("res://data/types.json")
	var types = JSON.parse_string(types_texte)
	if not (types is Dictionary):
		_echec("data/types.json : JSON invalide (pas un objet)")
		return
	if not types.has("mobile_test"):
		_echec("data/types.json : entree 'mobile_test' absente")
		return

	# 2. Lire data/mesh.json via le loader
	var catalogue_mesh: Dictionary = MeshCatalogue.charger()
	if catalogue_mesh.is_empty():
		_echec("mesh_catalogue.charger() a rendu {} -- data/mesh.json absent ou invalide")
		return
	if not catalogue_mesh.has("boite_simple"):
		_echec("data/mesh.json : entree 'boite_simple' absente")
		return

	# 3-5. Fabriquer un mobile_test et verifier ses proprietes
	var position_test := Vector3(1.0, 2.0, 3.0)
	var individu: Dictionary = Objet.fabriquer("mobile_test_0", "mobile_test", position_test, types)
	if individu.is_empty():
		_echec("objet.fabriquer a rendu {} -- fabrication refusee (voir push_error)")
		return
	if String(individu.get("id", "")) != "mobile_test_0":
		_echec("id incorrect apres fabrication : '%s'" % String(individu.get("id", "")))
	if (individu.get("position", Vector3.ZERO) as Vector3) != position_test:
		_echec("position incorrecte apres fabrication : %s" % str(individu.get("position", null)))
	var props: Dictionary = individu.get("proprietes", {})
	# Cles propres a mobile_test
	if not props.has("vitesse"):
		_echec("proprietes.vitesse absente -- surcharge du type non appliquee")
	elif float(props.vitesse) != 2.0:
		_echec("proprietes.vitesse = %f, attendu 2.0" % float(props.vitesse))
	if not props.has("mesh_ref"):
		_echec("proprietes.mesh_ref absente -- surcharge du type non appliquee")
	elif String(props.mesh_ref) != "boite_simple":
		_echec("proprietes.mesh_ref = '%s', attendu 'boite_simple'" % String(props.mesh_ref))
	# Cles heritees de dynamique
	if not props.has("reserves"):
		_echec("proprietes.reserves absente -- heritage de 'dynamique' non applique")
	elif not (props.reserves is Dictionary and (props.reserves as Dictionary).has("energie")):
		_echec("proprietes.reserves incomplete -- canal 'energie' de dynamique absent")
	# Cles heritees de objet_physique, defauts neutres (mobile_test sans composition)
	if not props.has("densite"):
		_echec("proprietes.densite absente -- heritage de 'objet_physique' non applique")
	elif float(props.densite) != 1000.0:
		_echec("proprietes.densite = %f, attendu 1000.0 (defaut neutre objet_physique)" % float(props.densite))
	if not props.has("masse"):
		_echec("proprietes.masse absente")
	elif float(props.masse) != 1.0:
		_echec("proprietes.masse = %f, attendu 1.0 (defaut neutre objet_physique)" % float(props.masse))
	# La cle 'herite' (instruction de fabrication) doit avoir ete retiree
	if props.has("herite"):
		_echec("proprietes.herite presente -- devrait etre retiree apres fusion")
	# Aucun _note ne doit trainer sur l'instance
	for cle in props.keys():
		if String(cle).begins_with("_"):
			_echec("proprietes porte '%s' (cle _note non retiree)" % String(cle))
			break

	# 6. Resoudre le mesh via le catalogue
	var fiche: Dictionary = catalogue_mesh.get("boite_simple", {})
	var mesh: Mesh = MeshCatalogue.fabriquer_mesh(fiche)
	if mesh == null:
		_echec("MeshCatalogue.fabriquer_mesh(boite_simple) a rendu null")
		return
	if not (mesh is BoxMesh):
		_echec("mesh resolu n'est pas un BoxMesh (type reel : %s)" % mesh.get_class())
		return
	var box := mesh as BoxMesh
	if box.size != Vector3(0.8, 0.8, 0.8):
		_echec("BoxMesh.size = %s, attendu (0.8,0.8,0.8)" % str(box.size))
	var mat := box.material
	if mat == null or not (mat is StandardMaterial3D):
		_echec("BoxMesh.material absent ou pas un StandardMaterial3D")
	else:
		var albedo: Color = (mat as StandardMaterial3D).albedo_color
		if not (is_equal_approx(albedo.r, 0.15) and is_equal_approx(albedo.g, 0.8) and is_equal_approx(albedo.b, 0.15)):
			_echec("albedo = %s, attendu (0.15,0.8,0.15)" % str(albedo))

func _echec(msg: String) -> void:
	_echecs.append(msg)

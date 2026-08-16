extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_etat_duree.gd
#
# Verrouille scripts/etat_duree.gd -- calcul PUR, aucune donnee sur disque
# necessaire pour la majorite des cas (voir ETATS_FICTIFS, HORS DOMAINE :
# "givre_zorg"/"rouille_zorg" n'apparaissent nulle part ailleurs dans le
# depot). Verrouille aussi etats_ponderes() COMPOSE avec
# EtatEffectif.valeur/resoudre (jamais reimplemente, jamais un calcul
# parallele) -- la preuve que l'intensite se lit sans qu'une seule ligne
# d'etat_effectif.gd n'ait change. Un dernier test charge le VRAI
# data/etats.json pour prouver que l'exemple illustratif (mouille avec
# duree reelle, huile sans) parse et se comporte comme attendu.

const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Verif = preload("res://scripts/verif.gd")

const ETATS_FICTIFS := {
	"givre_zorg": {
		"duree": 4.0,
		"effets": [{"propriete": "conductivite_zorg", "mode": "ecraser", "valeur": 0.0}],
	},
	"vernis_zorg": {
		"duree": 4.0,
		"effets": [{"propriete": "conductivite_zorg", "mode": "moduler", "facteur": 3.0}],
	},
	"rouille_zorg": {
		"effets": [{"propriete": "conductivite_zorg", "mode": "moduler", "facteur": 0.5}],
	},
}

func _chose(id: String, etats_actifs: Variant = null, etats_intensite: Variant = null) -> Dictionary:
	var proprietes: Dictionary = {"conductivite_zorg": 8.0}
	if etats_actifs != null:
		proprietes["etats_actifs"] = etats_actifs
	if etats_intensite != null:
		proprietes["etats_intensite"] = etats_intensite
	return {"id": id, "position": Vector3.ZERO, "proprietes": proprietes}

func _init() -> void:
	var v := Verif.new()
	_poser_ajoute_a_etats_actifs(v)
	_poser_avec_duree_initialise_intensite_a_un(v)
	_poser_sans_duree_ne_touche_pas_etats_intensite(v)
	_poser_etat_absent_du_catalogue_alarme_et_ne_pose_rien(v)
	_poser_deux_fois_remet_a_un_jamais_un_cumul(v)
	_poser_ne_duplique_pas_dans_etats_actifs(v)
	_avancer_decremente_l_intensite_proportionnellement_a_la_duree(v)
	_avancer_retire_l_etat_de_etats_intensite_et_etats_actifs_a_zero(v)
	_avancer_rend_les_expirations_id_et_nom_etat(v)
	_avancer_ignore_silencieusement_un_etat_sans_duree(v)
	_avancer_objet_sans_etats_intensite_est_un_chemin_mort(v)
	_avancer_plusieurs_objets_expirent_independamment(v)
	_avancer_ne_mute_jamais_la_propriete_de_base(v)
	_avancer_alarme_si_duree_disparait_du_catalogue(v)
	_etats_ponderes_etat_sans_intensite_suivie_passe_inchange(v)
	_etats_ponderes_ignore_un_etat_non_actif(v)
	_etats_ponderes_ecraseur_a_intensite_pleine_egale_le_catalogue(v)
	_etats_ponderes_ecraseur_a_intensite_partielle_lerp_vers_la_base(v)
	_etats_ponderes_ecraseur_a_intensite_nulle_rend_exactement_la_base(v)
	_etats_ponderes_modulateur_a_intensite_pleine_egale_le_catalogue(v)
	_etats_ponderes_modulateur_a_intensite_partielle_lerp_vers_un(v)
	_etats_ponderes_modulateur_a_intensite_nulle_rend_facteur_un(v)
	_composition_avec_etat_effectif_sans_reimplementer_sa_loi(v)
	_catalogue_reel_mouille_decroit_puis_expire_huile_jamais(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: etat_duree.gd -- poser() seede etats_intensite a 1.0 depuis 'duree' du catalogue " +
			"(absente = jamais suivie, remise a 1.0 sur repose), avancer() decroit proportionnellement " +
			"a la duree totale et retire l'etat a zero, etats_ponderes() pre-melange ecraseur vers la " +
			"base et modulateur vers 1.0 SANS jamais toucher etat_effectif.gd, qui consomme le resultat tel quel")
		quit(0)

func _poser_ajoute_a_etats_actifs(v) -> void:
	var chose := _chose("z1")
	EtatDuree.poser(chose, "givre_zorg", ETATS_FICTIFS)
	v.v(chose.proprietes.etats_actifs == ["givre_zorg"], "poser() doit ajouter le nom de l'etat a etats_actifs")

func _poser_avec_duree_initialise_intensite_a_un(v) -> void:
	var chose := _chose("z2")
	EtatDuree.poser(chose, "givre_zorg", ETATS_FICTIFS)
	v.v(is_equal_approx(chose.proprietes.etats_intensite.get("givre_zorg", -1.0), 1.0),
		"poser() d'un etat avec 'duree' declaree doit seeder etats_intensite a 1.0 exactement")

func _poser_sans_duree_ne_touche_pas_etats_intensite(v) -> void:
	var chose := _chose("z3")
	EtatDuree.poser(chose, "rouille_zorg", ETATS_FICTIFS)
	v.v(chose.proprietes.etats_actifs == ["rouille_zorg"], "un etat sans 'duree' doit quand meme etre pose (actif)")
	v.v(not chose.proprietes.has("etats_intensite"),
		"un etat sans 'duree' ne doit JAMAIS creer ni toucher etats_intensite -- absence legitime")

func _poser_etat_absent_du_catalogue_alarme_et_ne_pose_rien(v) -> void:
	var chose := _chose("z4")
	EtatDuree.poser(chose, "fantome_zorg", ETATS_FICTIFS)
	v.v(not chose.proprietes.has("etats_actifs"),
		"un etat absent du catalogue (reference cassee) ne doit rien poser du tout")

func _poser_deux_fois_remet_a_un_jamais_un_cumul(v) -> void:
	var chose := _chose("z5")
	EtatDuree.poser(chose, "givre_zorg", ETATS_FICTIFS)
	EtatDuree.avancer([chose], 2.0, ETATS_FICTIFS)
	v.v(is_equal_approx(chose.proprietes.etats_intensite.givre_zorg, 0.5),
		"apres 2.0s sur une duree totale de 4.0s, l'intensite doit valoir 0.5")
	EtatDuree.poser(chose, "givre_zorg", ETATS_FICTIFS)
	v.v(is_equal_approx(chose.proprietes.etats_intensite.givre_zorg, 1.0),
		"reposer le MEME etat doit REMETTRE L'INTENSITE A 1.0, jamais l'additionner ou la plafonner ailleurs")

func _poser_ne_duplique_pas_dans_etats_actifs(v) -> void:
	var chose := _chose("z6")
	EtatDuree.poser(chose, "givre_zorg", ETATS_FICTIFS)
	EtatDuree.poser(chose, "givre_zorg", ETATS_FICTIFS)
	v.v(chose.proprietes.etats_actifs == ["givre_zorg"], "reposer le meme etat ne doit jamais dupliquer son nom dans etats_actifs")

func _avancer_decremente_l_intensite_proportionnellement_a_la_duree(v) -> void:
	var chose := _chose("z7")
	EtatDuree.poser(chose, "givre_zorg", ETATS_FICTIFS)
	EtatDuree.avancer([chose], 1.0, ETATS_FICTIFS)
	v.v(is_equal_approx(chose.proprietes.etats_intensite.givre_zorg, 0.75),
		"avancer() doit soustraire exactement delta/duree_totale (1.0/4.0 = 0.25) de l'intensite")

func _avancer_retire_l_etat_de_etats_intensite_et_etats_actifs_a_zero(v) -> void:
	var chose := _chose("z8")
	EtatDuree.poser(chose, "givre_zorg", ETATS_FICTIFS)
	EtatDuree.avancer([chose], 4.0, ETATS_FICTIFS)
	v.v(not chose.proprietes.etats_intensite.has("givre_zorg"), "a intensite epuisee, l'entree doit disparaitre de etats_intensite")
	v.v(not chose.proprietes.etats_actifs.has("givre_zorg"), "a intensite epuisee, le nom doit AUSSI disparaitre de etats_actifs")

func _avancer_rend_les_expirations_id_et_nom_etat(v) -> void:
	var chose := _chose("z9")
	EtatDuree.poser(chose, "givre_zorg", ETATS_FICTIFS)
	var expirees: Array = EtatDuree.avancer([chose], 10.0, ETATS_FICTIFS)
	v.v(expirees.size() == 1 and expirees[0].id == "z9" and expirees[0].nom_etat == "givre_zorg",
		"avancer() doit rendre {id, nom_etat} pour chaque expiration survenue ce pas")

func _avancer_ignore_silencieusement_un_etat_sans_duree(v) -> void:
	var chose := _chose("z10")
	EtatDuree.poser(chose, "rouille_zorg", ETATS_FICTIFS)
	var expirees: Array = EtatDuree.avancer([chose], 1000.0, ETATS_FICTIFS)
	v.v(expirees.is_empty(), "avancer() ne doit jamais expirer un etat sans duree declaree, quel que soit le delta")
	v.v(chose.proprietes.etats_actifs.has("rouille_zorg"), "un etat sans duree doit rester actif pour toujours")

func _avancer_objet_sans_etats_intensite_est_un_chemin_mort(v) -> void:
	var chose := _chose("z11")
	var avant := JSON.stringify(chose.proprietes)
	var expirees: Array = EtatDuree.avancer([chose], 5.0, ETATS_FICTIFS)
	var apres := JSON.stringify(chose.proprietes)
	v.v(expirees.is_empty(), "un objet sans etats_intensite ne doit jamais produire d'expiration")
	v.v(avant == apres, "un objet sans etats_intensite doit traverser avancer() totalement inchange -- chemin mort")

func _avancer_plusieurs_objets_expirent_independamment(v) -> void:
	var court := _chose("z12")
	var long := _chose("z13")
	EtatDuree.poser(court, "givre_zorg", ETATS_FICTIFS)
	EtatDuree.poser(long, "givre_zorg", ETATS_FICTIFS)
	court.proprietes.etats_intensite.givre_zorg = 0.1
	var monde := [court, long]
	var expirees: Array = EtatDuree.avancer(monde, 0.5, ETATS_FICTIFS)
	v.v(expirees.size() == 1 and expirees[0].id == "z12",
		"seul l'objet dont l'intensite est epuisee ce pas doit expirer, l'autre continue independamment")
	v.v(long.proprietes.etats_intensite.has("givre_zorg"), "l'objet a intensite quasi pleine doit garder son etat actif")

func _avancer_ne_mute_jamais_la_propriete_de_base(v) -> void:
	var chose := _chose("z14")
	EtatDuree.poser(chose, "givre_zorg", ETATS_FICTIFS)
	EtatDuree.avancer([chose], 10.0, ETATS_FICTIFS)
	v.v(is_equal_approx(chose.proprietes.conductivite_zorg, 8.0),
		"etat_duree.gd ne doit jamais toucher la propriete de base elle-meme -- seul etat_effectif.gd la LIT")

func _avancer_alarme_si_duree_disparait_du_catalogue(v) -> void:
	var chose := _chose("z15")
	EtatDuree.poser(chose, "givre_zorg", ETATS_FICTIFS)
	var catalogue_sans_duree := {"givre_zorg": {"effets": []}}
	var avant: float = chose.proprietes.etats_intensite.givre_zorg
	EtatDuree.avancer([chose], 1.0, catalogue_sans_duree)
	v.v(is_equal_approx(chose.proprietes.etats_intensite.givre_zorg, avant),
		"si 'duree' disparait du catalogue entre temps, l'intensite ne doit ni descendre ni planter -- alarme et entree ignoree ce pas")

func _etats_ponderes_etat_sans_intensite_suivie_passe_inchange(v) -> void:
	var chose := _chose("z16", ["rouille_zorg"])
	var pondere := EtatDuree.etats_ponderes(chose, ETATS_FICTIFS)
	v.v(pondere.rouille_zorg.effets[0].facteur == 0.5,
		"un etat actif SANS intensite suivie doit passer par etats_ponderes exactement comme dans le catalogue (facteur 0.5 inchange)")

func _etats_ponderes_ignore_un_etat_non_actif(v) -> void:
	var chose := _chose("z17", [])
	var pondere := EtatDuree.etats_ponderes(chose, ETATS_FICTIFS)
	v.v(pondere.is_empty(), "aucun etat actif -> etats_ponderes doit rendre un Dictionary vide")

func _etats_ponderes_ecraseur_a_intensite_pleine_egale_le_catalogue(v) -> void:
	var chose := _chose("z18", ["givre_zorg"], {"givre_zorg": 1.0})
	var pondere := EtatDuree.etats_ponderes(chose, ETATS_FICTIFS)
	v.v(is_equal_approx(pondere.givre_zorg.effets[0].valeur, 0.0),
		"a intensite 1.0, l'ecraseur pondere doit egaler EXACTEMENT la valeur du catalogue (0.0)")

func _etats_ponderes_ecraseur_a_intensite_partielle_lerp_vers_la_base(v) -> void:
	var chose := _chose("z19", ["givre_zorg"], {"givre_zorg": 0.5})
	var pondere := EtatDuree.etats_ponderes(chose, ETATS_FICTIFS)
	# base=8.0, valeur_catalogue=0.0, i=0.5 -> lerp(8.0, 0.0, 0.5) = 4.0
	v.v(is_equal_approx(pondere.givre_zorg.effets[0].valeur, 4.0),
		"a intensite 0.5, l'ecraseur pondere doit etre EXACTEMENT a mi-chemin entre la base (8.0) et la valeur pleine (0.0)")

func _etats_ponderes_ecraseur_a_intensite_nulle_rend_exactement_la_base(v) -> void:
	var chose := _chose("z20", ["givre_zorg"], {"givre_zorg": 0.0})
	var pondere := EtatDuree.etats_ponderes(chose, ETATS_FICTIFS)
	v.v(is_equal_approx(pondere.givre_zorg.effets[0].valeur, 8.0),
		"a intensite 0.0, l'ecraseur pondere doit rendre EXACTEMENT la base -- l'IDENTITE d'un ecraseur epuise est la base")

func _etats_ponderes_modulateur_a_intensite_pleine_egale_le_catalogue(v) -> void:
	var chose := _chose("z21", ["vernis_zorg"], {"vernis_zorg": 1.0})
	var pondere := EtatDuree.etats_ponderes(chose, ETATS_FICTIFS)
	v.v(is_equal_approx(pondere.vernis_zorg.effets[0].facteur, 3.0),
		"a intensite 1.0, le modulateur pondere doit egaler EXACTEMENT le facteur du catalogue (3.0)")

func _etats_ponderes_modulateur_a_intensite_partielle_lerp_vers_un(v) -> void:
	var chose := _chose("z22", ["vernis_zorg"], {"vernis_zorg": 0.5})
	var pondere := EtatDuree.etats_ponderes(chose, ETATS_FICTIFS)
	# lerp(1.0, 3.0, 0.5) = 2.0
	v.v(is_equal_approx(pondere.vernis_zorg.effets[0].facteur, 2.0),
		"a intensite 0.5, le modulateur pondere doit etre a mi-chemin entre 1.0 (identite) et le facteur plein (3.0)")

func _etats_ponderes_modulateur_a_intensite_nulle_rend_facteur_un(v) -> void:
	var chose := _chose("z23", ["vernis_zorg"], {"vernis_zorg": 0.0})
	var pondere := EtatDuree.etats_ponderes(chose, ETATS_FICTIFS)
	v.v(is_equal_approx(pondere.vernis_zorg.effets[0].facteur, 1.0),
		"a intensite 0.0, le modulateur pondere doit rendre EXACTEMENT 1.0 -- l'IDENTITE d'un modulateur epuise est 1.0, jamais la base")

# COMPOSITION AVEC etat_effectif.gd, JAMAIS UN CALCUL PARALLELE : passe le
# Dictionary rendu par etats_ponderes() a EtatEffectif.valeur EXACTEMENT
# comme un vrai catalogue -- si etat_effectif.gd n'a pas ete modifie, ce
# test doit passer sans qu'aucune ligne de sa loi n'ait ete touchee.
func _composition_avec_etat_effectif_sans_reimplementer_sa_loi(v) -> void:
	var chose := _chose("z24", ["givre_zorg"], {"givre_zorg": 0.25})
	var pondere := EtatDuree.etats_ponderes(chose, ETATS_FICTIFS)
	var effective := EtatEffectif.valeur(chose, "conductivite_zorg", pondere)
	# lerp(8.0, 0.0, 0.25) = 6.0
	v.v(is_equal_approx(effective, 6.0),
		"EtatEffectif.valeur (jamais modifie) doit rendre la valeur ecraseur ponderee EXACTEMENT, composee sans calcul parallele")

func _catalogue_reel_mouille_decroit_puis_expire_huile_jamais(v) -> void:
	var etats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/etats.json"))
	var bois := {"id": "b1", "position": Vector3.ZERO, "proprietes": {"inflammabilite": 0.9}}
	var huile := {"id": "b2", "position": Vector3.ZERO, "proprietes": {"inflammabilite": 0.9}}
	EtatDuree.poser(bois, "mouille", etats)
	EtatDuree.poser(huile, "huile", etats)
	v.v(is_equal_approx(bois.proprietes.etats_intensite.get("mouille", -1.0), 1.0),
		"data/etats.json:mouille doit seeder etats_intensite a 1.0")
	v.v(not huile.proprietes.has("etats_intensite"), "data/etats.json:huile (sans 'duree') ne doit jamais creer etats_intensite")

	# a mi-duree, l'inflammabilite effective doit etre a mi-chemin entre 0.0 (mouille plein) et 0.9 (base)
	EtatDuree.avancer([bois], etats.mouille.duree / 2.0, etats)
	var pondere_mi := EtatDuree.etats_ponderes(bois, etats)
	v.v(is_equal_approx(EtatEffectif.valeur(bois, "inflammabilite", pondere_mi), 0.45),
		"a mi-duree reelle, l'inflammabilite effective de bois mouille doit valoir 0.45 (mi-chemin exact vers 0.9)")

	EtatDuree.avancer([bois], etats.mouille.duree / 2.0, etats)
	v.v(not bois.proprietes.etats_actifs.has("mouille"), "mouille (catalogue reel) doit expirer une fois sa duree totale ecoulee")
	var pondere_apres := EtatDuree.etats_ponderes(bois, etats)
	v.v(is_equal_approx(EtatEffectif.valeur(bois, "inflammabilite", pondere_apres), 0.9),
		"une fois mouille expire, l'inflammabilite effective doit etre revenue exactement a la base (0.9)")
	v.v(huile.proprietes.etats_actifs.has("huile"), "huile (catalogue reel, sans duree) ne doit jamais expirer, meme apres un temps long")

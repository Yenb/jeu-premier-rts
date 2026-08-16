extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_banc_etat_duree.gd
#
# Verrouille les fonctions statiques testables de banc_etat_duree.gd
# (_intensite_texte/_ratio_intensite/_teinte_pour_valeur/_texte_label/
# _ligne_pose/_ligne_rapport/_ligne_retrait) et, CHEMIN REEL (meme regime
# que test_banc_inflammabilite.gd), la fabrication effective des deux
# objets du banc depuis data/banc_etat_duree.json + data/etats.json, lus
# sur disque -- puis UNE BOUCLE REELLE qui avance EtatDuree.avancer()/lit
# EtatEffectif.valeur() via etats_ponderes() tick par tick jusqu'a
# l'expiration reelle de "mouille", en verifiant que la BARRE (ratio
# d'intensite) et la VALEUR EFFECTIVE bougent AU MEME RYTHME, puis relit
# le LABEL apres coup (verifier le seul statut ne suffit pas -- lecon de
# l'audit du chantier "feu -- inflammabilite effective").

const BancEtatDuree = preload("res://scripts/banc_etat_duree.gd")
const EtatDuree = preload("res://scripts/etat_duree.gd")
const EtatEffectif = preload("res://scripts/etat_effectif.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_intensite_texte_actif_avec_intensite(v)
	_intensite_texte_permanent(v)
	_intensite_texte_expire(v)
	_ratio_intensite_actif_avec_intensite_borne(v)
	_ratio_intensite_permanent_toujours_plein(v)
	_ratio_intensite_expire_nul(v)
	_teinte_grise_a_valeur_nulle_orange_croissante(v)
	_texte_label_porte_id_etat_intensite_et_valeur(v)
	_ligne_pose_finie_et_permanente(v)
	_ligne_rapport_porte_intensite_et_valeur(v)
	_ligne_retrait_porte_avant_et_apres(v)
	_donnees_reelles_deux_objets_bon_role(v)
	_chemin_reel_bar_et_valeur_bougent_au_meme_rythme_puis_expirent(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: banc_etat_duree.gd -- intensite/ratio distinguent actif/permanent/expire, la barre et " +
			"la valeur effective suivent EtatDuree.etats_ponderes/EtatEffectif.valeur au meme rythme sans " +
			"jamais reimplementer leur loi, chemin reel verifie jusqu'a une expiration reelle de 'mouille'")
		quit(0)

func _charger_json(chemin: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(chemin))

func _intensite_texte_actif_avec_intensite(v) -> void:
	var proprietes := {"etats_actifs": ["mouille"], "etats_intensite": {"mouille": 0.42}}
	v.v(BancEtatDuree._intensite_texte(proprietes, "mouille") == "0.42",
		"un etat actif avec une intensite suivie doit afficher l'intensite chiffree")

func _intensite_texte_permanent(v) -> void:
	var proprietes := {"etats_actifs": ["huile"]}
	v.v(BancEtatDuree._intensite_texte(proprietes, "huile") == "permanent",
		"un etat actif SANS entree dans etats_intensite doit afficher 'permanent'")

func _intensite_texte_expire(v) -> void:
	var proprietes := {"etats_actifs": []}
	v.v(BancEtatDuree._intensite_texte(proprietes, "mouille") == "expire",
		"un etat absent de etats_actifs doit afficher 'expire'")

func _ratio_intensite_actif_avec_intensite_borne(v) -> void:
	var proprietes := {"etats_actifs": ["mouille"], "etats_intensite": {"mouille": 0.3}}
	v.v(is_equal_approx(BancEtatDuree._ratio_intensite(proprietes, "mouille"), 0.3), "le ratio doit egaler l'intensite suivie")
	var hors_bornes := {"etats_actifs": ["mouille"], "etats_intensite": {"mouille": 1.4}}
	v.v(is_equal_approx(BancEtatDuree._ratio_intensite(hors_bornes, "mouille"), 1.0), "le ratio ne doit jamais depasser 1.0")

func _ratio_intensite_permanent_toujours_plein(v) -> void:
	var proprietes := {"etats_actifs": ["huile"]}
	v.v(is_equal_approx(BancEtatDuree._ratio_intensite(proprietes, "huile"), 1.0),
		"un etat actif sans intensite suivie doit rendre un ratio plein (1.0), barre toujours pleine")

func _ratio_intensite_expire_nul(v) -> void:
	var proprietes := {"etats_actifs": []}
	v.v(is_equal_approx(BancEtatDuree._ratio_intensite(proprietes, "mouille"), 0.0),
		"un etat absent doit rendre un ratio nul")

func _teinte_grise_a_valeur_nulle_orange_croissante(v) -> void:
	v.v(BancEtatDuree._teinte_pour_valeur(0.0) == Color(0.4, 0.4, 0.4), "valeur nulle doit rendre le gris neutre")
	var faible := BancEtatDuree._teinte_pour_valeur(0.3)
	var forte := BancEtatDuree._teinte_pour_valeur(0.9)
	v.v(faible.r > 0.0 and forte.r > faible.r, "la composante rouge doit croitre avec la valeur effective")

func _texte_label_porte_id_etat_intensite_et_valeur(v) -> void:
	var proprietes := {"etats_actifs": ["mouille"], "etats_intensite": {"mouille": 0.6}}
	var texte := BancEtatDuree._texte_label("objet_expire", "mouille", proprietes, 0.36)
	v.v(texte.find("objet_expire") != -1 and texte.find("mouille") != -1 and texte.find("0.60") != -1 and texte.find("0.36") != -1,
		"le label doit porter l'id, le nom de l'etat, l'intensite chiffree et la valeur effective")

func _ligne_pose_finie_et_permanente(v) -> void:
	var ligne_finie := BancEtatDuree._ligne_pose(0.0, "objet_expire", "mouille", 1.0)
	v.v(ligne_finie.find("1.00") != -1, "la ligne de pose d'un etat suivi doit porter l'intensite initiale chiffree (1.00)")
	var ligne_permanente := BancEtatDuree._ligne_pose(0.0, "objet_permanent", "huile", -1.0)
	v.v(ligne_permanente.find("permanent") != -1, "la ligne de pose d'un etat sans decroissance doit dire explicitement 'permanent'")

func _ligne_rapport_porte_intensite_et_valeur(v) -> void:
	var ligne := BancEtatDuree._ligne_rapport(3.0, "objet_expire", "mouille", 0.5, 0.45)
	v.v(ligne.find("objet_expire") != -1 and ligne.find("mouille") != -1 and ligne.find("0.50") != -1 and ligne.find("0.45") != -1,
		"la ligne de rapport doit porter l'objet, l'etat, l'intensite courante et la valeur effective")

func _ligne_retrait_porte_avant_et_apres(v) -> void:
	var ligne := BancEtatDuree._ligne_retrait(6.0, "objet_expire", "mouille", 0.0, 0.9)
	v.v(ligne.find("objet_expire") != -1 and ligne.find("mouille") != -1 and ligne.find("0.00") != -1 and ligne.find("0.90") != -1,
		"la ligne de retrait doit porter l'objet, l'etat, la valeur AVANT et la valeur APRES")

func _donnees_reelles_deux_objets_bon_role(v) -> void:
	var donnees := _charger_json("res://data/banc_etat_duree.json")
	var etats := _charger_json("res://data/etats.json")
	v.v(donnees.objets.size() == 2, "le banc doit declarer exactement deux objets")

	var objet_expire := {"id": "objet_expire", "position": Vector3.ZERO, "proprietes": {"inflammabilite": 0.9, "etats_actifs": []}}
	EtatDuree.poser(objet_expire, "mouille", etats)
	v.v(is_equal_approx(objet_expire.proprietes.etats_intensite.get("mouille", -1.0), 1.0),
		"objet_expire doit demarrer a intensite 1.0 sur l'etat reel 'mouille'")

	var objet_permanent := {"id": "objet_permanent", "position": Vector3.ZERO, "proprietes": {"inflammabilite": 0.9, "etats_actifs": []}}
	EtatDuree.poser(objet_permanent, "huile", etats)
	v.v(not objet_permanent.proprietes.has("etats_intensite"),
		"objet_permanent ('huile', sans duree reelle declaree) ne doit jamais recevoir etats_intensite")

# CHEMIN REEL, BOUCLE REELLE : avance EtatDuree.avancer()/lit
# EtatEffectif.valeur() via etats_ponderes() tick par tick, exactement
# comme banc_etat_duree.gd:_process, jusqu'a l'expiration reelle de
# "mouille" sur objet_expire -- verifie qu'a MI-PARCOURS la barre (ratio)
# et la valeur effective ont bouge AU MEME RYTHME (l'une suit l'autre),
# puis relit _texte_label/_ratio_intensite APRES l'expiration sur les
# deux objets en parallele.
func _chemin_reel_bar_et_valeur_bougent_au_meme_rythme_puis_expirent(v) -> void:
	var donnees := _charger_json("res://data/banc_etat_duree.json")
	var etats := _charger_json("res://data/etats.json")
	var duree_reelle: float = etats.mouille.duree

	var objet_expire := {"id": "objet_expire", "position": Vector3.ZERO, "proprietes": {"inflammabilite": 0.9, "etats_actifs": []}}
	EtatDuree.poser(objet_expire, "mouille", etats)
	var objet_permanent := {"id": "objet_permanent", "position": Vector3.ZERO, "proprietes": {"inflammabilite": 0.9, "etats_actifs": []}}
	EtatDuree.poser(objet_permanent, "huile", etats)
	var monde := [objet_expire, objet_permanent]

	# A MI-PARCOURS : ratio de barre et valeur effective doivent avoir
	# bouge du MEME POURCENTAGE relatif -- preuve que l'une suit l'autre,
	# jamais un decalage entre affichage de la barre et affichage de la
	# valeur.
	EtatDuree.avancer([objet_expire], duree_reelle / 2.0, etats)
	var ratio_mi: float = BancEtatDuree._ratio_intensite(objet_expire.proprietes, "mouille")
	var pondere_mi := EtatDuree.etats_ponderes(objet_expire, etats)
	var effective_mi: float = EtatEffectif.valeur(objet_expire, "inflammabilite", pondere_mi)
	v.v(is_equal_approx(ratio_mi, 0.5), "a mi-duree, le ratio de la barre doit valoir exactement 0.5")
	v.v(is_equal_approx(effective_mi, 0.45),
		"a mi-duree, la valeur effective doit valoir exactement 0.45 -- LE MEME 0.5 de progression que le ratio de la barre (base 0.9 * (1-0.5))")

	# Fin de parcours reel : expiration.
	var pas := 0.2
	var expire_ce_pas: Array = []
	for i in 100:
		expire_ce_pas = EtatDuree.avancer(monde, pas, etats)
		if not expire_ce_pas.is_empty():
			break
	v.v(expire_ce_pas.size() == 1 and expire_ce_pas[0].id == "objet_expire" and expire_ce_pas[0].nom_etat == "mouille",
		"objet_expire doit reellement expirer dans la fenetre du test, objet_permanent jamais")

	var pondere_apres := EtatDuree.etats_ponderes(objet_expire, etats)
	var effective_apres: float = EtatEffectif.valeur(objet_expire, "inflammabilite", pondere_apres)
	v.v(is_equal_approx(effective_apres, 0.9),
		"une fois 'mouille' expire, EtatEffectif.valeur (jamais modifie) doit rendre la base 0.9")
	v.v(is_equal_approx(BancEtatDuree._ratio_intensite(objet_expire.proprietes, "mouille"), 0.0),
		"une fois expire, le ratio de la barre doit tomber a 0.0 -- l'indicateur doit disparaitre de l'ecran")

	var texte_expire := BancEtatDuree._texte_label("objet_expire", "mouille", objet_expire.proprietes, effective_apres)
	v.v(texte_expire.find("expire") != -1, "le label reel d'objet_expire, apres coup, doit afficher intensite='expire'")
	v.v(texte_expire.find("0.90") != -1, "le label reel d'objet_expire, apres coup, doit afficher la valeur effective revenue a la base (0.90)")

	var pondere_permanent := EtatDuree.etats_ponderes(objet_permanent, etats)
	var effective_permanent: float = EtatEffectif.valeur(objet_permanent, "inflammabilite", pondere_permanent)
	v.v(is_equal_approx(effective_permanent, 1.8),
		"objet_permanent doit rester a 1.8 apres la meme duree ecoulee -- jamais retire par le temps")
	v.v(is_equal_approx(BancEtatDuree._ratio_intensite(objet_permanent.proprietes, "huile"), 1.0),
		"la barre d'objet_permanent doit rester pleine tout du long")

extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_bifurcation.gd
#
# Verrouille scripts/bifurcation.gd (chantier « bifurcation ponderee »,
# audit_mecaniques_psycho_sociales_prealable.md §3). ENTIEREMENT HORS
# DOMAINE : aucun catalogue reel n'est lu, aucun nom de ce fichier n'existe
# ailleurs dans le depot (suffixe "_qwil"), ni « grief », ni « soumission »,
# ni « peur » n'y apparaissent -- si le mecanisme marche ici, il marche sur
# n'importe quel domaine. Meme discipline que test_conditions.gd (suffixe
# "_vlok") et test_emergences.gd ("_zorg").
#
# Couvre : le produit poids x grandeur decide ; le poids absent compte 0 ;
# grandeur nulle/negative et biais nul ne font bifurquer personne (gate par
# la seule arithmetique) ; un poids negatif ne gagne jamais ; egalite
# stricte -> premiere DECLAREE dans l'Array, dans les DEUX ordres, et
# a_egalite la nomme ; sorties vide / biais vide -> chemin mort ; un doublon
# dans `sorties` ne fabrique jamais de fausse egalite ; la loi ne compte pas
# ses sorties (1, 2 et 5 sorties, meme loi) ; l'ordre du Dictionary `biais` ne
# decide jamais ; LA GRANDEUR NE CHANGE JAMAIS LE GAGNANT (limite reelle
# documentee en tete du mecanisme, verrouillee positivement) ; selectionner
# est un raccourci STRICT de resoudre ; aucune mutation des entrees.

const Bifurcation = preload("res://scripts/bifurcation.gd")
const Verif = preload("res://scripts/verif.gd")

const SORTIES_QWIL := ["prax_qwil", "velm_qwil", "tuor_qwil"]

func _init() -> void:
	var v := Verif.new()
	_le_produit_le_plus_haut_gagne(v)
	_poids_absent_compte_zero(v)
	_grandeur_nulle_ou_negative_ne_fait_bifurquer_personne(v)
	_biais_entierement_nul_ne_fait_bifurquer_personne(v)
	_un_poids_negatif_ne_gagne_jamais(v)
	_egalite_stricte_garde_la_premiere_declaree(v)
	_sorties_vide_et_biais_vide_sont_des_chemins_morts(v)
	_un_doublon_ne_fabrique_pas_de_fausse_egalite(v)
	_une_seule_sortie_declaree_gagne_toujours(v)
	_la_loi_ne_compte_pas_ses_sorties(v)
	_l_ordre_du_dictionnaire_biais_ne_decide_jamais(v)
	_la_grandeur_ne_change_jamais_le_gagnant(v)
	_selectionner_est_un_raccourci_strict_de_resoudre(v)
	_rien_n_est_jamais_mute(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: bifurcation -- selection d'une sortie parmi N par produit poids x grandeur, " +
			"argmax a score strictement positif, gate par la seule arithmetique (grandeur nulle/negative, " +
			"biais nul, poids negatif), egalite stricte alarmee et premiere DECLAREE conservee, " +
			"doublon sans fausse egalite, loi independante du nombre de sorties (1, 2, 5), " +
			"grandeur qui ne change jamais le gagnant, aucune mutation")
		quit(0)

func _le_produit_le_plus_haut_gagne(v) -> void:
	var biais := {"prax_qwil": 0.1, "velm_qwil": 0.7, "tuor_qwil": 0.2}
	var r := Bifurcation.resoudre(10.0, biais, SORTIES_QWIL)
	v.v(r.sortie == "velm_qwil",
		"la sortie au produit poids x grandeur le plus haut doit gagner")
	v.v(is_equal_approx(r.score, 7.0),
		"le score rendu doit etre le produit poids x grandeur du gagnant (0.7 x 10 = 7.0)")
	v.v(is_equal_approx(r.scores["prax_qwil"], 1.0) and is_equal_approx(r.scores["tuor_qwil"], 2.0),
		"resoudre doit rendre le score de TOUTES les sorties, gagnantes ou non")
	v.v(r.a_egalite.is_empty(),
		"sans egalite au sommet, a_egalite doit rester vide (jamais de taille 1)")

func _poids_absent_compte_zero(v) -> void:
	# "tuor_qwil" n'est pas dans le biais : repli 0.0, jamais une alarme --
	# un individu qui ne penche pour rien est legitime.
	var biais := {"prax_qwil": 0.3, "velm_qwil": 0.1}
	var r := Bifurcation.resoudre(10.0, biais, SORTIES_QWIL)
	v.v(is_equal_approx(r.scores["tuor_qwil"], 0.0),
		"une sortie absente du biais doit valoir 0.0, jamais un defaut invente")
	v.v(r.sortie == "prax_qwil",
		"une sortie absente du biais ne doit jamais empecher les autres de gagner")

func _grandeur_nulle_ou_negative_ne_fait_bifurquer_personne(v) -> void:
	var biais := {"prax_qwil": 0.1, "velm_qwil": 0.7, "tuor_qwil": 0.2}
	v.v(Bifurcation.selectionner(0.0, biais, SORTIES_QWIL) == "",
		"grandeur 0.0 : aucun score n'est strictement positif, aucune sortie ne doit etre rendue")
	v.v(Bifurcation.selectionner(-5.0, biais, SORTIES_QWIL) == "",
		"grandeur negative : aucune sortie ne doit etre rendue (gate par la seule arithmetique)")
	var r := Bifurcation.resoudre(0.0, biais, SORTIES_QWIL)
	v.v(is_equal_approx(r.score, 0.0) and r.a_egalite.is_empty(),
		"sans gagnant, le score doit etre 0.0 et a_egalite vide")
	v.v(r.scores.size() == 3,
		"sans gagnant, les scores de toutes les sorties doivent quand meme etre rendus (lisibilite)")

func _biais_entierement_nul_ne_fait_bifurquer_personne(v) -> void:
	var biais := {"prax_qwil": 0.0, "velm_qwil": 0.0, "tuor_qwil": 0.0}
	v.v(Bifurcation.selectionner(1000.0, biais, SORTIES_QWIL) == "",
		"un biais entierement nul ne doit faire bifurquer personne, si haute que soit la grandeur")

func _un_poids_negatif_ne_gagne_jamais(v) -> void:
	# Un seul poids, negatif : son produit est negatif, donc jamais > 0.0.
	var biais := {"prax_qwil": -0.9}
	v.v(Bifurcation.selectionner(10.0, biais, SORTIES_QWIL) == "",
		"un poids negatif ne doit jamais gagner, meme seul en lice")
	# Un negatif face a un positif plus faible : le positif gagne.
	var mixte := {"prax_qwil": -5.0, "velm_qwil": 0.01}
	v.v(Bifurcation.selectionner(10.0, mixte, SORTIES_QWIL) == "velm_qwil",
		"un poids positif meme faible doit toujours battre un poids negatif meme fort")

func _egalite_stricte_garde_la_premiere_declaree(v) -> void:
	# push_error attendu ici : l'egalite est ALARMEE, jamais tranchee en
	# silence. Le test verifie le comportement, pas l'absence d'alarme.
	var biais := {"prax_qwil": 0.5, "velm_qwil": 0.5, "tuor_qwil": 0.1}
	var r := Bifurcation.resoudre(10.0, biais, SORTIES_QWIL)
	v.v(r.sortie == "prax_qwil",
		"a egalite stricte, la PREMIERE sortie de l'Array declare doit etre conservee")
	v.v(r.a_egalite.size() == 2 and r.a_egalite.has("prax_qwil") and r.a_egalite.has("velm_qwil"),
		"a_egalite doit nommer exactement les sorties a egalite au sommet")
	# MEME biais, ordre de declaration INVERSE : c'est l'Array qui decide,
	# jamais l'ordre des cles du Dictionary.
	var inverse := ["velm_qwil", "prax_qwil", "tuor_qwil"]
	v.v(Bifurcation.selectionner(10.0, biais, inverse) == "velm_qwil",
		"inverser l'ordre DECLARE doit inverser le gagnant d'une egalite -- c'est l'Array qui tranche")

func _sorties_vide_et_biais_vide_sont_des_chemins_morts(v) -> void:
	var r := Bifurcation.resoudre(10.0, {"prax_qwil": 1.0}, [])
	v.v(r.sortie == "" and r.scores.is_empty(),
		"aucune sortie declaree : chemin mort silencieux, jamais une alarme")
	var r2 := Bifurcation.resoudre(10.0, {}, SORTIES_QWIL)
	v.v(r2.sortie == "",
		"un biais vide ne doit faire bifurquer personne")
	v.v(r2.scores.size() == 3,
		"un biais vide doit quand meme rendre les trois sorties a 0.0 (lisibilite)")

func _un_doublon_ne_fabrique_pas_de_fausse_egalite(v) -> void:
	# "prax_qwil" declare deux fois : les scores vivant dans un Dictionary,
	# le doublon fusionne -- il ne doit JAMAIS s'egaler lui-meme.
	var biais := {"prax_qwil": 0.5, "velm_qwil": 0.1}
	var r := Bifurcation.resoudre(10.0, biais, ["prax_qwil", "velm_qwil", "prax_qwil"])
	v.v(r.sortie == "prax_qwil",
		"un doublon dans les sorties ne doit pas changer le gagnant")
	v.v(r.a_egalite.is_empty(),
		"un nom declare deux fois ne doit JAMAIS produire une egalite avec lui-meme")
	v.v(r.scores.size() == 2,
		"un nom declare deux fois ne doit compter qu'une fois dans les scores")

func _une_seule_sortie_declaree_gagne_toujours(v) -> void:
	# Cas degenere : rien a departager. Elle gagne des que son score est
	# strictement positif, et jamais autrement -- aucune egalite possible
	# avec elle-meme (a_egalite ne vaut jamais 1).
	var seule := ["prax_qwil"]
	var r := Bifurcation.resoudre(2.0, {"prax_qwil": 0.05, "velm_qwil": 9.0}, seule)
	v.v(r.sortie == "prax_qwil",
		"une seule sortie declaree doit gagner des que son score est positif, si faible soit-il")
	v.v(r.a_egalite.is_empty() and r.scores.size() == 1,
		"une seule sortie declaree ne peut jamais etre a egalite, et un poids hors des sorties declarees ne compte pas")
	v.v(Bifurcation.selectionner(2.0, {"prax_qwil": 0.0}, seule) == "",
		"une seule sortie a poids nul ne doit pas gagner par defaut -- rien ne bifurque sans score positif")

func _la_loi_ne_compte_pas_ses_sorties(v) -> void:
	# DEUX sorties (le cas de l'audit ligne 2) et CINQ sorties : meme loi,
	# aucun nombre n'est cable nulle part.
	var deux := ["prax_qwil", "velm_qwil"]
	v.v(Bifurcation.selectionner(3.0, {"prax_qwil": 0.2, "velm_qwil": 0.8}, deux) == "velm_qwil",
		"la loi doit marcher a deux sorties sans une ligne de plus")
	var cinq := ["prax_qwil", "velm_qwil", "tuor_qwil", "mibb_qwil", "zell_qwil"]
	var biais5 := {"prax_qwil": 0.1, "velm_qwil": 0.2, "tuor_qwil": 0.15, "mibb_qwil": 0.9, "zell_qwil": 0.3}
	v.v(Bifurcation.selectionner(3.0, biais5, cinq) == "mibb_qwil",
		"la loi doit marcher a cinq sorties sans une ligne de plus")

func _l_ordre_du_dictionnaire_biais_ne_decide_jamais(v) -> void:
	# Memes poids, deux ordres d'insertion opposes dans le Dictionary.
	var a := {"prax_qwil": 0.2, "velm_qwil": 0.6, "tuor_qwil": 0.1}
	var b := {"tuor_qwil": 0.1, "velm_qwil": 0.6, "prax_qwil": 0.2}
	v.v(Bifurcation.selectionner(10.0, a, SORTIES_QWIL) == Bifurcation.selectionner(10.0, b, SORTIES_QWIL),
		"l'ordre d'insertion des cles du biais ne doit jamais changer le resultat")

func _la_grandeur_ne_change_jamais_le_gagnant(v) -> void:
	# LIMITE REELLE, verrouillee POSITIVEMENT (voir en-tete du mecanisme) :
	# un scalaire commun a toutes les sorties met a l'echelle sans arbitrer.
	# Si un chantier futur veut que la situation arbitre vraiment, il lui
	# faudra une grandeur PAR SORTIE -- et ce test rougira, ce qui est
	# exactement ce qu'on veut.
	var biais := {"prax_qwil": 0.1, "velm_qwil": 0.7, "tuor_qwil": 0.2}
	var faible := Bifurcation.selectionner(1.0, biais, SORTIES_QWIL)
	var fort := Bifurcation.selectionner(1000.0, biais, SORTIES_QWIL)
	v.v(faible == fort and faible == "velm_qwil",
		"a biais egal, la grandeur ne doit JAMAIS changer qui gagne -- elle ne fait que mettre a l'echelle")
	var r1 := Bifurcation.resoudre(1.0, biais, SORTIES_QWIL)
	var r2 := Bifurcation.resoudre(1000.0, biais, SORTIES_QWIL)
	v.v(is_equal_approx(r2.score, r1.score * 1000.0),
		"les scores doivent bien suivre la grandeur proportionnellement (elle est une echelle reelle)")

func _selectionner_est_un_raccourci_strict_de_resoudre(v) -> void:
	var biais := {"prax_qwil": 0.4, "velm_qwil": 0.9, "tuor_qwil": 0.2}
	for grandeur in [0.0, -3.0, 0.5, 42.0]:
		v.v(Bifurcation.selectionner(grandeur, biais, SORTIES_QWIL) == Bifurcation.resoudre(grandeur, biais, SORTIES_QWIL).sortie,
			"selectionner doit rester un raccourci STRICT de resoudre().sortie, jamais un second calcul")

func _rien_n_est_jamais_mute(v) -> void:
	var biais := {"prax_qwil": 0.4, "velm_qwil": 0.9, "tuor_qwil": 0.2}
	var sorties := SORTIES_QWIL.duplicate()
	var biais_avant := biais.duplicate(true)
	var sorties_avant := sorties.duplicate()
	Bifurcation.resoudre(10.0, biais, sorties)
	v.v(biais == biais_avant, "resoudre ne doit JAMAIS muter le biais recu")
	v.v(sorties == sorties_avant, "resoudre ne doit JAMAIS muter l'Array de sorties recu")

extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_repetitions.gd
#
# Verrouille scripts/repetitions.gd comme sonde GENERIQUE de repetition.
# Domaine hors colon/faction/monde : un atelier d'horlogerie invente, jamais vu
# ailleurs dans le depot, prouve que la sonde ne lit aucun mot du monde -- elle
# ne voit que des String et des empreintes opaques.
#
# Fonction pure : aucune couche, aucun noeud, aucun rendu, aucun disque.

const Repetitions = preload("res://scripts/repetitions.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_sans_note_aucun_defaut(v)
	_une_note_par_tour_aucun_defaut(v)
	_meme_cle_meme_empreinte_est_un_refait(v)
	_meme_cle_empreintes_differentes_est_un_instable(v)
	_deux_tours_differents_restent_legitimes(v)
	_sans_appel_a_tour_tout_tombe_dans_le_tour_zero(v)
	_empreinte_non_json_est_normalisee(v)
	_le_compte_de_notes_est_exact(v)
	_le_rapport_est_resumable_en_json(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: repetitions.gd separe le travail refait de la valeur instable, " +
			"generique a tout domaine invente")
		quit(0)

func _sans_note_aucun_defaut(v) -> void:
	var s = Repetitions.new()
	var r := s.rapport()
	v.v(r["refaits"].is_empty() and r["instables"].is_empty(),
		"une sonde jamais notee ne doit signaler aucun defaut")
	v.v(r["notes"] == 0 and r["cles_distinctes"] == 0,
		"une sonde jamais notee doit compter zero note et zero cle")
	v.v(s.resume().contains("aucune repetition"),
		"le resume d'une sonde vierge doit dire qu'il n'y a aucune repetition")

func _une_note_par_tour_aucun_defaut(v) -> void:
	var s = Repetitions.new()
	s.tour(1)
	s.noter("tension_ressort", 4.0)
	s.noter("jeu_pignon", 0.2)
	s.tour(2)
	s.noter("tension_ressort", 3.5)
	var r := s.rapport()
	v.v(r["refaits"].is_empty() and r["instables"].is_empty(),
		"une cle notee une seule fois par tour ne doit jamais etre un defaut")
	v.v(r["cles_distinctes"] == 2,
		"deux cles differentes doivent compter pour deux, meme reparties sur deux tours")

func _meme_cle_meme_empreinte_est_un_refait(v) -> void:
	var s = Repetitions.new()
	s.tour(7)
	s.noter("course_echappement", 12.5)
	s.noter("course_echappement", 12.5)
	s.noter("course_echappement", 12.5)
	var r := s.rapport()
	v.v(r["instables"].is_empty(),
		"un resultat identique redemande ne doit jamais etre classe instable")
	v.v(r["refaits"].size() == 1,
		"une cle recalculee pour le meme resultat dans le meme tour doit donner un seul refait")
	if r["refaits"].size() == 1:
		var d: Dictionary = r["refaits"][0]
		v.v(d["cle"] == "course_echappement" and d["tour"] == 7 and d["fois"] == 3,
			"un refait doit nommer la cle, le tour, et le nombre exact de calculs")

func _meme_cle_empreintes_differentes_est_un_instable(v) -> void:
	var s = Repetitions.new()
	s.tour(7)
	s.noter("course_echappement", 12.5)
	s.noter("course_echappement", 13.0)
	var r := s.rapport()
	v.v(r["refaits"].is_empty(),
		"une valeur qui bouge dans le tour ne doit jamais etre classee travail refait")
	v.v(r["instables"].size() == 1,
		"une cle qui rend deux resultats differents dans le meme tour doit donner un instable")
	if r["instables"].size() == 1:
		var d: Dictionary = r["instables"][0]
		v.v(d["cle"] == "course_echappement" and d["tour"] == 7 and d["empreintes"].size() == 2,
			"un instable doit nommer la cle, le tour, et les empreintes distinctes vues")

func _deux_tours_differents_restent_legitimes(v) -> void:
	var s = Repetitions.new()
	s.tour(1)
	s.noter("balancier", 1.0)
	s.tour(2)
	s.noter("balancier", 1.0)
	s.tour(3)
	s.noter("balancier", 9.0)
	var r := s.rapport()
	v.v(r["refaits"].is_empty() and r["instables"].is_empty(),
		"la meme cle notee une fois dans chacun de trois tours ne doit jamais etre un defaut, " +
		"que la valeur bouge ou non d'un tour a l'autre")

func _sans_appel_a_tour_tout_tombe_dans_le_tour_zero(v) -> void:
	var s = Repetitions.new()
	s.noter("remontoir", true)
	s.noter("remontoir", true)
	var r := s.rapport()
	v.v(r["refaits"].size() == 1 and r["refaits"][0]["tour"] == 0,
		"sans aucun appel a tour(), la detection doit marcher dans un tour 0 implicite")

func _empreinte_non_json_est_normalisee(v) -> void:
	var s = Repetitions.new()
	s.tour(4)
	s.noter("axe_pivot", Vector3(1.0, 2.0, 3.0))
	s.noter("axe_pivot", Vector3(1.0, 2.0, 3.0))
	s.noter("cadran", {"heures": [1, 2], "trotteuse": false})
	s.noter("cadran", {"heures": [1, 2], "trotteuse": true})
	var r := s.rapport()
	v.v(r["refaits"].size() == 1 and r["refaits"][0]["cle"] == "axe_pivot",
		"deux Vector3 egaux doivent compter comme un meme resultat, jamais comme deux")
	v.v(r["instables"].size() == 1 and r["instables"][0]["cle"] == "cadran",
		"deux Dictionary differents doivent compter comme deux resultats distincts")

func _le_compte_de_notes_est_exact(v) -> void:
	var s = Repetitions.new()
	s.tour(1)
	s.noter("a", 1)
	s.noter("a", 1)
	s.tour(2)
	s.noter("b", 2)
	var r := s.rapport()
	v.v(r["notes"] == 3, "le compte de notes doit valoir le nombre exact d'appels a noter()")
	v.v(r["cles_distinctes"] == 2, "le compte de cles doit dedoublonner d'un tour a l'autre")

# Resumabilite JSON stricte (voir docs/cadrage_corps_interne_colon.md) : le
# rapport doit traverser un aller-retour JSON sans rien perdre, sinon il ne
# peut ni etre ecrit sur disque ni etre lu par un resumeur.
func _le_rapport_est_resumable_en_json(v) -> void:
	var s = Repetitions.new()
	s.tour(5)
	s.noter("spiral", Vector3(0.0, 1.0, 0.0))
	s.noter("spiral", Vector3(0.0, 1.0, 0.0))
	s.noter("ancre", 1)
	s.noter("ancre", 2)
	var texte := JSON.stringify(s.rapport())
	var relu: Variant = JSON.parse_string(texte)
	v.v(relu != null, "le rapport doit passer JSON.stringify puis parse_string sans erreur")
	if relu != null:
		v.v(relu["refaits"].size() == 1 and relu["instables"].size() == 1,
			"le rapport relu depuis JSON doit porter les memes defauts que le rapport direct")
		v.v(relu["refaits"][0]["cle"] == "spiral" and relu["instables"][0]["cle"] == "ancre",
			"le rapport relu depuis JSON doit nommer les memes cles")

extends SceneTree

# Test manuel :
# godot --headless --script scripts/test_consommer.gd
#
# Verrouille scripts/consommer.gd comme MODELE GENERIQUE DE TRANSFERT
# DESTRUCTIF, pas comme un code de "manger". Objets et noms de reserve
# fictifs (sans aucun rapport avec nourriture/energie) prouvent que
# consommer.gd ignore le domaine -- meme discipline que test_champ.gd/
# test_flux (fonctions pures, aucune couche, aucun noeud, aucun rendu).

const Consommer = preload("res://scripts/consommer.gd")
const Verif = preload("res://scripts/verif.gd")

func _init() -> void:
	var v := Verif.new()
	_la_source_perd_et_le_receveur_gagne_la_meme_quantite(v)
	_la_reserve_source_est_bornee_a_zero(v)
	_quand_la_source_est_a_zero_source_epuisee_est_vrai(v)
	_quand_la_source_est_a_zero_aucun_transfert_ne_se_fait(v)
	_un_taux_de_zero_ne_transfere_rien(v)
	_un_delta_tres_petit_transfere_peu(v)
	_la_reserve_receveur_monte_correctement(v)
	_reserve_source_absente_aucun_transfert(v)
	_canal_receveur_absent_est_cree(v)
	_source_epuisee_faux_tant_que_non_nulle(v)
	_une_demande_superieure_au_restant_ne_credite_que_le_restant(v)
	_une_source_a_zero_ne_credite_rien(v)
	_le_modele_ignore_le_domaine(v)
	if v.echecs() > 0:
		quit(1)
	else:
		print("OK: consommer.gd transfere destructivement d'une reserve source vers une reserve " +
			"receptrice, source bornee a zero, source_epuisee correct, aucun nom de propriete en dur")
		quit(0)

func _chose(id: String, reserve_nom: String, reserve_valeur: float) -> Dictionary:
	return {
		"id": id,
		"position": Vector3.ZERO,
		"proprietes": {"reserves": {reserve_nom: {"reserve": reserve_valeur}}},
	}

func _la_source_perd_et_le_receveur_gagne_la_meme_quantite(v) -> void:
	var source := _chose("cristal_zorg", "eclat", 10.0)
	var receveur := _chose("golem_glurp", "charge", 0.0)
	var resultat := Consommer.transferer(source, receveur, "eclat", "charge", 2.0, 1.0)
	v.v(is_equal_approx(source.proprietes.reserves.eclat.reserve, 8.0),
		"la source doit perdre exactement taux*delta")
	v.v(is_equal_approx(receveur.proprietes.reserves.charge.reserve, 2.0),
		"le receveur doit gagner exactement la meme quantite que la source a perdue")
	v.v(not resultat.source_epuisee, "source non epuisee (8.0 restant) : source_epuisee doit rester faux")

func _la_reserve_source_est_bornee_a_zero(v) -> void:
	var source := _chose("cristal_zorg", "eclat", 3.0)
	var receveur := _chose("golem_glurp", "charge", 0.0)
	Consommer.transferer(source, receveur, "eclat", "charge", 10.0, 1.0)
	v.v(source.proprietes.reserves.eclat.reserve >= 0.0,
		"la reserve source ne doit jamais descendre sous zero, meme si taux*delta depasse ce qui reste")
	v.v(is_equal_approx(source.proprietes.reserves.eclat.reserve, 0.0),
		"une demande superieure au restant doit borner exactement a zero")

func _quand_la_source_est_a_zero_source_epuisee_est_vrai(v) -> void:
	var source := _chose("cristal_zorg", "eclat", 1.0)
	var receveur := _chose("golem_glurp", "charge", 0.0)
	var resultat := Consommer.transferer(source, receveur, "eclat", "charge", 1.0, 1.0)
	v.v(is_equal_approx(source.proprietes.reserves.eclat.reserve, 0.0),
		"la reserve source doit atteindre exactement zero sur ce pas")
	v.v(resultat.source_epuisee, "source_epuisee doit etre vrai des que la reserve atteint zero ce pas")

func _quand_la_source_est_a_zero_aucun_transfert_ne_se_fait(v) -> void:
	var source := _chose("cristal_zorg", "eclat", 0.0)
	var receveur := _chose("golem_glurp", "charge", 0.0)
	var resultat := Consommer.transferer(source, receveur, "eclat", "charge", 5.0, 1.0)
	v.v(is_equal_approx(receveur.proprietes.reserves.charge.reserve, 0.0),
		"une source deja a zero ne doit jamais transferer quoi que ce soit")
	v.v(resultat.source_epuisee, "une source deja a zero au depart reste marquee epuisee")

func _un_taux_de_zero_ne_transfere_rien(v) -> void:
	var source := _chose("cristal_zorg", "eclat", 10.0)
	var receveur := _chose("golem_glurp", "charge", 0.0)
	Consommer.transferer(source, receveur, "eclat", "charge", 0.0, 1.0)
	v.v(is_equal_approx(source.proprietes.reserves.eclat.reserve, 10.0),
		"un taux nul ne doit jamais faire baisser la source")
	v.v(is_equal_approx(receveur.proprietes.reserves.charge.reserve, 0.0),
		"un taux nul ne doit jamais faire monter le receveur")

func _un_delta_tres_petit_transfere_peu(v) -> void:
	var source := _chose("cristal_zorg", "eclat", 10.0)
	var receveur := _chose("golem_glurp", "charge", 0.0)
	Consommer.transferer(source, receveur, "eclat", "charge", 2.0, 0.001)
	v.v(receveur.proprietes.reserves.charge.reserve > 0.0,
		"un delta tres petit doit quand meme transferer une quantite strictement positive"
	)
	v.v(receveur.proprietes.reserves.charge.reserve < 0.1,
		"un delta tres petit doit transferer une quantite tres petite, jamais un pas entier")

func _la_reserve_receveur_monte_correctement(v) -> void:
	var source := _chose("cristal_zorg", "eclat", 20.0)
	var receveur := _chose("golem_glurp", "charge", 5.0)
	Consommer.transferer(source, receveur, "eclat", "charge", 3.0, 2.0)
	v.v(is_equal_approx(receveur.proprietes.reserves.charge.reserve, 11.0),
		"le receveur doit partir de sa reserve existante et monter de taux*delta, jamais repartir de zero")

func _reserve_source_absente_aucun_transfert(v) -> void:
	var source := {"id": "cristal_zorg", "position": Vector3.ZERO, "proprietes": {"reserves": {}}}
	var receveur := _chose("golem_glurp", "charge", 0.0)
	var resultat := Consommer.transferer(source, receveur, "eclat", "charge", 5.0, 1.0)
	v.v(is_equal_approx(receveur.proprietes.reserves.charge.reserve, 0.0),
		"une reserve source absente ne doit jamais transferer quoi que ce soit")
	v.v(not resultat.source_epuisee,
		"une reserve source absente n'est pas 'epuisee' -- elle n'a jamais existe, cas neutre")

func _canal_receveur_absent_est_cree(v) -> void:
	var source := _chose("cristal_zorg", "eclat", 10.0)
	var receveur := {"id": "golem_glurp", "position": Vector3.ZERO, "proprietes": {}}
	Consommer.transferer(source, receveur, "eclat", "charge", 2.0, 1.0)
	v.v(receveur.proprietes.has("reserves") and receveur.proprietes.reserves.has("charge"),
		"le canal receveur doit etre cree automatiquement s'il n'existe pas encore")
	v.v(is_equal_approx(receveur.proprietes.reserves.charge.reserve, 2.0),
		"le canal cree doit porter exactement la quantite transferee")

func _source_epuisee_faux_tant_que_non_nulle(v) -> void:
	var source := _chose("cristal_zorg", "eclat", 100.0)
	var receveur := _chose("golem_glurp", "charge", 0.0)
	var resultat := Consommer.transferer(source, receveur, "eclat", "charge", 1.0, 1.0)
	v.v(not resultat.source_epuisee, "une source encore loin de zero ne doit jamais etre marquee epuisee")

# LA SERRURE DE CONSERVATION (chantier « correction consommer.gd -- borner
# le credit a la quantite reellement retiree ») : demander plus que la
# source ne possede ne doit JAMAIS creer de matiere. Avant la correction,
# le receveur gagnait 5.0 pour une source de 2.0 -- c'est ce trou qui
# obligeait ecoulement.gd/banc_fertilite.gd/banc_erosion.gd a pre-borner.
func _une_demande_superieure_au_restant_ne_credite_que_le_restant(v) -> void:
	var source := _chose("cristal_zorg", "eclat", 2.0)
	var receveur := _chose("golem_glurp", "charge", 0.0)
	var total_avant: float = 2.0 + 0.0
	var resultat := Consommer.transferer(source, receveur, "eclat", "charge", 5.0, 1.0)
	v.v(is_equal_approx(source.proprietes.reserves.eclat.reserve, 0.0),
		"une demande de 5.0 sur une source de 2.0 doit vider la source exactement a zero")
	v.v(is_equal_approx(receveur.proprietes.reserves.charge.reserve, 2.0),
		"le receveur ne doit gagner que les 2.0 reellement retires, jamais les 5.0 demandes")
	var total_apres: float = source.proprietes.reserves.eclat.reserve + receveur.proprietes.reserves.charge.reserve
	v.v(is_equal_approx(total_avant, total_apres),
		"la somme source + receveur doit rester constante : aucune matiere creee par une demande excessive")
	v.v(is_equal_approx(resultat.quantite, 2.0),
		"la quantite rendue doit etre la quantite REELLEMENT retiree, jamais la quantite demandee")
	v.v(resultat.source_epuisee, "une source videe par une demande excessive doit etre marquee epuisee")

# Une source deja a zero ne credite rien, et le dit : quantite = 0.0
# (meme cas neutre que _quand_la_source_est_a_zero_aucun_transfert_ne_se_fait,
# verrouille ici du cote du NOMBRE RENDU, pas seulement du cote du receveur).
func _une_source_a_zero_ne_credite_rien(v) -> void:
	var source := _chose("cristal_zorg", "eclat", 0.0)
	var receveur := _chose("golem_glurp", "charge", 3.0)
	var resultat := Consommer.transferer(source, receveur, "eclat", "charge", 5.0, 1.0)
	v.v(is_equal_approx(resultat.quantite, 0.0),
		"une source a zero doit rendre une quantite reellement transferee de 0.0")
	v.v(is_equal_approx(receveur.proprietes.reserves.charge.reserve, 3.0),
		"une source a zero ne doit jamais faire monter le receveur d'un iota")
	v.v(is_equal_approx(source.proprietes.reserves.eclat.reserve, 0.0),
		"une source a zero doit rester a zero, jamais descendre en negatif")

# LA serrure generaliste : deux reserves fictives sans aucun rapport avec
# nourriture/energie, memes noms de reserve arbitraires, traversent le
# meme code -- consommer.gd ne nomme jamais "comestibilite" ni "valeur_
# nutritive_energie" ni aucun nom de domaine.
func _le_modele_ignore_le_domaine(v) -> void:
	var source := _chose("mineral_inconnu", "reserve_zorg", 7.0)
	var receveur := _chose("machine_glurp", "reserve_glurp", 1.0)
	var resultat := Consommer.transferer(source, receveur, "reserve_zorg", "reserve_glurp", 4.0, 1.0)
	v.v(is_equal_approx(source.proprietes.reserves.reserve_zorg.reserve, 3.0),
		"un domaine invente doit traverser exactement le meme code de soustraction")
	v.v(is_equal_approx(receveur.proprietes.reserves.reserve_glurp.reserve, 5.0),
		"un domaine invente doit traverser exactement le meme code de credit")
	v.v(not resultat.source_epuisee, "domaine invente : source non epuisee, meme logique que le cas reel")

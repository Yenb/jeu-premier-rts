extends RefCounted

# SIXIEME mecanisme du coeur neuf de cette session (chantier
# "consommer.gd -- transfert destructif + banc_manger"). Modele generique
# de TRANSFERT DESTRUCTIF : une chose portant une reserve SOURCE en perd,
# une chose portant une reserve RECEPTRICE en gagne EXACTEMENT la meme
# quantite, au meme tick. Difference avec flux.gd (transfert continu qui NE
# DEPLETE JAMAIS sa source, "flux.gd:10-12") : ici la source se VIDE --
# manger, boire, miner, recolter, traire, vampiriser partagent tous ce
# geste, aucun nom de contenu en dur.
#
# Aucun nom de propriete en dur ici : "taux" est deja un nombre resolu par
# l'appelant (le cablage du banc, ex. valeur_nutritive_energie *
# comestibilite pour "manger") -- consommer.gd ne lit jamais
# comestibilite/valeur_nutritive_energie ni aucun autre nom de domaine,
# seulement des noms de RESERVE (String, cles de proprietes.reserves).
#
# Meme forme de canal que depense.gd/flux.gd (proprietes.reserves.<nom>.
# reserve). BORNE BASSE identique a depense.gd (bug ferme 2026-08-07) :
# la reserve source est bornee a 0.0 A LA SOUSTRACTION (max(0.0, ...)),
# jamais negative.
#
# CONSERVATIF PAR CONSTRUCTION (bug ferme, chantier « correction
# consommer.gd -- borner le credit a la quantite reellement retiree ») : le
# receveur est credite de la quantite REELLEMENT RETIREE a la source
# (reserve_avant - reserve_apres), JAMAIS de la quantite DEMANDEE
# (taux * delta). Demander plus que la source ne possede ne cree donc
# aucune matiere : la somme source + receveur est invariante, quel que
# soit le taux ou le delta. Auparavant le credit valait taux*delta meme
# quand la source, bornee a 0.0, avait perdu moins -- trois appelants
# (ecoulement.gd, banc_fertilite.gd, banc_erosion.gd) pre-bornaient
# eux-memes pour s'en proteger ; ce pre-bornage n'est plus NECESSAIRE
# (garde, inoffensif -- min(demande, restant) est simplement redondant
# avec ce que ce fichier fait maintenant).
#
# Ne transforme JAMAIS l'objet source epuise -- ce fichier calcule un
# FLAG "source_epuisee", jamais un appel a produit.gd. Meme discipline que
# frappe.gd, qui ne transforme jamais lui-meme : c'est au cablage du banc
# d'appeler Produit.transformer quand source_epuisee est vrai.
#
# Recoit :
# - source (Dictionary { id, position, proprietes }) : proprietes.reserves.
#   <nom_reserve_source>.reserve lue. Reserve DEJA a zero -> AUCUN transfert,
#   "source_epuisee" rendu vrai quand meme (c'est un etat, pas seulement
#   un evenement de CE tick -- une source qui reste a zero reste epuisee).
#   Reserve ABSENTE (jamais existe) -> AUCUN transfert, "source_epuisee"
#   rendu faux (rien a epuiser, cas neutre legitime, jamais une alarme).
# - receveur (Dictionary { id, position, proprietes }) : proprietes.
#   reserves.<nom_reserve_receveur> cree (canal minimal { "reserve": 0.0 })
#   s'il n'existe pas encore, meme geste que flux.gd:_recharger.
# - nom_reserve_source / nom_reserve_receveur (String) : noms de reserve,
#   jamais des noms de propriete de domaine.
# - taux (float) : quantite transferee par seconde, DEJA RESOLU par
#   l'appelant (peut composer plusieurs proprietes, ex. valeur_nutritive_
#   energie * comestibilite -- ce calcul n'a pas sa place ici).
# - delta (float) : temps ecoule ce pas, en secondes.
#
# Rend un Dictionary { "source": Dictionary, "receveur": Dictionary,
# "source_epuisee": bool, "quantite": float } -- les DEUX objets recus,
# MUTES EN PLACE (memes references, pas des copies) et renvoyes par
# commodite d'appel ; "source_epuisee" vrai des que la reserve source EST
# a 0.0 (avant ou apres ce transfert -- voir ci-dessus) ; "quantite" est
# la quantite REELLEMENT transferee ce pas (jamais la quantite demandee),
# 0.0 sur tout cas neutre (reserve absente, source deja vide, taux ou
# delta nuls). Un taux/delta nuls ne mutent rien (quantite calculee a 0.0
# ne fait jamais rien) mais rendent quand meme "source_epuisee" reflet
# exact de l'etat courant de la reserve.
static func transferer(
	source: Dictionary,
	receveur: Dictionary,
	nom_reserve_source: String,
	nom_reserve_receveur: String,
	taux: float,
	delta: float,
) -> Dictionary:
	var reserves_source: Dictionary = source.get("proprietes", {}).get("reserves", {})
	if not reserves_source.has(nom_reserve_source):
		return {"source": source, "receveur": receveur, "source_epuisee": false, "quantite": 0.0}
	var canal_source: Dictionary = reserves_source[nom_reserve_source]
	var reserve_source: float = canal_source.get("reserve", 0.0)
	if reserve_source <= 0.0:
		return {"source": source, "receveur": receveur, "source_epuisee": true, "quantite": 0.0}

	var demande: float = taux * delta
	if demande <= 0.0:
		return {"source": source, "receveur": receveur, "source_epuisee": false, "quantite": 0.0}

	var nouvelle_reserve: float = max(0.0, reserve_source - demande)
	canal_source["reserve"] = nouvelle_reserve

	# LE credit se fait sur ce que la source a REELLEMENT perdu, jamais sur
	# la demande : quand la demande depasse le restant, la borne a 0.0 a
	# retire moins que demande -- crediter la demande creerait de la matiere.
	var quantite_reelle: float = reserve_source - nouvelle_reserve
	_crediter(receveur.proprietes, nom_reserve_receveur, quantite_reelle)

	return {
		"source": source,
		"receveur": receveur,
		"source_epuisee": nouvelle_reserve == 0.0,
		"quantite": quantite_reelle,
	}

static func _crediter(proprietes: Dictionary, nom_reserve: String, quantite: float) -> void:
	if not proprietes.has("reserves"):
		proprietes["reserves"] = {}
	var reserves: Dictionary = proprietes["reserves"]
	if not reserves.has(nom_reserve):
		reserves[nom_reserve] = {"reserve": 0.0}
	var canal: Dictionary = reserves[nom_reserve]
	canal["reserve"] = canal.get("reserve", 0.0) + quantite

extends RefCounted

# Mecanisme du coeur : MEMOIRE SPATIALE -- un percevant RETIENT OU il a vu une
# chose, et peut ensuite viser ce SOUVENIR plutot que le reel. Chantier
# « memoire spatiale + navigation par memoire », audit prealable
# audit_perception_croyance_memoire_prealable.md, lignes 5 et 6.
#
# CE QUE CE FICHIER EXISTE POUR COMBLER, ET RIEN D'AUTRE.
# lien_personnel_attraction.gd rend deja un candidat de saillance pour une
# chose HORS DE PORTEE DE PERCEPTION -- c'est ecrit et ferme. Mais il relit
# `wrapper.chose.position` a chaque tick, et monde.gd le confirme dans son
# en-tete : « la position est toujours relue depuis chose.position au moment de
# la requete, jamais figee a l'ajout ». Le percevant suit donc une chose qui
# BOUGERAIT, par telepathie. Et la position ne peut PAS vivre dans
# proprietes.liens_personnels : sa valeur est un float NU, sa resumabilite
# l'impose (« ne porte jamais que des float en valeur »), et l'enrichir
# casserait lien_personnel_saillance.gd, lien_personnel_attraction.gd,
# lien_personnel_croissance.gd, attache_par_trait.gd et agir.gd -- cinq
# fichiers du coeur. D'ou un registre SEPARE : meme FORME que
# lien_personnel.gd (Dictionary plat sur l'entite, trois fonctions, plancher de
# suppression), valeur ENRICHIE, et AUCUN fichier existant touche.
#
# ---------------------------------------------------------------------------
# STRUCTURE SUR L'ENTITE
# ---------------------------------------------------------------------------
# proprietes.memoire_spatiale = {
#   "<chose_id>": { "position": { "x": float, "y": float, "z": float },
#                   "force": float }
# }
#
# STRUCTURELLE, meme convention que proprietes.liens_personnels/deformation/
# engagement : sa cle ABSENTE dit « ceci n'est pas une entite equipee pour
# retenir une position », jamais « aucun souvenir » -- push_error, jamais un
# defaut silencieux. Sa valeur VIDE ({}) est legitime (rien de percu encore).
# Une chose absente du registre est un point neutre legitime : memoriser() la
# cree, avancer()/position_memorisee() ne l'inventent jamais.
#
# RESUMABILITE JSON STRICTE (docs/cadrage_corps_interne_colon.md) : la position
# est SERIALISEE en { x, y, z }, jamais un Vector3 -- un Vector3 ne survit pas
# a JSON.stringify/parse_string. VERTICALITE tenue a l'autre bout : l'API
# expose des Vector3 (memoriser en recoit un, position_memorisee en rend un),
# la serialisation ne vit qu'a l'interieur du registre.
#
# ---------------------------------------------------------------------------
# L'ERREUR EST DETERMINISTE -- REGLE ANTI-BRUIT, PAS UNE PRECAUTION
# ---------------------------------------------------------------------------
# CLAUDE.md, regle non negociable : « aucun hasard non-seede ». Et le depot va
# plus loin -- il n'y a AUCUN RNG nulle part (banc_menace_combat.gd : « pas un
# seul RNG dans le fichier » ; data/etats.json:colere : « RIEN DE STOCHASTIQUE
# la-dedans malgre le nom »). Ce fichier n'en introduit pas un.
# L'erreur est donc une FONCTION PURE de ses entrees : memes entrees, meme
# sortie, a la virgule pres, cent fois de suite (verrouille par test).
#
# DEUX MOITIES, et il ne faut pas les confondre :
# - COMBIEN on se trompe (`erreur`, un scalaire) : une memoire faible et la
#   nuit s'additionnent.
# - VERS OU on se trompe (`biais`, une direction) : derive du HASH de chose_id
#   -- une propriete de la CHOSE mal memorisee, stable dans le temps (le
#   souvenir derive toujours du meme cote, il ne tremble jamais d'un tick a
#   l'autre) -- multipliee par `forme.biais`, une propriete du PERCEVANT (un
#   stresse devie plus). Deux percevants de forme differente ont donc des biais
#   differents pour la MEME chose, et un percevant de biais nul ne devie
#   jamais, quelle que soit l'erreur.
#
# LE BIAIS RESTE DANS LE PLAN XY (z = 0.0). VERTICALITE tenue au sens de
# CLAUDE.md (tout est Vector3, jamais Vector2), mais aucun mecanisme du depot
# ne pose aujourd'hui d'altitude : un biais en Z pousserait la cible hors du
# plan de tous les bancs existants, et le souvenir paraitrait plus proche qu'il
# ne l'est. SIGNALE, jamais masque -- a rouvrir le jour ou une altitude reelle
# existe, c'est une ligne ici.
#
# ---------------------------------------------------------------------------
# CE QUE CE FICHIER NE FAIT PAS
# ---------------------------------------------------------------------------
# - Il ne PERCOIT rien : c'est l'appelant qui decide QUOI memoriser et QUAND
#   (perception.gd rend deja `position` sur chaque entree). Ce fichier ne
#   connait ni monde, ni perception, ni canal.
# - Il ne BORNE PAS LE HAUT d'une force. Constat deja pose cinq fois dans le
#   depot (banc_fertilite.gd, puis repete) : le coeur ne plafonne jamais, le
#   plafond vit au CABLAGE. Un appelant qui memorise chaque tick doit ecreter
#   lui-meme (patron banc_fatigue_circadien.gd:plafonner_reserves). Consequence
#   assumee et fermee ici : `1.0 - force` est CLAMPE dans [0, 1] au moment du
#   calcul -- sans ce clamp une force superieure a 1.0 rendrait une erreur
#   NEGATIVE, c'est-a-dire un biais RETOURNE, faux positif silencieux. Le clamp
#   protege la LECTURE, il ne plafonne pas le registre.
# - Il ne connait AUCUN nom de chose du monde : `chose_id` est une cle opaque,
#   `forme` un Dictionary de nombres. Aucun type, aucune propriete de contenu.
#
# ---------------------------------------------------------------------------
# ENTREES / SORTIES
# ---------------------------------------------------------------------------
# entite : Dictionary { id, position, proprietes }, MUTE EN PLACE par
#          memoriser()/avancer(). position_memorisee() ne mute JAMAIS rien.
# chose_id : String, identifiant opaque.
# position : Vector3 (memoriser) -- l'endroit OBSERVE, jamais relu plus tard.
# forme : Dictionary du percevant (proprietes.forme), meme Dictionary que lisent
#         deja dominance.gd/attaches.gd/jugement.gd/agir.gd. Seule cle lue :
#         `biais` (float), FACULTATIVE, defaut 0.0 -- un percevant sans terme de
#         biais ne devie jamais, point neutre legitime, jamais une alarme (meme
#         convention que forme.gain_inertie/forme.gain_jugement).
# heure : float. RECU, JAMAIS LU PAR LE CALCUL aujourd'hui -- la nuit entre par
#         `luminosite`, que l'appelant tire de lumiere.gd:soleil(heure, ...).
#         Garde par SYMETRIE avec le reste du depot et pour que l'appelant n'ait
#         rien a restructurer le jour ou une loi horaire s'y ajoute : precedent
#         explicite et documente, lumiere.gd:avancer recoit `delta` « SANS EFFET
#         sur le resultat ». Dit ici plutot que masque.
# luminosite : float, 0.0 nuit noire -> 1.0 plein jour. Meme echelle que
#              lumiere.gd:locale/soleil rendent en `intensite` -- jamais
#              recalculee ici, jamais bornee a l'ecriture, CLAMPEE a la lecture
#              pour la meme raison que la force.
# catalogue : Dictionary "defaut" -> { force_initiale, taux_decroissance,
#             plancher_suppression, coef_memoire_faible, coef_nuit } --
#             data/memoire_spatiale.json, JAMAIS charge par ce fichier (meme
#             convention que lien_personnel.gd/deformation.gd/lumiere.gd).
#             Catalogue sans entree "defaut" : push_error, et le registre reste
#             INTACT (memoriser n'ecrit rien, avancer ne decroit rien,
#             position_memorisee rend le repli d'absence).
#
# ECART ASSUME AVEC LA SIGNATURE DU PROMPT D'OUVERTURE, a trancher par Yael :
# le prompt fixait `position_memorisee(entite, chose_id, forme, heure,
# luminosite)` SANS catalogue, tout en placant `coef_memoire_faible`/`coef_nuit`
# dans data/memoire_spatiale.json. Les deux ne peuvent pas tenir ensemble : un
# mecanisme du coeur ne charge jamais son catalogue lui-meme. Le catalogue est
# donc passe en dernier parametre, comme partout ailleurs dans scripts/.

const REFERENCE_DEFAUT := "defaut"
const CLE_REGISTRE := "memoire_spatiale"

# Nombre de directions distinctes que le hash peut rendre. Une constante de
# QUANTIFICATION, pas une calibration de jeu : elle ne change ni l'amplitude ni
# la loi, seulement la finesse du repartiteur de directions -- elle n'a donc
# rien a faire en donnee (aucune decision de design ne s'y prend).
const _PAS_ANGULAIRES := 3600

# Ecrit ou met a jour le souvenir d'une chose. La POSITION est TOUJOURS
# reecrite (une nouvelle observation dit ou la chose est MAINTENANT -- c'est
# tout le sujet : sans cette reecriture, reapercevoir ne corrigerait jamais un
# souvenir perime). La FORCE, elle, s'ACCUMULE et ne remplace jamais -- patron
# exact de lien_personnel.gd:poser, meme raison : revoir une chose renforce le
# souvenir, il ne le remet pas a son niveau de depart.
static func memoriser(entite: Dictionary, chose_id: String, position: Vector3, catalogue: Dictionary) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has(CLE_REGISTRE):
		push_error("memoire_spatiale.gd : propriete structurelle '%s' absente de proprietes" % CLE_REGISTRE)
		return
	if not catalogue.has(REFERENCE_DEFAUT):
		push_error("memoire_spatiale.gd : catalogue sans entree '%s'" % REFERENCE_DEFAUT)
		return
	var regle: Dictionary = catalogue[REFERENCE_DEFAUT]
	var gain: float = regle.get("force_initiale", 0.0)
	var registre: Dictionary = proprietes[CLE_REGISTRE]
	var force_precedente: float = 0.0
	if registre.has(chose_id):
		force_precedente = float(registre[chose_id].get("force", 0.0))
	registre[chose_id] = {
		"position": {"x": position.x, "y": position.y, "z": position.z},
		"force": force_precedente + gain,
	}

# Decroissance de tous les souvenirs, et RETRAIT sous le plancher. Patron exact
# de lien_personnel.gd:avancer -- soustraction FIXE (`max(0, f - taux*delta)`),
# jamais une exponentielle : aucune decroissance du depot n'en est une, et il
# n'existe AUCUN equilibre naturel (constat (F) de l'audit, resultat negatif
# deja paye deux fois en donnee). Sans le retrait sous plancher, le registre
# grossirait indefiniment de souvenirs residuels quasi nuls -- et un souvenir a
# 0.001 de force n'est pas un souvenir faible, c'est un souvenir OUBLIE.
# Les cles a retirer sont collectees AVANT d'effacer : muter un Dictionary
# pendant qu'on l'itere n'est jamais sur.
static func avancer(entite: Dictionary, delta: float, catalogue: Dictionary) -> void:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has(CLE_REGISTRE):
		push_error("memoire_spatiale.gd : propriete structurelle '%s' absente de proprietes" % CLE_REGISTRE)
		return
	if not catalogue.has(REFERENCE_DEFAUT):
		push_error("memoire_spatiale.gd : catalogue sans entree '%s'" % REFERENCE_DEFAUT)
		return
	var regle: Dictionary = catalogue[REFERENCE_DEFAUT]
	var taux: float = regle.get("taux_decroissance", 0.0)
	var plancher: float = regle.get("plancher_suppression", 0.0)
	var registre: Dictionary = proprietes[CLE_REGISTRE]
	var a_retirer: Array = []
	for chose_id in registre:
		var entree: Dictionary = registre[chose_id]
		var force_restante: float = max(0.0, float(entree.get("force", 0.0)) - taux * delta)
		entree["force"] = force_restante
		if force_restante < plancher:
			a_retirer.append(chose_id)
	for chose_id in a_retirer:
		registre.erase(chose_id)

# LA LECTURE -- ne mute rien, ni le registre, ni l'entite, ni la forme.
# Rend { position: Vector3, force: float, erreur: float } ou :
# - `position` est le souvenir DEJA BIAISE (position memorisee + biais *
#   erreur) : c'est elle qu'un cablage passe a banc_commun.gd:bouger_vers.
#   Le souvenir NON biaise n'est jamais rendu -- personne n'a a le connaitre,
#   et le rendre inviterait un appelant a « corriger » l'erreur, ce qui viderait
#   ce fichier de sa raison d'etre.
# - `force` est la force BRUTE du souvenir (jamais clampee : c'est une valeur de
#   diagnostic, un cablage qui ecrete la lit telle qu'elle est).
# - `erreur` est le scalaire, deja compose : (1-force)*coef_memoire_faible +
#   (1-luminosite)*coef_nuit, chaque terme clampe a [0, 1] AVANT ponderation.
# CHOSE INCONNUE (jamais memorisee, ou souvenir tombe sous le plancher et
# retire) : { Vector3.ZERO, 0.0, INF } -- INF et non un grand nombre, parce
# qu'il n'y a rien a viser du tout, et qu'un appelant doit pouvoir distinguer
# « je ne sais pas » de « je sais tres mal ». Vector3.ZERO n'est PAS une
# position a suivre : c'est la valeur neutre qui accompagne erreur == INF, et
# tout appelant doit tester `erreur` (ou `force`) avant de bouger. Meme repli
# en cas de propriete structurelle absente ou de catalogue sans "defaut" --
# alarme, jamais un silence.
static func position_memorisee(
	entite: Dictionary,
	chose_id: String,
	forme: Dictionary,
	heure: float,
	luminosite: float,
	catalogue: Dictionary,
) -> Dictionary:
	var proprietes: Dictionary = entite.get("proprietes", {})
	if not proprietes.has(CLE_REGISTRE):
		push_error("memoire_spatiale.gd : propriete structurelle '%s' absente de proprietes" % CLE_REGISTRE)
		return _inconnue()
	if not catalogue.has(REFERENCE_DEFAUT):
		push_error("memoire_spatiale.gd : catalogue sans entree '%s'" % REFERENCE_DEFAUT)
		return _inconnue()
	var registre: Dictionary = proprietes[CLE_REGISTRE]
	if not registre.has(chose_id):
		return _inconnue()

	var entree: Dictionary = registre[chose_id]
	var brute: Dictionary = entree.get("position", {})
	var souvenir := Vector3(brute.get("x", 0.0), brute.get("y", 0.0), brute.get("z", 0.0))
	var force: float = float(entree.get("force", 0.0))

	var regle: Dictionary = catalogue[REFERENCE_DEFAUT]
	var erreur_base: float = clamp(1.0 - force, 0.0, 1.0) * float(regle.get("coef_memoire_faible", 0.0))
	var erreur_nuit: float = clamp(1.0 - luminosite, 0.0, 1.0) * float(regle.get("coef_nuit", 0.0))
	var erreur: float = erreur_base + erreur_nuit

	return {
		"position": souvenir + _biais(chose_id, forme) * erreur,
		"force": force,
		"erreur": erreur,
	}

static func _inconnue() -> Dictionary:
	return {"position": Vector3.ZERO, "force": 0.0, "erreur": INF}

# DIRECTION du biais : derivee du hash de chose_id, quantifiee en
# _PAS_ANGULAIRES directions du plan XY. absi() parce qu'un hash negatif
# rendrait un modulo negatif en GDScript, donc un angle hors [0, TAU) -- pas
# faux, mais illisible. AMPLITUDE : forme.biais, la seule chose que ce fichier
# lise du percevant. Amplitude nulle -> biais nul, sans meme calculer d'angle :
# un percevant sans terme de biais vise exactement son souvenir, aussi vieux
# soit-il.
static func _biais(chose_id: String, forme: Dictionary) -> Vector3:
	var amplitude: float = float(forme.get("biais", 0.0))
	if amplitude == 0.0:
		return Vector3.ZERO
	var pas: int = absi(chose_id.hash()) % _PAS_ANGULAIRES
	var angle: float = TAU * float(pas) / float(_PAS_ANGULAIRES)
	return Vector3(cos(angle), sin(angle), 0.0) * amplitude

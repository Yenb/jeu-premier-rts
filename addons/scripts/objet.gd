extends RefCounted

# Structure objet (voir docs/design.md, "Tout est objet") : un objet du
# monde est { id, position, proprietes }. Le type n'est qu'un raccourci
# de fabrication -- il charge un paquet de proprietes depuis une table
# de donnees et disparait. Une fois fabrique, l'objet ne porte plus que
# ses proprietes ; le moteur ne relit jamais le type d'origine.
#
# duplicate(true) : la table est un gabarit partage entre tous les
# objets d'un meme type. Sans copie, muter les proprietes d'un objet en
# jeu (ex. eteindre un feu) muterait le gabarit et contaminerait tous les
# autres objets du meme type.
#
# FUSION PAR COMPOSITION DE PAQUETS (PHASE 1, chantier "L'entite comme
# agent complet" -- refonte session ulterieure : d'un drapeau unaire
# "herite_entite" vers une composition explicite a N paquets) :
# docs/design.md, "Le colon n'est pas un type parent" interdit toute
# hierarchie IMPLICITE entre types (chaque type reste un paquet complet
# et autonome, Objet.fabriquer ne doit jamais deviner qu'un type
# "herite" d'un autre). Ici la fusion n'est donc jamais automatique : un
# type ne recoit les proprietes d'AUCUN paquet sauf s'il porte lui-meme,
# en donnee, la cle "herite" : Array de noms de paquet, dans l'ordre ou
# ils doivent se fusionner (voir data/types.json, "colon" ->
# ["objet_physique", "dynamique", "percevant", "agent"]).
# Cle absente ou Array vide : comportement neutre, aucune fusion -- une
# composition a zero paquet reste un type autonome comme n'importe quel
# autre. Avec un ou plusieurs noms : chaque paquet est duplique et
# fusionne DANS L'ORDRE DECLARE (le second ecrase les cles communes du
# premier, etc.), puis les proprietes du type demande sont fusionnees
# PAR-DESSUS TOUS les paquets deja fusionnes (ecrasent les cles
# communes) -- "prendre les paquets dans l'ordre, puis ecraser avec le
# type" reste explicite, jamais une hierarchie devinee : un colon n'est
# pas un sous-type d'entite, c'est une composition de paquets
# independants. La cle "herite" elle-meme est retiree du resultat, que
# la fusion ait pu avoir lieu ou non (sur N paquets, sur un seul, ou sur
# zero) : c'est une INSTRUCTION DE FABRICATION, pas une propriete de jeu
# -- la laisser trainer sur l'objet ne servirait jamais a rien, et
# polluerait proprietes d'une cle morte. Un paquet nomme dans "herite"
# mais absent de la table est une donnee incoherente -- push_error
# nommant le paquet ET le type qui le reference, puis repli sur les
# paquets resolus + le type, jamais un defaut silencieux.
#
# RESOLUTION NON RECURSIVE (garde ajoutee session ulterieure, audit
# prealable) : un paquet nomme dans "herite" qui porte lui-meme une cle
# "herite" n'est PAS resolu recursivement -- cette cle serait sinon
# fusionnee comme une propriete ordinaire, silencieusement ecrasee, puis
# perdue au retrait final de "herite", sans qu'aucune alarme ne le
# signale. La garde alarme (push_error nommant le paquet ET sa propre
# cle "herite"), retire cette cle du paquet intermediaire AVANT fusion
# (jamais tentee de resolution recursive), et continue de fusionner le
# reste du paquet normalement.
#
# Reçoit : id (String), type (String, cle dans table), position (Vector3),
# table (Dictionary type -> proprietes, ex. data/types.json), materiaux
# (Dictionary reference -> fiche de proprietes physiques, ex.
# data/materiaux.json -- FACULTATIF, defaut {}, voir DENSITE EFFECTIVE
# ci-dessous), proprietes_immuables (Array de String -- FACULTATIF, defaut
# [], voir RESERVE reecrite ci-dessous), reserve_combustible (Dictionary --
# FACULTATIF, defaut {}, voir RESERVE DE COMBUSTIBLE ci-dessous),
# catalogue_emergences (Array -- FACULTATIF, defaut [], voir EMERGENCES
# ci-dessous). Rend un objet { id, position, proprietes }, ou {} (Dictionary
# vide) si la fabrication est REFUSEE (voir DENSITE EFFECTIVE, echec fort).
#
# Ne fait pas : aucune requete spatiale, ne connait pas le monde -- voir
# perception.gd / monde.gd.
#
# DENSITE EFFECTIVE, calculee UNE FOIS A LA FABRICATION (chantier "la
# densite effective calculee a la fabrication", premiere brique physique
# dont les futurs mecanismes d'element -- CARTE.md §6, "L'entite comme agent
# complet" -- liront la densite comme une valeur plate, jamais recalculee).
# Un objet ne change JAMAIS sa composition de sa vie (se casser DETRUIT
# l'objet et en CREE d'autres, ca ne le modifie pas) -- la densite
# effective est donc IMMUABLE apres fabrication : posee ici, jamais
# recalculee par un tick, jamais mise en cache a part (le cache EST
# proprietes.densite lui-meme).
#
# GATE : strictement conditionne a proprietes.has("composition") APRES la
# fusion herite+type ci-dessus -- un objet qui ne porte pas cette cle
# (colon, feu, batisse, menace, et tout type futur non physique) traverse
# cette fonction EXACTEMENT comme avant ce chantier : chemin mort, aucune
# cle ajoutee, aucune valeur changee. MEME GATE pour proprietes_immuables :
# un objet sans "composition" ne recoit jamais "inflammabilite" ni aucune
# autre propriete listee -- absente, jamais un defaut 0.0 pose quand meme.
# MEME GATE pour reserve_combustible : un objet sans "composition" ne
# recoit jamais de canal calcule, "reserves" n'est pas touche -- il garde
# son forfait actuel (data/transformations.json:patron), pose ailleurs.
#
# composition : Array de { materiau: String, volume: float } -- TOUJOURS
# une liste, le mono-materiau etant le cas a un seul element (memes
# reponses "arbre"/"bloc" ci-dessous, patron data/types.json) ; aucune
# branche mono vs multi, le meme calcul traite un ou plusieurs termes.
# materiau est une reference vers materiaux (data/materiaux.json), MEME
# PATRON que profil_saillance -> data/profils_saillance.json
# (proximite.gd) : une String sur l'instance/l'element de composition,
# jamais fusionnee en dur -- ce fichier ne connait aucun nom de materiau.
#
# FORMULE (moyenne ponderee des volumes, aucun cas particulier) :
#   rho_effective = somme(rho_i * volume_i) / somme(volume_i)
#   volume total  = somme(volume_i)                              -- DERIVE
#   densite       = rho_effective                                -- DERIVE
#   masse         = densite * volume total                       -- DERIVE
#     (convention objet_physique deja en place : masse == densite*volume)
# Les trois (volume/densite/masse) sont ECRITS sur proprietes, remplacant
# les defauts herites du paquet objet_physique -- ce sont des SORTIES,
# plus jamais des entrees posees a la main sur une instance (voir
# data/types.json:arbre/bloc, qui ne portent plus que "composition").
#
# UNITE : materiaux.json porte "densite" en g/cm3 (lisibilite reelle --
# "plus leger/lourd que l'eau", ancrage LLM, voir materiaux.json:_note) ;
# objet_physique travaille en kg/m3 (SI, deja la convention des valeurs
# historiques d'arbre/bloc). La conversion vit ICI, EN CODE, jamais dans
# le catalogue -- G_CM3_VERS_KG_M3 est LA SEULE ligne qui la porte ;
# materiaux.json n'est JAMAIS mute ni relu dans une autre unite.
#
# ECHEC FORT (decision explicite, PAS le patron "ignorer + continuer" de
# herite sur paquet absent ci-dessus) : la composition est ce dont l'objet
# EST FAIT, pas un supplement facultatif -- un materiau absent de
# materiaux.json, ou une fiche resolue sans cle "densite", est une donnee
# cassee A LA RACINE. push_error nommant l'objet (id ET type) ET le
# materiau fautif POUR CHAQUE element fautif de composition (utile si
# plusieurs le sont a la fois), puis fabriquer() REND {} (Dictionary vide)
# -- l'objet N'EST PAS PRODUIT, jamais une densite mensongere qui laisserait
# passer une donnee douteuse (meme philosophie que le linter,
# scripts/test_lint_donnees.gd : refuser a l'entree). Une composition
# presente mais VIDE, ou dont le volume total resout a 0.0, echoue de la
# meme facon (aucune densite ne se calcule sur un objet "fait de rien") --
# meme severite, pas une exception. TOUT APPELANT DE fabriquer() DOIT donc
# verifier un retour {} avant de lire .id/.position/.proprietes des qu'un
# type qu'il fabrique peut porter "composition" -- mode d'echec choisi
# pour etre le plus visible et le plus tot possible, jamais un defaut
# silencieux ni un crash ambigu plus loin dans le pipeline.
#
# RESERVE (REECRITE, chantier "feu -- inflammabilite effective") : le
# critere de fusion a la fabrication n'a JAMAIS ete "densite seule" -- c'est
# L'IMMUABILITE DE LA COMPOSITION. Une propriete qui ne peut jamais changer
# apres fabrication (se casser DETRUIT l'objet et en CREE d'autres, ca ne
# le modifie jamais -- voir DENSITE EFFECTIVE ci-dessus) peut legitimement
# se calculer UNE FOIS ici plutot qu'a la demande par chaque mecanisme
# d'element. densite/volume/masse restent un cas SPECIAL au sein de ce
# critere, pas son unique exemple : conversion d'unite (g/cm3 -> kg/m3),
# derivation de volume/masse, ECHEC FORT (materiau absent ou fiche sans
# "densite" refuse TOUTE la fabrication) -- rien de tout cela ne
# generalise aux autres proprietes immuables.
#
# Toute AUTRE propriete immuable a fusionner (ex. inflammabilite, chantier
# "feu") vient du parametre proprietes_immuables -- jamais un nom en dur
# ici, catalogue reel : data/proprietes_immuables_composition.json. Chaque
# nom liste y est fusionne par la MEME moyenne ponderee des volumes que
# rho_effective, SANS conversion d'unite ni derivation, et FACULTATIF PAR
# FICHE MATERIAU (contrairement a "densite") : une fiche qui ne porte pas
# la propriete contribue 0.0, aucune alarme -- absence legitime, pas une
# donnee cassee. "densite" ne doit JAMAIS figurer dans proprietes_immuables
# -- son calcul dedie ci-dessus reste la SEULE voie ; une tentative alarme
# (push_error) et est ignoree, jamais recalculee une seconde fois par le
# chemin generique.
#
# Les proprietes NI immuables NI listees (magnetisme, resistances, points
# de fusion... la tres grande majorite des 45 de materiaux.json) restent
# lues A LA DEMANDE par chaque futur mecanisme d'element (ex. champ.gd sur
# magnetisme) -- ce chantier ne les touche pas.
#
# EMERGENCES (chantier "proprietes emergentes -- capacites conditionnelles a
# la fabrication") : DERNIER pas de fabriquer(), une fois herite+type ET la
# fusion par composition (si applicable) deja resolues -- lit proprietes EN
# L'ETAT, jamais avant. NE DEPEND PAS de "composition" -- contrairement a
# densite/proprietes_immuables/reserve_combustible ci-dessus, ce pas
# s'applique a TOUT objet fabrique (colon, feu, compose ou non) : une
# condition sur une propriete absente de l'objet echoue simplement, elle
# n'exige jamais "composition" comme prealable structurel.
#
# LA LOI D'EVALUATION ELLE-MEME N'EST PLUS ICI (chantier "biomes --
# conditions multiples -> type de terrain") : forme d'une entree, ET logique,
# operateurs supportes, coexistence de plusieurs entrees, comportement sur
# propriete absente ou donnee cassee -- tout cela vit desormais dans
# scripts/conditions.gd, extrait de ce fichier pour etre REJOUABLE A CHAQUE
# TICK sur une chose deja construite, pas seulement une fois a la naissance.
# Voir son en-tete, jamais recopie ici.
#
# CE QUE CE FICHIER GARANTIT, ET QUI NE CHANGE PAS APRES L'EXTRACTION :
# l'appel se fait SANS "retirer_si_faux" (defaut false) -- a la fabrication,
# les emergences se MERGENT et ne se retirent JAMAIS. Une capacite issue de
# la matiere ne peut pas disparaitre : un objet ne change jamais de
# composition de sa vie (voir DENSITE EFFECTIVE ci-dessus). Sans ce defaut,
# une emergence non declenchee EFFACERAIT une cle homonyme posee par un
# paquet ou par le type dans data/types.json. Catalogue vide (defaut []) :
# chemin mort, proprietes inchangees.
#
# RESERVE DE COMBUSTIBLE (chantier "feu -- la reserve de combustible suit
# la matiere") : TROISIEME calcul gate sur "composition", apres densite
# (dediee, echec fort) et proprietes_immuables (generique, MOYENNE). La
# CAPACITE est generique et calcule une SOMME (scripts/
# quantite_matiere.gd -- meme geste que champ.gd:_quantite_matiere,
# EXTRAIT dans ce fichier partage plutot que reecrit une troisieme fois ;
# champ.gd lui-meme N'EST PAS TOUCHE, sa copie privee reste une dette
# connue, voir quantite_matiere.gd) : une quantite de matiere est
# EXTENSIVE (un objet deux fois plus gros en contient deux fois plus),
# jamais une moyenne. Piloté par "reserve_combustible" (Dictionary
# FACULTATIF, defaut {} -- data/reserve_combustible_composition.json) :
# { nom_reserve, propriete_materiau, propriete_porosite, cout_base,
# facteur_densite, facteur_porosite, surcout_action, seuils_ref }. VIDE
# (defaut) OU objet SANS "composition" : chemin mort strict, "reserves"
# n'est pas touche -- UN OBJET SANS COMPOSITION GARDE SON FORFAIT ACTUEL
# (data/transformations.json:patron), comportement INCHANGE, aucune
# alarme. Voir scripts/combustible.gd pour la doctrine complete (capacite
# immuable vs reserve qui decroit, et pourquoi ce calcul vit ICI plutot
# qu'a la demande).
#
# VITESSE DE COMBUSTION SELON LA MATIERE (chantier "densite et porosite sur
# la vitesse de combustion") : "cout_base" en config est desormais une
# REFERENCE, pas la valeur finale ecrite sur le canal -- le champ ECRIT
# dans reserves.<nom>.cout_base (celui que depense.gd decremente, contrat
# INCHANGE) est la valeur EFFECTIVE, modulee par la composition :
#   cout_base_effectif = cout_base_reference
#                         * (1.0 + facteur_porosite * porosite_effective)
#                         / (1.0 + facteur_densite * densite_g_cm3_effective)
# Un materiau DENSE ralentit (au denominateur, jamais nul ni negatif :
# densite et facteur_densite sont tous deux positifs par construction) ; un
# materiau POREUX accelere (au numerateur). "densite_g_cm3_effective"
# REUTILISE "proprietes.densite" deja calcule ci-dessus (kg/m3, SI) --
# reconverti en g/cm3 par simple division par G_CM3_VERS_KG_M3, jamais une
# seconde moyenne ponderee independante : la conversion d'unite etant
# lineaire, elle commute avec la moyenne, les deux valeurs ne peuvent donc
# jamais diverger. "porosite_effective" est calculee par la MEME moyenne
# ponderee des volumes que les proprietes immuables (voir
# _moyenne_ponderee_volume ci-dessous, geste partage avec
# _fusionner_proprietes_immuables) -- FACULTATIVE PAR FICHE MATERIAU (une
# fiche sans la propriete nommee par "propriete_porosite" contribue 0.0,
# aucune alarme, meme philosophie que les proprietes immuables) -- et N'EST
# JAMAIS ECRITE sur "proprietes" (contrairement a proprietes_immuables) :
# elle reste un calcul interne a ce chantier, lue a la demande, jamais une
# propriete du monde exposee par ce chantier precis (voir plus haut,
# "proprietes NI immuables NI listees restent lues A LA DEMANDE"). Le NOM
# de la propriete de porosite vient de la donnee ("propriete_porosite"),
# jamais en dur ici -- seule "densite" reste un nom fixe, deja structurel
# et dedie par construction (voir DENSITE EFFECTIVE ci-dessus). Les deux
# facteurs sont DESORMAIS DES CHAMPS REQUIS de la config au meme titre que
# les cinq deja en place -- absents, meme echec (push_error, rien n'est
# ecrit).
const G_CM3_VERS_KG_M3 := 1000.0
const QuantiteMatiere = preload("res://scripts/quantite_matiere.gd")
const Conditions = preload("res://scripts/conditions.gd")

static func fabriquer(id: String, type: String, position: Vector3, table: Dictionary, materiaux: Dictionary = {}, proprietes_immuables: Array = [], reserve_combustible: Dictionary = {}, catalogue_emergences: Array = []) -> Dictionary:
	var proprietes_type: Dictionary = table.get(type, {})
	var proprietes: Dictionary = {}
	for nom_paquet in proprietes_type.get("herite", []):
		if table.has(nom_paquet):
			var paquet: Dictionary = table.get(nom_paquet, {}).duplicate(true)
			if paquet.has("herite"):
				push_error("objet.gd : paquet '%s' declare lui-meme heriter de %s -- resolution non recursive, cle ignoree" % [nom_paquet, str(paquet.herite)])
				paquet.erase("herite")
			proprietes.merge(paquet, true)
		else:
			push_error("objet.gd : type '%s' declare heriter du paquet '%s', absent de la table" % [type, nom_paquet])
	proprietes.merge(proprietes_type.duplicate(true), true)
	proprietes.erase("herite")
	# Les cles de NOTE sont une convention de commentaire du catalogue, jamais
	# une propriete du monde : elles sortent au meme endroit que "herite".
	# Laissees en place, elles voyagent sur chaque instance fabriquee et
	# apparaissent dans tout resume de l'objet -- lu par aucun mecanisme, lu
	# par un futur resumeur.
	for cle in proprietes.keys():
		if String(cle).begins_with("_"):
			proprietes.erase(cle)
	if proprietes.has("composition"):
		if not _calculer_densite_effective(proprietes, materiaux, id, type):
			return {}
		_fusionner_proprietes_immuables(proprietes, materiaux, proprietes_immuables)
		_fabriquer_reserve_combustible(proprietes, materiaux, reserve_combustible)
	_evaluer_emergences(proprietes, catalogue_emergences)
	return {
		"id": id,
		"position": position,
		"proprietes": proprietes,
	}

# Voir EMERGENCES en tete de fichier. La loi d'evaluation vit dans
# scripts/conditions.gd, jamais dupliquee ici. L'appel se fait SANS
# "retirer_si_faux" (defaut false) : a la fabrication, une emergence se
# fusionne et ne se retire jamais -- voir EMERGENCES pour le pourquoi. La
# trace rendue par Conditions.evaluer (ce qui a ete pose/retire) n'a aucun
# usage a la fabrication : "proprietes" est mutee en place, et fabriquer()
# rend l'objet complet juste apres.
static func _evaluer_emergences(proprietes: Dictionary, catalogue_emergences: Array) -> void:
	Conditions.evaluer(proprietes, catalogue_emergences)

# Geste partage entre _fusionner_proprietes_immuables et
# _fabriquer_reserve_combustible (chantier "densite et porosite sur la
# vitesse de combustion") : la MEME moyenne ponderee des volumes que la
# densite mais SANS conversion d'unite ni derivation, sur UNE propriete
# nommee -- jamais un nom en dur ici. Une fiche materiau sans la propriete
# demandee contribue 0.0 -- absence legitime, jamais une alarme (meme
# philosophie que "densite" en est l'exception dediee). Volume total nul
# (composition vide) : rend 0.0 plutot que diviser par zero -- n'arrive
# jamais en pratique ici (appelee uniquement apres que
# _calculer_densite_effective a deja garanti un volume total strictement
# positif), garde defensive plutot qu'un chemin reellement atteint.
static func _moyenne_ponderee_volume(composition: Array, materiaux: Dictionary, nom_propriete: String) -> float:
	var somme_ponderee := 0.0
	var somme_volume := 0.0
	for element in composition:
		var nom_materiau: String = element.get("materiau", "")
		var volume: float = float(element.get("volume", 0.0))
		var fiche: Dictionary = materiaux.get(nom_materiau, {})
		somme_ponderee += float(fiche.get(nom_propriete, 0.0)) * volume
		somme_volume += volume
	if somme_volume <= 0.0:
		return 0.0
	return somme_ponderee / somme_volume

# Voir RESERVE (reecrite) en tete de fichier. Fusionne, par _moyenne_
# ponderee_volume ci-dessus, chaque propriete nommee dans
# "proprietes_immuables" -- reçue en parametre, jamais un nom en dur ici.
# Appelee UNIQUEMENT apres que _calculer_densite_effective a deja reussi :
# le volume total est donc garanti strictement positif et chaque materiau
# de "composition" garanti present dans "materiaux". "densite" elle-meme,
# si presente dans la liste par erreur, est ignoree avec une alarme -- son
# calcul dedie ci-dessus reste la seule voie.
static func _fusionner_proprietes_immuables(proprietes: Dictionary, materiaux: Dictionary, proprietes_immuables: Array) -> void:
	var composition: Array = proprietes.composition
	for nom_propriete in proprietes_immuables:
		if nom_propriete == "densite":
			push_error("objet.gd : 'densite' ne doit pas figurer dans proprietes_immuables -- calcul dedie deja en place (conversion d'unite, masse/volume, echec fort), entree ignoree")
			continue
		proprietes[nom_propriete] = _moyenne_ponderee_volume(composition, materiaux, nom_propriete)

# Voir RESERVE DE COMBUSTIBLE en tete de fichier, et scripts/combustible.gd
# pour la doctrine complete du canal produit. VIDE (config par defaut) :
# rien n'est ecrit, "reserves" n'est pas touche -- chemin mort. Un champ
# requis absent de "config" : push_error nommant le champ manquant, rien
# n'est ecrit (donnee cassee, meme severite que les autres references de
# catalogue de ce fichier). Sinon : calcule la CAPACITE (SOMME ponderee
# par volume via QuantiteMatiere.quantite, jamais une moyenne) et ECRIT
# le canal complet -- { capacite, reserve, cout_base, surcout_action,
# seuils_ref } -- sous proprietes.reserves[nom_reserve], EN FUSIONNANT
# dans "reserves" si la cle existe deja (un type qui compose "dynamique"
# porte deja d'autres canaux -- energie, faim... -- jamais ecrases).
# "capacite" et "reserve" demarrent a la MEME valeur : "reserve" est le
# SEUL champ que depense.gd decremente ensuite, "capacite" ne sera plus
# jamais reecrite par aucun mecanisme de ce depot.
static func _fabriquer_reserve_combustible(proprietes: Dictionary, materiaux: Dictionary, config: Dictionary) -> void:
	if config.is_empty():
		return
	for champ_requis in ["nom_reserve", "propriete_materiau", "propriete_porosite", "cout_base", "facteur_densite", "facteur_porosite", "surcout_action", "seuils_ref"]:
		if not config.has(champ_requis):
			push_error("objet.gd : reserve_combustible incomplete, champ '%s' absent -- ignoree" % champ_requis)
			return
	var capacite: float = QuantiteMatiere.quantite(proprietes, config.propriete_materiau, materiaux)
	var porosite_effective: float = _moyenne_ponderee_volume(proprietes.composition, materiaux, config.propriete_porosite)
	var densite_g_cm3_effective: float = float(proprietes.densite) / G_CM3_VERS_KG_M3
	var cout_base_effectif: float = float(config.cout_base) \
		* (1.0 + float(config.facteur_porosite) * porosite_effective) \
		/ (1.0 + float(config.facteur_densite) * densite_g_cm3_effective)
	var reserves: Dictionary = proprietes.get("reserves", {})
	reserves[config.nom_reserve] = {
		"capacite": capacite,
		"reserve": capacite,
		"cout_base": cout_base_effectif,
		"surcout_action": config.surcout_action,
		"seuils_ref": config.seuils_ref,
	}
	proprietes["reserves"] = reserves

# Voir DENSITE EFFECTIVE en tete de fichier pour la doctrine complete.
# Mute "proprietes" en place (volume/densite/masse) UNIQUEMENT en cas de
# succes ; rend false sans rien ecrire des qu'un element de composition est
# fautif (materiau absent du catalogue, ou fiche sans "densite") ou que le
# volume total resout a 0.0 -- l'appelant (fabriquer) traduit false en un
# retour {} pour toute la fabrication, jamais une ecriture partielle.
static func _calculer_densite_effective(proprietes: Dictionary, materiaux: Dictionary, id: String, type: String) -> bool:
	var composition: Array = proprietes.composition
	var somme_volume := 0.0
	var somme_masse_volumique := 0.0
	var tout_resolu := true
	for element in composition:
		var nom_materiau: String = element.get("materiau", "")
		var volume: float = element.get("volume", 0.0)
		if not materiaux.has(nom_materiau):
			push_error("objet.gd : objet '%s' (type '%s') -- materiau '%s' absent de materiaux.json, fabrication refusee" % [id, type, nom_materiau])
			tout_resolu = false
			continue
		var fiche: Dictionary = materiaux[nom_materiau]
		if not fiche.has("densite"):
			push_error("objet.gd : objet '%s' (type '%s') -- fiche materiau '%s' sans propriete 'densite', fabrication refusee" % [id, type, nom_materiau])
			tout_resolu = false
			continue
		var rho_kg_m3: float = float(fiche.densite) * G_CM3_VERS_KG_M3
		somme_volume += volume
		somme_masse_volumique += rho_kg_m3 * volume
	if not tout_resolu:
		return false
	if somme_volume <= 0.0:
		push_error("objet.gd : objet '%s' (type '%s') -- composition sans volume total positif, fabrication refusee" % [id, type])
		return false
	var densite_effective: float = somme_masse_volumique / somme_volume
	proprietes["volume"] = somme_volume
	proprietes["densite"] = densite_effective
	proprietes["masse"] = densite_effective * somme_volume
	return true

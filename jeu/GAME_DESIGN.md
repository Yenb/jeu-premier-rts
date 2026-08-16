# Game Design — Premier RTS

Ce document porte les décisions de game design du jeu. Il ne
porte PAS le design du framework (voir addons/documents/design.md).
Il se lit et se met à jour à chaque session qui touche au gameplay.

## Principes

- La logistique a un coût réel : la distance fatigue les unités,
  consomme les ressources, dégrade l'efficacité au combat.
- Le rush est viable mais facturé : un pari à haut rendement et
  haut risque, pas une stratégie sans coût.
- Chaque style de jeu a un prix. Défensif, offensif, économique
  — aucun n'est gratuit, aucun n'est dominant. Le joueur choisit
  quel prix il accepte de payer.
- Mille joueurs, mille heures, mille doctrines : le test de
  réussite du jeu. Si le joueur n'a pas développé sa propre
  façon de jouer, le game design a échoué.

## IA

- L'IA adversaire est un classifieur LLM, pas un arbre de
  comportement. Elle pèse l'état, elle ne suit pas un script.
- Chaque agent IA est un Modelfile Ollama séparé avec son propre
  system prompt.
- Les agents mémoire sont côté code. Le modèle n'a aucune
  mémoire entre les appels.
- Le comportement de l'IA émerge de l'état, pas d'un profil
  câblé. Pas d'étiquette « turtle » ou « rusher » — l'IA
  réagit à ce qu'elle voit.

## Unités et ressources

(à remplir au fil des sessions)

## Conditions de victoire

(à remplir au fil des sessions)

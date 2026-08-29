# flop!EDT

L'emploi du temps de l'IUT de Blagnac sur iPhone et iPad, alimenté par l'API
publique de [flop!EDT](https://flopedt.iut-blagnac.fr).

## La v2

Réécriture complète. La v1 (tag `v26.03`) codait en dur ses référentiels —
départements, promos, groupes, durées de cours, amplitudes horaires — et il
fallait la reprendre à chaque rentrée. **La v2 supprime cette maintenance
annuelle** : tout vient de l'API au premier lancement, et se revalide seul.

Second objectif, la **fraîcheur**. L'intérêt de l'app face aux flux iCal des
enseignants est d'afficher un emploi du temps à jour à la seconde : le cache ne
sert jamais à éviter une requête, seulement à ne jamais montrer d'écran vide.

## Organisation

| | |
|---|---|
| `FlopEDTKit/` | Toute la logique hors interface : modèles, calendrier ISO, réseau, cache, calcul des salles libres. Se compile et se teste en ligne de commande. |
| `flopEDT/` | L'app SwiftUI. Architecture MV avec `@Observable`, un seul `AppModel` en Environment. |
| `API-FLOPEDT.md` | L'API telle qu'elle se comporte réellement, vérifiée sur la production. À lire avant toute supposition. |
| `typecheck-app.sh` | Typecheck du target app sans Xcode. |

Cible iOS 18, Swift 6, iPhone et iPad.

## Vérifier

```bash
cd FlopEDTKit && swift test
```

```bash
./typecheck-app.sh
```

152 tests hors ligne en trois secondes, sur des réponses réellement capturées
sur la production. Le script typecheck les fichiers de l'app contre le SDK
macOS — ce n'est pas un build iOS, mais il attrape toute erreur de type, de nom
ou d'isolation d'acteur sans ouvrir Xcode.

Contre le vrai serveur, avant une livraison :

```bash
cd FlopEDTKit && FLOP_LIVE_TESTS=1 swift test --filter LiveAPITests
```

Et le balayage complet de la fenêtre de rentrée, qui vérifie qu'aucune semaine
n'est illisible :

```bash
cd FlopEDTKit && FLOP_LIVE_TESTS=1 FLOP_LIVE_SWEEP=1 swift test --filter LiveAPITests
```

Les détails sont dans [`FlopEDTKit/README.md`](FlopEDTKit/README.md).

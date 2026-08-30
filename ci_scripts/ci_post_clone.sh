#!/bin/sh
#
# Exécuté par Xcode Cloud juste après le clone du dépôt.
#
# Xcode Cloud numérote ses constructions à partir de 1, alors qu'App Store
# Connect exige, pour une même version marketing, un numéro strictement
# supérieur au dernier téléversé. Les builds 67 et 68 de la 26.09 étant déjà
# consommés, un build « 1 » serait refusé quoi que vaille la signature.
#
# On décale donc le compteur d'Xcode Cloud au-dessus d'un palier. À relever si
# un numéro plus haut venait à être téléversé à la main.
#
set -e

PALIER=100
NUMERO=$((PALIER + ${CI_BUILD_NUMBER:-0}))
PROJET="$CI_PRIMARY_REPOSITORY_PATH/flopEDT/flopEDT.xcodeproj/project.pbxproj"

if [ ! -f "$PROJET" ]; then
    echo "Projet introuvable : $PROJET" >&2
    exit 1
fi

sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $NUMERO;/g" "$PROJET"

echo "Numéro de build : $NUMERO (palier $PALIER + construction Xcode Cloud ${CI_BUILD_NUMBER:-0})"
grep -m2 "CURRENT_PROJECT_VERSION" "$PROJET"

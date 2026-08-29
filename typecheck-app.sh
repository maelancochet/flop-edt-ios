#!/bin/zsh
#
# Typecheck du target app sans Xcode ni SDK iOS.
#
# Le paquet FlopEDTKit se teste en ligne de commande, mais les 13 fichiers de
# l'app SwiftUI n'étaient jusqu'ici vérifiables qu'en compilant dans Xcode.
# Or le SDK macOS des Command Line Tools embarque SwiftUI : à quatre
# modificateurs iOS-only près, neutralisés ci-dessous, l'app se typecheck contre
# lui.
#
# Ce n'est pas une compilation iOS et cela ne remplace pas un build : les
# branches `#available(iOS 26)`, le rendu et le comportement à l'exécution
# échappent à ce contrôle. Mais toute erreur de type, d'étiquette, de nom ou
# d'isolation d'acteur est attrapée en trois secondes, ce qui couvre l'essentiel
# de ce qu'on casse en éditant.
#
#   ./typecheck-app.sh
#
set -e
ROOT=${0:a:h}
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk

WORK=$(mktemp -d); trap "rm -rf $WORK" EXIT
mkdir -p $WORK/src

# Les modificateurs qui n'existent pas sur macOS, remplacés par des équivalents
# sans effet — ils ne portent aucune logique.
for f in $(find $ROOT/flopEDT/flopEDT -name '*.swift'); do
  sed \
    -e 's/\.navigationBarTitleDisplayMode(/.shimBarTitle(/g' \
    -e 's/placement: \.topBarTrailing/placement: .primaryAction/g' \
    -e 's/\.toolbarTitleDisplayMode([^)]*)/.shimNoop()/g' \
    -e 's/\.tabViewStyle(\.page([^)]*))/.shimNoop()/g' \
    "$f" > "$WORK/src/$(basename $f)"
done

cat > $WORK/src/_Shim.swift <<'EOF'
import SwiftUI
import AppKit

enum ShimBarTitle { case inline, large, automatic }

extension View {
    func shimBarTitle(_ mode: ShimBarTitle) -> some View { self }
    func shimNoop() -> some View { self }
}

extension NSColor { static var systemBackground: NSColor { .windowBackgroundColor } }
EOF

cd $ROOT/FlopEDTKit && swift build --target FlopEDTKit >/dev/null

out=$(xcrun swiftc -typecheck -swift-version 6 \
  -target arm64-apple-macos14.0 \
  -sdk $SDK \
  -I $ROOT/FlopEDTKit/.build/debug/Modules \
  $WORK/src/*.swift 2>&1) && rc=0 || rc=$?

if [[ -n "$out" ]]; then
  echo "$out" | sed "s|$WORK/src/|flopEDT/flopEDT/|"
fi
if [[ $rc -eq 0 ]]; then
  echo "app : typecheck OK"
fi
exit $rc

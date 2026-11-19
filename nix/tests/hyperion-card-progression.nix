# The NixOS Hyperion installer must actually ship the complete card and
# profile progression port, not merely carry its source as an unused patch.
{ pkgs, desktopData }:

pkgs.runCommand "ryoku-hyperion-card-progression-check" {
  nativeBuildInputs = [ pkgs.nodejs ];
} ''
  set -euo pipefail

  hub="${desktopData}/share/ryoku/config/quickshell/hub"

  test -s "$hub/registry/rarity.js"
  test -s "$hub/registry/progression.js"
  test -s "$hub/components/about/TradingCard.qml"
  test -s "$hub/components/about/ArchiveSeal.qml"
  test -s "$hub/components/about/StickerArtwork.qml"
  test -s "$hub/pages/Achievements.qml"
  test -s "$hub/pages/PointsShop.qml"
  test -s "$hub/assets/stickers/origins.svg"

  grep -Fq 'id: "master"' "$hub/registry/rarity.js"
  grep -Fq 'id: "secret-totality"' "$hub/registry/progression.js"
  grep -Fq 'id: achievementsPlaque' "$hub/components/Home.qml"
  grep -Fq 'id: shopPlaque' "$hub/components/Home.qml"

  node --test "$hub"/registry/*.test.mjs

  touch "$out"
''

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
  test -s "$hub/components/about/AchievementCard.qml"
  test -s "$hub/components/about/AchievementReveal.qml"
  test -s "$hub/components/about/BlackPrism.qml"
  test -s "$hub/registry/profile-ui.test.mjs"
  test -s "$hub/assets/badges/ryoku-voyager.svg"
  test "$(find "$hub/assets/badges" -maxdepth 1 -name '*.svg' | wc -l)" -eq 72
  grep -Fq 'Flat Hellenic achievement insignia' "$hub/assets/badges/ryoku-first-steps.svg"
  grep -Fq 'Flat Hellenic achievement insignia' "$hub/assets/badges/secret-absolute.svg"
  if grep -Elq '<(linearGradient|radialGradient|filter|image|script)' "$hub"/assets/badges/*.svg; then
    echo "Hyperion badges must stay flat and self-contained" >&2
    exit 1
  fi
  ! grep -Fq 'id: glint' "$hub/components/about/ArchiveSeal.qml"
  test -s "$hub/assets/scenes/bg-graphite.svg"
  test -s "$hub/assets/rewards/black-prism.gif"
  test -s "$hub/registry/progression.presentation.test.mjs"
  test -s "$hub/components/about/StickerArtwork.qml"
  test -s "$hub/pages/Achievements.qml"
  test -s "$hub/pages/PointsShop.qml"
  test -s "$hub/assets/ryodecors/aurelius.png"
  test -s "$hub/assets/ryodecors/rashin-hero.png"
  test -s "$hub/art/maintainers/aethctl.png"
  test -s "$hub/pages/KeepsakePage.qml"
  test -s "$hub/KeepsakeSequence.js"
  test -s "$hub/registry/progression.rebalance.test.mjs"
  test ! -e "$hub/assets/stickers/origins.svg"

  grep -Fq 'id: "master"' "$hub/registry/rarity.js"
  grep -Fq 'id: "bg-black-prism"' "$hub/registry/progression.js"
  grep -Fq 'completionSceneUnlocked' "$hub/registry/progression.js"
  grep -Fq 'id: "secret-absolute"' "$hub/registry/progression.js"
  grep -Fq 'id: "master-hyperion"' "$hub/registry/progression.js"
  grep -Fq 'version: 4' "$hub/registry/progression.js"
  grep -Fq 'id: achievementsPlaque' "$hub/components/Home.qml"
  grep -Fq 'id: shopPlaque' "$hub/components/Home.qml"

  node --test "$hub"/registry/*.test.mjs "$hub"/KeepsakeSequence.test.mjs

  touch "$out"
''

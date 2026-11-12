final: prev: {
  quickshell = prev.quickshell.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      (prev.fetchurl {
        url = "https://github.com/quickshell-mirror/quickshell/commit/851ab0eac6bdfa9201a1a50e7bc3a6d29af25949.patch";
        hash = "sha256-g+8NQeFyGK9v76cPM9ogkMSfLH0SGPOyREFkTf6MJ7I=";
      })
    ];
  });
}

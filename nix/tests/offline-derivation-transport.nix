# These recipes have intentionally absent outputs. A dependent recipe also
# proves export/import orders references without realizing any output.
{ pkgs }:
let
  baseExpression = ''derivation {
    name = "offline-unbuilt-output";
    system = "${pkgs.stdenv.hostPlatform.system}";
    builder = "/intentionally-missing-offline-test-builder";
  }'';
  fixture = builtins.derivation {
    name = "offline-unbuilt-output";
    system = pkgs.stdenv.hostPlatform.system;
    builder = "/intentionally-missing-offline-test-builder";
  };
  dependent = builtins.derivation {
    name = "offline-dependent-recipe";
    system = pkgs.stdenv.hostPlatform.system;
    builder = "/intentionally-missing-offline-test-builder";
    recipe = builtins.unsafeDiscardOutputDependency fixture.drvPath;
  };
  expression = ''let base = ${baseExpression}; in derivation {
    name = "offline-dependent-recipe";
    system = "${pkgs.stdenv.hostPlatform.system}";
    builder = "/intentionally-missing-offline-test-builder";
    recipe = builtins.unsafeDiscardOutputDependency base.drvPath;
  }'';
  archive = pkgs.runCommand "offline-test-recipes.export.gz" {
    nativeBuildInputs = [ pkgs.nix pkgs.gzip ];
  } ''
    export NIX_CONFIG='build-users-group ='
    sourceStore="$TMPDIR/source"
    drv=$(nix-instantiate --store "$sourceStore" --expr '${expression}')
    test "$drv" = '${builtins.unsafeDiscardOutputDependency dependent.drvPath}'
    # Deliberately supply the dependent first: export must order its references.
    nix-store --store "$sourceStore" --export "$drv" \
      '${builtins.unsafeDiscardOutputDependency fixture.drvPath}' | gzip -n > "$out"
  '';
  graph = pkgs.closureInfo { rootPaths = [ archive ]; };
in
pkgs.runCommand "offline-derivation-transport-check" {
  nativeBuildInputs = [ pkgs.nix pkgs.gzip pkgs.gnugrep pkgs.diffutils ];
} ''
  export NIX_CONFIG='build-users-group ='
  targetStore="$TMPDIR/target"
  gzip -dc ${archive} | nix-store --store "$targetStore" --import > imported
  grep -Fx '${builtins.unsafeDiscardOutputDependency fixture.drvPath}' imported
  grep -Fx '${builtins.unsafeDiscardOutputDependency dependent.drvPath}' imported
  cmp '${builtins.unsafeDiscardOutputDependency fixture.drvPath}' "$targetStore${builtins.unsafeDiscardStringContext fixture.drvPath}"
  cmp '${builtins.unsafeDiscardOutputDependency dependent.drvPath}' "$targetStore${builtins.unsafeDiscardStringContext dependent.drvPath}"
  if nix-store --store "$targetStore" --check-validity '${builtins.unsafeDiscardStringContext fixture.outPath}' 2>/dev/null; then
    echo 'The test output must remain unbuilt' >&2
    exit 1
  fi
  grep -Fx '${archive}' ${graph}/store-paths
  if grep -q '\.drv$' ${graph}/store-paths; then
    echo 'Recipe paths leaked into the ISO closure graph' >&2
    exit 1
  fi
  touch "$out"
''

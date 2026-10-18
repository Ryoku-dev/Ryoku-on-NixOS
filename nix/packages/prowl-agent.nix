{ pkgs }:

pkgs.buildGoModule {
  pname = "prowl-agent";
  version = "0.17.2";

  src =
    pkgs.fetchFromGitHub {
      owner = "neur0map";
      repo = "prowl-agent";
      rev = "5ba05eb922ff023e3cbc2b9a3768829179bca980";
      hash = "sha256-OslMKhH48f0XcfUlZ5DaDWyRmLb+fWM/qnU0p9C+Zyo=";
    };

  vendorHash = "sha256-EB+usU80HUIdhzg1MXAj/2uE/bOKqWVyX4A9Xk9NVUs=";

  # sqlite-vec includes <sqlite3.h> during CGO compilation.
  #
  # Prowl's go-sqlite3 dependency still builds its own bundled SQLite
  # amalgamation, so this is header availability only — we deliberately
  # do not link Prowl against Nixpkgs' libsqlite3.
  buildInputs = [
    pkgs.sqlite
  ];

  # Prowl uses SQLite FTS5 through CGO. buildGoModule enables
  # CGO by default on this platform; do not duplicate CGO_ENABLED
  # as a top-level derivation attribute.
  tags = [
    "sqlite_fts5"
  ];

  subPackages = [
    "cmd/prowl-agent"
  ];

  # Immutable Nix builds must never self-update into the store.
  ldflags = [
    "-s"
    "-w"
    "-X main.version=v0.15.6"
    "-X main.managedBy=nix"
  ];

  meta = {
    description =
      "Local code-intelligence indexer and MCP server used by Ryoku Rashin";

    homepage =
      "https://github.com/neur0map/prowl-agent";

    mainProgram =
      "prowl-agent";

    platforms =
      pkgs.lib.platforms.linux;
  };
}

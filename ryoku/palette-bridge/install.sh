#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v ryoku-host >/dev/null || {
  printf 'ryoku-host is required to manage the palette bridge service\n' >&2
  exit 1
}

migrate_legacy_services() {
  local legacy_unit
  ryoku-host svc --user daemon-reload
  for legacy_unit in ryoku-spicetify-palette.service spiceflow.service; do
    if ryoku-host svc --user is-enabled "$legacy_unit" >/dev/null 2>&1; then
      ryoku-host svc --user disable --now "$legacy_unit"
      printf 'Disabled legacy %s (its unit file was preserved)\n' "$legacy_unit"
    fi
  done
}

if [[ "$project_root" == /usr/share/ryoku/palette-bridge &&
      -x /usr/bin/ryoku-palette-bridge ]]; then
  migrate_legacy_services
  printf 'The packaged ryoku-palette-bridge.service is ready to enable.\n'
  exit 0
fi

command -v go >/dev/null || {
  printf 'Go is required only for a checkout install; install the ryoku-palette-bridge package on a release system.\n' >&2
  exit 1
}

bin_dir="$HOME/.local/bin"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
install -d "$bin_dir" "$unit_dir"
(cd "$project_root" && go build -trimpath -ldflags='-s -w' -o "$bin_dir/ryoku-palette-bridge" .)
install -m 0755 "$project_root/doctor.sh" "$bin_dir/ryoku-palette-bridge-doctor"
install -m 0755 "$project_root/remove-integrations.sh" "$bin_dir/ryoku-palette-bridge-remove-integrations"
install -Dm0644 "$project_root/vesktop/quickcss.sh" \
  "$bin_dir/../share/ryoku/palette-bridge/vesktop/quickcss.sh"
sed "s|^ExecStart=.*|ExecStart=$bin_dir/ryoku-palette-bridge|" \
  "$project_root/packaging/systemd/ryoku-palette-bridge.service" > "$unit_dir/ryoku-palette-bridge.service"
migrate_legacy_services
printf 'Installed ryoku-palette-bridge.service (enable it when ready).\n'

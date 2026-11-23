# Executed by the build-iso-offline flake app, on the connected build machine.
output_link="$PWD/result-offline"
if [[ ${1:-} == --help ]]; then
  echo 'Usage: nix run path:.#build-iso-offline -- [--out-link PATH] [--no-nvidia] [--payload-flake REF] [--resume DIR]'
  echo 'Downloads/builds the installation payload, then assembles a standalone ISO.'
  echo 'Minimal profile: latest kernel, niri, Firefox, ext4 by default, no optional apps. Use --nvidia to include its driver.'
  echo '--payload-flake REF reuses a previously prepared desktop source snapshot.'
  echo '--resume DIR retries image assembly using retained preparation files.'
  exit 0
fi
include_nvidia=0
profile=niri-latest-firefox-minimal-v2
payload_flake=$RYOKU_OFFLINE_FLAKE
resume_work=''
while [[ $# -gt 0 ]]; do
  case $1 in
    --out-link) output_link=${2:?--out-link requires a path}; shift 2 ;;
    --nvidia) include_nvidia=1; shift ;;
    --no-nvidia) include_nvidia=0; shift ;;
    --payload-flake) payload_flake=${2:?--payload-flake requires a reference}; shift 2 ;;
    --resume) resume_work=${2:?--resume requires a directory}; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
if [[ -n $resume_work ]]; then
  work=$(realpath -e "$resume_work")
  [[ -f $work/.ryoku-offline-preparation ]] || { echo "Not a build-iso-offline preparation directory: $work" >&2; exit 1; }
  [[ $(cat "$work/profile" 2>/dev/null) == "$profile" ]] || { echo "This preparation is not the minimal offline profile; start a fresh build." >&2; exit 1; }
  for name in store-paths.json sources.json derivations-path payload-source; do
    [[ -s $work/$name ]] || { echo "Incomplete preparation: $work/$name" >&2; exit 1; }
  done
  payload_flake="path:$(cat "$work/payload-source")"
else
  work=$(mktemp -d)
  touch "$work/.ryoku-offline-preparation"
  printf '%s\n' "$profile" > "$work/profile"
fi
cleanup() {
  local status=$?
  if [[ $status -eq 0 ]]; then
    rm -rf "$work"
  else
    printf '\nPreparation retained at %s (including payload GC roots).\n' "$work" >&2
    printf 'To reuse this desktop snapshot, retry with --payload-flake %s\n' "$payload_flake" >&2
    if [[ -s $work/store-paths.json && -s $work/derivations-path ]]; then
      printf 'To retry only image assembly, use --resume %s\n' "$work" >&2
    fi
  fi
}
trap cleanup EXIT
if [[ -z $resume_work ]]; then
# This is deliberately an online preparation phase. Archive every locked input,
# including transitive flakes and non-flake sources, before assembling the ISO.
[[ $(nix eval --raw "$payload_flake#lib.offlineProfile") == "$profile" ]] || { echo "Payload source does not provide the minimal offline profile." >&2; exit 1; }
printf 'Archiving locked input sources...\n'
nix flake archive --json "$payload_flake" > "$work/archive.json"
printf 'Preparing the generic payload (cached outputs are reused)...\n'
nix build --out-link "$work/payload" --json "$payload_flake#ryoku-offline-payload" > "$work/build.json"
if [[ $include_nvidia -eq 1 ]]; then
  printf 'Preparing the NVIDIA payload...\n'
  nix build --out-link "$work/nvidia-payload" --json "$payload_flake#ryoku-offline-nvidia-payload" > "$work/nvidia.json"
fi
# Record derivations, their source files, and already-realized outputs as well
# as runtime closures. No dependency is fetched while using the resulting ISO.
python3 - "$work" <<'PY'
import json
import gzip
import pathlib
import shutil
import subprocess
import sys

work = pathlib.Path(sys.argv[1])
sources = set()
def archive(node):
    sources.add(node['path'])
    for child in node.get('inputs', {}).values():
        archive(child)
archive(json.loads((work / 'archive.json').read_text()))
payload_source = json.loads((work / 'archive.json').read_text())['path']
paths = set(sources)
for filename in ('build.json', 'nvidia.json'):
    file = work / filename
    if not file.exists():
        continue
    for result in json.loads(file.read_text()):
        # Recipe references need their .drv/source files, not every available
        # build-time output (compilers, Cargo caches, development SDKs).
        for roots in ([result['drvPath']], list(result['outputs'].values())):
            closure = subprocess.check_output(
                ['nix-store', '--query', '--requisites', *roots], text=True)
            paths.update(closure.splitlines())
# exportReferencesGraph expands .drv outputs even when those outputs were never
# built (e.g. a tarball behind a substituted package). Keep recipes out of the
# ISO closure graph; transport/import them as an opaque compressed export.
derivations = sorted(path for path in paths if path.endswith('.drv'))
(work / 'derivations.txt').write_text(''.join(path + '\n' for path in derivations))
bundle = work / 'ryoku-offline-derivations.export.gz'
print(f'Packing {len(derivations)} derivations as data...', flush=True)
with (work / 'derivations.txt').open('rb') as inputs, bundle.open('wb') as raw:
    with subprocess.Popen(['nix-store', '--export', '--stdin'], stdin=inputs, stdout=subprocess.PIPE) as export:
        with gzip.GzipFile(fileobj=raw, mode='wb', mtime=0) as compressed:
            shutil.copyfileobj(export.stdout, compressed)
        if export.wait():
            raise RuntimeError('could not export offline derivations')
bundle_path = subprocess.check_output(['nix', 'store', 'add-file', str(bundle)], text=True).strip()
(work / 'derivations-path').write_text(bundle_path)
(work / 'payload-source').write_text(payload_source)
(work / 'store-paths.json').write_text(json.dumps(sorted(paths.difference(derivations))))
(work / 'sources.json').write_text(json.dumps(sorted(sources)))
PY
fi
export RYOKU_OFFLINE_STORE_PATHS="$work/store-paths.json"
export RYOKU_OFFLINE_SOURCE_PATHS="$work/sources.json"
export RYOKU_OFFLINE_DERIVATIONS
RYOKU_OFFLINE_DERIVATIONS=$(cat "$work/derivations-path")
export RYOKU_OFFLINE_PAYLOAD_SOURCE
RYOKU_OFFLINE_PAYLOAD_SOURCE=$(cat "$work/payload-source")
printf 'Assembling the offline ISO...\n'
nix build --impure --print-build-logs --print-out-paths --out-link "$output_link" --expr '
  let r = builtins.getFlake (builtins.getEnv "RYOKU_OFFLINE_FLAKE"); in
  (r.lib.mkOfflineIso {
    storePaths = builtins.fromJSON (builtins.readFile (builtins.getEnv "RYOKU_OFFLINE_STORE_PATHS"));
    sourcePaths = builtins.fromJSON (builtins.readFile (builtins.getEnv "RYOKU_OFFLINE_SOURCE_PATHS"));
    derivationsArchive = builtins.getEnv "RYOKU_OFFLINE_DERIVATIONS";
    payloadFlake = builtins.getFlake ("path:" + builtins.getEnv "RYOKU_OFFLINE_PAYLOAD_SOURCE");
  }).iso.config.system.build.isoImage'
printf '\nOffline ISO: %s/iso/\n' "$output_link"

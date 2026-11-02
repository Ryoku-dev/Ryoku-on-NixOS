import argparse
import subprocess
from pathlib import Path

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--image")
    p.add_argument("--mode")
    p.add_argument("--noswitch", action="store_true")
    p.add_argument("--skip-config-write", action="store_true")
    p.add_argument("path", nargs="?")
    a = p.parse_args()
    path = a.image or a.path
    if a.noswitch or not path:
        return
    path = str(Path(path.removeprefix("file://")).expanduser().resolve(strict=True))
    subprocess.run(["ryogami", "wallpaper", "set", path], check=True)

if __name__ == "__main__":
    main()

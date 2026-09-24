#!/usr/bin/env sh
# Скачивает Lune (читает и пишет файлы Roblox) в tools/bin/lune.
set -e
VERSION=0.10.5
DIR="$(dirname "$0")/bin"
mkdir -p "$DIR"
curl -sSL -o "$DIR/lune.zip" "https://github.com/lune-org/lune/releases/download/v$VERSION/lune-$VERSION-linux-x86_64.zip"
unzip -o -q "$DIR/lune.zip" -d "$DIR" && rm "$DIR/lune.zip" && chmod +x "$DIR/lune"
"$DIR/lune" --version

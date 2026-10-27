#!/bin/bash
# Installs Godot 4.7.2 (official Linux build) for cloud sessions. Safe to run twice.
set -euo pipefail
GODOT=Godot_v4.7.2-stable_linux.x86_64
SHA=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
if ! command -v godot >/dev/null 2>&1; then
  mkdir -p /opt/godot && cd /opt/godot
  curl -fsSL -o godot.zip "https://sourceforge.net/projects/godot-engine.mirror/files/4.7.2-stable/$GODOT.zip/download"
  echo "$SHA  godot.zip" | sha512sum -c -
  python3 -c "import zipfile; zipfile.ZipFile('godot.zip').extractall('.')"
  chmod +x "$GODOT" && ln -sf "/opt/godot/$GODOT" /usr/local/bin/godot
fi
godot --version

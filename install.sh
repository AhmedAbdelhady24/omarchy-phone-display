#!/usr/bin/env bash
set -euo pipefail
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
target=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/user.phone-display
command -v omarchy >/dev/null || { echo 'Omarchy shell is required.' >&2; exit 1; }
omarchy plugin validate "$source_dir"
if [[ $source_dir != "$target" ]]; then
  [[ ! -e $target ]] || { echo "Already installed: $target (back it up before replacing)." >&2; exit 1; }
  mkdir -p -- "$target/i18n"
  for file in manifest.json qmldir BarWidget.qml Backend.qml Panel.qml DisplayLayout.qml SetupGuide.qml Palette.qml ActionButton.qml Choice.qml Colors.js Layout.js phone-display.sh install.sh README.md; do
    install -m 644 -- "$source_dir/$file" "$target/$file"
  done
  install -m 644 -- "$source_dir/i18n/en.json" "$target/i18n/en.json"
  chmod 755 "$target/phone-display.sh" "$target/install.sh"
fi
omarchy plugin validate "$target"
config=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json
if [[ -f $config ]]; then cp -p -- "$config" "$config.phone-display-backup-$(date +%Y%m%d-%H%M%S)"; fi
omarchy-shell shell rescanPlugins >/dev/null
omarchy plugin enable user.phone-display --section right
echo "Installed: $target"
if ! command -v wayvnc >/dev/null; then
  echo 'Install the stream dependency in a terminal: omarchy pkg add wayvnc'
fi

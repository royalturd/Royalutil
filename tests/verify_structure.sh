#!/bin/bash


SCRIPT="./royalutil.sh"

if [ ! -f "$SCRIPT" ]; then
    echo "Error: $SCRIPT not found."
    exit 1
fi

chmod +x "$SCRIPT"

echo "Checking for essential functions..."
FUNCTIONS=("maintenance" "setup_editor" "install_git" "setup_brew" "setup_zsh" "install_flatpak" "install_apps" "install_utilities" "install_themes" "append_if_missing" "check_dependencies" "check_network" "show_progress")

for func in "${FUNCTIONS[@]}"; do
    if grep -q "$func()" "$SCRIPT"; then
        echo "✅ Function $func found."
    else
        echo "❌ Function $func NOT found."
        exit 1
    fi
done

echo -e "\nTesting help message..."
if "$SCRIPT" --help | grep -q "Usage:"; then
    echo "✅ Help message works."
else
    echo "❌ Help message failed."
    exit 1
fi

echo -e "\nAll structural checks passed!"

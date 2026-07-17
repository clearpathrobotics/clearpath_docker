#!/bin/sh
# Clearpath Lichtblick Web startup script
#
# Substitutes __NS__ placeholders in layout files with the actual robot
# namespace, then copies the selected default layout into the location
# expected by the official Lichtblick entrypoint.

set -e

NAMESPACE="${ROBOT_NAMESPACE:-a300_00000}"
DEFAULT_LAYOUT="${LICHTBLICK_DEFAULT_LAYOUT:-cpr-navigation}"
PORT="${LICHTBLICK_PORT:-8080}"
LAYOUTS_DIR="/lichtblick/layouts"

echo "============================================="
echo " Clearpath Lichtblick Web"
echo "============================================="
echo ""
echo "  Web UI:       http://localhost:${PORT}"
echo "  Namespace:    ${NAMESPACE}"
echo "  Default layout: ${DEFAULT_LAYOUT}"
echo ""
echo "  Connect to your robot via foxglove_bridge:"
echo "    ws://<host>:${FOXGLOVE_BRIDGE_PORT:-8765}"
echo ""
echo "  Available layouts:"

for layout in "${LAYOUTS_DIR}"/*.json; do
    if [ -f "$layout" ]; then
        name=$(basename "$layout" .json)
        echo "    - ${name}"
    fi
done

echo ""
echo "============================================="

# Substitute namespace in all layout files
for layout in "${LAYOUTS_DIR}"/*.json; do
    if [ -f "$layout" ]; then
        sed -i "s/__NS__/${NAMESPACE}/g" "$layout"
    fi
done

# Copy the selected default layout to where the official entrypoint expects it
if [ -f "${LAYOUTS_DIR}/${DEFAULT_LAYOUT}.json" ]; then
    cp "${LAYOUTS_DIR}/${DEFAULT_LAYOUT}.json" /lichtblick/default-layout.json
    echo "Default layout set: ${DEFAULT_LAYOUT}"
else
    echo "WARNING: Layout '${DEFAULT_LAYOUT}' not found, using empty default"
    echo "{}" > /lichtblick/default-layout.json
fi

# Run the official Lichtblick entrypoint logic:
# Inject default layout into index.html
index_html=$(cat index.html)
replace_pattern='/*LICHTBLICK_SUITE_DEFAULT_LAYOUT_PLACEHOLDER*/'
replace_value=$(cat /lichtblick/default-layout.json)
echo "${index_html/"$replace_pattern"/$replace_value}" > index.html

# Execute command. If caller did not provide --listen, bind to LICHTBLICK_PORT.
if [ "$#" -gt 0 ]; then
    has_listen="false"
    for arg in "$@"; do
        if [ "$arg" = "--listen" ]; then
            has_listen="true"
            break
        fi
    done

    if [ "$has_listen" = "false" ]; then
        set -- "$@" --listen ":${PORT}"
    fi
fi

exec "$@"

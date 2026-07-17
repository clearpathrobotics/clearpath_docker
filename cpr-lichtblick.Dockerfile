# Lichtblick Web with preconfigured Clearpath layouts
#
# Extends the official Lichtblick web image with Clearpath-specific
# layouts (navigation, robot overview).
#
# The official image supports injecting a default layout by bind-mounting
# or copying a JSON file to /lichtblick/default-layout.json.
#
# Usage:
#   docker compose up lichtblick foxglove-bridge
#   Open http://localhost:8080 in your browser
#
# Environment variables:
#   ROBOT_NAMESPACE - Robot namespace for topic substitution (default: a300_00000)
#   LICHTBLICK_PORT - Port for the web server (default: 8080)
#   LICHTBLICK_DEFAULT_LAYOUT - Which layout to use as default (default: cpr-navigation)

ARG ROS_DISTRO=jazzy
ARG CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker
ARG CPR_BASE_TAG=${ROS_DISTRO}-latest

FROM ${CPR_BASE_IMAGE}:${CPR_BASE_TAG} AS cpr-common
FROM ghcr.io/lichtblick-suite/lichtblick:latest AS lichtblick-upstream

FROM cpr-common AS cpr-lichtblick

# Bring in the upstream Lichtblick runtime (Caddy + static web assets).
COPY --from=lichtblick-upstream /usr/bin/caddy /usr/bin/caddy
COPY --from=lichtblick-upstream /config /config
COPY --from=lichtblick-upstream /src /src
COPY --from=lichtblick-upstream /entrypoint.sh /entrypoint.sh

WORKDIR /src

# Copy all preconfigured layouts
COPY lichtblick_layouts/*.json /lichtblick/layouts/

# Copy launch script that processes namespace substitution and sets default layout
COPY cpr-lichtblick-launch.sh /cpr-lichtblick-launch.sh

ENTRYPOINT ["/bin/bash", "/cpr-lichtblick-launch.sh"]
CMD ["caddy", "file-server"]

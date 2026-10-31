#!/usr/bin/env bash
# Development utilities and aliases for Clearpath containers.
# Source this file in your .bashrc or manually:
#   source /usr/local/bin/cpr-dev.sh

# Common development aliases for ROS 2 workspace
alias cb='colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=RelWithDebInfo'
alias cba='colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=RelWithDebInfo --packages-select'
alias cbu='colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=RelWithDebInfo --packages-up-to'
alias ct='colcon test'
alias ctr='colcon test-result --verbose'
alias cs='source install/setup.bash'

# Source workspace overlay if it exists
if [ -f /colcon_ws/install/setup.bash ]; then
    source /colcon_ws/install/setup.bash
fi

# Helpful development functions

# cclean - Clean colcon build artifacts
cclean() {
    local dirs=("build" "install" "log")
    for dir in "${dirs[@]}"; do
        if [ -d "${dir}" ]; then
            echo "Removing ${dir}/..."
            rm -rf "${dir}"
        fi
    done
    echo "Colcon workspace cleaned."
}

# cbp <package> - Build a specific package with verbose output
cbp() {
    if [ -z "$1" ]; then
        echo "Usage: cbp <package_name>"
        return 1
    fi
    colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=RelWithDebInfo --packages-select "$1" --event-handlers console_direct+
}

# Show helpful development commands
alias cpr-dev-help='cat <<EOF
Clearpath Development Aliases:
  cb              - Build workspace (symlink-install, RelWithDebInfo)
  cba <pkg>       - Build a specific package
  cbu <pkg>       - Build package and its dependencies
  cbp <pkg>       - Build package with verbose output
  ct              - Run tests
  ctr             - Show test results (verbose)
  cs              - Source the workspace overlay
  cclean          - Remove build/install/log directories
  cpr-dev-help    - Show this help message

Environment:
  ROS_DISTRO: ${ROS_DISTRO:-not set}
  RMW_IMPLEMENTATION: ${RMW_IMPLEMENTATION:-not set (using default)}
  WORKSPACE: /colcon_ws (default overlay workspace)
EOF'

echo "[cpr-dev] Development aliases loaded. Type 'cpr-dev-help' for usage."

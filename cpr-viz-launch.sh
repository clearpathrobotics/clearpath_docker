#!/usr/bin/env bash
set -euo pipefail

setup_path="${SETUP_PATH:-$HOME/setup/path/}"

# Extract namespace from robot.yaml
# The namespace is typically stored as platform.id in the format "a200_0000" or "a300_0000"
extract_namespace() {
  local yaml_file="$1"
  if [[ ! -f "$yaml_file" ]]; then
    echo "Error: robot.yaml not found at $yaml_file" >&2
    return 1
  fi
  
  # Use Python to safely parse YAML and extract namespace
  python3 -c "
import sys, yaml
try:
  with open('$yaml_file', 'r') as f:
    config = yaml.safe_load(f)
  if isinstance(config, dict):
    namespace = (config.get('platform', {}).get('id') or 
                config.get('system', {}).get('ros2', {}).get('namespace') or 
                config.get('id') or 
                config.get('namespace'))
    if namespace:
      print(namespace)
    else:
      sys.exit(1)
except Exception as e:
  print(f'Error parsing robot.yaml: {e}', file=sys.stderr)
  sys.exit(1)
"
}

# Extract namespace from robot.yaml
namespace=$(extract_namespace "$setup_path/robot.yaml" || echo "a300_00000")
use_sim_time="${USE_SIM_TIME:-true}"

wait_for_topic() {
  local topic="$1"
  local timeout_sec="${2:-30}"
  local waited=0

  while (( waited < timeout_sec )); do
    if ros2 topic list 2>/dev/null | grep -q "^${topic}$"; then
      return 0
    fi
    sleep 1
    ((waited+=1))
  done

  return 1
}

tf_topic="/${namespace}/tf"
description_topic="/${namespace}/robot_description"

echo "Waiting for simulation topics before starting RViz..."
wait_for_topic "$description_topic" 45 || echo "Warning: ${description_topic} not found yet" >&2
wait_for_topic "$tf_topic" 45 || echo "Warning: ${tf_topic} not found yet" >&2

echo "Launching clearpath visualization with namespace: $namespace"
exec ros2 launch clearpath_viz view_robot.launch.py "namespace:=${namespace}" "use_sim_time:=${use_sim_time}" "$@"

# clearpath_docker

Docker images for Clearpath Robotics ROS 2 development and CI, published to
GitHub Container Registry (GHCR) at
[`ghcr.io/clearpathrobotics/clearpath_docker`](https://github.com/clearpathrobotics/clearpath_docker/pkgs/container/clearpath_docker).

## Images

Two image variants are built for each supported ROS 2 distro, plus Humble- and
Jazzy-only common, robot, and sim variants. The dev and CI images are both
built `FROM` the base image; the common and robot images are built `FROM` the
CI image; the sim image is built `FROM` the dev image.

### Base — [cpr-base.Dockerfile](cpr-base.Dockerfile)

Headless server-side image — no GUI tooling. `ros:<distro>-ros-base`
extended with the Clearpath public rosdistro index and the Clearpath apt
source (when available for the Ubuntu codename). Slim, no extra tooling,
no non-root user — suitable as a runtime base for robots and as the parent
for the dev and CI images.

### Dev — [cpr-dev.Dockerfile](cpr-dev.Dockerfile)

Headless server-side dev/build environment — no GUI tooling (no `rviz2`,
`rqt`, X11 libs). Built on the base image. Adds `ros-build-essential`,
common Python tooling (`pip`, `pep8`, `autopep8`, `pylint`), editors
(`nano`, `vim`), `bash-completion`, and a non-root `robot` user (uid/gid
1000) with passwordless `sudo`. Bash history is redirected to
`/commandhistory` so it can be persisted via a volume.

### CI — [cpr-ci.Dockerfile](cpr-ci.Dockerfile)

Built on the base image. Adds the toolchain needed to build and test ROS 2
packages: `ros-dev-tools`, `colcon` mixins/metadata, `flake8` plugins,
`pytest` helpers, lcov, and the RTI Connext DDS package matching the distro.

### CI Common — [cpr-ci-common.Dockerfile](cpr-ci-common.Dockerfile)

Built on the CI image. Pre-installs the released
`ros-<distro>-clearpath-common` package so all of its build, test, and
runtime dependencies are baked into the image. This is a CI accelerator:
workflows that check out and build `clearpath_common` from source on top of
this image find every dependency already present, so the in-CI `rosdep
install` is a near no-op and the build only needs to compile. The
from-source overlay workspace shadows the pre-installed binary at runtime.
This variant is only built for `humble` and `jazzy`.

### CI Robot — [cpr-ci-robot.Dockerfile](cpr-ci-robot.Dockerfile)

Built on the CI image. Installs the released `ros-<distro>-clearpath-robot`
package so CI jobs targeting robot stacks can start from an image with the
robot metapackage and its dependencies already present. This variant is only
built for `humble` and `jazzy`.

### Sim — [cpr-sim.Dockerfile](cpr-sim.Dockerfile)

Built on the dev image. Installs the released
`ros-<distro>-clearpath-gz` package, switches the default runtime user to
`robot`, and launches:

```sh
ros2 launch clearpath_gz simulation.launch.py setup_path:=$HOME/setup/path/
```

The launcher defaults `setup_path` to `$HOME/setup/path/`, and you can
override it by passing `SETUP_PATH=/some/other/path/` into the container.
This variant is only built for `humble` and `jazzy`.

### Nav2 Demos — [cpr-nav2.Dockerfile](cpr-nav2.Dockerfile)

Built on the dev image. Installs `ros-<distro>-clearpath-nav2-demos` and
`ros-<distro>-clearpath-common` (which provides CycloneDDS, Fast DDS, and
Zenoh RMW implementations).

Reads the robot namespace from `robot.yaml` in the setup path (same file used
by the sim and viz containers) and launches Nav2 with platform-specific
configuration from `clearpath_nav2_demos`:

```sh
ros2 launch clearpath_nav2_demos nav2.launch.py \
  use_sim_time:=true \
  setup_path:=/etc/clearpath
```

The setup path must contain a `robot.yaml` that declares the platform serial
number — e.g. `j100-0000`, `a200-0000`. The namespace (`j100_0000`,
`a200_0000`) is derived automatically from `platform.id` in that file.

See [Compose environment variables](#compose-environment-variables) for all available variables.

The `AUTO_NAV2_STARTUP` bootstrap calls the lifecycle manager startup service,
then issues a pause/resume cycle to converge any nodes that lost the startup
race, then individually nudges any remaining inactive nodes — removing the need
to manually call the service from outside the container.

**Usage — standalone against a running sim:**

```sh
docker compose -f compose-sim-viz-nav2.yaml up
```

`SETUP_PATH_HOST` defaults to `$HOME/clearpath/`. Override if your
`robot.yaml` lives elsewhere:

```sh
SETUP_PATH_HOST=$HOME/my_robot docker compose -f compose-sim-viz-nav2.yaml up
```

### Viz — [cpr-viz.Dockerfile](cpr-viz.Dockerfile)

Built on the dev image. Installs `ros-<distro>-clearpath-viz`, reads the
namespace from `robot.yaml` in the setup path, and launches:

```sh
ros2 launch clearpath_viz view_robot.launch.py namespace:=<namespace>
```

The launcher automatically extracts the namespace from `robot.yaml` (e.g.,
`a300_00000`, `a200_0000`). Runs on the same host network as sim, so RViz can
visualize robot state from the simulation.

**Usage — Viz alone:**

```sh
xhost +local:
ROS_DISTRO=jazzy docker compose up viz
```

**Usage — Sim + Viz together:**

```sh
xhost +local:
ROS_DISTRO=jazzy docker compose -f compose-sim-viz.yaml up
```

**Usage — Sim + Nav2 + Viz together:**

```sh
xhost +local:
ROS_DISTRO=jazzy docker compose -f compose-sim-viz-nav2.yaml up
```

**Usage — Sim + Nav2 + Viz with NVIDIA GPU (Optimus/discrete GPU):**

```sh
xhost +local:
ROS_DISTRO=jazzy docker compose -f compose-sim-viz-nav2.yaml -f compose.nvidia.yaml up
```

For prerequisites and full details, see the [NVIDIA GPU overlay](#nvidia-gpu-overlay----composenvidiayaml) section.

The dedicated `compose-sim-viz-nav2.yaml` stack defaults `NAV2_LAUNCH_FILE` to
`nav2.launch.py` and sets `NAV2_ENABLE_SLAM=true`, so both Nav2 and SLAM start
automatically without manual steps. It also enables
`AUTO_NAV2_STARTUP=true`, which auto-runs a lifecycle pause/resume bootstrap
to converge Nav2 nodes into an active state.

In the RViz window, use the RobotModel and TF displays to inspect the simulated
robot. Both containers share the host network and ROS domain, so ROS 2 topics
and services flow between them automatically.

This variant is only built for `humble` and `jazzy`.

### Foxglove Bridge — [cpr-foxglove-bridge.Dockerfile](cpr-foxglove-bridge.Dockerfile)

Built on the base image. Headless container that runs a
[foxglove_bridge](https://docs.foxglove.dev/docs/connecting-to-data/ros-foxglove-bridge)
node, allowing [Lichtblick](https://github.com/Lichtblick-Suite/lichtblick)
(or Foxglove) to visualize ROS 2 topics without X11 or GPU access.

No display server is required — Lichtblick runs on your local machine and
connects to the container over WebSocket.

> **Note:** This container is intended for use with simulation or off-robot
> development. On a physical robot, foxglove_bridge is launched automatically
> when enabled via
> [`platform.enable_foxglove_bridge`](https://docs.clearpathrobotics.com/docs/ros/config/yaml/platform/foxglove_bridge)
> in `robot.yaml`.

**Usage — with simulation:**

```sh
docker compose up sim foxglove-bridge
```

Then open Lichtblick → **Open connection** → **Foxglove WebSocket** →
`ws://localhost:8765`.

See [Compose environment variables](#compose-environment-variables) for all available variables.

### Robot — [cpr-robot.Dockerfile](cpr-robot.Dockerfile) / [cpr-robot-humble.Dockerfile](cpr-robot-humble.Dockerfile)

Locally-built image that runs the full Clearpath robot stack on real hardware.
Uses `systemd` as PID 1 to manage the clearpath platform, sensor, and
manipulator services. Requires a `robot.yaml` mounted at `/etc/clearpath/`.

Two Dockerfiles are provided:

| Dockerfile | Distro | Default user | Published tag |
| --- | --- | --- | --- |
| `cpr-robot.Dockerfile` | Jazzy+ | `robot` | `jazzy-robot-latest` |
| `cpr-robot-humble.Dockerfile` | Humble | `administrator` | `humble-robot-latest` |

The active Dockerfile is controlled by the `ROBOT_DOCKERFILE` compose variable
(see [Compose environment variables](#compose-environment-variables) below).

**Pull and run — Jazzy (default):**

```sh
SETUP_PATH_HOST=$HOME/clearpath docker compose up -d robot
```

**Pull and run — Humble:**

```sh
ROBOT_DOCKERFILE=cpr-robot-humble.Dockerfile \
  ROS_DISTRO=humble \
  RMW_IMPLEMENTATION=rmw_fastrtps_cpp \
  SETUP_PATH_HOST=$HOME/clearpath \
  docker compose up -d robot
```

**Exec into the container:**

```sh
# Jazzy
docker compose exec --user robot robot bash

# Humble
docker compose exec --user administrator robot bash
```

Or directly by container name (without Compose):

```sh
# Jazzy
docker exec -it --user robot cpr-robot-jazzy bash

# Humble
docker exec -it --user administrator cpr-robot-humble bash
```

**Running ROS 2 CLI commands:**

Once inside the container, source the generated setup file before using any
`ros2` commands. This file is produced by `clearpath_robot install` and sources
the correct ROS distro overlay together with any workspace extensions:

```sh
source /etc/clearpath/setup.bash
```

You can then use any ROS 2 CLI tool. The robot namespace (e.g. `a300_00000`)
comes from `platform.id` in your `robot.yaml`:

```sh
# List all active nodes
ros2 node list

# List all topics
ros2 topic list

# Echo odometry (replace <namespace> with your robot's namespace, e.g. a300_00000)
ros2 topic echo /<namespace>/platform/odom/filtered

Source `/etc/clearpath/setup.bash` in every new shell; the container's default
`~/.bashrc` does **not** source it automatically.

> **Note (Humble only):** The MCU firmware requires FastDDS — set `RMW_IMPLEMENTATION=rmw_fastrtps_cpp` when running on Humble. CycloneDDS will not communicate with the robot hardware.

### NVIDIA GPU overlay — [compose.nvidia.yaml](compose.nvidia.yaml)

An optional compose overlay that enables NVIDIA GPU rendering for the `sim`
(Gazebo) and `viz` (RViz2) services. Uses the `nvidia` container runtime with
PRIME render offload for Optimus (Intel + discrete NVIDIA) laptops.

**Prerequisites:**

Install the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html):

```sh
sudo apt install nvidia-container-toolkit
sudo systemctl restart docker
```

**Usage** (layer on top of any sim-containing compose file):

```sh
xhost +local:

# Sim + Viz
SETUP_PATH_HOST=$HOME/clearpath ROS_DISTRO=jazzy docker compose -f compose-sim-viz.yaml -f compose.nvidia.yaml up

# Sim + Nav2 + Viz
SETUP_PATH_HOST=$HOME/clearpath ROS_DISTRO=jazzy docker compose -f compose-sim-viz-nav2.yaml -f compose.nvidia.yaml up
```

### Supported ROS 2 distros

`humble`, `jazzy`, `lyrical`, `rolling`.

## Utility Scripts

The images include utility scripts installed to `/usr/local/bin/`:

### cpr-common.sh

Common utilities and functions shared by Clearpath launch scripts. Includes:
- `detect_namespace` - Auto-detect robot namespace from `robot.yaml`
- `wait_for_sim_if_enabled` - Block until simulation is ready
- `wait_for_service` / `wait_for_topic` - Wait for ROS 2 resources
- `activate_node_direct` - Lifecycle node management
- `log_robot_yaml` - Debug robot configuration

Source this in scripts with:
```bash
source /usr/local/bin/cpr-common.sh
```

### cpr-dev.sh

Development aliases and utilities automatically sourced in the `sim`, `nav2`, and `viz` images. Provides:

**Build aliases:**
- `cb` - Build workspace with symlink-install (RelWithDebInfo)
- `cba <pkg>` - Build specific package
- `cbu <pkg>` - Build package and dependencies
- `cbp <pkg>` - Build package with verbose output
- `ct` - Run tests
- `ctr` - Show test results (verbose)
- `cs` - Source workspace overlay

**Helper functions:**
- `cclean` - Remove build/install/log directories
- `cpr-dev-help` - Show all available commands

The script automatically sources `/colcon_ws/install/setup.bash` if it exists, making it ideal for devcontainer and volume-mounted workspace scenarios.

## Tags

Tags are produced by the GitHub Actions workflow and follow this scheme:

| Variant | Tag pattern |
| --- | --- |
| Base | `<distro>-latest`, `<distro>-<branch>`, `<distro>-pr-<n>`, `<distro>-<semver>`, `<distro>-nightly` |
| Dev  | `<distro>-dev-latest`, `<distro>-dev-<branch>`, `<distro>-dev-pr-<n>`, `<distro>-dev-<semver>`, `<distro>-dev-nightly` |
| CI   | `<distro>-ci-latest`, `<distro>-ci-<branch>`, `<distro>-ci-pr-<n>`, `<distro>-ci-<semver>`, `<distro>-ci-nightly` |
| CI Common | `<distro>-ci-common-latest`, `<distro>-ci-common-<branch>`, `<distro>-ci-common-pr-<n>`, `<distro>-ci-common-<semver>`, `<distro>-ci-common-nightly` where `<distro>` is `humble` or `jazzy` |
| CI Robot | `<distro>-ci-robot-latest`, `<distro>-ci-robot-<branch>`, `<distro>-ci-robot-pr-<n>`, `<distro>-ci-robot-<semver>`, `<distro>-ci-robot-nightly` where `<distro>` is `humble` or `jazzy` |
| Robot | `<distro>-robot-latest`, `<distro>-robot-<branch>`, `<distro>-robot-pr-<n>`, `<distro>-robot-<semver>`, `<distro>-robot-nightly` where `<distro>` is `humble` or `jazzy` |
| Sim | `<distro>-sim-latest`, `<distro>-sim-<branch>`, `<distro>-sim-pr-<n>`, `<distro>-sim-<semver>`, `<distro>-sim-nightly` where `<distro>` is `humble` or `jazzy` |
| Nav2 Demos | local-compose image from `cpr-nav2.Dockerfile` |
| Viz | `<distro>-viz-latest`, `<distro>-viz-<branch>`, `<distro>-viz-pr-<n>`, `<distro>-viz-<semver>`, `<distro>-viz-nightly` where `<distro>` is `humble` or `jazzy` |
| Foxglove Bridge | `<distro>-foxglove-bridge-latest`, `<distro>-foxglove-bridge-<branch>`, `<distro>-foxglove-bridge-pr-<n>`, `<distro>-foxglove-bridge-<semver>`, `<distro>-foxglove-bridge-nightly` where `<distro>` is `humble` or `jazzy` |

For example:

```sh
docker pull ghcr.io/clearpathrobotics/clearpath_docker:jazzy-latest
docker pull ghcr.io/clearpathrobotics/clearpath_docker:jazzy-dev-latest
docker pull ghcr.io/clearpathrobotics/clearpath_docker:jazzy-ci-latest
docker pull ghcr.io/clearpathrobotics/clearpath_docker:humble-ci-common-latest
docker pull ghcr.io/clearpathrobotics/clearpath_docker:humble-ci-robot-latest
docker pull ghcr.io/clearpathrobotics/clearpath_docker:humble-sim-latest
docker pull ghcr.io/clearpathrobotics/clearpath_docker:jazzy-ci-common-latest
docker pull ghcr.io/clearpathrobotics/clearpath_docker:jazzy-ci-robot-latest
docker pull ghcr.io/clearpathrobotics/clearpath_docker:jazzy-sim-latest
```

## Building locally

Base image:

```sh
docker build \
  --build-arg ROS_DISTRO=jazzy \
  -f cpr-base.Dockerfile \
  -t cpr-base:jazzy .
```

Dev image (consumes a base image via `CPR_BASE_IMAGE` / `CPR_BASE_TAG`):

```sh
docker build \
  --build-arg ROS_DISTRO=jazzy \
  --build-arg CPR_BASE_IMAGE=cpr-base \
  --build-arg CPR_BASE_TAG=jazzy \
  -f cpr-dev.Dockerfile \
  -t cpr-dev:jazzy .
```

CI image (same pattern):

```sh
docker build \
  --build-arg ROS_DISTRO=jazzy \
  --build-arg CPR_BASE_IMAGE=cpr-base \
  --build-arg CPR_BASE_TAG=jazzy \
  -f cpr-ci.Dockerfile \
  -t cpr-ci:jazzy .
```

Common image (consumes a CI image via `CPR_BASE_IMAGE` / `CPR_BASE_TAG`):

```sh
docker build \
  --build-arg ROS_DISTRO=jazzy \
  --build-arg CPR_BASE_IMAGE=cpr-ci \
  --build-arg CPR_BASE_TAG=jazzy \
  -f cpr-ci-common.Dockerfile \
  -t cpr-ci-common:jazzy .
```

Robot image (consumes a CI image via `CPR_BASE_IMAGE` / `CPR_BASE_TAG`):

```sh
docker build \
  --build-arg ROS_DISTRO=jazzy \
  --build-arg CPR_BASE_IMAGE=cpr-ci \
  --build-arg CPR_BASE_TAG=jazzy \
  -f cpr-ci-robot.Dockerfile \
  -t cpr-ci-robot:jazzy .
```

Sim image (consumes a dev image via `CPR_BASE_IMAGE` / `CPR_BASE_TAG`):

```sh
docker build \
  --build-arg ROS_DISTRO=jazzy \
  --build-arg CPR_BASE_IMAGE=cpr-dev \
  --build-arg CPR_BASE_TAG=jazzy \
  -f cpr-sim.Dockerfile \
  -t cpr-sim:jazzy .
```

Nav2 demos image (consumes a dev image via `CPR_BASE_IMAGE` / `CPR_BASE_TAG`):

```sh
docker build \
  --build-arg ROS_DISTRO=jazzy \
  --build-arg CPR_BASE_IMAGE=cpr-dev \
  --build-arg CPR_BASE_TAG=jazzy \
  -f cpr-nav2.Dockerfile \
  -t cpr-nav2:jazzy .
```

Foxglove Bridge image (consumes a base image via `CPR_BASE_IMAGE` / `CPR_BASE_TAG`):

```sh
docker build \
  --build-arg ROS_DISTRO=jazzy \
  --build-arg CPR_BASE_IMAGE=cpr-base \
  --build-arg CPR_BASE_TAG=jazzy \
  -f cpr-foxglove-bridge.Dockerfile \
  -t cpr-foxglove-bridge:jazzy .
```

Run the sim image with the default setup path:

```sh
docker run --rm --network host \
  ghcr.io/clearpathrobotics/clearpath_docker:jazzy-sim-latest
```

Override the setup path passed to `simulation.launch.py`:

```sh
docker run --rm --network host \
  -e SETUP_PATH="$HOME/setup/path/" \
  ghcr.io/clearpathrobotics/clearpath_docker:jazzy-sim-latest
```

## Using the dev image with a `ros2_ws`

The dev image expects you to mount your ROS 2 workspace at
`/home/robot/ros2_ws` and run as the `robot` user. A typical loop:

```sh
mkdir -p ~/ros2_ws/src ~/.clearpath_docker_history

docker run -it --rm \
  --name cpr-dev \
  --user robot \
  --network host \
  -v ~/ros2_ws:/home/robot/ros2_ws \
  -v ~/.clearpath_docker_history:/commandhistory \
  -w /home/robot/ros2_ws \
  ghcr.io/clearpathrobotics/clearpath_docker:jazzy-dev-latest \
  bash
```

Inside the container, `/opt/ros/<distro>/setup.bash` is sourced automatically
by the `robot` user's `.bashrc`. Resolve dependencies and build with `colcon`:

```sh
sudo apt-get update
rosdep update
rosdep install --from-paths src --ignore-src -r -y
colcon build --symlink-install
source install/setup.bash
```

The mounted `~/.clearpath_docker_history` volume keeps your shell history
between container runs.

### Using Compose

For a less typing-heavy workflow, [compose.yaml](compose.yaml) defines a
`dev` service equivalent to the `docker run` invocation above:

```sh
ROS_DISTRO=jazzy docker compose up -d dev
docker compose exec dev bash
docker compose down
```

The same file also defines a `nav2` service that launches Nav2 demos:

```sh
SETUP_PATH_HOST=$HOME/clearpath ROS_DISTRO=jazzy docker compose up nav2
```

Run simulation, Nav2 demos, and visualization together:

```sh
xhost +local:
SETUP_PATH_HOST=$HOME/clearpath ROS_DISTRO=jazzy docker compose up sim nav2 viz
```

Or use the dedicated compose file:

```sh
xhost +local:
SETUP_PATH_HOST=$HOME/clearpath ROS_DISTRO=jazzy \
  docker compose -f compose-sim-viz-nav2.yaml up
```

The same file also defines a `sim` service that launches:

```sh
ros2 launch clearpath_gz simulation.launch.py setup_path:=<SETUP_PATH>
```

using the sim image defaults. The Gazebo GUI will forward to your host display via X11. Run it with:

```sh
ROS_DISTRO=jazzy docker compose up sim
```

By default, `SETUP_PATH` inside the container is `/etc/clearpath`, and
that path is backed by `${HOME}/clearpath/` on the host. Override either side
as needed:

```sh
SETUP_PATH_HOST=$HOME/my_setup_path \
SETUP_PATH=/etc/clearpath \
docker compose up sim
```

X11 display forwarding is automatic if `DISPLAY` is set on your host (usually `:0` or `:1`);
to override:

```sh
DISPLAY=:1 docker compose up sim
```

**Important**: The setup path must be writable by the container. If using a custom path,
grant write permission first:

```sh
chmod a+w $HOME/my_setup_path
```

Also grant X11 access to local docker connections before launching:

```sh
xhost +local:
```

`ROS_DISTRO`, `ROS2_WS`, `SETUP_PATH`, `SETUP_PATH_HOST`, and any other
variable below can also be set in a `.env` file (git-ignored).
For host-specific tweaks (USB passthrough, extra `group_add`, etc.),
copy [compose.override.yaml.example](compose.override.yaml.example) to
`compose.override.yaml` and edit — Compose merges it automatically.

### Compose environment variables

All variables can be passed on the command line or set in a `.env` file.

| Variable | Default | Services | Description |
| --- | --- | --- | --- |
| `ROS_DISTRO` | `jazzy` | all | ROS 2 distribution (`humble`, `jazzy`, `lyrical`, `rolling`) |
| `ROBOT_DOCKERFILE` | `cpr-robot.Dockerfile` | robot | Dockerfile for the robot service; use `cpr-robot-humble.Dockerfile` for Humble |
| `CLEARPATH_USER` | `robot` | robot | User that runs clearpath services (`administrator` for Humble) |
| `SETUP_PATH_HOST` | `$HOME/clearpath/` | robot, sim, nav2, viz | **Host-side** path to the directory containing `robot.yaml`; mounted into the container at `SETUP_PATH` |
| `SETUP_PATH` | `/etc/clearpath` | sim, nav2, viz | **Container-side** mount point for the setup directory (the other end of `SETUP_PATH_HOST`) |
| `ROS2_WS` | `~/ros2_ws` | dev, dev-local | Host workspace path mounted into the container |
| `USER_UID` | `1000` | dev-local | Host user UID — used to match file ownership in the mounted workspace |
| `USER_GID` | `1000` | dev-local | Host user GID — used to match file ownership in the mounted workspace |
| `RMW_IMPLEMENTATION` | `rmw_cyclonedds_cpp` | sim, nav2, viz, robot | ROS 2 middleware — Humble robot containers must use `rmw_fastrtps_cpp` (firmware requirement) |
| `ROS_AUTOMATIC_DISCOVERY_RANGE` | `LOCALHOST` | sim, nav2, viz | DDS participant discovery scope |
| `ROS_DOMAIN_ID` | `0` | sim, nav2, viz, robot | ROS domain ID |
| `CYCLONEDDS_URI` | (inline XML) | sim, nav2, viz, robot | CycloneDDS configuration XML |
| `DISPLAY` | `:0` | sim, viz | X11 display target |
| `USE_SIM_TIME` | `true` | nav2, viz | Use `/clock` from Gazebo instead of wall time |
| `CLEARPATH_VIZ_CONFIG` | `robot` | viz | RViz config profile (`robot` or `navigation`) |
| `ROBOT_NAMESPACE` | _(auto-detect)_ | nav2, viz | Override the robot namespace (normally read from `robot.yaml`) |
| `WAIT_FOR_SIM` | `false` | nav2 | Wait for `/clock` before starting Nav2 |
| `WAIT_FOR_TIMEOUT_SEC` | `120` | nav2, viz | Seconds to wait for sim topics when `WAIT_FOR_SIM=true` |
| `SCAN_TOPIC` | _(unset)_ | nav2 | Override the lidar scan topic (useful for 3D lidar) |
| `NAV2_LAUNCH_FILE` | `nav2.launch.py` | nav2 | Nav2 launch file; use `slam.launch.py` for SLAM-only mode |
| `NAV2_ENABLE_SLAM` | `false` | nav2 | Run `slam.launch.py` alongside `nav2.launch.py` |
| `NAV2_SLAM_SYNC` | `false` | nav2 | Run SLAM in synchronous mode |
| `AUTO_NAV2_STARTUP` | `true` | nav2 | Auto-call the lifecycle manager startup service on container start |
| `NAV2_STARTUP_TIMEOUT_S` | `120` | nav2 | Seconds to wait for the lifecycle manager service to appear |
| `NAV2_SERVICE_CALL_TIMEOUT_S` | `8` | nav2 | Per-call timeout for lifecycle service calls |
| `NAV2_ACTIVE_WAIT_TIMEOUT_S` | `60` | nav2 | Seconds to wait for all navigation nodes to reach active state |
| `NAV2_TOPIC_WAIT_TIMEOUT_S` | `120` | nav2 | Seconds to wait for odom/TF topics before Nav2 bringup |
| `SIM_STARTUP_TIMEOUT_S` | `120` | sim | Seconds to wait for the simulation stack to become ready |
| `GAZEBO_STARTUP_TIMEOUT` | `120` | sim | Seconds to wait for the Gazebo process to start |
| `GAZEBO_MAX_RESTARTS` | `3` | sim | Max times the Gazebo watchdog will restart Gazebo on failure |
| `FOXGLOVE_BRIDGE_PORT` | `8765` | foxglove-bridge | WebSocket port for `foxglove_bridge` |

#### Matching your host uid/gid (non-1000 users)

The published dev image bakes the `robot` user at uid/gid 1000, so files it
creates in the mounted workspace are owned by uid 1000 on the host. If
your host user is not 1000, use the `dev-local` service in
[compose.yaml](compose.yaml) instead — it rebuilds `cpr-dev.Dockerfile`
locally with `USER_UID` / `USER_GID` build args:

```sh
USER_UID=$(id -u) USER_GID=$(id -g) \
  docker compose up -d --build dev-local
docker compose exec dev-local bash
```

Set `USER_UID` / `USER_GID` in `.env` to avoid re-typing them.

### Hardware access (USB, serial, network)

The dev image runs as the non-root `robot` user (uid/gid 1000). To talk to
host hardware you usually need to pass the device through *and* match the
host group that owns the device node.

A specific serial / USB adapter:

```sh
docker run -it --rm \
  --device=/dev/ttyUSB0 \
  --group-add "$(getent group dialout | cut -d: -f3)" \
  ... ghcr.io/clearpathrobotics/clearpath_docker:jazzy-dev-latest bash
```

All USB devices with dynamic hotplug (catches devices plugged in after the
container starts; `189` is the USB device major):

```sh
docker run -it --rm \
  -v /dev/bus/usb:/dev/bus/usb \
  --device-cgroup-rule='c 189:* rmw' \
  ... ghcr.io/clearpathrobotics/clearpath_docker:jazzy-dev-latest bash
```

For full access on a personal dev box: `--privileged -v /dev:/dev`. Avoid
on shared machines.

Networking: the examples above use `--network host`, which is enough for
raw sockets, multicast DDS discovery, and SocketCAN interfaces brought up
on the host. For tighter isolation, drop `--network host` and add specific
`--cap-add` / `--publish` flags as needed.

## Publishing

[.github/workflows/docker-publish.yml](.github/workflows/docker-publish.yml)
builds and pushes the base, dev, and CI variants for every supported distro,
plus the Humble- and Jazzy-only common, robot, and sim variants, to GHCR on
pushes to `main`, on version tags (`v*`), on pull requests, and nightly at
00:00 UTC. The dev and CI builds wait for the base build and reuse the tag
produced for the same ref; the common and robot (CI and runtime) builds wait
for the CI and base builds respectively and reuse their tags; the sim build
waits for the dev build and reuses its tag.

## License

See [LICENSE](LICENSE).

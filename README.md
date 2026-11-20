# clearpath_docker

Docker images for Clearpath Robotics ROS 2 development and CI, published to
GitHub Container Registry (GHCR) at
[`ghcr.io/clearpathrobotics/clearpath_docker`](https://github.com/clearpathrobotics/clearpath_docker/pkgs/container/clearpath_docker).

## Images

The base, dev, and CI images are built for every supported ROS 2 distro; the
other variants are built for Humble and Jazzy only. The dev, CI, robot, and
foxglove-bridge images are built `FROM` the base image; the CI common and CI
robot images are built `FROM` the CI image; the sim, nav2, and viz images are
built `FROM` the dev image.

### Base — [cpr-base.Dockerfile](docker/cpr-base.Dockerfile)

Headless server-side image — no GUI tooling. `ros:<distro>-ros-base`
extended with the Clearpath public rosdistro index and the Clearpath apt
source (when available for the Ubuntu codename; amd64 only). Slim, no extra tooling,
no non-root user — suitable as a runtime base for robots and as the parent
for the dev and CI images.

### Dev — [cpr-dev.Dockerfile](docker/cpr-dev.Dockerfile)

Headless server-side dev/build environment — no GUI tooling (no `rviz2`,
`rqt`, X11 libs). Built on the base image. Adds `ros-build-essential`,
common Python tooling (`pip`, `pep8`, `autopep8`, `pylint`), editors
(`nano`, `vim`), `bash-completion`, and a non-root user (uid/gid 1000) with
passwordless `sudo`: `administrator` on Humble (matching `clearpath_robot`),
`robot` on other distros. The image runs as that user by default and exports
its name as `CPR_USER`; the sim, nav2, and viz images inherit it. Bash history
is redirected to `/commandhistory` so it can be persisted via a volume.

### CI — [cpr-ci.Dockerfile](docker/cpr-ci.Dockerfile)

Built on the base image. Adds the toolchain needed to build and test ROS 2
packages: `ros-dev-tools`, `colcon` mixins/metadata, `flake8` plugins,
`pytest` helpers, lcov, and the RTI Connext DDS package matching the distro.

### CI Common — [cpr-ci-common.Dockerfile](docker/cpr-ci-common.Dockerfile)

Built on the CI image. Pre-installs the released
`ros-<distro>-clearpath-common` package so all of its build, test, and
runtime dependencies are baked into the image. This is a CI accelerator:
workflows that check out and build `clearpath_common` from source on top of
this image find every dependency already present, so the in-CI `rosdep
install` is a near no-op and the build only needs to compile. The
from-source overlay workspace shadows the pre-installed binary at runtime.
This variant is only built for `humble` and `jazzy`.

### CI Robot — [cpr-ci-robot.Dockerfile](docker/cpr-ci-robot.Dockerfile)

Built on the CI image. Installs the released `ros-<distro>-clearpath-robot`
package so CI jobs targeting robot stacks can start from an image with the
robot metapackage and its dependencies already present. This variant is only
built for `humble` and `jazzy`.

### Sim — [cpr-sim.Dockerfile](docker/cpr-sim.Dockerfile)

Built on the dev image. Installs the released
`ros-<distro>-clearpath-gz` package, runs as the dev image's non-root user
(`administrator` on Humble, `robot` otherwise), and launches:

```sh
ros2 launch clearpath_gz simulation.launch.py setup_path:=/etc/clearpath/
```

The setup path defaults to `/etc/clearpath` and must contain your
`robot.yaml`; pass `SETUP_PATH=/some/other/path` into the container to use
another directory. A watchdog restarts Gazebo if `/clock` doesn't appear in
time (see [sim variables](#compose-environment-variables)).
This variant is only built for `humble` and `jazzy`.

### Nav2 Demos — [cpr-nav2.Dockerfile](docker/cpr-nav2.Dockerfile)

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

The setup path must contain a `robot.yaml`. The namespace comes from that
file: `system.ros2.namespace` when set, otherwise the serial number
(`j100-0000` becomes `j100_0000`). `ROBOT_NAMESPACE` overrides it.

See [Compose environment variables](#compose-environment-variables) for all available variables.

Nav2's lifecycle manager starts its nodes on its own. With `AUTO_NAV2_STARTUP`
(the default), the launcher waits for the lifecycle manager to report its
nodes active, leaving it time to finish (for example while a costmap waits for
its transform), and restarts Nav2 if its launch exits, the bringup fails, or
the nodes still aren't active after `NAV2_ACTIVE_WAIT_TIMEOUT_S`, up to
`NAV2_START_ATTEMPTS` times. The `nav2` container reports healthy
once the lifecycle manager reports its nodes active (with `NAV2_MAP`, the
localization lifecycle manager too) and, with SLAM, a map is publishing; in
SLAM-only mode (`NAV2_LAUNCH_FILE=slam.launch.py`) only the map is checked.

**Usage — standalone against a running sim or robot:**

```sh
docker compose up nav2
```

**Usage — with the sim and RViz:**

```sh
docker compose -f compose-sim-viz-nav2.yaml up
```

`SETUP_PATH_HOST` defaults to `$HOME/clearpath/`. Override if your
`robot.yaml` lives elsewhere:

```sh
SETUP_PATH_HOST=$HOME/my_robot docker compose -f compose-sim-viz-nav2.yaml up
```

#### Saving and loading a map

The `nav2` service mounts `maps/` in the setup directory read-write at
`/etc/clearpath/maps`. Create it before starting the stack, writable by the
container's user (uid 1000, or your uid with `nav2-local`); otherwise Docker
creates it owned by root:

```sh
mkdir -p ~/clearpath/maps && chmod a+w ~/clearpath/maps
```

Save the map SLAM has built with `cpr-nav2 save-map`, passing the same `-f` files
you started the stack with. It finds the robot namespace from `robot.yaml` and
writes `my_map.yaml` and `my_map.pgm` to `~/clearpath/maps`:

```sh
docker compose -f compose-sim-viz-nav2.yaml exec nav2 cpr-nav2 save-map my_map
```

Options after the name go to `map_saver_cli` (for example `--fmt png`), and a
name containing `/` is used as a path inside the container.

To navigate on a saved map instead of building one, point `NAV2_MAP` at it
inside the container. The `nav2` container then runs localization (AMCL and
the map server) alongside navigation:

```sh
xhost +local:
SETUP_PATH_HOST=$HOME/clearpath \
NAV2_MAP=/etc/clearpath/maps/my_map.yaml \
NAV2_INITIAL_POSE="0 0 0" \
CLEARPATH_VIZ_CONFIG=navigation \
docker compose up sim nav2 viz
```

`NAV2_INITIAL_POSE` is the robot's `x y yaw` in the map frame; `0 0 0` is
right when the robot starts where the map was started, such as a fresh sim
with a map built from its spawn point. Otherwise leave it unset and set the
pose with RViz's **2D Pose Estimate**: navigation starts once AMCL has a
pose, and the `nav2` container stays starting until then. `NAV2_MAP` can't be
combined with SLAM.

### Viz — [cpr-viz.Dockerfile](docker/cpr-viz.Dockerfile)

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
ROS_DISTRO=jazzy docker compose up sim viz
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

For prerequisites and full details, see the [NVIDIA GPU overlay](#nvidia-gpu-overlay--composenvidiayaml) section.

The dedicated `compose-sim-viz-nav2.yaml` stack defaults `NAV2_LAUNCH_FILE` to
`nav2.launch.py` and sets `NAV2_ENABLE_SLAM=true`, so both Nav2 and SLAM start
automatically without manual steps, and Nav2 is restarted if it doesn't
become active (`AUTO_NAV2_STARTUP=true`).

In the RViz window, use the RobotModel and TF displays to inspect the simulated
robot. Both containers share the host network and ROS domain, so ROS 2 topics
and services flow between them automatically.

This variant is only built for `humble` and `jazzy`.

### Foxglove Bridge — [cpr-foxglove-bridge.Dockerfile](docker/cpr-foxglove-bridge.Dockerfile)

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

**Usage — with simulation:** started together, the bridge waits for the sim to
report healthy:

```sh
GAZEBO_HEADLESS=true docker compose up sim foxglove-bridge
```

**Usage — standalone against a running sim:**

```sh
docker compose up foxglove-bridge
```

The service uses the same middleware, domain, and setup directory as the other
services. When the bridge runs without Compose (`docker run`), match those
settings yourself; the image waits for the sim (`WAIT_FOR_SIM=true`) unless
told otherwise.

Then open Lichtblick → **Open connection** → **Foxglove WebSocket** →
`ws://localhost:8765`.

See [Compose environment variables](#compose-environment-variables) for all available variables.

### Robot — [cpr-robot.Dockerfile](docker/cpr-robot.Dockerfile) / [cpr-robot-humble.Dockerfile](docker/cpr-robot-humble.Dockerfile)

Runs the full Clearpath robot stack on real hardware, in place of a native
`clearpath_robot` install. Uses `systemd` as PID 1 to manage the clearpath
platform, sensor, and manipulator services. Requires a `robot.yaml` mounted at
`/etc/clearpath/`.

| Dockerfile | Distro | Clearpath user | Published tag |
| --- | --- | --- | --- |
| `cpr-robot.Dockerfile` | Jazzy+ | `robot` | `jazzy-robot-latest` |
| `cpr-robot-humble.Dockerfile` | Humble | `administrator` | `humble-robot-latest` |

The container runs as root (systemd); the services run as the Clearpath user,
which has passwordless `sudo`. On start, the entrypoint runs
`clearpath_robot install` against your `robot.yaml`, enables
`clearpath-robot.service`, and masks `clearpath-shutdown.service` so stopping
the container never powers the robot off.

#### Running on a robot

1. **Install Docker** (Engine plus Compose 2.24 or newer) on the robot
   computer, enable it at boot (`sudo systemctl enable docker`), and clone this
   repository.

2. **Disable any native Clearpath services**, so they don't fight the container
   for the hardware:

   ```sh
   systemctl list-unit-files 'clearpath-*'
   sudo systemctl disable --now clearpath-robot.service
   ```

3. **Install the udev rules on the host.** The container shares the host's
   `/dev`, but only the host's udev creates device links such as
   `/dev/clearpath/*`, `/dev/microstrain_*`, and brings up `can0`/`can1`.
   Copy the rules shipped in the image:

   ```sh
   docker run --rm --entrypoint sh -v /etc/udev/rules.d:/host-rules \
     ghcr.io/clearpathrobotics/clearpath_docker:jazzy-robot-latest \
     -c 'cp /lib/udev/rules.d/60-ros-*.rules /host-rules/'
   sudo udevadm control --reload-rules && sudo udevadm trigger
   ```

   Use the `humble-robot-latest` tag on Humble.

4. **Configure the host network** as for a native install, e.g. the
   `192.168.131.1` address the computer uses to reach the MCU and Ethernet
   sensors. The container uses the host network and doesn't change it.

5. **Put `robot.yaml` in the setup directory**, `~/clearpath/` by default
   (`SETUP_PATH_HOST` points elsewhere). The middleware, domain ID, and
   namespace the services use come from `robot.yaml` (`system.ros2`), not from
   the compose variables.

6. **Start the robot:**

   ```sh
   # Jazzy
   SETUP_PATH_HOST=$HOME/clearpath docker compose up -d robot

   # Humble
   ROS_DISTRO=humble SETUP_PATH_HOST=$HOME/clearpath docker compose up -d robot
   ```

   Put these variables in a `.env` file next to `compose.yaml` to avoid
   retyping them.

7. **Start it on boot** with a `compose.override.yaml`:

   ```yaml
   services:
     robot:
       restart: unless-stopped
   ```

**Checking status:**

```sh
docker compose ps robot                     # (healthy) once the MCU status is publishing
docker compose logs -f robot                # entrypoint and systemd boot output
docker compose exec robot systemctl list-units 'clearpath-*'
docker compose exec robot journalctl -u clearpath-platform -f
```

**After editing `robot.yaml`**, restart the container so the entrypoint
regenerates the launch files: `docker compose restart robot`.

**Updating:** `docker compose pull robot && docker compose up -d robot`.

**Stopping:** `docker compose down`. The robot stays powered.

**Exec into the container** as the Clearpath user. The container's main
process is systemd, which runs as root, so `exec` defaults to root unless
told otherwise:

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

The Clearpath user's shells source `/etc/clearpath/setup.bash`, the file
`clearpath_robot install` generates from `robot.yaml`, as the robot services
do. It sets the ROS distro overlay, any workspace extensions, and the
middleware settings. Other shells (root's, or `bash -c` without `-i`) need it
sourced by hand:

```sh
source /etc/clearpath/setup.bash
```

You can then use any ROS 2 CLI tool. The robot namespace (e.g. `a300_00000`)
comes from `robot.yaml`:

```sh
# List all active nodes
ros2 node list

# List all topics
ros2 topic list

# Echo odometry (replace <namespace> with your robot's namespace, e.g. a300_00000)
ros2 topic echo /<namespace>/platform/odom/filtered
```

Source `/etc/clearpath/setup.bash` in every new shell; the container's default
`~/.bashrc` does **not** source it automatically.

> **Note (Humble only):** The MCU firmware requires FastDDS — keep `system.ros2.middleware.implementation` set to `rmw_fastrtps_cpp` in `robot.yaml` on Humble. CycloneDDS will not communicate with the robot hardware.

If your host user isn't uid 1000, use `robot-local` instead of `robot` so files
the services write into the setup directory are owned by you (see
[Matching your host uid/gid](#matching-your-host-uidgid-non-1000-users)).

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
SETUP_PATH_HOST=$HOME/clearpath ROS_DISTRO=jazzy docker compose -f compose.yaml -f compose.nvidia.yaml up sim viz

# Sim + Nav2 + Viz
SETUP_PATH_HOST=$HOME/clearpath ROS_DISTRO=jazzy docker compose -f compose-sim-viz-nav2.yaml -f compose.nvidia.yaml up
```

### Supported platforms

**ROS 2 distros and container OS** (the Ubuntu release comes from the upstream
`ros:<distro>-ros-base` image):

| ROS 2 distro | Container OS | Images |
| --- | --- | --- |
| `humble` | Ubuntu 22.04 (jammy) | all |
| `jazzy` | Ubuntu 24.04 (noble) | all |
| `lyrical` | Ubuntu 26.04 (resolute) | base, dev, ci |
| `rolling` | Ubuntu 26.04 (resolute) | base, dev, ci |

**Architectures:**

| Image | amd64 | arm64 |
| --- | --- | --- |
| base | yes | yes |
| dev | yes | yes |
| ci, ci-common, ci-robot | yes | no |
| sim, nav2, viz, foxglove-bridge | yes | yes |
| robot | yes | no |

Multi-arch tags resolve to the host architecture automatically. The arm64
base image does not add the Clearpath apt source, which has no arm64 Clearpath
packages; `ros-<distro>-clearpath-robot` is not published for arm64 at all.
The arm64 sim, nav2, viz, and foxglove-bridge images install Clearpath packages
from the ROS apt repo instead, so their versions can lag the amd64 images.

**Host requirements:**

- A Linux host matching the image architecture. Any distribution works; the
  containers carry their own Ubuntu and ROS. The images are tested on an
  Ubuntu 24.04 amd64 host.
- Docker Engine with Compose 2.24 or newer (the compose files use `!reset`,
  `!override`, and optional `depends_on`), and Buildx for `docker buildx bake`.
- Host networking (`network_mode: host`), which needs Docker Engine on Linux.
  Docker Desktop on macOS or Windows isn't supported.
- For `sim` and `viz` with a GUI: an X11 or Xwayland display and
  `xhost +local:`. `GAZEBO_HEADLESS=true` and foxglove-bridge need no display.
- For GPU rendering: an NVIDIA driver and the NVIDIA Container Toolkit (see
  [NVIDIA GPU overlay](#nvidia-gpu-overlay--composenvidiayaml)). Without it
  Gazebo and RViz render on the CPU or through `/dev/dri`.
- For `robot`: the robot computer, with cgroup v2 (systemd runs as PID 1 in
  the container) and the host setup in [Running on a robot](#running-on-a-robot).

## Utility Scripts

The images include utility scripts from [scripts/](scripts/), installed to
`/usr/local/bin/`:

### cpr-common.sh

Common utilities and functions shared by Clearpath launch scripts. Includes:
- `detect_namespace` - Auto-detect robot namespace from `robot.yaml`
- `load_ros_env` - Export the ROS domain, middleware, and discovery settings from `robot.yaml`
- `have_namespace` - Warn and skip a step when no namespace was found
- `wait_for_sim_if_enabled` - Block until `/clock` and odometry are publishing (`WAIT_FOR_SIM`)
- `topic_publishing` / `wait_for_topic_publishing` - Check or wait for messages on a topic
- `split_subcommand` / `source_ros` - Shared plumbing for the service commands below
- `log_robot_yaml` - Debug robot configuration

Source this in scripts with:
```bash
source /usr/local/bin/cpr-common.sh
```

### Service commands

Each runtime image has one command, `cpr-<service>`, whose `launch`
subcommand is the image's default command (launch arguments such as
`name:=value` can follow it, or replace it) and whose `healthcheck` subcommand
is the image's health check:

| Command | `launch` | `healthcheck` passes when |
| --- | --- | --- |
| `cpr-sim` | Gazebo, with a watchdog | `/clock` and odometry are publishing |
| `cpr-nav2` | Nav2, supervised | every lifecycle manager reports its nodes active and, with SLAM, a map is publishing |
| `cpr-viz` | RViz | RViz is running |
| `cpr-foxglove-bridge` | foxglove_bridge | its WebSocket port accepts connections |
| `cpr-robot` | `entrypoint` instead: installs and enables the robot services, then starts systemd | the MCU status is publishing |

`cpr-nav2 save-map <name>` also saves the robot's map (from SLAM or a loaded
map) to `${SETUP_PATH}/maps/<name>.yaml` and `.pgm`; see
[Saving and loading a map](#saving-and-loading-a-map).

### cpr-dev.sh

Development aliases and utilities automatically sourced in shells in the `sim`, `nav2`, `viz`, and
`robot` images. It also loads `robot.yaml`'s ROS settings: in the `robot` image from the robot's
`/etc/clearpath/setup.bash`, elsewhere with `load_ros_env`. Provides:

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
| Nav2 Demos | `<distro>-nav2-latest`, `<distro>-nav2-<branch>`, `<distro>-nav2-pr-<n>`, `<distro>-nav2-<semver>`, `<distro>-nav2-nightly` where `<distro>` is `humble` or `jazzy` |
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

[docker-bake.hcl](docker-bake.hcl) defines every image as a
`<variant>-<distro>` target. Bake builds the parent chain from source (for
example base → dev → sim) and tags the result `cpr-<variant>:<distro>`:

```sh
docker buildx bake sim-jazzy        # cpr-sim:jazzy
docker buildx bake ci-common-humble # cpr-ci-common:humble
docker buildx bake nav2             # cpr-nav2:humble and cpr-nav2:jazzy
docker buildx bake --print viz-jazzy  # show the resolved build without running it
```

To build a single image on top of a published parent instead, pass the
parent through `CPR_BASE_IMAGE` / `CPR_BASE_TAG`:

```sh
docker build \
  --build-arg ROS_DISTRO=jazzy \
  --build-arg CPR_BASE_IMAGE=ghcr.io/clearpathrobotics/clearpath_docker \
  --build-arg CPR_BASE_TAG=jazzy-dev-latest \
  -f docker/cpr-sim.Dockerfile \
  -t cpr-sim:jazzy .
```

Run the sim image headless, with the setup directory containing your
`robot.yaml` mounted at the default `/etc/clearpath` (the sim writes generated
files there, so it must be writable):

```sh
docker run --rm --network host \
  -v $HOME/clearpath:/etc/clearpath \
  -e GAZEBO_HEADLESS=true \
  ghcr.io/clearpathrobotics/clearpath_docker:jazzy-sim-latest
```

To mount it somewhere else, point `SETUP_PATH` at the mount:

```sh
docker run --rm --network host \
  -v $HOME/clearpath:/opt/setup \
  -e SETUP_PATH=/opt/setup \
  -e GAZEBO_HEADLESS=true \
  ghcr.io/clearpathrobotics/clearpath_docker:jazzy-sim-latest
```

## Using the dev image with a `ros2_ws`

The dev image expects you to mount your ROS 2 workspace at `/ros2_ws` and
runs as its non-root user (`administrator` on Humble, `robot` otherwise).
A typical loop:

```sh
mkdir -p ~/ros2_ws/src ~/.clearpath_docker_history

docker run -it --rm \
  --name cpr-dev \
  --network host \
  -v ~/ros2_ws:/ros2_ws \
  -v ~/.clearpath_docker_history:/commandhistory \
  ghcr.io/clearpathrobotics/clearpath_docker:jazzy-dev-latest \
  bash
```

Inside the container, `/opt/ros/<distro>/setup.bash` is sourced automatically
by the user's `.bashrc`. Resolve dependencies and build with `colcon`:

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

`nav2` and `viz` wait for `sim` to be healthy only when it's started in the
same command. Started on their own (for example against a real robot), they
don't start the sim and launch straight away.

Or use the dedicated compose file:

```sh
xhost +local:
SETUP_PATH_HOST=$HOME/clearpath ROS_DISTRO=jazzy \
  docker compose -f compose-sim-viz-nav2.yaml up
```

`compose.yaml` also defines the `sim` service on its own, which launches:

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

To run Gazebo headless (server only, no GUI or X11 required):

```sh
GAZEBO_HEADLESS=true docker compose up sim
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

The `sim` and `viz` services mount the host X authority file from `$XAUTHORITY`,
falling back to `~/.Xauthority`. The file is usually readable only by your user,
so it authenticates containers that run as your uid: the `*-local` services, or
the default images when your uid is 1000. Other containers rely on
`xhost +local:`. If neither path exists, Docker creates an empty root-owned
directory at `~/.Xauthority` instead.

`ROS_DISTRO`, `ROS2_WS`, `SETUP_PATH`, `SETUP_PATH_HOST`, and any other
variable below can also be set in a `.env` file (git-ignored).
For host-specific tweaks (USB passthrough, extra `group_add`, etc.),
copy [compose.override.yaml.example](compose.override.yaml.example) to
`compose.override.yaml` and edit — Compose merges it automatically.

### ROS middleware settings

The sim, nav2, viz, and foxglove-bridge containers take their ROS settings
from the `system.ros2` section of `robot.yaml`, as a robot does:

```yaml
system:
  ros2:
    domain_id: 0                              # ROS_DOMAIN_ID
    middleware:
      implementation: rmw_cyclonedds_cpp      # RMW_IMPLEMENTATION
      automatic_discovery_range: localhost    # ROS_AUTOMATIC_DISCOVERY_RANGE
      profile: /etc/clearpath/cyclonedds.xml  # optional CycloneDDS or Fast DDS profile
```

Fields left out take clearpath_config's defaults: domain 0,
`rmw_fastrtps_cpp`, and subnet discovery. A profile must exist at that path in
every container, so keep it in the setup directory. Without one, CycloneDDS
uses the image's profile (see `CYCLONEDDS_CONFIG` below).

Setting one of the variables overrides `robot.yaml`, for example
`ROS_DOMAIN_ID=5 docker compose up sim nav2`. The exception is
`ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET`, which ROS itself sets by default, so
it can't override a `robot.yaml` range. Interactive shells
(`docker compose exec nav2 bash`) load the same settings; for a one-off
command, use `bash -ic`:

```sh
docker compose exec nav2 bash -ic 'ros2 topic list'
```

Host-side ROS tools need the same domain, middleware, discovery range, and
profile to see the containers.

### Compose environment variables

All variables can be passed on the command line or set in a `.env` file. The
`*-local` services take the same variables as the service they rebuild.

**Common**

| Variable | Default | Services | Description |
| --- | --- | --- | --- |
| `ROS_DISTRO` | `jazzy` | all | ROS 2 distribution (`humble`, `jazzy`, `lyrical`, `rolling`) |
| `SETUP_PATH_HOST` | `$HOME/clearpath/` | sim, nav2, viz, foxglove-bridge, robot | **Host-side** path to the directory containing `robot.yaml`; mounted into the container at `SETUP_PATH` |
| `SETUP_PATH` | `/etc/clearpath` | sim, nav2, viz, foxglove-bridge, robot | **Container-side** mount point for the setup directory (the other end of `SETUP_PATH_HOST`) |
| `RMW_IMPLEMENTATION` | _(robot.yaml)_ | sim, nav2, viz, foxglove-bridge | ROS 2 middleware; overrides `robot.yaml` (see [ROS middleware settings](#ros-middleware-settings)). The `robot` service always uses `robot.yaml` |
| `ROS_AUTOMATIC_DISCOVERY_RANGE` | _(robot.yaml)_ | sim, nav2, viz, foxglove-bridge | DDS participant discovery scope; overrides `robot.yaml` |
| `ROS_DOMAIN_ID` | _(robot.yaml)_ | sim, nav2, viz, foxglove-bridge | ROS domain ID; overrides `robot.yaml` |
| `CYCLONEDDS_CONFIG` | `./config/cyclonedds.xml` | sim, nav2, viz, foxglove-bridge, robot | Host-side CycloneDDS profile mounted at `/etc/cpr/cyclonedds.xml`. The default [config/cyclonedds.xml](config/cyclonedds.xml) sets `ParticipantIndex` to `auto` with `MaxAutoParticipantIndex` 120, which `LOCALHOST` discovery needs for more than 32 ROS processes. Host-side ROS processes, such as the `ros2` CLI, must use the same profile (`export CYCLONEDDS_URI=file://$PWD/config/cyclonedds.xml`) to discover the containers. |
| `CYCLONEDDS_URI` | `file:///etc/cpr/cyclonedds.xml` | sim, nav2, viz, foxglove-bridge | Replaces the profile entirely (a container path or inline XML); overrides a `robot.yaml` profile unless left at the default |
| `ROBOT_NAMESPACE` | _(auto-detect)_ | nav2, viz | Override the robot namespace (normally read from `robot.yaml`) |
| `USE_SIM_TIME` | `true` | nav2, viz | Use `/clock` from Gazebo instead of wall time |
| `WAIT_FOR_SIM` | `false` | nav2, foxglove-bridge | Wait for `/clock` and odometry before starting. Compose already waits for a sim started in the same command |
| `WAIT_FOR_TIMEOUT_SEC` | `120` | nav2, foxglove-bridge | Seconds to wait for sim topics when `WAIT_FOR_SIM=true` |
| `DISPLAY` | `:0` | sim, viz | X11 display target |
| `XAUTHORITY` | `$HOME/.Xauthority` | sim, viz | Host X authority file, mounted read-only at `/tmp/.Xauthority`. Wayland sessions set this to the Xwayland auth file |
| `USER_UID` | `1000` | *-local | Host user UID — used to match file ownership in mounted directories |
| `USER_GID` | `1000` | *-local | Host user GID — used to match file ownership in mounted directories |

**dev**

| Variable | Default | Description |
| --- | --- | --- |
| `ROS2_WS` | `~/ros2_ws` | Host workspace path mounted at `/ros2_ws` |

**sim**

| Variable | Default | Description |
| --- | --- | --- |
| `GAZEBO_STARTUP_TIMEOUT` | `120` | Seconds to wait for `/clock` before the watchdog restarts Gazebo |
| `GAZEBO_MAX_RESTARTS` | `3` | Max times the Gazebo watchdog will restart Gazebo on failure |
| `GAZEBO_HEADLESS` | `false` | Run Gazebo server only (no GUI, headless rendering); no X11 needed |

On a cold start, Gazebo may need to download models before `/clock` is
published. If that takes longer than `GAZEBO_STARTUP_TIMEOUT`, the watchdog
restarts Gazebo and may eventually exhaust its retries. Temporarily allow more
startup time for the first run, for example:

```sh
GAZEBO_STARTUP_TIMEOUT=600 docker compose up sim
```

This timeout applies to every startup attempt. Once the model cache is warm,
you can return to the default.

**nav2**

| Variable | Default | Description |
| --- | --- | --- |
| `NAV2_LAUNCH_FILE` | `nav2.launch.py` | Nav2 launch file; use `slam.launch.py` for SLAM-only mode |
| `NAV2_ENABLE_SLAM` | `false` | Run `slam.launch.py` alongside `nav2.launch.py` |
| `NAV2_SLAM_SYNC` | `false` | Run SLAM in synchronous mode |
| `NAV2_MAP` | _(unset)_ | Saved map (`.yaml`) inside the container, e.g. under `/etc/clearpath`; runs localization alongside navigation |
| `NAV2_INITIAL_POSE` | _(unset)_ | Robot pose `x y yaw` in the map frame, sent to AMCL once localization is up |
| `SCAN_TOPIC` | _(unset)_ | Override the lidar scan topic (useful for 3D lidar) |
| `AUTO_NAV2_STARTUP` | `true` | Wait for Nav2's nodes to become active and restart Nav2 if they don't |
| `NAV2_START_ATTEMPTS` | `3` | Times to start Nav2 before leaving the last attempt running |
| `NAV2_SERVICE_CALL_TIMEOUT_S` | `8` | Timeout for each lifecycle manager status check |
| `NAV2_ACTIVE_WAIT_TIMEOUT_S` | `300` | Seconds to wait for Nav2's nodes to become active before restarting it (`0` waits indefinitely) |
| `NAV2_TOPIC_WAIT_TIMEOUT_S` | `120` | Seconds to wait for odom/TF topics before Nav2 bringup |

**viz**

| Variable | Default | Description |
| --- | --- | --- |
| `CLEARPATH_VIZ_CONFIG` | `robot` | RViz config profile (`robot` or `navigation`) |

**foxglove-bridge**

| Variable | Default | Description |
| --- | --- | --- |
| `FOXGLOVE_BRIDGE_PORT` | `8765` | WebSocket port for `foxglove_bridge` |

The `robot` service takes only common variables; its ROS settings come from
`robot.yaml` (see [Running on a robot](#running-on-a-robot)).

#### Matching your host uid/gid (non-1000 users)

The published images create their user (`robot`, or `administrator` on
Humble) at uid/gid 1000, so files they create in mounted directories are
owned by uid 1000 on the host. If your host user is not 1000, use the
`*-local` services in [compose.yaml](compose.yaml) (`dev-local`, `sim-local`,
`nav2-local`, `viz-local`, `robot-local`). They rebuild the published image with
[docker/cpr-local-user.Dockerfile](docker/cpr-local-user.Dockerfile), which
re-numbers that user to your `USER_UID` / `USER_GID`:

```sh
USER_UID=$(id -u) USER_GID=$(id -g) \
  docker compose up -d --build dev-local
docker compose exec dev-local bash

USER_UID=$(id -u) USER_GID=$(id -g) \
  docker compose up --build sim-local nav2-local viz-local
```

Run the local services together rather than mixing them with the non-local
ones: DDS shared memory doesn't deliver data between containers running as
different uids. Set `USER_UID` / `USER_GID` in `.env` to avoid re-typing them.

### Hardware access (USB, serial, network)

The dev image runs as a non-root user (uid/gid 1000). To talk to
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
plus the Humble- and Jazzy-only CI common, CI robot, robot, sim, nav2, viz, and
foxglove-bridge variants, to GHCR on pushes to `main`, on version tags (`v*`),
on pull requests, and nightly at 00:00 UTC. Each build waits for its parent and
reuses the tag produced for the same ref: dev, CI, robot, and foxglove-bridge
wait for base; CI common and CI robot wait for CI; sim, nav2, and viz wait for
dev.

The base, dev, sim, nav2, viz, and foxglove-bridge images are built natively on `ubuntu-latest` (amd64) and
`ubuntu-24.04-arm` (arm64) runners, pushed by digest, and merged into a single
multi-arch tag. Downstream images wait for the merge.

Each image is a job in `docker-publish.yml` that calls the reusable
[.github/workflows/build-image.yml](.github/workflows/build-image.yml) with its
Dockerfile, parent variant, and distro list.

## License

See [LICENSE](LICENSE).

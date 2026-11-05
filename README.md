# clearpath_docker

Docker images for Clearpath Robotics ROS 2 development and CI, published to
GitHub Container Registry (GHCR) at
[`ghcr.io/clearpathrobotics/clearpath_docker`](https://github.com/clearpathrobotics/clearpath_docker/pkgs/container/clearpath_docker).

## Images

Two image variants are built for each supported ROS 2 distro, plus Humble- and
Jazzy-only common, robot, and sim variants. The dev and CI images are both
built `FROM` the base image; the common and robot images are built `FROM` the
CI image; the sim image is built `FROM` the dev image.

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
`ros-<distro>-clearpath-gz` package, switches the default runtime user to
`robot`, and launches:

```sh
ros2 launch clearpath_gz simulation.launch.py setup_path:=$HOME/setup/path/
```

The launcher defaults `setup_path` to `$HOME/setup/path/`, and you can
override it by passing `SETUP_PATH=/some/other/path/` into the container.
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

**Usage — with simulation:**

```sh
docker compose up sim foxglove-bridge
```

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
the correct ROS distro overlay together with any workspace extensions and the
middleware settings from `robot.yaml`:

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

> **Note (Humble only):** The MCU firmware requires FastDDS — keep `system.ros2.rmw_implementation` set to `rmw_fastrtps_cpp` in `robot.yaml` on Humble. CycloneDDS will not communicate with the robot hardware.

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
  [NVIDIA GPU overlay](#nvidia-gpu-overlay----composenvidiayaml)). Without it
  Gazebo and RViz render on the CPU or through `/dev/dri`.
- For `robot`: the robot computer, with cgroup v2 (systemd runs as PID 1 in
  the container) and the host setup in [Running on a robot](#running-on-a-robot).

## Utility Scripts

The images include utility scripts from [scripts/](scripts/), installed to
`/usr/local/bin/`:

### cpr-common.sh

Common utilities and functions shared by Clearpath launch scripts. Includes:
- `detect_namespace` - Auto-detect robot namespace from `robot.yaml`
- `have_namespace` - Warn and skip a step when no namespace was found
- `wait_for_sim_if_enabled` - Block until `/clock` and odometry are publishing (`WAIT_FOR_SIM`)
- `topic_publishing` / `wait_for_topic_publishing` - Check or wait for messages on a topic
- `wait_for_service` - Wait for a ROS 2 service
- `get_node_state` / `activate_node_direct` - Lifecycle node management
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

`ROS_DISTRO`, `ROS2_WS`, `SETUP_PATH`, `SETUP_PATH_HOST`, and any other
variable below can also be set in a `.env` file (git-ignored).
For host-specific tweaks (USB passthrough, extra `group_add`, etc.),
copy [compose.override.yaml.example](compose.override.yaml.example) to
`compose.override.yaml` and edit — Compose merges it automatically.

### Compose environment variables

All variables can be passed on the command line or set in a `.env` file. The
`*-local` services take the same variables as the service they rebuild.

**Common**

| Variable | Default | Services | Description |
| --- | --- | --- | --- |
| `ROS_DISTRO` | `jazzy` | all | ROS 2 distribution (`humble`, `jazzy`, `lyrical`, `rolling`) |
| `SETUP_PATH_HOST` | `$HOME/clearpath/` | sim, nav2, viz, robot | **Host-side** path to the directory containing `robot.yaml`; mounted into the container at `SETUP_PATH` |
| `SETUP_PATH` | `/etc/clearpath` | sim, nav2, viz, robot | **Container-side** mount point for the setup directory (the other end of `SETUP_PATH_HOST`) |
| `RMW_IMPLEMENTATION` | `rmw_cyclonedds_cpp` | sim, nav2, viz, robot | ROS 2 middleware. On `robot` it only affects `docker exec` shells; the robot services use `robot.yaml` |
| `ROS_AUTOMATIC_DISCOVERY_RANGE` | `LOCALHOST` | sim, nav2, viz, robot | DDS participant discovery scope |
| `ROS_DOMAIN_ID` | `0` | sim, nav2, viz, robot | ROS domain ID |
| `CYCLONEDDS_CONFIG` | `./config/cyclonedds.xml` | sim, nav2, viz, robot | Host-side CycloneDDS profile mounted at `/etc/cpr/cyclonedds.xml`. The default [config/cyclonedds.xml](config/cyclonedds.xml) sets `ParticipantIndex` to `auto` with `MaxAutoParticipantIndex` 120, which `LOCALHOST` discovery needs for more than 32 ROS processes. Host-side ROS processes, such as the `ros2` CLI, must use the same profile (`export CYCLONEDDS_URI=file://$PWD/config/cyclonedds.xml`) to discover the containers. |
| `CYCLONEDDS_URI` | `file:///etc/cpr/cyclonedds.xml` | sim, nav2, viz, robot | Replaces the profile entirely (a container path or inline XML) |
| `ROBOT_NAMESPACE` | _(auto-detect)_ | nav2, viz | Override the robot namespace (normally read from `robot.yaml`) |
| `USE_SIM_TIME` | `true` | nav2, viz | Use `/clock` from Gazebo instead of wall time |
| `WAIT_FOR_SIM` | nav2: `false`, foxglove-bridge: `true` | nav2, foxglove-bridge | Wait for `/clock` and odometry before starting |
| `WAIT_FOR_TIMEOUT_SEC` | `120` | nav2, foxglove-bridge | Seconds to wait for sim topics when `WAIT_FOR_SIM=true` |
| `DISPLAY` | `:0` | sim, viz | X11 display target |
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

**nav2**

| Variable | Default | Description |
| --- | --- | --- |
| `NAV2_LAUNCH_FILE` | `nav2.launch.py` | Nav2 launch file; use `slam.launch.py` for SLAM-only mode |
| `NAV2_ENABLE_SLAM` | `false` | Run `slam.launch.py` alongside `nav2.launch.py` |
| `NAV2_SLAM_SYNC` | `false` | Run SLAM in synchronous mode |
| `SCAN_TOPIC` | _(unset)_ | Override the lidar scan topic (useful for 3D lidar) |
| `AUTO_NAV2_STARTUP` | `true` | Auto-call the lifecycle manager startup service on container start |
| `NAV2_STARTUP_TIMEOUT_S` | `120` | Seconds to wait for the lifecycle manager service to appear |
| `NAV2_SERVICE_CALL_TIMEOUT_S` | `8` | Per-call timeout for lifecycle service calls |
| `NAV2_ACTIVE_WAIT_TIMEOUT_S` | `60` | Seconds to wait for all navigation nodes to reach active state |
| `NAV2_TOPIC_WAIT_TIMEOUT_S` | `120` | Seconds to wait for odom/TF topics before Nav2 bringup |

**viz**

| Variable | Default | Description |
| --- | --- | --- |
| `CLEARPATH_VIZ_CONFIG` | `robot` | RViz config profile (`robot` or `navigation`) |

**foxglove-bridge** (`docker run -e`; not a compose service)

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
plus the Humble- and Jazzy-only common, robot, and sim variants, to GHCR on
pushes to `main`, on version tags (`v*`), on pull requests, and nightly at
00:00 UTC. The dev and CI builds wait for the base build and reuse the tag
produced for the same ref; the common and robot (CI and runtime) builds wait
for the CI and base builds respectively and reuse their tags; the sim build
waits for the dev build and reuses its tag.

The base, dev, sim, nav2, viz, and foxglove-bridge images are built natively on `ubuntu-latest` (amd64) and
`ubuntu-24.04-arm` (arm64) runners, pushed by digest, and merged into a single
multi-arch tag. Downstream images wait for the merge.

Each image is a job in `docker-publish.yml` that calls the reusable
[.github/workflows/build-image.yml](.github/workflows/build-image.yml) with its
Dockerfile, parent variant, and distro list.

## License

See [LICENSE](LICENSE).

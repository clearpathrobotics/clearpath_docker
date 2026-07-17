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
(`nano`, `vim`), `bash-completion`, and a non-root `ros` user (uid/gid
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
`ros`, and launches:

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
  setup_path:=/home/ros/setup/path/
```

The setup path must contain a `robot.yaml` that declares the platform serial
number — e.g. `j100-0000`, `a200-0000`. The namespace (`j100_0000`,
`a200_0000`) is derived automatically from `platform.id` in that file.

**Environment variables:**

| Variable | Default | Description |
| --- | --- | --- |
| `SETUP_PATH` | `/home/ros/setup/path/` | Path inside container to robot.yaml |
| `USE_SIM_TIME` | `true` | Use `/clock` from Gazebo sim |
| `RMW_IMPLEMENTATION` | `rmw_cyclonedds_cpp` | ROS 2 middleware |
| `SCAN_TOPIC` | _(unset)_ | Override the lidar scan topic (useful for 3D lidar) |
| `NAV2_LAUNCH_FILE` | `nav2.launch.py` | Launch file; use `slam.launch.py` to start in SLAM-only mode |
| `NAV2_ENABLE_SLAM` | `false` | When `true`, runs `slam.launch.py` alongside `nav2.launch.py` |
| `AUTO_NAV2_STARTUP` | `false` | When `true`, automatically calls the lifecycle manager startup service and retries until all navigation nodes are active |
| `NAV2_STARTUP_TIMEOUT_S` | `120` | Seconds to wait for the lifecycle manager service to appear |
| `NAV2_SERVICE_CALL_TIMEOUT_S` | `8` | Per-call timeout for lifecycle service calls |
| `NAV2_ACTIVE_WAIT_TIMEOUT_S` | `60` | Seconds to wait for all navigation nodes to reach active state |

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

See [compose.nvidia.yaml](compose.nvidia.yaml) for prerequisites and details.

The dedicated `compose-sim-viz-nav2.yaml` stack defaults `NAV2_LAUNCH_FILE` to
`nav2.launch.py` and sets `NAV2_ENABLE_SLAM=true`, so both Nav2 and SLAM start
automatically without manual steps. It also enables
`AUTO_NAV2_STARTUP=true`, which auto-runs a lifecycle pause/resume bootstrap
to converge Nav2 nodes into an active state.

In the RViz window, use the RobotModel and TF displays to inspect the simulated
robot. Both containers share the host network and ROS domain, so ROS2 topics
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

**Environment variables:**

| Variable | Default | Description |
| --- | --- | --- |
| `FOXGLOVE_BRIDGE_PORT` | `8765` | WebSocket port for foxglove_bridge |

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
docker compose -f compose-sim-viz-nav2.yaml -f compose.nvidia.yaml up
docker compose -f compose-sim-viz.yaml       -f compose.nvidia.yaml up
```

### Supported ROS 2 distros

`humble`, `jazzy`, `lyrical`, `rolling`.

## Tags

Tags are produced by the GitHub Actions workflow and follow this scheme:

| Variant | Tag pattern |
| --- | --- |
| Base | `<distro>-latest`, `<distro>-<branch>`, `<distro>-pr-<n>`, `<distro>-<semver>`, `<distro>-nightly` |
| Dev  | `<distro>-dev-latest`, `<distro>-dev-<branch>`, `<distro>-dev-pr-<n>`, `<distro>-dev-<semver>`, `<distro>-dev-nightly` |
| CI   | `<distro>-ci-latest`, `<distro>-ci-<branch>`, `<distro>-ci-pr-<n>`, `<distro>-ci-<semver>`, `<distro>-ci-nightly` |
| CI Common | `<distro>-ci-common-latest`, `<distro>-ci-common-<branch>`, `<distro>-ci-common-pr-<n>`, `<distro>-ci-common-<semver>`, `<distro>-ci-common-nightly` where `<distro>` is `humble` or `jazzy` |
| CI Robot | `<distro>-ci-robot-latest`, `<distro>-ci-robot-<branch>`, `<distro>-ci-robot-pr-<n>`, `<distro>-ci-robot-<semver>`, `<distro>-ci-robot-nightly` where `<distro>` is `humble` or `jazzy` |
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
`/home/ros/ros2_ws` and run as the `ros` user. A typical loop:

```sh
mkdir -p ~/ros2_ws/src ~/.clearpath_docker_history

docker run -it --rm \
  --name cpr-dev \
  --user ros \
  --network host \
  -v ~/ros2_ws:/home/ros/ros2_ws \
  -v ~/.clearpath_docker_history:/commandhistory \
  -w /home/ros/ros2_ws \
  ghcr.io/clearpathrobotics/clearpath_docker:jazzy-dev-latest \
  bash
```

Inside the container, `/opt/ros/<distro>/setup.bash` is sourced automatically
by the `ros` user's `.bashrc`. Resolve dependencies and build with `colcon`:

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

By default, `SETUP_PATH` inside the container is `/home/ros/setup/path/`, and
that path is backed by `${HOME}/setup/path/` on the host. Override either side
as needed:

```sh
SETUP_PATH_HOST=$HOME/my_setup_path \
SETUP_PATH=/home/ros/setup/path/ \
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

`ROS_DISTRO`, `ROS2_WS`, `SETUP_PATH`, and `SETUP_PATH_HOST` can also be set
in a `.env` file (git-ignored).
For host-specific tweaks (USB passthrough, extra `group_add`, etc.),
copy [compose.override.yaml.example](compose.override.yaml.example) to
`compose.override.yaml` and edit — Compose merges it automatically.

#### Matching your host uid/gid (non-1000 users)

The published dev image bakes the `ros` user at uid/gid 1000, so files it
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

The dev image runs as the non-root `ros` user (uid/gid 1000). To talk to
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
produced for the same ref; the common and robot builds wait for the CI build
and reuse its tag; the sim build waits for the dev build and reuses its tag.

## License

See [LICENSE](LICENSE).

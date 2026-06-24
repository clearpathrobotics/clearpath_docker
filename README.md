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

### Viz — [cpr-viz.Dockerfile](cpr-viz.Dockerfile)

Built on the dev image. Installs `ros-<distro>-clearpath-viz`, reads the
namespace from `robot.yaml` in the setup path, and launches:

```sh
ros2 launch clearpath_viz view_robot.launch.py namespace:=<namespace>
```

The launcher automatically extracts the namespace from `robot.yaml` (e.g.,
`a300_0000`, `a200_0000`). Runs on the same host network as sim, so RViz can
visualize robot state from the simulation.

**Usage — Viz alone:**

```sh
xhost +local:
SETUP_PATH_HOST=$HOME/clearpath ROS_DISTRO=jazzy docker compose up viz
```

**Usage — Sim + Viz together:**

```sh
xhost +local:
SETUP_PATH_HOST=$HOME/clearpath ROS_DISTRO=jazzy \
  docker compose -f compose-sim-viz.yaml up
```

In the RViz window, use the RobotModel and TF displays to inspect the simulated
robot. Both containers share the host network and ROS domain, so ROS2 topics
and services flow between them automatically.

This variant is only built for `humble` and `jazzy`.

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
| Viz | `<distro>-viz-latest`, `<distro>-viz-<branch>`, `<distro>-viz-pr-<n>`, `<distro>-viz-<semver>`, `<distro>-viz-nightly` where `<distro>` is `humble` or `jazzy` |

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

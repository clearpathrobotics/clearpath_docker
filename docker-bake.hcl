# Local builds of the full image chain, e.g. `docker buildx bake sim-jazzy`.
# Images are tagged cpr-<variant>:<distro>; parents are built from source, not pulled.

variable "ALL_DISTROS" {
  default = ["humble", "jazzy", "lyrical", "rolling"]
}

variable "CPR_DISTROS" {
  default = ["humble", "jazzy"]
}

group "default" {
  targets = ["dev-jazzy"]
}

target "base" {
  name       = "base-${distro}"
  matrix     = { distro = ALL_DISTROS }
  dockerfile = "docker/cpr-base.Dockerfile"
  args       = { ROS_DISTRO = distro }
  tags       = ["cpr-base:${distro}"]
}

target "dev" {
  name       = "dev-${distro}"
  matrix     = { distro = ALL_DISTROS }
  dockerfile = "docker/cpr-dev.Dockerfile"
  args       = parent_args("base", distro)
  contexts   = parent_context("base", distro)
  tags       = ["cpr-dev:${distro}"]
}

target "ci" {
  name       = "ci-${distro}"
  matrix     = { distro = ALL_DISTROS }
  dockerfile = "docker/cpr-ci.Dockerfile"
  args       = parent_args("base", distro)
  contexts   = parent_context("base", distro)
  tags       = ["cpr-ci:${distro}"]
}

target "ci-common" {
  name       = "ci-common-${distro}"
  matrix     = { distro = CPR_DISTROS }
  dockerfile = "docker/cpr-ci-common.Dockerfile"
  args       = parent_args("ci", distro)
  contexts   = parent_context("ci", distro)
  tags       = ["cpr-ci-common:${distro}"]
}

target "ci-robot" {
  name       = "ci-robot-${distro}"
  matrix     = { distro = CPR_DISTROS }
  dockerfile = "docker/cpr-ci-robot.Dockerfile"
  args       = parent_args("ci", distro)
  contexts   = parent_context("ci", distro)
  tags       = ["cpr-ci-robot:${distro}"]
}

target "robot" {
  name       = "robot-${distro}"
  matrix     = { distro = CPR_DISTROS }
  dockerfile = distro == "humble" ? "docker/cpr-robot-humble.Dockerfile" : "docker/cpr-robot.Dockerfile"
  args       = parent_args("base", distro)
  contexts   = parent_context("base", distro)
  tags       = ["cpr-robot:${distro}"]
}

target "sim" {
  name       = "sim-${distro}"
  matrix     = { distro = CPR_DISTROS }
  dockerfile = "docker/cpr-sim.Dockerfile"
  args       = parent_args("dev", distro)
  contexts   = parent_context("dev", distro)
  tags       = ["cpr-sim:${distro}"]
}

target "nav2" {
  name       = "nav2-${distro}"
  matrix     = { distro = CPR_DISTROS }
  dockerfile = "docker/cpr-nav2.Dockerfile"
  args       = parent_args("dev", distro)
  contexts   = parent_context("dev", distro)
  tags       = ["cpr-nav2:${distro}"]
}

target "viz" {
  name       = "viz-${distro}"
  matrix     = { distro = CPR_DISTROS }
  dockerfile = "docker/cpr-viz.Dockerfile"
  args       = parent_args("dev", distro)
  contexts   = parent_context("dev", distro)
  tags       = ["cpr-viz:${distro}"]
}

target "foxglove-bridge" {
  name       = "foxglove-bridge-${distro}"
  matrix     = { distro = CPR_DISTROS }
  dockerfile = "docker/cpr-foxglove-bridge.Dockerfile"
  args       = parent_args("base", distro)
  contexts   = parent_context("base", distro)
  tags       = ["cpr-foxglove-bridge:${distro}"]
}

function "parent_args" {
  params = [parent, distro]
  result = {
    ROS_DISTRO     = distro
    CPR_BASE_IMAGE = "cpr-${parent}"
    CPR_BASE_TAG   = distro
  }
}

# Resolve the parent FROM to the sibling bake target instead of a registry pull
function "parent_context" {
  params = [parent, distro]
  result = { "cpr-${parent}:${distro}" = "target:${parent}-${distro}" }
}

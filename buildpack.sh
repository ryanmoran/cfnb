#!/usr/bin/env bash

set -eu
set -o pipefail

readonly BUILDPACK_DIR="$(cd "$(dirname "${0}")/.." && pwd)"

function main() {
  case "$(basename "${0}")" in
    "detect")
      phase::detect "${@:-}"
      ;;

    "supply")
      phase::supply "${@:-}"
      ;;

    "finalize")
      phase::finalize "${@:-}"
      ;;

    "release")
      phase::release "${@:-}"
      ;;
  esac
}

function phase::detect() {
  local working_dir
  working_dir="${1}"

  CNB_STACK_ID=org.cloudfoundry.stacks.cflinuxfs3 \
    "${BUILDPACK_DIR}/cnb/lifecycle/detector" \
       -app "${working_dir}" \
       -buildpacks "${BUILDPACK_DIR}/cnb/buildpacks" \
       -group /tmp/group.toml \
       -log-level info \
       -order "${BUILDPACK_DIR}/buildpack.toml" \
       -plan /tmp/plan.toml \
       -platform /tmp/platform
}

function phase::supply() {
  local working_dir deps_dir index
  working_dir="${1}"
  index="${4}"

  local name version
  name="$(
    grep '\[buildpack\]' -A 4 < "${BUILDPACK_DIR}/buildpack.toml" \
      | grep name \
      | sed 's/  name = \"//' \
      | sed 's/\"$//'
  )"
  version="$(
    grep '\[buildpack\]' -A 4 < "${BUILDPACK_DIR}/buildpack.toml" \
      | grep version \
      | sed 's/  version = \"//' \
      | sed 's/\"$//'
  )"

  echo "-----> ${name} ${version}"

  # Link deps directory to /home/vcap/deps because the given directory is a
  # random path that does not persist into the droplet.
  ln -sf "${3}" "${HOME}/deps"
  deps_dir="${HOME}/deps"

  # Put all layers in this buildpack's dependency directory.
  mkdir "${deps_dir}/${index}/layers"

  CNB_STACK_ID=org.cloudfoundry.stacks.cflinuxfs3 \
    "${BUILDPACK_DIR}/cnb/lifecycle/builder" \
       -app "${working_dir}" \
       -buildpacks "${BUILDPACK_DIR}/cnb/buildpacks" \
       -group /tmp/group.toml \
       -layers "${deps_dir}/${index}/layers" \
       -log-level info \
       -plan /tmp/plan.toml \
       -platform /tmp/platform

  # Remove the deps directory link, restoring the /home/vcap directory to its original state.
  rm "${deps_dir}"
}

function phase::finalize() {
  local deps_dir index
  deps_dir="${3}"
  index="${4}"

  # Copy the launch into the deps directory to that it ends up in the droplet.
  cp -a "${BUILDPACK_DIR}/cnb/lifecycle/launcher" "${deps_dir}/${index}/launcher"

  # Create a launch.yml with references to the layers directory. This will be emitted in the release script.
  cat << EOF > "${deps_dir}/${index}/launch.yml"
---
default_process_types:
  web: |
    CNB_LAYERS_DIR=/home/vcap/deps/${index}/layers \
    CNB_APP_DIR=/home/vcap/app \
      /home/vcap/deps/${index}/launcher
EOF

  cp "${deps_dir}/${index}/launch.yml" /tmp/launch.yml
}

function phase::release() {
  cat /tmp/launch.yml
}

main "${@:-}"

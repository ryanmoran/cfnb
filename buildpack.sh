#!/usr/bin/env bash

set -eu
set -o pipefail

readonly BUILDPACK_DIR="$(cd "$(dirname "${0}")/.." && pwd)"

function main() {
  local phase
  phase="$(basename "${0}")"
  echo "phase: ${phase} | args: ${*:-}" 1>&2

  case "${phase}" in
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
      -platform /tmp/platform \
        > /dev/null
}

function phase::supply() {
  local working_dir deps_dir index
  working_dir="${1}"
  index="${4}"

  if [[ ! -e /tmp/group.toml ]]; then
    phase::detect "${@:-}" > /dev/null
  fi

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

  # Write out the buildpack configuration to indicate to the platform the name
  # and version of the buildpack.
  cat <<EOF > "${deps_dir}/${index}/config.yml"
---
name: ${name}
version: ${version}
magic_string: true # this is a "magic string" used by the profile.d script at launch to help stitch together all of the v3 buildpacks
EOF

  CNB_STACK_ID=org.cloudfoundry.stacks.cflinuxfs3 \
    "${BUILDPACK_DIR}/cnb/lifecycle/builder" \
       -app "${working_dir}" \
       -buildpacks "${BUILDPACK_DIR}/cnb/buildpacks" \
       -group /tmp/group.toml \
       -layers "${deps_dir}/${index}/layers" \
       -log-level info \
       -plan /tmp/plan.toml \
       -platform /tmp/platform

  # Remove the deps directory link, restoring the /home/vcap directory to its
  # original state.
  rm "${deps_dir}"

  # Remove other shared lifecycle files.
  if [[ -e /tmp/group.toml ]]; then
    rm /tmp/group.toml
  fi

  if [[ -e /tmp/plan.toml ]]; then
    rm /tmp/plan.toml
  fi

  if [[ -e /tmp/platform ]]; then
    rmdir /tmp/platform
  fi
}

function phase::finalize() {
  local deps_dir index profile_dir
  deps_dir="${3}"
  index="${4}"
  profile_dir="${5}"

  # Copy the launch into the deps directory to that it ends up in the droplet.
  cp -a "${BUILDPACK_DIR}/cnb/lifecycle/launcher" "${deps_dir}/${index}/launcher"

  # Write out a launch profile script that links up all the layer directories
  # so that the start command works.
  cat << EOF > "${profile_dir}/launch.sh"
mkdir -p /home/vcap/layers/config
touch /home/vcap/layers/config/metadata.toml

for idx in \$(ls /home/vcap/deps); do
	if [[ -e "/home/vcap/deps/\${idx}/config.yml" ]]; then
		if grep --silent magic_string "/home/vcap/deps/\${idx}/config.yml"; then
			for layer in \$(ls /home/vcap/deps/\${idx}/layers); do
				if [[ "\${layer}" == "config" ]]; then
					mv /home/vcap/layers/config/metadata.toml /home/vcap/layers/config/metadata.toml.old
					cat "/home/vcap/deps/\${idx}/layers/\${layer}/metadata.toml" /home/vcap/layers/config/metadata.toml.old > /home/vcap/layers/config/metadata.toml
					rm /home/vcap/layers/config/metadata.toml.old
				else
					ln -s "/home/vcap/deps/\${idx}/layers/\${layer}" "/home/vcap/layers/\${layer}"
				fi
			done
		fi
	fi
done

cat /home/vcap/layers/config/metadata.toml
EOF

  chmod +x "${profile_dir}/launch.sh"

  local cmd
  #cmd="CNB_LAYERS_DIR=/home/vcap/deps/${index}/layers CNB_APP_DIR=/home/vcap/app /home/vcap/deps/${index}/launcher"
  cmd="CNB_LAYERS_DIR=/home/vcap/layers CNB_APP_DIR=/home/vcap/app /home/vcap/deps/${index}/launcher"

  # Create a launch.yml with references to the layers directory.
  cat << EOF > "${deps_dir}/${index}/launch.yml"
---
processes:
- type: web
  command: ${cmd}
EOF

  # Write release.yml to the temporary directory so that the release phase can
  # emit the launch process.
  cat << EOF > /tmp/release.yml
---
default_process_types:
  web: ${cmd}
EOF
}

function phase::release() {
  cat /tmp/release.yml
  rm /tmp/release.yml
}

# HACK: Ensure that errors can be logged as they seem to be dropped if we print
# and then exit too quickly.
function phase::exit() {
  sleep 1
}

trap "phase::exit" EXIT

main "${@:-}"

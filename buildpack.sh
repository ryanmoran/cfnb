#!/usr/bin/env bash

set -e
set -u
set -o pipefail

BUILDPACK_DIR="$(cd "$(dirname "${0}")/.." && pwd)"
readonly BUILDPACK_DIR

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
  local working_dir platform_dir
  working_dir="${1}"
  platform_dir="/tmp/platform"

  util::platform::environment::initialize "${platform_dir}"

  CNB_STACK_ID=org.cloudfoundry.stacks.cflinuxfs3 \
    "${BUILDPACK_DIR}/cnb/lifecycle/detector" \
      -app "${working_dir}" \
      -buildpacks "${BUILDPACK_DIR}/cnb/buildpacks" \
      -group /tmp/group.toml \
      -log-level info \
      -order "${BUILDPACK_DIR}/buildpack.toml" \
      -plan /tmp/plan.toml \
      -platform "${platform_dir}" \
        > /dev/null
}

function phase::supply() {
  local working_dir deps_dir index platform_dir
  working_dir="${1}"
  deps_dir="${3}"
  index="${4}"
  platform_dir="/tmp/platform"

  util::environment::staging::set "${deps_dir}"
  util::platform::environment::initialize "${platform_dir}"

  # If the /tmp/group.toml file is not present, the buildpack skipped
  # detection and we will need to manually invoke it here.
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
  ln -sf "${deps_dir}" "${HOME}/deps"
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
       -platform "${platform_dir}"

  # Write out a launch profile script that links up all the layer directories
  # so that the start command works.
  local profile_dir
  profile_dir="${deps_dir}/${index}/profile.d"
  mkdir -p "${profile_dir}"

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
          for dir in \$(find "/home/vcap/layers/\${layer}/" -mindepth 1 -maxdepth 1 -type d); do
            if [[ -e "\${dir}/bin" ]]; then
              export "PATH=\${dir}/bin\$([[ -n "\${PATH:-}" ]] && printf "%s" ":\${PATH}")"
            fi

            if [[ -e "\${dir}/lib" ]]; then
              export "LD_LIBRARY_PATH=\${dir}/lib\$([[ -n "\${LD_LIBRARY_PATH:-}" ]] && printf "%s" ":\${LD_LIBRARY_PATH}")"
              export "LIBRARY_PATH=\${dir}/lib\$([[ -n "\${LIBRARY_PATH:-}" ]] && printf "%s" ":\${LIBRARY_PATH}")"
            fi

            if [[ -e "\${dir}/include" ]]; then
              export "CPATH=\${dir}/include\$([[ -n "\${CPATH:-}" ]] && printf "%s" ":\${CPATH}")"
            fi

            if [[ -e "\${dir}/pkgconfig" ]]; then
              export "PKG_CONFIG_PATH=\${dir}/pkgconfig\$([[ -n "\${PKG_CONFIG_PATH:-}" ]] && printf "%s" ":\${PKG_CONFIG_PATH}")"
            fi
          done
				fi
			done
		fi
	fi
done
EOF

  chmod +x "${profile_dir}/launch.sh"

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

  if [[ -e "${platform_dir}" ]]; then
    rm -rf "${platform_dir}"
  fi
}

function phase::finalize() {
  local deps_dir index profile_dir
  deps_dir="${3}"
  index="${4}"
  profile_dir="${5}"

  util::environment::staging::set "${deps_dir}"

  # Copy the launch into the deps directory to that it ends up in the droplet.
  cp -a "${BUILDPACK_DIR}/cnb/lifecycle/launcher" "${deps_dir}/${index}/launcher"

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

  util::environment::launch::set "${deps_dir}" "${profile_dir}"
}

function phase::release() {
  cat /tmp/release.yml
  rm /tmp/release.yml
}

function util::environment::staging::set() {
  local deps_dir
  deps_dir="${1}"

  # Prepend all deps/<idx>/bin directories onto $PATH
  IFS=$'\n' read -r -d '' -a paths < <(find "${deps_dir}" -name bin -mindepth 2 -maxdepth 2 | sort | sed "s|${deps_dir}|/home/vcap/deps|" && printf '\0')
  for path in "${paths[@]}"; do
    export "PATH=${path}$([[ -n "${PATH:-}" ]] && printf "%s" ":${PATH}")"
  done

  # Prepend all deps/<idx>/lib directories onto $LD_LIBRARY_PATH and $LIBRARY_PATH
  IFS=$'\n' read -r -d '' -a library_paths < <(find "${deps_dir}" -name lib -mindepth 2 -maxdepth 2 | sort | sed "s|${deps_dir}|/home/vcap/deps|" && printf '\0')
  for path in "${library_paths[@]}"; do
    export "LD_LIBRARY_PATH=${path}$([[ -n "${LD_LIBRARY_PATH:-}" ]] && printf "%s" ":${LD_LIBRARY_PATH}")"
    export "LIBRARY_PATH=${path}$([[ -n "${LIBRARY_PATH:-}" ]] &&  ":${LIBRARY_PATH}")"
  done

  # Prepend all deps/<idx>/include directories onto $CPATH
  IFS=$'\n' read -r -d '' -a cpaths < <(find "${deps_dir}" -name include -mindepth 2 -maxdepth 2 | sort | sed "s|${deps_dir}|/home/vcap/deps|" && printf '\0')
  for path in "${cpaths[@]}"; do
    export "CPATH=${path}$([[ -n "${CPATH:-}" ]] && printf "%s" ":${CPATH}")"
  done

  # Prepend all deps/<idx>/pkgconfig directories onto $PKG_CONFIG_PATH
  IFS=$'\n' read -r -d '' -a pkg_config_paths < <(find "${deps_dir}" -name pkgconfig -mindepth 2 -maxdepth 2 | sort | sed "s|${deps_dir}|/home/vcap/deps|" && printf '\0')
  for path in "${pkg_config_paths[@]}"; do
    export "PKG_CONFIG_PATH=${path}$([[ -n "${PKG_CONFIG_PATH:-}" ]] && printf "%s" ":${PKG_CONFIG_PATH}")"
  done

  # Export all environment variables defined in deps/<idx>/env
  IFS=$'\n' read -r -d '' -a directories < <(find "${deps_dir}" -name env -mindepth 2 -maxdepth 2 | sort && printf '\0')
  for directory in "${directories[@]}"; do
    IFS=$'\n' read -r -d '' -a vars < <(find "${directory}" -type f -mindepth 1 -maxdepth 1 | sort && printf '\0')
    for var in "${vars[@]}"; do
      export "$(basename "${var}")=$(cat "${var}")"
    done
  done
}

function util::environment::launch::set() {
  local deps_dir profile_dir
  deps_dir="${1}"
  profile_dir="${2}"


  # Search the deps directory to find matching directories and prepend them to
  # the following paths, exporting them into
  # /home/vcap/profile.d/000_multi-supply.sh:
  #   PATH            -> bin
  #   LD_LIBRARY_PATH -> lib
  #   LIBRARY_PATH    -> lib
  # Each export should look like the following:
  #   export SOME_VAR=some-value$([[ -n "${SOME_VAR:-}" ]] && echo ":$SOME_VAR")
  local script_path
  script_path="${profile_dir}/000_multi-supply.sh"

  IFS=$'\n' read -r -d '' -a paths < <(find "${deps_dir}" -name bin -mindepth 2 -maxdepth 2 | sort && printf '\0')
  for path in "${paths[@]}"; do
    echo "export PATH=${path}\$([[ -n \"\${PATH:-}\" ]] && printf \"%s\" \":\${PATH}\")" > "${script_path}"
  done

  IFS=$'\n' read -r -d '' -a library_paths < <(find "${deps_dir}" -name lib -mindepth 2 -maxdepth 2 | sort && printf '\0')
  for path in "${library_paths[@]}"; do
    echo "export LD_LIBRARY_PATH=${path}\$([[ -n \"\${LD_LIBRARY_PATH:-}\" ]] && printf \"%s\" \":\${LD_LIBRARY_PATH}\")" > "${script_path}"
    echo "export LIBRARY_PATH=${path}\$([[ -n \"\${LIBRARY_PATH:-}\" ]] && printf \"%s\" \":\${LIBRARY_PATH}\")" > "${script_path}"
  done

  # Search the deps/<idx>/profile.d directories for files. Copy each file into
  # the /home/vcap/profile.d directory using "<idx>_" as a prefix to the
  # filename when copying.
  IFS=$'\n' read -r -d '' -a directories < <(find "${deps_dir}" -name profile.d -mindepth 2 -maxdepth 2 | sort && printf '\0')
  for directory in "${directories[@]}"; do
    IFS=$'\n' read -r -d '' -a files < <(find "${directory}" -type f -mindepth 1 -maxdepth 1 | sort && printf '\0')
    for path in "${files[@]}"; do
      local index
      index="$(echo "${path}" | sed -E 's|.*/([0-9]+)\/profile.d/.*|\1|')"

      cp "${path}" "${profile_dir}/${index}_$(basename "${path}")"
    done
  done
}

function util::platform::environment::initialize() {
  local dir
  dir="${1}"

  mkdir -p "${dir}/env"

  # Find environment variables that are provided by the user
  IFS=$'\n' read -r -d '' -a variables < <(
    env \
      | grep -v '^CF_' \
      | grep -v '^VCAP_' \
      | grep -v '^USER=' \
      | grep -v '^PWD=' \
      | grep -v '^HOME=' \
      | grep -v '^PATH=' \
      | grep -v '^SHLVL=' \
      | grep -v '^_=' \
      | grep -v '^LANG=' \
      | grep -v '^MEMORY_LIMIT='

    printf '\0'
  )

  for variable in "${variables[@]}"; do
    IFS=$'=' read -r -d '' -a parts < <( printf "%s\0" "${variable}" )

    local key value
    key="${parts[0]}"
    value="$(util::join "=" "${parts[@]:1:${#parts[@]}}")"

    printf "%s" "${value}" > "${dir}/env/${key}"
  done
}

function util::join() {
  local IFS="${1}"
  shift
  echo "${*}"
}

# HACK: Ensure that errors can be logged as they seem to be dropped if we print
# and then exit too quickly.
function util::exit() {
  sleep 1
}

trap "util::exit" EXIT

main "${@:-}"

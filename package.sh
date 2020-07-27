#!/usr/bin/env bash

set -eu
set -o pipefail

readonly ROOT_DIR="$(cd "$(dirname "${0}")" && pwd)"

function main() {
  local buildpack lifecycle output

  while [[ "${#}" != 0 ]]; do
    case "${1}" in
      --buildpack)
        buildpack="$(cd "$(dirname "${2}")" && pwd)/$(basename "${2}")"
        shift 2
        ;;

      --lifecycle)
        lifecycle="$(cd "$(dirname "${2}")" && pwd)/$(basename "${2}")"
        shift 2
        ;;

      --output)
        output="${2}"
        shift 2
        ;;

      "")
        # skip if the argument is empty
        shift 1
        ;;

      *)
        util::print::error "unknown argument \"${1}\""
    esac
  done

  if [[ -z "${buildpack}" ]]; then
    echo "--buildpack is a required flag"
    exit 1
  fi

  if [[ -z "${lifecycle}" ]]; then
    echo "--lifecycle is a required flag"
    exit 1
  fi

  if [[ -z "${output}" ]]; then
    echo "--output is a required flag"
    exit 1
  fi

  echo "Packaging Buildpack..."

  local working_dir
  working_dir="$(mktemp -d)"

  pushd "${working_dir}" > /dev/null || true
    cp -a "${buildpack}" ./buildpack.cnb
    cp -a "${lifecycle}" ./lifecycle.tgz

    mkdir bin
    cp -a "${ROOT_DIR}/buildpack.sh" ./bin/run
    pushd ./bin > /dev/null
      for phase in detect supply finalize release; do
        ln -sf run "${phase}"
      done
    popd > /dev/null

    util::tar xzf ./buildpack.cnb /index.json

    local manifest
    manifest="blobs/sha256/$(jq -r '.manifests[0].digest' index.json | sed 's/sha256://')"
    rm index.json

    util::tar xzf ./buildpack.cnb "/${manifest}"

    local config
    config="blobs/sha256/$(jq -r '.config.digest' "${manifest}" | sed 's/sha256://')"
    util::tar xzf ./buildpack.cnb "/${config}"

    local main_id
    main_id="$(jq -r '.config.Labels."io.buildpacks.buildpackage.metadata"' "${config}" | jq -r .id)"

    for layer in $(jq -r '.layers[].digest' "${manifest}" | sed 's/sha256://'); do
      util::tar xzf ./buildpack.cnb "/blobs/sha256/${layer}"
      util::tar xf "blobs/sha256/${layer}"

      if [[ "${main_id}" == "$(util::tar xOf "blobs/sha256/${layer}" ./*buildpack.toml | yj -tj | jq -r .buildpack.id)" ]]; then
        util::tar xOf "blobs/sha256/${layer}" ./*buildpack.toml > buildpack.toml
      fi
    done
    rm -rf "blobs"
    rm ./buildpack.cnb

    pushd cnb > /dev/null
      util::tar xzf ../lifecycle.tgz
      rm ../lifecycle.tgz
    popd > /dev/null

    zip --symlinks --quiet -r "${output}" .
  popd > /dev/null || true

  rm -rf "${working_dir}"
}

function util::tar() {
  tar "${@:-}" 2>&1 | grep -v  "Removing leading" || true
}

main "${@:-}"

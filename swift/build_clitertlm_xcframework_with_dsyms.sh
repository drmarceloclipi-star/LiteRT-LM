#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
readonly ARTIFACT_DIR="${1:-${REPO_ROOT}/dist}"

if [[ "${REPO_ROOT}" == *" "* ]]; then
  echo "error: checkout path must not contain spaces (rules_rust limitation): ${REPO_ROOT}" >&2
  exit 1
fi

BAZEL_STARTUP_ARGS=()
BAZEL_COMMON_ARGS=()

if [[ -n "${CLITERTLM_BAZEL_OUTPUT_USER_ROOT:-}" ]]; then
  BAZEL_STARTUP_ARGS+=("--output_user_root=${CLITERTLM_BAZEL_OUTPUT_USER_ROOT}")
fi

if [[ -n "${CLITERTLM_BAZEL_REPOSITORY_CACHE:-}" ]]; then
  BAZEL_COMMON_ARGS+=("--repository_cache=${CLITERTLM_BAZEL_REPOSITORY_CACHE}")
fi

cd "${REPO_ROOT}"

bazel "${BAZEL_STARTUP_ARGS[@]}" build \
  "${BAZEL_COMMON_ARGS[@]}" \
  --apple_generate_dsym \
  --output_groups=+dsyms \
  //swift:CLiteRTLM

BAZEL_BIN="$(bazel "${BAZEL_STARTUP_ARGS[@]}" info "${BAZEL_COMMON_ARGS[@]}" bazel-bin)"
readonly BAZEL_BIN
readonly SOURCE_ZIP="${BAZEL_BIN}/swift/CLiteRTLM.xcframework.zip"
readonly DEVICE_DSYM="${BAZEL_BIN}/swift/CLiteRTLM_dsyms/CLiteRTLM_ios_device.framework.dSYM"
readonly SIMULATOR_DSYM="${BAZEL_BIN}/swift/CLiteRTLM_dsyms/CLiteRTLM_ios_simulator.framework.dSYM"

for required_path in "${SOURCE_ZIP}" "${DEVICE_DSYM}" "${SIMULATOR_DSYM}"; do
  if [[ ! -e "${required_path}" ]]; then
    echo "error: expected Bazel output missing: ${required_path}" >&2
    exit 1
  fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clitertlm-xcframework.XXXXXX")"
readonly WORK_DIR
trap 'rm -rf "${WORK_DIR}"' EXIT

ditto -x -k "${SOURCE_ZIP}" "${WORK_DIR}/extracted"

readonly DEVICE_FRAMEWORK="${WORK_DIR}/extracted/CLiteRTLM.xcframework/ios-arm64/CLiteRTLM.framework"
readonly SIMULATOR_FRAMEWORK="${WORK_DIR}/extracted/CLiteRTLM.xcframework/ios-arm64-simulator/CLiteRTLM.framework"
readonly DEVICE_DWARF="${DEVICE_DSYM}/Contents/Resources/DWARF/CLiteRTLM_ios_device"
readonly SIMULATOR_DWARF="${SIMULATOR_DSYM}/Contents/Resources/DWARF/CLiteRTLM_ios_simulator"

uuid_for_binary() {
  dwarfdump --uuid "$1" | awk 'NR == 1 { print $2 }'
}

verify_symbol_pair() {
  local framework_binary="$1"
  local dsym_binary="$2"
  local framework_uuid
  local dsym_uuid

  framework_uuid="$(uuid_for_binary "${framework_binary}")"
  dsym_uuid="$(uuid_for_binary "${dsym_binary}")"

  if [[ -z "${framework_uuid}" || "${framework_uuid}" != "${dsym_uuid}" ]]; then
    echo "error: framework/dSYM UUID mismatch: ${framework_uuid:-missing} != ${dsym_uuid:-missing}" >&2
    exit 1
  fi

  if ! xcrun llvm-objdump --macho --section-headers "${dsym_binary}" \
    | awk '$2 == "__debug_info" && $3 !~ /^0+$/ { found = 1 } END { exit !found }'; then
    echo "error: dSYM has no non-empty __debug_info section: ${dsym_binary}" >&2
    exit 1
  fi

  echo "verified ${framework_uuid}: ${framework_binary}"
}

verify_symbol_pair "${DEVICE_FRAMEWORK}/CLiteRTLM" "${DEVICE_DWARF}"
verify_symbol_pair "${SIMULATOR_FRAMEWORK}/CLiteRTLM" "${SIMULATOR_DWARF}"

mkdir -p "${ARTIFACT_DIR}"

readonly XCFRAMEWORK_PATH="${WORK_DIR}/CLiteRTLM.xcframework"
readonly ZIP_PATH="${ARTIFACT_DIR}/CLiteRTLM.xcframework.zip"
readonly STAGED_ZIP_PATH="${WORK_DIR}/CLiteRTLM.xcframework.zip"

xcodebuild -create-xcframework \
  -framework "${DEVICE_FRAMEWORK}" \
  -debug-symbols "${DEVICE_DSYM}" \
  -framework "${SIMULATOR_FRAMEWORK}" \
  -debug-symbols "${SIMULATOR_DSYM}" \
  -output "${XCFRAMEWORK_PATH}"

# SwiftPM hashes the complete archive. Fixed timestamps make identical inputs
# produce an identical release checksum.
find "${XCFRAMEWORK_PATH}" -exec touch -h -t 198001010000 {} +

(
  cd "${WORK_DIR}"
  COPYFILE_DISABLE=1 /usr/bin/zip -q -r -X "${STAGED_ZIP_PATH}" CLiteRTLM.xcframework
)

mv -f "${STAGED_ZIP_PATH}" "${ZIP_PATH}"

readonly CHECKSUM="$(swift package compute-checksum "${ZIP_PATH}")"

echo "artifact: ${ZIP_PATH}"
echo "checksum: ${CHECKSUM}"

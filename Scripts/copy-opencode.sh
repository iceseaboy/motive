#!/bin/sh
set -euo pipefail

SOURCE="${PROJECT_DIR}/Motive/Resources/opencode"
if [ -n "${OPENCODE_BINARY_PATH:-}" ]; then
  SOURCE="${OPENCODE_BINARY_PATH}"
fi

DEST="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/opencode"
PLUGIN_SOURCE_DIR="${PROJECT_DIR}/Motive/Resources/Plugins/motive-memory"
PLUGIN_DEST_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Resources/Plugins/motive-memory"

if [ ! -f "${SOURCE}" ]; then
  echo "warning: OpenCode binary not found at ${SOURCE}."
  echo "warning: Provide ${PROJECT_DIR}/Motive/Resources/opencode or set OPENCODE_BINARY_PATH."
else
  cp -f "${SOURCE}" "${DEST}"
  chmod +x "${DEST}"

  if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]; then
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${DEST}"
  else
    /usr/bin/codesign --force --sign - "${DEST}"
  fi
fi

if [ -d "${PLUGIN_SOURCE_DIR}" ]; then
  mkdir -p "${PLUGIN_DEST_DIR}"
  cp -R "${PLUGIN_SOURCE_DIR}/." "${PLUGIN_DEST_DIR}"
else
  echo "warning: Memory plugin source not found at ${PLUGIN_SOURCE_DIR}."
fi

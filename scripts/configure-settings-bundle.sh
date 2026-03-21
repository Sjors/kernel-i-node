#!/bin/sh

set -eu

settings_bundle_path="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Settings.bundle"

if [ ! -d "${settings_bundle_path}" ]; then
    exit 0
fi

case " ${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-} " in
    *" DISABLE_KERNEL_LOGGING "*)
        cp "${SRCROOT}/Node/Settings.bundle/Root.LoggingDisabled.plist" "${settings_bundle_path}/Root.plist"
        ;;
    *)
        cp "${SRCROOT}/Node/Settings.bundle/Root.plist" "${settings_bundle_path}/Root.plist"
        ;;
esac

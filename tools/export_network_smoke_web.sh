#!/usr/bin/env bash
# Build the disposable networking smoke-test scene as a Web export.
#
# Godot exports the project's configured main scene. Production must keep its
# real main menu, so this helper temporarily points project.godot at the smoke
# scene, exports it, and restores the original file before it exits.

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_DIR="$(cd "${TOOLS_DIR}/.." && pwd)"
PROJECT_FILE="${GAME_DIR}/project.godot"
EXPORT_PRESETS_FILE="${GAME_DIR}/export_presets.cfg"
OUTPUT_DIR="${GAME_DIR}/releases/network-smoke-web"
GODOT_BIN="${GODOT_BIN:-godot}"
SMOKE_MAIN_SCENE='run/main_scene="uid://ty8b6rdy818c"'

if ! command -v "${GODOT_BIN}" >/dev/null 2>&1; then
	echo "Godot executable not found: ${GODOT_BIN}" >&2
	echo "Install Godot or run with GODOT_BIN=/path/to/godot." >&2
	exit 1
fi

# Keep the backup outside the project so Godot never treats it as a resource.
PROJECT_BACKUP="$(mktemp "${TMPDIR:-/tmp}/network-smoke-project.XXXXXX")"
PROJECT_REWRITE="$(mktemp "${TMPDIR:-/tmp}/network-smoke-project-rewrite.XXXXXX")"
EXPORT_PRESETS_BACKUP="$(mktemp "${TMPDIR:-/tmp}/network-smoke-export-presets.XXXXXX")"
EXPORT_PRESETS_REWRITE="$(mktemp "${TMPDIR:-/tmp}/network-smoke-export-presets-rewrite.XXXXXX")"

cleanup() {
	# The main scene is a project setting, not a smoke-test implementation detail.
	# Always put the original configuration back, including on export failure.
	cp "${PROJECT_BACKUP}" "${PROJECT_FILE}"
	cp "${EXPORT_PRESETS_BACKUP}" "${EXPORT_PRESETS_FILE}"
	rm -f \
		"${PROJECT_BACKUP}" \
		"${PROJECT_REWRITE}" \
		"${EXPORT_PRESETS_BACKUP}" \
		"${EXPORT_PRESETS_REWRITE}"
}
trap cleanup EXIT

cp "${PROJECT_FILE}" "${PROJECT_BACKUP}"
cp "${EXPORT_PRESETS_FILE}" "${EXPORT_PRESETS_BACKUP}"

# Replace exactly one project setting without relying on macOS-only `sed -i`.
awk -v replacement="${SMOKE_MAIN_SCENE}" '
	BEGIN { replaced = 0 }
	/^run\/main_scene=/ {
		print replacement
		replaced = 1
		next
	}
	{ print }
	END {
		if (!replaced) {
			exit 1
		}
	}
' "${PROJECT_FILE}" >"${PROJECT_REWRITE}"

mv "${PROJECT_REWRITE}" "${PROJECT_FILE}"

# The smoke test does not use threads or native extensions. Disabling both for
# this export lets a basic static HTTP server run it without COOP/COEP headers.
awk '
	/^variant\/extensions_support=/ {
		print "variant/extensions_support=false"
		next
	}
	/^variant\/thread_support=/ {
		print "variant/thread_support=false"
		next
	}
	{ print }
' "${EXPORT_PRESETS_FILE}" >"${EXPORT_PRESETS_REWRITE}"

mv "${EXPORT_PRESETS_REWRITE}" "${EXPORT_PRESETS_FILE}"
mkdir -p "${OUTPUT_DIR}"

echo "Exporting the network smoke test to ${OUTPUT_DIR}"
"${GODOT_BIN}" --headless --path "${GAME_DIR}" --export-debug "Web" "releases/network-smoke-web/index.html"
echo "Done. Serve ${OUTPUT_DIR} over HTTP to run the smoke test."

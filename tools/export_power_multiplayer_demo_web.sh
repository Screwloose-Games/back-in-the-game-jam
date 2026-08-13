#!/usr/bin/env bash
# Build the integrated power-and-lighting multiplayer demo as a Web export.
#
# Production keeps its real main menu. This helper temporarily selects the demo,
# disables Web features the demo does not use, exports, and restores both project
# configuration files even when Godot fails.

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_DIR="$(cd "${TOOLS_DIR}/.." && pwd)"
PROJECT_FILE="${GAME_DIR}/project.godot"
EXPORT_PRESETS_FILE="${GAME_DIR}/export_presets.cfg"
OUTPUT_DIR="${GAME_DIR}/releases/power-multiplayer-demo-web"
GODOT_BIN="${GODOT_BIN:-godot}"
DEMO_SCENE='res://prototypes/power_and_lighting/power_and_lighting_multiplayer_demo.tscn'
DEMO_MAIN_SCENE="run/main_scene=\"${DEMO_SCENE}\""

if ! command -v "${GODOT_BIN}" >/dev/null 2>&1; then
	echo "Godot executable not found: ${GODOT_BIN}" >&2
	exit 1
fi

PROJECT_BACKUP="$(mktemp "${TMPDIR:-/tmp}/power-mp-project.XXXXXX")"
PROJECT_REWRITE="$(mktemp "${TMPDIR:-/tmp}/power-mp-project-rewrite.XXXXXX")"
EXPORT_PRESETS_BACKUP="$(mktemp "${TMPDIR:-/tmp}/power-mp-export-presets.XXXXXX")"
EXPORT_PRESETS_REWRITE="$(mktemp "${TMPDIR:-/tmp}/power-mp-export-presets-rewrite.XXXXXX")"

cleanup() {
	cp "${PROJECT_BACKUP}" "${PROJECT_FILE}"
	cp "${EXPORT_PRESETS_BACKUP}" "${EXPORT_PRESETS_FILE}"
	rm -f \
		"${PROJECT_BACKUP}" \
		"${PROJECT_REWRITE}" \
		"${EXPORT_PRESETS_BACKUP}" \
		"${EXPORT_PRESETS_REWRITE}"
}

cp "${PROJECT_FILE}" "${PROJECT_BACKUP}"
cp "${EXPORT_PRESETS_FILE}" "${EXPORT_PRESETS_BACKUP}"
trap cleanup EXIT

awk -v replacement="${DEMO_MAIN_SCENE}" '
	BEGIN {
		replaced = 0
	}
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
cp "${PROJECT_REWRITE}" "${PROJECT_FILE}"

# The demo has no native extensions. Its single-threaded build is the portable
# Godot Web default and works on ordinary static hosts without SharedArrayBuffer
# isolation headers. Keep the preset's complete resource set for now: Godot's
# scene-only filter does not discover every dependency referenced through
# GDScript (including class_name types and preloaded player/network scenes).
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
cp "${EXPORT_PRESETS_REWRITE}" "${EXPORT_PRESETS_FILE}"

mkdir -p "${OUTPUT_DIR}"
echo "Exporting the power multiplayer demo to ${OUTPUT_DIR}"
"${GODOT_BIN}" \
	--headless \
	--path "${GAME_DIR}" \
	--export-release "Web" \
	"releases/power-multiplayer-demo-web/index.html"
echo "Done. Serve ${OUTPUT_DIR} over HTTP and open it in two browsers."

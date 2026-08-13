#!/usr/bin/env bash
# Build the drill-and-mining multiplayer proof as a portable Web export.
#
# Production keeps its real main scene and autoloads. This helper temporarily
# selects the self-contained demo, exports only its dependency closure, and
# restores the tracked configuration files even when Godot fails.

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_DIR="$(cd "${TOOLS_DIR}/.." && pwd)"
PROJECT_FILE="${GAME_DIR}/project.godot"
EXPORT_PRESETS_FILE="${GAME_DIR}/export_presets.cfg"
OUTPUT_DIR="${GAME_DIR}/releases/drill-multiplayer-demo-web"
EXPORT_LOG="${TMPDIR:-/tmp}/drill-multiplayer-demo-export.log"
GODOT_BIN="${GODOT_BIN:-godot}"
DEMO_SCENE='res://prototypes/drill_and_mining/drill_and_mining_multiplayer_demo.tscn'
DEMO_SCENE_FILE="${GAME_DIR}/${DEMO_SCENE#res://}"
DEMO_SCENE_MARKER='prototypes/drill_and_mining/drill_and_mining_multiplayer_demo.tscn'
DEMO_MAIN_SCENE="run/main_scene=\"${DEMO_SCENE}\""

# Scene dependencies are followed by Godot. The explicit filters also cover
# scripts reached through class_name and preload calls rather than scene nodes.
INCLUDE_FILTER='common/network/multiplayer_session_shell.*'
INCLUDE_FILTER+=',common/network/network_session.*'
INCLUDE_FILTER+=',common/network/prediction/*'
INCLUDE_FILTER+=',common/network/signaling_client.*'
INCLUDE_FILTER+=',common/network/webrtc_session.*'
INCLUDE_FILTER+=',common/themes/*,common/fonts/*'
INCLUDE_FILTER+=',prototypes/drill_and_mining/drill_and_mining_multiplayer_demo.*'
INCLUDE_FILTER+=',prototypes/drill_and_mining/multiplayer_drill_*'
INCLUDE_FILTER+=',prototypes/drill_and_mining/drill_knobs.*'
INCLUDE_FILTER+=',prototypes/drill_and_mining/drill_settings.*'
INCLUDE_FILTER+=',prototypes/drill_and_mining/ore_debris_pool.*'
INCLUDE_FILTER+=',prototypes/drill_and_mining/ore_node.*'
INCLUDE_FILTER+=',prototypes/drill_and_mining/surface_net_mesher.*'
INCLUDE_FILTER+=',prototypes/drill_and_mining/voxel_field.*'
INCLUDE_FILTER+=',prototypes/drill_and_mining/imported/drill_movement_knobs.*'
INCLUDE_FILTER+=',prototypes/drill_and_mining/materials/*'
INCLUDE_FILTER+=',prototypes/shared/prototype_settings.gd'
INCLUDE_FILTER+=',prototypes/shared/prototype_settings.gd.uid'

if ! command -v "${GODOT_BIN}" >/dev/null 2>&1; then
	echo "Godot executable not found: ${GODOT_BIN}" >&2
	exit 1
fi

if [[ ! -f "${DEMO_SCENE_FILE}" ]]; then
	echo "Drill multiplayer scene not found: ${DEMO_SCENE_FILE}" >&2
	exit 1
fi

file_mode() {
	local path="$1"
	local mode

	if mode="$(stat -f '%Lp' "${path}" 2>/dev/null)"; then
		printf '%s\n' "${mode}"
	elif mode="$(stat -c '%a' "${path}" 2>/dev/null)"; then
		printf '%s\n' "${mode}"
	else
		echo "Could not read file mode: ${path}" >&2
		return 1
	fi
}

PROJECT_MODE="$(file_mode "${PROJECT_FILE}")"
EXPORT_PRESETS_MODE="$(file_mode "${EXPORT_PRESETS_FILE}")"
PROJECT_BACKUP="$(mktemp "${TMPDIR:-/tmp}/drill-mp-project.XXXXXX")"
PROJECT_REWRITE="$(mktemp "${TMPDIR:-/tmp}/drill-mp-project-rewrite.XXXXXX")"
EXPORT_PRESETS_BACKUP="$(mktemp "${TMPDIR:-/tmp}/drill-mp-presets.XXXXXX")"
EXPORT_PRESETS_REWRITE="$(mktemp "${TMPDIR:-/tmp}/drill-mp-presets-rewrite.XXXXXX")"
RESTORED=false

restore_configuration() {
	if [[ "${RESTORED}" == true ]]; then
		return
	fi

	cp "${PROJECT_BACKUP}" "${PROJECT_FILE}"
	chmod "${PROJECT_MODE}" "${PROJECT_FILE}"
	cp "${EXPORT_PRESETS_BACKUP}" "${EXPORT_PRESETS_FILE}"
	chmod "${EXPORT_PRESETS_MODE}" "${EXPORT_PRESETS_FILE}"
	RESTORED=true
}

cleanup() {
	local status=$?
	trap - EXIT INT TERM
	set +e

	restore_configuration
	local restore_status=$?
	rm -f \
		"${PROJECT_BACKUP}" \
		"${PROJECT_REWRITE}" \
		"${EXPORT_PRESETS_BACKUP}" \
		"${EXPORT_PRESETS_REWRITE}"

	if ((restore_status != 0)); then
		echo "Failed to restore Godot configuration after export." >&2
		exit 1
	fi
	exit "${status}"
}

cp "${PROJECT_FILE}" "${PROJECT_BACKUP}"
cp "${EXPORT_PRESETS_FILE}" "${EXPORT_PRESETS_BACKUP}"
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The demo owns its session and gameplay state. Production globals would pull
# unrelated scenes and addons into this deliberately narrow export.
awk -v replacement="${DEMO_MAIN_SCENE}" '
	BEGIN {
		replaced = 0
	}
	/^run\/main_scene=/ {
		print replacement
		replaced = 1
		next
	}
	/^(GlobalSignalBus|SceneManager|SceneTransitionManager|GameSettings|SoundManager|_mcp_game_helper)=/ {
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

# Selected-scene export avoids packing unrelated jam prototypes. Single-thread
# Web with no native extensions works on an ordinary static HTTP host without
# requiring SharedArrayBuffer cross-origin-isolation headers.
awk -v scene="${DEMO_SCENE}" -v includes="${INCLUDE_FILTER}" '
	/^\[preset\.0\]$/ {
		in_web = 1
		print
		next
	}
	/^\[preset\.[0-9]+\]$/ {
		in_web = 0
		print
		next
	}
	in_web && /^export_filter=/ {
		print "export_filter=\"scenes\""
		print "export_files=PackedStringArray(\"" scene "\")"
		next
	}
	in_web && /^export_files=/ {
		next
	}
	in_web && /^include_filter=/ {
		print "include_filter=\"" includes "\""
		next
	}
	in_web && /^variant\/extensions_support=/ {
		print "variant/extensions_support=false"
		next
	}
	in_web && /^variant\/thread_support=/ {
		print "variant/thread_support=false"
		next
	}
	{ print }
' "${EXPORT_PRESETS_FILE}" >"${EXPORT_PRESETS_REWRITE}"
cp "${EXPORT_PRESETS_REWRITE}" "${EXPORT_PRESETS_FILE}"

mkdir -p "${OUTPUT_DIR}"
echo "Exporting the drill multiplayer demo to ${OUTPUT_DIR}"
"${GODOT_BIN}" \
	--headless \
	--log-file "${EXPORT_LOG}" \
	--path "${GAME_DIR}" \
	--export-release "Web" \
	"releases/drill-multiplayer-demo-web/index.html"

for output_file in index.html index.js index.pck index.wasm; do
	if [[ ! -s "${OUTPUT_DIR}/${output_file}" ]]; then
		echo "Expected export output is missing or empty: ${OUTPUT_DIR}/${output_file}" >&2
		exit 1
	fi
done

if ! grep -aFq "${DEMO_SCENE_MARKER}" "${OUTPUT_DIR}/index.pck"; then
	echo "Export pack does not contain the drill multiplayer scene." >&2
	exit 1
fi

restore_configuration
echo "Done. Serve ${OUTPUT_DIR} over HTTP and open it in two browsers."

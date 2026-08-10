#!/usr/bin/env bash
# Build the small tentacle-crawler multiplayer proof as a portable Web export.
#
# The production game keeps its main scene and autoloads. This helper swaps in
# the demo, narrows the export to its known dependency folders, exports, and
# restores both configuration files even if Godot fails.

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_DIR="$(cd "${TOOLS_DIR}/.." && pwd)"
PROJECT_FILE="${GAME_DIR}/project.godot"
EXPORT_PRESETS_FILE="${GAME_DIR}/export_presets.cfg"
OUTPUT_DIR="${GAME_DIR}/releases/tentacle-crawler-multiplayer-demo-web"
GODOT_BIN="${GODOT_BIN:-godot}"
DEMO_SCENE='res://prototypes/tentacle_crawler_chaser/tentacle_crawler_multiplayer_demo.tscn'
DEMO_MAIN_SCENE="run/main_scene=\"${DEMO_SCENE}\""
INCLUDE_FILTER='common/network/multiplayer_session_shell.*'
INCLUDE_FILTER+=',common/network/network_session.gd'
INCLUDE_FILTER+=',common/network/prediction/*'
INCLUDE_FILTER+=',common/network/signaling_client.gd'
INCLUDE_FILTER+=',common/network/webrtc_session.gd'
INCLUDE_FILTER+=',common/themes/theme.tres,common/fonts/*'
INCLUDE_FILTER+=',prototypes/tentacle_crawler/actors/crawler/*'
INCLUDE_FILTER+=',prototypes/tentacle_crawler/components/probe/*'
INCLUDE_FILTER+=',prototypes/tentacle_crawler/components/rig/*'
INCLUDE_FILTER+=',prototypes/tentacle_crawler/components/tentacle/*'
INCLUDE_FILTER+=',prototypes/tentacle_crawler/assets/models/*'
INCLUDE_FILTER+=',prototypes/tentacle_crawler/assets/audio/sfx_tentacle_thud_*'
INCLUDE_FILTER+=',prototypes/tentacle_crawler/data/*'
INCLUDE_FILTER+=',prototypes/tentacle_crawler/materials/anchor_pad.tres'
INCLUDE_FILTER+=',prototypes/tentacle_crawler/materials/corridor_floor.tres'
INCLUDE_FILTER+=',prototypes/tentacle_crawler/materials/corridor_wall.tres'
INCLUDE_FILTER+=',prototypes/tentacle_crawler_chaser/multiplayer_chase_*'
INCLUDE_FILTER+=',prototypes/tentacle_crawler_chaser/tentacle_crawler_multiplayer_demo.*'
INCLUDE_FILTER+=',prototypes/tentacle_crawler_chaser/chase_knobs.gd'
INCLUDE_FILTER+=',prototypes/tentacle_crawler_chaser/creature_contact.gd'
INCLUDE_FILTER+=',prototypes/object_carrying/carry_knobs.gd'

if ! command -v "${GODOT_BIN}" >/dev/null 2>&1; then
	echo "Godot executable not found: ${GODOT_BIN}" >&2
	exit 1
fi

PROJECT_BACKUP="$(mktemp "${TMPDIR:-/tmp}/crawler-mp-project.XXXXXX")"
PROJECT_REWRITE="$(mktemp "${TMPDIR:-/tmp}/crawler-mp-project-rewrite.XXXXXX")"
EXPORT_PRESETS_BACKUP="$(mktemp "${TMPDIR:-/tmp}/crawler-mp-presets.XXXXXX")"
EXPORT_PRESETS_REWRITE="$(mktemp "${TMPDIR:-/tmp}/crawler-mp-presets-rewrite.XXXXXX")"

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

# These production globals are unused by the isolated proof. In particular,
# SceneManager eagerly loads the main game and would pull its dependency graph
# back into an otherwise narrow demo export.
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

# Include script folders explicitly. Godot's selected-scene filter follows
# scene resources but not every class_name reference made only from GDScript.
# The explicit list keeps that dependency closure complete without packing all
# unrelated jam prototypes. Single-threaded Web remains the most portable itch
# and ordinary-static-host configuration; this demo has no GDExtensions.
awk -v scene="${DEMO_SCENE}" -v includes="${INCLUDE_FILTER}" '
	/^\[preset\.0\]$/ {
		in_web = 1
		print
		next
	}
	/^\[preset\.1\]$/ {
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
echo "Exporting the tentacle crawler multiplayer demo to ${OUTPUT_DIR}"
"${GODOT_BIN}" \
	--headless \
	--path "${GAME_DIR}" \
	--export-release "Web" \
	"releases/tentacle-crawler-multiplayer-demo-web/index.html"
echo "Done. Serve ${OUTPUT_DIR} over HTTP and open it in two browsers."

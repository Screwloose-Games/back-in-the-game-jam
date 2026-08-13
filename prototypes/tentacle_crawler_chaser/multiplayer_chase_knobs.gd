class_name MultiplayerChaseKnobs
extends RefCounted

## Defaults unique to the small multiplayer chase proof.
##
## The original chaser is a large navigation experiment. This companion keeps
## its network proof deliberately small: one straight, static corridor with no
## runtime CSG or navmesh bake.

const ARENA_WIDTH := 10.0
const ARENA_LENGTH := 72.0
const WALL_THICKNESS := 1.0

const HOST_SPAWN := Vector3(-1.5, 0.0, 14.0)
const CLIENT_SPAWN := Vector3(1.5, 0.0, 14.0)
const CRAWLER_SPAWN := Vector3(0.0, 0.0, 31.0)
const EXTRACTION_Z := -30.0

const PLAYER_MAX_TURN_RATE := 8.0
## Slightly faster than a survivor's 4 m/s ceiling, but starting far enough
## behind that a clean run still wins. Hesitation makes the catch/reset path a
## real part of the demo instead of something testers must stage deliberately.
const CRAWLER_MAX_SPEED := 4.5
const CRAWLER_CATCH_RADIUS := 2.25
const TARGET_SWITCH_MARGIN := 1.5
const CRAWLER_STATE_INTERVAL := 0.05
const PLAYER_STATE_INTERVAL := 0.05
const PLAYER_INPUT_INTERVAL := 0.0333333

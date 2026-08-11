class_name CoreLoopHud
extends CanvasLayer

## The readout, and the monster's debug block.
##
## THE MONSTER BLOCK IS THE POINT OF THIS FILE. Everything else here is a number
## you could feel without being told - you know your lamp is dying because it is
## dying. The creature is different: it hunts by sound, from off screen, and every
## interesting thing it does happens where you cannot see it. Without a readout,
## "it never came" and "it came, lost you, and left" look identical, and so do "it
## is hunting your last noise" and "it has you".
##
## So the block prints the state machine directly: which state, how far away it
## is, how long the chase has left, how long it has been since it heard anything,
## and what the last noise was. That is the difference between tuning the numbers
## and guessing at them.

const REFRESH_INTERVAL := 0.1

const CONTROL_LEGEND := (
	"WASD/space/ctrl thrust   Q/E roll   shift sprint   R stabilise\n"
	+ "LMB drill   F grip   T tether   C crank   TAB reset   ESC mouse"
)

## Warm when the creature is only hunting, hot when it has you.
const HUNTING_COLOR := Color(1.0, 0.78, 0.35, 0.95)
const CHASING_COLOR := Color(1.0, 0.36, 0.30, 1.0)
const DORMANT_COLOR := Color(0.55, 0.62, 0.70, 0.7)

var _suit: CoreLoopSuit
var _beam: CoreLoopDrillBeam
var _power: CoreLoopPowerSystem
var _suit_store: PowerStore
var _cube_store: PowerStore
var _noise: CoreLoopNoise
var _director: MonsterDirector

var _collected := 0
var _total := 0
var _elapsed := 0.0

@onready var _readout: Label = $Readout
@onready var _monster: Label = $Monster
@onready var _suit_bar: PowerBar = $SuitPower


func _process(delta: float) -> void:
	if _suit == null:
		return
	_suit_bar.set_charging(_power.is_charging())
	_elapsed += delta
	if _elapsed < REFRESH_INTERVAL:
		return
	_elapsed = 0.0
	_readout.text = _build_readout()
	_write_monster_block()


## Holds the objects rather than the prototype root, which is what stops this and
## CoreLoopPrototype depending on each other's types.
func bind(
	suit: CoreLoopSuit,
	beam: CoreLoopDrillBeam,
	power: CoreLoopPowerSystem,
	suit_store: PowerStore,
	cube_store: PowerStore,
	noise: CoreLoopNoise,
	director: MonsterDirector
) -> void:
	_suit = suit
	_beam = beam
	_power = power
	_suit_store = suit_store
	_cube_store = cube_store
	_noise = noise
	_director = director
	_suit_store.charge_changed.connect(_suit_bar.show_fraction)
	_suit_bar.show_fraction(_suit_store.get_fraction())


func set_score(collected: int, total: int) -> void:
	_collected = collected
	_total = total


func _build_readout() -> String:
	var lines := PackedStringArray()
	lines.append("crystals  %d / %d" % [_collected, _total])
	(
		lines
		. append(
			(
				"suit      %3.0f%%%s"
				% [
					_suit_store.get_fraction() * 100.0,
					"   CHARGING" if _power.is_charging() else "",
				]
			)
		)
	)
	(
		lines
		. append(
			(
				"cube      %3.0f%%%s"
				% [
					_cube_store.get_fraction() * 100.0,
					"   CRANKING" if _power.is_cranking() else "",
				]
			)
		)
	)
	if not _beam.has_power():
		lines.append("drill     FLAT - no charge to cut with")
	lines.append("speed     %.1f m/s%s" % [_suit.get_drift_speed(), _sprint_note()])
	lines.append("depth     %.0f m" % -_suit.global_position.y)
	lines.append("noise     %s" % _noise.describe())
	lines.append("")
	lines.append(CONTROL_LEGEND)
	return "\n".join(lines)


func _sprint_note() -> String:
	if _suit.sprint_engaged:
		return "   SPRINT"
	if _suit.stabilizers_engaged:
		return "   STABILISING"
	return ""


## The block the whole file exists for. Colour carries the state as well as the
## word, because the one thing you need at a glance while flying is whether it has
## you or is merely looking.
func _write_monster_block() -> void:
	var state := _director.debug_state()
	var name_of: String = state["state"]

	if not _director.is_spawned():
		_monster.add_theme_color_override("font_color", DORMANT_COLOR)
		_monster.text = "MONSTER  not spawned\nlast noise  %s" % _noise.describe()
		return

	var is_chasing := name_of == "chasing"
	_monster.add_theme_color_override("font_color", CHASING_COLOR if is_chasing else HUNTING_COLOR)

	var lines := PackedStringArray()
	lines.append("MONSTER  %s" % name_of.to_upper())
	lines.append("distance    %.0f m" % state["distance"])
	if is_chasing:
		lines.append("chase ends  %.1f s" % state["chase_left"])
	else:
		lines.append("gives up in %.0f s" % (_director.despawn_silence - float(state["silence"])))
	lines.append("heard       %s" % _noise.describe())
	lines.append("came from   %.0f m away" % state["spawn_path"])
	_monster.text = "\n".join(lines)

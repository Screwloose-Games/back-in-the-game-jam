class_name LoadingScreen
extends CanvasLayer

## The screen between pressing Start and the level arriving.
##
## Knows nothing about loading: it is handed a fraction and draws it, and whoever put
## it up decides when it goes away.

## Seconds a line of flavour text stays up. Short enough that a player watching it can
## tell the game is still running, long enough to read.
const LINE_SECONDS := 2.0

## How fast the bar chases the real number, in bar-fractions per second. ResourceLoader
## reports progress a dependency at a time, and a bar that teleports reads as broken.
const BAR_CATCHUP := 1.5

## Seconds a full bar is held before the screen goes away.
const HOLD_SECONDS := 0.2

const LINES: PackedStringArray = [
	"Loading level",
	"Loading scary creature",
	"Loading Alien AI pathing",
	"Stirring up trouble",
	"Clearing the dust",
	"Adding nightmare fuel",
	"Pressurising the airlock",
	"Counting what is left of the oxygen",
	"Teaching the dark to move",
	"Sharpening the drill bits",
]

var _target := 0.0
var _shown := 0.0
var _order: Array[int] = []
var _line := 0
var _since_line := 0.0

@onready var _flavour_label: Label = %FlavourLabel
@onready var _bar: ProgressBar = %ProgressBar
@onready var _percent_label: Label = %PercentLabel


func _ready() -> void:
	_order = shuffled_order(LINES.size())
	_show_line()


func _process(delta: float) -> void:
	_shown = advance(_shown, _target, delta)
	_bar.value = _shown
	_percent_label.text = "%d%%" % roundi(_shown * 100.0)
	_since_line += delta
	if _since_line >= LINE_SECONDS:
		_line = (_line + 1) % maxi(_order.size(), 1)
		_show_line()


## Where the bar is told to go. Anything outside 0..1 is clamped rather than refused.
func set_progress(ratio: float) -> void:
	_target = clampf(ratio, 0.0, 1.0)


## Fills the bar and holds it there long enough to be read.
##
## Snapped rather than eased: the easing exists to smooth out the steps ResourceLoader
## reports, and a load that finishes before the bar catches up would otherwise have the
## bar vanish half full, which reads as giving up rather than as finishing.
func complete() -> void:
	_target = 1.0
	_shown = 1.0
	_bar.value = 1.0
	_percent_label.text = "100%"
	await get_tree().create_timer(HOLD_SECONDS).timeout


## Where the bar draws this frame.
##
## Static and pure so the easing can be checked without building a scene. Never goes
## backwards, and snaps rather than crawling after a frame long enough that easing
## would itself look like a stall.
static func advance(shown: float, target: float, delta: float) -> float:
	var goal := clampf(target, 0.0, 1.0)
	if goal <= shown:
		return shown
	return minf(shown + BAR_CATCHUP * delta, goal)


## Indices into LINES in a random order, so a wait long enough to show every line shows
## each of them once rather than repeating a favourite.
static func shuffled_order(count: int) -> Array[int]:
	var order: Array[int] = []
	for index: int in count:
		order.append(index)
	order.shuffle()
	return order


func _show_line() -> void:
	_since_line = 0.0
	if _order.is_empty():
		return
	_flavour_label.text = "%s..." % LINES[_order[_line]]

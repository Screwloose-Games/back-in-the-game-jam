---
paths:
    - "**/*.gd"
---

# GDScript file layout

Every `.gd` file declares things in this order. This is not style preference —
`gdlint` enforces it via `class-definitions-order` in `gdlintrc`, and anything out
of order fails the pre-commit hook and CI.

1. `@tool`
2. `class_name`
3. `extends`
4. Docstring comment
5. `signal`
6. `enum`
7. `const`
8. `static var`
9. `@export var`
10. Public `var`
11. Private `var` (`_name`)
12. `@onready` public var
13. `@onready` private var
14. Everything else (functions, inner classes)

Two things that trip people up:

- **`class_name` goes above `extends`**, not below. Both orders run fine in Godot 4,
  only one passes the linter.
- **`@onready` vars go last, below plain `var`s** — not next to the exports they
  relate to. Their assignments run at `_ready()` regardless of source position, so
  moving them is safe unless a plain `var` initializer references one.

```gdscript
class_name SoundEffectConnector
extends Node

enum TryConnectError {
	INSTANCE_INVALID = 49,
}

@export var sound_effect: AudioStream

var try_connect_start_result: int = FAILED

@onready var sound_manager = get_parent()


func _ready() -> void:
	pass
```

Blank lines: two before each function, one between logical blocks. `gdformat` owns
this — don't hand-tune it.

## Indentation: tabs, always

`gdformat` emits tabs and has no option not to, so tabs are not a preference here
-- they are the only thing that passes `gdformat --check` in the commit hook and
in CI. Never write a `.gd` file indented with spaces, in any tool.

The trap is the Godot script editor. `text_editor/behavior/files/convert_indent_on_save`
defaults to on and rewrites the indentation of the **whole file** on every save,
so an editor whose `text_editor/behavior/indent/type` is set to Spaces silently
reformats every script it touches. `gdformat` converts it straight back, and the
file then flips between tabs and spaces from commit to commit -- which is exactly
what happened to `common/ui/main_menu/main_menu.gd`.

`addons/repo_hooks` sets `indent/type` back to Tabs when the project is opened,
so that is handled. `.editorconfig` is not enough on its own: Godot never reads
it. Neither is `.gitattributes`, which normalizes line endings and cannot touch
indentation.

## Checking your work

```bash
gdlint  <file>          # ordering + naming
gdformat --check <file> # formatting; drop --check to rewrite in place
gdformat --diff  <file> # preview what it would change
pre-commit run          # both, on staged files (what the commit hook runs)
```

`addons/` is third-party and excluded everywhere — `gdlintrc`, `gdformatrc`,
`.pre-commit-config.yaml`, and CI. Don't lint or reformat it.

`prototypes/` is **not** excluded. It is exempt from the naming and structural
conventions, but `gdformat` and `gdlint` still gate it like anything else.

Note: `excluded_directories` in `gdlintrc`/`gdformatrc` is ignored when you pass
explicit file paths, so running `gdlint addons/some_file.gd` by hand will report
errors that nothing actually enforces.

## Comments

- Include 1-3 sentences of docstring at the top of the file.
- Include a maximum of 1 sentence docstring per function. Prefer no docstring and
  instead, make the function name expressive and concise.

extends Node

# levels / menus
signal changed_level
signal title_screen_started
signal credits_screen_started
signal level_started
signal level_reset
## The crew met quota and asked the elevator to leave. One event per run, which is what
## this bus is for; the level decides what happens next.
signal level_exit_requested
signal game_paused
signal game_unpaused

# UI
signal ui_button_pressed
signal ui_button_hovered

class_name MenuBackdropLayer
extends CanvasLayer
## Persistent backdrop for all non-game UI screens.
##
## This is registered as an autoload, so the expensive MenuBackground
## SubViewport and its level geometry survive scene changes instead of being
## rebuilt by each menu scene. Individual menu scenes stay transparent and just
## ask this singleton to show/hide behind them.

const MENU_LAYER := -100
const DEFAULT_DIM := Color(0.04, 0.08, 0.10, 0.56)
const BASE_COLOR := Color(0.1, 0.14, 0.18, 1.0)

var _root: Control
var _base: ColorRect
var _background: MenuBackground
var _dim: ColorRect

func _ready() -> void:
    layer = MENU_LAYER
    _build()
    hide_for_game()

func show_for_menu(dim_color: Color = DEFAULT_DIM) -> void:
    visible = true
    _dim.color = dim_color
    if _background != null:
        _background.set_active(true)

func hide_for_game() -> void:
    visible = false
    if _background != null:
        _background.set_active(false)

func _build() -> void:
    _root = Control.new()
    _root.name = "Root"
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_root)

    _base = ColorRect.new()
    _base.name = "Base"
    _base.color = BASE_COLOR
    _base.set_anchors_preset(Control.PRESET_FULL_RECT)
    _base.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_base)

    _background = MenuBackground.new()
    _background.name = "Background"
    _background.set_anchors_preset(Control.PRESET_FULL_RECT)
    _background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_background)

    _dim = ColorRect.new()
    _dim.name = "Dim"
    _dim.color = DEFAULT_DIM
    _dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    _dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_dim)

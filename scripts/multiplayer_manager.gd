extends Node
## Autoload singleton placeholder for multiplayer functionality.
##
## This is registered as the `MultiplayerManager` autoload in project.godot.
## It currently holds no networking logic — it exists so the autoload resolves
## cleanly at launch. Multiplayer session handling (matchmaking, peer sync,
## highscore exchange) will be built out here later.

func _ready() -> void:
    pass

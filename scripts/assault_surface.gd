extends StaticBody3D
## Per-texture brush collider routes damage to its owning original brush.
var brush

func receive_damage(damage: float) -> void:
	brush.receive_damage(damage)

extends "res://scripts/remote_sync.gd"


# Test-only override: the companion HttpApi autoload is replaced with an
# in-memory fixture before this script is attached, so no network is available.
func _remote_writes_blocked() -> bool:
	return false

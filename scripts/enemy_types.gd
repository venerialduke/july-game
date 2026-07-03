class_name EnemyTypes
## Enemy archetype table — THE place to tune enemy identity. Speeds are
## multipliers on the Leader's slow walk (leader sprint = 2.0), so a
## hunter at 1.15 outpaces a walking Leader but loses to a sprinter:
## escaping costs stamina.
##
## aggro_radius: acquires the Leader within this hex distance (0 = never).
## leash_range:  hunter gives up beyond this distance from the Leader;
##               brute abandons a chase beyond this distance from home.
## repath_interval / wander_interval: seconds between AI decisions.

const TABLE: Dictionary[StringName, Dictionary] = {
	&"drifter": {
		"speed_mult": 0.4, "hp": 30.0, "power": 6.0,
		"aggro_radius": 0, "leash_range": 0,
		"repath_interval": 2.0, "wander_interval": 4.0, "wander_radius": 2,
	},
	&"brute": {
		"speed_mult": 0.6, "hp": 130.0, "power": 20.0,
		"aggro_radius": 2, "leash_range": 4,
		"repath_interval": 1.5, "wander_interval": 5.0, "wander_radius": 2,
	},
	&"hunter": {
		"speed_mult": 1.15, "hp": 50.0, "power": 10.0,
		"aggro_radius": 5, "leash_range": 9,
		"repath_interval": 1.0, "wander_interval": 3.0, "wander_radius": 2,
	},
}


static func stats(archetype: StringName) -> Dictionary:
	return TABLE.get(archetype, {})

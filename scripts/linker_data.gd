class_name LinkerData
extends RefCounted
## Plain data for one linker: an object that lives on a tile, spins on the
## global tick clock, and beams a transient effect onto an adjacent tile.
## The integer orientation is the gameplay truth; visuals may lerp for juice
## but logic reads the int only.

enum Type {
	TRANSMUTE,   ## Beam temporarily overrides host + neighbor tile type.
	CONNECTOR,   ## Beam makes the host->neighbor edge passable/cheap while active.
}

var id: int = -1                ## Assigned by MapSim.add_linker().
var host_coord: Vector2i        ## Tile the linker lives on.
var orientation: int = 0        ## 0..5, logical truth. 60-degree steps.
var period: int = 1             ## Steps every `period` ticks (1 fast .. N slow).
var phase_offset: int = 0       ## 0..period-1, staggers same-period linkers.
var spin_dir: int = 1           ## +1 or -1. Reverse tool flips this.
var frozen: bool = false        ## Freeze tool. Frozen linkers skip ticks.
var type: Type = Type.CONNECTOR
var links: Array[int] = [0]     ## Logical edges. A link at logical edge e points
                                ## across physical direction (e + orientation) % 6.


func _init(p_host: Vector2i, p_type: Type, p_period: int = 1,
		p_phase: int = 0, p_orientation: int = 0) -> void:
	host_coord = p_host
	type = p_type
	period = p_period
	phase_offset = p_phase
	orientation = p_orientation

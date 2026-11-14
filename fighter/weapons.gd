class_name Weapons
## Shared weapon table (contract). Slots: 0 primary, 1 secondary, 2 consumable, 3 throwable.
## recoil = pitch kick (rad) per shot; ads_spread = spread multiplier while aiming; ads_fov = camera fov while aiming.
## model = first-person GLB (null = procedural); char_node = weapon node to show in the character GLB hand.

const PRIMARIES := ["rifle", "shotgun"]
const HEADSHOT_MULT := 2.0
const HEAD_HEIGHT := 1.45  # hit point y above the target's feet that counts as a headshot
const DATA := {
	"rifle": {"name": "Rifle", "slot": 0, "damage": 18, "pellets": 1, "fire_rate": 0.1, "mag": 30, "reserve": 120, "reload_time": 2.0, "spread": 0.015, "auto": true, "range": 150.0, "recoil": 0.012, "ads_spread": 0.3, "ads_fov": 50.0, "model": "res://assets/models/ak.glb", "char_node": "AK"},
	"shotgun": {"name": "Escopeta", "slot": 0, "damage": 12, "pellets": 8, "fire_rate": 0.8, "mag": 6, "reserve": 30, "reload_time": 2.5, "spread": 0.08, "auto": false, "range": 40.0, "recoil": 0.06, "ads_spread": 0.7, "ads_fov": 65.0, "model": "res://assets/models/shotgun.glb", "char_node": "Shotgun"},
	"pistol": {"name": "Pistola", "slot": 1, "damage": 25, "pellets": 1, "fire_rate": 0.3, "mag": 12, "reserve": 48, "reload_time": 1.5, "spread": 0.01, "auto": false, "range": 100.0, "recoil": 0.025, "ads_spread": 0.4, "ads_fov": 60.0, "model": "res://assets/models/pistol.glb", "char_node": "Pistol"},
	"medkit": {"name": "Botiquín", "slot": 2, "heal": 50, "count": 2, "use_time": 1.0, "model": null, "char_node": ""},
	"grenade": {"name": "Granada", "slot": 3, "damage": 100, "radius": 5.0, "fuse": 2.5, "count": 2, "throw_speed": 15.0, "model": "res://assets/models/grenade.glb", "char_node": ""},
}


## Upper bound for one shot's summed damage incl. headshots; host uses it to reject forged damage requests.
static func max_shot_damage() -> int:
	var m := 0
	for w in DATA.values():
		if w.has("pellets"):
			m = maxi(m, w.damage * w.pellets)
	return int(m * HEADSHOT_MULT)

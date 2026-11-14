# Short Fights — project memory & contract

Godot **4.7.2**, GDScript only, renderer `mobile`. Editor exe: `C:/Users/ROX/Desktop/Godot.exe` (override with env `GODOT`; check.sh exits 2 if missing).
FPS, max 2 humans over LAN (ENet, host/join by IP) + bots. Modes: TEAMS (same bots per team) / FFA. 3 untextured maps. PC + iPhone (touch).
UI text in Spanish. Workflow/method: `.claude/skills/godot-token-efficient-engineering/SKILL.md`.

## Verify
- `tools/check.sh` (~20 s) — import, menu, 3 headless offline matches (every map, both modes). Prints errors, spawn lines, kill counts. Kills > 0 = AI, hitscan, damage, respawn work.
- `tools/check.sh net` (+~30 s) — adds LAN test on 127.0.0.1: host + client match, asserts a 3rd human is refused.
- Visual: `Godot.exe --path . --resolution 960x540 --fixed-fps 30 --quit-after 45 --write-movie <scratch>/f.png res://match/match.tscn -- --map=N`, then view the last PNG.
- Test hooks (user args after `--`): `--map=N --bots=N --ffa --difficulty=N --primary=ID --host --join=IP` (Game._ready), `--test-aim` (local fighter always aims; ADS frames).
- Gotcha: `godot --check-only --script` doesn't load autoloads => false "Identifier not found: Game". Don't use it.
- Gotcha: `--fixed-fps` disables real-time; network tests must use `--max-fps` instead.
- No export templates installed locally. iOS: `.github/workflows/ios-unsigned.yml` (macos-15 runner, Godot export_project_only + xcodebuild CODE_SIGNING_ALLOWED=NO) => artifact ShortFights-unsigned.ipa, user re-signs with Sideloader. Not run yet; GODOT_TAG there must match the editor version.

## Files (owner = who may edit during a build wave)
| File | Role |
|---|---|
| project.godot, *.tscn, fighter/weapons.gd, CLAUDE.md | orchestrator-owned contract |
| autoload/game.gd | `Game` autoload: config, LAN, input map, shared helpers |
| ui/main_menu.gd | menu (built in code) on `ui/main_menu.tscn` (root Control) |
| match/match.gd | `/root/Match` (Node3D, children `Fighters`, `Projectiles`). Host-authoritative rules |
| match/maps.gd | `class_name Maps`, 3 map layouts built in code |
| fighter/fighter.gd | `class_name Fighter extends CharacterBody3D`, builds itself in code (no .tscn) |
| fighter/bot_ai.gd | `class_name BotAI extends RefCounted` |
| fighter/grenade.gd | `class_name Grenade extends RigidBody3D` |
| ui/hud.gd | `class_name Hud extends CanvasLayer`, group `hud` |
| ui/touch_controls.gd | `class_name TouchControls extends Control` |

Replace placeholder visuals later: Fighter `_build_body()` and weapon meshes (CC0 GLB from Kenney/Quaternius into `assets/`).

## Conventions
- Tabs, static typing where cheap, no new scenes (build nodes in code), no addons.
- Physics layers: 1 world, 2 fighters, 3 grenades (value 4). Ray mask for shots: 1|2 = 3.
- Groups: `match` (Match), `fighters` (each Fighter), `hud` (Hud).
- Cross-file calls on Match/Hud are via `get_tree().get_first_node_in_group(...)` (untyped) so files parse independently.
- Offline play = default OfflineMultiplayerPeer: `multiplayer.is_server()` is true and `rpc()` with call_local runs locally.

## Game (autoload/game.gd)
```
const PORT := 7777; const MAX_HUMANS := 2; const MAX_HEALTH := 100; const RESPAWN_TIME := 3.0
const MOUSE_SENS := 0.0025            # rad per mouse pixel
const TEAM_COLORS := [Color(0.2,0.45,1), Color(1,0.3,0.25), Color(0.3,0.9,0.3), Color(1,0.85,0.2), Color(0.8,0.4,1), Color(0.2,0.9,0.9), Color(1,0.6,0.2), Color(0.9,0.9,0.9)]
enum Mode { TEAMS, FFA }
var config := {"mode": Mode.TEAMS, "bots": 2, "map": 0, "kill_limit": 15}   # bots = per team (TEAMS) or total (FFA)
var loadouts := {}                    # peer_id(int) -> primary id ("rifle"/"shotgun"); missing => "rifle"
var touch_look := Vector2.ZERO        # radians; TouchControls adds, local Fighter consumes & zeroes
var ready_peers := {}                 # host: peer_id -> true once its Match scene loaded
var last_message := ""                # shown by menu after returning (e.g. "El host se desconectó")
signal peers_changed                  # lobby peer list changed
signal peer_ready(id: int)
func team_color(team: int) -> Color   # TEAM_COLORS[team % size]
func are_enemies(a: int, b: int) -> bool   # a != b
func humans() -> Array                # host: [1] + multiplayer.get_peers()
func host() -> Error; func join(ip: String) -> Error; func leave()   # leave: close peer, Offline peer, mouse visible, go to menu
func start_match()                    # host only: _load_match.rpc(config, loadouts)
@rpc("authority","call_local","reliable") func _load_match(cfg: Dictionary, lo: Dictionary)  # set config/loadouts, clear ready_peers, change_scene_to_file("res://match/match.tscn")
@rpc("any_peer","call_local","reliable") func _peer_ready()   # host records sender (0 => 1), emits peer_ready
@rpc("any_peer","reliable") func _set_loadout(primary: String) # client -> host, validated against Weapons.PRIMARIES
```
`_ready` registers input actions in code (InputMap.add_action if missing): move_forward W/Up, move_back S/Down, move_left A/Left, move_right D/Right, jump Space, fire LMB, reload R, slot_1..slot_4 keys 1-4, next_weapon Q + wheel down.
Host refuses a 3rd human (disconnect_peer) and anyone joining mid-match. Client `server_disconnected` => last_message + leave().

## Match (match/match.gd, root of match.tscn, group `match`)
- `_ready`: `Maps.build(self, Game.config.map)`; add Hud (`Hud.new()`); if touch (`DisplayServer.is_touchscreen_available()` or `"--touch" in OS.get_cmdline_user_args()`) add `TouchControls.new()` as child of the Hud. Then `Game._peer_ready.rpc_id(1)`. Host: when every id in `Game.humans()` is in `Game.ready_peers` => spawn all once and `print("[match] spawned %d fighters" % n)`.
- Teams: TEAMS: host team 0 (spawns_a), client team 1 (spawns_b), `bots` bots on each team. FFA: every fighter its own team 0..n-1, spawns from a+b. Names: humans `"H%d" % peer_id`, bots `"B%d" % i`. Display: "Jugador 1" (host), "Jugador 2", "Bot N".
- Click captures mouse (non-touch); `ui_cancel`: captured => visible, else => `Game.leave()`.
- Host handles `multiplayer.peer_disconnected` => free that human's fighter.
- RPCs (all `"reliable"`; host->all are `"authority","call_local"`):
  - `_spawn(fname, display, team, peer_id, is_bot, primary, pos)`: `Fighter.new()`, set fields + name, `set_multiplayer_authority(1 if is_bot else peer_id)`, add to `$Fighters`, set global_position.
  - `_set_state(fname, health, alive)`: `f.health = health; f.set_alive(alive)`.
  - `_respawn(fname, pos)`: `f.respawn(pos)`. `_set_score(text)`: hud.set_score. `_feed(text)`: hud.show_message(text, 2.0) + print("[match] ", text). `_end(text)`: hud.show_message(text, 0); after 5 s `Game.leave()`.
  - `request_damage(target, amount, attacker)` `"any_peer","call_local"`: host only; reject unless sender (0 => 1) is attacker's authority and `amount <= Weapons.max_shot_damage()`.
  - `request_heal(target, amount)` `"any_peer","call_local"`: host only; sender must own target; amount <= medkit heal.
  - `spawn_grenade(pos, vel, thrower)` `"any_peer","call_local"`: every peer adds `Grenade.new()` to `$Projectiles`, `g.setup(pos, vel, thrower)`.
- `apply_explosion(pos, thrower)` (host, plain call from Grenade): linear falloff `damage*(1-d/radius)` to alive enemies of thrower in radius.
- Host damage rule: only alive targets that are enemies of attacker (no self/friendly fire). health<=0 => alive false, score (TEAMS: per team; FFA: per fighter), `_feed("A eliminó a B")`, `_set_score` text, respawn after RESPAWN_TIME at a random spawn of its side, `_end("Gana …")` at kill_limit.

## Fighter (fighter/fighter.gd)
- Fields set before add_child: `team:int, peer_id:int, is_bot:bool, primary:String="rifle", display_name:String`. State: `health:int` (setter updates Hud if local), `alive:bool`, `yaw`, `pitch`, `slot:int` 0-3.
- API: `set_alive(v)` (hide, disable collision/process when dead; local shows "Reapareces…"), `respawn(pos)` (full health/ammo/counts, alive), `is_local() -> bool` (= !is_bot and peer_id == multiplayer.get_unique_id()), `head: Node3D` (eye at 1.6 m).
- `_enter_tree`: add to group `fighters`. Collision layer 2, mask 1|2. Camera3D current only if is_local().
- Only the authority simulates: builds an **intent** each physics frame, applies it, then after 0.5 s alive sends `_sync.rpc(global_position, yaw, pitch, slot)` (`"authority","unreliable_ordered"`); others apply it.
- Intent dict (human from Input/mouse/Game.touch_look; bot from `BotAI.think(self, delta)`): `{move: Vector2 (x right+, y forward+), look: Vector2 (rad yaw,pitch deltas), jump, fire (held), reload, slot (-1 or 0-3), next}`.
- Weapons per Weapons.DATA, slots `[primary, "pistol", "medkit", "grenade"]`. Gun: hitscan from head with spread/pellets, sum damage per target per shot => `match.request_damage.rpc_id(1, target.name, dmg, name)`; local hit => `hud.flash_hit()`. Medkit: fire press, after use_time => `request_heal.rpc_id(1, name, heal)`. Grenade: fire press => `match.spawn_grenade.rpc(head pos + forward*0.6, forward*throw_speed + velocity + Vector3.UP*2, name)`.
- Local Hud updates: `set_health`, `set_weapon(name, ammo_text)`.

## Grenade (fighter/grenade.gd)
`setup(pos, vel, thrower)`; sphere r 0.12, layer 4, mask 1; after fuse: if `multiplayer.is_server()` => `match.apply_explosion(global_position, thrower)`; brief orange sphere flash on all peers; free.

## Hud (ui/hud.gd)
`set_health(v:int)`, `set_weapon(name:String, ammo_text:String)`, `set_score(text:String)`, `show_message(text:String, seconds:float)` (0 = stays), `flash_hit()` (crosshair red 0.1 s). Crosshair center, health bottom-left, weapon bottom-right, score top-center.

## TouchControls (ui/touch_controls.gd)
Full-rect, draws itself. Sets `Input.emulate_mouse_from_touch = false` in _ready, restores in _exit_tree. Left half: virtual joystick => `Input.action_press("move_*", strength)`. Right half drag => `Game.touch_look += relative * 0.005`. Hold buttons (right side): fire, jump, reload, next_weapon (action_press/release). Small exit button top-left => `Game.leave()`. Multitouch by finger index.

## Maps (match/maps.gd)
`const NAMES := ["Almacén", "Patio", "Torres"]`; `static func build(parent: Node3D, index: int) -> Dictionary` returns `{"spawns_a": Array[Vector3], "spawns_b": Array[Vector3]}` (>= 6 each, y = 1). Adds StaticBody3D boxes (BoxMesh + BoxShape3D, plain colored StandardMaterial3D, layer 1), outer walls, DirectionalLight3D with shadows, WorldEnvironment (plain color background + ambient).

## Known limits (verified/assumed)
- Host trusts client positions (LAN friends). Sounds are synthesized (autoload/sfx.gd), not sampled; never listened to by Claude.
- Lobby cap is enforced by ENet max clients (MAX_HUMANS-1) + `refuse_new_connections` during a match; kicking after connect leaves a half-open peer that spams ENet errors (verified).
- Fighter.respawn() faces the origin, so maps must stay centered on (0,0,0).
- Verified v2: models/anims render (movie frames), navmesh bakes (95-183 polys), bots kill on all maps, headshots occur (hard: ~70% of kills), LAN host+client OK.
- Exit warning "ObjectDB instances leaked" = AudioStreamPlaybackWAV still playing when `--quit-after` kills the run (dummy audio). Not a runtime leak; ignore.
- Model facts: character GLBs face +Z, ~2.0 m tall => FighterModel scales to 1.8 m and rotates PI. Weapon GLBs barrel at -X => ViewModel rotates -90° Y. Nav cell_height 0.2 (0.25 warns).
- Not verified: touch controls on a real device, how the sounds feel, iOS export (needs Mac), Windows export (needs templates).

# Contract v2 (wave 2: models, audio, FX, aim, smarter bots)
New files (implemented in wave 2): autoload/sfx.gd (`Sfx` autoload), fighter/fx.gd, fighter/fighter_model.gd, fighter/view_model.gd, match/nav.gd.
Orchestrator already did: Weapons fields `recoil, ads_spread, ads_fov, model, char_node`, `HEADSHOT_MULT=2.0`, `HEAD_HEIGHT=1.45`; Game actions `aim` (RMB) + `sprint` (Shift), `config.difficulty` 0-2 (`Game.DIFFICULTIES`); menu difficulty; Match changes below.

## Assets (assets/models, CC0 Quaternius Toon Shooter, see LICENSE.txt)
- Characters soldier.glb, enemy.glb, hazmat.glb: skinned `CharacterArmature`, AnimationPlayer anims `CharacterArmature|<Name>`: Idle, Idle_Shoot, Run, Run_Gun, Jump, Jump_Idle, Jump_Land, Duck, HitReact, Death, Punch, Wave, Yes, No (+ a few more). Weapon meshes are already children of the right-hand bone, named AK, Shotgun, Pistol, Revolver, Revolver_Small, SMG, Sniper, Sniper_2, ShortCannon, GrenadeLauncher, RocketLauncher, Shovel, Knife_1, Knife_2 — show only `Weapons.DATA[id].char_node`, hide the rest.
- Weapons ak.glb, shotgun.glb, pistol.glb, grenade.glb (static meshes, vertex-color/flat materials, no textures).
- Scale/orientation unknown: measure with AABB at load and normalize (character ~1.8 m tall, facing -Z, feet at y 0).

## Sfx (autoload/sfx.gd)
`play(id: String, pos: Variant = null, volume_db := 0.0)`; pos Vector3 => AudioStreamPlayer3D at pos (pooled, auto-free), null => 2D. All sounds synthesized in code at _ready into AudioStreamWAV (no files). Ids: rifle, shotgun, pistol, reload, empty, switch, hit, headshot, kill, hurt, step, jump, land, throw, bounce, explosion, heal, death. Unknown id => no-op.

## Fx (fighter/fx.gd, static, parent = node to add effects under, use Match `Projectiles` or current_scene)
`tracer(parent, from, to)`, `muzzle(parent, pos, dir)`, `impact(parent, pos, normal, flesh)`, `explosion(parent, pos, radius)` (also `get_tree().call_group("fighters","shake", pos, 1.0)`). All unshaded, cheap (mobile), self-freeing < 1 s.

## FighterModel (fighter/fighter_model.gd, child of Fighter, origin at feet)
`setup(skin, team_color, hide_for_local)` skin 0 soldier, 1 enemy, 2 hazmat; team marker (small colored diamond ~2.2 m, hidden if hide_for_local); hide_for_local => meshes cast shadows only. `set_weapon(id)`, `set_motion(speed, on_floor, shooting)` picks Idle/Idle_Shoot/Run/Run_Gun/Jump_Idle with blend, `play_hit()`, `die()` (Death, no loop), `revive()`.
Skin choice (Fighter): TEAMS team0 soldier, team1 enemy; FFA `team % 3`.

## ViewModel (fighter/view_model.gd, child of Camera3D, local human only)
`set_weapon(id)` (GLB from Weapons.model, medkit = white box + red cross, procedural), `update(delta, aim 0..1, move_speed, on_floor)` hip<->ADS pose (centered, closer), bob, sway, `kick(amount)` recoil, `reload_anim(time)` dip, `muzzle_global() -> Vector3`. Weapon rendered so it doesn't look huge; clipping into walls accepted.

## Fighter additions (fighter/fighter.gd)
- Visuals: replace capsule/box visuals with FighterModel (everyone) + ViewModel (local). Keep capsule collision.
- Intent adds `aim: bool`, `sprint: bool`. Aim: fov lerp to `ads_fov`, spread *= `ads_spread`, sens *0.6, speed *0.6, no sprint. Sprint: speed 9, forward only, not while aiming/firing/reloading.
- Recoil: pitch += recoil per shot (+ small random yaw), ViewModel.kick. Headshot: hit y - target.global_position.y > HEAD_HEIGHT => damage *= HEADSHOT_MULT. `request_damage.rpc_id(1, target, dmg, name, headshot)`.
- Shot FX: authority calls `_shot_fx.rpc(from: Vector3, ends: PackedVector3Array, flesh: PackedByteArray, weapon: String)` `("authority","call_local","unreliable")`; all peers: Fx.muzzle, Fx.tracer per pellet, Fx.impact, Sfx.play(weapon, from), set `last_shot_ms`. Local `from` = ViewModel.muzzle_global(); remote = head pos + forward*0.6.
- Sounds: step every ~0.38 s (sprint 0.28) on floor while moving, jump, land, reload, empty, switch, heal, throw, death. Shooter hears `hit`/`headshot` (2D) on confirmed hit.
- `on_hurt(from, headshot)` (called by Match on all peers): model.play_hit(); if local: hud.damage_from(angle rad relative to view, 0 = front, + = right), Sfx "hurt", small shake. `shake(origin, strength)`: local camera trauma by distance. `last_shot_ms: int`.
- Death: model.die() + Sfx "death"; respawn: model.revive().
- Hud calls (untyped): `set_aim(bool)`, `flash_hit(headshot)`.

## Match v2 (done by orchestrator)
`request_damage(target, amount, attacker, headshot=false)` (cap = max_shot_damage(), already includes HEADSHOT_MULT). Host->all `_hurt(fname, from, headshot)` => `f.on_hurt`; `_kill(killer, victim, headshot)` => `hud.kill_feed(text)`, killer local => Sfx "kill" + `hud.show_bonus(text)`. Host calls `Nav.bake(self)` after Maps.build.

## Hud v2 (ui/hud.gd)
Add: `kill_feed(text)` (top-right stack, max 5, 5 s each), `show_bonus(text)` (small yellow under crosshair, 1.2 s), `damage_from(angle)` (red arc at screen edge toward angle, fades 1 s, several allowed), `set_aim(aiming)` (crosshair -> small dot), `flash_hit(headshot := false)` (headshot: bigger, yellow, 0.2 s), low-health red vignette when health < 35 (in set_health). Touch: APUNTAR toggle button (press/release "aim"), joystick > 0.95 strength => press "sprint".

## Nav + BotAI v2
`Nav.bake(map_root)`: NavigationRegion3D child of map_root, NavigationMesh (agent_radius 0.5, height 1.8, max_climb 0.4, max_slope 35°, cell 0.25, parsed STATIC_COLLIDERS, source = map_root children), bake synchronously. `Nav.path(world, from, to)` via NavigationServer3D.map_get_path(world.navigation_map, ...); empty => [from, to].
BotAI: follows Nav paths; difficulty (Game.config.difficulty) sets reaction (0.6/0.35/0.15 s), aim noise (0.12/0.06/0.02 rad), turn speed (3/5/8 rad/s), aims chest(easy)/chest-head(normal)/head(hard); ADS at > 15 m (normal+); hears shots (`last_shot_ms` < 1 s, < 30 m) => investigate; remembers last seen pos; retreats + heals < 35 HP; grenades at last seen pos 8-20 m when target in cover; sprints when chasing far.

# Slimebound — build 0.6: The Wilds

A Godot 4.3+ third-person co-op exploration prototype. Follow an outdoor trail from a campsite, through pine groves and uphill ridges, to the Moss Warden's summit. Slimes split to explore and gather powers, then fuse to fight.

![Actual Godot capture of the third-person summit encounter](docs/screenshots/wilds.png)

This is a **bounded outdoor level**, not a finished open-world game or a PEAK clone. It has sloped terrain and jumping, but not climbing, procedural islands, swimming, quests, save games or audio yet.

## Run the new build

1. Download the latest repository ZIP and extract it into a **fresh folder**.
2. Import `project.godot` in Godot 4.3 or newer. Allow the bundled GLB models to import.
3. Press F5. Confirm the menu says **BUILD 0.6 · THE WILDS · THIRD-PERSON CO-OP**.
4. Select **PLAY LOCAL DUNGEON — NO IP REQUIRED** for two players on one keyboard. This familiar button now starts the outdoor expedition.

## Camera and local controls

The camera stays **third-person in every form**. Separate local slimes each get a split-screen view. Fusion merges the screens and smoothly pulls the camera back to frame the larger body. Splitting restores two views. Mouse look belongs to player 1; player 2 can orbit using U/O. In the shared fused view, both mouse and U/O turn the camera. Movement is camera-relative.

| Action | Player 1 | Player 2 |
| --- | --- | --- |
| Move | WASD | Arrow keys |
| Orbit camera | Mouse | U / O |
| Jump | Space | Enter |
| Hold sprint | Shift | Ctrl |
| Attack, fused only | Left mouse | M (nearby enemy auto-aim) |
| Offer fusion | E | N |
| Split | Q | B |
| Collect nearby power, solo only | F | L |
| Release / capture mouse | Tab | Tab |
| Restart expedition | R (host) | — |
| Return to menu | Escape | Escape |

Stand close and offer fusion within three seconds of each other. Both players steer the shared body: opposing movement cancels out; an idle partner no longer reduces speed. Every member must consent to larger online fusions. Any member can split.

Space now jumps; it no longer attacks. Mouse look aims player 1's ground-following spell attacks. These are not free-aim vertical projectiles.

## Explore the route

- **Trailhead:** campsite, movement practice and three replenishing power pickups.
- **Whispering Grove:** follow the winding trail uphill and approach the ruined landmark **while fused** to begin a four-enemy encounter.
- **Sunlit Ridge:** after clearing the grove, continue to the second landmark and its six-enemy encounter.
- **Warden Summit:** after the ridge, reach the final clearing to awaken the 1,400-HP Moss Warden. It has telegraphed slams, radial volleys, summoned crawlers and a faster second phase below half health.
- **Summit arch:** defeat the Warden and enter the arch together to finish.

There are no room gates or transition teleports. You can wander and backtrack throughout the valley, but encounters activate in order and require a fused party. Three extra power caches lie off the trail. Distant mountain meshes are scenery, not additional playable regions.

Jump or move out of red ground-slam warnings. Terrain climbs 8.4 metres between trailhead and summit. Trees and landmark boulders block movement; the camera pulls in around them. Decorative foliage is non-colliding.

Defeat reforms the team at its latest active landmark, retaining powers and resetting that encounter. R resets the expedition, powers and score.

## Slime abilities

Solo slimes cannot damage enemies. Moving on the ground leaves a seven-second trail: ordinary enemies move 55% slower on it, and the Warden moves 30% slower. Solo slimes move faster and carry one power. Collecting another replaces it; pickups replenish after one second.

Fusion uses an existing animated limbed creature model, enables melee strikes and activates equipped powers. Splitting retains each player's power and health percentage; it does not heal them.

| Equipped powers | Fused effect |
| --- | --- |
| Ember | Added impact damage and burning |
| Frost | Added impact damage and slowing |
| Storm | Added impact damage and chain damage |
| Two of the same | Double elemental damage; double burn/chain damage or frost duration |
| Ember + Frost | Frostfire: burning impact and slowing splash |
| Ember + Storm | Plasma: splash and burning chains |
| Frost + Storm | Blizzard: slowing chains |
| All three, 3+ players | Tempest: burn, frost, chain and splash |

Matching powers multiply the elemental portion, not the physical base strike. No friendly fire.

## Online play

Host/Join supports up to six players on UDP **7777**. Internet play may need port forwarding; there is no relay or matchmaking. Each online player has a third-person orbit camera, including when controlling a shared fused body. The host simulates movement, powers, enemies, progression and victory. Local Dungeon never opens a server port.

## Public assets only

All model and effect art is bundled CC0 work by Kenney and Quaternius. The outdoor environment uses **Kenney Nature Kit**. Layout, asset transforms, engine material palette/roughness adjustments, standard sky, fog and lighting are configured in code. No custom artwork meshes or textures were created.

The fused form remains Quaternius's stock **Yeti**, used as a limbed stand-in—not a bespoke humanoid slime. The Warden uses **Mushroom King**. See [ASSET_CREDITS.md](ASSET_CREDITS.md) and the included license files.

## Developer checks

```sh
godot --headless --editor --import --quit
godot --headless --script res://tests/gameplay_test.gd
```

The gameplay test covers solo restrictions, trails, powers, fusion, boss phases, victory, jumping, terrain, a clear traversal route, split-screen and fused third-person framing. Godot 4.3's dummy renderer may print `mesh_get_surface_count` during resource cleanup; check the test results and exit status for failures.

For networking, run `godot --headless --script res://tests/network_test.gd -- --server`, then launch `godot --headless --script res://tests/network_test.gd` in another terminal within one second. For rendered captures, run `godot --script res://tests/visual_check.gd`; images go to `user://screenshots` unless `SLIME_SCREENSHOT_DIR` is set.

## Movement and shared levels (build 0.6)

Walking is 9 units/second solo and 7.6 fused. Hold sprint for 1.7× speed; either moving member can sprint the fused body. Acceleration and braking soften starts and stops. Camera orbit is smoothed, follows the rendered slime each frame, and retracts around obstacles with a gradual release. Online characters interpolate buffered snapshots (120 ms) rather than stepping between network updates.

The party shares XP: crawlers grant 25, brutes 45, the boss 250, new landmarks 40, and each exploration cache 35. Rewards are claimed once per expedition; ordinary power pedestals and boss summons grant no XP. Level 2 requires 100 XP, with each subsequent level costing 50 more. Each level adds 10 maximum health per slime (and heals that amount) and 12% of base fusion damage, including elemental effects. Maximum level is 10. The HUD shows level and progress to the next level.

Levels survive defeat and splitting/fusion. R starts a fresh expedition at level 1; there is no saved progression between sessions.

Additional regression test: `godot --headless --path . --script res://tests/movement_level_test.gd`.

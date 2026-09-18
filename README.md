# Slimebound — build 0.10

A Godot 4.3+ third-person co-op prototype with two connected outdoor maps. Explore as small slimes, climb to rare powers, then fuse to fight using swords, bows or elemental magic. All artwork is publicly licensed; see [ASSET_CREDITS.md](ASSET_CREDITS.md).

## Run

Download the repository ZIP into a fresh folder, import `project.godot`, and press F5. Confirm **BUILD 0.10**. Select **PLAY LOCAL DUNGEON — NO IP REQUIRED** for two players on one keyboard. Separate players get split-screen cameras; fusion merges the views. Both forms stay third-person.

Online Host/Join uses UDP 7777, up to six players. Internet play may require port forwarding; there is no relay or matchmaking. Local play opens no server port. The host controls gameplay state and progression.

## Controls

| Action | Player 1 | Player 2 (local) |
| --- | --- | --- |
| Move | WASD | Arrow keys |
| Attack while fused | Left click | M, with nearby-enemy aim assistance |
| Cycle Sword / Bow / Magic | X | J |
| Jump; release for short hop | Space | Enter |
| Sprint | Shift | Ctrl |
| Climb while solo | Hold C against a ledge and move into it | Hold period (.) and move into it |
| Offer fusion / split | E / Q | N / B |
| Collect / read / turn rune / operate lock | F | L |
| Camera turn | Mouse | U / O |
| Camera tilt | Mouse or T / G | I / K |
| Camera zoom | Mouse wheel | [ / ] |
| Capture / release mouse | Right-click / Tab | — |
| Reset view | Home | Home |
| Travel to map two after completing map one | F8, host only | — |
| Restart entire expedition / menu | R / Escape | — |

Both players must consent to fusion. Opposing movement cancels; idle partners do not halve speed. Any member can split. Each player selects their own attack style, even while sharing a body. The weapon on the model reflects the most recent attack style. The fused character now has the 90-degree facing correction.

## Three different attacks

- **Sword:** short forward cleave that can hit several enemies. Works without powers; no automatic magic projectile. Uses a public sword model and a swing animation.
- **Bow:** fast physical arrows with longer range. Works without powers and does not consume ammunition. Uses public bow and arrow models.
- **Magic:** slower elemental shots that activate the fusion’s collected powers and combinations. Requires at least one power. If none are equipped, switch to Sword or Bow.

Physical attacks benefit from party-level damage bonuses. Elemental powers affect magic and solo trails; swords and arrows do not automatically trigger elemental spells. Ranged aim remains horizontal and shots follow the terrain; this is not yet full vertical free aiming.

## Explore, climb and manage stamina

Each map has stone steps and an optional **Sky Route**: three taller terraces rising 3, 6 and 9 metres above the local ground. A rare pickup sits on the upper terrace. These surfaces support landings, walking and repeat jumps. Height-aware collisions stop movement through their sides and jumping through low roofs.

Only solo slimes climb. Approach a terrace edge, hold C / period and push toward the rock; once above its lip, move onto the surface. Rest on ledges between climbs. Releasing climb lets you fall. There is no fall damage yet.

Each body has one 100-point stamina pool shared by sprinting and climbing. Sprint uses 18 points/second, climbing 28; resting on the ground or a ledge restores 24/second. Release sprint/climb to recover. Empty stamina stops those abilities. Fusing uses the lower stamina value of the two bodies; splitting copies the remaining pool, so transformations cannot refill it. Each player’s roster entry includes a stamina bar.

## Scarce powers and leveling

The Wilds has **five** scattered pickups; Amber Ruins has **six**. There are no replenishing power stations. Finds are shared and can be collected once per expedition. Defeat does not refill them. Look along side paths and on elevated terraces. Empty slots fill first; a full inventory replaces the oldest power, so choose deliberately.

Each slime has 1/2/3/4 power slots at party levels 1/3/6/9. Duplicate powers stack. Fusion pools all members’ inventories; splitting and defeat retain them.

The party shares XP from enemies, discoveries and solving the rune lock. Level 2 costs 100 XP, with subsequent levels costing 50 more. Each level adds 10 health per slime and 12% of base fusion damage. Maximum level is 10. Levels and powers carry into map two. R resets the full expedition; there is no save system between sessions.

| Power | Solo trail | Fused magic |
| --- | --- | --- |
| Ember | Minor contact burning | Impact damage, burn and mixed-power splash |
| Frost | Allies move faster with slippery momentum | Slow |
| Storm | Small periodic shocks | Chain lightning |
| Venom, map two | Weak lingering poison | Stronger poison |
| Gale, map two | Ally speed boost and gentle enemy push | Knockback and mixed-power gust |

Trails last seven seconds. Allied speed bonuses cap at 35%; overlapping patches use the strongest stack count for each element, rather than multiplying damage by patch count. Solo slimes cannot attack directly.

**Magic combinations:** Ember + Frost = Frostfire; Ember + Storm = Plasma; Frost + Storm = Blizzard; all three = Tempest. Venom + Ember = Volatile Venom (ignition burst); Venom + Frost = Deep Chill (longer poison); Venom + Storm = Plague Arc (poison chains); Venom + Gale = Toxic Cyclone (poison gust). Gale combines with Ember/Frost/Storm as Firestorm/Squall/Thunderclap. Three or more elements involving Venom or Gale retain their effects as Prism Surge.

## Maps and the rune puzzle

**The Wilds:** Trailhead → Whispering Grove → Sunlit Ridge → Warden Summit. Activate encounters while fused, clear them, defeat the 1,800-HP Moss Warden and enter the summit arch. The host can then press F8 to reach Amber Ruins with the party’s progression intact.

**Amber Ruins:** Caravan Camp → Broken Court → Pillar Pass → Amber Sanctum. Enemies have 40% more health. The Amber Warden currently reuses the first boss’s model and attack patterns at 2,520 HP.

**The old pressure plates are removed.** After Broken Court, explore the low-roof passages as solo slimes and press F/L at each hidden inscription. Combine their clues to determine the order of three symbols. At the three column dials, F/L cycles the nearest symbol. Then regroup, fuse, and interact with the heavy lock. Incorrect orders give feedback without resetting the dials. The lock requires both inscriptions to have been read. Solving it unlocks Pillar Pass and grants 80 XP; it stays solved through defeat.

The maps are bounded authored routes with side areas, not a finished open world. There is no swimming, procedural generation, inventory screen, audio or persistence yet.

## Enemies and effects

Crawlers and mushroom brutes fight at close range. Skeletons keep distance and fire red bolts after a warning. Low-hovering bats pause before dashing. Bosses use telegraphed slams, radial volleys and summons, with a faster second phase. Jump to evade ground slams.

Magic shots have solid opaque colored bodies, with bright cores and directional tails. Enemy shots are red; bow shots use arrow models. Fusion pulls the source slimes together and pops the combined model into view; splitting sends solo models out in short hops. Transformations do not pause gameplay or change health ratios.

## Checks

```sh
godot --headless --editor --import --quit
godot --headless --script res://tests/gameplay_test.gd
godot --headless --script res://tests/combat_climb_test.gd
```

Additional regression scripts cover movement, powers, trails, camera input, traversal and transformations. `tests/network_test.gd` verifies authoritative state and travel to map two: start one instance with `-- --server`, then a second without that flag within one second. `tests/visual_check.gd` captures rendered scenes in `user://screenshots` (or `SLIME_SCREENSHOT_DIR`). Godot 4.3’s dummy renderer can print `mesh_get_surface_count` during resource cleanup; inspect test results and exit status for failures.

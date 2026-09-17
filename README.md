# Slimebound — build 0.4

A Godot 4.3+ 3D co-op dungeon prototype. Two to six players can fuse into a shared creature; **Local Dungeon** runs two players on one keyboard with no IP address, network connection or server.

## Play the latest version

1. Download this repository's latest ZIP (Code → Download ZIP), or pull `main`.
2. Extract it into a fresh folder. Import its `project.godot` in Godot 4.3 or newer.
3. Let Godot finish importing the bundled GLB models and textures, then press **F6** on `scenes/main.tscn` or **F5** for the project.
4. Confirm the menu says **BUILD 0.4 · THE MOSS WARDEN · CC0 ASSETS**.
5. Click **PLAY LOCAL DUNGEON — NO IP REQUIRED**, above Host and Join.

If you still see an older build number, you are opening an older extracted copy. Run the project from the newly downloaded folder.

## Shared keyboard

| Action | Player 1 | Player 2 |
| --- | --- | --- |
| Move | WASD | Arrow keys |
| Aim | Mouse | Automatically toward closest enemy |
| Attack (fused only) | Left mouse / Space | M |
| Offer fusion | E | N |
| Split | Q | B |
| Absorb nearby power (solo only) | F | L |
| Restart run | R (host) | — |
| Return to menu | Escape | Escape |

Stand close and press **E and N within three seconds** to fuse. Every member must offer consent when merging larger groups. Both players steer the shared body: agreeing moves it at full speed; opposite inputs cancel. Either player may split. The local camera keeps both slimes visible and follows the shared body after fusion.

## The full level

- **The Nursery:** safe place to learn movement, collect powers, and fuse. Walk north together through the arch.
- **Root Gallery:** four pursuing enemies. Solo trails slow them; fuse to defeat them and unlock the north exit.
- **Crucible Hall:** six enemies, including tougher brutes. New power pedestals allow different combinations.
- **Moss Warden:** a 1,400-HP boss with delayed ground slams, radial projectile volleys, summoned crawlers, and a faster second phase below half health. Move out of the red warnings before they fire. Defeat it, fuse, and enter the Heart Gate to complete the level.

Each chamber is a checkpoint. If a slime is defeated, the party reforms at that chamber with its collected powers intact and the encounter resets. R starts a fresh run. Room transitions reform the party as solo slimes so you can change powers before the next fight.

## Solo and fusion rules

Solo slimes **cannot deal damage**, even with a power equipped. Moving leaves a seven-second trail that slows ordinary enemies by 55% and the boss by 30%. Solo slimes are faster and can absorb one power at a time; collecting another replaces it. Pedestals replenish after one second, so both players can choose the same element.

Fusion gives the team a larger body with arms and legs and enables close-range strikes. Collected powers also enable ranged attacks. Splitting keeps powers and the current health percentage; it does not heal you.

| Power selection | Fused effect |
| --- | --- |
| Ember | Added impact damage and burning |
| Frost | Added impact damage and slowing |
| Storm | Added impact damage and chain damage |
| Same element twice | Double that element's added damage; double burn/chain damage or frost duration |
| Ember + Frost | **Frostfire:** burning impact and slowing splash |
| Ember + Storm | **Plasma:** splash plus burning chain attacks |
| Frost + Storm | **Blizzard:** slowing chain attacks |
| All three (3+ online players) | **Tempest:** burn, frost, chain and splash |

Matching-power scaling applies to the elemental portion, not the underlying physical strike. Larger groups can stack additional copies. There is no friendly fire.

## Online play

Host opens UDP port **7777**; other players join the host's reachable IP. Across the internet the host may need port forwarding. There is no matchmaking or relay. Local Dungeon never opens a port. The host owns movement, collision, powers, enemies, boss attacks, checkpoints and victory; clients send inputs and receive authoritative snapshots.

## Public artwork only

Models and visual-effect textures are bundled CC0 assets by **Kenney** and **Quaternius**. See [ASSET_CREDITS.md](ASSET_CREDITS.md) for original links and license files. The fused form uses Quaternius's existing animated Yeti as a limbed creature stand-in; no custom slime artwork was made. The boss uses the existing Mushroom King. The previous procedural character/environment meshes and custom icon have been removed.

## Verification

Run from the project folder:

```sh
godot --headless --editor --import --quit
godot --headless --script res://tests/gameplay_test.gd
```

For the two-process networking check, start `godot --headless --script res://tests/network_test.gd -- --server`, then start `godot --headless --script res://tests/network_test.gd` in another terminal within one second.

This is a playable prototype, not a finished commercial game: four chambers, simple enemy pursuit, one boss, and no saved progression or audio yet. Difficulty and internet latency need real-player playtesting.

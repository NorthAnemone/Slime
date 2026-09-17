# Slimebound

Slimebound is a Godot 4 multiplayer dungeon-crawler prototype built around one unusual co-op mechanic: nearby players can consent to fuse into a single, stronger slime. Every player in the fusion shares the same body and camera perspective, and their movement inputs are combined, so steering the bigger slime requires cooperation.

## Play the prototype

1. Install **Godot 4.3 or newer**.
2. Import `project.godot` and run the project.
3. One player selects **Host Dungeon**.
4. Other players enter the host's IP address and select **Join Dungeon**.
5. Allow UDP port `7777` through the host's firewall/router when playing over the internet.

For a quick local test, run two editor instances and join `127.0.0.1` from the second window.

### Single-computer local co-op

Select the large **Play Local Dungeon — No IP Required** option above **Host Dungeon** and **Join Dungeon**. This runs both slimes in one Godot instance and does not open a server, require an IP address, or require a second copy of the game. The updated title screen is marked `BUILD 0.2 · LOCAL DUNGEON INCLUDED` so it is easy to distinguish from an older extracted copy.

| Player | Movement | Attack | Fuse | Split |
| --- | --- | --- | --- | --- |
| Player 1 | WASD | Mouse / Space | E | Q |
| Player 2 | Arrow keys | M (auto-aim) | N | B |

Both players must offer fusion while their slimes are close. Once fused, both movement vectors contribute to the same shared slime. The local camera frames both bodies while separated and converges on the shared body after fusion.

## Controls

| Input | Action |
| --- | --- |
| WASD / arrow keys | Move |
| Mouse | Aim |
| Left click / Space | Spit gel |
| E | Offer fusion; a nearby slime must also press E |
| Q | Split the current fusion |

## Included systems

- Godot ENet host/join multiplayer for up to six players
- Offline two-player keyboard co-op for rapid fusion testing
- Server-authoritative movement, combat, enemies, pickups, fusion, and floor progression
- Mutual-consent fusion between any two slime bodies
- Shared control: movement vectors from every fused player are combined
- Shared perspective: every member's camera follows the same fused body
- Fusion scaling for health, damage, projectile fire rate, body size, and speed
- Independent aiming and attacks for every player inside a fusion
- Forced split on defeat and voluntary split with `Q`
- Dungeon creatures, collectible cores, healing, heart gate, and escalating floors
- Entirely procedural primitive art, so there are no external asset dependencies
- Explicit `game_world.tscn` 3D scene with a current camera, lit dungeon floor, spawn dais, rune glow, environment, generated walls, and runtime actors

## Architecture

The host is the simulation authority. Clients send compact movement, aim, attack, fuse, and split inputs; the host simulates the shared dungeon and broadcasts snapshots. A fused body stores multiple peer IDs, while each player retains an independent input stream. This makes the fusion a real shared entity instead of attaching one player's avatar to another.

## Current prototype limitations

- Direct IP connection only; there is no relay, matchmaking, or NAT traversal yet.
- Sessions are not persistent.
- The dungeon layout is fixed while enemy positions and encounters vary.
- Controller and mobile input are not implemented yet.

## Good next milestones

1. Add Steam Networking or a relay-backed lobby system.
2. Give each fused player a distinct role, such as movement, shield, ranged attack, or special ability.
3. Replace the fixed layout with modular procedural rooms.
4. Add a boss designed around deliberately splitting and recombining.
5. Add proximity voice chat and persistent cosmetic unlocks.

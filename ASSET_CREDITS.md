# Public asset credits

All shipped model and effect artwork comes from the following publicly available **CC0 1.0** packs. No generated artwork, hand-built character meshes, or hand-built environment meshes are used. Godot draws the text and standard interface controls. Level layout, animation playback, model sizing, team/effect colours, and gameplay are implemented in code.

| Files | Creator / pack | Original source | Use |
| --- | --- | --- | --- |
| `assets/nature/` | Kenney — Nature Kit 1.0 | https://kenney.nl/assets/nature-kit | Grass surfaces, paths, pine trees, rocks, plants, flowers, campsite props |
| `assets/kenney/` | Kenney — Mini Dungeon 2.0 | https://kenney.nl/assets/mini-dungeon | Floors, walls, arches, gates, columns, banners, potion pickups |
| `assets/particles/` | Kenney — Particle Pack | https://kenney.nl/assets/particle-pack | Slime trails, targeting, spell shots, fusion offers, boss warning circles |
| `assets/quaternius/slime.glb` | Quaternius — Ultimate Monsters, Green Blob | https://poly.pizza/m/y4kJh8EeYS | Solo slime |
| `assets/quaternius/fusion.glb` | Quaternius — Slime | https://poly.pizza/m/LyjSUKHKnh | Animated green slime with small arms, enlarged for fusion |
| `assets/quaternius/crawler.glb` | Quaternius — Ultimate Monsters, Mushnub | https://poly.pizza/m/LWKmS30Xxl | Crawlers |
| `assets/quaternius/warden.glb` | Quaternius — Ultimate Monsters, Mushroom King | https://poly.pizza/m/grnFTziU8u | Brutes and Moss Warden |

Quaternius pack source and license: https://quaternius.com/packs/ultimatemonsters.html

Kenney's original license files are included in each corresponding folder. Quaternius models have individual source records, and the complete CC0 legal text is included at `assets/quaternius/CC0-1.0.txt`.

The fused form uses Quaternius’s CC0 Slime with its existing small arms and idle/walk/attack animations. The original model is uniformly enlarged in-engine; no new character artwork was created.

Build 0.5 uses in-engine palette, roughness and metallic adjustments on these existing models. The landscape is assembled by placing/scaling/rotating the supplied grass, path, rock and tree models. No new artwork meshes or textures were made. The sky, lighting, fog, UI and invisible collision shapes use standard Godot engine facilities. Nature Kit's original license is included in `assets/nature/License.txt`.

Build 0.8 Amber Ruins reuses the bundled Kenney ground, path, cliff, rock, column, arch and campsite models with in-engine sand/stone palette changes. Elemental trails reuse Kenney smoke artwork tinted by equipped elements. No new artwork was created.

Build 0.9 adds these unmodified, animated CC0 1.0 assets by Quaternius:

| File | Model and source | Use |
| --- | --- | --- |
| `assets/quaternius/skeleton.glb` | [Skeleton](https://poly.pizza/m/wODZYCgX5Z) | Ranged enemy |
| `assets/quaternius/bat.glb` | [Bat](https://poly.pizza/m/hNO9XvjlKa) | Low-hovering dash enemy |

Individual source/download records are included beside both models. Traversal uses existing Kenney cliff models; transform effects animate the existing slime models and circle sprites. Opaque projectiles reuse Kenney’s rock_largeA mesh with an opaque unshaded material, plus existing smoke sprites with alpha discard. No new projectile artwork was created.

# Third-party assets / 第三方资产

## Male City Zombie, Ready for use in Game Engines

- Author / 作者: **Rikindle3D**
- Source: https://opengameart.org/content/male-city-zombie-ready-for-use-in-game-engines
- Download: https://opengameart.org/sites/default/files/Male%20City%20Zombie.7z
- License: **CC0 1.0 Universal** — https://creativecommons.org/publicdomain/zero/1.0/
- Includes: textured human zombie, rig, walking variants, run, attacks, idle, hurt, death, scream.
- Used as: `assets/models/city_zombie.glb`.
- Changes: polygon reduction, material/texture restoration, FK animation retargeting, in-place animation, GLB conversion; runtime body proportions, outfit tint and attached gear vary.

## 3D Horror Game Monster

- Author / 作者: **City Building Game Art / HorrorGameMaker.com**
- Source: https://opengameart.org/content/3d-horror-game-monster
- Download: https://opengameart.org/sites/default/files/Poses.zip
- License: **CC0 1.0 Universal** — https://creativecommons.org/publicdomain/zero/1.0/
- Includes: textured anatomical horror creature, rig, walk and run motions.
- Used as: `assets/models/horror_mutant.glb`.
- Changes: authoring-control removal, packed albedo and normal maps resized to 2048px maximum, in-place skeletal clips, shortened walk segment for melee motion, GLB conversion; runtime body proportions, infection growths and coloration vary.

## Soldier (rigged) / 幸存者士兵

- Author / 作者: **Grab3D**
- Source: https://grab3d.com/models/characters/soldier/
- Download: https://grab3d.com/dl/soldier-rigged/soldier-rigged.glb
- License: **CC0 1.0 Universal** — https://grab3d.com/license/
- Original SHA256: `b1f32017868a6f951c21c45b84646696431e6b4c813d563af37944123f673a59`
- Includes: independent humanoid skeleton, camouflage clothing, tactical vest, helmet, boots, albedo/normal textures, walk and run clips.
- Used as: `assets/models/survivor_soldier.glb`, LAN player / teammate third-person appearance.
- Changes: reduced from 278,969 to 27,896 triangles, textures limited to 2048px, added standing idle from a walk pose, GLB conversion with original skeleton and animations preserved.
- Reproduction: `python3 tools/fetch_survivor.py`, then isolated Blender `--background --factory-startup --python tools/convert_survivor.py`.
- Source reports AI-assisted model creation followed by Blender cleanup: https://grab3d.com/how-we-make-models/

## Godot Engine

- Version: **4.7 stable**
- License: **MIT**
- License and third-party notices: https://godotengine.org/license/
- Official Windows release export template from:
  https://github.com/godotengine/godot-builds/releases/tag/4.7-stable

## Rust binding library

- `godot` / gdext **0.5.5**
- License: **MPL-2.0**
- Source: https://github.com/godot-rust/gdext
- Source modifications to gdext: none. Game extension source: `rust/src/` in the supplied project.
